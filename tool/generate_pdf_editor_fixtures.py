#!/usr/bin/env python3
"""Generate small PDF integration fixtures with a second implementation.

Run from any directory with reportlab, pypdf, and cryptography installed.
Unencrypted fixture bytes are deterministic for a fixed dependency version;
AES-256 encryption intentionally uses fresh random salts/IVs on regeneration.
"""

from __future__ import annotations

import argparse
import io
import json
from pathlib import Path

from pypdf import PdfReader, PdfWriter
from reportlab.lib import colors
from reportlab.lib.pagesizes import letter
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = ROOT / "test" / "fixtures" / "pdf_editor"
MANIFEST = {
    "schema": 1,
    "plain_fixture": "form_rotated.pdf",
    "encrypted_fixture": "form_rotated_encrypted.pdf",
    "redaction_fixture": "redaction.pdf",
    "partial_form_fixture": "partial_form.pdf",
    "password": "crispcloud-pdf-fixture",
    "owner_password": "crispcloud-pdf-fixture-owner",
    "field_name": "reviewer",
    "original_field_value": "Awaiting review",
    "edited_field_value": "Reviewed in CrispCloud",
    "annotation_text": "CrispCloud integration note",
    "page_markers": ["CRISPCLOUD_PAGE_ONE", "CRISPCLOUD_PAGE_TWO"],
    "preserved_text": "Embedded Roboto: Cafe, caf\u00e9, and r\u00e9sum\u00e9.",
    "redaction_secret": "CRISPCLOUD_REDACT_ME_672a",
    "redaction_public": "Public content must survive text redaction.",
    "partial_form_secret": "CRISPCLOUD_FORM_SECRET_9841",
    "partial_form_public": "Public content inside a partially covered form.",
    "redaction_rect": [70, 694, 520, 718],
}


def pdf_canvas(buffer: io.BytesIO, title: str) -> canvas.Canvas:
    result = canvas.Canvas(
        buffer,
        pagesize=letter,
        invariant=1,
        pageCompression=1,
        pdfVersion=(1, 7),
    )
    result.setTitle(title)
    result.setAuthor("CrispCloud integration tests")
    result.setSubject("Generated test content; contains no real personal data")
    return result


def write_form_document(output: Path) -> None:
    buffer = io.BytesIO()
    document = pdf_canvas(buffer, "CrispCloud PDF form and rotation fixture")
    for index, marker in enumerate(MANIFEST["page_markers"]):
        document.setFillColor(colors.HexColor("#20344A"))
        document.setFont("FixtureRoboto", 22)
        document.drawString(54, 738, f"PDF integration - page {index + 1}")
        document.setFont("FixtureRoboto", 12)
        document.drawString(54, 700, marker)
        document.drawString(54, 674, MANIFEST["preserved_text"])
        if index == 0:
            document.drawString(54, 606, "Reviewer (interactive text field)")
            document.acroForm.textfield(
                name=MANIFEST["field_name"],
                tooltip="Review status",
                value=MANIFEST["original_field_value"],
                x=54,
                y=566,
                width=360,
                height=28,
                fontName="Helvetica",
                fontSize=12,
                borderWidth=1,
                borderColor=colors.HexColor("#60788E"),
                fillColor=colors.HexColor("#F4F7FA"),
                textColor=colors.black,
                forceBorder=True,
            )
        else:
            document.drawString(54, 606, "This page has a /Rotate value of 90.")
            document.drawString(54, 582, "It should become the first page after editing.")
        document.showPage()
    document.save()

    writer = PdfWriter()
    writer.clone_document_from_reader(PdfReader(io.BytesIO(buffer.getvalue())))
    writer.pages[1].rotate(90)
    with output.open("wb") as stream:
        writer.write(stream)


def write_redaction_document(output: Path, *, partial_form: bool) -> None:
    buffer = io.BytesIO()
    document = pdf_canvas(buffer, "CrispCloud redaction engine regression fixture")
    if partial_form:
        # The text is inside a full-page Form XObject. The redaction rectangle
        # covers its secret line but only a small portion of the Form's BBox.
        document.beginForm("partial_content", 0, 0, *letter)
    document.setFont("Helvetica", 12)
    secret_key = "partial_form_secret" if partial_form else "redaction_secret"
    public_key = "partial_form_public" if partial_form else "redaction_public"
    document.drawString(72, 700, MANIFEST[secret_key])
    document.drawString(72, 620, MANIFEST[public_key])
    if partial_form:
        document.endForm()
        document.doForm("partial_content")
    document.showPage()
    document.save()
    output.write_bytes(buffer.getvalue())


def generate(output: Path) -> None:
    output.mkdir(parents=True, exist_ok=True)
    pdfmetrics.registerFont(
        TTFont("FixtureRoboto", str(ROOT / "assets" / "fonts" / "Roboto-Regular.ttf"))
    )
    plain = output / MANIFEST["plain_fixture"]
    write_form_document(plain)

    encrypted = PdfWriter()
    encrypted.clone_document_from_reader(PdfReader(plain))
    encrypted.encrypt(
        user_password=MANIFEST["password"],
        owner_password=MANIFEST["owner_password"],
        algorithm="AES-256",
    )
    with (output / MANIFEST["encrypted_fixture"]).open("wb") as stream:
        encrypted.write(stream)

    write_redaction_document(output / MANIFEST["redaction_fixture"], partial_form=False)
    write_redaction_document(output / MANIFEST["partial_form_fixture"], partial_form=True)
    (output / "manifest.json").write_text(
        json.dumps(MANIFEST, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    print(f"Generated four PDF fixtures and manifest in {output}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    generate(parser.parse_args().output_dir)


if __name__ == "__main__":
    main()
