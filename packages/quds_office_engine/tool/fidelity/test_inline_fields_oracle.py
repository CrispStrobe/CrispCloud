"""Negative controls use hand-authored XML, independently of the Dart writer."""

import unittest

from inline_fields_oracle import W, inspect_document


def source() -> bytes:
    return f'''<w:document xmlns:w="{W}"><w:body><w:p>
      <w:r><w:rPr><w:b/></w:rPr><w:t>Before </w:t></w:r>
      <w:fldSimple w:instr=" CITATION PAGE "><w:r><w:t>(Ada 2026)</w:t></w:r></w:fldSimple>
      <w:r><w:rPr><w:i/></w:rPr><w:t> between </w:t></w:r>
      <w:fldSimple w:instr=" CITATION TIME "><w:r><w:t>(Grace 2025)</w:t></w:r></w:fldSimple>
      <w:r><w:rPr><w:u w:val="single"/></w:rPr><w:t> after</w:t></w:r>
    </w:p><w:sectPr/></w:body></w:document>'''.encode()


class InlineFieldOracleTest(unittest.TestCase):
    def test_accepts_independent_native_fields(self):
        self.assertEqual(len(inspect_document(source())["fields"]), 2)

    def test_rejects_loss_of_body_prefix(self):
        with self.assertRaisesRegex(AssertionError, "surrounding text"):
            inspect_document(source().replace(b"Before ", b""))

    def test_rejects_plain_text_instead_of_live_field(self):
        with self.assertRaisesRegex(AssertionError, "two independent inline fields"):
            inspect_document(source().replace(b"fldSimple", b"hyperlink"))

    def test_rejects_reserved_word_misclassification(self):
        with self.assertRaisesRegex(AssertionError, "instructions or results"):
            inspect_document(source().replace(b"CITATION PAGE", b"PAGE"))

    def test_rejects_formatting_loss(self):
        with self.assertRaisesRegex(AssertionError, "prefix bold"):
            inspect_document(source().replace(b"<w:b/>", b'<w:b w:val="0"/>'))

    def test_rejects_nested_instead_of_inline_fields(self):
        data = source().replace(b'<w:fldSimple w:instr=" CITATION PAGE ">',
                                b'<w:hyperlink><w:fldSimple w:instr=" CITATION PAGE ">', 1)
        data = data.replace(b'</w:fldSimple>', b'</w:fldSimple></w:hyperlink>', 1)
        with self.assertRaisesRegex(AssertionError, "two independent inline fields"):
            inspect_document(data)


if __name__ == "__main__":
    unittest.main()
