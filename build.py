import argparse
import gzip
import hashlib
import io
import plistlib
import re
import shutil
import struct
import subprocess
import tarfile
from pathlib import Path


BUNDLE_ID = "com.360buy.jdmobile"
PACKAGE = "com.solhk.jdx"
VERSION = "0.1"
NAME = "JDX"
ARCH = "iphoneos-arm64"
MIN_IOS = "15.0"
SDK_VERSION = "16.5"
INSTALL_DIR = "./var/jb/Library/MobileSubstrate/DynamicLibraries"
DEFAULT_LLVM = Path(r"C:\Program Files\LLVM\bin")


def require(condition, message):
    if not condition:
        raise SystemExit(message)


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


def verify_dylib(llvm, dylib):
    data = dylib.read_bytes()
    require(struct.unpack_from("<IIII", data) == (0xFEEDFACF, 0x0100000C, 0, 6),
            "Expected a thin ARM64 Mach-O dynamic library")
    headers = llvm("llvm-objdump", "--macho", "--private-headers", dylib).decode()
    expected_headers = ("platform ios", f"minos {MIN_IOS}", f"sdk {SDK_VERSION}")
    require(all(value in {line.strip() for line in headers.splitlines()} for value in expected_headers)
            and f"name @rpath/{dylib.name} " in headers, "Unexpected Mach-O build identity")

    dependencies = llvm("llvm-objdump", "--macho", "--dylibs-used", dylib).decode().splitlines()[1:]
    libraries = [line.strip().split(" (", 1)[0] for line in dependencies]
    expected_libraries = {
        "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation",
        "/System/Library/Frameworks/Foundation.framework/Foundation",
        "/System/Library/Frameworks/UIKit.framework/UIKit",
        "/usr/lib/libobjc.A.dylib",
        "/usr/lib/libSystem.B.dylib",
    }
    require(libraries[0] == f"@rpath/{dylib.name}" and set(libraries[1:]) == expected_libraries,
            "Found an unexpected external dependency")

    signature = re.search(r"\bcmd LC_CODE_SIGNATURE\s+cmdsize 16\s+dataoff (\d+)\s+datasize (\d+)", headers)
    require(signature, "Missing embedded Mach-O signature")
    offset, size = map(int, signature.groups())
    magic, length, count, slot, relative_offset = struct.unpack_from(">5I", data, offset)
    require((magic, length, count, slot) == (0xFADE0CC0, size, 1, 0) and offset + size == len(data),
            "Invalid embedded signature envelope")
    directory = offset + relative_offset
    magic, length, _, flags, hashes, _, special_slots, pages, limit, hash_size, algorithm, _, page_power = (
        struct.unpack_from(">9I4B", data, directory)
    )
    require(magic == 0xFADE0C02 and flags & 0x2 and special_slots == 0 and limit == offset
            and (hash_size, algorithm, page_power) == (32, 2, 12), "Unexpected ad-hoc CodeDirectory")
    expected = b"".join(hashlib.sha256(data[start:min(start + 4096, offset)]).digest()
                        for start in range(0, offset, 4096))
    require(hashes + pages * hash_size <= length
            and data[directory + hashes:directory + hashes + pages * hash_size] == expected,
            "CodeDirectory page hashes do not match")
    return data


def build_package(llvm, build_dir, library):
    control = (
        f"Package: {PACKAGE}\n"
        f"Name: {NAME}\n"
        f"Version: {VERSION}\n"
        f"Architecture: {ARCH}\n"
        "Description: Hide selected ads in the JD iOS app.\n"
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

    (build_dir / "debian-binary").write_bytes(b"2.0\n")
    package = build_dir / f"{PACKAGE}_{VERSION}_{ARCH}.deb"
    package.unlink(missing_ok=True)
    members = ["debian-binary", *archives]
    llvm("llvm-ar", "--format=gnu", "rcD", package, *members)
    require(llvm("llvm-ar", "t", package).decode().splitlines() == members
            and llvm("llvm-ar", "p", package, "debian-binary") == b"2.0\n", "Invalid Debian package envelope")
    for name, files in archives.items():
        data = llvm("llvm-ar", "p", package, name)
        with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
            entries = archive.getmembers()
            require(all(entry.isfile() or entry.isdir() for entry in entries), f"Unexpected entry in {name}")
            installed = [entry.name for entry in entries if entry.isdir() and entry.mode == 0o755]
            require(installed == (directories if name == "data.tar.gz" else []), f"Unexpected directories in {name}")
            contents = {entry.name: (archive.extractfile(entry).read(), entry.mode)
                        for entry in entries if entry.isfile()}
            require(contents == files, f"Unexpected files in {name}")
    return package


def main():
    parser = argparse.ArgumentParser(description="Compile, package, and verify JDX.")
    parser.add_argument("--source", type=Path, default=Path(__file__).with_name("Tweak.m"))
    parser.add_argument("--build-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--llvm-dir", type=Path, default=DEFAULT_LLVM)
    parser.add_argument("--sdk", type=Path, required=True)
    args = parser.parse_args()
    source = args.source.resolve()
    build = args.build_dir.resolve()
    output = args.output.resolve()
    sdk = args.sdk.resolve()
    tools = args.llvm_dir.resolve()
    build.mkdir(parents=True, exist_ok=True)

    def llvm(tool, *arguments):
        return subprocess.run([str(tools / f"{tool}.exe"), *map(str, arguments)], cwd=build,
                              check=True, stdout=subprocess.PIPE).stdout

    obj = build / "Tweak.o"
    dylib = build / f"{NAME}.dylib"
    llvm("clang", "-target", f"arm64-apple-ios{MIN_IOS}", "-isysroot", sdk, "-fobjc-arc",
         "-Wall", "-Wextra", "-Werror", "-Oz", "-c", source, "-o", obj)
    llvm("ld64.lld", "-dylib", "-arch", "arm64", "-platform_version", "ios", MIN_IOS, SDK_VERSION,
         "-syslibroot", sdk, "-install_name", f"@rpath/{dylib.name}", "-adhoc_codesign", "-framework", "Foundation",
         "-framework", "UIKit", "-lobjc", "-lSystem", obj, "-o", dylib)
    package = build_package(llvm, build, verify_dylib(llvm, dylib))

    output.mkdir(parents=True, exist_ok=True)
    for artifact in (dylib, package):
        destination = output / artifact.name
        if artifact != destination:
            shutil.copyfile(artifact, destination)
        print(f"{hashlib.sha256(destination.read_bytes()).hexdigest()}  {destination}")
    print("Verified arm64 iOS Mach-O identity, ad-hoc signature hashes, system dependencies, and rootless package payload.")


if __name__ == "__main__":
    main()
