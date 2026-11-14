"""Exercise the real startup guard with isolated executable app fixtures."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


@unittest.skipUnless(shutil.which("bash"), "The macOS startup guard requires bash")
class StartupSmokeTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="crisp-startup-guard-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.guard = self.root / "macos_startup_smoke.sh"
        shutil.copy2(Path(__file__).with_name(self.guard.name), self.guard)
        diagnostics = self.root / "macos_startup_diagnostics.sh"
        diagnostics.write_text("#!/bin/bash\necho 'fixture diagnostics'\n")
        self.app = self.root / "Fixture.app"
        self.executable = self.app / "Contents/MacOS/CrispCloud"
        self.executable.parent.mkdir(parents=True)
        self.pid_file = self.root / "pid"

    def run_guard(self, lines, exit_code=None):
        # Lines are fixed test data, passed as printf arguments without shell
        # interpolation. The fixture execs sleep, so cleanup owns its whole PID.
        import shlex
        script = ["#!/bin/bash", f"echo $$ > {shlex.quote(str(self.pid_file))}"]
        script.extend("printf '%s\\n' " + shlex.quote(line) for line in lines)
        script.append("exec sleep 30" if exit_code is None else f"exit {exit_code}")
        self.executable.write_text("\n".join(script) + "\n")
        self.executable.chmod(0o755)
        result = subprocess.run(
            ["bash", str(self.guard), str(self.app), "1", str(self.root / "startup.log")],
            capture_output=True, text=True, timeout=10,
        )
        pid = int(self.pid_file.read_text())
        with self.assertRaises(ProcessLookupError):
            os.kill(pid, 0)
        return result

    def test_ready_live_app_passes_and_is_cleaned_up(self):
        result = self.run_guard(["[Main] Credential policy ready"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("remained healthy", result.stdout)

    def test_texture_failures_reject_a_live_credential_ready_app(self):
        for message in (
            "Impeller validation: The texture and its descriptor disagree about its size.",
            "Impeller validation: Store action needs resolve but no valid resolve texture specified.",
        ):
            with self.subTest(message=message):
                result = self.run_guard(["[Main] Credential policy ready", message])
                self.assertEqual(result.returncode, 1)
                self.assertIn("fatal startup signature", result.stderr)
                self.assertIn(message, result.stderr)

    def test_alive_without_credential_preflight_cannot_pass(self):
        result = self.run_guard(["[Main] Application shell rendered"])
        self.assertEqual(result.returncode, 1)
        self.assertIn("did not complete credential preflight", result.stderr)

    def test_early_process_failure_cannot_pass(self):
        result = self.run_guard(["[Main] Credential policy ready"], exit_code=17)
        self.assertEqual(result.returncode, 1)
        self.assertIn("exited during startup (status 17)", result.stderr)


if __name__ == "__main__":
    unittest.main()
