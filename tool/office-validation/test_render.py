"""Negative controls for independent rendering and save-cycle comparisons."""
from pathlib import Path
import copy
import hashlib
import json
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zlib
from zipfile import ZipFile

import render


def record(name, *, text='Known document text', pixels=None, pages=1):
    return {'file': name, 'pages': pages, 'text': text,
            'pixel_sha256': ['1' * 64] * pages if pixels is None else pixels}


class PixelEvidenceTests(unittest.TestCase):
    def test_binary_whitespace_and_hash_pixels_are_not_header_text(self):
        rgb = b'\n# '
        self.assertEqual(render.ppm_pixels(b'P6\n# page comment\n1 1\n255\n' + rgb),
                         (1, 1, rgb))
        self.assertEqual(render.ppm_pixels(b'P6\r\n1 1\r\n255\r\n' + rgb),
                         (1, 1, rgb))

    def test_invalid_ppm_cannot_become_a_golden(self):
        for data in (b'', b'P3\n1 1\n255\n123', b'P6\n0 1\n255\n',
                     b'P6\n1 1\n65535\n123', b'P6\n1 1\n255\n12',
                     b'P6\n1 1\n255\n1234', b'P6\n# unterminated'):
            with self.subTest(data=data), self.assertRaises(render.FidelityError):
                render.ppm_pixels(data)

    def test_png_contains_the_exact_authored_rgb_pixels(self):
        # Decode the output's PNG chunks independently, checking CRC and the
        # unfiltered scanlines rather than comparing an encoder to itself.
        rgb = bytes([255, 0, 0, 0, 255, 0, 0, 0, 255, 32, 10, 35])
        png = render.png_bytes(2, 2, rgb)
        self.assertEqual(png[:8], b'\x89PNG\r\n\x1a\n')
        offset, chunks = 8, {}
        while offset < len(png):
            length = struct.unpack('>I', png[offset:offset + 4])[0]
            kind = png[offset + 4:offset + 8]
            payload = png[offset + 8:offset + 8 + length]
            checksum = struct.unpack('>I', png[offset + 8 + length:offset + 12 + length])[0]
            self.assertEqual(checksum, zlib.crc32(kind + payload) & 0xffffffff)
            chunks[kind] = payload
            offset += 12 + length
        self.assertEqual(struct.unpack('>IIBBBBB', chunks[b'IHDR']), (2, 2, 8, 2, 0, 0, 0))
        self.assertEqual(zlib.decompress(chunks[b'IDAT']), b'\0' + rgb[:6] + b'\0' + rgb[6:])
        self.assertEqual(chunks[b'IEND'], b'')

    def test_page_order_is_numeric_and_includes_page_ten(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for number in [12, 2, 1, 10, 3, 11, 8, 7, 9, 6, 4, 5]:
                (root / f'page-{number}.ppm').touch()
            self.assertEqual([p.name for p in render.ordered_pages(root, 12)],
                             [f'page-{number}.ppm' for number in range(1, 13)])

    def test_missing_extra_and_duplicate_pages_fail(self):
        for names, expected in [(['page-1.ppm'], 2),
                                (['page-1.ppm', 'page-3.ppm'], 3),
                                (['page-1.ppm', 'page-2.ppm'], 1),
                                (['page-1.ppm', 'page-01.ppm'], 1),
                                ([], 0)]:
            with self.subTest(names=names), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                for name in names:
                    (root / name).touch()
                with self.assertRaises(render.FidelityError):
                    render.ordered_pages(root, expected)


class HostPicturePixelTests(unittest.TestCase):
    # Independently authored fixture values, not copied from the oracle at run
    # time. Rendered geometry must agree with these source test intentions.
    FIXTURES = {
        'landscape': (720, 405, 72, 40.5, 360, 180),
        'portrait': (720, 405, 72, 40.5, 120, 240),
        'square': (720, 405, 72, 40.5, 240, 240),
        'bounds': (100, 72, 10, 7.2, 90, 45),
    }

    def raster(self, case='bounds', *, rectangle=None, color=b'\0\0\0', background=b'\xff\xff\xff'):
        width, height, x, y, rect_width, rect_height = self.FIXTURES[case]
        if rectangle is not None:
            x, y, rect_width, rect_height = rectangle
        pixels = bytearray(background * (width * height))
        for row in range(max(0, int(y)), min(height, int(y + rect_height))):
            start, end = max(0, int(x)), min(width, int(x + rect_width))
            pixels[(row * width + start) * 3:(row * width + end) * 3] = color * (end - start)
        return width, height, bytes(pixels)

    def geometry(self, case='bounds'):
        values = self.FIXTURES[case]
        return {'page_emu': [round(value * 12700) for value in values[:2]],
                'rect_emu': [round(value * 12700) for value in values[2:]]}

    def package(self, path, *, geometry=None, missing=False, extra=False):
        geometry = geometry or self.geometry()
        width, height = geometry['page_emu']
        x, y, rect_width, rect_height = geometry['rect_emu']
        presentation_ns = 'http://schemas.openxmlformats.org/presentationml/2006/main'
        drawing_ns = 'http://schemas.openxmlformats.org/drawingml/2006/main'
        relationship_ns = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
        picture = '' if missing else (
            f'<p:pic><p:spPr><a:xfrm><a:off x="{x}" y="{y}"/>'
            f'<a:ext cx="{rect_width}" cy="{rect_height}"/></a:xfrm></p:spPr></p:pic>')
        with ZipFile(path, 'w') as package:
            package.writestr('ppt/presentation.xml',
                f'<p:presentation xmlns:p="{presentation_ns}" xmlns:r="{relationship_ns}">'
                '<p:sldIdLst><p:sldId id="256" r:id="slide"/></p:sldIdLst>'
                f'<p:sldSz cx="{width}" cy="{height}"/></p:presentation>')
            package.writestr('ppt/_rels/presentation.xml.rels',
                '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                f'<Relationship Id="slide" Type="{relationship_ns}/slide" '
                'Target="slides/slide1.xml"/></Relationships>')
            package.writestr('ppt/slides/slide1.xml',
                f'<p:sld xmlns:p="{presentation_ns}" xmlns:a="{drawing_ns}">'
                f'<p:cSld><p:spTree>{picture}{"<p:sp/>" if extra else ""}'
                '</p:spTree></p:cSld></p:sld>')

    def evidence(self, case='bounds'):
        return render.picture_pixel_evidence(case, *self.raster(case), self.geometry(case), self.FIXTURES[case][:2])

    def test_all_four_authored_rectangles_are_measured(self):
        for case, (width, height, x, y, rect_width, rect_height) in self.FIXTURES.items():
            with self.subTest(case=case):
                evidence = self.evidence(case)
                self.assertEqual(evidence['page_size'], [width, height])
                self.assertEqual(evidence['black_bbox'],
                                 [int(x), int(y), int(x + rect_width), int(y + rect_height)])
                self.assertEqual(evidence['black_pixels'], rect_width * rect_height)
                self.assertEqual(evidence['white_pixels'], width * height - rect_width * rect_height)
                self.assertEqual(evidence['outside_nonwhite_pixels'], 0)
                self.assertEqual(evidence['interior_nonblack_pixels'], 0)

    def test_blank_missing_wrong_aspect_shifted_clipped_colored_and_wrong_page_fail(self):
        cases = [self.raster(color=b'\xff\xff\xff'),
                 self.raster(rectangle=(10, 7.2, 0, 0)),
                 self.raster(rectangle=(10, 7.2, 45, 90)),
                 self.raster(rectangle=(4, 7.2, 90, 45)),
                 self.raster(rectangle=(25, 7.2, 90, 45)),
                 self.raster(color=b'\xff\0\0'),
                 self.raster(color=b'\x80\x80\x80'),
                 (101, 72, b'\xff' * (101 * 72 * 3))]
        for index, raster in enumerate(cases):
            with self.subTest(index=index), self.assertRaises(render.FidelityError):
                render.picture_pixel_evidence('bounds', *raster, self.geometry(), (100, 72))

    def test_one_pixel_edge_antialiasing_is_allowed_but_holes_and_extra_ink_fail(self):
        width, height, pixels = self.raster()
        gray_edge = bytearray(pixels)
        gray_edge[(7 * width + 10) * 3:(7 * width + 10) * 3 + 3] = b'\x80' * 3
        evidence = render.picture_pixel_evidence('bounds', width, height, bytes(gray_edge), self.geometry(), (100, 72))
        self.assertEqual(evidence['gray_pixels'], 1)
        for position, color in ((0, b'\0' * 3), (20 * width + 30, b'\xff' * 3),
                                (20 * width + 30, b'\x80' * 3)):
            altered = bytearray(pixels)
            altered[position * 3:position * 3 + 3] = color
            with self.subTest(position=position, color=color), self.assertRaises(render.FidelityError):
                render.picture_pixel_evidence('bounds', width, height, bytes(altered), self.geometry(), (100, 72))

    def test_only_subpixel_page_rounding_accepts_an_extra_raster_row_or_column(self):
        self.assertEqual(render.picture_raster_size('bounds', [100.006, 72]), [101, 72])
        self.assertEqual(render.picture_raster_size('landscape', [720, 405.014]), [720, 406])
        for size in ([100, 73], [100.1, 72], [99, 72], [100, float('nan')],
                     [100, float('inf')], [True, 72], [100], None):
            with self.subTest(size=size), self.assertRaises(render.FidelityError):
                render.picture_raster_size('bounds', size)
        # Supplying the correct point dimensions does not excuse a raster at
        # the wrong DPI or with different dimensions.
        with self.assertRaises(render.FidelityError):
            render.picture_pixel_evidence('bounds', *self.raster(), self.geometry(), (100.006, 72))

    def test_package_geometry_rejects_hidden_overflow_even_when_visible_pixels_match(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'picture.pptx'
            self.package(path)
            self.assertEqual(render.picture_package_geometry(path, 'bounds'), self.geometry())
            # 110 points at x=10 clips to exactly the same visible 90-point
            # rectangle as the correct extent. Pixel equality cannot detect it.
            self.assertEqual(self.raster(rectangle=(10, 7.2, 110, 45)), self.raster())
            for changed in ('overflow', 'canvas', 'missing', 'extra'):
                geometry = self.geometry()
                if changed == 'overflow':
                    geometry['rect_emu'][2] = 110 * 12700
                elif changed == 'canvas':
                    geometry['page_emu'][0] += 12700
                self.package(path, geometry=geometry, missing=changed == 'missing', extra=changed == 'extra')
                with self.subTest(changed=changed), self.assertRaises(render.FidelityError):
                    render.picture_package_geometry(path, 'bounds')

    def test_picture_names_elsewhere_and_other_cycles_formats_are_not_exempted(self):
        for name in ('slide-picture-bounds-1.pptx', 'other/slide-picture-bounds-1.pptx',
                     'fidelity-host/slide-picture-bounds-1.docx',
                     'fidelity-host/slide-picture-bounds-0.pptx',
                     'fidelity-host/slide-picture-bounds-4.pptx',
                     'fidelity-host/slide-picture-unknown-1.pptx'):
            with self.subTest(name=name):
                self.assertIsNone(render.host_picture_case(name))
                candidate = record(name, text='')
                candidate['picture_pixel_evidence'] = self.evidence()
                with self.assertRaises(render.FidelityError):
                    render.validate_record(candidate)

    def test_empty_text_cycles_require_measured_evidence_for_every_save_and_root_scope(self):
        for directory, root in (('fidelity-host/', None), ('', Path('/corpus/fidelity-host'))):
            files = [f'{directory}slide-picture-bounds-{cycle}.pptx' for cycle in range(1, 4)]
            measured = self.evidence()
            records = {name: dict(record(name, text='\f', pixels=[measured['pixel_sha256']]),
                                  picture_pixel_evidence=copy.deepcopy(measured)) for name in files}
            passing = render.cycle_coverage(files, records, root=root)
            self.assertEqual(passing['failures'], [])
            self.assertTrue(passing['cycle_comparisons'][0]['passed'])
            for key, value in (('oracle', 'claimed-pass'), ('black_pixels', 0),
                               ('black_bbox', [0, 0, 90, 45]), ('colored_pixels', 1),
                               ('pixel_sha256', '2' * 64), ('source_geometry', {})):
                changed = copy.deepcopy(records)
                changed[files[1]]['picture_pixel_evidence'][key] = value
                with self.subTest(key=key, root=root):
                    self.assertTrue(render.cycle_coverage(files, changed, root=root)['failures'])
            for text in ('', 'Unexpected text does not replace pixel evidence'):
                changed = copy.deepcopy(records)
                changed[files[1]]['text'] = text
                del changed[files[1]]['picture_pixel_evidence']
                self.assertTrue(render.cycle_coverage(files, changed, root=root)['failures'])

    def test_native_pipeline_requires_pixels_and_retains_measured_evidence(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder) / 'fidelity-host'
            root.mkdir()
            source = root / 'slide-picture-bounds-1.pptx'
            self.package(source)
            output = Path(folder) / 'output'
            output.mkdir()
            raster, page_count = self.raster(), 1

            def command(args, **kwargs):
                if Path(args[0]).name in ('libreoffice', 'soffice'):
                    dest = Path(args[args.index('--outdir') + 1])
                    (dest / (source.stem + '.pdf')).write_bytes(b'%PDF fixture')
                elif args[0] == 'pdftoppm':
                    self.assertEqual(args[1:3], ['-r', '72'])
                    prefix = Path(args[-1])
                    width, height, pixels = raster
                    prefix.with_name('page-1.ppm').write_bytes(
                        f'P6\n{width} {height}\n255\n'.encode() + pixels)
                return subprocess.CompletedProcess(args, 0, stdout=b'', stderr=b'')

            def output_text(args, **kwargs):
                return f'Pages: {page_count}\nPage size: 100 x 72 pts\n' if args[0] == 'pdfinfo' else '\f'

            with patch.object(render.subprocess, 'run', side_effect=command), \
                    patch.object(render.subprocess, 'check_output', side_effect=output_text):
                result = render.render_document(source, root, output, 0)
                measured = result['picture_pixel_evidence']
                self.assertEqual(measured['black_pixels'], 4050)
                self.assertEqual(measured['black_bbox'], [10, 7, 100, 52])
                self.assertEqual(result['pixel_sha256'], [measured['pixel_sha256']])
                self.assertEqual(json.loads(json.dumps(result)), result)
                for raster, page_count in ((self.raster(color=b'\xff' * 3), 1), (self.raster(), 2)):
                    with self.subTest(pages=page_count), self.assertRaises(render.FidelityError):
                        render.render_document(source, root, output, 1)


class HostWordPicturePixelTests(unittest.TestCase):
    # A4 in twentieth-points, one authored 12-point empty line, then a 60x30
    # point inline picture at the one-inch left/top margins. These values do
    # not come from the renderer's expected geometry or a generated document.
    def geometry(self, kind='jpeg'):
        return {'page_twips': [11906, 16838],
                'margins_twips': [1440, 1440, 1440, 1440, 720, 720],
                'leading_spacing_twips': [0, 0, 240], 'leading_line_rule': 'exact',
                'inline_extent_emu': [762000, 381000],
                'inline_distances_emu': [0, 0, 114300, 114300],
                'picture_offset_emu': [0, 0], 'picture_extent_emu': [762000, 381000],
                'media_dimensions_pixels': [80, 40], 'media_mime': 'image/' + kind}

    def raster(self, *, rectangle=(72, 84, 60, 30), color=b'\0' * 3):
        width, height = 596, 842
        x, y, rect_width, rect_height = rectangle
        pixels = bytearray(b'\xff' * (width * height * 3))
        for row in range(y, min(height, y + rect_height)):
            start, end = max(0, x), min(width, x + rect_width)
            pixels[(row * width + start) * 3:(row * width + end) * 3] = color * (end - start)
        return width, height, bytes(pixels)

    def parts(self, kind='jpeg'):
        # The unit packages exercise raw OOXML/header parsing only. Native
        # decoding is independently required by render_document's pixel check
        # and by the real six-file acceptance; these tiny header fixtures are
        # deliberately not claimed as complete decodable Office documents.
        w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
        a = 'http://schemas.openxmlformats.org/drawingml/2006/main'
        r = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
        pic = 'http://schemas.openxmlformats.org/drawingml/2006/picture'
        wp = 'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing'
        document = (
            f'<w:document xmlns:w="{w}" xmlns:a="{a}" xmlns:r="{r}" xmlns:pic="{pic}" xmlns:wp="{wp}">'
            '<w:body><w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="exact"/>'
            '<w:ind w:left="0" w:right="0"/><w:jc w:val="left"/></w:pPr><w:r><w:t/></w:r></w:p>'
            '<w:p><w:r><w:drawing><wp:inline distT="0" distB="0" distL="114300" distR="114300">'
            '<wp:extent cx="762000" cy="381000"/><wp:effectExtent l="0" t="0" r="0" b="0"/>'
            f'<a:graphic><a:graphicData uri="{pic}"><pic:pic><pic:blipFill><a:blip r:embed="image"/>'
            '<a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/>'
            '<a:ext cx="762000" cy="381000"/></a:xfrm></pic:spPr></pic:pic></a:graphicData></a:graphic>'
            '</wp:inline></w:drawing></w:r></w:p><w:sectPr><w:type w:val="nextPage"/>'
            '<w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:bottom="1440" '
            'w:left="1440" w:right="1440" w:header="720" w:footer="720"/>'
            '<w:cols w:num="1" w:space="720"/></w:sectPr></w:body></w:document>')
        jpeg = b'\xff\xd8\xff\xc0\x00\x08\x08\x00\x28\x00\x50\x03\xff\xd9'
        gif = (b'GIF89a' + struct.pack('<HHBBB', 80, 40, 0, 0, 0)
               + b'\x2c' + struct.pack('<HHHHB', 0, 0, 80, 40, 0) + b'\x02\x01\x00\x00\x3b')
        return {'word/document.xml': document.encode(),
                'word/_rels/document.xml.rels': (
                    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                    f'<Relationship Id="image" Type="{r}/image" Target="media/image1.{kind}"/>'
                    '</Relationships>').encode(),
                '[Content_Types].xml': (
                    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
                    f'<Default Extension="{kind}" ContentType="image/{kind}"/>'
                    f'<Override PartName="/word/media/image1.{kind}" ContentType="image/{kind}"/>'
                    '</Types>').encode(),
                f'word/media/image1.{kind}': jpeg if kind == 'jpeg' else gif}

    def package(self, path, parts):
        with ZipFile(path, 'w') as package:
            for name, payload in parts.items():
                package.writestr(name, payload)

    def evidence(self, kind='jpeg'):
        return render.picture_pixel_evidence('word-' + kind, *self.raster(),
                                             self.geometry(kind), (595.3, 841.9))

    def test_both_codecs_require_raw_authored_geometry_and_measured_pixels(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'image.docx'
            for kind in ('jpeg', 'gif'):
                with self.subTest(kind=kind):
                    self.package(path, self.parts(kind))
                    self.assertEqual(render.picture_package_geometry(path, 'word-' + kind), self.geometry(kind))
                    reopened = self.parts(kind)
                    reopened['word/document.xml'] = reopened['word/document.xml'].replace(b'<w:r><w:t/></w:r>', b'')
                    self.package(path, reopened)
                    self.assertEqual(render.picture_package_geometry(path, 'word-' + kind), self.geometry(kind))
                    measured = self.evidence(kind)
                    self.assertEqual(measured['oracle'], 'host-word-black-picture-v1')
                    self.assertEqual(measured['page_size'], [596, 842])
                    self.assertEqual(measured['expected_page_size'], [595.3, 841.9])
                    self.assertEqual(measured['black_bbox'], [72, 84, 132, 114])
                    self.assertEqual(measured['black_pixels'], 1800)
                    self.assertEqual(measured['white_pixels'], 596 * 842 - 1800)
                    self.assertEqual(measured['colored_pixels'], 0)
                    self.assertEqual(measured['outside_nonwhite_pixels'], 0)
                    self.assertEqual(measured['interior_nonblack_pixels'], 0)

    def test_changed_page_margins_line_spacing_or_paragraph_structure_fail(self):
        replacements = [
            (b'w:w="11906"', b'w:w="12240"'), (b'w:h="16838"', b'w:h="15840"'),
            (b'w:top="1440"', b'w:top="1200"'), (b'w:left="1440"', b'w:left="1200"'),
            (b'w:after="0"', b'w:after="240"'), (b'w:line="240"', b'w:line="280"'),
            (b'w:lineRule="exact"', b'w:lineRule="auto"'),
            (b'<w:t/>', b'<w:t>sentinel</w:t>'), (b'<w:t/>', b'<w:br/><w:t/>'),
            (b'<w:r><w:t/></w:r>', b'<w:r><w:t/></w:r><w:r><w:t/></w:r>'),
            (b'<w:sectPr>', b'<w:p/><w:sectPr>'), (b'w:num="1"', b'w:num="2"'),
            (b'<w:sectPr>', b'<w:sectPr><w:headerReference r:id="header"/>')]
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'bad.docx'
            for before, after in replacements:
                parts = self.parts()
                self.assertIn(before, parts['word/document.xml'])
                parts['word/document.xml'] = parts['word/document.xml'].replace(before, after)
                self.package(path, parts)
                with self.subTest(after=after), self.assertRaises(render.FidelityError):
                    render.picture_package_geometry(path, 'word-jpeg')

    def test_changed_inline_geometry_crop_rotation_effect_or_extra_image_fail(self):
        replacements = [
            (b'<wp:inline', b'<wp:anchor'), (b'cx="762000"', b'cx="1524000"'),
            (b'cy="381000"', b'cy="762000"'), (b'<a:off x="0"', b'<a:off x="12700"'),
            (b'distL="114300"', b'distL="0"'), (b'<a:xfrm>', b'<a:xfrm rot="60000">'),
            (b'<a:stretch>', b'<a:srcRect l="1000"/><a:stretch>'),
            (b'<a:blip r:embed="image"/>', b'<a:blip r:embed="image"><a:alphaModFix amt="0"/></a:blip>'),
            (b'<wp:effectExtent l="0"', b'<wp:effectExtent l="12700"'),
            (b'</a:graphicData>', b'<pic:pic/></a:graphicData>')]
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'bad.docx'
            for before, after in replacements:
                parts = self.parts()
                parts['word/document.xml'] = parts['word/document.xml'].replace(before, after)
                if before == b'<wp:inline':
                    parts['word/document.xml'] = parts['word/document.xml'].replace(b'</wp:inline>', b'</wp:anchor>')
                self.package(path, parts)
                with self.subTest(after=after), self.assertRaises(render.FidelityError):
                    render.picture_package_geometry(path, 'word-jpeg')

    def test_wrong_external_ambiguous_relationship_mime_or_extra_media_fail(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'bad.docx'
            for mutation in ('target', 'external', 'type', 'duplicate', 'default', 'override', 'extra', 'missing'):
                parts = self.parts()
                relationships = 'word/_rels/document.xml.rels'
                types = '[Content_Types].xml'
                if mutation == 'target':
                    parts[relationships] = parts[relationships].replace(b'media/image1.jpeg', b'media/image2.jpeg')
                elif mutation == 'external':
                    parts[relationships] = parts[relationships].replace(b'Id="image"', b'Id="image" TargetMode="External"')
                elif mutation == 'type':
                    parts[relationships] = parts[relationships].replace(b'/image"', b'/hyperlink"')
                elif mutation == 'duplicate':
                    parts[relationships] = parts[relationships].replace(b'</Relationships>', b'<Relationship Id="image"/></Relationships>')
                elif mutation == 'default':
                    parts[types] = parts[types].replace(b'ContentType="image/jpeg"', b'ContentType="image/png"', 1)
                elif mutation == 'override':
                    parts[types] = parts[types].replace(b'PartName="/word/media/image1.jpeg" ContentType="image/jpeg"',
                                                      b'PartName="/word/media/image1.jpeg" ContentType="image/png"')
                elif mutation == 'extra':
                    parts['word/media/image2.jpeg'] = parts['word/media/image1.jpeg']
                else:
                    del parts['word/media/image1.jpeg']
                self.package(path, parts)
                with self.subTest(mutation=mutation), self.assertRaises(render.FidelityError):
                    render.picture_package_geometry(path, 'word-jpeg')

    def test_wrong_media_dimensions_signatures_and_gif_frame_count_fail(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'bad.docx'
            for kind in ('jpeg', 'gif'):
                original = self.parts(kind)[f'word/media/image1.{kind}']
                changed_dimensions = bytearray(original)
                changed_dimensions[9 if kind == 'jpeg' else 6] = 1
                variants = [b'', b'not an image', original[:-1], bytes(changed_dimensions)]
                if kind == 'gif':
                    variants.extend([original[:-1] + original[13:],
                                     original[:14] + b'\x01' + original[15:]])
                for payload in variants:
                    parts = self.parts(kind)
                    parts[f'word/media/image1.{kind}'] = payload
                    self.package(path, parts)
                    with self.subTest(kind=kind, payload=payload), self.assertRaises(render.FidelityError):
                        render.picture_package_geometry(path, 'word-' + kind)

    def test_blank_aspect_position_color_extra_ink_and_interior_hole_fail(self):
        rasters = [self.raster(color=b'\xff' * 3), self.raster(rectangle=(72, 84, 30, 60)),
                   self.raster(rectangle=(72, 72, 60, 30)), self.raster(rectangle=(80, 84, 60, 30)),
                   self.raster(color=b'\xff\0\0')]
        width, height, pixels = self.raster()
        for position, color in ((0, b'\0' * 3), (100 * width + 90, b'\xff' * 3)):
            altered = bytearray(pixels)
            altered[position * 3:position * 3 + 3] = color
            rasters.append((width, height, bytes(altered)))
        for index, raster in enumerate(rasters):
            with self.subTest(index=index), self.assertRaises(render.FidelityError):
                render.picture_pixel_evidence('word-jpeg', *raster, self.geometry(), (595.3, 841.9))
        for page in ((612, 792), (595.3, 842), (595.4, 841.9)):
            with self.subTest(page=page), self.assertRaises(render.FidelityError):
                render.picture_raster_size('word-jpeg', page)
        self.assertEqual(render.picture_raster_size('word-jpeg', (595.304, 841.89)), [596, 842])

    def test_only_exact_six_word_paths_can_use_measured_empty_text_evidence(self):
        measured = self.evidence()
        for name in ('word-picture-jpeg-1.docx', 'other/word-picture-jpeg-1.docx',
                     'fidelity-host/word-picture-jpeg-0.docx', 'fidelity-host/word-picture-jpeg-4.docx',
                     'fidelity-host/word-picture-jpeg-1.pptx', 'fidelity-host/word-picture-png-1.docx'):
            with self.subTest(name=name):
                self.assertIsNone(render.host_picture_case(name))
                candidate = dict(record(name, text='', pixels=[measured['pixel_sha256']]),
                                 picture_pixel_evidence=measured)
                with self.assertRaises(render.FidelityError):
                    render.validate_record(candidate)
        # A JPEG measurement cannot satisfy the separately scoped GIF case.
        candidate = dict(record('fidelity-host/word-picture-gif-1.docx', text='',
                                pixels=[measured['pixel_sha256']]), picture_pixel_evidence=measured)
        with self.assertRaises(render.FidelityError):
            render.validate_record(candidate)

    def test_both_three_save_groups_require_every_measured_page_and_exact_cycles(self):
        for directory, root in (('fidelity-host/', None), ('', Path('/corpus/fidelity-host'))):
            records = {}
            for kind in ('jpeg', 'gif'):
                measured = self.evidence(kind)
                for cycle in range(1, 4):
                    name = f'{directory}word-picture-{kind}-{cycle}.docx'
                    records[name] = dict(record(name, text='\f', pixels=[measured['pixel_sha256']]),
                                         picture_pixel_evidence=copy.deepcopy(measured))
            files = list(records)
            passing = render.cycle_coverage(files, records, root=root)
            self.assertEqual(passing['failures'], [])
            self.assertEqual(passing['cycle_groups'], 2)
            self.assertTrue(all(group['passed'] for group in passing['cycle_comparisons']))
            for mutation in ('missing', 'unmeasured', 'geometry', 'pixels', 'text', 'pages'):
                changed = copy.deepcopy(records)
                if mutation == 'missing':
                    del changed[files[1]]
                elif mutation == 'unmeasured':
                    del changed[files[1]]['picture_pixel_evidence']
                elif mutation == 'geometry':
                    changed[files[1]]['picture_pixel_evidence']['source_geometry']['leading_spacing_twips'][2] = 280
                elif mutation == 'pixels':
                    changed[files[1]]['pixel_sha256'] = ['2' * 64]
                elif mutation == 'text':
                    changed[files[1]]['text'] = 'Unexpected text\f'
                else:
                    changed[files[1]]['pages'] = 2
                    changed[files[1]]['pixel_sha256'] *= 2
                with self.subTest(mutation=mutation, root=root):
                    self.assertTrue(render.cycle_coverage(files, changed, root=root)['failures'])
            self.assertTrue(render.cycle_coverage(files[:-1], records, root=root)['failures'])

    def test_native_pipeline_measures_word_pixels_and_rejects_blank_or_extra_pages(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder) / 'fidelity-host'
            root.mkdir()
            source = root / 'word-picture-jpeg-1.docx'
            self.package(source, self.parts())
            output = Path(folder) / 'output'
            output.mkdir()
            raster, pages = self.raster(), 1

            def command(args, **kwargs):
                if Path(args[0]).name in ('libreoffice', 'soffice'):
                    dest = Path(args[args.index('--outdir') + 1])
                    (dest / (source.stem + '.pdf')).write_bytes(b'%PDF fixture')
                elif args[0] == 'pdftoppm':
                    self.assertEqual(args[1:3], ['-r', '72'])
                    width, height, pixels = raster
                    Path(args[-1]).with_name('page-1.ppm').write_bytes(
                        f'P6\n{width} {height}\n255\n'.encode() + pixels)
                return subprocess.CompletedProcess(args, 0, stdout=b'', stderr=b'')

            def output_text(args, **kwargs):
                return f'Pages: {pages}\nPage size: 595.304 x 841.89 pts\n' if args[0] == 'pdfinfo' else '\f'

            with patch.object(render.subprocess, 'run', side_effect=command), \
                    patch.object(render.subprocess, 'check_output', side_effect=output_text):
                result = render.render_document(source, root, output, 0)
                measured = result['picture_pixel_evidence']
                self.assertEqual(measured['black_bbox'], [72, 84, 132, 114])
                self.assertEqual(measured['black_pixels'], 1800)
                self.assertEqual(measured['source_geometry'], self.geometry())
                self.assertEqual(result['pixel_sha256'], [measured['pixel_sha256']])
                self.assertEqual(json.loads(json.dumps(result)), result)
                for raster, pages in ((self.raster(color=b'\xff' * 3), 1), (self.raster(), 2)):
                    with self.subTest(pages=pages), self.assertRaises(render.FidelityError):
                        render.render_document(source, root, output, 1)


class CycleComparisonTests(unittest.TestCase):
    def test_complete_zero_and_one_based_series_pass(self):
        for cycles in ([0, 1, 2], [1, 2, 3]):
            files = [f'case-{n}.docx' for n in cycles]
            result = render.cycle_coverage(files, {name: record(name) for name in files})
            self.assertEqual(result['failures'], [])
            self.assertEqual(result['cycle_groups'], 1)
            self.assertTrue(result['cycle_comparisons'][0]['passed'])

    def test_missing_duplicate_or_extra_cycle_fails(self):
        for suffixes in (['1'], ['1', '3'], ['2', '3'], ['0', '1'],
                         ['1', '2', '3', '4'], ['1', '01', '2', '3']):
            with self.subTest(suffixes=suffixes):
                files = [f'case-{suffix}.docx' for suffix in suffixes]
                result = render.cycle_coverage(files, {name: record(name) for name in files})
                self.assertEqual(len(result['failures']), 1)
                self.assertFalse(result['cycle_comparisons'][0]['passed'])

    def test_failed_cycle_cannot_disappear_from_comparison(self):
        files = ['case-1.docx', 'case-2.docx', 'case-3.docx']
        records = {name: record(name) for name in files if name != 'case-2.docx'}
        result = render.cycle_coverage(files, records)
        self.assertIn('Missing successful render', result['failures'][0]['error'])

    def test_text_pixel_and_page_changes_each_fail(self):
        files = ['case-1.docx', 'case-2.docx', 'case-3.docx']
        for change in ({'text': 'Lost the footnote'}, {'pixels': ['2' * 64]},
                       {'pages': 2}):
            with self.subTest(change=change):
                records = {name: record(name) for name in files}
                records[files[1]] = record(files[1], **change)
                result = render.cycle_coverage(files, records)
                self.assertEqual(len(result['failures']), 1)
                self.assertIn('Render changed', result['failures'][0]['error'])

    def test_identically_empty_or_malformed_render_evidence_does_not_pass(self):
        files = ['case-1.docx', 'case-2.docx', 'case-3.docx']
        for change in ({'text': ''}, {'pages': 0}, {'pixels': []}, {'pixels': ['']}):
            with self.subTest(change=change):
                records = {name: record(name, **change) for name in files}
                result = render.cycle_coverage(files, records)
                self.assertEqual(len(result['failures']), 1)
                self.assertIn('Invalid or empty render evidence', result['failures'][0]['error'])

    def test_cases_are_scoped_by_directory_and_format(self):
        records = {}
        for folder, suffix in [('host', '.docx'), ('engine', '.docx'), ('engine', '.xlsx')]:
            for cycle in range(1, 4):
                name = f'{folder}/case-{cycle}{suffix}'
                records[name] = record(name, text=folder + suffix)
        result = render.cycle_coverage(list(records), records)
        self.assertEqual(result['cycle_groups'], 3)
        self.assertEqual(result['failures'], [])

    def test_unnumbered_files_are_reported_without_claiming_cycle_coverage(self):
        files = ['host-save.docx', 'created.xlsx']
        result = render.cycle_coverage(files, {name: record(name) for name in files})
        self.assertEqual(result['cycle_groups'], 0)
        self.assertEqual(result['failures'], [])
        self.assertEqual(result['render_only_files'], sorted(files))

    def test_first_roundtrip_must_match_supplied_edited_or_import_baseline(self):
        for prefix, baseline in [('roundtrip', 'edited'), ('unchanged', 'input'),
                                 ('unchanged', 'source'), ('story-imported', 'story-input'),
                                 ('story-imported', 'story-source')]:
            with self.subTest(prefix=prefix):
                files = [f'{prefix}-{cycle}.docx' for cycle in range(1, 4)]
                files.append(f'{baseline}.docx')
                records = {name: record(name) for name in files}
                passing = render.cycle_coverage(files, records)
                self.assertEqual(passing['failures'], [])
                self.assertEqual(passing['baseline_comparisons'], 1)
                self.assertEqual(passing['render_only_files'], [])
                records[files[-1]] = record(files[-1], text='Original source contains more text')
                failing = render.cycle_coverage(files, records)
                self.assertEqual(len(failing['failures']), 1)

    def test_bookmark_clone_series_requires_its_explicit_native_baseline(self):
        for folder in ('fidelity-bookmarks', 'engine/fidelity-bookmarks'):
            with self.subTest(folder=folder):
                cycles = [f'{folder}/cloned-{cycle}.docx' for cycle in range(1, 4)]
                source = f'{folder}/source.docx'
                files = cycles + [source]
                records = {name: record(name) for name in files}
                result = render.cycle_coverage(files, records)
                self.assertEqual(result['failures'], [])
                self.assertEqual(result['baseline_comparisons'], 1)
                self.assertEqual(result['cycle_comparisons'][0]['baseline'], source)
                self.assertEqual(result['render_only_files'], [])

                missing = render.cycle_coverage(cycles, records)
                self.assertIn('Missing required native baseline',
                              missing['failures'][0]['error'])
                del records[source]
                failed = render.cycle_coverage(files, records)
                self.assertIn('Missing successful baseline render',
                              failed['failures'][0]['error'])

    def test_bookmark_clone_first_save_text_pixels_and_page_count_must_match_source(self):
        files = [f'fidelity-bookmarks/cloned-{cycle}.docx' for cycle in range(1, 4)]
        source = 'fidelity-bookmarks/source.docx'
        files.append(source)
        for change in ({'text': 'Native source has additional visible text'},
                       {'pixels': ['2' * 64]}, {'pages': 2}):
            with self.subTest(change=change):
                records = {name: record(name) for name in files}
                records[source] = record(source, **change)
                result = render.cycle_coverage(files, records)
                self.assertEqual(len(result['failures']), 1)
                self.assertIn('Render changed', result['failures'][0]['error'])
                self.assertFalse(result['cycle_comparisons'][0]['passed'])

    def test_explicit_clone_mapping_does_not_guess_other_scenario_baselines(self):
        for folder, case, suffix in (
                ('other-corpus', 'cloned', '.docx'),
                ('fidelity-bookmarks', 'cloned', '.xlsx'),
                ('fidelity-bookmarks', 'edited', '.docx'),
                ('fidelity-bookmarks', 'frame', '.docx')):
            with self.subTest(folder=folder, case=case, suffix=suffix):
                files = [f'{folder}/{case}-{cycle}{suffix}' for cycle in range(1, 4)]
                source = f'{folder}/source{suffix}'
                files.append(source)
                records = {name: record(name) for name in files}
                records[source] = record(source, text='Intentionally different source')
                result = render.cycle_coverage(files, records)
                self.assertEqual(result['failures'], [])
                self.assertEqual(result['baseline_comparisons'], 0)
                self.assertEqual(result['render_only_files'], [source])

    def test_declared_frame_wrap_modes_require_their_exact_native_source(self):
        for mode in ('none', 'square', 'topBottom'):
            with self.subTest(mode=mode):
                cycles = [f'engine/fidelity-frame-wrap/{mode}-{cycle}.docx'
                          for cycle in range(1, 4)]
                source = f'engine/fidelity-frame-wrap/{mode}-source.docx'
                files = cycles + [source]
                records = {name: record(name) for name in files}
                passed = render.cycle_coverage(files, records)
                self.assertEqual(passed['failures'], [])
                self.assertEqual(passed['baseline_comparisons'], 1)
                missing = render.cycle_coverage(cycles, records)
                self.assertIn('Missing required native baseline', missing['failures'][0]['error'])
                records[source] = record(source, pixels=['2' * 64])
                changed = render.cycle_coverage(files, records)
                self.assertIn('Render changed (pixel_sha256)', changed['failures'][0]['error'])


class TableGridBaselineTests(unittest.TestCase):
    def test_each_phase_and_route_requires_authored_native_baseline(self):
        for prefix in ('fidelity-table-grid', 'engine/fidelity-table-grid'):
            for route in ('direct', 'isolate'):
                for phase in ('unchanged', 'format', 'replace', 'unmerge'):
                    with self.subTest(prefix=prefix, route=route, phase=phase):
                        cycles = [f'{prefix}/{route}/{phase}-{n}.docx' for n in (1, 2, 3)]
                        source = f'{prefix}/' + ('source.docx' if phase == 'unchanged' else f'expected-{phase}.docx')
                        files = cycles + [source]
                        records = {name: record(name) for name in files}
                        passed = render.cycle_coverage(files, records)
                        self.assertEqual(passed['failures'], [])
                        self.assertEqual(passed['baseline_comparisons'], 1)
                        self.assertEqual(passed['cycle_comparisons'][0]['baseline'], source)
                        missing = render.cycle_coverage(cycles, records)
                        self.assertIn('Missing required native baseline', missing['failures'][0]['error'])
                        records[source] = record(source, pixels=['2' * 64])
                        changed = render.cycle_coverage(files, records)
                        self.assertIn('Render changed (pixel_sha256)', changed['failures'][0]['error'])

    def test_corpus_root_preserves_mapping_and_other_names_are_not_guessed(self):
        self.assertEqual(render.table_grid_baseline(Path('direct/format.docx'), '/tmp/fidelity-table-grid'),
                         'expected-format.docx')
        for case in ('fidelity-table-grid/preview/format.docx', 'other/direct/format.docx',
                     'fidelity-table-grid/direct/format.xlsx', 'fidelity-table-grid/direct/other.docx'):
            self.assertIsNone(render.table_grid_baseline(Path(case)))


class SectionPageOrderTests(unittest.TestCase):
    # Authored expectations, not values imported from the renderer's mapping.
    cases = [('unchanged', 'ABCDEF', [1, 2, 3, 4, 5, 6]),
             ('within', 'BACDEF', [2, 1, 3, 4, 5, 6]),
             ('forward', 'BCDAEF', [2, 3, 4, 1, 5, 6]),
             ('backward', 'AFBCDE', [1, 6, 2, 3, 4, 5]),
             ('emptied', 'CABDEF', [3, 1, 2, 4, 5, 6])]

    @staticmethod
    def deck(name, order):
        return record(name, pages=len(order),
                      text=''.join(f'  Native slide {label}\n\f' for label in order),
                      pixels=[f'{ord(label):064x}' for label in order])

    def corpus(self, case='forward', order='BCDAEF', folder='fidelity-slide-sections/direct',
               suffix='.pptx'):
        source = f'{folder}/source{suffix}'
        cycles = [f'{folder}/{case}-{cycle}{suffix}' for cycle in range(1, 4)]
        records = {name: self.deck(name, order) for name in cycles}
        records[source] = self.deck(source, 'ABCDEF')
        return cycles, source, records

    def test_all_declared_orders_require_exact_source_pages_in_both_modes(self):
        for mode in ('direct', 'isolate'):
            for case, order, pages in self.cases:
                with self.subTest(mode=mode, case=case):
                    cycles, source, records = self.corpus(
                        case, order, f'engine/build/fidelity-slide-sections/{mode}')
                    result = render.cycle_coverage(cycles + [source], records)
                    self.assertEqual(result['failures'], [])
                    self.assertEqual(result['baseline_comparisons'], 1)
                    self.assertEqual(result['page_order_comparisons'], 1)
                    self.assertEqual(result['render_only_files'], [])
                    self.assertEqual(result['cycle_comparisons'][0]['baseline'], source)
                    self.assertEqual(result['cycle_comparisons'][0]['baseline_page_order'], pages)

    def test_missing_source_file_is_not_optional_even_for_unchanged(self):
        for case, order, _ in self.cases:
            with self.subTest(case=case):
                cycles, _, records = self.corpus(case, order)
                result = render.cycle_coverage(cycles, records)
                self.assertIn('Missing required native baseline', result['failures'][0]['error'])
                self.assertEqual(result['page_order_comparisons'], 0)

    def test_failed_native_source_cannot_be_hidden_by_stable_cycles(self):
        cycles, source, records = self.corpus()
        del records[source]
        result = render.cycle_coverage(cycles + [source], records)
        self.assertIn('Missing successful baseline render', result['failures'][0]['error'])

    def test_stable_but_wrong_first_export_order_fails_every_changed_case(self):
        for case, _, _ in self.cases[1:]:
            with self.subTest(case=case):
                cycles, source, records = self.corpus(case, 'ABCDEF')
                result = render.cycle_coverage(cycles + [source], records)
                self.assertIn('Render changed', result['failures'][0]['error'])
                self.assertFalse(result['cycle_comparisons'][0]['passed'])

    def test_first_export_page_text_pixels_and_page_count_are_independent_checks(self):
        for change in ('text', 'pixel', 'count'):
            with self.subTest(change=change):
                cycles, source, records = self.corpus()
                for name in cycles:
                    if change == 'text':
                        records[name]['text'] = records[name]['text'].replace('Native slide A', 'Lost A')
                    elif change == 'pixel':
                        records[name]['pixel_sha256'][3] = 'f' * 64
                    else:
                        records[name] = self.deck(name, 'BCDAE')
                result = render.cycle_coverage(cycles + [source], records)
                self.assertEqual(len(result['failures']), 1)
                expected = {'text': 'text', 'pixel': 'pixel_sha256', 'count': 'pages'}[change]
                self.assertIn(f'Render changed ({expected})', result['failures'][0]['error'])

    def test_source_must_have_all_six_pages(self):
        for order in ('ABCDE', 'ABCDEFG'):
            with self.subTest(order=order):
                cycles, source, records = self.corpus()
                records[source] = self.deck(source, order)
                result = render.cycle_coverage(cycles + [source], records)
                self.assertIn('Native page count/permutation mismatch', result['failures'][0]['error'])

    def test_missing_separators_trailing_page_or_blank_page_text_fails(self):
        source_text = self.deck('source', 'ABCDEF')['text']
        for text in (source_text.replace('\f', ''), source_text[:-1],
                     source_text + '\f', source_text.replace('  Native slide C\n', ' \n')):
            with self.subTest(text=text):
                cycles, source, records = self.corpus()
                records[source]['text'] = text
                result = render.cycle_coverage(cycles + [source], records)
                self.assertIn('Incomplete native page text', result['failures'][0]['error'])

    def test_invalid_permutation_cannot_drop_or_repeat_native_pages(self):
        source = self.deck('source', 'ABCDEF')
        for order in ([], [1, 2, 3, 4, 5], [1, 2, 3, 4, 5, 5],
                      [0, 1, 2, 3, 4, 5], [True, 2, 3, 4, 5, 6]):
            with self.subTest(order=order), self.assertRaises(render.FidelityError):
                render.compare_page_order(source, source, order)

    def test_mapping_does_not_guess_other_corpora_modes_formats_or_cases(self):
        for folder, case, suffix in (
                ('other-corpus/direct', 'forward', '.pptx'),
                ('fidelity-slide-sections/preview', 'forward', '.pptx'),
                ('fidelity-slide-sections/direct', 'forward', '.docx'),
                ('fidelity-slide-sections/direct', 'edited', '.pptx')):
            with self.subTest(folder=folder, case=case, suffix=suffix):
                cycles, source, records = self.corpus(case, 'BCDAEF', folder, suffix)
                result = render.cycle_coverage(cycles + [source], records)
                self.assertEqual(result['failures'], [])
                self.assertEqual(result['baseline_comparisons'], 0)
                self.assertEqual(result['page_order_comparisons'], 0)
                self.assertEqual(result['render_only_files'], [source])

    def test_cli_keeps_exact_contract_when_corpus_is_input_root(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder) / 'fidelity-slide-sections'
            (root / 'direct').mkdir(parents=True)
            cycles, source, records = self.corpus(folder='direct')
            for name in cycles + [source]:
                (root / name).write_bytes(b'Office input')
            output = Path(folder) / 'output'

            def converted(path, input_root, destination, index):
                return records[path.relative_to(input_root).as_posix()]

            with patch.object(render, 'render_document', side_effect=converted), \
                    patch.object(render.subprocess, 'check_output', return_value='LibreOffice test'):
                self.assertEqual(render.main([str(root), str(output)]), 0)
            result = json.loads((output / 'render-report.json').read_text())
            self.assertEqual(result['page_order_comparisons'], 1)
            self.assertEqual(result['cycle_comparisons'][0]['baseline_page_order'], [2, 3, 4, 1, 5, 6])


class RenderExecutionTests(unittest.TestCase):
    def test_empty_and_missing_inputs_fail_with_a_report(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            empty = root / 'empty'
            empty.mkdir()
            for source in (empty, root / 'missing'):
                output = root / ('out-' + source.name)
                with patch.object(render.subprocess, 'check_output') as command:
                    self.assertEqual(render.main([str(source), str(output)]), 1)
                    command.assert_not_called()
                result = json.loads((output / 'render-report.json').read_text())
                self.assertEqual(result['files'], 0)
                self.assertTrue(result['failures'])

    def test_stale_pdf_cannot_satisfy_a_failed_conversion(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = root / 'source.docx'
            source.write_bytes(b'Office input')
            output = root / 'out'
            old = output / '000'
            old.mkdir(parents=True)
            (old / 'source.pdf').write_bytes(b'%PDF stale')
            (old / 'document.pdf').write_bytes(b'%PDF stale')
            with patch.object(render.subprocess, 'run', return_value=subprocess.CompletedProcess(
                    ['soffice'], 0, stdout=b'', stderr=b'')):
                with self.assertRaisesRegex(render.FidelityError, 'did not produce'):
                    render.render_document(source, root, output, 0)

    def test_missing_pdf_retains_both_streams_and_exit_status(self):
        for empty_pdf in (False, True):
            with self.subTest(empty_pdf=empty_pdf), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                source = root / 'source.docx'
                source.write_bytes(b'Office input')
                output = root / 'out'
                output.mkdir()

                def conversion(args, **kwargs):
                    if empty_pdf:
                        (Path(args[args.index('--outdir') + 1]) / 'source.pdf').touch()
                    return subprocess.CompletedProcess(
                        args, 0, stdout=b'Converter stdout\n', stderr=b'Converter stderr\n')

                with patch.object(render.subprocess, 'run', side_effect=conversion), \
                        self.assertRaises(render.MissingPdfError) as caught:
                    render.render_document(source, root, output, 0)
                self.assertEqual(render.conversion_diagnostics(caught.exception), {
                    'returncode': 0, 'stdout': 'Converter stdout\n', 'stderr': 'Converter stderr\n'})
                self.assertFalse(render.known_native_import_rejection(caught.exception))

    def test_ordinary_missing_pdf_failure_report_keeps_conversion_diagnostics(self):
        for diagnostic in (b'Permission denied\n', b'Error: source file could not be loaded\n'):
            with self.subTest(diagnostic=diagnostic), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                source = root / 'input'
                source.mkdir()
                (source / 'ordinary.docx').write_bytes(b'Office input')
                output = root / 'out'
                conversion = subprocess.CompletedProcess(
                    ['soffice'], 0, stdout=b'Converter stdout\n', stderr=diagnostic)
                with patch.object(render.subprocess, 'run', return_value=conversion), \
                        patch.object(render.subprocess, 'check_output', return_value='LibreOffice test'):
                    self.assertEqual(render.main([str(source), str(output)]), 1)
                report = json.loads((output / 'render-report.json').read_text())
                self.assertEqual(report['native_schema_only_files'], 0)
                self.assertEqual(report['rendered_files'], 0)
                attempts = report['failures'][0].pop('conversion_attempts')
                self.assertEqual(len(attempts), 1)
                self.assertEqual(attempts[0]['returncode'], 0)
                self.assertTrue(attempts[0]['input_unchanged'])
                self.assertEqual(report['failures'], [{
                    'file': 'ordinary.docx', 'error': 'LibreOffice did not produce a nonempty PDF',
                    'returncode': 0, 'stdout': 'Converter stdout\n', 'stderr': diagnostic.decode()}])

    def test_png_pdf_and_text_artifacts_are_retained(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = root / 'source.docx'
            source.write_bytes(b'Office input')
            output = root / 'out'
            output.mkdir()

            def command(args, **kwargs):
                if Path(args[0]).name in ('libreoffice', 'soffice'):
                    dest = Path(args[args.index('--outdir') + 1])
                    (dest / 'source.pdf').write_bytes(b'%PDF fixture')
                elif args[0] == 'pdftoppm':
                    prefix = Path(args[-1])
                    prefix.with_name('page-1.ppm').write_bytes(b'P6\n1 1\n255\n\xff\0\0')
                return subprocess.CompletedProcess(args, 0, stdout=b'', stderr=b'')

            def output_text(args, **kwargs):
                return 'Pages: 1\n' if args[0] == 'pdfinfo' else 'Known document text\n'

            with patch.object(render.subprocess, 'run', side_effect=command), \
                    patch.object(render.subprocess, 'check_output', side_effect=output_text):
                result = render.render_document(source, root, output, 0)
            self.assertEqual(result['pages'], 1)
            self.assertEqual((output / result['pdf']).read_bytes(), b'%PDF fixture')
            png = output / result['page_artifacts'][0]['png']
            self.assertTrue(png.read_bytes().startswith(b'\x89PNG\r\n\x1a\n'))
            self.assertEqual((output / '000' / 'text.txt').read_text(), 'Known document text\n')
            self.assertEqual(list(output.glob('render-*')), [])
            self.assertEqual(list(output.rglob('*.ppm')), [])


class KilledConversionRetryTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.folder = Path(temporary.name)
        self.root = self.folder / 'input'
        self.root.mkdir()
        self.source = self.root / 'source.docx'
        self.source.write_bytes(b'Office input')
        self.output = self.folder / 'output'
        self.output.mkdir()
        self.calls = []
        self.workspaces = []
        self.codes = []
        self.errors = []
        self.converter_error = None
        self.raster_error = None
        self.mutate = False
        self.text = 'Known document text\n'

    def command(self, argv, **kwargs):
        if Path(argv[0]).name in ('libreoffice', 'soffice'):
            self.calls.append(argv)
            work = Path(argv[argv.index('--outdir') + 1])
            self.assertFalse((work / 'source.pdf').exists())
            self.assertFalse((work / 'profile').exists())
            if self.workspaces:
                self.assertFalse(self.workspaces[-1].exists())
            self.workspaces.append(work)
            (work / 'profile').mkdir()
            # Even a killed attempt may leave a PDF. A later attempt must not
            # consume it, or reuse the failed converter's profile.
            (work / 'source.pdf').write_bytes(b'%PDF partial')
            if self.mutate:
                self.source.write_bytes(b'Office other')  # Same length.
            if self.converter_error is not None:
                raise self.converter_error
            number = len(self.calls) - 1
            if number < len(self.codes) and self.codes[number] is not None:
                error = subprocess.CalledProcessError(
                    self.codes[number], argv, output=b'Converter output\n',
                    stderr=b'Error: source file could not be loaded\n')
                self.errors.append(error)
                raise error
            (work / 'source.pdf').write_bytes(b'%PDF complete')
        elif argv[0] == 'pdftoppm':
            if self.raster_error is not None:
                raise self.raster_error
            Path(argv[-1]).with_name('page-1.ppm').write_bytes(b'P6\n1 1\n255\n\xff\0\0')
        return subprocess.CompletedProcess(argv, 0, stdout=b'Converted\n', stderr=b'')

    def output_text(self, argv, **kwargs):
        if '--version' in argv:
            return 'LibreOffice test'
        return 'Pages: 1\n' if argv[0] == 'pdfinfo' else self.text

    def execute(self):
        with patch.object(render.subprocess, 'run', side_effect=self.command), \
                patch.object(render.subprocess, 'check_output', side_effect=self.output_text):
            return render.render_document(self.source, self.root, self.output, 0)

    def test_killed_then_success_uses_fresh_profile_and_retains_both_attempts(self):
        self.codes = [-9]
        result = self.execute()
        attempts = result['conversion_attempts']
        digest = hashlib.sha256(b'Office input').hexdigest()
        self.assertEqual([item['returncode'] for item in attempts], [-9, 0])
        self.assertEqual([item['status'] for item in attempts], ['failed', 'converted'])
        self.assertEqual(attempts[0]['stdout'], 'Converter output\n')
        self.assertEqual(attempts[0]['stderr'], 'Error: source file could not be loaded\n')
        self.assertEqual(result['input_sha256'], digest)
        self.assertTrue(all(item['input_sha256_before'] == item['input_sha256_after'] == digest
                            and item['input_unchanged'] for item in attempts))
        self.assertEqual(len(set(self.workspaces)), 2)
        self.assertTrue(all(not work.exists() for work in self.workspaces))
        self.assertEqual((self.output / result['pdf']).read_bytes(), b'%PDF complete')

    def test_exhausted_kills_are_finite_and_every_attempt_remains_in_failed_report(self):
        self.codes = [-9] * 10
        with patch.object(render.subprocess, 'run', side_effect=self.command), \
                patch.object(render.subprocess, 'check_output', side_effect=self.output_text):
            self.assertEqual(render.main([str(self.root), str(self.output)]), 1)
        report = json.loads((self.output / 'render-report.json').read_text())
        self.assertEqual(len(self.calls), 3)
        self.assertEqual(report['reports'], [])
        self.assertEqual(report['native_schema_only'], [])
        self.assertEqual(report['failures'][0]['returncode'], -9)
        attempts = report['failures'][0]['conversion_attempts']
        self.assertEqual([item['returncode'] for item in attempts], [-9, -9, -9])
        self.assertTrue(all(item['input_unchanged'] for item in attempts))
        self.assertEqual(len(set(self.workspaces)), 3)

    def test_ordinary_exits_timeouts_and_os_errors_keep_original_exception_without_retry(self):
        errors = [subprocess.CalledProcessError(code, ['soffice'], stderr='diagnostic')
                  for code in (1, 2, 9, 137, -11)]
        errors += [subprocess.TimeoutExpired(['soffice'], 60), FileNotFoundError('converter absent')]
        for error in errors:
            self.calls.clear()
            self.converter_error = error
            with self.subTest(error=error), self.assertRaises(type(error)) as caught:
                self.execute()
            self.assertIs(caught.exception, error)
            self.assertEqual(len(self.calls), 1)
            self.assertEqual(len(error.conversion_attempts), 1)

    def test_platform_without_sigkill_has_no_retry_code(self):
        self.codes = [-9]
        with patch.object(render, 'SOFFICE_SIGKILL_RETURN_CODE', None), \
                self.assertRaises(subprocess.CalledProcessError):
            self.execute()
        self.assertEqual(len(self.calls), 1)

    def test_poppler_sigkill_is_not_a_soffice_retry(self):
        error = subprocess.CalledProcessError(-9, ['pdftoppm'], stderr='raster killed')
        self.raster_error = error
        with self.assertRaises(subprocess.CalledProcessError) as caught:
            self.execute()
        self.assertIs(caught.exception, error)
        self.assertEqual(len(self.calls), 1)
        self.assertEqual(error.conversion_attempts[0]['returncode'], 0)

    def test_semantic_failure_after_recovery_does_not_retry_again(self):
        self.codes = [-9]
        self.text = ''
        with self.assertRaisesRegex(render.FidelityError, 'no extractable text') as caught:
            self.execute()
        self.assertEqual(len(self.calls), 2)
        self.assertEqual([item['returncode'] for item in caught.exception.conversion_attempts], [-9, 0])

    def test_input_mutation_after_kill_aborts_without_discarding_kill_diagnostics(self):
        self.codes = [-9]
        self.mutate = True
        with self.assertRaisesRegex(render.FidelityError, 'input changed') as caught:
            self.execute()
        self.assertEqual(len(self.calls), 1)
        attempt = render.failure_details(caught.exception)['conversion_attempts'][0]
        self.assertEqual(attempt['returncode'], -9)
        self.assertIn('source file could not be loaded', attempt['stderr'])
        self.assertNotEqual(attempt['input_sha256_before'], attempt['input_sha256_after'])
        self.assertFalse(attempt['input_unchanged'])
        self.assertFalse(render.known_native_import_rejection(caught.exception))

    def test_input_mutation_after_success_cannot_return_a_verified_render(self):
        self.mutate = True
        with self.assertRaisesRegex(render.FidelityError, 'input changed') as caught:
            self.execute()
        self.assertEqual(len(self.calls), 1)
        self.assertFalse(caught.exception.conversion_attempts[0]['input_unchanged'])

    def test_normal_import_refusal_after_kill_preserves_the_qualifier_and_history(self):
        self.codes = [-9, 1]
        with self.assertRaises(subprocess.CalledProcessError) as caught:
            self.execute()
        self.assertIs(caught.exception, self.errors[-1])
        self.assertEqual(caught.exception.returncode, 1)
        self.assertTrue(render.known_native_import_rejection(caught.exception))
        self.assertEqual([item['returncode'] for item in
                          render.failure_details(caught.exception)['conversion_attempts']], [-9, 1])

    def test_qualified_schema_only_report_keeps_killed_and_refused_attempts(self):
        self.source.unlink()
        corpus = self.root / 'fidelity-aux-controls'
        corpus.mkdir()
        for name in render.NATIVE_AUX_FILES:
            (corpus / name).write_bytes(b'Office input')
        self.source = corpus / 'source.docx'
        receipt = self.folder / 'schema.json'
        receipt.write_text(json.dumps({'Reports': [
            {'File': str(corpus / name), 'Sha256': hashlib.sha256(b'Office input').hexdigest(), 'Errors': []}
            for name in sorted(render.NATIVE_AUX_FILES)]}))
        self.codes = [-9, 1]
        # The existing native-limitation controls separately exercise malformed
        # XML and all receipt failures. Here the real conversion retry must
        # retain its history through the qualified-report routing.
        with patch.object(render, 'validate_native_aux_corpus'), \
                patch.object(render.subprocess, 'run', side_effect=self.command), \
                patch.object(render.subprocess, 'check_output', side_effect=self.output_text):
            self.assertEqual(render.main([str(self.root), str(self.output), '--schema-report', str(receipt)]), 0)
        report = json.loads((self.output / 'render-report.json').read_text())
        self.assertEqual(report['failures'], [])
        self.assertEqual(report['rendered_files'], 0)
        self.assertEqual(report['native_schema_only_files'], 7)
        self.assertEqual(len(self.calls), 2)
        for item in report['native_schema_only']:
            self.assertEqual(item['source_conversion']['returncode'], 1)
            self.assertEqual([attempt['returncode'] for attempt in item['source_conversion_attempts']], [-9, 1])

    def test_retry_success_still_requires_strict_text_and_pixel_comparison(self):
        self.codes = [-9]
        actual = self.execute()
        for key, value in (('text', 'Different native text'), ('pixel_sha256', ['2' * 64])):
            expected = dict(actual, file='baseline.docx')
            expected[key] = value
            with self.subTest(key=key), self.assertRaisesRegex(render.FidelityError, f'Render changed \\({key}\\)'):
                render.compare_records(expected, actual)


if __name__ == '__main__':
    unittest.main()
