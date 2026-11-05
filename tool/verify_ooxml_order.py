#!/usr/bin/env python3
"""Validate OOXML child order that Word's strict reader enforces.

Word reports packages as corrupt when properties are emitted in the wrong
order even though every XML part parses. This catches the important property
containers without launching Word.

Usage:
    ~/miniconda3/bin/python tool/verify_ooxml_order.py file.docx [...]
"""

from __future__ import annotations

import argparse
import sys
import zipfile
from pathlib import Path

try:
    from lxml import etree
except ImportError as exc:
    print(
        "Missing lxml. Use a Python with lxml, for example "
        "~/miniconda3/bin/python.",
        file=sys.stderr,
    )
    raise SystemExit(2) from exc

W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"

# ECMA-376 CT_PPr and CT_RPr child order. Only the elements CrispCloud emits
# matter here; unknown elements are reported rather than silently ignored.
PPR_ORDER = [
    "pStyle",
    "keepNext",
    "keepLines",
    "pageBreakBefore",
    "framePr",
    "widowControl",
    "numPr",
    "suppressLineNumbers",
    "pBdr",
    "shd",
    "tabs",
    "suppressAutoHyphens",
    "kinsoku",
    "wordWrap",
    "overflowPunct",
    "topLinePunct",
    "autoSpaceDE",
    "autoSpaceDN",
    "bidi",
    "adjustRightInd",
    "snapToGrid",
    "spacing",
    "ind",
    "contextualSpacing",
    "mirrorIndents",
    "suppressOverlap",
    "jc",
    "textDirection",
    "textAlignment",
    "textboxTightWrap",
    "outlineLvl",
    "divId",
    "cnfStyle",
    "rPr",
    "sectPr",
    "pPrChange",
]

RPR_ORDER = [
    "rStyle",
    "rFonts",
    "b",
    "bCs",
    "i",
    "iCs",
    "caps",
    "smallCaps",
    "strike",
    "dstrike",
    "outline",
    "shadow",
    "emboss",
    "imprint",
    "noProof",
    "snapToGrid",
    "vanish",
    "webHidden",
    "color",
    "spacing",
    "w",
    "kern",
    "position",
    "sz",
    "szCs",
    "highlight",
    "u",
    "effect",
    "bdr",
    "shd",
    "fitText",
    "vertAlign",
    "rtl",
    "cs",
    "em",
    "lang",
    "eastAsianLayout",
    "specVanish",
    "oMath",
]


SECTPR_ORDER = [
    "headerReference",
    "footerReference",
    "footnotePr",
    "endnotePr",
    "type",
    "pgSz",
    "pgMar",
    "paperSrc",
    "pgBorders",
    "lnNumType",
    "pgNumType",
    "cols",
    "formProt",
    "vAlign",
    "noEndnote",
    "titlePg",
    "textDirection",
    "bidi",
    "rtlGutter",
    "docGrid",
    "printerSettings",
    "sectPrChange",
]

LVL_ORDER = [
    "start",
    "numFmt",
    "lvlRestart",
    "pStyle",
    "isLgl",
    "suff",
    "lvlText",
    "lvlPicBulletId",
    "legacy",
    "lvlJc",
    "pPr",
    "rPr",
]

NUMBERING_ORDER = ["numPicBullet", "abstractNum", "num", "numIdMacAtCleanup"]

HIGHLIGHT_VALUES = {
    "yellow",
    "green",
    "cyan",
    "magenta",
    "blue",
    "red",
    "darkBlue",
    "darkCyan",
    "darkGreen",
    "darkMagenta",
    "darkRed",
    "darkYellow",
    "darkGray",
    "lightGray",
    "black",
    "white",
}

def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1] if "}" in tag else tag


def check_container(root, container: str, order: list[str]) -> list[str]:
    rank = {name: index for index, name in enumerate(order)}
    issues: list[str] = []
    wanted = f"{{{W}}}{container}"
    for element in root.iter(wanted):
        last = -1
        last_name = ""
        for child in element:
            name = local_name(child.tag)
            if name not in rank:
                issues.append(f"unknown {container} child <{name}>")
                continue
            current = rank[name]
            if current < last:
                issues.append(
                    f"<{name}> after <{last_name}> inside {container}"
                )
            last = current
            last_name = name
    return issues


def check_file(path: Path) -> list[str]:
    issues: list[str] = []
    with zipfile.ZipFile(path) as z:
        for name in z.namelist():
            if not name.endswith(".xml"):
                continue
            if not name.startswith("word/"):
                continue
            try:
                root = etree.fromstring(z.read(name))
            except etree.XMLSyntaxError as exc:
                issues.append(f"{name}: XML parse error: {exc}")
                continue
            for container, order in (
                ("pPr", PPR_ORDER),
                ("rPr", RPR_ORDER),
                ("sectPr", SECTPR_ORDER),
                ("lvl", LVL_ORDER),
                ("numbering", NUMBERING_ORDER),
            ):
                for issue in check_container(root, container, order):
                    issues.append(f"{name}: {issue}")
            for hi in root.iter(f"{{{W}}}highlight"):
                value = hi.get(f"{{{W}}}val", "")
                if value not in HIGHLIGHT_VALUES:
                    issues.append(f"{name}: invalid highlight value {value!r}")
    return issues


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("docx", nargs="+", type=Path)
    args = parser.parse_args()
    failed = False
    for path in args.docx:
        if not path.exists():
            print(f"FAIL  {path}: not found")
            failed = True
            continue
        issues = check_file(path)
        if issues:
            failed = True
            print(f"FAIL  {path}")
            for issue in issues[:40]:
                print(f"  - {issue}")
            if len(issues) > 40:
                print(f"  … {len(issues) - 40} more")
        else:
            print(f"PASS  {path}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
