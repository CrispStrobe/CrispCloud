#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Authored counterexamples for content operands hidden by equal cached text."""
from pathlib import Path
import tempfile
import unittest
import zipfile

from independent_semantic_cases import CASES, R, REL, W, package
from oracle import ROOT, compare_semantics, snapshot


class InlineSemanticsTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='inline-oracle-', dir=ROOT)
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.serial = 0

    def authored(self, case):
        path = self.directory / (case + '.docx')
        contract = CASES[case](path)
        return path, contract

    def mutate(self, source, replacements):
        self.serial += 1
        path = self.directory / f'mutation-{self.serial}.docx'
        with zipfile.ZipFile(source) as original, zipfile.ZipFile(path, 'x') as output:
            for name in original.namelist():
                value = original.read(name).decode()
                for part, before, after in replacements:
                    if part == name:
                        self.assertIn(before, value)
                        value = value.replace(before, after)
                output.writestr(name, value)
        return path

    def changes(self, before, after):
        return {difference['property'] for difference in
                compare_semantics(snapshot(before), snapshot(after))}

    def body(self, body, **kwargs):
        self.serial += 1
        path = self.directory / f'authored-{self.serial}.docx'
        package(path, body, **kwargs)
        return path

    def inline(self, source, kind):
        return [event for story in snapshot(source)['inlineContent']
                for event in story['items'] if event['kind'] == kind]

    def test_hyphen_controls_are_text_but_tab_properties_are_not(self):
        source, contract = self.authored('character-controls')
        data = snapshot(source)
        self.assertEqual('\n'.join(contract['mainParagraphs']), data['stories'][0]['text'])
        for token in ('noBreakHyphen', 'softHyphen'):
            mutation = self.mutate(source, [('word/document.xml', f'<w:{token}/>', '')])
            self.assertIn('stories', self.changes(source, mutation))
        mutation = self.mutate(source, [('word/document.xml', 'w:pos="720"', 'w:pos="1440"')])
        self.assertEqual(data['stories'], snapshot(mutation)['stories'])

    def test_symbol_operands_survive_hex_case_but_not_glyph_or_font_changes(self):
        source, contract = self.authored('symbol-glyphs')
        symbols = self.inline(source, 'symbol')
        self.assertEqual(contract['symbolGlyphs'],
                         [{key: item[key] for key in ('font', 'char')} for item in symbols])
        for before, after in [('F061', 'F062'), ('w:font="Symbol"', 'w:font="Wingdings"')]:
            mutation = self.mutate(source, [('word/document.xml', before, after)])
            self.assertEqual(snapshot(source)['stories'], snapshot(mutation)['stories'])
            self.assertIn('inlineContent', self.changes(source, mutation))
        lower = self.mutate(source, [('word/document.xml', 'F061', 'f061')])
        self.assertEqual(set(), self.changes(source, lower))
        removed = self.mutate(source, [('word/document.xml', '<w:sym w:font="Symbol" w:char="F061"/>', '')])
        self.assertIn('stories', self.changes(source, removed))

    def test_equal_cached_result_does_not_hide_changed_field_target_or_quotes(self):
        source, _ = self.authored('locked-fields')
        for before, after in [('REF Target_A', 'REF WrongTarget'),
                              ('QUOTE "LITERAL-β"', 'QUOTE "LITERAL-γ"'),
                              ('HYPERLINK \\l "Target_A"', 'HYPERLINK \\l Target_A')]:
            mutation = self.mutate(source, [('word/document.xml', before, after)])
            self.assertEqual(snapshot(source)['stories'], snapshot(mutation)['stories'])
            self.assertIn('inlineContent', self.changes(source, mutation))
        split = self.mutate(source, [('word/document.xml', ' REF Target_A \\h ',
                                    ' REF </w:instrText></w:r><w:r><w:instrText xml:space="preserve">Target_A \\h ')])
        self.assertEqual(set(), self.changes(source, split))

    def test_nested_fields_keep_phase_and_boundary_topology(self):
        body = '<w:p><w:r><w:fldChar w:fldCharType="begin"/></w:r><w:r><w:instrText> IF </w:instrText></w:r><w:r><w:fldChar w:fldCharType="begin"/></w:r><w:r><w:instrText> REF A </w:instrText></w:r><w:r><w:fldChar w:fldCharType="separate"/></w:r><w:r><w:t>INNER</w:t></w:r><w:r><w:fldChar w:fldCharType="end"/></w:r><w:r><w:instrText> = "INNER" "YES" "NO" </w:instrText></w:r><w:r><w:fldChar w:fldCharType="separate"/></w:r><w:r><w:t>YES</w:t></w:r><w:r><w:fldChar w:fldCharType="end"/></w:r></w:p>'
        source = self.body(body)
        fields = self.inline(source, 'field')
        self.assertEqual(2, len(fields))
        self.assertEqual([' IF ', {'field': 1}, ' = "INNER" "YES" "NO" '], fields[0]['instruction'])
        self.assertEqual(['INNER'], fields[1]['result'])
        self.assertEqual(['YES'], fields[0]['result'])
        broken = self.body(body.replace('<w:fldChar w:fldCharType="end"/>', '', 1))
        self.assertIn('inlineContent', self.changes(source, broken))
        self.assertIsNone(self.inline(broken, 'field')[0]['end'])

    def test_simple_field_and_property_decoy_instructions(self):
        source = self.body('<w:p><w:pPr><w:rPr><w:instrText>NOT CONTENT</w:instrText></w:rPr></w:pPr><w:fldSimple w:instr=" REF Actual "><w:r><w:t>CACHE</w:t></w:r></w:fldSimple></w:p>')
        fields = self.inline(source, 'field')
        self.assertEqual([' REF Actual '], fields[0]['instruction'])
        self.assertEqual(['CACHE'], fields[0]['result'])
        self.assertEqual([], self.inline(source, 'orphanFieldInstruction'))

    def test_note_anchors_resolve_content_and_shared_identity_not_raw_ids(self):
        source, _ = self.authored('note-joins')
        notes = self.inline(source, 'footnoteReference')
        self.assertEqual(['NOTE-A:α', 'NOTE-B:β'], [item['target']['text']['excerpt'] for item in notes])
        redirected = self.mutate(source, [('word/document.xml', 'w:id="19"', 'w:id="7"')])
        self.assertEqual(snapshot(source)['stories'], snapshot(redirected)['stories'])
        self.assertIn('inlineContent', self.changes(source, redirected))
        renamed = self.mutate(source, [('word/document.xml', 'w:id="19"', 'w:id="919"'),
                                      ('word/footnotes.xml', 'w:id="19"', 'w:id="919"')])
        self.assertEqual(set(), self.changes(source, renamed))
        identical = self.mutate(source, [('word/footnotes.xml', 'NOTE-B:β', 'NOTE-A:α')])
        shared = self.mutate(identical, [('word/document.xml', 'w:id="19"', 'w:id="7"')])
        self.assertIn('inlineContent', self.changes(identical, shared))

    def test_hyperlink_relationship_renaming_preserves_anchor_binding(self):
        relationships = f'<Relationships xmlns="{REL}"><Relationship Id="A" Type="{R}/hyperlink" Target="https://example.invalid/one" TargetMode="External"/><Relationship Id="B" Type="{R}/hyperlink" Target="https://example.invalid/two" TargetMode="External"/></Relationships>'
        source = self.body('<w:p><w:hyperlink r:id="A"><w:r><w:t>VISIBLE</w:t></w:r></w:hyperlink></w:p>', additional_parts={'word/_rels/document.xml.rels': relationships})
        redirected = self.mutate(source, [('word/document.xml', 'r:id="A"', 'r:id="B"')])
        self.assertEqual(snapshot(source)['externalLinks'], snapshot(redirected)['externalLinks'])
        self.assertIn('inlineContent', self.changes(source, redirected))
        renamed = self.mutate(source, [('word/document.xml', 'r:id="A"', 'r:id="renamed"'), ('word/_rels/document.xml.rels', 'Id="A"', 'Id="renamed"')])
        self.assertEqual(set(), self.changes(source, renamed))

    def test_same_field_text_in_a_different_story_remains_a_change(self):
        field = '<w:p><w:r><w:fldChar w:fldCharType="begin"/></w:r><w:r><w:instrText> REF A </w:instrText></w:r><w:r><w:fldChar w:fldCharType="separate"/></w:r><w:r><w:t>CACHE</w:t></w:r><w:r><w:fldChar w:fldCharType="end"/></w:r></w:p>'
        source = self.body(field, additional_parts={'word/header.xml': f'<w:hdr xmlns:w="{W}">' + field + '</w:hdr>'}, relationships=[('header', 'header', 'header.xml')])
        changed = self.mutate(source, [('word/header.xml', ' REF A ', ' REF B ')])
        self.assertEqual(snapshot(source)['stories'], snapshot(changed)['stories'])
        events = snapshot(changed)['inlineContent']
        self.assertEqual({'header', 'main'}, {event['story'] for event in events})
        self.assertIn('inlineContent', self.changes(source, changed))


    def test_bound_font_charset_changes_are_not_hidden_by_equal_pua_text(self):
        body = '<w:p><w:r><w:rPr><w:rFonts w:ascii="Wingdings" w:hAnsi="Wingdings"/></w:rPr><w:t>\uf0fc</w:t></w:r></w:p>'

        def font_package(value='02', path='fontTable.xml', rid='fonts', related=True):
            table = f'<w:fonts xmlns:w="{W}"><w:font w:name="Wingdings"><w:charset w:val="{value}"/></w:font></w:fonts>'
            return self.body(body, additional_parts={'word/' + path: table},
                             relationships=[(rid, 'fontTable', path)] if related else [])

        source = font_package()
        changed = font_package('01')
        self.assertEqual(6, snapshot(source)['oracleSchemaVersion'])
        self.assertEqual(snapshot(source)['stories'], snapshot(changed)['stories'])
        self.assertEqual(snapshot(source)['paragraphs'], snapshot(changed)['paragraphs'])
        self.assertEqual({'fontCharsets'}, self.changes(source, changed))
        self.assertEqual(set(), self.changes(source, font_package(path='metadata/fonts.xml', rid='renamed')))
        self.assertEqual(set(), self.changes(font_package('B2'), font_package('b2')))
        self.assertEqual(snapshot(font_package(related=False))['fontCharsets'], [])
        self.assertIn('fontCharsets', self.changes(source, font_package(related=False)))

    def test_font_declaration_order_normalizes_but_duplicates_and_absence_remain(self):
        first = '<w:font w:name="A"><w:charset w:val="02"/></w:font>'
        second = '<w:font w:name="B"><w:charset w:val="01"/></w:font>'

        def font_package(content, root='fonts'):
            return self.body('<w:p/>', additional_parts={'word/fonts.xml':
                f'<w:{root} xmlns:w="{W}">{content}</w:{root}>'},
                relationships=[('fonts', 'fontTable', 'fonts.xml')])

        source = font_package(first + second)
        self.assertEqual(set(), self.changes(source, font_package(second + first)))
        self.assertEqual({'fontCharsets'}, self.changes(source, font_package(first + first + second)))
        self.assertEqual({'fontCharsets'}, self.changes(source, font_package(first.replace('<w:charset w:val="02"/>', '') + second)))
        with self.assertRaisesRegex(ValueError, 'fontTable'):
            snapshot(font_package(first, root='document'))


if __name__ == '__main__':
    unittest.main()
