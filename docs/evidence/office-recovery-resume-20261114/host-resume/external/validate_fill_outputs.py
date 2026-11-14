"""Run the unchanged OpenXML validator on the exact native-fill host artifacts.

The Office validator, SDK, and NuGet assemblies have already been built and
self-tested. This collector checks their recorded hashes, reruns the self-test,
then binds the four host-produced packages to the schema receipt. It never
rewrites an Office package or invokes Quds to inspect it.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--test-file", required=True, help="App-relative test source")
    parser.add_argument("--host-inputs", required=True,
                        help="App-relative frozen inputs receipt for the actual host run")
    parser.add_argument("--label", default="final")
    parser.add_argument("--workspace", type=Path,
                        help="Parent directory containing CrispCloud and toolchain")
    args = parser.parse_args()
    if not args.label.replace("-", "").replace("_", "").isalnum():
        raise ValueError("Use a simple letters/digits/dashes attempt label")

    evidence = Path(__file__).resolve().parent
    workspace = (args.workspace or evidence.parent).resolve()
    app = workspace / "CrispCloud"
    tool = workspace / "toolchain/office-validation"
    dotnet = workspace / "toolchain/dotnet/dotnet"
    output_root = app / "build/office-fill-host-acceptance"
    source = app / "tool/office-validation/Program.cs"
    project = app / "tool/office-validation/OfficeValidation.csproj"
    build = json.loads((evidence / "validator-build-receipt.json").read_text())
    provenance = json.loads((evidence / "validator-provenance.json").read_text())
    assert sha256(source) == build["source_sha256"]
    assert sha256(project) == provenance["project"]["sha256"]
    assert sha256(tool / "OfficeValidation.dll") == build["assembly_sha256"]
    for name, expected in build["dependencies_sha256"].items():
        assert sha256(tool / name) == expected, name

    names = ("source.xlsx", "saved-1.xlsx", "saved-2.xlsx", "saved-3.xlsx")
    office_suffixes = {".xlsx", ".pptx", ".docx", ".docm", ".dotx", ".dotm"}
    found = sorted(p.relative_to(output_root).as_posix()
                   for p in output_root.rglob("*")
                   if p.is_file() and p.suffix.lower() in office_suffixes)
    assert found == sorted(names), found
    inventory = [{"file": name,
                  "role": "independently_authored_input" if name == "source.xlsx"
                          else "actual_host_saved_output",
                  "path": str(output_root / name),
                  "size_bytes": (output_root / name).stat().st_size,
                  "sha256": sha256(output_root / name)} for name in names]

    test_source = (app / args.test_file).resolve()
    assert test_source.is_relative_to(app.resolve()) and test_source.is_file()
    recipe_paths = (
        test_source,
        app / "packages/quds_office_engine/test/fixtures/fidelity/sheet-fill-native.xml",
        app / "test/fixtures/office_native_workflows/native-sheet-source.xlsx",
    )
    recipe = [{"path": str(path), "sha256": sha256(path)}
              for path in recipe_paths]
    host_capture_path = (app / args.host_inputs).resolve()
    assert host_capture_path.is_relative_to(app) and host_capture_path.is_file()
    host_capture_bytes = host_capture_path.read_bytes()
    host_capture = json.loads(host_capture_bytes)
    assert host_capture["test_sha256"][args.test_file] == sha256(test_source)
    for item in recipe[1:]:
        relative = Path(item["path"]).relative_to(app).as_posix()
        assert host_capture["independent_input_sha256"][relative] == item["sha256"]
    run_root = evidence / args.label
    run_root.mkdir(exist_ok=False)
    (run_root / "host-inputs.json").write_bytes(host_capture_bytes)
    env = dict(os.environ)
    env.update(provenance["environment"])
    commands = []
    started = datetime.now(timezone.utc).isoformat()

    def run(label: str, command: list[str]) -> int:
        result = subprocess.run(command, cwd=app, env=env,
                                stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True)
        (run_root / (label + ".log")).write_text(result.stdout)
        commands.append({"label": label, "command": command,
                         "cwd": str(app), "exit_code": result.returncode,
                         "log": label + ".log"})
        write_json(run_root / "commands.json", commands)
        print(result.stdout, end="", flush=True)
        return result.returncode

    self_test_exit = run("validator-self-test", [str(dotnet),
                        str(tool / "OfficeValidation.dll"), "--self-test"])
    if self_test_exit != 0:
        return self_test_exit
    report_path = run_root / "schema-report.json"
    validation_exit = run("schema-validation", [str(dotnet),
                          str(tool / "OfficeValidation.dll"),
                          str(output_root), str(report_path)])
    report = json.loads(report_path.read_text())
    by_path = {r["File"]: r for r in report["Reports"]}
    assert len(by_path) == len(names) == report["Files"]
    artifacts = run_root / "artifacts"
    artifacts.mkdir()
    for item in inventory:
        assert sha256(Path(item["path"])) == item["sha256"], item["file"]
        result = by_path[item["path"]]
        assert result["Sha256"] == item["sha256"], item["file"]
        item["validation_errors"] = len(result.get("Errors", []))
        item["exception"] = result.get("Exception")
        saved_copy = artifacts / item["file"]
        saved_copy.write_bytes(Path(item["path"]).read_bytes())
        assert sha256(saved_copy) == item["sha256"], item["file"]
        item["evidence_copy"] = saved_copy.relative_to(run_root).as_posix()
    for item in recipe:
        assert sha256(Path(item["path"])) == item["sha256"], item["path"]
    write_json(run_root / "input-inventory.json", inventory)
    summary = {
        "schema_version": 1,
        "scope": "Four native-fill host regression packages only; independent OpenXML SDK schema validation, without rendering",
        "started_utc": started,
        "completed_utc": datetime.now(timezone.utc).isoformat(),
        "app_commit_at_validation": subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=app, text=True).strip(),
        "test_source": {"path": str(test_source), "sha256": sha256(test_source)},
        "fixture_recipe_inputs": recipe,
        "host_input_capture": {
            "path": str(host_capture_path),
            "sha256": hashlib.sha256(host_capture_bytes).hexdigest(),
            "evidence_copy": "host-inputs.json",
            "head": host_capture["head"],
            "command": host_capture["command"],
            "scope": "Execution inputs only; host test outcome is recorded by the host collector separately",
        },
        "validator_source": {"path": str(source), "sha256": sha256(source)},
        "sdk_version": build["sdk"],
        "runtime_version": build["runtime"],
        "openxml_version": "3.3.0",
        "file_format_validation_target": "Office2019",
        "self_test_exit_code": self_test_exit,
        "validation_exit_code": validation_exit,
        "files": report["Files"],
        "failures": report["Failures"],
        "all_hashes_matched_before_during_after_validation": True,
        "inventory": inventory,
        "collector_sha256": sha256(Path(__file__)),
        "artifacts_sha256": {name: sha256(run_root / name) for name in (
            "schema-report.json", "input-inventory.json", "commands.json",
            "validator-self-test.log", "schema-validation.log", "host-inputs.json")},
    }
    write_json(run_root / "validation-summary.json", summary)
    print(json.dumps({"files": report["Files"], "failures": report["Failures"],
                      "exit_code": validation_exit, "evidence": str(run_root)},
                     indent=2))
    return validation_exit


if __name__ == "__main__":
    raise SystemExit(main())
