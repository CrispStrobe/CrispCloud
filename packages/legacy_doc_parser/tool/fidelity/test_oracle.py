# SPDX-License-Identifier: MPL-2.0
import copy
import tempfile
import unittest
import zipfile
from pathlib import Path
from oracle import ROOT, NS, W, compare_layout, compare_semantics, load_corpus, snapshot


class OracleRegressionTest(unittest.TestCase):
    def test_pinned_corpus_is_not_replaced_with_converter_output(self):
        manifest = load_corpus()
        pinned = [case for case in manifest['cases'] if case['source'] in ('quds', 'existing-package-fixture')]
        self.assertEqual(11, len(pinned))
        self.assertEqual('ca9853b5b08784beac50df5680176cb4e5b3cb25', manifest['sources']['quds']['commit'])
        for case in manifest['cases']:
            if case['path'].endswith('.docx'):
                self.assertTrue(snapshot(ROOT / case['path'])['stories'])

    def test_lost_story_image_and_last_table_are_detected(self):
        original = snapshot(ROOT / 'test/fixtures/fidelity/word.docx')
        damaged = copy.deepcopy(original)
        damaged['stories'] = [s for s in damaged['stories'] if s['kind'] == 'main']
        damaged['imageDigests'] = []
        damaged['counts']['tbl'] = 0
        keys = {d['property'] for d in compare_semantics(original, damaged)}
        self.assertTrue({'stories', 'imageDigests', 'counts.tbl'} <= keys)

    def test_relocated_thread_parts_are_followed(self):
        result = snapshot(ROOT / 'test/fixtures/fidelity/comment-threads.docx')
        self.assertEqual(3, result['counts']['comment'])
        self.assertEqual(1, result['counts']['commentThreads'])
        self.assertTrue(any('Reply arrived first' in story['text'] for story in result['stories']))

    def test_same_text_on_different_pages_is_not_exact_pagination(self):
        page = {'size': [612.0, 792.0], 'words': [{'text': 'Marker', 'box': [10., 20., 30., 40.]}]}
        self.assertFalse(compare_layout([page], [page, page])['matchesWithinTolerance'])
        changed = copy.deepcopy(page)
        changed['words'][0]['box'][1] += 1
        self.assertFalse(compare_layout([page], [changed])['matchesWithinTolerance'])
        changed['words'][0]['box'][1] -= .9
        self.assertTrue(compare_layout([page], [changed])['matchesWithinTolerance'])


class StructuralOracleTest(unittest.TestCase):
    """Authored OOXML mutation probes, independent of Dart-generated output."""
    def package(self, body, *, styles=None, numbering=None, extra=None):
        temporary = tempfile.TemporaryDirectory(prefix='oracle-test-', dir=ROOT)
        self.addCleanup(temporary.cleanup)
        path = Path(temporary.name) / 'fixture.docx'
        declarations = ' '.join('xmlns:' + prefix + '="' + uri + '"' for prefix, uri in NS.items())
        document = '<w:document ' + declarations + '><w:body>' + body + '</w:body></w:document>'
        parts = {'word/document.xml': document,
                 '[Content_Types].xml': '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="xml" ContentType="application/xml"/><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/></Types>',
                 '_rels/.rels': '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="office1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'}
        rels = []
        for kind, value in [('styles', styles), ('numbering', numbering)]:
            if value is not None:
                parts['word/' + kind + '.xml'] = '<w:' + kind + ' xmlns:w="' + W + '">' + value + '</w:' + kind + '>'
                rels.append('<Relationship Id="' + kind + '1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/' + kind + '" Target="' + kind + '.xml"/>')
        parts['word/_rels/document.xml.rels'] = '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' + ''.join(rels) + '</Relationships>'
        parts.update(extra or {})
        with zipfile.ZipFile(path, 'w') as archive:
            for name, value in parts.items():
                archive.writestr(name, value)
        return snapshot(path)

    def changes(self, first, second):
        return {entry['property'] for entry in compare_semantics(first, second)}

    @staticmethod
    def paragraph(text, properties=''):
        return '<w:p>' + ('<w:pPr>' + properties + '</w:pPr>' if properties else '') + '<w:r><w:t>' + text + '</w:t></w:r></w:p>'

    def test_revision_author_date_and_previous_format_mutations_are_detected(self):
        body = '''<w:p><w:pPr><w:pPrChange w:id="9" w:author="Alice" w:date="2026-11-12T09:00:00Z"><w:pPr><w:spacing w:before="120"/></w:pPr></w:pPrChange><w:rPr><w:ins w:id="10" w:author="Mark author" w:date="2026-11-12T10:00:00Z"/></w:rPr></w:pPr><w:ins w:id="11" w:author="Alice" w:date="2026-11-12T11:00:00Z"><w:r><w:rPr><w:i/><w:rPrChange w:id="12" w:author="Bob" w:date="2026-11-12T12:00:00Z"><w:rPr><w:b/></w:rPr></w:rPrChange></w:rPr><w:t>Visible</w:t></w:r></w:ins><w:del w:id="13" w:author="Alice" w:date="2026-11-12T13:00:00Z"><w:r><w:delText>Removed</w:delText></w:r></w:del></w:p>'''
        original = self.package(body)
        entries = original['revisions'][0]['items']
        self.assertEqual(5, len(entries))
        self.assertTrue(any(item['scope'] == 'paragraphMark' for item in entries))
        self.assertEqual('Bob', next(item for item in entries if item['kind'] == 'rPrChange')['author'])
        for damaged in [body.replace('w:author="Alice"', 'w:author="Mallory"'),
                        body.replace('T12:00:00Z', 'T12:01:00Z'),
                        body.replace('<w:rPr><w:b/></w:rPr>', '<w:rPr><w:strike/></w:rPr>'),
                        body.replace('w:before="120"', 'w:before="240"')]:
            actual = self.package(damaged)
            self.assertEqual(original['counts'], actual['counts'])
            self.assertEqual(original['stories'], actual['stories'])
            self.assertIn('revisions', self.changes(original, actual))
        renumbered = body
        for old, new in [('9', '109'), ('10', '110'), ('11', '111'), ('12', '112'), ('13', '113')]:
            renumbered = renumbered.replace('w:id="' + old + '"', 'w:id="' + new + '"')
        self.assertEqual([], compare_semantics(original, self.package(renumbered)))

    def test_revision_range_topology_survives_identity_renumbering(self):
        body = '<w:p><w:moveFromRangeStart w:id="8" w:author="A"/><w:r><w:t>X</w:t></w:r><w:moveFromRangeEnd w:id="8"/></w:p>'
        original = self.package(body)
        self.assertEqual([], compare_semantics(original, self.package(body.replace('w:id="8"', 'w:id="92"'))))
        broken = self.package(body.replace('<w:moveFromRangeEnd w:id="8"', '<w:moveFromRangeEnd w:id="9"'))
        self.assertIn('revisions', self.changes(original, broken))

    def test_revision_moved_between_identical_text_keeps_its_anchor(self):
        run = '<w:r><w:t>Same</w:t></w:r>'
        revision = '<w:ins w:id="1" w:author="Alice">' + run + '</w:ins>'
        first = self.package('<w:p>' + revision + run + '</w:p>')
        second = self.package('<w:p>' + run + revision + '</w:p>')
        self.assertEqual(first['counts'], second['counts'])
        self.assertEqual(first['stories'], second['stories'])
        self.assertEqual(0, first['revisions'][0]['items'][0]['offsetInParagraph'])
        self.assertEqual(4, second['revisions'][0]['items'][0]['offsetInParagraph'])
        self.assertIn('revisions', self.changes(first, second))

    def table_fixture(self):
        styles = '''<w:style w:type="table" w:styleId="BaseStyle"><w:tblPr><w:tblBorders><w:top w:val="single" w:sz="8" w:color="112233"/></w:tblBorders></w:tblPr></w:style><w:style w:type="table" w:styleId="AccentStyle"><w:basedOn w:val="BaseStyle"/><w:tblStylePr w:type="firstRow"><w:tcPr><w:shd w:fill="AABBCC"/></w:tcPr></w:tblStylePr></w:style>'''
        inner = '<w:tbl><w:tblGrid><w:gridCol w:w="800"/></w:tblGrid><w:tr><w:tc>' + self.paragraph('Inside') + '</w:tc></w:tr></w:tbl>'
        outer = '<w:tbl><w:tblPr><w:tblStyle w:val="AccentStyle"/><w:tblLook w:firstRow="1"/></w:tblPr><w:tblGrid><w:gridCol w:w="2400"/></w:tblGrid><w:tr><w:trPr><w:cantSplit/></w:trPr><w:tc><w:tcPr><w:tcW w:w="2400" w:type="dxa"/><w:vMerge w:val="restart"/><w:tcMar><w:left w:w="120" w:type="dxa"/></w:tcMar></w:tcPr>' + self.paragraph('Outside') + inner + self.paragraph('Tail') + '</w:tc></w:tr></w:tbl>'
        return outer, inner, styles

    def test_equal_table_counts_do_not_hide_depth_style_or_cell_format_loss(self):
        body, inner, styles = self.table_fixture()
        original = self.package(body, styles=styles)
        tables = original['tables'][0]['items']
        self.assertEqual([0, 1], [table['depth'] for table in tables])
        self.assertEqual([1], tables[0]['rows'][0]['cells'][0]['nestedTables'])
        mutants = [(body.replace(inner, '') + inner, styles),
                   (body, styles.replace('112233', '445566')),
                   (body, styles.replace('AABBCC', 'DDDDDD')),
                   (body.replace('w:val="restart"', 'w:val="continue"'), styles),
                   (body.replace('w:w="120"', 'w:w="121"'), styles)]
        for changed_body, changed_styles in mutants:
            actual = self.package(changed_body, styles=changed_styles)
            self.assertEqual(original['counts']['tbl'], actual['counts']['tbl'])
            self.assertEqual(original['counts']['tc'], actual['counts']['tc'])
            self.assertIn('tables', self.changes(original, actual))
        renamed = self.package(body.replace('AccentStyle', 'RenamedA'), styles=styles.replace('AccentStyle', 'RenamedA').replace('BaseStyle', 'RenamedB'))
        self.assertEqual([], compare_semantics(original, renamed))

    def numbering_fixture(self):
        numbering = '''<w:abstractNum w:abstractNumId="10"><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%1."/></w:lvl><w:lvl w:ilvl="1"><w:start w:val="3"/><w:numFmt w:val="lowerLetter"/><w:lvlText w:val="%1.%2)"/></w:lvl></w:abstractNum><w:num w:numId="17"><w:abstractNumId w:val="10"/><w:lvlOverride w:ilvl="0"><w:startOverride w:val="5"/></w:lvlOverride></w:num><w:num w:numId="18"><w:abstractNumId w:val="10"/><w:lvlOverride w:ilvl="0"><w:startOverride w:val="5"/></w:lvlOverride></w:num>'''
        body = ''.join(self.paragraph(text, '<w:numPr><w:ilvl w:val="' + str(level) + '"/><w:numId w:val="17"/></w:numPr>')
                       for text, level in [('A', 0), ('B', 1), ('C', 0), ('D', 1)])
        return body, numbering

    def test_numbering_resolves_overrides_restart_and_concrete_continuation(self):
        body, numbering = self.numbering_fixture()
        original = self.package(body, numbering=numbering)
        items = original['numbering'][0]['items']
        self.assertEqual([5, 3, 6, 3], [item['counter'] for item in items])
        self.assertEqual([None, 0, 1, 2], [item['previousParagraph'] for item in items])
        self.assertEqual([0, 0, 0, 0], [item['instance'] for item in items])
        changed = self.package(body, numbering=numbering.replace('w:startOverride w:val="5"', 'w:startOverride w:val="7"'))
        self.assertEqual(original['counts'], changed['counts'])
        self.assertIn('numbering', self.changes(original, changed))
        parts = body.split('</w:p>')
        broken = '</w:p>'.join(parts[:2] + [part.replace('w:val="17"', 'w:val="18"') for part in parts[2:]])
        self.assertIn('numbering', self.changes(original, self.package(broken, numbering=numbering)))
        never = numbering.replace('<w:numFmt w:val="lowerLetter"/>', '<w:numFmt w:val="lowerLetter"/><w:lvlRestart w:val="0"/>')
        never_items = self.package(body, numbering=never)['numbering'][0]['items']
        self.assertEqual([5, 3, 6, 4], [item['counter'] for item in never_items])
        renamed_body = body.replace('w:val="17"', 'w:val="71"')
        renamed_num = numbering.replace('w:numId="17"', 'w:numId="71"').replace('w:numId="18"', 'w:numId="81"').replace('w:abstractNumId="10"', 'w:abstractNumId="40"').replace('w:val="10"', 'w:val="40"')
        self.assertEqual([], compare_semantics(original, self.package(renamed_body, numbering=renamed_num)))

    def test_numbering_inherited_from_style_is_resolved(self):
        _, numbering = self.numbering_fixture()
        styles = '<w:style w:type="paragraph" w:styleId="ListBase"><w:pPr><w:numPr><w:numId w:val="17"/></w:numPr></w:pPr></w:style><w:style w:type="paragraph" w:styleId="ListChild"><w:basedOn w:val="ListBase"/></w:style>'
        numbering = numbering.replace('<w:numFmt w:val="lowerLetter"/>', '<w:numFmt w:val="lowerLetter"/><w:pStyle w:val="ListChild"/>')
        result = self.package(self.paragraph('Styled item', '<w:pStyle w:val="ListChild"/>'), styles=styles, numbering=numbering)
        item = result['numbering'][0]['items'][0]
        self.assertEqual(1, item['level'])
        self.assertEqual(3, item['counter'])
        self.assertEqual('lowerLetter', item['resolvedLevel']['format'])

    def textbox_fixture(self):
        return ''.join('<w:p><w:r><w:pict><v:rect id="' + name + '" style="width:72pt;height:36pt;' + ('mso-next-textbox:#' + next_name + ';' if next_name else '') + '"><v:textbox inset="1pt,2pt,3pt,4pt" style="v-text-anchor:middle"><w:txbxContent>' + self.paragraph(text) + '</w:txbxContent></v:textbox></v:rect></w:pict></w:r></w:p>'
                       for name, next_name, text in [('boxA', 'boxB', 'First'), ('boxB', 'boxC', 'Second'), ('boxC', None, 'Third')])

    def test_vml_textbox_graph_and_layout_are_not_reduced_to_counts(self):
        body = self.textbox_fixture()
        original = self.package(body)
        items = original['textboxes'][0]['items']
        self.assertEqual([1, 2, None], [item['next'] for item in items])
        self.assertEqual(914400, items[0]['layout']['shapeStyle']['width'])
        for changed in [body.replace('width:72pt', 'width:73pt'),
                        body.replace('v-text-anchor:middle', 'v-text-anchor:top'),
                        body.replace('inset="1pt,2pt,3pt,4pt"', 'inset="0pt,2pt,3pt,4pt"')]:
            actual = self.package(changed)
            self.assertEqual(original['stories'], actual['stories'])
            self.assertEqual(original['counts'], actual['counts'])
            self.assertIn('textboxes', self.changes(original, actual))
        renamed = body.replace('boxA', 'frame92').replace('boxB', 'frame84').replace('boxC', 'frame76')
        self.assertEqual([], compare_semantics(original, self.package(renamed)))
        # The combined independent structure validator rejects malformed
        # graphs instead of allowing a measured result with an issue only.
        with self.assertRaisesRegex(ValueError, 'Multiple predecessors'):
            self.package(body.replace('mso-next-textbox:#boxB', 'mso-next-textbox:#boxC'))
        with self.assertRaisesRegex(ValueError, 'Cyclic textbox'):
            self.package(body.replace('mso-next-textbox:#boxC', 'mso-next-textbox:#boxA'))
        with self.assertRaisesRegex(ValueError, 'Unresolved linked textbox'):
            self.package(body.replace('mso-next-textbox:#boxB', 'mso-next-textbox:#missing'))

    def drawingml_textbox(self, identifier='77', sequence=None):
        box = '<wps:txbx id="' + identifier + '"><w:txbxContent>' + self.paragraph('Only once') + '</w:txbxContent></wps:txbx>' if sequence is None else '<wps:linkedTxbx id="' + identifier + '" seq="' + str(sequence) + '"/>'
        return '<w:r><w:drawing><wp:inline><wp:extent cx="914400" cy="457200"/><a:graphic><a:graphicData><wps:wsp><wps:spPr><a:xfrm><a:ext cx="914400" cy="457200"/></a:xfrm></wps:spPr>' + box + '<wps:bodyPr lIns="12700" anchor="ctr"/></wps:wsp></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>'

    def test_drawingml_chain_ids_are_canonical_but_sequence_loss_is_visible(self):
        body = '<w:p>' + self.drawingml_textbox() + '</w:p><w:p>' + self.drawingml_textbox(sequence=1) + '</w:p>'
        original = self.package(body)
        self.assertEqual([1, None], [item['next'] for item in original['textboxes'][0]['items']])
        self.assertEqual([], compare_semantics(original, self.package(body.replace('id="77"', 'id="999"'))))
        bad = self.package(body.replace('seq="1"', 'seq="2"'))
        self.assertIn('textboxes', self.changes(original, bad))
        self.assertIn('nonconsecutive-drawingml-chain', bad['textboxes'][0]['items'][0]['issues'])

    def test_alternate_content_selects_one_namespace_resolved_branch(self):
        fallback = '<w:r><w:pict><v:rect id="fallback"><v:textbox><w:txbxContent>' + self.paragraph('Only once') + '</w:txbxContent></v:textbox></v:rect></w:pict></w:r>'
        body = '<w:p><mc:AlternateContent><mc:Choice Requires="wps">' + self.drawingml_textbox() + '</mc:Choice><mc:Fallback>' + fallback + '</mc:Fallback></mc:AlternateContent></w:p>'
        original = self.package(body)
        self.assertEqual(1, original['stories'][0]['text'].count('Only once'))
        self.assertEqual(1, original['counts']['txbxContent'])
        self.assertEqual(1, original['counts']['drawing'])
        self.assertEqual(0, original['counts']['pict'])
        self.assertTrue(original['alternatives'][0]['availability'][0]['fallbackAvailable'])
        rebound = body.replace('<mc:Choice Requires="wps">', '<mc:Choice xmlns:wps="urn:unsupported-future" Requires="wps">')
        alternate = self.package(rebound)
        self.assertEqual(1, alternate['counts']['txbxContent'])
        self.assertEqual(0, alternate['counts']['drawing'])
        self.assertEqual('fallback', alternate['alternatives'][0]['availability'][0]['selected'])
        renamed = body.replace('<mc:Choice Requires="wps">', '<mc:Choice xmlns:alias="' + NS['wps'] + '" Requires="alias">')
        self.assertEqual([], compare_semantics(original, self.package(renamed)))

    def test_pinned_compatibility_fixture_does_not_show_unselected_content(self):
        result = snapshot(ROOT / 'test/fixtures/fidelity/word-compatibility.docx')
        self.assertTrue(result['alternatives'])
        self.assertFalse(any('UNSELECTED' in story['text'] for story in result['stories']))
        self.assertTrue(any('Selected supported body' in story['text'] for story in result['stories']))
        self.assertTrue(any(item['selected'] == 'none' for record in result['alternatives'] for item in record['availability']))

    def test_comment_authors_dates_and_parent_joins_are_canonicalized(self):
        comments = '<w:comments xmlns:w="' + W + '" xmlns:w14="' + NS['w14'] + '">' + ''.join(
            '<w:comment w:id="' + str(index + 10) + '" w:author="' + author + '" w:date="2026-11-12T09:00:00Z"><w:p w14:paraId="' + paragraph + '"><w:r><w:t>' + text + '</w:t></w:r></w:p></w:comment>'
            for index, (author, paragraph, text) in enumerate([
                ('Alice', '000000AA', 'Parent'), ('Bob', '000000BB', 'Reply'), ('Carol', '000000CC', 'Other root')])) + '</w:comments>'
        extension = '<w15:commentsEx xmlns:w15="' + NS['w15'] + '"><w15:commentEx w15:paraId="000000BB" w15:paraIdParent="000000AA" w15:done="0"/></w15:commentsEx>'
        rels = '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="comments1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/comments" Target="notes/comment-data.xml"/><Relationship Id="threads1" Type="http://schemas.microsoft.com/office/2011/relationships/commentsExtended" Target="notes/thread-data.xml"/></Relationships>'
        parts = {'word/notes/comment-data.xml': comments,
                 'word/notes/thread-data.xml': extension,
                 'word/_rels/document.xml.rels': rels}
        original = self.package(self.paragraph('Annotated'), extra=parts)
        self.assertEqual([None, 0, None], [item['parent'] for item in original['comments'][0]['items']])
        for name, before, after in [('word/notes/comment-data.xml', 'w:author="Bob"', 'w:author="Mallory"'),
                                    ('word/notes/comment-data.xml', 'T09:00:00Z', 'T09:01:00Z'),
                                    ('word/notes/thread-data.xml', 'paraIdParent="000000AA"', 'paraIdParent="000000CC"'),
                                    ('word/notes/thread-data.xml', 'done="0"', 'done="1"')]:
            changed = {**parts, name: parts[name].replace(before, after)}
            actual = self.package(self.paragraph('Annotated'), extra=changed)
            self.assertEqual(original['stories'], actual['stories'])
            self.assertEqual(original['counts'], actual['counts'])
            self.assertIn('comments', self.changes(original, actual))
        renamed = {name: value.replace('000000AA', '100000AA').replace('000000BB', '100000BB').replace('000000CC', '100000CC').replace('w:id="10"', 'w:id="90"').replace('w:id="11"', 'w:id="91"').replace('w:id="12"', 'w:id="92"')
                   for name, value in parts.items()}
        self.assertEqual([], compare_semantics(original, self.package(self.paragraph('Annotated'), extra=renamed)))

    def test_oracle_detects_structural_cycles_and_depth_limits(self):
        styles = '<w:style w:type="table" w:styleId="A"><w:basedOn w:val="B"/></w:style><w:style w:type="table" w:styleId="B"><w:basedOn w:val="A"/></w:style>'
        body = '<w:tbl><w:tblPr><w:tblStyle w:val="A"/></w:tblPr><w:tr><w:tc>' + self.paragraph('Cell') + '</w:tc></w:tr></w:tbl>'
        with self.assertRaisesRegex(ValueError, 'Cyclic'):
            self.package(body, styles=styles)
        with self.assertRaisesRegex(ValueError, 'structural limits'):
            self.package('<w:customXml>' * 130 + self.paragraph('Deep') + '</w:customXml>' * 130)

    def test_current_body_formatting_changes_survive_equal_text_and_counts(self):
        body = ('<w:p><w:pPr><w:jc w:val="right"/><w:spacing w:before="120"/></w:pPr>'
                '<w:r><w:rPr><w:b/><w:color w:val="AABBCC"/></w:rPr><w:t>Same word</w:t></w:r></w:p>')
        original = self.package(body)
        for changed in [body.replace('<w:b/>', '<w:i/>'),
                        body.replace('AABBCC', 'AABBCD'),
                        body.replace('w:before="120"', 'w:before="240"'),
                        body.replace('w:val="right"', 'w:val="left"')]:
            actual = self.package(changed)
            self.assertEqual(original['stories'], actual['stories'])
            self.assertEqual(original['counts'], actual['counts'])
            self.assertIn('paragraphs', self.changes(original, actual))
        # Splitting a run without changing its resolved stored properties is
        # not a formatting mutation. Coalescing also stays linear in run count.
        split = body.replace('<w:t>Same word</w:t>', '<w:t xml:space="preserve">Same </w:t></w:r>'
                             '<w:r><w:rPr><w:b/><w:color w:val="AABBCC"/></w:rPr><w:t>word</w:t>')
        self.assertEqual([], compare_semantics(original, self.package(split)))

    def test_document_and_implicit_style_defaults_are_measured(self):
        definitions = ('<w:docDefaults><w:rPrDefault><w:rPr><w:color w:val="112233"/>'
                       '</w:rPr></w:rPrDefault></w:docDefaults>'
                       '<w:style w:type="paragraph" w:default="1" w:styleId="Normal">'
                       '<w:pPr><w:spacing w:after="120"/></w:pPr><w:rPr><w:b/></w:rPr></w:style>')
        original = self.package(self.paragraph('Default formatting'), styles=definitions)
        for changed in [definitions.replace('112233', '112234'),
                        definitions.replace('<w:b/>', '<w:i/>'),
                        definitions.replace('w:after="120"', 'w:after="240"')]:
            self.assertIn('styleDefaults', self.changes(
                original, self.package(self.paragraph('Default formatting'), styles=changed)))
        self.assertEqual([], compare_semantics(original, self.package(
            self.paragraph('Default formatting'), styles=definitions.replace('styleId="Normal"', 'styleId="Renamed"'))))

    def comment_anchor_fixture(self):
        comments = '<w:comments xmlns:w="' + W + '">' + ''.join(
            '<w:comment w:id="' + str(index) + '" w:author="Alice"><w:p><w:r><w:t>' + text +
            '</w:t></w:r></w:p></w:comment>' for index, text in [(10, 'Review Alpha'), (20, 'Review Beta')]) + '</w:comments>'
        rels = '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="commentPart" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/comments" Target="notes/review.xml"/></Relationships>'
        return {'word/notes/review.xml': comments, 'word/_rels/document.xml.rels': rels}

    def test_comment_anchor_movement_and_content_joins_are_measured(self):
        a, b = '<w:r><w:t>Alpha</w:t></w:r>', '<w:r><w:t xml:space="preserve"> Beta</w:t></w:r>'
        start = '<w:commentRangeStart w:id="10"/>'
        end = '<w:commentRangeEnd w:id="10"/><w:r><w:commentReference w:id="10"/></w:r>'
        body = '<w:p>' + start + a + end + b + '</w:p>'
        parts = self.comment_anchor_fixture()
        original = self.package(body, extra=parts)
        self.assertEqual([0, 5, 5], [item['offsetInParagraph'] for item in original['commentAnchors'][0]['items']])
        moved = self.package('<w:p>' + a + start + b + end + '</w:p>', extra=parts)
        retargeted = self.package(body.replace('w:id="10"', 'w:id="20"'), extra=parts)
        for actual in (moved, retargeted):
            self.assertEqual(original['stories'], actual['stories'])
            self.assertEqual(original['counts'], actual['counts'])
            self.assertIn('commentAnchors', self.changes(original, actual))
        renamed = {name: value.replace('w:id="10"', 'w:id="90"').replace('w:id="20"', 'w:id="91"')
                   for name, value in parts.items()}
        self.assertEqual([], compare_semantics(original, self.package(body.replace('w:id="10"', 'w:id="90"'), extra=renamed)))

    def test_point_comments_and_incomplete_or_unknown_anchor_findings(self):
        body = '<w:p><w:r><w:t>Point</w:t><w:commentReference w:id="10"/></w:r></w:p>'
        parts = self.comment_anchor_fixture()
        point = self.package(body, extra=parts)['commentAnchors'][0]['items']
        self.assertEqual([], point[0]['issues'])
        self.assertEqual(5, point[0]['offsetInParagraph'])
        incomplete = body.replace('<w:r>', '<w:commentRangeStart w:id="10"/><w:r>', 1)
        measured = self.package(incomplete, extra=parts)['commentAnchors'][0]['items']
        self.assertTrue(all('incomplete-comment-range' in item['issues'] for item in measured))
        unknown = self.package(body.replace('w:id="10"', 'w:id="999"'), extra=parts)['commentAnchors'][0]['items']
        self.assertIn('unresolved-comment', unknown[0]['issues'])

    def section_story_fixture(self, *, same_text=False):
        parts, rels = {}, []
        for kind, root in [('header', 'hdr'), ('footer', 'ftr')]:
            for letter, mark in [('A', 'b'), ('B', 'i')]:
                text = kind if same_text else kind + letter
                parts['word/' + kind + letter + '.xml'] = (
                    '<w:' + root + ' xmlns:w="' + W + '"><w:p><w:r><w:rPr><w:' + mark +
                    '/></w:rPr><w:t>' + text + '</w:t></w:r></w:p></w:' + root + '>')
                rels.append('<Relationship Id="' + kind + letter + '" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/' + kind + '" Target="' + kind + letter + '.xml"/>')
        parts['word/_rels/document.xml.rels'] = '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' + ''.join(rels) + '</Relationships>'
        section = lambda letter: '<w:sectPr><w:headerReference w:type="default" r:id="header' + letter + '"/><w:footerReference w:type="default" r:id="footer' + letter + '"/></w:sectPr>'
        body = '<w:p><w:pPr>' + section('A') + '</w:pPr><w:r><w:t>First</w:t></w:r></w:p>' + self.paragraph('Second') + section('B')
        return body, parts

    def test_section_header_footer_bindings_are_not_a_sorted_story_bag(self):
        for same_text in (False, True):
            body, parts = self.section_story_fixture(same_text=same_text)
            original = self.package(body, extra=parts)
            for kind in ('header', 'footer'):
                changed = body.replace(kind + 'A', 'placeholder').replace(kind + 'B', kind + 'A').replace('placeholder', kind + 'B')
                actual = self.package(changed, extra=parts)
                self.assertEqual(original['stories'], actual['stories'])
                self.assertEqual(original['counts'], actual['counts'])
                self.assertIn('sectionStories', self.changes(original, actual))
        body, parts = self.section_story_fixture()
        with self.assertRaisesRegex(ValueError, 'section header/footer reference'):
            self.package(body.replace('r:id="headerA"', 'r:id="missing"'), extra=parts)

    def test_section_story_part_and_relationship_renames_are_canonical(self):
        body, parts = self.section_story_fixture()
        original = self.package(body, extra=parts)
        renamed, renamed_body = {}, body
        rels = parts['word/_rels/document.xml.rels']
        for index, (name, xml) in enumerate((item for item in parts.items() if not item[0].endswith('.rels'))):
            basename = name.removeprefix('word/').removesuffix('.xml')
            target = 'relocated/story' + str(index) + '.xml'
            renamed[target] = xml
            rels = rels.replace('Id="' + basename + '"', 'Id="rel' + str(index) + '"').replace('Target="' + basename + '.xml"', 'Target="/' + target + '"')
            renamed_body = renamed_body.replace('r:id="' + basename + '"', 'r:id="rel' + str(index) + '"')
        renamed['word/_rels/document.xml.rels'] = rels
        self.assertEqual([], compare_semantics(original, self.package(renamed_body, extra=renamed)))

    def test_auxiliary_comment_mc_is_projected_once_for_both_oracles(self):
        declarations = ' '.join('xmlns:' + prefix + '="' + uri + '"' for prefix, uri in NS.items())
        note = lambda text: '<w:comment w:id="10" w:author="Alice">' + self.paragraph(text) + '</w:comment>'
        parts = self.comment_anchor_fixture()
        parts['word/notes/review.xml'] = ('<w:comments ' + declarations + '><mc:AlternateContent>'
            '<mc:Choice Requires="wps">' + note('Selected comment') + '</mc:Choice><mc:Fallback>' +
            note('Unselected comment') + '</mc:Fallback></mc:AlternateContent></w:comments>')
        result = self.package('<w:p><w:r><w:t>Body</w:t><w:commentReference w:id="10"/></w:r></w:p>', extra=parts)
        self.assertEqual(1, result['counts']['comment'])
        self.assertEqual(1, len(result['structure']['comments']))
        self.assertEqual('Selected comment\n', result['structure']['comments'][0]['text'])
        self.assertFalse(any('Unselected' in story['text'] for story in result['stories']))


if __name__ == '__main__':
    unittest.main()
