"""Positive authored XML first; deliberate corruptions must then fail."""
import unittest
from xml.etree import ElementTree as ET

from frame_wrap_oracle import MODES, NS, SOURCE, W, W10, WP, inspect_document


def source(mode='square'):
    root = ET.fromstring(SOURCE.read_bytes())
    wrap = root.find('.//wp:wrapSquare', NS)
    wrap.tag = f'{{{WP}}}{MODES[mode]}'
    if mode != 'square':
        wrap.attrib.clear()
    if mode == 'topBottom':
        host = root.find('w:body/w:p/w:r', NS)
        pict = ET.SubElement(host, f'{{{W}}}pict')
        rect = ET.SubElement(pict, '{urn:schemas-microsoft-com:vml}rect')
        ET.SubElement(rect, f'{{{W10}}}wrap', {'type': 'topAndBottom'})
    inspect_document(ET.tostring(root), mode)
    return root


class FrameWrapOracleTest(unittest.TestCase):
    def test_accepts_independently_authored_modes(self):
        for mode in MODES:
            source(mode)

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


if __name__ == '__main__':
    unittest.main()
