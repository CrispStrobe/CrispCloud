#!/usr/bin/env python3
"""Run exactly one source-bound local gate; the caller saves it before continuing."""
import argparse
from pathlib import Path
import os
import shutil
import subprocess
import sys


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("name")
parser.add_argument("--label")
parser.add_argument("--repo", type=Path, default=Path.cwd())
args = parser.parse_args()
repo = args.repo.resolve()
plans = Path(__file__).resolve().parent
base = plans.parent
output = base / (args.label or args.name)
head = subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip()
sdk = Path(os.environ["FLUTTER_ROOT"])
tools = [Path(__file__).resolve(), sdk / "bin/cache/dart-sdk/bin/dart",
         Path(os.environ["CRISP_TOOLCHAIN_ROOT"]) / "env.sh"]
cwd = "."
suites = None
env = os.environ.copy()
# Native hooks remain enabled; bound parallel compilation on this shared host.
env.setdefault("CARGO_BUILD_JOBS", "4")


def manifest(name):
    path = plans / name
    tools.append(path)
    return path, [line.strip() for line in path.read_text().splitlines()
                  if line.strip() and not line.lstrip().startswith("#")]


if args.name.startswith("analysis-"):
    _, files = manifest(args.name + "-files.txt")
    command = ["dart", "analyze", "--fatal-infos", "--fatal-warnings", *files]
    if args.name == "analysis-cli":
        tools.extend(repo / "cli/.dart_tool" / name
                     for name in ("package_config.json", "package_graph.json"))
elif args.name in {"app", "editor", "engine", "host-focus", "ods-geometry", "navigation-capture"}:
    name = "navigation" if args.name == "navigation-capture" else args.name
    suites, paths = manifest(name + "-suites.txt")
    absolute = [str(repo / p) for p in paths]
    if args.name in {"engine", "ods-geometry"}:
        cwd = "packages/quds_office_engine"
        command = ["dart", "test", "--reporter", "json", "--concurrency=2", *absolute]
    else:
        if args.name == "editor":
            cwd = "packages/quds_office_editor"
        tools.extend([sdk / "bin/flutter", sdk / "bin/cache/artifacts/engine/linux-x64/flutter_tester"])
        concurrency = "1" if args.name == "navigation-capture" else "2"
        command = ["flutter", "--no-version-check", "--suppress-analytics", "test",
                   "--no-pub", "--reporter", "json", "--concurrency=" + concurrency, *absolute]
        if args.name == "navigation-capture":
            env["OFFICE_NAVIGATION_PREVIEW"] = "1"
            retained = base / "navigation-prior-build"
            for name in ("office-sheet-navigation-acceptance", "office-sheet-navigation-preview"):
                old = repo / "build" / name
                if old.exists():
                    retained.mkdir(exist_ok=True)
                    if (retained / name).exists():
                        raise SystemExit("prior navigation outputs already retained; use a fresh continuation")
                    shutil.move(str(old), retained / name)
elif args.name == "scripted-oracle":
    driver = repo / "docs/evidence/storage-carving-20261115/local-resume-20261115T1010/run_scripted_oracle.py"
    tools.append(driver)
    command = [sys.executable, str(driver), "--repo", str(repo), "--output", str(base / "scripted-artifacts")]
elif args.name == "source-integrity":
    driver = plans / "run_source_and_notices.py"
    tools.append(driver)
    command = [sys.executable, str(driver), "--repo", str(repo),
               "--quds", str(repo.parent / "QudsCanonical"), "--parser", str(repo.parent / "ParserCanonical"),
               "--output", str(base / "source-integrity-details")]
elif args.name == "png-portable":
    driver = repo / "docs/evidence/storage-carving-20261115/run_portable.py"
    launcher = plans / "toolchain_launcher.sh"
    tools.extend([driver, launcher])
    command = [sys.executable, str(driver), "--repo", str(repo), "--launcher", str(launcher),
               "--output", str(base / "png-portable-artifacts")]
elif args.name == "navigation-independent-review":
    driver = plans / "verify_navigation_capture.py"
    tools.append(driver)
    command = [sys.executable, str(driver), "--repo", str(repo),
               "--capture-receipt", str(base / "navigation-capture"), "--output", str(base / "navigation-artifacts")]
else:
    raise SystemExit("unknown gate: " + args.name)

record = [sys.executable, str(repo / "docs/evidence/storage-carving-20261115/record_gate.py"),
          "--repo", str(repo), "--output", str(output), "--head", head, "--cwd", cwd]
if suites:
    record.extend(["--suites", str(suites)])
for tool in tools:
    record.extend(["--tool", str(tool)])
record.extend(["--", *command])
print("Recording", args.name, "against", head, flush=True)
raise SystemExit(subprocess.run(record, cwd=repo, env=env).returncode)
