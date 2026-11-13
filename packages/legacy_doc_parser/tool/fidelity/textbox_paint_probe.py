#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Measure independently authored textbox paints against exact DOC bytes.

Runs one native case at a time, retaining original, binary, baseline and
candidate renders separately. No source fixture or golden is overwritten.
"""

import argparse
import hashlib
import json
from pathlib import Path

from authored_cases import package
from goldens import compare_render
from run import command, digest, office_convert, render, source_receipt, tool_receipt


ROOT = Path(__file__).resolve().parents[2]
CASES = {
    "plain": "",
    "fill-half": '<v:fill opacity="32768f"/>',
    "fill-zero": '<v:fill opacity="0f"/>',
    "line-half": '<v:stroke opacity="32768f"/>',
    "dashed": '<v:stroke dashstyle="shortdash"/>',
    "shadow-enabled": '<v:shadow on="t" type="single" color="#445566" opacity="65536f" offset="4pt,6pt"/>',
    "shadow-translucent": '<v:shadow on="t" type="single" color="#445566" opacity="32768f" offset="4pt,6pt"/>',
    "shadow-disabled": '<v:shadow on="f" type="single" color="#445566" opacity="32768f" offset="4pt,6pt"/>',
}
PREPARE_BINARY = None


def write(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def authored(paint):
    return '''<w:p><w:r><w:t>Textbox paint control</w:t></w:r><w:r><w:pict>
<v:rect id="_x0000_s1025" o:spid="_x0000_s1025" style="position:absolute;margin-left:72pt;margin-top:144pt;width:180pt;height:72pt;mso-position-horizontal-relative:page;mso-position-vertical-relative:page;z-index:1" fillcolor="#6699CC" strokecolor="#993366" strokeweight="2pt">''' + paint + '''
<v:textbox inset="7.2pt,3.6pt,7.2pt,3.6pt" style="v-text-anchor:top;mso-fit-shape-to-text:f"><w:txbxContent><w:p><w:r><w:t>Editable textbox paint</w:t></w:r></w:p></w:txbxContent></v:textbox>
<w10:wrap type="none" anchorx="page" anchory="page"/></v:rect></w:pict></w:r></w:p>'''


def compile_converter(root, destination, dart):
    before = source_receipt(root)
    # Retain exact inputs at measurement time, including uncommitted versions.
    # Later evidence packing must not depend on a still-unchanged worktree.
    snapshots = destination.parent / "build-sources"
    snapshots.mkdir(exist_ok=True)
    for name, expected in before["files"].items():
        raw = (root / name).read_bytes()
        if hashlib.sha256(raw).hexdigest() != expected:
            raise RuntimeError("Build input changed while retaining source: " + name)
        target = snapshots / expected
        if target.exists():
            if target.read_bytes() != raw:
                raise RuntimeError("Retained source hash collision")
        else:
            target.write_bytes(raw)
    identity = {
        "commit": command(["git", "rev-parse", "HEAD"], cwd=root).strip(),
        "tree": command(["git", "rev-parse", "HEAD^{tree}"], cwd=root).strip(),
        "workingTree": command(["git", "status", "--porcelain"], cwd=root).splitlines(),
        "sources": before,
    }
    argv = [dart, "compile", "exe", "tool/fidelity/convert.dart", "-o", destination]
    identity["compileCommand"] = [str(x) for x in argv]
    log = command(argv, cwd=root)
    destination.with_suffix(".log").write_text(log)
    after = source_receipt(root)
    identity.update(executableSha256=digest(destination), sourcesUnchanged=after == before)
    if after != before:
        identity["sourcesAfterCompilation"] = after
    write(destination.with_suffix(".build.json"), identity)
    if after != before:
        raise RuntimeError("Build inputs changed during compilation")
    return identity


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dart", required=True, type=Path)
    parser.add_argument("--office", required=True, type=Path)
    parser.add_argument("--baseline-parser", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--case", action="append", choices=sorted(CASES))
    parser.add_argument("--roundtrip-cycles", type=int, choices=range(4), default=0)
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    fonts = command(["fc-list", "--format", "%{family}|%{style}|%{file}\n"])
    (out / "fonts.txt").write_text(fonts)
    font_files = {name: digest(Path(name)) for name in sorted({line.rsplit("|", 1)[-1] for line in fonts.splitlines()})}
    write(out / "font-files.json", font_files)
    report = {
        "schema": "legacy-doc-parser/textbox-paint-probe", "version": 1,
        "method": "Independent authored OOXML, native DOC bridge, two parser builds, and candidate repeats; 72-DPI lossless RGB; sequential cases.",
        "status": "running", "roundtripCycles": args.roundtrip_cycles,
        "tools": {"dart": tool_receipt(args.dart), "office": tool_receipt(args.office),
                  **{name: tool_receipt(name, ("-v",)) for name in ("pdfinfo", "pdftoppm", "pdftotext")}},
        "fontInventorySha256": hashlib.sha256("\n".join(sorted(fonts.splitlines())).encode()).hexdigest(),
        "fontFilesSha256": digest(out / "font-files.json"), "cases": [],
    }
    write(out / "report.json", report)
    try:
        builds = {}
        for label, root in [("baseline", args.baseline_parser.resolve()), ("candidate", ROOT)]:
            builds[label] = compile_converter(root, out / (label + "-convert"), args.dart)
        report["builds"] = builds
        write(out / "report.json", report)
        for name in args.case or CASES:
            directory = out / name
            directory.mkdir()
            source = directory / "authored.docx"
            package(source, authored(CASES[name]))
            row = {"id": name, "sourceSha256": digest(source), "status": "running", "renders": {}, "cycles": []}
            report["cases"].append(row)
            write(out / "report.json", report)
            def measure(label, path):
                result = render(args.office, path, directory / label, 72, raster_storage="gzip")
                write(directory / (label + "-render.json"), result)
                row["renders"][label] = result
                write(out / "report.json", report)
                return result
            original = measure("original", source)
            binary = office_convert(args.office, source, directory / "binary", "doc")
            if PREPARE_BINARY is not None:
                row["nativeExportSha256"] = digest(binary)
                binary, row["sourceControl"] = PREPARE_BINARY(args, name, binary, directory)
            row["binaryPath"] = binary.relative_to(directory).as_posix()
            row["binarySha256"] = digest(binary)
            binary_render = measure("binary-render", binary)
            row["authoredToBinary"] = compare_render(original, binary_render)
            for label in ("baseline", "candidate"):
                converted = directory / (label + ".docx")
                row[label + "Converter"] = json.loads(command([out / (label + "-convert"), binary, converted]))
                observed = measure(label, converted)
                row[label + "AgainstBinary"] = compare_render(binary_render, observed)
                row[label + "AgainstAuthored"] = compare_render(original, observed)
            first = previous = row["renders"]["candidate"]
            previous_docx = directory / "candidate.docx"
            for index in range(1, args.roundtrip_cycles + 1):
                label = f"repeat-{index:02d}"
                repeated_binary = office_convert(args.office, previous_docx, directory / (label + "-doc"), "doc")
                repeated_binary_render = measure(label + "-binary", repeated_binary)
                repeated_docx = directory / (label + ".docx")
                converter = json.loads(command([out / "candidate-convert", repeated_binary, repeated_docx]))
                repeated_render = measure(label + "-converted", repeated_docx)
                row["cycles"].append({"index": index, "converter": converter,
                    "binarySha256": digest(repeated_binary), "docxSha256": digest(repeated_docx),
                    "againstBinary": compare_render(repeated_binary_render, repeated_render),
                    "againstPrevious": compare_render(previous, repeated_render),
                    "againstFirst": compare_render(first, repeated_render)})
                previous, previous_docx = repeated_render, repeated_docx
            if digest(source) != row["sourceSha256"] or digest(binary) != row["binarySha256"]:
                raise RuntimeError("Source input changed during measurement")
            row.update(status="complete", inputsUnchanged=True)
            write(directory / "result.json", row)
            write(out / "report.json", report)
            print(json.dumps({"case": name, "baseline": row["baselineAgainstBinary"], "candidate": row["candidateAgainstBinary"]}), flush=True)
        for label, root in [("baseline", args.baseline_parser.resolve()), ("candidate", ROOT)]:
            if source_receipt(root) != builds[label]["sources"]:
                raise RuntimeError("Build inputs changed during measurement")
        report.update(status="complete", sourceInputsUnchanged=True)
    except Exception as error:
        report.update(status="error", errorType=type(error).__name__, error=str(error))
        raise
    finally:
        write(out / "report.json", report)


if __name__ == "__main__":
    if not __debug__:
        raise SystemExit("Run the inherited render/comparison helpers with normal Python, without optimization.")
    main()
