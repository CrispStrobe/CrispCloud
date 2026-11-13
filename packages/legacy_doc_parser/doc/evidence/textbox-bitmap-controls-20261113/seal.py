#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Seal original bitmap observations, portable controls and exact build inputs."""
import hashlib
import io
import json
from pathlib import Path
import tarfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
WORKSPACE = ROOT.parent


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def main():
    payloads, observations = {}, {}
    for number in range(1, 5):
        prefix = f"probe-{number}"
        source = WORKSPACE / f"textbox-next-bitmap-probe-{number}"
        for path in sorted(source.rglob("*")):
            relative = path.relative_to(source)
            if (not path.is_file() or "profile" in relative.parts or
                    path.name in ("baseline-convert", "candidate-convert")):
                continue
            name = relative.as_posix()
            key = name if relative.parts[0] == "build-sources" else f"{prefix}/{name}"
            raw = path.read_bytes()
            if key in payloads and payloads[key] != raw:
                raise ValueError("Conflicting retained source bytes: " + key)
            payloads[key] = raw
        report = json.loads(payloads[f"{prefix}/report.json"])
        if report["status"] != "complete":
            raise ValueError("Native observation is not complete")
        observations[prefix] = report
        for build in report["builds"].values():
            for expected in build["sources"]["files"].values():
                if sha(payloads[f"build-sources/{expected}"]) != expected:
                    raise ValueError("Build source bytes differ")
    for path in sorted((WORKSPACE / "textbox-bitmap-schema-cases-1").iterdir()):
        payloads[f"portable/schema-cases/{path.name}"] = path.read_bytes()
    for name in ("textbox-bitmap-schema-validation-1.json",
                 "textbox-bitmap-schema-validation-2.json",
                 "textbox-bitmap-focused-tests.log"):
        payloads[f"portable/{name}"] = (WORKSPACE / name).read_bytes()
    summary = {
        "schema": "legacy-doc-parser/textbox-bitmap-evidence", "version": 1,
        "scope": "Runs 1-3 retain original exploratory build identities based on 9c02110. Run 4 measures clean remote 237509e6. Source-controlled DIB patterns preserve original native exports and FSPA coordinates. All exact build inputs were retained at measurement time.",
        "runs": {name: {"status": report["status"], "cases": [
            {key: case[key] for key in ("id", "sourceSha256", "binarySha256", "nativeExportSha256", "binaryPath", "sourceControl", "authoredToBinary", "baselineAgainstBinary", "candidateAgainstBinary", "candidateAgainstAuthored", "cycles") if key in case}
            for case in report["cases"]]} for name, report in observations.items()},
        "initialObservations": sum(len(report["cases"]) for report in observations.values()),
        "repeatCycles": sum(len(case["cycles"]) for report in observations.values() for case in report["cases"]),
    }
    summary_raw = (json.dumps(summary, indent=2, sort_keys=True) + "\n").encode()
    (HERE / "summary.json").write_bytes(summary_raw)
    archive = HERE / "native-artifacts.tar.xz"
    entries = []
    with tarfile.open(archive, "w:xz", preset=9) as retained:
        for name, raw in sorted(payloads.items()):
            member = tarfile.TarInfo(name)
            member.size = len(raw)
            member.mode = 0o644
            member.mtime = member.uid = member.gid = 0
            retained.addfile(member, io.BytesIO(raw))
            entries.append({"path": name, "bytes": len(raw), "sha256": sha(raw)})
    raw = archive.read_bytes()
    manifest = {
        "schema": "legacy-doc-parser/textbox-bitmap-artifacts", "version": 1,
        "archive": {"path": archive.name, "bytes": len(raw), "sha256": sha(raw)},
        "summarySha256": sha(summary_raw), "files": entries,
        "comparisonHelperSha256": sha((ROOT / "tool/fidelity/goldens.py").read_bytes()),
        "supportFiles": {path.name: sha(path.read_bytes()) for path in sorted(HERE.iterdir())
                         if path.is_file() and path.name not in
                         ("manifest.json", "native-artifacts.tar.xz", "summary.json")},
    }
    (HERE / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"files": len(entries), "archive": manifest["archive"]}))


if __name__ == "__main__":
    main()
