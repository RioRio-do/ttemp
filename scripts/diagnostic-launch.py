#!/usr/bin/env python3
"""Fail closed before launching an app that could alter production menu-bar records."""
import argparse
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys


PRODUCTION_ID = "com.am921.ttemp"
DEVELOPMENT_ID = "com.am921.ttemp.development"
TEST_ID = re.compile(
    r"com\.am921\.ttemp\.(?:runtime-test|update-test)\."
    r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
)
REJECTIONS = [
    ([], "Test apps require --self-test or --isolated"),
    (["--self-test", "--isolated"], "Choose one diagnostic mode"),
    (["--self-test", "--disposable-ci"], "Diagnostics require a development/test bundle ID"),
    (["--isolated", "--probe-library", "/unused"], "--probe-library requires --self-test"),
]


def is_disposable_ci(environment):
    # Accidental-launch guard only. Environment variables are not an attestation.
    return all(environment.get(key) == value for key, value in {
        "TTEMP_DISPOSABLE_CI": "1",
        "GITHUB_ACTIONS": "true",
        "RUNNER_ENVIRONMENT": "github-hosted",
        "RUNNER_OS": "macOS",
    }.items())


def runtime_arguments(identifier, environment):
    if isinstance(identifier, str) and (identifier == DEVELOPMENT_ID or TEST_ID.fullmatch(identifier)):
        return []
    if identifier == PRODUCTION_ID and is_disposable_ci(environment):
        return ["--disposable-ci"]
    raise ValueError("Runtime verification requires a development/test bundle ID. "
                     "Use scripts/test-release.sh, or --static-only for a production app. "
                     "Production runtime verification is restricted to disposable CI.")


def check_rejections(identifier, executable):
    # Even if the app's guard regresses, never exercise these cases with production
    # or the persistent development identity. subprocess kills/reaps a timed-out child.
    if not isinstance(identifier, str) or not TEST_ID.fullmatch(identifier):
        raise ValueError("Rejection tests require a disposable runtime/update test ID")
    for arguments, expected in REJECTIONS:
        result = subprocess.run([str(executable), *arguments], capture_output=True, text=True, timeout=5)
        if result.returncode != 1 or expected not in result.stderr or "TTEMP_" in result.stdout:
            raise ValueError(f"Diagnostic entry guard did not reject {arguments!r}")
    print(f"TTEMP_DIAGNOSTIC_REJECTIONS_OK {len(REJECTIONS)} checks")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("distribution-mode")
    runtime = commands.add_parser("runtime")
    runtime.add_argument("app", type=Path)
    rejections = commands.add_parser("check-rejections")
    rejections.add_argument("app", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "distribution-mode":
            print("--runtime" if is_disposable_ci(os.environ) else "--static-only")
        else:
            with (args.app / "Contents/Info.plist").open("rb") as stream:
                info = plistlib.load(stream)
            if not isinstance(info, dict):
                raise ValueError("Invalid app Info.plist")
            if args.command == "check-rejections":
                check_rejections(info.get("CFBundleIdentifier"), args.app / "Contents/MacOS/Ttemp")
            else:
                print(" ".join(runtime_arguments(info.get("CFBundleIdentifier"), os.environ)))
    except (OSError, ValueError, plistlib.InvalidFileException, subprocess.TimeoutExpired) as error:
        print(f"Diagnostic launch rejected: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
