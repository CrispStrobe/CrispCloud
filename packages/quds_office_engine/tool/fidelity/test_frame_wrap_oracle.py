"""Positive authored XML first; deliberate corruptions must then fail."""
from copy import deepcopy
import unittest
from xml.etree import ElementTree as ET

from frame_wrap_oracle import MC, MODES, NS, SOURCE, VML, W, W10, WP, inspect_document


def source(mode='square', phase='imported'):
    """Author both native branches without reading any engine output.

    The DrawingML input is the hand-written fixture. The compatibility form
    independently adds a VML rectangle with the same 100x72-point geometry,
    text, colors, and native default insets; the raw source has no such branch.
    """
    for prefix, namespace in NS.items():
        ET.register_namespace(prefix, namespace)
    root = ET.fromstring(SOURCE.read_bytes())
    wrap = root.find('.//wp:wrapSquare', NS)
    wrap.tag = f'{{{WP}}}{MODES[mode]}'
    if mode != 'square':
        wrap.attrib.clear()
    if phase == 'imported':
        host = root.find('w:body/w:p/w:r', NS)
        drawing = host.find('w:drawing', NS)
        native_text = drawing.find('.//wps:txbx/w:txbxContent', NS)
        host.remove(drawing)
        alternate = ET.SubElement(host, f'{{{MC}}}AlternateContent')
        choice = ET.SubElement(alternate, f'{{{MC}}}Choice', {'Requires': 'wps'})
        choice.append(drawing)
        fallback = ET.SubElement(alternate, f'{{{MC}}}Fallback')
        pict = ET.SubElement(fallback, f'{{{W}}}pict')
        rect = ET.SubElement(pict, f'{{{VML}}}rect', {
            'id': 'AuthoredFallback',
            'style': ('position:absolute;margin-left:0pt;margin-top:0pt;'
                      'width:100pt;height:72pt;mso-position-horizontal-relative:margin;'
                      'mso-position-vertical-relative:margin;mso-wrap-style:'
                      + ('square' if mode == 'square' else 'none')),
            'fillcolor': '#E8F0FB', 'strokecolor': '#355C7D',
        })
        textbox = ET.SubElement(rect, f'{{{VML}}}textbox', {
            'inset': '7.2pt,3.6pt,7.2pt,3.6pt',
        })
        textbox.append(deepcopy(native_text))
        if mode == 'topBottom':
            ET.SubElement(rect, f'{{{W10}}}wrap', {'type': 'topAndBottom'})
    inspect_document(ET.tostring(root), mode, phase)
    return root


class FrameWrapOracleTest(unittest.TestCase):
    def test_accepts_independently_authored_modes(self):
        for phase in ['source', 'imported']:
            for mode in MODES:
                with self.subTest(mode=mode, phase=phase):
                    source(mode, phase)

    def test_native_source_and_imported_compatibility_contracts_are_distinct(self):
        for mode in MODES:
            with self.subTest(mode=mode):
                raw = source(mode, 'source')
                self.assertIsNone(raw.find('.//mc:AlternateContent', NS))
                self.assertIsNone(raw.find('.//w:pict', NS))
                with self.assertRaisesRegex(AssertionError, 'fallback missing'):
                    inspect_document(ET.tostring(raw), mode, 'imported')
                imported = source(mode, 'imported')
                with self.assertRaisesRegex(AssertionError, 'invented compatibility branch'):
                    inspect_document(ET.tostring(imported), mode, 'source')

    def test_rejects_missing_or_duplicate_fallback(self):
        for mode in MODES:
            for mutation in ['missing', 'duplicate']:
                with self.subTest(mode=mode, mutation=mutation):
                    root = source(mode)
                    alternate = root.find('.//mc:AlternateContent', NS)
                    fallback = alternate.find('mc:Fallback', NS)
                    if mutation == 'missing':
                        alternate.remove(fallback)
                    else:
                        alternate.append(deepcopy(fallback))
                    with self.assertRaisesRegex(AssertionError, 'fallback missing or duplicated'):
                        inspect_document(ET.tostring(root), mode)

    def test_rejects_duplicate_native_anchor(self):
        root = source()
        drawing = root.find('.//mc:Choice/w:drawing', NS)
        drawing.append(deepcopy(drawing.find('wp:anchor', NS)))
        with self.assertRaisesRegex(AssertionError, 'anchor lost or duplicated'):
            inspect_document(ET.tostring(root), 'square')

    def test_rejects_wrong_compatibility_choice_owner_or_capability(self):
        for mutation in ['requires', 'owner']:
            with self.subTest(mutation=mutation):
                root = source()
                choice = root.find('.//mc:Choice', NS)
                if mutation == 'requires':
                    choice.set('Requires', 'pic')
                else:
                    drawing = choice.find('w:drawing', NS)
                    choice.remove(drawing)
                    root.find('w:body/w:p/w:r', NS).append(drawing)
                with self.assertRaisesRegex(AssertionError, 'compatibility choice owner'):
                    inspect_document(ET.tostring(root), 'square')

    def test_rejects_mode_conflation(self):
        root = source('topBottom')
        root.find('.//wp:wrapTopAndBottom', NS).tag = f'{{{WP}}}wrapSquare'
        with self.assertRaisesRegex(AssertionError, 'mode changed'):
            inspect_document(ET.tostring(root), 'topBottom')

    def test_rejects_wrong_geometry_and_ownership(self):
        for selector, attr, value in [
            ('.//wp:positionH', 'relativeFrom', 'page'),
            ('.//wp:extent', 'cx', '1270001'),
            ('.//wp:wrapSquare', 'wrapText', 'left'),
        ]:
            with self.subTest(selector=selector):
                root = source()
                root.find(selector, NS).set(attr, value)
                with self.assertRaises(AssertionError):
                    inspect_document(ET.tostring(root), 'square')

    def test_rejects_lost_body_or_frame_text(self):
        for selector in ['.//wps:txbx/w:txbxContent//w:t', 'w:body/w:p[2]/w:r/w:t']:
            with self.subTest(selector=selector):
                root = source()
                root.find(selector, NS).text = 'Lost text'
                with self.assertRaises(AssertionError):
                    inspect_document(ET.tostring(root), 'square')

    def test_rejects_wrong_top_bottom_fallback(self):
        root = source('topBottom')
        root.find('.//w10:wrap', NS).set('type', 'square')
        with self.assertRaisesRegex(AssertionError, 'fallback changed'):
            inspect_document(ET.tostring(root), 'topBottom')

    def test_rejects_fallback_text_insets_and_wrapping_metadata(self):
        for mutation in ['text', 'insets', 'wrap', 'unexpected-top-bottom']:
            with self.subTest(mutation=mutation):
                root = source()
                rect = root.find('.//mc:Fallback/w:pict/v:rect', NS)
                textbox = rect.find('v:textbox', NS)
                if mutation == 'text':
                    textbox.find('w:txbxContent//w:t', NS).text = 'Lost fallback text'
                elif mutation == 'insets':
                    textbox.set('inset', '0pt,0pt,0pt,0pt')
                elif mutation == 'wrap':
                    rect.set('style', 'mso-wrap-style:none')
                else:
                    ET.SubElement(rect, f'{{{W10}}}wrap', {'type': 'topAndBottom'})
                with self.assertRaisesRegex(AssertionError, 'fallback'):
                    inspect_document(ET.tostring(root), 'square')

    def test_rejects_invented_native_body_and_anchor_paragraph_properties(self):
        for mutation in ['body-insets', 'paragraph-properties']:
            with self.subTest(mutation=mutation):
                root = source()
                if mutation == 'body-insets':
                    root.find('.//wps:bodyPr', NS).set('lIns', '0')
                else:
                    host = root.find('w:body/w:p', NS)
                    host.insert(0, ET.Element(f'{{{W}}}pPr'))
                with self.assertRaisesRegex(AssertionError, 'native'):
                    inspect_document(ET.tostring(root), 'square')

    def test_rejects_changed_frame_fill_or_stroke(self):
        for selector in ['.//wps:spPr/a:solidFill/a:srgbClr',
                         './/wps:spPr/a:ln/a:solidFill/a:srgbClr']:
            with self.subTest(selector=selector):
                root = source()
                root.find(selector, NS).set('val', 'ABCDEF')
                with self.assertRaisesRegex(AssertionError, 'fill/stroke changed'):
                    inspect_document(ET.tostring(root), 'square')

    def test_rejects_invented_line_width_in_native_and_imported_modes(self):
        # The source deliberately omits a:ln/@w. Inventing 12700 (1pt)
        # changes its border pixels and top/bottom body positioning in LO.
        for phase in ['source', 'imported']:
            for mode in MODES:
                with self.subTest(mode=mode, phase=phase):
                    root = source(mode, phase)
                    root.find('.//wps:spPr/a:ln', NS).set('w', '12700')
                    with self.assertRaisesRegex(AssertionError, 'line-property omission'):
                        inspect_document(ET.tostring(root), mode, phase)

    def test_rejects_duplicate_native_line_properties(self):
        root = source()
        shape = root.find('.//wps:spPr', NS)
        shape.append(deepcopy(shape.find('a:ln', NS)))
        with self.assertRaisesRegex(AssertionError, 'line-property omission'):
            inspect_document(ET.tostring(root), 'square')


if __name__ == '__main__':
    unittest.main()
