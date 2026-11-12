# SPDX-License-Identifier: MPL-2.0
"""Adversarial, independently authored OOXML controls for the fidelity oracle."""
from pathlib import Path
import tempfile
import unittest
from zipfile import ZipFile
import xml.etree.ElementTree as ET

from oracle import ROOT, W, R, REL, compare_semantics, snapshot
from structure import NS, review_text

DECL = ' '.join(f'xmlns:{prefix}="{uri}"' for prefix, uri in NS.items())
DECL += f' xmlns:r="{R}"'


def paragraph(text, props=''):
    return f'<w:p>{props}<w:r><w:t>{text}</w:t></w:r></w:p>'


def relationship(identifier, kind, target):
    return f'<Relationship Id="{identifier}" Type="{R}/{kind}" Target="{target}"/>'


def styles(body):
    return f'<w:styles {DECL}>{body}</w:styles>'


def numbering(body):
    return f'<w:numbering {DECL}>{body}</w:numbering>'


class StructuralOracleTest(unittest.TestCase):
    def setUp(self):
        (ROOT / 'build').mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=ROOT / 'build')
        self.addCleanup(self.temp.cleanup)
        self.next_file = 0

    def package(self, body, auxiliary=None, *, main='word/document.xml'):
        auxiliary = auxiliary or {}
        parts = {main: f'<w:document {DECL}><w:body>{body}</w:body></w:document>',
                 '_rels/.rels': f'<Relationships xmlns="{REL}">' +
                 relationship('root', 'officeDocument', main) + '</Relationships>'}
        rels = []
        for index, (kind, (path, content)) in enumerate(auxiliary.items()):
            parts[path] = content
            rels.append(relationship(str(index), kind, '/' + path))
        if rels:
            directory, name = main.rsplit('/', 1)
            parts[directory + '/_rels/' + name + '.rels'] = (
                f'<Relationships xmlns="{REL}">' + ''.join(rels) + '</Relationships>')
        self.next_file += 1
        path = Path(self.temp.name) / f'{self.next_file}.docx'
        with ZipFile(path, 'w') as archive:
            for name, content in parts.items():
                archive.writestr(name, content)
        return snapshot(path)

    def assert_structure_change(self, reference, actual):
        # These are deliberately count-preserving mutations.
        self.assertEqual(reference['counts'], actual['counts'])
        self.assertIn('structure', {d['property'] for d in compare_semantics(reference, actual)})

    def table(self, props='<w:tblStyle w:val="Child"/>'):
        return ('<w:tbl><w:tblPr>' + props + '</w:tblPr>'
                '<w:tblGrid><w:gridCol w:w="2000"/></w:tblGrid>'
                '<w:tr><w:tc><w:tcPr><w:tcW w:w="2000" w:type="dxa"/>'
                '</w:tcPr>' + paragraph('Cell') + '</w:tc></w:tr></w:tbl>')

    def test_conditional_style_change_and_direct_flattening_are_detected(self):
        definitions = ('<w:style w:type="table" w:styleId="Base">'
                       '<w:tblPr><w:tblBorders><w:top w:val="single" w:sz="8"/>'
                       '</w:tblBorders></w:tblPr></w:style>'
                       '<w:style w:type="table" w:styleId="Child"><w:basedOn w:val="Base"/>'
                       '<w:tblStylePr w:type="firstRow"><w:tcPr><w:shd w:fill="FF0000"/>'
                       '</w:tcPr></w:tblStylePr></w:style>')
        source = self.package(self.table(), {'styles': ('moved/styles.xml', styles(definitions))})
        changed = self.package(self.table(), {'styles': ('moved/styles.xml', styles(definitions.replace('FF0000', '00FF00')))})
        self.assert_structure_change(source, changed)
        flat = self.package(self.table('<w:tblBorders><w:top w:val="single" w:sz="8"/></w:tblBorders>'))
        self.assert_structure_change(source, flat)

    def test_row_origin_cell_merge_and_unequal_columns_are_not_counts(self):
        body = self.table('') + '<w:sectPr><w:cols w:num="2" w:equalWidth="0"><w:col w:w="1000" w:space="360"/><w:col w:w="3000"/></w:cols></w:sectPr>'
        source = self.package(body)
        for changed in [body.replace('<w:tblPr>', '<w:tblPr><w:tblInd w:w="108" w:type="dxa"/>'),
                        body.replace('<w:tcPr>', '<w:tcPr><w:vMerge w:val="restart"/>'),
                        body.replace('w:w="1000"', 'w:w="2000"')]:
            self.assert_structure_change(source, self.package(changed))

    def test_style_cycle_and_unresolved_style_fail(self):
        cyclic = '<w:style w:type="table" w:styleId="Child"><w:basedOn w:val="Child"/></w:style>'
        with self.assertRaisesRegex(ValueError, 'Cyclic style'):
            self.package(self.table(), {'styles': ('s/styles.xml', styles(cyclic))})
        with self.assertRaisesRegex(ValueError, 'Unresolved style'):
            self.package(self.table())

    def numbered(self, ids=('1', '1', '2', '2')):
        return ''.join(paragraph(str(i), f'<w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="{n}"/></w:numPr></w:pPr>')
                       for i, n in enumerate(ids))

    def numbers(self, start='5', restart='0'):
        return numbering('<w:abstractNum w:abstractNumId="9"><w:lvl w:ilvl="0">'
                         '<w:start w:val="1"/><w:numFmt w:val="decimal"/>'
                         f'<w:lvlRestart w:val="{restart}"/><w:lvlText w:val="%1."/>'
                         '</w:lvl></w:abstractNum><w:num w:numId="1"><w:abstractNumId w:val="9"/></w:num>'
                         '<w:num w:numId="2"><w:abstractNumId w:val="9"/><w:lvlOverride w:ilvl="0">'
                         f'<w:startOverride w:val="{start}"/></w:lvlOverride></w:num>')

    def test_list_restart_level_and_continuation_graph(self):
        source = self.package(self.numbered(), {'numbering': ('lists/n.xml', self.numbers())})
        for number in (self.numbers(start='1'), self.numbers(restart='1')):
            self.assert_structure_change(source, self.package(self.numbered(), {'numbering': ('lists/n.xml', number)}))
        collapsed = self.package(self.numbered(('1', '1', '1', '1')), {'numbering': ('lists/n.xml', self.numbers())})
        self.assert_structure_change(source, collapsed)
        # Unused ids/part locations can change without a false difference.
        renamed = self.package(self.numbered().replace('w:val="2"', 'w:val="77"'),
                               {'numbering': ('other/renamed.xml', self.numbers().replace('w:numId="2"', 'w:numId="77"'))})
        self.assertEqual(source['structure'], renamed['structure'])

    def test_numbering_inherited_from_paragraph_style(self):
        style = '<w:style w:type="paragraph" w:styleId="List"><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr></w:style>'
        body = paragraph('Item', '<w:pPr><w:pStyle w:val="List"/></w:pPr>')
        result = self.package(body, {'styles': ('s.xml', styles(style)), 'numbering': ('n.xml', self.numbers())})
        self.assertEqual('Item', result['structure']['stories'][0]['numbering'][0]['text'])
        with self.assertRaisesRegex(ValueError, 'Unresolved numbering instance'):
            self.package(body, {'styles': ('s.xml', styles(style))})

    def boxes(self, successor='#b', height='20pt'):
        return ('<w:p><w:r><w:pict><v:rect id="a" style="width:100pt;height:' + height +
                ';mso-next-textbox:' + successor + '"><v:textbox inset="1pt,2pt,3pt,4pt">'
                '<w:txbxContent>' + paragraph('One two three four') + '</w:txbxContent></v:textbox></v:rect>'
                '<v:rect id="b" style="width:100pt;height:100pt"><v:textbox><w:txbxContent><w:p/>'
                '</w:txbxContent></v:textbox></v:rect></w:pict></w:r></w:p>')

    def test_textbox_chain_geometry_and_margins(self):
        body = self.boxes()
        source = self.package(body)
        for changed in (body.replace(';mso-next-textbox:#b', ''), self.boxes(height='40pt'),
                        body.replace('1pt,2pt,3pt,4pt', '0pt,0pt,0pt,0pt')):
            self.assert_structure_change(source, self.package(changed))
        renamed = body.replace('id="a"', 'id="x"').replace('id="b"', 'id="y"').replace('#b', '#y')
        self.assertEqual(source['structure'], self.package(renamed)['structure'])

    def test_dangling_cycle_and_conflicting_box_links_fail(self):
        with self.assertRaisesRegex(ValueError, 'Unresolved linked textbox'):
            self.package(self.boxes('#absent'))
        with self.assertRaisesRegex(ValueError, 'Cyclic textbox'):
            self.package(self.boxes('#a'))
        with self.assertRaisesRegex(ValueError, 'Conflicting textbox successors'):
            self.package(self.boxes().replace('<v:textbox inset=', '<v:textbox style="mso-next-textbox:#a" inset='))

    def comment_aux(self, parent='00000001', done='0'):
        comments = (f'<w:comments {DECL}><w:comment w:id="2" w:author="B">'
                    '<w:p w14:paraId="00000002"><w:r><w:t>Reply</w:t></w:r></w:p></w:comment>'
                    '<w:comment w:id="1" w:author="A"><w:p w14:paraId="00000000"><w:r><w:t>Opening</w:t></w:r></w:p>'
                    '<w:p w14:paraId="00000001"><w:r><w:t>Root final</w:t></w:r></w:p></w:comment></w:comments>')
        extension = (f'<w15:commentsEx {DECL}><w15:commentEx w15:paraId="00000002" '
                     f'w15:paraIdParent="{parent}" w15:done="{done}"/>'
                     '<w15:commentEx w15:paraId="00000001" w15:done="1"/></w15:commentsEx>')
        return {'comments': ('review/notes.xml', comments), 'commentsExtended': ('review/replies.xml', extension)}

    def test_comment_parent_and_resolved_state(self):
        source = self.package(paragraph('Body'), self.comment_aux(), main='custom/main.xml')
        self.assertEqual(1, source['structure']['comments'][0]['parent'])
        self.assert_structure_change(source, self.package(paragraph('Body'), self.comment_aux(done='1')))
        with self.assertRaisesRegex(ValueError, 'Unresolved comment parent'):
            self.package(paragraph('Body'), self.comment_aux(parent='00000000'))
        with self.assertRaisesRegex(ValueError, 'Cyclic comment thread'):
            self.package(paragraph('Body'), self.comment_aux(parent='00000002'))

    def test_comment_hex_ids_and_boolean_aliases_are_semantic_values(self):
        auxiliary = self.comment_aux()
        auxiliary = {kind: (path, value.replace('00000001', '00ABCD01'))
                     for kind, (path, value) in auxiliary.items()}
        source = self.package(paragraph('Body'), auxiliary)
        path, extension = auxiliary['commentsExtended']
        auxiliary['commentsExtended'] = (path, extension.replace('00ABCD01', '00abcd01').replace('w15:done="1"', 'w15:done="on"'))
        self.assertEqual(source['structure'], self.package(paragraph('Body'), auxiliary)['structure'])

    def test_prior_section_snapshot_does_not_add_a_current_section(self):
        body = paragraph('Body') + ('<w:sectPr><w:pgSz w:w="12240" w:h="15840"/>'
                '<w:sectPrChange w:id="2" w:author="A"><w:sectPr>'
                '<w:pgSz w:w="10000" w:h="14000"/></w:sectPr></w:sectPrChange></w:sectPr>')
        result = self.package(body)
        self.assertEqual(1, len(result['sections']))
        self.assertEqual(1, len(result['structure']['stories'][0]['sections']))
        self.assertEqual('sectPrChange', result['structure']['stories'][0]['revisions'][0]['kind'])

    def test_review_views_preserve_exact_spans_and_paragraph_mark_merges(self):
        body = ('<w:p><w:pPr><w:rPr><w:del w:id="3"/></w:rPr></w:pPr>'
                '<w:r><w:t>A</w:t></w:r><w:ins w:id="1"><w:r><w:t>new</w:t></w:r></w:ins>'
                '<w:del w:id="2"><w:r><w:delText>old</w:delText></w:r></w:del></w:p>' + paragraph('B'))
        result = self.package(body)['structure']['stories'][0]
        self.assertEqual('AnewB\n', result['acceptedText'])
        self.assertEqual('Aold\nB\n', result['rejectedText'])
        self.assertEqual(3, len(result['revisions']))

    def test_move_views_and_row_revisions_are_not_flat_text(self):
        body = ('<w:p><w:moveFrom w:id="1"><w:r><w:delText>Here</w:delText></w:r></w:moveFrom>'
                '<w:moveTo w:id="2"><w:r><w:t>There</w:t></w:r></w:moveTo></w:p>'
                '<w:tbl><w:tr><w:trPr><w:del w:id="3"/></w:trPr><w:tc>' + paragraph('Old row') + '</w:tc></w:tr></w:tbl>')
        tree = ET.fromstring(f'<w:body {DECL}>{body}</w:body>')
        self.assertEqual('There\n', review_text(tree, 'accepted'))
        self.assertEqual('Here\nOld row\n', review_text(tree, 'rejected'))

    def test_revision_author_previous_state_and_ink_mutations(self):
        body = ('<w:p><w:pPr><w:jc w:val="right"/><w:pPrChange w:id="1" w:author="A">'
                '<w:pPr><w:jc w:val="left"/></w:pPr></w:pPrChange></w:pPr>'
                '<w:r><w:t>Text</w:t><w:pict><o:ink i="AQID"/></w:pict></w:r></w:p>')
        source = self.package(body)
        for changed in (body.replace('w:author="A"', 'w:author="B"'),
                        body.replace('w:val="left"', 'w:val="center"'),
                        body.replace('i="AQID"', 'i="BAUG"')):
            self.assert_structure_change(source, self.package(changed))

    def test_compatibility_false_is_not_absence(self):
        body = paragraph('Body')
        settings = f'<w:settings {DECL}><w:compat><w:doNotUseHTMLParagraphAutoSpacing w:val="0"/></w:compat></w:settings>'
        source = self.package(body, {'settings': ('s.xml', settings)})
        self.assert_structure_change(source, self.package(body, {'settings': ('s.xml', settings.replace('w:val="0"', 'w:val="1"'))}))
        self.assert_structure_change(source, self.package(body))


if __name__ == '__main__':
    unittest.main()
