"""Mutation tests use ZIP/XML authored here, never the engine serializer."""
import io
import unittest
import zipfile

from lists_oracle import snapshot

NS = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'


def authored_parts():
    paragraphs = ''.join(
        f'<w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="{number}"/></w:numPr></w:pPr><w:r><w:t>{text}</w:t></w:r></w:p>'
        for number, text in zip([2, 2, 3, 3, 4, 4], ['One', 'Two', 'Three', 'Four', 'Five', 'Six'])
    )
    numbering = f'<w:numbering xmlns:w="{NS}"><w:abstractNum w:abstractNumId="2"><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%1."/></w:lvl></w:abstractNum>'
    for number in [2, 3, 4]:
        override = '' if number == 2 else '<w:lvlOverride w:ilvl="0"><w:startOverride w:val="5"/></w:lvlOverride>'
        numbering += f'<w:num w:numId="{number}"><w:abstractNumId w:val="2"/>{override}</w:num>'
    return {
        'word/document.xml': f'<w:document xmlns:w="{NS}"><w:body>{paragraphs}</w:body></w:document>',
        'word/numbering.xml': numbering + '</w:numbering>',
        'word/_rels/document.xml.rels': '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/></Relationships>',
    }


def package(parts):
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, 'w') as archive:
        for name, text in parts.items():
            archive.writestr(name, text)
    return buffer.getvalue()


class ListOracleTest(unittest.TestCase):
    def test_authored_restart_semantics(self):
        self.assertEqual(snapshot(package(authored_parts()))['labels'], [1, 2, 5, 6, 5, 6])

    def test_rejects_missing_or_wrong_restart(self):
        for replacement in ['', '<w:startOverride w:val="6"/>']:
            with self.subTest(replacement=replacement):
                parts = authored_parts()
                parts['word/numbering.xml'] = parts['word/numbering.xml'].replace('<w:startOverride w:val="5"/>', replacement, 1)
                with self.assertRaises(AssertionError):
                    snapshot(package(parts))

    def test_rejects_merged_restart_instances(self):
        parts = authored_parts()
        parts['word/document.xml'] = parts['word/document.xml'].replace('<w:numId w:val="4"/>', '<w:numId w:val="3"/>')
        with self.assertRaises(AssertionError):
            snapshot(package(parts))

    def test_rejects_wrong_text_or_relationship(self):
        for name, old, new in [
            ('word/document.xml', '>Three<', '>Wrong<'),
            ('word/_rels/document.xml.rels', 'Target="numbering.xml"', 'Target="missing.xml"'),
        ]:
            with self.subTest(part=name):
                parts = authored_parts()
                parts[name] = parts[name].replace(old, new)
                with self.assertRaises(AssertionError):
                    snapshot(package(parts))


if __name__ == '__main__':
    unittest.main()
