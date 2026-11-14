"""Compile and execute the production hook installer with a small ObjC runtime.

These tests exercise method ownership, live dispatch and original IMP chaining;
they do not infer behavior from source-text patterns. Run from any directory with
`python3 tests/test_hook_runtime.py`. A C compiler (cc, clang or gcc) is required.
"""

import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests" / "fixtures"


class HookRuntimeTest(unittest.TestCase):
    def test_compiled_runtime_regressions(self):
        compiler = shlex.split(os.environ.get("CC", ""))
        if not compiler:
            available = next((shutil.which(name) for name in ("cc", "clang", "gcc")
                              if shutil.which(name)), None)
            self.assertIsNotNone(available, "Install a C compiler or set CC to run runtime regressions")
            compiler = [available]
        with tempfile.TemporaryDirectory(prefix="jdx-hook-runtime-") as directory:
            executable = Path(directory) / ("hook-runtime.exe" if os.name == "nt" else "hook-runtime")
            compiled = subprocess.run(
                [*compiler, "-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic", "-O2",
                 "-I", str(FIXTURES), "-I", str(ROOT), str(FIXTURES / "hook_runtime.c"),
                 "-o", str(executable)],
                capture_output=True, text=True, timeout=60,
            )
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            executed = subprocess.run([str(executable)], capture_output=True, text=True, timeout=15)
            self.assertEqual(executed.returncode, 0, executed.stdout + executed.stderr)
            self.assertIn("9 compiled hook-runtime regression scenarios", executed.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
