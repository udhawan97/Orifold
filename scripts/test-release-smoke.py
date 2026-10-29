#!/usr/bin/env python3
"""Exercise the release workflow's shell with synthetic children, never a packaged app."""
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import textwrap


def main():
    root = Path(sys.argv[1]).resolve()
    root.mkdir(parents=True, exist_ok=True)
    workflow = (Path(__file__).resolve().parents[1] / ".github/workflows/release.yml").read_text()
    step = workflow.split("      - name: Smoke-test packaged app\n", 1)[1]
    step = step.split("\n      - name:", 1)[0]
    # Skip DMG mounting/copying; retain the actual resource, signature and launch gates.
    body = textwrap.dedent(step[step.index("          # Structural gate:"):])
    failures = []
    for scenario in ["0", "1", "137", "live", "missing-bundle", "missing-localization", "bad-signature"]:
        case = Path(tempfile.mkdtemp(prefix=scenario + "-", dir=root))
        app = case / "synthetic.app"
        executable = app / "Contents/MacOS/Orifold"
        executable.parent.mkdir(parents=True)
        # These are disposable test children, with no application code or user files.
        executable.write_text("#!/bin/bash\necho synthetic-child-output\n"
                              "if [[ $SCENARIO == live ]]; then exec /bin/sleep 60; fi\n"
                              "exit \"$SCENARIO\"\n")
        executable.chmod(0o700)
        bundle = app / "Contents/Resources/Orifold_Orifold.bundle"
        if scenario != "missing-bundle":
            bundle.mkdir(parents=True)
            if scenario != "missing-localization":
                (bundle / "Localizable.xcstrings").write_text("synthetic localization marker")
        script = case / "probe.bash"
        script.write_text("set -euo pipefail\n"
                          "smoke=" + shlex.quote(str(case)) + "\n"
                          "app=" + shlex.quote(str(app)) + "\n"
                          "export SCENARIO=" + shlex.quote(scenario) + "\n" + """
# Platform adapter: never consult a keychain or verify a real app signature.
codesign() { [[ "$SCENARIO" != bad-signature ]]; }
# Wait deterministically for early children; the live case remains running.
sleep() {
    if [[ "$SCENARIO" != live ]]; then
        while kill -0 "$pid" 2>/dev/null; do /bin/sleep 0.01; done
    fi
}
""" + body)
        result = subprocess.run(["/bin/bash", "--noprofile", "--norc", str(script)],
                                cwd=case, env={"PATH": "/usr/bin:/bin:/usr/sbin:/sbin"},
                                capture_output=True, text=True, timeout=5)
        output = result.stdout + result.stderr
        early = scenario in {"0", "1", "137"}
        expected_status = 1 if scenario in {"137", "missing-bundle", "missing-localization", "bad-signature"} else 0
        diagnostics = ("----- launch output -----" in output and "synthetic-child-output" in output)
        checks = {"final status": result.returncode == expected_status,
                  "child diagnostics": diagnostics == early}
        if early:
            checks["classification"] = (f"signal exit code {scenario}" in output if scenario == "137"
                                         else f"App exited early (code {scenario})" in output)
        elif scenario == "live":
            checks["live classification"] = "App still alive after 8s — launch OK" in output
        else:
            message = {"missing-bundle": "Orifold_Orifold.bundle missing",
                       "missing-localization": "resource bundle contains no localization artifact",
                       "bad-signature": "codesign verify failed"}[scenario]
            checks["structural/signature gate"] = message in output
            checks["no launch after blocked gate"] = not (case / "out.log").exists()
        failed = [name for name, passed in checks.items() if not passed]
        print(f"{'FAIL' if failed else 'PASS'} {scenario}: status={result.returncode}, "
              f"diagnostics={diagnostics}; " + (", ".join(failed) or "all checks"))
        if failed:
            failures.append((scenario, failed, output))
    assert not failures, failures
    print("Passed 7 extracted release-smoke cases (synthetic children; no packaged-app acceptance claim).")


if __name__ == "__main__":
    main()
