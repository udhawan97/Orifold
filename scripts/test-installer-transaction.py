#!/usr/bin/env python3
"""Exercise the installer's actual transaction functions using disposable marker bundles.

Never source the installer entry point. Process control and platform verification are
replaced in the extracted functions; no app, Apple event, or user directory is touched.
"""
import hashlib
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile


def function(source, name):
    match = re.search(rf"^{name}\(\) \{{\n.*?^\}}$", source, re.M | re.S)
    if match is None:
        raise AssertionError(f"Missing installer function: {name}")
    return match.group(0)


def digest(directory):
    return {str(p.relative_to(directory)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in directory.rglob("*") if p.is_file()}


def main():
    root = Path(sys.argv[1]).resolve()
    root.mkdir(parents=True, exist_ok=True)
    source = Path(__file__).with_name("install-mac.sh").read_text()
    body = "\n".join(function(source, n) for n in
                     ["cleanup", "stop_running_app", "remove_stray_app_copies", "replace_staged_app"])
    # Intercept every process/Apple-event operation in the tested source, including
    # any future kill regression, before the shell can execute it.
    assert "/usr/bin/pkill" not in body and not re.search(r"\bkill\b", body)
    for original, replacement in {
        "/usr/bin/pgrep": "fake_pgrep", "/usr/bin/osascript": "fake_osascript",
        "/bin/sleep": "fake_sleep", "/usr/bin/ditto": "fake_ditto",
        "/usr/bin/xattr": "fake_xattr", "/bin/mv": "fake_mv",
    }.items():
        body = body.replace(original, replacement)
    body = body.replace(">/dev/null 2>&1 <<", "<<")
    # Limit duplicate cleanup to fixture locations, preserving the production loop.
    body = body.replace('local other_locations=("/Applications" "$INSTALL_DIR")',
                        'local other_locations=("$CASE_ROOT/OtherApplications" "$INSTALL_DIR")')
    assert '"/Applications"' not in body
    scenarios = ["cancel", "still-running", "copy-failure", "preverify-failure",
                 "backup-move-failure", "swap-failure", "postverify-failure", "interrupt",
                 "fresh-postverify-failure", "success", "clean-quit", "fresh-success", "duplicate-cancel"]
    for scenario in scenarios:
        case = Path(tempfile.mkdtemp(prefix=scenario + "-", dir=root))
        current = case / "Applications/Orifold.app"
        fresh = scenario.startswith("fresh-")
        if not fresh:
            (current / "Contents").mkdir(parents=True)
            (current / "Contents/old.bin").write_bytes(b"old-app\x00\xff")
            (current / "old-resource").write_text("preserve exactly")
        previous = digest(current)
        staged = case / "stage/Orifold.app"
        staged.mkdir(parents=True)
        (staged / "new.bin").write_bytes(b"new-app\x00\x01")
        expected = digest(staged)
        duplicate = case / "OtherApplications/Orifold.app"
        duplicate.mkdir(parents=True)
        (duplicate / "duplicate.bin").write_bytes(b"duplicate")
        script = case / "probe.zsh"
        script.write_text("""#!/bin/zsh
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
CASE_ROOT=""" + shlex.quote(str(case)) + "\nSCENARIO=" + shlex.quote(scenario) + """
TMPPREFIX="$CASE_ROOT/zsh"
APP_NAME=Orifold
LEGACY_APP_NAMES=(LegacyOrifold)
INSTALL_DIR="$CASE_ROOT/Applications"
INSTALLED_APP="$INSTALL_DIR/Orifold.app"
STAGE_ROOT="$CASE_ROOT/stage"
STAGED_APP="$STAGE_ROOT/Orifold.app"
LOG_FILE="$CASE_ROOT/install.log"
INSTALL_TRANSACTION_DIR=""
INSTALL_TRANSACTION_ACTIVE=0
INSTALL_HAD_PREVIOUS=0
print_step() { :; }
print_note() { print -r -- "$1" >> "$LOG_FILE"; }
fail() { print -r -- "$1" >> "$LOG_FILE"; exit 1; }
fake_pgrep() {
    if [[ "$SCENARIO" == clean-quit ]]; then [[ ! -f "$CASE_ROOT/quit-targets" ]]; return; fi
    [[ "$SCENARIO" == cancel || "$SCENARIO" == still-running || "$SCENARIO" == duplicate-cancel ]]
}
fake_osascript() {
    print -r -- "$2" >> "$CASE_ROOT/quit-targets"
    [[ "$SCENARIO" != cancel && "$SCENARIO" != duplicate-cancel ]]
}
fake_sleep() { :; }
fake_xattr() { :; }
fake_ditto() {
    [[ "$SCENARIO" != copy-failure ]] || return 1
    /bin/cp -R "$2" "$3"
}
fake_mv() {
    if [[ "$1" == "$INSTALLED_APP" && "$SCENARIO" == backup-move-failure ]]; then return 1; fi
    if [[ "$1" == */new.app ]]; then
        [[ "$SCENARIO" != swap-failure ]] || return 1
        /bin/mv "$@"
        # Simulate the termination trap exactly after the install rename, before
        # post-swap verification can commit it. No signal reaches another process.
        [[ "$SCENARIO" != interrupt ]] || exit 143
    else
        /bin/mv "$@"
    fi
}
verify_app_bundle() {
    if [[ "$1" == */new.app && "$SCENARIO" == preverify-failure ]]; then fail preverify; fi
    if [[ "$1" == "$INSTALLED_APP" && ( "$SCENARIO" == postverify-failure || "$SCENARIO" == fresh-postverify-failure ) ]]; then fail postverify; fi
}
""" + body + """
trap cleanup EXIT
# A duplicate refusal happens after a normal target quit, so simulate that target
# as already closed without weakening the actual duplicate-cleanup function.
if [[ "$SCENARIO" == duplicate-cancel ]]; then
    functions[original_stop_running_app]=$functions[stop_running_app]
    stop_running_app() {
        [[ "$1" != "$INSTALLED_APP" ]] || return 0
        original_stop_running_app "$1"
    }
fi
replace_staged_app
""")
        result = subprocess.run(["/bin/zsh", str(script)], cwd=case,
                                env={"PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                                     "TMPDIR": str(case)}, capture_output=True, text=True)
        success = scenario in {"success", "clean-quit", "fresh-success", "duplicate-cancel"}
        assert (result.returncode == 0) == success, (scenario, result.returncode, result.stderr)
        assert digest(current) == (expected if success else previous), scenario
        assert current.exists() == (success or not fresh), scenario
        assert duplicate.exists() == (not success or scenario == "duplicate-cancel"), scenario
        assert not list((case / "Applications").glob(".orifold-update.*")), scenario
        if scenario in {"cancel", "still-running", "clean-quit"}:
            assert (case / "quit-targets").read_text().splitlines() == [str(current)]
        if (case / "quit-targets").exists():
            targets = (case / "quit-targets").read_text().splitlines()
            assert all(target.startswith(str(case) + "/") for target in targets), scenario
        print(f"PASS {scenario}: bundle bytes and duplicate preservation")
    print(f"Passed {len(scenarios)} installer transaction scenarios (synthetic bundles; no native launch claim).")


if __name__ == "__main__":
    main()
