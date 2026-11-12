"""Independent authored positive fixture and mutation controls for SDT checks."""

import copy
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from xml.etree import ElementTree as ET

from content_control_oracle import CUSTOMER, ENGINE, EXPECTED_FILES, M, MC, NS, PNG, R, SOURCE, W, inspect_directory, inspect_parts

PKG = "http://schemas.openxmlformats.org/package/2006/relationships"
VML = "urn:schemas-microsoft-com:vml"


def node(root, identifier):
    return next(control for control in root.iter(f"{{{W}}}sdt")
                if control.find("w:sdtPr/w:id", NS).get(f"{{{W}}}val") == str(identifier))


def run(text, bold=False):
    result = ET.Element(f"{{{W}}}r")
    if bold:
        ET.SubElement(ET.SubElement(result, f"{{{W}}}rPr"), f"{{{W}}}b")
    ET.SubElement(result, f"{{{W}}}t").text = text
    return result


def auxiliary(identifier, content):
    return ET.fromstring(
        f'<w:sdt xmlns:w="{W}"><w:sdtPr><w:alias w:val="Aux control {identifier}"/>'
        f'<w:tag w:val="control-{identifier}"/><w:id w:val="{identifier}"/><w:richText/>'
        '</w:sdtPr><w:sdtEndPr><w:rPr><w:color w:val="112233"/></w:rPr>'
        f'</w:sdtEndPr><w:sdtContent>{content}</w:sdtContent></w:sdt>')


def inline_story(identifier, text):
    paragraph = ET.Element(f"{{{W}}}p")
    paragraph.append(run("Before "))
    control = auxiliary(identifier, f'<w:r><w:rPr><w:i/></w:rPr><w:t>{text}</w:t></w:r>')
    paragraph.append(control)
    paragraph.append(run(" after"))
    return paragraph


def source(*, edited=True, fallback=True):
    """Author expected native structures using only Python and source XML."""
    root = ET.parse(SOURCE).getroot()
    root.set("xmlns:wps", "http://schemas.microsoft.com/office/word/2010/wordprocessingShape")
    body = root.find("w:body", NS)
    content = node(root, 71).find("w:sdtContent", NS)
    if edited:
        body.find("w:p/w:r/w:t", NS).text = "Outside before edited"
        first = content.find("w:p", NS)
        first.remove(first.find("w:r", NS))
        first.extend([run("Block "), run("Edited", bold=True)])
        tail = ET.Element(f"{{{W}}}p")
        tail.append(copy.deepcopy(first.find("w:pPr", NS)))
        tail.append(run(" Beta"))
        content.insert(1, tail)
        node(root, 73).find("w:sdtContent/w:p/w:r/w:t", NS).text = "Edited cell content"
        frame = node(root, 74).find("w:sdtContent", NS)
        frame.find("w:p/w:r/w:t", NS).text = "Frame content updated"
        second = ET.SubElement(frame, f"{{{W}}}p")
        second.append(run("Frame second"))
        node(root, 75).find("w:sdtContent/w:r/w:t", NS).text = "Gamma "
        node(root, 76).find("w:sdtContent/w:r/w:t", NS).text = "Core"
        node(root, 77).find("w:sdtContent", NS).append(run("empty filled"))
    if fallback:
        drawing = content.find("w:p/w:r/w:drawing", NS)
        parents = {child: parent for parent in root.iter() for child in parent}
        owner = parents[drawing]
        owner.remove(drawing)
        alternative = ET.SubElement(owner, f"{{{MC}}}AlternateContent")
        ET.SubElement(alternative, f"{{{MC}}}Choice", {"Requires": "wps"}).append(drawing)
        fallback_node = ET.SubElement(alternative, f"{{{MC}}}Fallback")
        pict = ET.SubElement(fallback_node, f"{{{W}}}pict")
        textbox = ET.SubElement(ET.SubElement(pict, f"{{{VML}}}rect"), f"{{{VML}}}textbox")
        ET.SubElement(textbox, f"{{{W}}}txbxContent").append(copy.deepcopy(node(root, 74)))
    rels = ET.Element(f"{{{PKG}}}Relationships")

    def relation(identifier, kind, target):
        ET.SubElement(rels, f"{{{PKG}}}Relationship",
                      {"Id": identifier, "Type": R + "/" + kind, "Target": target})

    parts = {
        "_rels/.rels": f'<Relationships xmlns="{PKG}"><Relationship Id="main" Type="{R}/officeDocument" Target="word/document.xml"/></Relationships>'.encode(),
        "word/media/control.png": PNG,
        "customXml/controlData.xml": CUSTOMER,
        "customXml/controlProps.xml": b'<ds:datastoreItem xmlns:ds="http://schemas.openxmlformats.org/officeDocument/2006/customXml" ds:itemID="{00000000-0000-0000-0000-000000000071}"/>',
        "customXml/_rels/controlData.xml.rels": f'<Relationships xmlns="{PKG}"><Relationship Id="properties" Type="{R}/customXmlProps" Target="controlProps.xml"/></Relationships>'.encode(),
    }
    relation("controlImage", "image", "media/control.png")
    relation("binding", "customXml", "../customXml/controlData.xml")
    section = body.find("w:sectPr", NS)
    identifier = 81
    for kind in ("header", "footer"):
        for variant in ("default", "first", "even"):
            uri = f"word/{kind}_{variant}.xml"
            story = ET.Element(f"{{{W}}}{'hdr' if kind == 'header' else 'ftr'}")
            story.append(inline_story(identifier, kind + "-" + variant))
            parts[uri] = ET.tostring(story)
            rid = kind + "_" + variant
            relation(rid, kind, uri.removeprefix("word/"))
            ET.SubElement(section, f"{{{W}}}{kind}Reference",
                          {f"{{{W}}}type": variant, f"{{{R}}}id": rid})
            identifier += 1
    comments = ET.Element(f"{{{W}}}comments")
    comment = ET.SubElement(comments, f"{{{W}}}comment",
                            {f"{{{W}}}id": "7", f"{{{W}}}author": "Source author"})
    comment.append(inline_story(87, "Comment"))
    parts["word/comments.xml"] = ET.tostring(comments)
    relation("comments", "comments", "comments.xml")
    for kind, block_id, inline_id, name in (("footnote", 91, 88, "Footnote"),
                                          ("endnote", 92, 89, "Endnote")):
        story = ET.Element(f"{{{W}}}{kind}s")
        note = ET.SubElement(story, f"{{{W}}}{kind}", {f"{{{W}}}id": "1"})
        block = auxiliary(block_id, "")
        note.append(block)
        paragraph = ET.SubElement(block.find("w:sdtContent", NS), f"{{{W}}}p")
        ET.SubElement(ET.SubElement(paragraph, f"{{{W}}}r"), f"{{{W}}}{kind}Ref")
        paragraph.append(run(name + " "))
        paragraph.append(auxiliary(inline_id, '<w:r><w:t>body</w:t></w:r>'))
        if edited:
            paragraph.append(run(" edited"))
        parts[f"word/{kind}s.xml"] = ET.tostring(story)
        relation(kind, kind + "s", kind + "s.xml")
    parts["word/document.xml"] = ET.tostring(root)
    parts["word/_rels/document.xml.rels"] = ET.tostring(rels)
    return parts


def change(parts, name, operation):
    root = ET.fromstring(parts[name])
    operation(root)
    parts[name] = ET.tostring(root)


class ContentControlOracleTest(unittest.TestCase):
    def test_rejects_inline_math_promoted_to_display(self):
        def mutate(root):
            paragraph = node(root, 72).findall("w:sdtContent/w:p", NS)[1]
            math = paragraph.find("m:oMath", NS)
            paragraph.remove(math)
            ET.SubElement(paragraph, f"{{{M}}}oMathPara").append(math)
        self.reject(mutate, "inline equation")

    def test_rejects_new_empty_settings_part(self):
        parts = source()
        parts["word/settings.xml"] = f'<w:settings xmlns:w="{W}"/>'.encode()
        with self.assertRaisesRegex(AssertionError, "settings absence"):
            inspect_parts(parts)

    def test_rejects_new_settings_relationship_at_nondefault_path(self):
        parts = source()
        parts["settings/native.xml"] = f'<w:settings xmlns:w="{W}"/>'.encode()
        change(parts, "word/_rels/document.xml.rels", lambda root:
               ET.SubElement(root, f"{{{PKG}}}Relationship",
                             {"Id": "settings", "Type": R + "/settings", "Target": "../settings/native.xml"}))
        with self.assertRaisesRegex(AssertionError, "settings absence"):
            inspect_parts(parts)

    def test_rejects_invented_frame_anchor_spacing(self):
        def mutate(root):
            paragraph = next(p for p in node(root, 71).findall("w:sdtContent/w:p", NS)
                             if p.find(".//wps:wsp", NS) is not None)
            properties = ET.Element(f"{{{W}}}pPr")
            ET.SubElement(properties, f"{{{W}}}spacing", {f"{{{W}}}line": "20", f"{{{W}}}lineRule": "exact"})
            paragraph.insert(0, properties)
        self.reject(mutate, "anchor paragraph")

    def test_rejects_default_frame_insets_replaced_by_zero(self):
        self.reject(lambda root: root.find(".//wps:bodyPr", NS).set("lIns", "0"), "default insets")

    def test_rejects_added_toc_field_paragraph(self):
        self.reject(lambda root: node(root, 78).find("w:sdtContent", NS).append(ET.Element(f"{{{W}}}p")),
                    "field paragraph placement")

    def test_rejects_toc_boundary_moved_to_title(self):
        def mutate(root):
            title, entry = node(root, 78).findall("w:sdtContent/w:p", NS)
            begin = entry.find("w:r", NS)
            entry.remove(begin)
            title.append(begin)
        self.reject(mutate, "field paragraph placement")

    def test_rejects_new_toc_dot_leader(self):
        def mutate(root):
            item = node(root, 78).findall("w:sdtContent/w:p", NS)[1]
            tabs = ET.SubElement(item.find("w:pPr", NS), f"{{{W}}}tabs")
            ET.SubElement(tabs, f"{{{W}}}tab", {f"{{{W}}}val": "right", f"{{{W}}}leader": "dot", f"{{{W}}}pos": "9360"})
        self.reject(mutate, "tabs/leaders")

    def test_rejects_reformatted_toc_page_suffix(self):
        def mutate(root):
            item = node(root, 78).findall("w:sdtContent/w:p", NS)[1]
            suffix = next(r for r in item.findall("w:r", NS) if r.find("w:tab", NS) is not None)
            properties = ET.Element(f"{{{W}}}rPr")
            ET.SubElement(properties, f"{{{W}}}color", {f"{{{W}}}val": "FF0000"})
            suffix.insert(0, properties)
        self.reject(mutate, "suffix acquired direct formatting")

    def test_accepts_independently_authored_native_positive(self):
        self.assertEqual(inspect_parts(source())["inline_controls"], 12)

    def test_accepts_unchanged_authored_source_without_generated_fallback(self):
        result = inspect_parts(source(edited=False, fallback=False), phase="source")
        self.assertEqual(result["phase"], "source")
        self.assertIsNone(result["frame_fallback_matches"])

    def test_accepts_unchanged_import_with_owned_matching_fallback(self):
        result = inspect_parts(source(edited=False), phase="imported")
        self.assertEqual(result["phase"], "imported")
        self.assertTrue(result["frame_fallback_matches"])

    def test_edited_output_cannot_satisfy_unchanged_baseline(self):
        with self.assertRaisesRegex(AssertionError, "unrelated body text"):
            inspect_parts(source(), phase="imported")

    def test_source_phase_cannot_hide_changed_control_text(self):
        parts = source(edited=False, fallback=False)
        change(parts, "word/document.xml", lambda root:
               setattr(node(root, 73).find("w:sdtContent/w:p/w:r/w:t", NS), "text", "Changed before import"))
        with self.assertRaisesRegex(AssertionError, "table-cell content"):
            inspect_parts(parts, phase="source")

    def test_exact_ten_file_inventory_dispatches_independent_phase_expectations(self):
        with tempfile.TemporaryDirectory(dir=ENGINE/"build") as folder:
            root = Path(folder)
            for name in EXPECTED_FILES:
                (root/name).write_bytes(b"inventory-only control")
            with patch("content_control_oracle.inspect_package", side_effect=lambda path, phase: {"phase": phase}):
                result = inspect_directory(root)
            self.assertEqual(len(result), 10)
            self.assertEqual(result["source.docx"]["phase"], "source")
            for cycle in range(1, 4):
                self.assertEqual(result[f"imported-{cycle}.docx"]["phase"], "imported")
                for mode in ("direct", "isolate"):
                    self.assertEqual(result[f"{mode}-{cycle}.docx"]["phase"], "edited")

    def test_native_baseline_inventory_rejects_missing_source(self):
        with tempfile.TemporaryDirectory(dir=ENGINE/"build") as folder:
            root = Path(folder)
            for name in EXPECTED_FILES - {"source.docx"}:
                (root/name).touch()
            with self.assertRaisesRegex(AssertionError, "missing=.*source.docx"):
                inspect_directory(root)

    def test_native_baseline_inventory_rejects_unexpected_extra_package(self):
        with tempfile.TemporaryDirectory(dir=ENGINE/"build") as folder:
            root = Path(folder)
            for name in EXPECTED_FILES | {"stale.docx"}:
                (root/name).touch()
            with self.assertRaisesRegex(AssertionError, "unexpected=.*stale.docx"):
                inspect_directory(root)

    def reject(self, operation, message, part="word/document.xml"):
        parts = source()
        change(parts, part, operation)
        with self.assertRaisesRegex(AssertionError, message):
            inspect_parts(parts)

    def test_rejects_flattened_block_wrapper(self):
        def flatten(root):
            body = root.find("w:body", NS)
            control = node(root, 71)
            at = list(body).index(control)
            body.remove(control)
            for child in control.find("w:sdtContent", NS):
                body.insert(at, child)
                at += 1
        self.reject(flatten, "body control inventory")

    def test_rejects_changed_alias(self):
        self.reject(lambda root: node(root, 73).find("w:sdtPr/w:alias", NS).set(f"{{{W}}}val", "Lost alias"), "native sdtPr metadata")

    def test_rejects_lost_end_properties(self):
        self.reject(lambda root: node(root, 75).remove(node(root, 75).find("w:sdtEndPr", NS)), "native sdtEndPr metadata")

    def test_rejects_binding_metadata_rewritten(self):
        self.reject(lambda root: node(root, 71).find("w:sdtPr/w:dataBinding", NS).set(f"{{{W}}}xpath", "/wrong"), "native sdtPr metadata")

    def test_rejects_duplicate_active_id(self):
        self.reject(lambda root: node(root, 76).find("w:sdtPr/w:id", NS).set(f"{{{W}}}val", "75"), "duplicate active content-control")

    def test_rejects_cell_content_escaping_wrapper(self):
        def move(root):
            content = node(root, 73).find("w:sdtContent", NS)
            paragraph = content.find("w:p", NS)
            content.remove(paragraph)
            root.find("w:body/w:sdt/w:sdtContent/w:tbl/w:tr/w:tc", NS).append(paragraph)
        self.reject(move, "table-cell content control")

    def test_rejects_frame_fallback_drift(self):
        self.reject(lambda root: setattr(root.find(".//mc:Fallback//w:sdtContent/w:p/w:r/w:t", NS), "text", "Stale frame"), "fallback disagrees")

    def test_rejects_inline_range_expanding_to_prefix(self):
        def move(root):
            parents = {child: parent for parent in root.iter() for child in parent}
            control = node(root, 75)
            paragraph = parents[control]
            prefix = paragraph.find("w:r", NS)
            paragraph.remove(prefix)
            control.find("w:sdtContent", NS).insert(0, prefix)
        self.reject(move, "inline ranges expanded")

    def test_rejects_empty_control_edit_loss(self):
        self.reject(lambda root: node(root, 77).find("w:sdtContent", NS).clear(), "inline surrounding text")

    def test_rejects_redundant_toc_instruction(self):
        def duplicate(root):
            instruction = node(root, 78).find(".//w:instrText", NS)
            parents = {child: parent for parent in root.iter() for child in parent}
            parents[instruction].append(copy.deepcopy(instruction))
        self.reject(duplicate, "TOC instruction missing or duplicated")

    def test_rejects_broken_controlled_heading_target(self):
        self.reject(lambda root: node(root, 72).find(".//w:bookmarkStart", NS).set(f"{{{W}}}name", "WrongTarget"), "TOC target")

    def test_rejects_header_story_swap(self):
        self.reject(lambda root: root.find("w:body/w:sectPr/w:headerReference", NS).set(f"{{{R}}}id", "footer_default"), "invalid owned header relationship")

    def test_rejects_note_wrapper_flattening(self):
        def flatten(root):
            note = root.find("w:footnote", NS)
            control = note.find("w:sdt", NS)
            note.remove(control)
            note.extend(list(control.find("w:sdtContent", NS)))
        self.reject(flatten, "unexpected controls in footnote", part="word/footnotes.xml")

    def test_rejects_picture_payload_change(self):
        parts = source()
        parts["word/media/control.png"] = b"unrelated image bytes"
        with self.assertRaisesRegex(AssertionError, "image payload changed"):
            inspect_parts(parts)

    def test_rejects_binding_data_overwrite(self):
        parts = source()
        parts["customXml/controlData.xml"] = b"<empty/>"
        with self.assertRaisesRegex(AssertionError, "binding data overwritten"):
            inspect_parts(parts)


if __name__ == "__main__":
    unittest.main()
