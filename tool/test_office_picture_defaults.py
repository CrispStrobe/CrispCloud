"""Host-only controls; preserve the managed upstream render fixture bytes."""
import importlib
import sys
from pathlib import Path
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent / 'office-validation'))

import render

_oracles = importlib.import_module('test_render')


class HostPictureDefaultControls(unittest.TestCase):
    parts = _oracles.HostWordPictureTests.parts
    package = _oracles.HostWordPictureTests.package
    geometry = _oracles.HostWordPictureTests.geometry
    DOCUMENT = _oracles.HostWordPictureTests.DOCUMENT
    STYLES = _oracles.HostWordPictureTests.STYLES
    MEDIA_HEX = _oracles.HostWordPictureTests.MEDIA_HEX

    def test_explicit_disabled_small_caps_retains_exact_picture_geometry(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'source.docx'
            for fmt in ('gif', 'jpeg'):
                parts = self.parts(fmt)
                parts['word/document.xml'] = parts['word/document.xml'].replace(
                    b'<w:i w:val="0"/>',
                    b'<w:i w:val="0"/><w:smallCaps w:val="0"/>', 1)
                self.package(path, parts)
                with self.subTest(fmt=fmt):
                    self.assertEqual(render.picture_package_geometry(path, 'word-' + fmt),
                                     self.geometry(fmt))

    def test_small_caps_cannot_admit_enabled_implicit_or_unreviewed_content(self):
        faults = [b'<w:smallCaps w:val="1"/>', b'<w:smallCaps/>',
                  b'<w:smallCaps w:val="true"/>',
                  b'<w:smallCaps w:val="0" w:extra="0"/>',
                  b'<w:smallCaps w:val="0"><w:b/></w:smallCaps>',
                  b'<w:smallCaps w:val="0"/><w:smallCaps w:val="0"/>']
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'source.docx'
            for fault in faults:
                parts = self.parts()
                parts['word/document.xml'] = parts['word/document.xml'].replace(
                    b'<w:i w:val="0"/>', b'<w:i w:val="0"/>' + fault, 1)
                self.package(path, parts)
                with self.subTest(fault=fault), self.assertRaises(render.FidelityError):
                    render.picture_package_geometry(path, 'word-gif')
