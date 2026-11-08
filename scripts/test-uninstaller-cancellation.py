#!/usr/bin/env python3
"""Exercise only the uninstaller's quit gate with recording platform/removal adapters."""
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile


def main():
    root = Path(sys.argv[1]).resolve()
    root.mkdir(parents=True, exist_ok=True)
    source = Path(__file__).with_name("uninstall-mac.sh").read_text()
    body = re.search(r"^stop_running_app\(\) \{\n.*?^\}$", source, re.M | re.S).group(0)
    start = source.index('\n', source.index('printf "================='))
    end = source.index('\nprint_step "Removing installed app', start)
    gate = source[start:end]
    for original, replacement in {
        "/usr/bin/osascript": "fake_osascript",
        "/usr/bin/pgrep": "fake_pgrep",
        "/usr/bin/pkill": "fake_pkill",
        "/bin/sleep": "fake_sleep",
    }.items():
        body = body.replace(original, replacement)
    assert not re.search(r"\b(?:osascript|pgrep|pkill|kill|sleep)\b", body)
    gate = gate.replace('"/Applications/', '"$CASE_ROOT/SystemApplications/')
    assert '"/Applications/' not in gate

    for scenario in ["cancel", "still-running", "success", "other-copy-running"]:
        case = Path(tempfile.mkdtemp(prefix=scenario + "-", dir=root))
        for location in ["Applications", "SystemApplications"]:
            for name in ["Orifold", "LegacyOrifold"]:
                app = case / location / (name + ".app")
                app.mkdir(parents=True, exist_ok=True)
                (app / "marker").write_text("preserve app")
        (case / "unrelated.app").mkdir()
        (case / "support-marker").write_text("preserve support")
        script = case / "probe.zsh"
        script.write_text("""#!/bin/zsh -f
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
""" + "\n".join(name + "=" + shlex.quote(str(value)) for name, value in {
            "CASE_ROOT": case, "SCENARIO": scenario,
        }.items()) + """
TMPPREFIX="$CASE_ROOT/zsh"
APP_NAME=Orifold
LEGACY_APP_NAMES=(LegacyOrifold)
INSTALLED_APP="$CASE_ROOT/Applications/Orifold.app"
SYSTEM_INSTALLED_APP="$CASE_ROOT/SystemApplications/Orifold.app"
print_step() { :; }
print_note() { :; }
fake_osascript() {
    print -r -- "$2" >> "$CASE_ROOT/quit-targets"
    cat > "$CASE_ROOT/apple-script"
    [[ "$SCENARIO" != cancel && "$SCENARIO" != still-running ]]
}
fake_pgrep() { return 0; }
fake_pkill() { print -r -- "$*" >> "$CASE_ROOT/force-kill"; }
fake_sleep() { :; }
""" + body + "\n" + gate + """
# This stands at the first destructive boundary; no real removal is executed.
: > "$CASE_ROOT/removal-reached"
""")
        result = subprocess.run(["/bin/zsh", "-f", str(script)], cwd=case,
                                env={"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "TMPDIR": str(case)},
                                capture_output=True, text=True)
        should_stop = scenario in {"cancel", "still-running"}
        assert (result.returncode != 0) == should_stop, (scenario, result.returncode, result.stderr)
        assert not (case / "force-kill").exists(), (scenario, "force termination attempted")
        assert (case / "removal-reached").exists() != should_stop, scenario
        expected = [str(case / location / (name + ".app"))
                    for name in ["Orifold", "LegacyOrifold"]
                    for location in ["Applications", "SystemApplications"]]
        targets = (case / "quit-targets").read_text().splitlines()
        assert targets == (expected[:1] if should_stop else expected), (scenario, targets)
        apple_script = (case / "apple-script").read_text()
        assert 'application appPath is running' in apple_script, scenario
        assert 'tell application appPath to quit' in apple_script, scenario
        assert 'delay 0.25' in apple_script and 'error ' in apple_script, scenario
        assert (case / "support-marker").read_text() == "preserve support"
        assert (case / "unrelated.app").is_dir()
        assert len(list(case.glob("*Applications/*.app/marker"))) == 4
        print(f"PASS {scenario}: exact targets; cancellation stops before removal; no process effects")
    print("Passed 4 uninstaller gate scenarios (recording adapters; no native acceptance claim).")
    test_recorded_removal(root, source, body, gate)
    test_atomic_desktop_command(root)


def desktop_functions(source, names):
    return "\n".join(re.search(rf"^{name}\(\) \{{\n.*?^\}}$", source, re.M | re.S).group(0)
                     for name in names)


def command_bytes(repo, endpoint):
    return (f'#!/bin/zsh\nset -euo pipefail\nPATH="/usr/bin:/bin:/usr/sbin:/sbin"\n'
            f'/usr/bin/curl -fsSL https://raw.githubusercontent.com/udhawan97/{repo}/main/{endpoint} | /bin/zsh\n').encode()


def desktop_fixture(case, home):
    desktop = home / "Desktop"
    desktop.mkdir(parents=True)
    folder = desktop / "Orifold"
    folder.mkdir()
    (folder / "fictional.pdf").write_bytes(b"fictional user document")
    app_folder = desktop / "Install or Update pdFold.app"
    app_folder.mkdir()
    (app_folder / "keep").write_bytes(b"not a managed bundle")
    modified = desktop / "Uninstall Orifold.command"
    modified.write_bytes(command_bytes("Orifold", "scripts/uninstall-mac.sh") + b"# user modification\n")
    target = case / "unrelated-file"
    target.write_bytes(b"keep the target unchanged")
    link = desktop / "Orifold.command"
    link.symlink_to(target)
    legacy = desktop / "pdFold.command"
    legacy.write_bytes(command_bytes("pdFold", "install.sh"))
    bare = desktop / "PDFold"
    bare.write_bytes(b"ordinary desktop file")
    return desktop, legacy, link, {p: p.read_bytes() for p in [folder / "fictional.pdf", app_folder / "keep",
                                                                modified, target, bare]}


def test_atomic_desktop_command(root):
    source = Path(__file__).with_name("install-mac.sh").read_text()
    helpers = desktop_functions(source, ["desktop_command_contents", "install_desktop_command"])
    for scenario in ["write-failure", "collision"]:
        case = Path(tempfile.mkdtemp(prefix=scenario + "-", dir=root))
        helper = case / "Orifold.command"
        script = case / "publish.zsh"
        script.write_text("set -euo pipefail\nAPP_NAME=Orifold\n" + helpers + """
functions[original_contents]=$functions[desktop_command_contents]
desktop_command_contents() {
    if [[ "$SCENARIO" == write-failure ]]; then
        printf 'incomplete'
        return 1
    fi
    /bin/mkdir "$TARGET"
    print -r -- 'user-owned' > "$TARGET/marker"
    original_contents "$@"
}
if install_desktop_command "$TARGET" install.sh; then
    [[ "$SCENARIO" == collision ]] || exit 91
else
    [[ "$SCENARIO" == write-failure && ! -e "$TARGET" ]] || exit 92
fi
if [[ "$SCENARIO" == collision ]]; then
    [[ "$(< "$TARGET/marker")" == user-owned ]] || exit 93
    /bin/rm "$TARGET/marker"
    /bin/rmdir "$TARGET"
fi
functions[desktop_command_contents]=$functions[original_contents]
install_desktop_command "$TARGET" install.sh
""")
        result = subprocess.run(["/bin/zsh", "-f", str(script)], cwd=case,
                                env={"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "TARGET": str(helper),
                                     "SCENARIO": scenario, "TMPDIR": str(case)}, capture_output=True, text=True)
        assert result.returncode == 0, (scenario, result.stderr)
        assert helper.read_bytes() == command_bytes("Orifold", "install.sh") and os.access(helper, os.X_OK)
        assert not list(case.glob(".orifold-command.*")), scenario
    print("Passed partial write, conflicting directory and retry for Desktop helper publication.")


def test_recorded_removal(root, source, body, gate):
    assignments = source[source.index("APP_NAME="):source.index("KEEP_USER_DATA=")]
    removal = source[source.index('print_step "Removing installed app and commands"'):]
    assignments = assignments.replace("$HOME", "$FIXTURE_HOME").replace(
        '"/Applications/', '"$FIXTURE_HOME/SystemApplications/')
    removal = removal.replace("$HOME", "$FIXTURE_HOME").replace(
        '"/Applications/', '"$FIXTURE_HOME/SystemApplications/')
    assert "$HOME" not in assignments + removal
    assert not re.search(r"\b(?:rm|osascript|pgrep|pkill|kill|open)\b", removal)

    for keep_data, removal_error in [(0, False), (1, False), (1, True)]:
        case = Path(tempfile.mkdtemp(prefix=f"remove-keep-{keep_data}-", dir=root))
        home = case / "fixture-home"
        names = ["Orifold", "pdFold", "PDFold"]
        for location in ["Applications", "SystemApplications"]:
            for name in names:
                app = home / location / (name + ".app")
                app.mkdir(parents=True, exist_ok=True)
                (app / "marker").write_text("unchanged fixture")
        marker = home / "Library/Application Support/Orifold/marker"
        marker.parent.mkdir(parents=True)
        marker.write_text("user data marker")
        desktop, legacy, link, user_files = desktop_fixture(case, home)
        installer = Path(__file__).with_name("install-mac.sh").read_text()
        shared_names = ["desktop_command_contents", "remove_known_desktop_command"]
        install_helpers = desktop_functions(installer, shared_names + ["install_desktop_command", "refresh_desktop_commands"])
        install_helpers = install_helpers.replace("$HOME", "$FIXTURE_HOME")
        # Execute only the extracted Desktop path. Every actual file is inside the fixture.
        prepare = case / "install-helpers.zsh"
        prepare.write_text("set -euo pipefail\n" + assignments + install_helpers + """
print_note() { :; }
DESKTOP_LAUNCHER="$FIXTURE_HOME/Desktop/Orifold.command"
DESKTOP_UNINSTALLER="$FIXTURE_HOME/Desktop/Uninstall Orifold.command"
refresh_desktop_commands
""")
        env = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "FIXTURE_HOME": str(home), "TMPDIR": str(case)}
        subprocess.run(["/bin/zsh", "-f", str(prepare)], cwd=case, env=env, check=True)
        assert not legacy.exists() and link.is_symlink()
        assert all(path.read_bytes() == content for path, content in user_files.items())
        # Also check a first install: both helpers must be executable, with exact expected bytes.
        fresh_home = case / "fresh"
        (fresh_home / "Desktop").mkdir(parents=True)
        subprocess.run(["/bin/zsh", "-f", str(prepare)], cwd=case, env={**env, "FIXTURE_HOME": str(fresh_home)}, check=True)
        for filename, endpoint in [("Orifold.command", "install.sh"), ("Uninstall Orifold.command", "scripts/uninstall-mac.sh")]:
            fresh = fresh_home / "Desktop" / filename
            assert fresh.is_file() and os.access(fresh, os.X_OK) and fresh.read_bytes() == command_bytes("Orifold", endpoint)
        legacy.write_bytes(command_bytes("pdFold", "install.sh"))
        uninstall_helpers = desktop_functions(source, shared_names)
        if removal_error:
            # Simulate an unremovable, verified helper without elevated privileges.
            uninstall_helpers = uninstall_helpers.replace('/bin/rm -f "$helper"', 'false')

        script = case / "removal.zsh"
        script.write_text("""#!/bin/zsh -f
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
""" + "\n".join(name + "=" + shlex.quote(str(value)) for name, value in {
            "CASE_ROOT": case, "FIXTURE_HOME": home, "KEEP_USER_DATA": keep_data,
        }.items()) + "\n" + assignments + """
TMPPREFIX="$CASE_ROOT/zsh"
REMOVE_ERRORS=()
print_step() { :; }
print_note() { :; }
fake_osascript() { print -r -- "$2" >> "$CASE_ROOT/quit-targets"; cat >/dev/null; }
fake_pgrep() { return 1; }
fake_pkill() { exit 92; }
fake_sleep() { :; }
record_removal() {
    [[ "$2" == "$FIXTURE_HOME/"* ]] || exit 91
    printf '%s\t%s\n' "$1" "$2" >> "$CASE_ROOT/removals"
}
remove_path() { record_removal path "$1"; }
remove_glob_paths() { record_removal glob "$1"; }
""" + uninstall_helpers + "\n" + body + "\n" + gate + "\n" + removal)
        result = subprocess.run(["/bin/zsh", "-f", str(script)], cwd=case,
                                env={"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "TMPDIR": str(case)},
                                capture_output=True, text=True)
        assert result.returncode == int(removal_error), (keep_data, removal_error, result.stderr)
        if removal_error:
            assert str(legacy) in result.stderr and legacy.exists(), result.stderr
        expected = []

        def expect(kind, relative):
            expected.append(f"{kind}\t{home / relative}")

        for name in names:
            for location in ["Applications", "SystemApplications"]:
                expect("path", f"{location}/{name}.app")
        assert legacy.exists() == removal_error and link.is_symlink()
        assert all(path.read_bytes() == content for path, content in user_files.items())
        for cache in [".orifold", ".pdfold"]:
            expect("path", cache)
        if not keep_data:
            for name in names:
                expect("path", f"Library/Application Support/{name}")
            for bundle in ["com.ud.Orifold", "com.ud.PDFold"]:
                for directory, suffix in [("Application Scripts", ""), ("Caches", ""), ("Containers", ""),
                                          ("Cookies", ".binarycookies"), ("HTTPStorages", ""),
                                          ("Preferences", ".plist"), ("Saved Application State", ".savedState"),
                                          ("WebKit", "")]:
                    expect("path", f"Library/{directory}/{bundle}{suffix}")
                expect("glob", f"Library/Preferences/ByHost/{bundle}.*.plist")
            for name in names:
                for extension in ["ips", "crash"]:
                    expect("glob", f"Library/Logs/DiagnosticReports/{name}*.{extension}")
        actual = (case / "removals").read_text().splitlines()
        assert actual == expected, (keep_data, actual, expected)
        assert (case / "quit-targets").read_text().splitlines() == [
            str(home / location / (name + ".app"))
            for name in names for location in ["Applications", "SystemApplications"]]
        assert marker.read_text() == "user data marker"
        assert all((home / location / (name + ".app") / "marker").read_text() == "unchanged fixture"
                   for name in names for location in ["Applications", "SystemApplications"])
        print(f"PASS removal keep-user-data={keep_data}: exact {len(expected)} recorded non-Desktop paths/globs; Desktop ownership verified")
    print("Passed 3 install/uninstall Desktop ownership scenarios, including a reported removal failure.")


if __name__ == "__main__":
    main()
