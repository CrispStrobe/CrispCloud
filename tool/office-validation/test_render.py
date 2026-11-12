"""Negative controls for independent rendering and save-cycle comparisons."""
from pathlib import Path
import copy
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


class OfficePackageDiscoveryTests(unittest.TestCase):
    def test_word_templates_and_macro_packages_are_required_native_inputs(self):
        # These are host save formats in the authored inventory. A successful
        # native run must not silently leave them out of its input set.
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            expected = ['word.docx', 'macro.docm', 'template.dotx',
                        'macro-template.dotm', 'UPPER.DOTM',
                        'nested/sheet.xlsx', 'nested/slides.pptx']
            for name in expected + ['legacy.doc', 'legacy.xls', 'notes.txt']:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b'input-discovery-control')
            (root / 'directory.docm').mkdir()
            self.assertEqual(
                [path.relative_to(root).as_posix()
                 for path in render.discover_inputs(root)], sorted(expected))

    def test_template_only_capture_is_not_an_empty_corpus(self):
        for extension in ('.docm', '.dotx', '.dotm'):
            with self.subTest(extension=extension), tempfile.TemporaryDirectory() as folder:
                source = Path(folder) / ('host-save' + extension)
                source.write_bytes(b'input-discovery-control')
                self.assertEqual(render.discover_inputs(folder), [source])


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
        'bounds': (100, 60, 10, 6, 90, 45),
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
                 self.raster(rectangle=(10, 6, 0, 0)),
                 self.raster(rectangle=(10, 6, 45, 90)),
                 self.raster(rectangle=(4, 6, 90, 45)),
                 self.raster(rectangle=(25, 6, 90, 45)),
                 self.raster(color=b'\xff\0\0'),
                 self.raster(color=b'\x80\x80\x80'),
                 (101, 60, b'\xff' * (101 * 60 * 3))]
        for index, raster in enumerate(cases):
            with self.subTest(index=index), self.assertRaises(render.FidelityError):
                render.picture_pixel_evidence('bounds', *raster, self.geometry(), (100, 60))

    def test_one_pixel_edge_antialiasing_is_allowed_but_holes_and_extra_ink_fail(self):
        width, height, pixels = self.raster()
        gray_edge = bytearray(pixels)
        gray_edge[(6 * width + 10) * 3:(6 * width + 10) * 3 + 3] = b'\x80' * 3
        evidence = render.picture_pixel_evidence('bounds', width, height, bytes(gray_edge), self.geometry(), (100, 60))
        self.assertEqual(evidence['gray_pixels'], 1)
        for position, color in ((0, b'\0' * 3), (20 * width + 30, b'\xff' * 3),
                                (20 * width + 30, b'\x80' * 3)):
            altered = bytearray(pixels)
            altered[position * 3:position * 3 + 3] = color
            with self.subTest(position=position, color=color), self.assertRaises(render.FidelityError):
                render.picture_pixel_evidence('bounds', width, height, bytes(altered), self.geometry(), (100, 60))

    def test_only_subpixel_page_rounding_accepts_an_extra_raster_row_or_column(self):
        self.assertEqual(render.picture_raster_size('bounds', [100.006, 60.0094]), [101, 61])
        self.assertEqual(render.picture_raster_size('landscape', [720, 405.014]), [720, 406])
        for size in ([100, 61], [100.1, 60], [99, 60], [100, float('nan')],
                     [100, float('inf')], [True, 60], [100], None):
            with self.subTest(size=size), self.assertRaises(render.FidelityError):
                render.picture_raster_size('bounds', size)
        # Supplying the correct point dimensions does not excuse a raster at
        # the wrong DPI or with different dimensions.
        with self.assertRaises(render.FidelityError):
            render.picture_pixel_evidence('bounds', *self.raster(), self.geometry(), (100.006, 60.0094))

    def test_package_geometry_rejects_hidden_overflow_even_when_visible_pixels_match(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'picture.pptx'
            self.package(path)
            self.assertEqual(render.picture_package_geometry(path, 'bounds'), self.geometry())
            # 110 points at x=10 clips to exactly the same visible 90-point
            # rectangle as the correct extent. Pixel equality cannot detect it.
            self.assertEqual(self.raster(rectangle=(10, 6, 110, 45)), self.raster())
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

            def output_text(args, **kwargs):
                return f'Pages: {page_count}\nPage size: 100 x 60 pts\n' if args[0] == 'pdfinfo' else '\f'

            with patch.object(render.subprocess, 'run', side_effect=command), \
                    patch.object(render.subprocess, 'check_output', side_effect=output_text):
                result = render.render_document(source, root, output, 0)
                measured = result['picture_pixel_evidence']
                self.assertEqual(measured['black_pixels'], 4050)
                self.assertEqual(measured['black_bbox'], [10, 6, 100, 51])
                self.assertEqual(result['pixel_sha256'], [measured['pixel_sha256']])
                self.assertEqual(json.loads(json.dumps(result)), result)
                for raster, page_count in ((self.raster(color=b'\xff' * 3), 1), (self.raster(), 2)):
                    with self.subTest(pages=page_count), self.assertRaises(render.FidelityError):
                        render.render_document(source, root, output, 1)


class CycleComparisonTests(unittest.TestCase):
    def test_omitted_table_grid_requires_matching_native_source(self):
        for folder in ('fidelity-table-grid', 'engine/fidelity-table-grid'):
            with self.subTest(folder=folder):
                cycles = [f'{folder}/omitted-{cycle}.docx' for cycle in range(1, 4)]
                source = f'{folder}/omitted-source.docx'
                files = [source, *cycles]
                records = {name: record(name) for name in files}
                passing = render.cycle_coverage(files, records)
                self.assertEqual(passing['failures'], [])
                self.assertEqual(passing['baseline_comparisons'], 1)
                for changes in ({'text': 'Lost native omitted cell geometry'},
                                {'pixels': ['2' * 64]}, {'pages': 2}):
                    broken = dict(records, **{source: record(source, **changes)})
                    self.assertEqual(len(render.cycle_coverage(files, broken)['failures']), 1)
                self.assertEqual(len(render.cycle_coverage(cycles, records)['failures']), 1)

    def test_omitted_grid_edits_require_the_authored_postedit_expectation(self):
        for folder in ('fidelity-table-grid', 'engine/fidelity-table-grid'):
            with self.subTest(folder=folder):
                cycles = [f'{folder}/omitted-edited-{cycle}.docx'
                          for cycle in range(1, 4)]
                expected = f'{folder}/omitted-edited-expected.docx'
                original = f'{folder}/omitted-source.docx'
                files = [original, expected, *cycles]
                records = {name: record(name, text='Still editable') for name in files}
                records[original] = record(original, text='First physical')
                passing = render.cycle_coverage(files, records)
                self.assertEqual(passing['failures'], [])
                self.assertEqual(passing['baseline_comparisons'], 1)
                self.assertEqual(passing['cycle_comparisons'][0]['baseline'], expected)
                for changes in ({'text': 'Wrong replacement'},
                                {'pixels': ['2' * 64]}, {'pages': 2}):
                    broken = dict(records, **{expected: record(expected, **changes)})
                    self.assertEqual(len(render.cycle_coverage(files, broken)['failures']), 1)
                without_expected = [original, *cycles]
                self.assertEqual(len(render.cycle_coverage(without_expected, records)['failures']), 1)
                # A repeated but unchanged export must not satisfy an edit.
                unchanged = {name: record(name, text='First physical') for name in files}
                unchanged[expected] = record(expected, text='Still editable')
                self.assertEqual(len(render.cycle_coverage(files, unchanged)['failures']), 1)

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

    def test_expansion_first_saves_require_their_independent_native_references(self):
        authored = [
            ('fidelity-bookmark-copy', 'copied', '.docx', 'copied-expected.docx'),
            ('fidelity-bookmark-copy', 'editor', '.docx', 'copied-expected.docx'),
            ('fidelity-sheet-qualified-names', 'recalculated', '.xlsx', 'expected-recalculated.xlsx'),
            ('fidelity-sheet-qualified-names', 'renamed', '.xlsx', 'expected-renamed.xlsx'),
            ('fidelity-sheet-rename', 'renamed', '.xlsx', 'qualified-expected.xlsx'),
            ('fidelity-slide-arrange', 'direct', '.pptx', 'source.pptx'),
            ('fidelity-slide-arrange', 'isolate', '.pptx', 'source.pptx'),
        ]
        for folder, stem, suffix, expected in authored:
            with self.subTest(folder=folder, case=stem):
                cycles = [f'package/{folder}/{stem}-{n}{suffix}' for n in (1, 2, 3)]
                baseline = f'package/{folder}/{expected}'
                files = cycles + [baseline]
                records = {name: record(name) for name in files}
                passing = render.cycle_coverage(files, records)
                self.assertEqual(passing['failures'], [])
                self.assertEqual(passing['baseline_comparisons'], 1)
                self.assertEqual(passing['cycle_comparisons'][0]['baseline'], baseline)
                missing = render.cycle_coverage(cycles, records)
                self.assertIn('Missing required native baseline', missing['failures'][0]['error'])
                for difference in ({'text': 'Different authored content'},
                                   {'pixels': ['9' * 64]}, {'pages': 2}):
                    records[baseline] = record(baseline, **difference)
                    failure = render.cycle_coverage(files, records)
                    self.assertEqual(len(failure['failures']), 1)
                    self.assertIn('Render changed', failure['failures'][0]['error'])

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
        for prefix in ('fidelity-table-widths', 'engine/fidelity-table-widths'):
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
        self.assertEqual(render.table_grid_baseline(Path('direct/format.docx'), '/tmp/fidelity-table-widths'),
                         'expected-format.docx')
        for case in ('fidelity-table-widths/preview/format.docx', 'other/direct/format.docx',
                     'fidelity-table-widths/direct/format.xlsx', 'fidelity-table-widths/direct/other.docx'):
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
            with patch.object(render.subprocess, 'run'):
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


if __name__ == '__main__':
    unittest.main()
