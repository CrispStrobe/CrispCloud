#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Seal completed paint diagnostics, including the rejected setup run."""
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
    payloads, reports = {}, {}
    for number in range(1, 5):
        source = WORKSPACE / f"textbox-next-paint-probe-{number}"
        prefix = f"probe-{number}"
        for path in sorted(source.rglob("*")):
            relative = path.relative_to(source)
            if not path.is_file() or "profile" in relative.parts or path.name in ("baseline-convert", "candidate-convert"):
                continue
            payloads[f"{prefix}/{relative.as_posix()}"] = path.read_bytes()
        report = json.loads(payloads[f"{prefix}/report.json"])
        reports[prefix] = report
        for label, build in report.get("builds", {}).items():
            base = ROOT if label == "candidate" else WORKSPACE / "parser-evidence"
            for name, expected in build["sources"]["files"].items():
                raw = (base / name).read_bytes()
                if sha(raw) != expected and name == "tool/fidelity/textbox_paint_probe.py":
                    text = raw.decode()
                    text = text.replace('"shadow-enabled": \'<v:shadow on="t" type="single" color="#445566" opacity="65536f" offset="4pt,6pt"/>\',\n    "shadow-translucent":', '"shadow-enabled":')
                    raw = text.encode()
                if sha(raw) != expected and name == "lib/src/word_textbox_writer.dart":
                    text = raw.decode().replace(
                        "        (shape.shadow?.type ?? 0) != 0 ||",
                        "        (line?.dash ?? 0) != 0 ||\n        shape.shadow?.enabled == true ||",
                    ).replace(
                        "    // Dashing and a simple offset shadow do not change the border's outside\n    // thickness. Binary placement is in whole twips. The outer half of an\n    // odd-width border is truncated in that source space, e.g. 15 -> 7.",
                        "    // Binary placement is in whole twips. The outer half of an odd-width\n    // border is truncated in that source coordinate space, e.g. 15 -> 7.",
                    )
                    raw = text.encode()
                if sha(raw) != expected:
                    raise RuntimeError(f"Cannot reproduce {prefix}/{label}/{name}")
                payloads[f"build-sources/{expected}"] = raw
    summary = {
        "schema": "legacy-doc-parser/textbox-paint-evidence", "version": 1,
        "publishedRuntime": "33240acea1927a93a8c6022c507e7be26290f8b5",
        "scope": "Exploratory source-hashed builds based on 4518f43; reports retain original dirty-worktree identities. Publishing the reviewed implementation later does not relabel those executions as clean runs.",
        "runs": {
            name: {"status": report["status"], "error": report.get("error"),
                   "cases": [{"id": row["id"], "sourceSha256": row["sourceSha256"],
                              "binarySha256": row.get("binarySha256"),
                              "authoredToBinary": row.get("authoredToBinary"),
                              "baselineAgainstBinary": row.get("baselineAgainstBinary"),
                              "candidateAgainstBinary": row.get("candidateAgainstBinary"),
                              "cycles": row["cycles"]} for row in report["cases"]]}
            for name, report in reports.items()
        },
        "completedRuns": sum(r["status"] == "complete" for r in reports.values()),
        "retainedSetupFailures": sum(r["status"] == "error" for r in reports.values()),
        "completedInitialCases": sum(len(r["cases"]) for r in reports.values()),
        "completedRepeatCycles": sum(len(c["cycles"]) for r in reports.values() for c in r["cases"]),
    }
    summary_raw = (json.dumps(summary, indent=2, sort_keys=True) + "\n").encode()
    (HERE / "summary.json").write_bytes(summary_raw)
    archive = HERE / "paint-diagnostics.tar.xz"
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
    manifest = {"schema": "legacy-doc-parser/textbox-paint-artifacts", "version": 1,
                "archive": {"path": archive.name, "bytes": len(raw), "sha256": sha(raw)},
                "summarySha256": sha(summary_raw), "files": entries,
                "comparisonHelperSha256": sha((ROOT / "tool/fidelity/goldens.py").read_bytes())}
    (HERE / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"files": len(entries), "archive": manifest["archive"], "runs": len(reports)}))


if __name__ == "__main__":
    main()
