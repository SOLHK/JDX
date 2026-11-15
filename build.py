"""Build JDX with LLVM on Linux/Windows or Xcode on macOS.

The only third-party build inputs are the compiler/linker and an iPhoneOS SDK.
Packaging and Mach-O/signature verification use Python's standard library.
"""
import argparse
import gzip
import hashlib
import io
import json
import plistlib
import re
import shutil
import struct
import subprocess
import sys
import tarfile
from pathlib import Path


BUNDLE_ID = "com.360buy.jdmobile"
PACKAGE = "com.solhk.jdx"
VERSION = "0.3.0"
NAME = "JDX"
ARCH = "iphoneos-arm64"
MIN_IOS = "15.0"
INSTALL_DIR = "./var/jb/Library/MobileSubstrate/DynamicLibraries"
SYSTEM_LIBRARIES = {
    "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation",
    "/System/Library/Frameworks/Foundation.framework/Foundation",
    "/System/Library/Frameworks/UIKit.framework/UIKit",
    "/System/Library/Frameworks/Network.framework/Network",
    "/usr/lib/libobjc.A.dylib",
    "/usr/lib/libSystem.B.dylib",
}


def require(condition, message):
    if not condition:
        raise SystemExit(message)


def packed_version(version):
    require(bool(re.fullmatch(r"\d+\.\d+(?:\.\d+)?", version)), f"Invalid version: {version}")
    parts = [int(value) for value in version.split(".")]
    parts += [0] * (3 - len(parts))
    require(parts[0] <= 65535 and all(value <= 255 for value in parts[1:]), "Version component overflow")
    return (parts[0] << 16) | (parts[1] << 8) | parts[2]


def sdk_version(sdk, override=None):
    if override:
        packed_version(override)
        return override
    for name in ("SDKSettings.json", "SDKSettings.plist"):
        settings = sdk / name
        if settings.is_file():
            metadata = json.loads(settings.read_text(encoding="utf-8")) if name.endswith("json") else plistlib.loads(settings.read_bytes())
            version = metadata.get("Version")
            if version:
                packed_version(str(version))
                return str(version)
    match = re.fullmatch(r"iPhoneOS(\d+\.\d+(?:\.\d+)?)\.sdk", sdk.name)
    require(match, "Cannot determine the iPhoneOS SDK version; pass --sdk-version")
    return match.group(1)


def write_archive(path, files, directories=()):
    with path.open("wb") as target, gzip.GzipFile(filename="", mode="wb", fileobj=target, mtime=0) as compressed:
        with tarfile.open(fileobj=compressed, mode="w", format=tarfile.USTAR_FORMAT) as archive:
            for name in directories:
                entry = tarfile.TarInfo(name)
                entry.type = tarfile.DIRTYPE
                entry.mode = 0o755
                entry.uname = entry.gname = "root"
                archive.addfile(entry)
            for name, (data, mode) in files.items():
                entry = tarfile.TarInfo(name)
                entry.mode = mode
                entry.size = len(data)
                entry.uname = entry.gname = "root"
                archive.addfile(entry, io.BytesIO(data))


def write_ar(path, members):
    # Debian's required members have short ASCII names; GNU extensions are unnecessary.
    with path.open("wb") as target:
        target.write(b"!<arch>\n")
        for name, data in members.items():
            require(len(name) <= 15 and "/" not in name, "Unsupported ar member name")
            header = f"{name + '/':<16}{0:<12}{0:<6}{0:<6}{'100644':<8}{len(data):<10}`\n"
            require(len(header) == 60, "Invalid ar header size")
            target.write(header.encode("ascii"))
            target.write(data)
            if len(data) % 2:
                target.write(b"\n")


def read_ar(data):
    require(data.startswith(b"!<arch>\n"), "Invalid Debian ar envelope")
    members = {}
    offset = 8
    while offset < len(data):
        header = data[offset:offset + 60]
        require(len(header) == 60 and header[-2:] == b"`\n", "Invalid ar member header")
        name = header[:16].decode("ascii").strip().removesuffix("/")
        require(name not in members, "Duplicate ar member")
        size = int(header[48:58])
        offset += 60
        require(size >= 0 and offset + size <= len(data), "Truncated ar member")
        members[name] = data[offset:offset + size]
        offset += size
        if size % 2:
            require(data[offset:offset + 1] == b"\n", "Invalid ar padding")
            offset += 1
    require(offset == len(data), "Trailing ar data")
    return members


def verify_signature(data, offset, size):
    require(offset > 0 and size >= 20 and offset + size == len(data), "Invalid signature range")
    magic, length, count = struct.unpack_from(">3I", data, offset)
    require(magic == 0xFADE0CC0 and 12 + 8 * count <= length <= size, "Invalid signature envelope")
    require(not any(data[offset + length:offset + size]), "Nonzero signature padding")
    code_directory = None
    for index in range(count):
        slot, relative = struct.unpack_from(">2I", data, offset + 12 + 8 * index)
        require(12 + 8 * count <= relative <= length - 8, "Invalid signature blob offset")
        blob_magic, blob_length = struct.unpack_from(">2I", data, offset + relative)
        require(8 <= blob_length <= length - relative, "Invalid signature blob length")
        if slot == 0:
            require(code_directory is None and blob_magic == 0xFADE0C02, "Invalid CodeDirectory slot")
            code_directory = data[offset + relative:offset + relative + blob_length]
    require(code_directory and len(code_directory) >= 44, "Missing CodeDirectory")
    _, length, _, flags, hashes, _, special_slots, pages, limit, hash_size, algorithm, _, page_power = (
        struct.unpack_from(">9I4B", code_directory)
    )
    require(flags & 0x2 and limit == offset and (hash_size, algorithm, page_power) == (32, 2, 12),
            "Expected an ad-hoc SHA-256 signature with 4096-byte pages")
    require(pages == (offset + 4095) // 4096 and hashes >= 44 + special_slots * hash_size
            and hashes + pages * hash_size <= length, "Invalid CodeDirectory hash table")
    expected = b"".join(hashlib.sha256(data[start:min(start + 4096, offset)]).digest()
                        for start in range(0, offset, 4096))
    require(code_directory[hashes:hashes + len(expected)] == expected, "CodeDirectory page hashes do not match")


def verify_dylib(dylib, sdk):
    data = dylib.read_bytes()
    require(len(data) >= 32, "Truncated Mach-O header")
    magic, cpu, subtype, file_type, commands, command_size, _, _ = struct.unpack_from("<8I", data)
    require((magic, cpu, subtype, file_type) == (0xFEEDFACF, 0x0100000C, 0, 6),
            "Expected a thin ARM64 Mach-O dynamic library")
    require(32 + command_size <= len(data) and commands <= command_size // 8, "Invalid Mach-O load command range")
    offset = 32
    identity = None
    build_version = None
    signature = None
    libraries = set()
    dylib_commands = {0xC, 0x18 | 0x80000000, 0x1F | 0x80000000, 0x23 | 0x80000000}
    for _ in range(commands):
        require(offset + 8 <= 32 + command_size, "Truncated Mach-O command")
        command, size = struct.unpack_from("<2I", data, offset)
        require(size >= 8 and size % 8 == 0 and offset + size <= 32 + command_size, "Invalid Mach-O command size")
        if command == 0xD or command in dylib_commands:
            require(size >= 24, "Truncated dylib command")
            name_offset = struct.unpack_from("<I", data, offset + 8)[0]
            require(24 <= name_offset < size, "Invalid dylib name offset")
            raw_name = data[offset + name_offset:offset + size]
            require(b"\0" in raw_name, "Unterminated dylib name")
            name = raw_name.split(b"\0", 1)[0].decode("utf-8")
            if command == 0xD:
                require(identity is None, "Duplicate Mach-O identity")
                identity = name
            else:
                libraries.add(name)
        elif command == 0x32:
            require(size >= 24 and build_version is None, "Invalid build version command")
            build_version = struct.unpack_from("<3I", data, offset + 8)
        elif command == 0x1D:
            require(size == 16 and signature is None, "Invalid code signature command")
            signature = struct.unpack_from("<2I", data, offset + 8)
        offset += size
    require(offset == 32 + command_size, "Incorrect Mach-O command count")
    require(identity == f"@rpath/{NAME}.dylib", "Unexpected Mach-O install name")
    require(build_version == (2, packed_version(MIN_IOS), packed_version(sdk)), "Unexpected Mach-O platform, minimum OS, or SDK")
    required_libraries = SYSTEM_LIBRARIES - {"/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"}
    require(required_libraries <= libraries <= SYSTEM_LIBRARIES, f"Unexpected dynamic libraries: {sorted(libraries)}")
    require(signature, "Missing embedded Mach-O signature")
    verify_signature(data, *signature)
    return data


def build_package(build_dir, library):
    control = (
        f"Package: {PACKAGE}\n"
        f"Name: {NAME}\n"
        f"Version: {VERSION}\n"
        f"Architecture: {ARCH}\n"
        "Description: Configurable JD ad filtering and local diagnostics.\n"
        "Maintainer: JDX\n"
        "Section: Tweaks\n"
        "Conflicts: com.solhk.jd-adblock\n"
        f"Depends: mobilesubstrate, firmware (>= {MIN_IOS})\n"
    ).encode()
    plist = plistlib.dumps({"Filter": {"Bundles": [BUNDLE_ID]}})
    archives = {
        "control.tar.gz": {"./control": (control, 0o644)},
        "data.tar.gz": {
            f"{INSTALL_DIR}/{NAME}.dylib": (library, 0o755),
            f"{INSTALL_DIR}/{NAME}.plist": (plist, 0o644),
        },
    }
    segments = INSTALL_DIR.split("/")
    directories = ["/".join(segments[:end]) for end in range(2, len(segments) + 1)]
    for name, files in archives.items():
        write_archive(build_dir / name, files, directories if name == "data.tar.gz" else ())
    members = {"debian-binary": b"2.0\n", **{name: (build_dir / name).read_bytes() for name in archives}}
    package = build_dir / f"{PACKAGE}_{VERSION}_{ARCH}.deb"
    write_ar(package, members)
    installed_members = read_ar(package.read_bytes())
    require(list(installed_members) == list(members) and installed_members == members, "Invalid Debian package envelope")
    for name, files in archives.items():
        with tarfile.open(fileobj=io.BytesIO(installed_members[name]), mode="r:gz") as archive:
            entries = archive.getmembers()
            require(all(entry.isfile() or entry.isdir() for entry in entries), f"Unexpected entry in {name}")
            installed = [entry.name for entry in entries if entry.isdir() and entry.mode == 0o755]
            require(installed == (directories if name == "data.tar.gz" else []), f"Unexpected directories in {name}")
            require(all(entry.uid == entry.gid == 0 for entry in entries), "Unexpected package ownership")
            contents = {entry.name: (archive.extractfile(entry).read(), entry.mode)
                        for entry in entries if entry.isfile()}
            require(contents == files, f"Unexpected files in {name}")
    return package


def run(*arguments, cwd=None):
    return subprocess.run(list(map(str, arguments)), cwd=cwd, check=True, stdout=subprocess.PIPE).stdout


def find_tool(name, tool_dir=None):
    if tool_dir:
        for suffix in ("", ".exe"):
            candidate = tool_dir / (name + suffix)
            if candidate.is_file():
                # lld chooses its driver from argv[0]; resolving ld64.lld's symlink
                # into lld would accidentally select the generic driver.
                return str(candidate.absolute())
        raise SystemExit(f"Cannot find {name} in {tool_dir}")
    result = shutil.which(name)
    require(result, f"Cannot find {name}; install LLVM and lld, or pass --llvm-dir")
    return str(Path(result).absolute())


def source_hashes(source):
    return {str(path.relative_to(source.parent)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted(source.parent.glob("*")) if path.suffix in (".m", ".h")}


def main():
    parser = argparse.ArgumentParser(description="Compile, package, and verify JDX (Python 3.9+).")
    parser.add_argument("--source", type=Path, default=Path(__file__).with_name("Tweak.m"))
    parser.add_argument("--build-dir", type=Path, default=Path("build"))
    parser.add_argument("--output", type=Path, default=Path("dist"))
    parser.add_argument("--llvm-dir", type=Path, help="Directory containing clang and ld64.lld (optional if on PATH)")
    parser.add_argument("--sdk", type=Path, help="iPhoneOS SDK (auto-detected with xcrun on macOS)")
    parser.add_argument("--sdk-version", help="Override SDK version if SDKSettings is unavailable")
    parser.add_argument("--toolchain", choices=("auto", "llvm", "xcode"), default="auto")
    args = parser.parse_args()
    source = args.source.resolve()
    build = args.build_dir.resolve()
    output = args.output.resolve()
    require(source.is_file(), f"Source does not exist: {source}")
    xcode = args.toolchain == "xcode" or (args.toolchain == "auto" and sys.platform == "darwin" and not args.llvm_dir)
    require(not xcode or sys.platform == "darwin", "The Xcode toolchain requires macOS")
    if args.sdk:
        sdk = args.sdk.resolve()
    else:
        require(xcode, "Pass --sdk with the path to an iPhoneOS SDK")
        sdk = Path(run("xcrun", "--sdk", "iphoneos", "--show-sdk-path").decode().strip())
    require((sdk / "System/Library/Frameworks/UIKit.framework").is_dir(), "SDK must be for iPhoneOS and contain UIKit")
    sdk_release = sdk_version(sdk, args.sdk_version)
    require(packed_version(sdk_release) >= packed_version(MIN_IOS), "SDK is older than the minimum supported iOS")
    build.mkdir(parents=True, exist_ok=True)
    compiler = run("xcrun", "--sdk", "iphoneos", "--find", "clang").decode().strip() if xcode else find_tool("clang", args.llvm_dir)
    compiler_version = run(compiler, "--version").decode().splitlines()[0]
    print(f"Compiler: {compiler_version}\nSDK: iPhoneOS {sdk_release}\nJDX: {VERSION}", flush=True)
    compiled_sources = source_hashes(source)
    obj = build / "Tweak.o"
    dylib = build / f"{NAME}.dylib"
    common = ["-target", f"arm64-apple-ios{MIN_IOS}", "-isysroot", sdk]
    run(compiler, *common, "-fobjc-arc", "-fblocks", "-fobjc-exceptions", "-Wall", "-Wextra", "-Werror",
        "-Werror=unguarded-availability", "-Oz", f'-DJDX_BUILD_VERSION="{VERSION}"', "-I", source.parent,
        "-c", source, "-o", obj, cwd=build)
    frameworks = ["-framework", "Foundation", "-framework", "UIKit", "-framework", "CoreFoundation",
                  "-framework", "Network", "-lobjc", "-lSystem"]
    if xcode:
        run(compiler, *common, "-dynamiclib", f"-Wl,-install_name,@rpath/{dylib.name}", "-Wl,-adhoc_codesign",
            f"-Wl,-platform_version,ios,{MIN_IOS},{sdk_release}", *frameworks, obj, "-o", dylib, cwd=build)
    else:
        linker = find_tool("ld64.lld", args.llvm_dir)
        run(linker, "-dylib", "-arch", "arm64", "-platform_version", "ios", MIN_IOS, sdk_release,
            "-syslibroot", sdk, "-install_name", f"@rpath/{dylib.name}", "-adhoc_codesign",
            *frameworks, obj, "-o", dylib, cwd=build)
    package = build_package(build, verify_dylib(dylib, sdk_release))
    require(source_hashes(source) == compiled_sources, "Sources changed during compilation; rebuild before distributing")
    output.mkdir(parents=True, exist_ok=True)
    hashes = {}
    for artifact in (dylib, package):
        destination = output / artifact.name
        if artifact != destination:
            shutil.copyfile(artifact, destination)
        hashes[artifact.name] = hashlib.sha256(destination.read_bytes()).hexdigest()
    (output / "SHA256SUMS").write_text("".join(f"{digest}  {name}\n" for name, digest in hashes.items()), encoding="utf-8")
    manifest = {"name": NAME, "version": VERSION, "architecture": "arm64", "minimum_ios": MIN_IOS,
                "sdk_version": sdk_release, "compiler": compiler_version, "sources": compiled_sources,
                "artifacts": hashes, "device_validation": "pending"}
    (output / "build-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    for name, digest in hashes.items():
        print(f"{digest}  {output / name}")
    print("Verified arm64 iOS Mach-O identity, ad-hoc signature hashes, system dependencies, and rootless package payload.")


if __name__ == "__main__":
    main()
