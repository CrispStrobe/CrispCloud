"""Authored native positives plus destructive controls for auxiliary SDT evidence."""
import unittest
from xml.etree import ElementTree as ET

from auxiliary_content_control_oracle import EXT, NS, P, R, STORIES, W, W14, W15, inspect_parts


def authored(*, edited=False, wrapped_comment=True):
    """Build valid evidence independently of any engine-produced package."""
    parts = {}
    rels = []
    references = []
    prefix = 'Changed' if edited else 'Original'
    for index, story in enumerate(STORIES):
        if story == 'footer_default':
            paragraph = ('<w:p><w:pPr><w:jc w:val="center"/></w:pPr>'
                         '<w:r><w:fldChar w:fldCharType="begin"/></w:r>'
                         '<w:r><w:instrText>PAGE \\* MERGEFORMAT</w:instrText></w:r>'
                         '<w:r><w:fldChar w:fldCharType="separate"/></w:r>'
                         '<w:r><w:t>1</w:t></w:r>'
                         '<w:r><w:fldChar w:fldCharType="end"/></w:r></w:p>')
        else:
            anchor = ' w14:paraId="00000077"' if story == 'comments' else ''
            bold = '<w:rPr><w:b/></w:rPr>' if edited else ''
            paragraph = (f'<w:p{anchor}><w:r>{bold}<w:t>{prefix} {story}</w:t></w:r>'
                         '<w:hyperlink r:id="h"><w:r><w:t> link</w:t></w:r></w:hyperlink></w:p>')
        content = paragraph
        native_ids = [700 + index * 2, 701 + index * 2] if story != 'comments' or wrapped_comment else []
        for native_id in reversed(native_ids):
            content = (f'<w:sdt><w:sdtPr><w:id w:val="{native_id}"/>'
                       f'<w:alias w:val="Auxiliary {native_id}"/>'
                       f'<w:tag w:val="{story}-{native_id}"/>'
                       '<w:lock w:val="unlocked"/><w:richText/></w:sdtPr>'
                       '<w:sdtEndPr><w:rPr><w:color w:val="123456"/></w:rPr></w:sdtEndPr>'
                       f'<w:sdtContent>{content}</w:sdtContent></w:sdt>')
        kind = story.split('_')[0]
        root = 'comments' if story == 'comments' else 'hdr' if kind == 'header' else 'ftr'
        if story == 'comments':
            content = '<w:comment w:id="7">' + content + '</w:comment>'
        parts['word/' + story + '.xml'] = (
            f'<w:{root} xmlns:w="{W}" xmlns:r="{R}" xmlns:w14="{W14}">{content}</w:{root}>'
        ).encode()
        parts['word/_rels/' + story + '.xml.rels'] = (
            f'<Relationships xmlns="{P}"><Relationship Id="h" Type="{R}/hyperlink" '
            f'TargetMode="External" Target="https://example.test/{story}"/></Relationships>'
        ).encode()
        rels.append(f'<Relationship Id="s{index}" Type="{R}/{kind}" Target="{story}.xml"/>')
        if story != 'comments':
            references.append(f'<w:{kind}Reference w:type="{story.split("_")[1]}" r:id="s{index}"/>')
    rels.append(f'<Relationship Id="ext" Type="{EXT}" Target="extended.xml"/>')
    parts['word/_rels/document.xml.rels'] = (
        f'<Relationships xmlns="{P}">{"".join(rels)}</Relationships>').encode()
    parts['word/extended.xml'] = (
        f'<w15:commentsEx xmlns:w15="{W15}"><w15:commentEx '
        'w15:paraId="00000077" w15:done="1"/></w15:commentsEx>').encode()
    body = 'Body edited' if edited else 'Body'
    parts['word/document.xml'] = (
        f'<w:document xmlns:w="{W}" xmlns:r="{R}"><w:body><w:p><w:r><w:t>{body}</w:t>'
        f'</w:r></w:p><w:sectPr>{"".join(references)}</w:sectPr></w:body></w:document>').encode()
    inspect_parts(parts, edited=edited, wrapped_comment=wrapped_comment)
    return parts


class AuxiliaryControlOracleTest(unittest.TestCase):
    def test_independent_original_and_edited_positives(self):
        for edited in [False, True]:
            self.assertEqual(inspect_parts(authored(edited=edited), edited=edited)['native_controls'], 14)
            plain = authored(edited=edited, wrapped_comment=False)
            self.assertEqual(inspect_parts(plain, edited=edited, wrapped_comment=False)['native_controls'], 12)

    def test_plain_comment_visual_case_cannot_satisfy_the_wrapped_comment_contract(self):
        with self.assertRaisesRegex(AssertionError, 'wrapper flattened'):
            inspect_parts(authored(wrapped_comment=False))

    def test_rejects_flattened_wrapper_with_text_retained(self):
        parts = authored()
        root = ET.fromstring(parts['word/header_default.xml'])
        paragraph = root.find('.//w:p', NS)
        root.clear()
        root.append(paragraph)
        parts['word/header_default.xml'] = ET.tostring(root)
        with self.assertRaisesRegex(AssertionError, 'wrapper flattened'):
            inspect_parts(parts)

    def test_rejects_changed_id_alias_tag_and_end_properties(self):
        for selector in ['w:sdt/w:sdtPr/w:id', 'w:sdt/w:sdtPr/w:alias',
                         'w:sdt/w:sdtPr/w:tag', 'w:sdt/w:sdtEndPr/w:rPr/w:color']:
            with self.subTest(selector=selector):
                parts = authored()
                root = ET.fromstring(parts['word/header_default.xml'])
                root.find(selector, NS).set(f'{{{W}}}val', 'lost')
                parts['word/header_default.xml'] = ET.tostring(root)
                with self.assertRaises(AssertionError):
                    inspect_parts(parts)

    def test_rejects_page_instruction_or_field_boundary_loss(self):
        for selector in ['.//w:instrText', './/w:fldChar']:
            with self.subTest(selector=selector):
                parts = authored()
                root = ET.fromstring(parts['word/footer_default.xml'])
                node = root.find(selector, NS)
                if selector.endswith('instrText'):
                    node.text = 'NUMPAGES'
                else:
                    node.set(f'{{{W}}}fldCharType', 'end')
                parts['word/footer_default.xml'] = ET.tostring(root)
                with self.assertRaisesRegex(AssertionError, 'PAGE field'):
                    inspect_parts(parts)

    def test_rejects_link_resolution_in_the_wrong_story_part(self):
        parts = authored()
        del parts['word/_rels/header_default.xml.rels']
        with self.assertRaisesRegex(AssertionError, 'relationship ownership'):
            inspect_parts(parts)

    def test_rejects_lost_controlled_text_or_formatting(self):
        for changed in ['text', 'bold']:
            with self.subTest(changed=changed):
                parts = authored(edited=True)
                root = ET.fromstring(parts['word/header_default.xml'])
                if changed == 'text':
                    root.find('.//w:p/w:r/w:t', NS).text = 'Gone'
                else:
                    properties = root.find('.//w:p/w:r/w:rPr', NS)
                    properties.remove(properties.find('w:b', NS))
                parts['word/header_default.xml'] = ET.tostring(root)
                with self.assertRaises(AssertionError):
                    inspect_parts(parts, edited=True)

    def test_rejects_detached_comment_resolution(self):
        parts = authored()
        root = ET.fromstring(parts['word/comments.xml'])
        root.find('.//w:p', NS).set(f'{{{W14}}}paraId', '00000088')
        parts['word/comments.xml'] = ET.tostring(root)
        with self.assertRaisesRegex(AssertionError, 'paragraph anchor'):
            inspect_parts(parts)


if __name__ == '__main__':
    unittest.main()
