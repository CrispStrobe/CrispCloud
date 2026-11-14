#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Render every successful external-corpus conversion using isolated LibreOffice."""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import json
from pathlib import Path
import subprocess

from run import office_convert


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--parser-output", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--office", default="soffice")
    parser.add_argument("--workers", type=int, choices=range(1, 5), default=3)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    probe = json.loads((args.parser_output / "report.json").read_text())
    jobs = []
    for case in probe["cases"]:
        for mode in ("preserve", "cachedResults"):
            stage = case.get("result", {}).get("stages", {}).get("convert-" + mode, {})
            if stage.get("status") == "ok":
                source = args.parser_output / Path(case["name"]).stem / stage["output"]
                jobs.append((case["name"], mode, source.resolve()))
    report = {"version": 1, "oracle": subprocess.check_output([args.office, "--version"], text=True, timeout=10).strip(),
              "expectedRenders": len(jobs), "macroAndLinkExecution": False, "cases": []}

    def render(name, mode, source):
        digest = hashlib.sha256(source.read_bytes()).hexdigest()
        case = {"name": name, "mode": mode, "sourceSha256": digest}
        try:
            pdf = office_convert(args.office, source, output / Path(name).stem / mode, "pdf")
            text = pdf.with_suffix(".txt")
            subprocess.run(["pdftotext", "-layout", str(pdf), str(text)], capture_output=True, check=True, timeout=20)
            info = subprocess.run(["pdfinfo", str(pdf)], capture_output=True, text=True, check=True, timeout=20).stdout
            (pdf.parent / "pdfinfo.txt").write_text(info)
            case.update(status="ok", path=str(pdf.relative_to(output)),
                        pdfSha256=hashlib.sha256(pdf.read_bytes()).hexdigest(),
                        textSha256=hashlib.sha256(text.read_bytes()).hexdigest(),
                        pages=int(next(line.split(":", 1)[1] for line in info.splitlines() if line.startswith("Pages:"))))
        except Exception as error:
            case.update(status="error", error=str(error))
        case["sourceUnchanged"] = hashlib.sha256(source.read_bytes()).hexdigest() == digest
        return case

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        for future in as_completed([pool.submit(render, *job) for job in jobs]):
            case = future.result()
            report["cases"].append(case)
            report["cases"].sort(key=lambda item: (item["name"], item["mode"]))
            (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
            print(case["name"], case["mode"], case["status"], flush=True)
    report["counts"] = {"total": len(jobs), "ok": sum(c["status"] == "ok" for c in report["cases"])}
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    return int(any(c["status"] != "ok" or not c["sourceUnchanged"] for c in report["cases"]))


if __name__ == "__main__":
    raise SystemExit(main())
