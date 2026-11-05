#!/usr/bin/env python3
"""Open XLSX files in Microsoft Excel, save/export, and verify cells.

Staging uses Excel's own sandbox container so macOS does not repeatedly prompt
for folder access. Requires Microsoft Excel, openpyxl, and pdftotext.

Usage:
    ~/miniconda3/bin/python tool/verify_excel_roundtrip.py file.xlsx [...]
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import uuid
from pathlib import Path

try:
    from openpyxl import load_workbook
except ImportError as exc:
    print(
        "Missing openpyxl. Use a Python that has it, for example "
        "~/miniconda3/bin/python.",
        file=sys.stderr,
    )
    raise SystemExit(2) from exc

EXCEL_CONTAINER = (
    Path.home()
    / "Library/Containers/com.microsoft.Excel/Data/tmp/crispcloud-excel-verify"
)


def apple_string(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def run(args: list[str], timeout: int = 120) -> subprocess.CompletedProcess:
    return subprocess.run(
        args, capture_output=True, text=True, timeout=timeout, check=False
    )


def workbook_values(path: Path) -> list[dict[str, object]]:
    wb = load_workbook(path, data_only=False)
    result = []
    for ws in wb.worksheets:
        cells = {}
        for row in ws.iter_rows():
            for cell in row:
                if cell.value is not None:
                    cells[cell.coordinate] = cell.value
        result.append({"title": ws.title, "cells": cells})
    return result


def excel_roundtrip(source: Path, work: Path) -> tuple[Path, Path, int]:
    work.mkdir(parents=True, exist_ok=True)
    key = hashlib.sha256(str(source.resolve()).encode()).hexdigest()[:8]
    run_id = uuid.uuid4().hex[:8]
    stem = source.stem.replace(" ", "_")
    base = f"crispcloud-{stem}-{key}-{run_id}"
    input_name = f"{base}.xlsx"
    output_name = f"{base}-excel.xlsx"
    pdf_name = f"{base}-excel.pdf"
    staged = work / input_name
    output = work / output_name
    pdf = work / pdf_name
    for old in (staged, output, pdf):
        old.unlink(missing_ok=True)
    shutil.copy2(source, staged)

    script = f"""
set inPath to {apple_string(str(staged))}
set outPath to {apple_string(str(output))}
set pdfPath to {apple_string(str(pdf))}
tell application "Microsoft Excel"
  set display alerts to false
  activate
  set wb to open workbook workbook file name inPath
  delay 1
  set sheetCount to count of worksheets of wb
  save workbook as wb filename outPath file format Excel XML file format
  delay 1
  try
    close active workbook saving no
  end try
  set wb2 to open workbook workbook file name outPath
  delay 1
  save workbook as wb2 filename pdfPath file format PDF file format
  delay 1
  try
    close active workbook saving no
  end try
  return sheetCount
end tell
"""
    proc = run(["osascript", "-e", script], timeout=180)
    if proc.returncode != 0:
        raise RuntimeError(f"Excel failed: {proc.stderr.strip()}")
    count = int(proc.stdout.strip() or 0)
    return output, pdf, count


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("xlsx", nargs="+", type=Path)
    parser.add_argument(
        "--out",
        type=Path,
        default=Path("build/excel_verification"),
        help="copy Excel outputs here",
    )
    args = parser.parse_args()
    if sys.platform != "darwin":
        print("This verifier requires macOS and Microsoft Excel.", file=sys.stderr)
        return 2
    if shutil.which("osascript") is None or shutil.which("pdftotext") is None:
        print("Missing osascript or pdftotext", file=sys.stderr)
        return 2

    args.out.mkdir(parents=True, exist_ok=True)
    results = []
    for source in args.xlsx:
        if not source.exists():
            print(f"Not found: {source}", file=sys.stderr)
            return 2
        try:
            staged, pdf, sheet_count = excel_roundtrip(source.resolve(), EXCEL_CONTAINER)
            out_xlsx = args.out / f"{source.stem}-excel.xlsx"
            out_pdf = args.out / f"{source.stem}-excel.pdf"
            shutil.copy2(staged, out_xlsx)
            shutil.copy2(pdf, out_pdf)
            before = workbook_values(source)
            after = workbook_values(out_xlsx)
            text = run(["pdftotext", "-layout", str(out_pdf), "-"]).stdout
            normalized = " ".join(text.split())
            checks = {
                "excel_opened": True,
                "sheet_count_matches": sheet_count == len(before),
                "sheet_names_match": [s["title"] for s in before]
                == [s["title"] for s in after],
                "cell_values_and_formulas_match": [s["cells"] for s in before]
                == [s["cells"] for s in after],
                "pdf_has_cell_text": all(
                    str(value) in normalized
                    for sheet in before
                    for value in sheet["cells"].values()
                    if isinstance(value, str) and not value.startswith("=")
                ),
            }
            ok = all(checks.values())
            results.append(
                {
                    "source": str(source),
                    "excel_xlsx": str(out_xlsx),
                    "excel_pdf": str(out_pdf),
                    "checks": checks,
                    "ok": ok,
                }
            )
            print(f"{'PASS' if ok else 'FAIL'}  {source}")
            for name, passed in checks.items():
                print(f"  {'✓' if passed else '✗'} {name}")
        except Exception as exc:
            print(f"FAIL  {source}: {exc}")
            results.append({"source": str(source), "ok": False, "error": str(exc)})

    report = args.out / "report.json"
    report.write_text(json.dumps(results, indent=2, ensure_ascii=False))
    print(f"\nReport: {report}")
    return 0 if all(r.get("ok") for r in results) else 1


if __name__ == "__main__":
    sys.exit(main())
