#!/usr/bin/env python3
"""Current-continuation copy of run_portable.py with an explicit JS runtime and artifact index."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--launcher", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--node", type=Path, required=True)
    args = parser.parse_args()
    repo, output = args.repo.resolve(), args.output.resolve()
    if output.exists() and any(output.iterdir()):
        parser.error("output must be empty")
    output.mkdir(parents=True, exist_ok=True)
    commands = []

    def run(name, command):
        result = subprocess.run(command, cwd=repo, capture_output=True, check=False)
        (output / f"{name}.stdout").write_bytes(result.stdout)
        (output / f"{name}.stderr").write_bytes(result.stderr)
        commands.append({"name": name, "argv": command, "cwd": str(repo),
                         "returncode": result.returncode})
        (output / "commands.json").write_text(json.dumps(commands, indent=2) + "\n")
        if result.returncode:
            raise SystemExit(f"{name} failed with exit {result.returncode}; see retained logs")
        return result.stdout

    dart = [str(args.launcher.resolve()), "dart"]
    driver = "test/support/archive_png_carving_web_acceptance.dart"
    run("fixture-reference", [sys.executable,
                              "test/support/generate_png_carving_reference.py", "--check"])
    vm = json.loads(run("vm-candidates", [*dart, "--packages=.dart_tool/package_config.json",
                                          driver, "--emit-candidates"]))
    compiled = output / "png-carving.js"
    run("javascript-compile", [*dart, "compile", "js", "--packages=.dart_tool/package_config.json",
                                "-O2", driver, "-o", str(compiled)])
    bootstrap = ("global.self=global; "
                 "global.dartMainRunner=(main,args)=>main(['--emit-candidates']); "
                 "require(process.argv[1]);")
    js = json.loads(run("javascript-candidates", [str(args.node.resolve()), "-e", bootstrap, str(compiled)]))
    expected = json.loads((repo / "test/fixtures/archives/png-carving-reference-manifest.json").read_text())
    summaries = {}
    for runtime, receipt in (("vm", vm), ("javascript", js)):
        if receipt["groups"] != len(expected["cases"]) or receipt["checks"] <= 0:
            raise SystemExit(f"{runtime} did not execute the complete independent fixture inventory")
        candidates = output / f"{runtime}-candidates.json"
        candidates.write_text(json.dumps(receipt, sort_keys=True) + "\n")
        oracle = output / f"{runtime}-python.json"
        run(f"{runtime}-python", [sys.executable, "test/support/check_archive_png_carving.py",
                                  "--candidates", str(candidates), "--report", str(oracle)])
        verified = json.loads(oracle.read_text())
        if verified["passed"] != len(expected["cases"]) or not verified["wrongExpectedHashRejected"]:
            raise SystemExit(f"{runtime} independent verification incomplete")
        summaries[runtime] = {"cases": receipt["groups"], "assertions": receipt["checks"],
                              "verified_zips": verified["passed"],
                              "verified_pngs": verified["verifiedPngs"],
                              "wrong_expected_hash_rejected": verified["wrongExpectedHashRejected"]}
    if vm["referenceCases"] != js["referenceCases"] or vm["checks"] != js["checks"]:
        raise SystemExit("VM and JavaScript recovery identities differ")
    summary = {"runtimes": summaries, "runtime_outputs_match": True,
               "compiled_javascript_sha256": hashlib.sha256(compiled.read_bytes()).hexdigest(),
               "qualification_success": True}
    (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    artifacts = {str(path.relative_to(output)): {"sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                  "size": path.stat().st_size} for path in sorted(output.rglob("*")) if path.is_file()}
    (output / "artifacts-sha256.json").write_text(json.dumps(artifacts, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
