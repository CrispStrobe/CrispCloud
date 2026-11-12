"""Revision oracle controls use hand-authored native XML, never Dart output."""

import unittest

from revision_story_oracle import DATE, NS, PKG, R, W, inspect_parts, inspect_story
from xml.etree import ElementTree as ET


def story(name):
    return ''.join(f'''<w:p><w:r><w:t>{name}</w:t></w:r>
      <w:{kind} w:id="1" w:author="Native reviewer" w:date="{DATE}">
      <w:r><w:rPr><w:b/></w:rPr><w:{node}>{value}</w:{node}></w:r></w:{kind}>
      <w:r><w:t> tail</w:t></w:r></w:p>'''
                   for kind, node, value in [('ins', 't', ' added'),
                                              ('del', 'delText', ' removed')])


def paragraphs(data=None):
    xml = f'<w:hdr xmlns:w="{W}">{data or story("Header-default")}</w:hdr>'
    return ET.fromstring(xml).findall('w:p', NS)


def source():
    parts = {'_rels/.rels': f'<Relationships xmlns="{PKG}"><Relationship Id="main" Type="{R}/officeDocument" Target="word/document.xml"/></Relationships>'.encode()}
    rels, references = [], []
    for kind, root in [('header', 'hdr'), ('footer', 'ftr')]:
        for variant in ('default', 'first', 'even'):
            key = f'{kind}-{variant}'
            parts[f'word/{key}.xml'] = f'<w:{root} xmlns:w="{W}">{story(key.capitalize())}</w:{root}>'.encode()
            references.append(f'<w:{kind}Reference w:type="{variant}" r:id="{key}"/>')
            rels.append(f'<Relationship Id="{key}" Type="{R}/{kind}" Target="{key}.xml"/>')
    for name, kind, item, identifier in [('Footnote', 'footnotes', 'footnote', 1),
                                         ('Endnote', 'endnotes', 'endnote', 1),
                                         ('Comment', 'comments', 'comment', 7)]:
        parts[f'word/{kind}.xml'] = f'<w:{kind} xmlns:w="{W}"><w:{item} w:id="{identifier}">{story(name)}</w:{item}></w:{kind}>'.encode()
        rels.append(f'<Relationship Id="{kind}" Type="{R}/{kind}" Target="{kind}.xml"/>')
    parts['word/_rels/document.xml.rels'] = f'<Relationships xmlns="{PKG}">{"".join(rels)}</Relationships>'.encode()
    parts['word/document.xml'] = f'<w:document xmlns:w="{W}" xmlns:r="{R}"><w:body><w:p><w:r><w:t>UNCHANGED</w:t></w:r></w:p>{story("Body")}<w:sectPr>{"".join(references)}</w:sectPr></w:body></w:document>'.encode()
    return parts


class RevisionStoryOracleTest(unittest.TestCase):
    def test_accepts_independent_native_stories(self):
        self.assertEqual(len(inspect_parts(source())), 10)

    def test_rejects_wrong_story_owner(self):
        parts = source()
        parts['word/header-default.xml'] = parts['word/header-default.xml'].replace(b'Header-default', b'Body')
        with self.assertRaisesRegex(AssertionError, 'ownership changed'):
            inspect_parts(parts)

    def test_rejects_broadened_revision_span(self):
        data = story('Header-default').replace('<w:t> added</w:t>', '<w:t>Header-default added</w:t>').replace('<w:t>Header-default</w:t>', '<w:t></w:t>', 1)
        with self.assertRaisesRegex(AssertionError, 'tracked span'):
            inspect_story(paragraphs(data), 'Header-default')

    def test_rejects_missing_native_change(self):
        data = story('Header-default').replace('w:ins', 'w:hyperlink')
        with self.assertRaisesRegex(AssertionError, 'native ins'):
            inspect_story(paragraphs(data), 'Header-default')

    def test_rejects_lost_header_reference(self):
        parts = source()
        parts['word/document.xml'] = parts['word/document.xml'].replace(b'<w:headerReference w:type="first" r:id="header-first"/>', b'')
        with self.assertRaisesRegex(AssertionError, 'missing header variants'):
            inspect_parts(parts)

    def test_rejects_body_corruption(self):
        parts = source()
        parts['word/document.xml'] = parts['word/document.xml'].replace(b'UNCHANGED', b'CHANGED')
        with self.assertRaisesRegex(AssertionError, 'unchanged body'):
            inspect_parts(parts)

    def test_rejects_lost_metadata(self):
        with self.assertRaisesRegex(AssertionError, 'reviewer changed'):
            inspect_story(paragraphs(story('Header-default').replace('Native reviewer', 'Someone')), 'Header-default')

    def test_rejects_lost_formatting(self):
        with self.assertRaisesRegex(AssertionError, 'bold formatting'):
            inspect_story(paragraphs(story('Header-default').replace('<w:b/>', '<w:b w:val="0"/>')), 'Header-default')


if __name__ == '__main__':
    unittest.main()
