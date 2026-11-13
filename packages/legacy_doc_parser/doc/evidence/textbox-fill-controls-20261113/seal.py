#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Seal the original scaled-gradient observations and exact build inputs."""
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tarfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
WORKSPACE = ROOT.parent


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def source_bytes(name, expected, candidate):
    root = ROOT if candidate else WORKSPACE / "parser-evidence"
    raw = (root / name).read_bytes()
    if sha(raw) == expected:
        return raw
    # Once sealed, historical build inputs are available independently of
    # later working-tree changes. Reuse only bytes matching the original hash.
    existing = HERE / "native-artifacts.tar.xz"
    if existing.exists():
        with tarfile.open(existing, "r:xz") as retained:
            try:
                prior = retained.extractfile(f"build-sources/{expected}").read()
            except KeyError:
                prior = None
        if prior is not None and sha(prior) == expected:
            return prior
    if name == "tool/fidelity/textbox_paint_probe.py":
        raw = subprocess.check_output(["git", "show", "ae8a938b8aae13fa9268e171afeb886836268f69:" + name], cwd=ROOT)
    elif name == "tool/fidelity/textbox_fill_probe.py":
        text = raw.decode().replace("import json\n", "")
        start = text.index("GRADIENT_PROPERTIES = {")
        end = text.index("\ndef png(", start)
        text = text[:start].rstrip("\n") + "\n\n\n" + text[end + 1:]
        text = text.replace("    probe.PREPARE_BINARY = prepare_binary\n", "")
        raw = text.encode()
    if sha(raw) != expected:
        raise RuntimeError(f"Cannot recover exact source bytes: {name}: {expected}")
    return raw


def main():
    payloads, observations = {}, {}
    for number in range(1, 4):
        prefix = f"probe-{number}"
        source = WORKSPACE / f"textbox-next-fill-probe-{number}"
        for path in sorted(source.rglob("*")):
            relative = path.relative_to(source)
            if not path.is_file() or "profile" in relative.parts or path.name in ("baseline-convert", "candidate-convert"):
                continue
            payloads[f"{prefix}/{relative.as_posix()}"] = path.read_bytes()
        report = json.loads(payloads[f"{prefix}/report.json"])
        if report["status"] != "complete":
            raise RuntimeError("Native observation is not complete")
        observations[prefix] = report
        for label, build in report["builds"].items():
            for name, expected in build["sources"]["files"].items():
                payloads[f"build-sources/{expected}"] = source_bytes(name, expected, label == "candidate")
    summary = {
        "schema": "legacy-doc-parser/textbox-gradient-evidence", "version": 1,
        "scope": "Source-hashed exploratory builds based on ae8a938b; original working-tree identities are retained. Probe 1 exposes native DOC export flattening; probes 2 and 3 use separately retained source FOPT controls.",
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
    manifest = {"schema": "legacy-doc-parser/textbox-gradient-artifacts", "version": 1,
                "archive": {"path": archive.name, "bytes": len(raw), "sha256": sha(raw)},
                "summarySha256": sha(summary_raw), "files": entries,
                "comparisonHelperSha256": sha((ROOT / "tool/fidelity/goldens.py").read_bytes())}
    (HERE / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"files": len(entries), "archive": manifest["archive"]}))


if __name__ == "__main__":
    main()
