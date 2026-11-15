#!/usr/bin/env python3
"""Run one source-bound gate; preserve each receipt before starting the next."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("name")
parser.add_argument("--label")
parser.add_argument("--engine-label", default="engine")
parser.add_argument("--capture-label", default="navigation-capture")
parser.add_argument("--repo", type=Path, default=Path.cwd())
args = parser.parse_args()
repo = args.repo.resolve()
plans = Path(__file__).resolve().parent
base = plans.parent
label = args.label or args.name
for value in (label, args.engine_label, args.capture_label):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", value):
        parser.error("gate labels must be simple directory names")
output = base / label
if output.exists() and any(output.iterdir()):
    parser.error("receipt already exists; use a fresh --label")
head = subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip()
sdk = Path(os.environ["FLUTTER_ROOT"]).resolve()
dart = sdk / "bin/cache/dart-sdk/bin/dart"
flutter = sdk / "bin/flutter"
recorder = repo / "docs/evidence/storage-carving-20261115/record_gate.py"
spec = importlib.util.spec_from_file_location("gate_recorder", recorder)
recording = importlib.util.module_from_spec(spec)
spec.loader.exec_module(recording)
state = recording.state(repo)
if state["head"] != head or state["source_changes"] or state["untracked_source"]:
    parser.error("save the complete clean source before running a gate")
tools = [Path(__file__).resolve(), dart,
         Path(os.environ["CRISP_TOOLCHAIN_ROOT"]) / "env.sh"]
cwd = "."
suites = None
artifacts = None
env = os.environ.copy()
env.setdefault("CARGO_BUILD_JOBS", "4")


def fingerprint(path):
    data = path.read_bytes()
    return {"sha256": hashlib.sha256(data).hexdigest(), "size": len(data)}


def manifest(name):
    path = plans / name
    tools.append(path)
    return path, [line.strip() for line in path.read_text().splitlines()
                  if line.strip() and not line.lstrip().startswith("#")]


def fresh_artifacts(suffix):
    path = base / (label + suffix)
    if path.exists() and any(path.iterdir()):
        raise SystemExit("artifact directory already exists; use a fresh --label: " + str(path))
    return path


def retain_previous(paths):
    existing = [path for path in paths if path.exists()]
    if not existing:
        return
    retained = fresh_artifacts("-prior-build")
    retained.mkdir(parents=True, exist_ok=True)
    for path in existing:
        shutil.move(str(path), retained / path.name)


def prerequisite(name, required_suite):
    path = base / name
    indexed = json.loads((path / "artifacts-sha256.json").read_text())
    actual = {p.name for p in path.iterdir() if p.is_file() and p.name != "artifacts-sha256.json"}
    if actual != set(indexed):
        raise SystemExit("prerequisite artifact inventory differs: " + name)
    for filename, expected in indexed.items():
        item = path / filename
        if item.parent != path or item.is_symlink() or fingerprint(item) != expected:
            raise SystemExit("prerequisite artifact hash differs: " + name + "/" + filename)
    metadata = json.loads((path / "metadata.json").read_text())
    summary = json.loads((path / "summary.json").read_text())
    selected = (path / "suites.txt").read_text().splitlines()
    if not (metadata["qualification_success"] and metadata["inputs_and_commit_stable"]
            and metadata["returncode"] == 0 and metadata.get("postprocessing", {}).get("success")
            and summary["qualification_success"]
            and summary["done_success"] and required_suite in selected
            and not any(summary["totals"][key] for key in ("failed", "errors", "skipped", "other_results"))):
        raise SystemExit("prerequisite did not pass: " + name)
    current = recording.snapshot(repo)
    if current["entries_sha256"] != metadata["after_entries_sha256"]:
        raise SystemExit("prerequisite source/resolution differs: " + name)
    changed = subprocess.check_output(["git", "-C", str(repo), "diff", "--name-only",
                                      metadata["after_git"]["head"], head, "--", ".", ":(exclude)docs/evidence/**"])
    if changed:
        raise SystemExit("prerequisite source identities or modes differ: " + name)
    if metadata["after_tools"].get(str(Path(__file__).resolve())) != fingerprint(Path(__file__))['sha256']:
        raise SystemExit("prerequisite used a different gate driver: " + name)
    tools.extend(sorted(path / filename for filename in [*indexed, "artifacts-sha256.json"]))
    return path


if args.name.startswith("analysis-"):
    _, files = manifest(args.name + "-files.txt")
    command = [str(dart), "analyze", "--fatal-infos", "--fatal-warnings", *files]
    if args.name == "analysis-cli":
        tools.extend(repo / "cli/.dart_tool" / name for name in ("package_config.json", "package_graph.json"))
elif args.name in {"app", "editor", "engine", "host-focus", "ods-geometry", "navigation-capture"}:
    name = "navigation" if args.name == "navigation-capture" else args.name
    suites, paths = manifest(name + "-suites.txt")
    absolute = [str(repo / p) for p in paths]
    if args.name in {"engine", "ods-geometry"}:
        cwd = "packages/quds_office_engine"
        command = [str(dart), "test", "--reporter", "json", "--concurrency=2", *absolute]
        if args.name == "engine":
            retain_previous([repo / cwd / "build/fidelity-scripted"])
    else:
        if args.name == "editor":
            cwd = "packages/quds_office_editor"
        tools.extend([flutter, sdk / "bin/cache/artifacts/engine/linux-x64/flutter_tester"])
        concurrency = "1" if args.name == "navigation-capture" else "2"
        command = [str(flutter), "--no-version-check", "--suppress-analytics", "test",
                   "--no-pub", "--reporter", "json", "--concurrency=" + concurrency, *absolute]
        if args.name == "navigation-capture":
            command = ["env", "OFFICE_NAVIGATION_PREVIEW=1", *command]
            retain_previous([repo / "build" / name for name in
                             ("office-sheet-navigation-acceptance", "office-sheet-navigation-preview")])
elif args.name == "scripted-oracle":
    generation = prerequisite(args.engine_label, "packages/quds_office_engine/test/scripted_workflows_test.dart")
    driver = plans / "run_scripted_oracle_current.py"
    tools.append(driver)
    artifacts = fresh_artifacts("-artifacts")
    command = [sys.executable, str(driver), "--repo", str(repo), "--output", str(artifacts),
               "--generation-receipt", str(generation / "produced-files.json")]
elif args.name == "source-integrity":
    driver = plans / "run_source_and_notices.py"
    historical = repo / "docs/evidence/storage-carving-20261115/local-resume-20261115T1010/source-integrity"
    tools.extend([driver, historical / "run_source_only_controls.py", historical / "verify_current_source.py"])
    artifacts = fresh_artifacts("-details")
    command = [sys.executable, str(driver), "--repo", str(repo),
               "--quds", str(repo.parent / "quds_office_suite"), "--parser", str(repo.parent / "legacy-doc-parser"),
               "--output", str(artifacts)]
elif args.name == "png-portable":
    driver = plans / "run_portable_current.py"
    launcher = plans / "toolchain_launcher.sh"
    resolved_node = shutil.which("node")
    if resolved_node is None:
        raise SystemExit("Node is required for actual compiled JavaScript execution")
    node = Path(resolved_node).resolve()
    tools.extend([driver, launcher, node])
    artifacts = fresh_artifacts("-artifacts")
    command = [sys.executable, str(driver), "--repo", str(repo), "--launcher", str(launcher),
               "--node", str(node), "--output", str(artifacts)]
elif args.name == "navigation-independent-review":
    capture = prerequisite(args.capture_label, "test/widget/office_sheet_navigation_workflow_test.dart")
    driver = plans / "verify_navigation_capture.py"
    helper = repo / "docs/evidence/office-worksheet-navigation-20261115/resume/hosted-7e5af83c/integrity/verify_hosted_artifacts.py"
    tools.extend([driver, helper])
    artifacts = fresh_artifacts("-artifacts")
    command = [sys.executable, str(driver), "--repo", str(repo),
               "--capture-receipt", str(capture), "--output", str(artifacts)]
else:
    raise SystemExit("unknown gate: " + args.name)

record = [sys.executable, str(recorder), "--repo", str(repo), "--output", str(output), "--head", head, "--cwd", cwd]
if suites:
    record.extend(["--suites", str(suites)])
for tool in dict.fromkeys(tools):
    record.extend(["--tool", str(tool)])
record.extend(["--", *command])
print("Recording", args.name, "against", head, flush=True)
code = subprocess.run(record, cwd=repo, env=env).returncode
if code == 0 and args.name in {"engine", "navigation-capture"}:
    metadata = json.loads((output / "metadata.json").read_text())
    try:
        if args.name == "engine":
            produced = repo / "packages/quds_office_engine/build/fidelity-scripted"
            expected = {f"{kind}/{name}.{extension}" for kind, extension in
                        (("word", "docx"), ("sheet", "xlsx"), ("slide", "pptx"))
                        for name in ("edited", "roundtrip-1", "roundtrip-2", "roundtrip-3")}
            actual = {str(path.relative_to(produced)) for path in produced.rglob("*")
                      if path.suffix in {".docx", ".xlsx", ".pptx"}}
            files = {name: produced / name for name in sorted(expected)}
            if actual != expected:
                raise RuntimeError("fresh engine output inventory is incomplete")
        else:
            files = {}
            for folder in ("office-sheet-navigation-acceptance", "office-sheet-navigation-preview"):
                for path in sorted((repo / "build" / folder).iterdir()):
                    if path.is_file():
                        files[folder + "/" + path.name] = path
        if any(path.is_symlink() or not path.is_file() for path in files.values()):
            raise RuntimeError("produced outputs must be regular files")
        fingerprints = {name: fingerprint(path) for name, path in files.items()}
        after_binding = recording.state(repo)
        if (after_binding["head"] != head or after_binding["source_changes"] or after_binding["untracked_source"]
                or recording.snapshot(repo)["entries_sha256"] != metadata["after_entries_sha256"]):
            raise RuntimeError("source changed while binding produced outputs")
        binding = {"schema": 1, "gate": label, "tested_head": head,
                   "source_resolution_sha256": metadata["after_entries_sha256"], "files": fingerprints,
                   "scope": "Fresh outputs were cleared before this passed generator gate and fingerprinted immediately after it."}
        (output / "produced-files.json").write_text(json.dumps(binding, indent=2) + "\n")
    except (Exception, KeyboardInterrupt) as error:
        metadata["qualification_success"] = False
        metadata["postprocessing"] = {"success": False, "error": repr(error)}
        summary_path = output / "summary.json"
        summary = json.loads(summary_path.read_text())
        summary["qualification_success"] = False
        summary_path.write_text(json.dumps(summary, indent=2) + "\n")
        code = 130 if isinstance(error, KeyboardInterrupt) else 1
        print(json.dumps({"output": str(output), "qualification_success": False,
                          "postprocessing_error": repr(error)}), flush=True)
    else:
        metadata["postprocessing"] = {"success": True,
            "produced_files_sha256": fingerprint(output / "produced-files.json")["sha256"]}
    (output / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
    indexed = {path.name: fingerprint(path) for path in sorted(output.iterdir())
               if path.is_file() and path.name != "artifacts-sha256.json"}
    (output / "artifacts-sha256.json").write_text(json.dumps(indexed, indent=2) + "\n")
raise SystemExit(code)
