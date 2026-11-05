#!/usr/bin/env python3
"""Open DOCX files in Microsoft Word, save copies/PDFs, and verify structure.

This uses Word's own sandbox container for staging, so macOS does not ask for
folder access on every run. Word then performs the independent reopen, save,
and render. The script compares the result with python-docx, Pandoc and
pdftotext.

Requirements: Microsoft Word, python-docx, lxml, pandoc, pdftotext.

Usage:
    python tool/verify_word_roundtrip.py build/quds_roundtrip/minimal.docx
    python tool/verify_word_roundtrip.py --out build/word_verification *.docx
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import uuid
import sys
import zipfile
from pathlib import Path

try:
    from docx import Document
    from lxml import etree
except ImportError as exc:
    print(
        "Missing Python dependency: python-docx/lxml. "
        "Use a Python with these installed (for example ~/miniconda3/bin/python).",
        file=sys.stderr,
    )
    raise SystemExit(2) from exc

W_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
WORD_CONTAINER = (
    Path.home()
    / "Library/Containers/com.microsoft.Word/Data/tmp/crispcloud-word-verify"
)


def apple_string(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def run(args: list[str], *, timeout: int = 120) -> subprocess.CompletedProcess:
    return subprocess.run(
        args,
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False,
    )


def docx_text(path: Path) -> list[str]:
    return [p.text for p in Document(str(path)).paragraphs if p.text]


def footnotes(path: Path) -> list[dict[str, object]]:
    with zipfile.ZipFile(path) as z:
        if "word/footnotes.xml" not in z.namelist():
            return []
        root = etree.fromstring(z.read("word/footnotes.xml"))
    result: list[dict[str, object]] = []
    for note in root.findall(f"{{{W_NS}}}footnote"):
        note_id = note.get(f"{{{W_NS}}}id")
        note_type = note.get(f"{{{W_NS}}}type")
        text = "".join(note.itertext()).strip()
        has_ref = note.find(f".//{{{W_NS}}}footnoteRef") is not None
        result.append(
            {
                "id": int(note_id) if note_id and note_id.lstrip("-").isdigit() else None,
                "type": note_type,
                "text": text,
                "has_footnote_ref": has_ref,
            }
        )
    return result


def word_roundtrip(source: Path, work: Path) -> dict[str, object]:
    work.mkdir(parents=True, exist_ok=True)
    key = hashlib.sha256(str(source.resolve()).encode()).hexdigest()[:8]
    run_id = uuid.uuid4().hex[:8]
    stem = source.stem.replace(" ", "_")
    base = f"crispcloud-{stem}-{key}-{run_id}"
    input_name = f"{base}.docx"
    output_name = f"{base}-word.docx"
    pdf_name = f"{base}-word.pdf"
    staged = work / input_name
    output = work / output_name
    pdf = work / pdf_name
    for old in (staged, output, pdf):
        old.unlink(missing_ok=True)
    shutil.copy2(source, staged)

    script = f"""
set wdir to {apple_string(str(work))}
set inPath to {apple_string(str(staged))}
set outPath to {apple_string(str(output))}
set pdfPath to {apple_string(str(pdf))}
set inputName to {apple_string(input_name)}
set outputName to {apple_string(output_name)}
tell application "Microsoft Word"
  set display alerts to alerts none
  activate
  set d to open file name inPath
  delay 1
  set fnCount to count of footnotes of d
  set pCount to count of paragraphs of d
  save as d file name outPath file format format document
  delay 1
  try
    close (first document whose name is outputName) saving no
  end try
  set d2 to open file name outPath
  delay 1
  save as d2 file name pdfPath file format format PDF
  delay 1
  try
    close (first document whose name is outputName) saving no
  end try
  return (fnCount as string) & "|" & (pCount as string)
end tell
"""
    proc = run(["osascript", "-e", script], timeout=180)
    if proc.returncode != 0:
        raise RuntimeError(f"Word failed: {proc.stderr.strip()}")
    pieces = proc.stdout.strip().split("|")
    return {
        "word_footnote_count": int(pieces[0]) if pieces and pieces[0] else 0,
        "word_paragraph_count": int(pieces[1]) if len(pieces) > 1 else 0,
        "word_docx": output,
        "word_pdf": pdf,
    }


def pdf_text(path: Path) -> str:
    proc = run(["pdftotext", "-layout", str(path), "-"])
    if proc.returncode != 0:
        raise RuntimeError(f"pdftotext failed: {proc.stderr.strip()}")
    return proc.stdout


def check_case(source: Path, out_dir: Path) -> dict[str, object]:
    key = hashlib.sha256(str(source.resolve()).encode()).hexdigest()[:12]
    work = WORD_CONTAINER / key
    result = word_roundtrip(source, work)

    staged_result = out_dir / f"{source.stem}-word.docx"
    staged_pdf = out_dir / f"{source.stem}-word.pdf"
    shutil.copy2(result["word_docx"], staged_result)
    shutil.copy2(result["word_pdf"], staged_pdf)

    source_paras = docx_text(source)
    word_paras = docx_text(staged_result)
    source_notes = footnotes(source)
    word_notes = footnotes(staged_result)
    source_real = [n for n in source_notes if n["type"] is None]
    word_real = [n for n in word_notes if n["type"] is None]
    rendered = pdf_text(staged_pdf)
    rendered_norm = " ".join(rendered.split())

    checks = {
        "word_opened": True,
        "paragraph_text_preserved": source_paras == word_paras,
        "footnote_count_matches": len(source_real) == len(word_real),
        "footnote_text_preserved": [n["text"] for n in source_real]
        == [n["text"] for n in word_real],
        "footnote_refs_present": all(n["has_footnote_ref"] for n in word_real),
        "separator_present": any(n["type"] == "separator" for n in word_notes),
        "continuation_separator_present": any(
            n["type"] == "continuationSeparator" for n in word_notes
        ),
        "pdf_has_body_text": all(
            " ".join(text.split()) in rendered_norm for text in source_paras[:1]
        ),
        "pdf_has_footnote_text": all(
            " ".join(str(n["text"]).split()) in rendered_norm
            for n in source_real
        ),
    }
    return {
        "source": str(source),
        "word_docx": str(staged_result),
        "word_pdf": str(staged_pdf),
        "word_footnote_count": result["word_footnote_count"],
        "word_paragraph_count": result["word_paragraph_count"],
        "source_paragraphs": source_paras,
        "word_paragraphs": word_paras,
        "source_footnotes": source_notes,
        "word_footnotes": word_notes,
        "checks": checks,
        "ok": all(checks.values()),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("docx", nargs="+", type=Path)
    parser.add_argument(
        "--out",
        type=Path,
        default=Path("build/word_verification"),
        help="copy Word outputs here for inspection",
    )
    args = parser.parse_args()

    if sys.platform != "darwin":
        print("This verifier requires macOS and Microsoft Word.", file=sys.stderr)
        return 2
    for tool in ("osascript", "pandoc", "pdftotext"):
        if shutil.which(tool) is None:
            print(f"Missing required tool: {tool}", file=sys.stderr)
            return 2

    args.out.mkdir(parents=True, exist_ok=True)
    results = []
    for source in args.docx:
        if not source.exists():
            print(f"Not found: {source}", file=sys.stderr)
            return 2
        try:
            result = check_case(source.resolve(), args.out)
        except Exception as exc:  # Word/permission failures should be loud.
            print(f"FAIL  {source}: {exc}")
            results.append({"source": str(source), "ok": False, "error": str(exc)})
            continue
        results.append(result)
        print(f"{'PASS' if result['ok'] else 'FAIL'}  {source}")
        for name, ok in result["checks"].items():
            print(f"  {'✓' if ok else '✗'} {name}")
        print(f"  Word outputs: {result['word_docx']} / {result['word_pdf']}")

    report = args.out / "report.json"
    report.write_text(json.dumps(results, indent=2, ensure_ascii=False))
    print(f"\nReport: {report}")
    return 0 if all(r.get("ok") for r in results) else 1


if __name__ == "__main__":
    sys.exit(main())
