#!/usr/bin/env python3
"""Rebuild the owned binary DOC fixture using an already installed LibreOffice.

Run with a Python containing python-docx and Pillow, and pass --soffice. This is
a fixture authoring tool, not a runtime dependency or a downloaded test asset.
"""
from __future__ import annotations

import argparse
import io
import os
from pathlib import Path
import subprocess
import tempfile
import zipfile

from docx import Document
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor
from PIL import Image, ImageDraw


def build_docx(path: Path) -> None:
    document = Document()
    document.add_heading("Installed Office conversion fixture", level=1)
    paragraph = document.add_paragraph("Unicode café — 東京 😀. ")
    bold = paragraph.add_run("Bold red text")
    bold.bold = True
    bold.font.color.rgb = RGBColor(0xC0, 0x20, 0x30)
    bold.font.size = Pt(18)
    paragraph.add_run(" and italic text.").italic = True
    table = document.add_table(rows=2, cols=2)
    table.style = "Table Grid"
    for cell, text in zip(
        [cell for row in table.rows for cell in row.cells],
        ["Column A", "Column B", "Cell one", "Cell two"],
    ):
        cell.text = text
    image = Image.new("RGB", (80, 48), "#e5efff")
    draw = ImageDraw.Draw(image)
    draw.rectangle((5, 5, 36, 42), fill="#2244aa")
    draw.ellipse((43, 8, 73, 38), fill="#cc3344")
    picture = io.BytesIO()
    image.save(picture, format="PNG")
    picture.seek(0)
    document.add_picture(picture, width=Inches(1.4))
    paragraph = document.add_paragraph("A footnote remains attached here")
    reference = OxmlElement("w:footnoteReference")
    reference.set(qn("w:id"), "1")
    paragraph.add_run()._r.append(reference)
    document.add_paragraph("A second paragraph after the footnote.")
    document.sections[0].header.paragraphs[0].text = "Fixture header"
    document.sections[0].footer.paragraphs[0].text = "Fixture footer"
    document.core_properties.author = "CrispCloud test fixture"
    document.save(path)
    with zipfile.ZipFile(path) as package:
        parts = {name: package.read(name) for name in package.namelist()}
    w = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    parts["word/footnotes.xml"] = f'''<?xml version="1.0" encoding="UTF-8"?>
<w:footnotes xmlns:w="{w}">
 <w:footnote w:type="separator" w:id="-1"><w:p><w:r><w:separator/></w:r></w:p></w:footnote>
 <w:footnote w:type="continuationSeparator" w:id="0"><w:p><w:r><w:continuationSeparator/></w:r></w:p></w:footnote>
 <w:footnote w:id="1"><w:p><w:r><w:footnoteRef/></w:r><w:r><w:t>Footnote content survives conversion.</w:t></w:r></w:p></w:footnote>
</w:footnotes>'''.encode()
    content_types = parts["[Content_Types].xml"].decode()
    parts["[Content_Types].xml"] = content_types.replace(
        "</Types>",
        '<Override PartName="/word/footnotes.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footnotes+xml"/></Types>',
    ).encode()
    relationships = parts["word/_rels/document.xml.rels"].decode()
    parts["word/_rels/document.xml.rels"] = relationships.replace(
        "</Relationships>",
        '<Relationship Id="rIdFixtureFootnotes" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footnotes" '
        'Target="footnotes.xml"/></Relationships>',
    ).encode()
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as package:
        for name, data in parts.items():
            package.writestr(name, data)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--soffice", required=True, type=Path)
    parser.add_argument("--temp-root", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="word-fixture-", dir=args.temp_root) as temporary:
        workspace = Path(temporary)
        source = workspace / "formatting.docx"
        build_docx(source)
        profile = workspace / "profile"
        (profile / "user").mkdir(parents=True)
        (profile / "user/registrymodifications.xcu").write_text('''
<oor:items xmlns:oor="http://openoffice.org/2001/registry">
 <item oor:path="/org.openoffice.Office.Common/Security/Scripting">
  <prop oor:name="DisableMacrosExecution" oor:op="fuse"><value>true</value></prop>
  <prop oor:name="BlockUntrustedRefererLinks" oor:op="fuse"><value>true</value></prop>
 </item>
 <item oor:path="/org.openoffice.Office.Writer/Content/Update">
  <prop oor:name="Link" oor:op="fuse"><value>0</value></prop>
 </item>
</oor:items>''')
        output = workspace / "output"
        output.mkdir()
        result = subprocess.run(
            [str(args.soffice), "-env:UserInstallation=" + profile.as_uri(),
             "--headless", "--nologo", "--nodefault", "--norestore",
             "--convert-to", "doc:MS Word 97", "--outdir", str(output), str(source)],
            env={**os.environ, "TMPDIR": str(workspace), "SAL_USE_VCLPLUGIN": "svp"},
            capture_output=True, timeout=60, check=True,
        )
        converted = output / "formatting.doc"
        data = converted.read_bytes()
        if data[:8] != bytes.fromhex("d0cf11e0a1b11ae1"):
            raise RuntimeError("LibreOffice did not create a binary Word document")
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(data)
        print(f"Created {args.output}: {len(data)} bytes")


if __name__ == "__main__":
    main()
