"""Regression checks for release integrity; no compiler/SDK is required."""
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import struct
import tarfile
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("jdx_build", Path(__file__).resolve().parents[1] / "build.py")
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)


class BuildIntegrityTests(unittest.TestCase):
    @unittest.skipIf(os.name == "nt", "Creating test symlinks may require Windows privileges")
    def test_linker_driver_keeps_symlink_name(self):
        # lld selects Mach-O mode from argv[0], so realpath would break this.
        with tempfile.TemporaryDirectory() as directory:
            tools = Path(directory)
            (tools / "lld").write_text("fixture")
            (tools / "ld64.lld").symlink_to("lld")
            self.assertEqual(Path(build.find_tool("ld64.lld", tools)).name, "ld64.lld")

    def test_sdk_metadata_wins_over_directory_name(self):
        # Some published SDK folders are named 16.5 but declare 16.4 internally.
        with tempfile.TemporaryDirectory() as directory:
            sdk = Path(directory) / "iPhoneOS16.5.sdk"
            sdk.mkdir()
            (sdk / "SDKSettings.json").write_text(json.dumps({"Version": "16.4"}))
            self.assertEqual(build.sdk_version(sdk), "16.4")

    def test_sdk_plist_and_missing_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            sdk = Path(directory)
            (sdk / "SDKSettings.plist").write_bytes(plistlib.dumps({"Version": "18.2"}))
            self.assertEqual(build.sdk_version(sdk), "18.2")
            (sdk / "SDKSettings.plist").unlink()
            with self.assertRaisesRegex(SystemExit, "Cannot determine"):
                build.sdk_version(sdk)

    def test_package_contents_and_repeatability(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory)
            payload = b"arm64 fixture\x00binary\xff"
            package = build.build_package(target, payload)
            first = package.read_bytes()
            self.assertEqual(build.build_package(target, payload).read_bytes(), first)
            members = build.read_ar(first)
            self.assertEqual(list(members), ["debian-binary", "control.tar.gz", "data.tar.gz"])
            self.assertEqual(members["debian-binary"], b"2.0\n")
            with tarfile.open(fileobj=io.BytesIO(members["data.tar.gz"]), mode="r:gz") as archive:
                self.assertEqual(archive.extractfile(f"{build.INSTALL_DIR}/JDX.dylib").read(), payload)
                plist = plistlib.loads(archive.extractfile(f"{build.INSTALL_DIR}/JDX.plist").read())
                self.assertEqual(plist, {"Filter": {"Bundles": ["com.360buy.jdmobile"]}})
            with tarfile.open(fileobj=io.BytesIO(members["control.tar.gz"]), mode="r:gz") as archive:
                control = archive.extractfile("./control").read().decode()
                self.assertIn("Version: 0.3.0\n", control)
                self.assertIn("Architecture: iphoneos-arm64\n", control)

    def test_ar_rejects_truncation_and_invalid_padding(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fixture.ar"
            build.write_ar(path, {"small": b"123"})
            valid = path.read_bytes()
            self.assertEqual(build.read_ar(valid), {"small": b"123"})
            for malformed in (valid[:-2], valid[:-1] + b"X", b"nope"):
                with self.assertRaises(SystemExit):
                    build.read_ar(malformed)

    @staticmethod
    def signed_page_fixture():
        # One signed 4 KiB page followed by Apple's minimal ad-hoc superblob.
        code = b"sample executable bytes".ljust(4096, b"\x00")
        directory = struct.pack(">9I4B", 0xFADE0C02, 76, 0x20001, 2, 44, 0, 0, 1, len(code), 32, 2, 0, 12)
        directory += struct.pack(">I", 0) + hashlib.sha256(code).digest()
        signature = struct.pack(">5I", 0xFADE0CC0, len(directory) + 20, 1, 0, 20) + directory
        return code + signature, len(code), len(signature)

    def test_signature_detects_changed_executable_page(self):
        data, offset, size = self.signed_page_fixture()
        build.verify_signature(data, offset, size)
        damaged = bytearray(data)
        damaged[105] ^= 0x80
        with self.assertRaisesRegex(SystemExit, "page hashes do not match"):
            build.verify_signature(damaged, offset, size)

    def test_signature_rejects_missing_code_slots(self):
        data, offset, size = self.signed_page_fixture()
        damaged = bytearray(data)
        struct.pack_into(">I", damaged, offset + 20 + 28, 0)
        with self.assertRaisesRegex(SystemExit, "hash table"):
            build.verify_signature(damaged, offset, size)

    def test_signature_rejects_out_of_bounds_blob(self):
        data, offset, size = self.signed_page_fixture()
        damaged = bytearray(data)
        struct.pack_into(">I", damaged, offset + 16, 0xFFFFFFF0)
        with self.assertRaisesRegex(SystemExit, "blob offset"):
            build.verify_signature(damaged, offset, size)

    def test_macho_rejects_non_ios_and_truncated_input(self):
        with tempfile.TemporaryDirectory() as directory:
            dylib = Path(directory) / "JDX.dylib"
            for invalid in (b"", b"not a dylib".ljust(32, b"\x00"), struct.pack("<8I", 0xFEEDFACF, 0x0100000C, 0, 6, 1, 16, 0, 0)):
                dylib.write_bytes(invalid)
                with self.assertRaises(SystemExit):
                    build.verify_dylib(dylib, "16.4")


if __name__ == "__main__":
    unittest.main()
