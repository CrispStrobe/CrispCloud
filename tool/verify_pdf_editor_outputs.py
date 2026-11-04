#!/usr/bin/env python3
"""Independently inspect Dart PDF editor output with pypdf.

This verifies concrete form/annotation/page-order/encryption invariants and a
simple text-only redaction. It also reproduces the retained Form XObject
limitation that keeps redaction disabled in the product. It is not a general
redaction safety certification or a substitute for visual/device testing.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

from pypdf import PdfReader
from pypdf.generic import IndirectObject, StreamObject


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_FIXTURES = ROOT / "test" / "fixtures" / "pdf_editor"
DEFAULT_OUTPUT = ROOT / "build" / "pdf_editor_verification"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def text_of(reader: PdfReader, page: int) -> str:
    return re.sub(r"\s+", " ", reader.pages[page].extract_text() or "").strip()


def annotations(page: Any) -> list[Any]:
    references = page.get("/Annots", [])
    if hasattr(references, "get_object"):
        references = references.get_object()
    return [reference.get_object() for reference in references]


def inherited_value(widget: Any, key: str) -> Any:
    seen: set[int] = set()
    while widget is not None and id(widget) not in seen:
        seen.add(id(widget))
        if key in widget:
            return widget[key]
        parent = widget.get("/Parent")
        widget = parent.get_object() if parent is not None else None
    return None


def verify_field(reader: PdfReader, manifest: dict[str, Any], value: str) -> None:
    name = manifest["field_name"]
    fields = reader.get_fields() or {}
    require(name in fields, f"Missing canonical form field {name}")
    require(fields[name].get("/V") == value, "Canonical form value was not preserved")
    widgets = [
        annotation
        for page in reader.pages
        for annotation in annotations(page)
        if annotation.get("/Subtype") == "/Widget"
        and inherited_value(annotation, "/T") == name
    ]
    require(len(widgets) == 1, "Expected one widget for the canonical reviewer field")
    require(inherited_value(widgets[0], "/V") == value, "Widget value disagrees with field tree")
    appearance_dictionary = widgets[0].get("/AP")
    require(appearance_dictionary is not None, "Reviewer widget has no appearance dictionary")
    appearance = appearance_dictionary.get_object().get("/N")
    require(appearance is not None, "Reviewer widget has no normal appearance")
    stream = appearance.get_object()
    require(isinstance(stream, StreamObject) and bool(stream.get_data()),
            "Reviewer widget appearance is empty")


def verify_embedded_font(reader: PdfReader) -> None:
    embedded = 0
    for page in reader.pages:
        fonts = page["/Resources"].get("/Font", {})
        fonts = fonts.get_object()
        for reference in fonts.values():
            font = reference.get_object()
            descriptor = font.get("/FontDescriptor")
            if descriptor is not None and "/FontFile2" in descriptor.get_object():
                embedded += 1
    require(embedded >= 2, "Expected an embedded TrueType font on both original pages")


def decoded_streams(reader: PdfReader) -> list[bytes]:
    """Scan every current xref object, including objects outside the page tree."""
    references = {
        (object_number, generation)
        for generation, entries in reader.xref.items()
        for object_number in entries
        if object_number > 0 and generation != 65535
    }
    references.update((number, 0) for number in reader.xref_objStm)
    streams = []
    for number, generation in sorted(references):
        obj = reader.get_object(IndirectObject(number, generation, reader))
        if isinstance(obj, StreamObject):
            streams.append(obj.get_data())
    return streams


def open_encrypted(path: Path, password: str) -> PdfReader:
    wrong = PdfReader(path, strict=True)
    require(wrong.is_encrypted, f"{path.name} lost its encryption")
    require(wrong.decrypt("incorrect") == 0, "An incorrect password opened the output")
    reader = PdfReader(path, strict=True)
    require(reader.decrypt(password) != 0, "The original password no longer opens the PDF")
    return reader


def verify_fixtures(directory: Path, manifest: dict[str, Any]) -> PdfReader:
    plain = PdfReader(directory / manifest["plain_fixture"], strict=True)
    require(len(plain.pages) == 2, "Plain fixture must have two pages")
    for index, marker in enumerate(manifest["page_markers"]):
        require(marker in text_of(plain, index), f"Missing fixture page marker {marker}")
        require(manifest["preserved_text"] in text_of(plain, index), "Embedded-font text mismatch")
    require(plain.pages[1].rotation == 90, "Fixture second page must be rotated")
    verify_field(plain, manifest, manifest["original_field_value"])
    verify_embedded_font(plain)

    encrypted = open_encrypted(directory / manifest["encrypted_fixture"], manifest["password"])
    require(len(encrypted.pages) == 2, "Encrypted fixture must retain both pages")
    verify_field(encrypted, manifest, manifest["original_field_value"])
    for fixture, secret, public in (
        ("redaction_fixture", "redaction_secret", "redaction_public"),
        ("partial_form_fixture", "partial_form_secret", "partial_form_public"),
    ):
        reader = PdfReader(directory / manifest[fixture], strict=True)
        require(manifest[secret] in text_of(reader, 0), f"Missing {secret} in fixture")
        require(manifest[public] in text_of(reader, 0), f"Missing {public} in fixture")
        require(any(manifest[secret].encode() in stream for stream in decoded_streams(reader)),
                f"Fixture {secret} must be recoverable from a decoded stream")
    return plain


def verify_edited(reader: PdfReader, original: PdfReader, manifest: dict[str, Any]) -> None:
    require(len(reader.pages) == 2, "Editing changed the page count")
    for output_index, original_index in enumerate((1, 0)):
        require(text_of(reader, output_index) == text_of(original, original_index),
                f"Original text or page order changed at page {output_index + 1}")
    require(reader.pages[0].rotation == 90 and reader.pages[1].rotation == 0,
            "Page rotation did not follow the reordered page")
    verify_embedded_font(reader)
    verify_field(reader, manifest, manifest["edited_field_value"])
    notes = [
        (page_index, annotation)
        for page_index, page in enumerate(reader.pages)
        for annotation in annotations(page)
        if annotation.get("/Subtype") == "/Text"
        and annotation.get("/Contents") == manifest["annotation_text"]
    ]
    require(len(notes) == 1 and notes[0][0] == 1,
            "The added note did not stay attached to the moved first page")


def verify_outputs(directory: Path, fixtures: Path, manifest: dict[str, Any],
                   original: PdfReader) -> dict[str, Any]:
    plain_path = directory / "round_trip.pdf"
    require(plain_path.is_file(), "Run flutter test test/pdf_editor_round_trip_test.dart first")
    plain = PdfReader(plain_path, strict=True)
    require(not plain.is_encrypted, "The plain document unexpectedly became encrypted")
    verify_edited(plain, original, manifest)

    encrypted_path = directory / "encrypted_edited.pdf"
    encrypted = open_encrypted(encrypted_path, manifest["password"])
    verify_edited(encrypted, original, manifest)
    original_encrypted = open_encrypted(fixtures / manifest["encrypted_fixture"], manifest["password"])
    for key in ("/V", "/R", "/Length", "/O", "/U"):
        require(encrypted.trailer["/Encrypt"].get(key) == original_encrypted.trailer["/Encrypt"].get(key),
                f"Editing changed encryption parameter {key}")
    encrypted_bytes = encrypted_path.read_bytes()
    for key in ("edited_field_value", "annotation_text"):
        require(manifest[key].encode() not in encrypted_bytes,
                f"New {key} was appended outside encryption")

    redacted_path = directory / "redacted.pdf"
    redacted = PdfReader(redacted_path, strict=True)
    secret = manifest["redaction_secret"]
    require(secret not in text_of(redacted, 0), "Redacted text is still extractable")
    require(manifest["redaction_public"] in text_of(redacted, 0), "Redaction removed public text")
    require("/Prev" not in redacted.trailer, "Redaction kept an incremental revision chain")
    raw = redacted_path.read_bytes()
    require(raw.count(b"%%EOF") == 1, "Redaction kept a previous complete PDF revision")
    for encoding in ("utf-8", "utf-16-be", "utf-16-le"):
        require(secret.encode(encoding) not in raw, "Secret remains in raw PDF bytes")
    for stream in decoded_streams(redacted):
        require(secret.encode() not in stream, "Secret remains in a decoded PDF stream")
    require(not any(annotation.get("/Subtype") == "/Redact"
                    for page in redacted.pages for annotation in annotations(page)),
            "The redaction output still contains un-applied marks")

    partial = PdfReader(directory / "partial_form_redaction.pdf", strict=True)
    require(manifest["partial_form_secret"] in text_of(partial, 0),
            "Upstream partial-Form behavior changed; review and update the documented limitation")
    require(any(manifest["partial_form_secret"].encode() in stream
                for stream in decoded_streams(partial)),
            "Expected known limitation was not reproduced in the retained Form stream")
    require(manifest["partial_form_public"] in text_of(partial, 0), "Partial-Form public text changed")

    return {
        "passed": ["original_text_and_embedded_fonts", "canonical_form_and_widget_value",
                   "note_annotation", "page_reorder_and_rotation", "aes256_password_preserved",
                   "text_only_redaction_removes_bytes_and_history"],
        "known_limitations": {
            "partially_covered_form_xobject_retains_secret": True,
            "required_product_policy": "redaction disabled",
            "general_redaction_safety_certified": False,
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixtures-dir", type=Path, default=DEFAULT_FIXTURES)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--fixtures-only", action="store_true")
    arguments = parser.parse_args()
    manifest = json.loads((arguments.fixtures_dir / "manifest.json").read_text(encoding="utf-8"))
    require(manifest.get("schema") == 1, "Unsupported fixture manifest schema")
    original = verify_fixtures(arguments.fixtures_dir, manifest)
    if arguments.fixtures_only:
        print("Verified all four input fixtures; no Dart-generated outputs checked.")
        return
    report = verify_outputs(arguments.output_dir, arguments.fixtures_dir, manifest, original)
    (arguments.output_dir / "verification.json").write_text(
        json.dumps(report, indent=2) + "\n", encoding="utf-8"
    )
    print("Verified edited PDFs independently with pypdf.")
    print("Text-only redaction passes; the known partial-Form limitation is reproduced.")
    print("Production redaction remains disabled; this is not a general safety certification.")


if __name__ == "__main__":
    main()
