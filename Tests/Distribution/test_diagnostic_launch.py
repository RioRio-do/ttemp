import importlib.util
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/diagnostic-launch.py"
spec = importlib.util.spec_from_file_location("diagnostic_launch", SCRIPT)
policy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(policy)
UUID = "E6F7877C-EDAD-4157-8018-49733B072152"
HOSTED = {"TTEMP_DISPOSABLE_CI": "1", "GITHUB_ACTIONS": "true",
          "RUNNER_ENVIRONMENT": "github-hosted", "RUNNER_OS": "macOS"}


def local_environment():
    return {key: value for key, value in os.environ.items()
            if not key.startswith(("TTEMP_", "GITHUB_", "RUNNER_"))}


class DiagnosticPolicyTests(unittest.TestCase):
    def test_dedicated_ids_do_not_need_ci_or_request_an_override(self):
        for identifier in (policy.DEVELOPMENT_ID, f"com.am921.ttemp.runtime-test.{UUID}",
                           f"com.am921.ttemp.update-test.{UUID.lower()}"):
            for environment in ({}, HOSTED):
                self.assertEqual(policy.runtime_arguments(identifier, environment), [])

    def test_production_is_rejected_outside_explicit_hosted_macos_ci(self):
        invalid = [{}, {"CI": "true"}, {"TTEMP_DISPOSABLE_CI": "1"}]
        invalid += [{k: v for k, v in HOSTED.items() if k != missing} for missing in HOSTED]
        invalid += [dict(HOSTED, **{key: value}) for key, value in (
            ("RUNNER_ENVIRONMENT", "self-hosted"), ("RUNNER_OS", "Linux"),
            ("GITHUB_ACTIONS", "false"), ("TTEMP_DISPOSABLE_CI", "true"))]
        for environment in invalid:
            with self.subTest(environment=environment), self.assertRaises(ValueError):
                policy.runtime_arguments(policy.PRODUCTION_ID, environment)
        self.assertEqual(policy.runtime_arguments(policy.PRODUCTION_ID, HOSTED), ["--disposable-ci"])

    def test_invalid_ids_are_rejected_even_in_hosted_ci(self):
        for identifier in (None, 42, [], "", "com.am921.ttemp.tests", "org.example.Ttemp",
                           "com.am921.ttemp.development.extra", "com.am921.ttemp.runtime-test.",
                           "com.am921.ttemp.update-test.invalid", f"com.am921.ttemp.runtime-test.{UUID}\n",
                           f"com.am921.ttemp.runtime-test.{UUID}-extra", f"com.am921.ttemp.runtime-test.{{{UUID}}}"):
            with self.subTest(identifier=identifier), self.assertRaises(ValueError):
                policy.runtime_arguments(identifier, HOSTED)

    def test_rejection_checks_never_launch_production_development_or_unknown_ids(self):
        for identifier in (None, policy.PRODUCTION_ID, policy.DEVELOPMENT_ID, "com.am921.ttemp.runtime-test.invalid"):
            with mock.patch.object(policy.subprocess, "run") as run, self.assertRaises(ValueError):
                policy.check_rejections(identifier, "/unused/Ttemp")
            run.assert_not_called()

    def test_rejection_checks_require_exit_code_diagnostic_and_no_success_marker(self):
        identifier = f"com.am921.ttemp.runtime-test.{UUID}"
        good = [subprocess.CompletedProcess([], 1, "", expected) for _, expected in policy.REJECTIONS]
        with mock.patch.object(policy.subprocess, "run", side_effect=good) as run, mock.patch("builtins.print"):
            policy.check_rejections(identifier, "/unused/Ttemp")
        self.assertEqual(run.call_count, len(policy.REJECTIONS))
        self.assertTrue(all(call.kwargs["timeout"] == 5 for call in run.call_args_list))
        for result in (subprocess.CompletedProcess([], 0, "", good[0].stderr),
                       subprocess.CompletedProcess([], 1, "", "unrelated failure"),
                       subprocess.CompletedProcess([], 1, "TTEMP_ISOLATED_READY", good[0].stderr)):
            with mock.patch.object(policy.subprocess, "run", return_value=result), self.assertRaises(ValueError):
                policy.check_rejections(identifier, "/unused/Ttemp")


class DiagnosticPreflightTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="ttemp-launch-guard-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.app = self.root / "path with spaces/Ttemp.app"
        self.contents = self.app / "Contents"
        (self.contents / "MacOS").mkdir(parents=True)
        self.app_marker = self.root / "app-was-launched"
        self.signing_marker = self.root / "static-check-reached"
        executable = self.contents / "MacOS/Ttemp"
        executable.write_text(f'#!/bin/bash\ntouch "{self.app_marker}"\nexit 88\n', encoding="utf-8")
        executable.chmod(0o755)
        tool_dir = self.root / "tools"
        tool_dir.mkdir()
        codesign = tool_dir / "codesign"
        codesign.write_text(f'#!/bin/bash\ntouch "{self.signing_marker}"\nexit 89\n', encoding="utf-8")
        codesign.chmod(0o755)
        self.environment = dict(local_environment(), PATH=str(tool_dir) + os.pathsep + os.environ["PATH"])
        self.set_id(policy.PRODUCTION_ID)

    def set_id(self, identifier, fmt=plistlib.FMT_XML):
        (self.contents / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": identifier}, fmt=fmt))

    def run_guard(self, *args, environment=None):
        return subprocess.run([sys.executable, "-B", str(SCRIPT), *args], capture_output=True,
                              text=True, env=environment or self.environment, timeout=10)

    def run_verifier(self, *args, environment=None):
        return subprocess.run(["/bin/bash", str(ROOT / "scripts/verify-app.sh"), *args, str(self.app)],
                              capture_output=True, text=True, env=environment or self.environment, timeout=10)

    def test_distribution_mode_is_static_locally_and_runtime_only_in_opted_in_ci(self):
        self.assertEqual(self.run_guard("distribution-mode").stdout.strip(), "--static-only")
        result = self.run_guard("distribution-mode", environment=dict(self.environment, **HOSTED))
        self.assertEqual(result.stdout.strip(), "--runtime")

    def test_rejects_production_before_signing_or_launching(self):
        for mode in ((), ("--runtime",)):
            result = self.run_verifier(*mode)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Diagnostic launch rejected", result.stderr)
            self.assertFalse(self.app_marker.exists())
            self.assertFalse(self.signing_marker.exists())

    def test_self_hosted_ci_cannot_bypass_preflight(self):
        environment = dict(self.environment, **HOSTED)
        environment["RUNNER_ENVIRONMENT"] = "self-hosted"
        result = self.run_verifier(environment=environment)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.signing_marker.exists())
        self.assertFalse(self.app_marker.exists())

    def test_static_only_reaches_static_checks_but_never_launches(self):
        result = self.run_verifier("--static-only")
        self.assertEqual(result.returncode, 89)
        self.assertTrue(self.signing_marker.exists())
        self.assertFalse(self.app_marker.exists())
        self.assertNotIn("TTEMP_SELF_TEST_OK", result.stdout)

    def test_dedicated_id_reaches_static_checks(self):
        self.set_id(f"com.am921.ttemp.runtime-test.{UUID}")
        result = self.run_verifier()
        self.assertEqual(result.returncode, 89)
        self.assertTrue(self.signing_marker.exists())
        self.assertFalse(self.app_marker.exists())

    def test_runtime_cli_accepts_xml_and_binary_plists_without_running_the_app(self):
        for fmt in (plistlib.FMT_XML, plistlib.FMT_BINARY):
            self.set_id(policy.PRODUCTION_ID, fmt)
            result = self.run_guard("runtime", str(self.app), environment=dict(self.environment, **HOSTED))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "--disposable-ci")
            self.assertFalse(self.app_marker.exists())

    def test_missing_malformed_or_unrecognized_metadata_is_rejected(self):
        info = self.contents / "Info.plist"
        info.unlink()
        self.assertNotEqual(self.run_guard("runtime", str(self.app)).returncode, 0)
        for data in (b"not a plist", plistlib.dumps([]), plistlib.dumps({}),
                     plistlib.dumps({"CFBundleIdentifier": "org.example.Ttemp"})):
            info.write_bytes(data)
            self.assertNotEqual(self.run_guard("runtime", str(self.app)).returncode, 0)
        self.assertFalse(self.app_marker.exists())


if __name__ == "__main__":
    unittest.main()
