"""Mutation controls for the independently verified public step-script outputs."""
import copy
from pathlib import Path
import tempfile
import unittest
from xml.etree import ElementTree as E
from corpus import read_zip
import scripted_oracle as oracle

class ScriptedOracleControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path('build/fidelity-scripted')
        cls.parts = {kind:read_zip(root/kind/f'edited.{extension}') for kind,extension in
                     [('word','docx'),('sheet','xlsx'),('slide','pptx')]}
        # Without a passing positive control, a mutation rejection proves nothing.
        for kind, parts in cls.parts.items(): oracle.VERIFY[kind](parts)

    def corrupt(self,kind,part,change):
        parts = copy.deepcopy(self.parts[kind])
        root = E.fromstring(parts[part]); change(root)
        parts[part] = E.tostring(root)
        with self.assertRaises((AssertionError,KeyError,AttributeError,StopIteration)):
            oracle.VERIFY[kind](parts)

    def test_wrong_note_body_is_rejected(self):
        self.corrupt('word','word/footnotes.xml',lambda r:r.find('.//'+oracle.W+'t').__setattr__('text','lost'))

    def test_note_hard_break_loss_is_rejected(self):
        def change(root):
            run = next(run for run in root.iter(oracle.W+'r')
                       if run.find(oracle.W+'br') is not None)
            run.remove(run.find(oracle.W+'br'))
        self.corrupt('word','word/footnotes.xml',change)

    def test_false_to_true_direct_format_is_rejected(self):
        def change(root):
            paragraph = root.find(oracle.W+'body/'+oracle.W+'p')
            content = next(run for run in paragraph.findall(oracle.W+'r')
                           if run.find(oracle.W+'t') is not None)
            content.find(oracle.W+'rPr/'+oracle.W+'b').set(oracle.W+'val','1')
        self.corrupt('word','word/document.xml',change)

    def heading_style(self, styles):
        title = E.fromstring(self.parts['word']['word/document.xml']).find(oracle.W+'body/'+oracle.W+'p')
        style_id = title.find(oracle.W+'pPr/'+oracle.W+'pStyle').get(oracle.W+'val')
        return next(style for style in styles if style.get(oracle.W+'styleId') == style_id)

    def test_heading_inherited_through_parent_style_is_accepted(self):
        parts = copy.deepcopy(self.parts['word'])
        styles = E.fromstring(parts['word/styles.xml'])
        style = self.heading_style(styles)
        ppr = style.find(oracle.W+'pPr')
        outline = ppr.find(oracle.W+'outlineLvl')
        ppr.remove(outline)
        style.insert(1, E.Element(oracle.W+'basedOn', {oracle.W+'val':'ScriptHeadingParent'}))
        parent = E.SubElement(styles, oracle.W+'style', {
            oracle.W+'type':'paragraph', oracle.W+'styleId':'ScriptHeadingParent'})
        E.SubElement(parent, oracle.W+'pPr').append(outline)
        parts['word/styles.xml'] = E.tostring(styles)
        oracle.verify_word(parts)

    def test_wrong_inherited_heading_level_is_rejected(self):
        def change(styles):
            self.heading_style(styles).find(oracle.W+'pPr/'+oracle.W+'outlineLvl').set(oracle.W+'val','8')
        self.corrupt('word','word/styles.xml',change)

    def test_direct_outline_overrides_inherited_heading_level(self):
        parts = copy.deepcopy(self.parts['word'])
        styles = E.fromstring(parts['word/styles.xml'])
        self.heading_style(styles).find(oracle.W+'pPr/'+oracle.W+'outlineLvl').set(oracle.W+'val','8')
        parts['word/styles.xml'] = E.tostring(styles)
        document = E.fromstring(parts['word/document.xml'])
        ppr = document.find(oracle.W+'body/'+oracle.W+'p/'+oracle.W+'pPr')
        E.SubElement(ppr, oracle.W+'outlineLvl', {oracle.W+'val':str(oracle.EXPECTED['word']['heading'])})
        parts['word/document.xml'] = E.tostring(document)
        oracle.verify_word(parts)

    def test_wrong_direct_outline_is_not_hidden_by_valid_style(self):
        def change(document):
            ppr = document.find(oracle.W+'body/'+oracle.W+'p/'+oracle.W+'pPr')
            E.SubElement(ppr, oracle.W+'outlineLvl', {oracle.W+'val':'8'})
        self.corrupt('word','word/document.xml',change)

    def test_missing_heading_style_reference_is_rejected(self):
        def change(document):
            document.find(oracle.W+'body/'+oracle.W+'p/'+oracle.W+'pPr/'+oracle.W+'pStyle').set(oracle.W+'val','Missing')
        self.corrupt('word','word/document.xml',change)

    def test_missing_or_cyclic_heading_parent_is_rejected(self):
        for parent_id in ['Missing', 'self']:
            with self.subTest(parent=parent_id):
                def change(styles):
                    style = self.heading_style(styles)
                    ppr = style.find(oracle.W+'pPr')
                    ppr.remove(ppr.find(oracle.W+'outlineLvl'))
                    target = style.get(oracle.W+'styleId') if parent_id == 'self' else parent_id
                    style.insert(1, E.Element(oracle.W+'basedOn', {oracle.W+'val':target}))
                self.corrupt('word','word/styles.xml',change)

    def test_wrong_restart_is_rejected(self):
        self.corrupt('word','word/numbering.xml',lambda r:r.find('.//'+oracle.W+'lvlOverride[@'+oracle.W+'ilvl="1"]/'+oracle.W+'startOverride').set(oracle.W+'val','1'))

    def test_wrong_picture_pixels_are_rejected(self):
        parts = copy.deepcopy(self.parts['word'])
        root = E.fromstring(parts['word/document.xml'])
        path = oracle.target(parts,'word/document.xml',rid=root.find('.//'+oracle.A+'blip').get(oracle.R+'embed'))
        parts[path] = read_zip(oracle.FIXTURES/'word.docx')['word/media/source.png']
        with self.assertRaises(AssertionError): oracle.verify_word(parts)

    def test_formula_cache_drift_is_rejected(self):
        self.corrupt('sheet','xl/worksheets/sheet1.xml',lambda r:r.find('.//'+oracle.X+'c[@r="C2"]/'+oracle.X+'v').__setattr__('text','29'))

    def test_wrong_merge_is_rejected(self):
        self.corrupt('sheet','xl/worksheets/sheet1.xml',lambda r:r.find('.//'+oracle.X+'mergeCell').set('ref','A5:B5'))

    def test_sheet_reorder_loss_is_rejected(self):
        self.corrupt('sheet','xl/workbook.xml',lambda r:r.find(oracle.X+'sheets').__setitem__(slice(None), list(reversed(r.find(oracle.X+'sheets')))))

    def test_slide_font_loss_is_rejected(self):
        self.corrupt('slide','ppt/slides/slide1.xml',lambda r:r.find('.//'+oracle.A+'rPr').set('sz','2900'))

    def test_slide_notes_loss_is_rejected(self):
        parts = copy.deepcopy(self.parts['slide'])
        path = oracle.target(parts,'ppt/slides/slide1.xml','notesSlide')
        root = E.fromstring(parts[path])
        for text in root.iter(oracle.A+'t'): text.text = 'LOST'
        parts[path] = E.tostring(root)
        with self.assertRaises(AssertionError): oracle.verify_slide(parts)

    def test_incomplete_corpus_never_passes(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(AssertionError,'inventory'):
                oracle.verify_directory(Path(directory))

if __name__ == '__main__': unittest.main()
