#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Run pinned Apache POI or isolated LibreOffice against the external corpus.

These observations are independent oracles, not declarations that either reader
is canonical. Every manifest member remains in the report, including failures.
The command exits nonzero if an oracle fails, a source changes, or a timeout
occurs. Apache POI intentionally rejects the deep-table-cell depth-limit fixture.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import json
import os
from pathlib import Path
import subprocess
import urllib.request

from run import office_convert

ROOT = Path(__file__).resolve().parents[2]
DEPENDENCIES = Path(__file__).with_name("poi-oracle-dependencies.json")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def corpus_files(corpus: Path) -> list[tuple[dict, Path]]:
    manifest = json.loads((corpus / "manifest.json").read_text())
    result = []
    identities = set()
    for case in manifest["files"]:
        path = (corpus / case["path"]).resolve()
        if not path.is_relative_to(corpus.resolve()) or case["id"] in identities:
            raise ValueError("Invalid or duplicate corpus identity")
        identities.add(case["id"])
        if path.stat().st_size != case["bytes"] or sha256(path) != case["sha256"]:
            raise ValueError(f"Corpus checksum mismatch: {case['path']}")
        result.append((case, path))
    if len(result) != 88:
        raise ValueError("The pinned external corpus must contain exactly 88 files")
    return result


def poi_classpath(cache: Path, output: Path, java: str) -> tuple[str, dict]:
    pins = json.loads(DEPENDENCIES.read_text())
    cache.mkdir(parents=True, exist_ok=True)
    jars = []
    for artifact in pins["artifacts"]:
        name = f"{artifact['artifact']}-{artifact['version']}.jar"
        path = cache / name
        if not path.exists():
            if not artifact["url"].startswith("https://repo.maven.apache.org/maven2/"):
                raise ValueError("Unexpected Maven artifact origin")
            with urllib.request.urlopen(artifact["url"], timeout=30) as response:
                data = response.read(artifact["bytes"] + 1)
            if len(data) != artifact["bytes"] or hashlib.sha256(data).hexdigest() != artifact["sha256"]:
                raise ValueError(f"Downloaded dependency checksum mismatch: {name}")
            path.write_bytes(data)
        if path.stat().st_size != artifact["bytes"] or sha256(path) != artifact["sha256"]:
            raise ValueError(f"Cached dependency checksum mismatch: {name}")
        jars.append(str(path.resolve()))
    classes = output / "classes"
    classes.mkdir()
    source = Path(__file__).with_name("ExternalWordOracle.java")
    # jdk.compiler works on installations that expose java but no javac binary.
    command = [java, "--module", "jdk.compiler/com.sun.tools.javac.Main",
               "-classpath", os.pathsep.join(jars), "-d", str(classes), str(source)]
    compiled = subprocess.run(command, capture_output=True, text=True, timeout=60)
    (output / "compile.log").write_text(compiled.stdout + compiled.stderr)
    compiled.check_returncode()
    return os.pathsep.join([str(classes.resolve()), *jars]), {
        "dependencies": pins,
        "sourceSha256": sha256(source),
        "javaVersion": subprocess.run([java, "-version"], capture_output=True,
                                       text=True, check=True, timeout=10).stderr,
    }


def poi_case(case: dict, path: Path, output: Path, java: str, classpath: str) -> dict:
    target = output / (case["id"] + ".json")
    command = [java, "-Xmx256m", "-cp", classpath,
               "ExternalWordOracle", str(path), str(target)]
    run = subprocess.run(command, capture_output=True, text=True, timeout=30)
    (output / (case["id"] + ".stderr.log")).write_text(run.stderr)
    result = json.loads(target.read_text()) if target.exists() else {"status": "missing-output"}
    return {"status": result["status"], "exitCode": run.returncode,
            "output": target.name, "outputSha256": sha256(target) if target.exists() else None,
            "errorType": result.get("errorType"), "error": result.get("error")}


def native_case(case: dict, path: Path, output: Path, office: str) -> dict:
    stages = {}
    for kind in ("docx", "pdf"):
        try:
            target = office_convert(office, path, (output / case["id"] / kind).resolve(), kind)
            stage = {"status": "ok", "path": str(target.relative_to(output)),
                     "bytes": target.stat().st_size, "sha256": sha256(target)}
            if kind == "pdf":
                text = target.with_suffix(".txt")
                run = subprocess.run(["pdftotext", "-layout", str(target), str(text)],
                                     capture_output=True, text=True, timeout=20)
                stage["textExitCode"] = run.returncode
                if run.returncode:
                    stage.update(status="error", error=run.stderr)
                elif text.exists():
                    stage["textSha256"] = sha256(text)
            stages[kind] = stage
        except Exception as error:
            stages[kind] = {"status": "error", "error": str(error)}
    return {"status": "ok" if all(s["status"] == "ok" for s in stages.values()) else "error",
            "stages": stages}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("poi", "native"))
    parser.add_argument("--corpus", type=Path, default=ROOT / "test/fixtures/external/poi-20261114")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--poi-cache", type=Path, default=ROOT / "build/poi-oracle-cache")
    parser.add_argument("--java", default="java")
    parser.add_argument("--office", default="soffice")
    parser.add_argument("--workers", type=int, choices=range(1, 5), default=3)
    args = parser.parse_args()
    files = corpus_files(args.corpus)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    report = {"version": 1, "mode": args.mode, "manifestSha256": sha256(args.corpus / "manifest.json"),
              "cases": [], "macroAndLinkExecution": False}
    classpath = None
    if args.mode == "poi":
        classpath, metadata = poi_classpath(args.poi_cache, output, args.java)
        report.update(oracle="Apache POI 6.0.0", **metadata)
    else:
        files = [(case, path) for case, path in files if path.suffix.lower() == ".doc"]
        report["oracle"] = subprocess.check_output([args.office, "--version"], text=True, timeout=10).strip()

    def run_case(case: dict, path: Path) -> dict:
        record = {"id": case["id"], "path": case["path"], "sourceSha256": case["sha256"]}
        try:
            if args.mode == "poi":
                record.update(poi_case(case, path, output, args.java, classpath))
            else:
                record.update(native_case(case, path, output, args.office))
        except subprocess.TimeoutExpired as error:
            record.update(status="timeout", error=str(error))
        except Exception as error:
            record.update(status="harness-error", error=str(error))
        record["sourceUnchanged"] = sha256(path) == case["sha256"]
        return record

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        for future in as_completed([pool.submit(run_case, case, path) for case, path in files]):
            record = future.result()
            report["cases"].append(record)
            report["cases"].sort(key=lambda case: case["id"])
            (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
            print(record["id"], record["status"], flush=True)
    report["counts"] = {"total": len(files), "ok": sum(c["status"] == "ok" for c in report["cases"])}
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    return int(any(c["status"] != "ok" or not c["sourceUnchanged"] for c in report["cases"]))


if __name__ == "__main__":
    raise SystemExit(main())
