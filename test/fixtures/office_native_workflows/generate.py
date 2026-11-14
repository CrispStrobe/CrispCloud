#!/usr/bin/env python3
"""Author native host-workflow inputs and independent first-save expectations.

This script never opens a Quds export. Source and expected packages are authored
from the same explicit scenario definitions using raw WordprocessingML,
openpyxl and python-pptx. Expected files are checked in, hashed and immutable
during tests; normal acceptance never invokes this generator.
"""

from datetime import datetime
from hashlib import sha256
from importlib.metadata import version
from io import BytesIO
import json
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

from lxml import etree
from openpyxl import Workbook
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.worksheet.page import PageMargins
from pptx import Presentation
from pptx.util import Inches, Pt


ROOT = Path(__file__).resolve().parent
WORD = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
SHEET = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
RELS = "http://schemas.openxmlformats.org/package/2006/relationships"
OFFICE_RELS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
TYPES = "http://schemas.openxmlformats.org/package/2006/content-types"
STAMP = datetime(2026, 11, 14, 0, 0, 0)


def package(parts: dict[str, bytes | str], path: Path) -> None:
    with ZipFile(path, "w", compression=ZIP_DEFLATED, compresslevel=9) as archive:
        for name, content in sorted(parts.items()):
            item = ZipInfo(name, (2026, 11, 14, 0, 0, 0))
            item.compress_type = ZIP_DEFLATED
            item.external_attr = 0o600 << 16
            archive.writestr(item, content.encode() if isinstance(content, str) else content)


def unpack(data: bytes) -> dict[str, bytes]:
    with ZipFile(BytesIO(data)) as archive:
        return {name: archive.read(name) for name in archive.namelist()}


def fixed_metadata(parts: dict[str, bytes]) -> None:
    if "docProps/core.xml" not in parts:
        return
    root = etree.fromstring(parts["docProps/core.xml"])
    for element in root:
        if etree.QName(element).localname in {"created", "modified"}:
            element.text = "2026-11-14T00:00:00Z"
    parts["docProps/core.xml"] = etree.tostring(root, xml_declaration=True, encoding="UTF-8")


def word(edited: bool) -> dict[str, bytes | str]:
    text = "Reviewed: Native workflow report" if edited else "Native workflow report"
    bold = '<w:b w:val="1"/>' if edited else ""
    indent = '<w:ind w:left="480"/>' if edited else ""
    after = "360" if edited else "160"
    font = '<w:rFonts w:ascii="Liberation Sans" w:hAnsi="Liberation Sans"/>'
    size = '<w:sz w:val="24"/>'
    run = font + size
    edited_run = font + bold + size
    return {
        "[Content_Types].xml": f'''<Types xmlns="{TYPES}">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
</Types>''',
        "_rels/.rels": f'<Relationships xmlns="{RELS}"><Relationship Id="rId1" Type="{OFFICE_RELS}/officeDocument" Target="word/document.xml"/></Relationships>',
        "word/_rels/document.xml.rels": f'<Relationships xmlns="{RELS}"><Relationship Id="rStyles" Type="{OFFICE_RELS}/styles" Target="styles.xml"/></Relationships>',
        "word/styles.xml": f'''<w:styles xmlns:w="{WORD}">
<w:docDefaults><w:rPrDefault><w:rPr>{run}</w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="160" w:line="240" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>
<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>
</w:styles>''',
        "word/document.xml": f'''<w:document xmlns:w="{WORD}"><w:body>
<w:p><w:pPr><w:spacing w:after="{after}" w:line="240" w:lineRule="auto"/>{indent}</w:pPr><w:r><w:rPr>{edited_run}</w:rPr><w:t>{text}</w:t></w:r></w:p>
<w:p><w:pPr><w:spacing w:after="160" w:line="240" w:lineRule="auto"/></w:pPr><w:r><w:rPr>{run}</w:rPr><w:t>Reference paragraph remains unchanged.</w:t></w:r></w:p>
<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>
</w:body></w:document>''',
    }


def sheet(edited: bool) -> dict[str, bytes]:
    book = Workbook()
    book.properties.creator = "Independent host workflow fixture"
    book.properties.created = STAMP
    book.properties.modified = STAMP
    page = book.active
    page.title = "Budget"
    page.append(["Native budget", "Amount"])
    page.append(["Approved travel" if edited else "Travel", 135.5 if edited else 120.5])
    page.append(["Equipment", 300])
    page.append(["Total", "=SUM(B2:B3)"])
    page.append(["Approved for review"])
    page.merge_cells("A5:B5")
    page.column_dimensions["A"].width = 28
    page.column_dimensions["B"].width = 20
    page.row_dimensions[1].height = 28
    page.row_dimensions[2].height = 42
    page.row_dimensions[5].height = 60
    for row in page:
        for cell in row:
            if cell.__class__.__name__ != "MergedCell":
                cell.font = Font(name="Liberation Sans", size=11)
    for cell in page[1]:
        cell.font = Font(name="Liberation Sans", size=12, bold=True)
        cell.fill = PatternFill("solid", fgColor="E6EEF8")
    page["A2"].font = Font(name="Liberation Sans", size=11, italic=True, bold=edited, color="234567")
    page["A2"].alignment = Alignment(horizontal="center" if edited else None, vertical="bottom", wrap_text=True)
    if edited:
        page["A5"].alignment = Alignment(horizontal="center")
    for address in ("B2", "B3", "B4"):
        page[address].number_format = "0.00"
    page.print_area = "A1:B5"
    page.page_setup.orientation = "portrait"
    page.page_setup.paperSize = page.PAPERSIZE_A4
    page.page_setup.fitToWidth = 1
    page.page_setup.fitToHeight = 0
    page.sheet_properties.pageSetUpPr.fitToPage = True
    page.page_margins = PageMargins(left=.5, right=.5, top=.5, bottom=.5, header=.2, footer=.2)
    output = BytesIO()
    book.save(output)
    parts = unpack(output.getvalue())
    # The authored cached total is independent of any Quds evaluation.
    xml = etree.fromstring(parts["xl/worksheets/sheet1.xml"])
    xml.find(f'.//{{{SHEET}}}c[@r="B4"]/{{{SHEET}}}v').text = "435.5" if edited else "420.5"
    parts["xl/worksheets/sheet1.xml"] = etree.tostring(xml, xml_declaration=True, encoding="UTF-8")
    # Exercise insertion into a prefixed, non-default namespace style part.
    styles = etree.fromstring(parts["xl/styles.xml"])
    # openpyxl writes several font properties outside their schema sequence.
    # Author standards-valid sources so validator failures identify exports.
    font_order = ["b", "i", "strike", "condense", "extend", "outline", "shadow", "u", "vertAlign", "sz", "color", "name", "family", "charset", "scheme"]
    for font in styles.findall(f"{{{SHEET}}}fonts/{{{SHEET}}}font"):
        font[:] = sorted(font, key=lambda child: font_order.index(etree.QName(child).localname))
    prefixed = etree.Element(styles.tag, nsmap={"s": SHEET})
    prefixed.attrib.update(styles.attrib)
    prefixed.extend(list(styles))
    parts["xl/styles.xml"] = etree.tostring(prefixed, xml_declaration=True, encoding="UTF-8")
    assert b"<s:styleSheet" in parts["xl/styles.xml"]
    fixed_metadata(parts)
    return parts


def slide(edited: bool) -> dict[str, bytes]:
    deck = Presentation()
    deck.slide_width = Inches(10)
    deck.slide_height = Inches(5.625)
    deck.core_properties.author = "Independent host workflow fixture"
    deck.core_properties.created = STAMP
    deck.core_properties.modified = STAMP
    page = deck.slides.add_slide(deck.slide_layouts[6])
    for index, (text, top, size) in enumerate([
        ("Reviewed slide title" if edited else "Native slide title", 1.0, 24),
        ("Reference body remains unchanged.", 2.2, 18),
    ]):
        shape = page.shapes.add_textbox(Inches(1), Inches(top), Inches(8), Inches(0.8))
        shape.name = "Workflow title" if index == 0 else "Reference body"
        frame = shape.text_frame
        frame.margin_left = frame.margin_right = frame.margin_top = frame.margin_bottom = 0
        frame.word_wrap = False
        paragraph = frame.paragraphs[0]
        paragraph.space_before = paragraph.space_after = Pt(0)
        paragraph.line_spacing = 1
        run = paragraph.add_run()
        run.text = text
        run.font.name = "Liberation Sans"
        run.font.size = Pt(size)
        run.font.bold = False
    page.notes_slide.notes_text_frame.text = (
        "Reviewed notes\nDecision: approved\nReference retained."
        if edited else "Source notes\nReference retained."
    )
    output = BytesIO()
    deck.save(output)
    parts = unpack(output.getvalue())
    fixed_metadata(parts)
    return parts


def main() -> None:
    cases = []
    for name, extension, build, semantics in [
        ("native-word", "docx", word, {"paragraphs": ["Reviewed: Native workflow report", "Reference paragraph remains unchanged."], "first_paragraph_bold": True, "first_paragraph_left_twips": 480, "first_paragraph_after_twips": 360}),
        ("native-sheet", "xlsx", sheet, {"A2": "Approved travel", "B2": 135.5, "B3": 300, "B4_formula": "SUM(B2:B3)", "B4_cache": 435.5, "A2_bold": True, "A2_italic": True, "A2_horizontal": "center", "A2_vertical": "bottom", "A5_horizontal": "center", "A5_vertical": None, "merge": "A5:B5"}),
        ("native-slide", "pptx", slide, {"texts": ["Reviewed slide title", "Reference body remains unchanged."], "notes": "Reviewed notes\nDecision: approved\nReference retained."}),
    ]:
        item = {"id": name, "format": extension, "expected_semantics": semantics}
        for edited, role in [(False, "source"), (True, "expected")]:
            filename = f"{name}-{role}.{extension}"
            path = ROOT / filename
            package(build(edited), path)
            item[role] = filename
            item[f"{role}_sha256"] = sha256(path.read_bytes()).hexdigest()
        cases.append(item)
    manifest = {
        "version": 1,
        "generator": "test/fixtures/office_native_workflows/generate.py",
        "authorship": "Raw WordprocessingML, openpyxl and python-pptx; never derived from a Quds export.",
        "tools": {name: version(name) for name in ["openpyxl", "python-pptx", "lxml"]},
        "cases": cases,
    }
    (ROOT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    main()
