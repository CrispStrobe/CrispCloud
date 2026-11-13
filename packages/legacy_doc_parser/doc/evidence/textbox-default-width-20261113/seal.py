#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Seal paired source-default width controls and exact build inputs."""
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
    for number in range(1, 3):
        prefix = f"probe-{number}"
        source = WORKSPACE / f"textbox-next-width-probe-{number}"
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
    for name in ("textbox-width-full-tests.log", "textbox-width-word14-model.json",
                 "textbox-width-disabled-source-1.json", "textbox-width-disabled-source-2.json"):
        payloads[f"scope/{name}"] = (WORKSPACE / name).read_bytes()
    helper = ROOT / "doc/evidence/textbox-next-20261113/source_inspect.dart"
    payloads["scope/source_inspect.dart"] = helper.read_bytes()
    original = ROOT / "test/fixtures/word_native/word14-margin-origin.doc"
    payloads["scope/word14-source.json"] = (json.dumps({
        "path": original.relative_to(ROOT).as_posix(), "sha256": sha(original.read_bytes()),
        "bytes": original.stat().st_size, "inspectionHelperSha256": sha(helper.read_bytes()),
        "scope": "Read-only model inspection; no new native Word14 measurement or guard bypass.",
    }, indent=2, sort_keys=True) + "\n").encode()
    summary = {
        "schema": "legacy-doc-parser/textbox-source-default-evidence", "version": 1,
        "scope": "Two original source-hashed candidate runs based on 7356e9a, subsequently published as cc475608. True absent source widths are authored by removing 0x1cb, without inherited remnants or FSPA coordinate changes. The first disabled authoring attempt did not preserve the disabled source flag and remains separately retained. The corrected explicit-false control is unchanged by this runtime candidate.",
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
        "schema": "legacy-doc-parser/textbox-source-default-artifacts", "version": 1,
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
