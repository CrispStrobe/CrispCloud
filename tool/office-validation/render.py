#!/usr/bin/env python3
"""Render exported Office files with LibreOffice and compare repeated saves.

Usage: render.py INPUT_DIRECTORY OUTPUT_DIRECTORY

The fidelity corpus uses three numbered saves per case, either CASE-1..3 or
CASE-0..2. Unnumbered files are rendered and reported without implying repeated
save coverage. A roundtrip series also compares against a sibling edited file;
an unchanged/imported series compares against a sibling input/source file when supplied.
Explicit corpus mappings additionally require native baselines for unchanged
scenarios whose names do not express that contract. Native sectioned presentation
cases also compare their first save against an explicit source-page permutation.
Requires LibreOffice and Poppler; PNG creation uses only Python's standard library.
"""
import argparse
from collections import defaultdict
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import shutil
import signal
import struct
import subprocess
import tempfile
import zlib
from xml.etree import ElementTree as ET
from zipfile import BadZipFile, ZipFile

OFFICE_SUFFIXES = {'.docx', '.xlsx', '.pptx'}
CYCLE_COUNT = 3
SOFFICE_MAX_ATTEMPTS = 3
# POSIX subprocess return codes identify signal termination by a negative
# number. Platforms without SIGKILL simply have no eligible retry code.
SOFFICE_SIGKILL_RETURN_CODE = -int(signal.SIGKILL) if hasattr(signal, 'SIGKILL') else None
# This producer deep-clones imported body blocks without intended visible edits.
# Do not infer that other "cloned", "edited", or "frame" series are unchanged.
# The directory and Office format are part of this specific corpus contract.
REQUIRED_SERIES_BASELINES = {
    ('fidelity-bookmarks', 'cloned.docx'): 'source.docx',
    ('fidelity-frame-wrap', 'none.docx'): 'none-source.docx',
    ('fidelity-frame-wrap', 'square.docx'): 'square-source.docx',
    ('fidelity-frame-wrap', 'topBottom.docx'): 'topBottom-source.docx',
}
# This six-slide native fixture changes only slide order and section membership.
# These are authored page orders, independent of the engine/XML oracle. Scope
# them to the exact producer directory, direct/isolate mode and PPTX filename.
SECTION_PAGE_ORDERS = {
    'unchanged.pptx': (1, 2, 3, 4, 5, 6),
    'within.pptx': (2, 1, 3, 4, 5, 6),
    'forward.pptx': (2, 3, 4, 1, 5, 6),
    'backward.pptx': (1, 6, 2, 3, 4, 5),
    'emptied.pptx': (3, 1, 2, 4, 5, 6),
}
NATIVE_AUX_CORPUS = 'fidelity-aux-controls'
NATIVE_AUX_FILES = {'source.docx'} | {
    f'{phase}-{cycle}.docx' for phase in ('imported', 'edited') for cycle in range(1, 4)}
NATIVE_AUX_REASON = (
    'LibreOffice rejected the authored native block content control in a comment. '
    'These exact files passed the independent native XML oracle and matching '
    'Open XML SDK receipts; they have no visual certification from this renderer.')
# Authored expectations for the host's opaque black picture insertion fixtures.
# Points equal pixels at the fixed 72 dpi used below. These are not inferred
# from the exported picture, and no other text-free document is exempted.
HOST_PICTURE_GEOMETRY = {
    'landscape': ((720, 405), (72, 40.5, 360, 180)),
    'portrait': ((720, 405), (72, 40.5, 120, 240)),
    'square': ((720, 405), (72, 40.5, 240, 240)),
    'bounds': ((100, 72), (10, 7.2, 90, 45)),
    'word-jpeg': ((595.3, 841.9), (72, 84, 60, 30)),
    'word-gif': ((595.3, 841.9), (72, 84, 60, 30)),
}
HOST_PICTURE_ORACLE = 'host-slide-black-picture-v1'
HOST_WORD_PICTURE_ORACLE = 'host-word-black-picture-v1'


def office_binary():
    """LibreOffice is installed as ``libreoffice`` on Linux, ``soffice`` on macOS."""
    return shutil.which('libreoffice') or shutil.which('soffice') or 'libreoffice'


class FidelityError(ValueError):
    """Missing evidence or a difference detected by the independent renderer."""


class MissingPdfError(FidelityError):
    """A completed Office conversion produced no usable PDF; retain its evidence."""

    def __init__(self, conversion):
        super().__init__('LibreOffice did not produce a nonempty PDF')
        self.returncode = conversion.returncode
        self.stdout = conversion.stdout
        self.stderr = conversion.stderr


def diagnostic_text(value):
    return value.decode('utf-8', errors='replace') if isinstance(value, bytes) else value or ''


def conversion_diagnostics(error):
    """Keep both output streams, including the zero-exit/no-PDF case."""
    if not isinstance(error, (MissingPdfError, subprocess.CalledProcessError)):
        return {}

    return {'returncode': error.returncode, 'stdout': diagnostic_text(error.stdout),
            'stderr': diagnostic_text(error.stderr)}


def failure_details(error):
    details = {'error': str(error), **conversion_diagnostics(error)}
    if hasattr(error, 'conversion_attempts'):
        details['conversion_attempts'] = error.conversion_attempts
    return details


def discover_inputs(root):
    root = Path(root)
    if not root.is_dir():
        raise FidelityError(f'Input directory does not exist: {root}')
    paths = sorted(p for p in root.rglob('*')
                   if p.is_file() and p.suffix.lower() in OFFICE_SUFFIXES)
    if not paths:
        raise FidelityError('No Office documents to render')
    return paths


def ordered_pages(directory, expected_pages):
    """Require exactly pages 1..N, sorting numerically rather than lexically."""
    if expected_pages < 1:
        raise FidelityError('PDF contains no pages')
    pages = {}
    for path in Path(directory).glob('page-*.ppm'):
        match = re.fullmatch(r'page-(\d+)\.ppm', path.name)
        if not match:
            raise FidelityError(f'Unexpected page artifact: {path.name}')
        number = int(match[1])
        if number in pages:
            raise FidelityError(f'Duplicate page number {number}')
        pages[number] = path
    expected = set(range(1, expected_pages + 1))
    actual = set(pages)
    if actual != expected:
        raise FidelityError(
            f'Incomplete rendered pages: missing={sorted(expected - actual)}, '
            f'unexpected={sorted(actual - expected)}')
    return [pages[number] for number in sorted(pages)]


def ppm_pixels(data):
    """Read Poppler's binary P6 RGB output without stripping pixel bytes."""
    offset = 0
    tokens = []
    whitespace = b' \t\r\n\v\f'
    while len(tokens) < 4:
        while offset < len(data):
            if data[offset] in whitespace:
                offset += 1
            elif data[offset:offset + 1] == b'#':
                newline = data.find(b'\n', offset)
                if newline < 0:
                    raise FidelityError('Truncated PPM header comment')
                offset = newline + 1
            else:
                break
        start = offset
        while offset < len(data) and data[offset] not in whitespace:
            offset += 1
        if start == offset:
            raise FidelityError('Truncated PPM header')
        tokens.append(data[start:offset])
    if tokens[0] != b'P6' or tokens[3] != b'255':
        raise FidelityError('Expected an 8-bit RGB P6 page from Poppler')
    try:
        width, height = int(tokens[1]), int(tokens[2])
    except ValueError as error:
        raise FidelityError('Invalid PPM dimensions') from error
    if width < 1 or height < 1 or offset >= len(data):
        raise FidelityError('Invalid or empty PPM page')
    # Only the header separator belongs to the header. RGB bytes can themselves
    # be spaces, newlines or '#', so stripping them here corrupts pixels.
    offset += 2 if data[offset:offset + 2] == b'\r\n' else 1
    pixels = data[offset:]
    if len(pixels) != width * height * 3:
        raise FidelityError('PPM pixel data length does not match its dimensions')
    return width, height, pixels


def png_bytes(width, height, pixels):
    """Encode exact RGB pixels as a deterministic, non-interlaced PNG."""
    if width < 1 or height < 1 or len(pixels) != width * height * 3:
        raise FidelityError('Invalid RGB image dimensions or payload')

    def chunk(kind, payload):
        checksum = zlib.crc32(kind + payload) & 0xffffffff
        return struct.pack('>I', len(payload)) + kind + payload + struct.pack('>I', checksum)

    stride = width * 3
    scanlines = b''.join(b'\0' + pixels[start:start + stride]
                         for start in range(0, len(pixels), stride))
    return (b'\x89PNG\r\n\x1a\n'
            + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(scanlines)) + chunk(b'IEND', b''))


def host_picture_case(path, root=None):
    """Select the twelve slide PNG and six Word JPEG/GIF authored exports."""
    path = Path(root) / path if root is not None else Path(path)
    if path.parent.name != 'fidelity-host':
        return None
    match = re.fullmatch(r'slide-picture-(landscape|portrait|square|bounds)-[123]\.pptx',
                         path.name)
    if match:
        return match[1]
    match = re.fullmatch(r'word-picture-(jpeg|gif)-[123]\.docx', path.name)
    return 'word-' + match[1] if match else None


def picture_source_geometry(case):
    page, rectangle = HOST_PICTURE_GEOMETRY[case]
    if case in ('word-jpeg', 'word-gif'):
        return {'page_twips': [11906, 16838],
                'margins_twips': [1440, 1440, 1440, 1440, 720, 720],
                'leading_spacing_twips': [0, 0, 240], 'leading_line_rule': 'exact',
                'inline_extent_emu': [762000, 381000],
                'inline_distances_emu': [0, 0, 114300, 114300],
                'picture_offset_emu': [0, 0], 'picture_extent_emu': [762000, 381000],
                'media_dimensions_pixels': [80, 40], 'media_mime': 'image/' + case[5:]}
    return {'page_emu': [round(value * 12700) for value in page],
            'rect_emu': [round(value * 12700) for value in rectangle]}


def picture_media_dimensions(payload, kind):
    """Check encoded dimensions independently; actual decoded pixels are checked later."""
    if kind == 'gif':
        if payload[:6] not in (b'GIF87a', b'GIF89a') or len(payload) < 14:
            raise ValueError('Expected a GIF image')
        dimensions = list(struct.unpack('<HH', payload[6:10]))
        offset = 13 + (3 * (2 ** ((payload[10] & 7) + 1)) if payload[10] & 128 else 0)
        frames = 0
        while offset < len(payload):
            marker = payload[offset]
            offset += 1
            if marker == 0x3b:
                if frames != 1 or offset != len(payload):
                    raise ValueError('Expected one complete GIF frame')
                return dimensions
            if marker == 0x2c:
                left, top, width, height, packed = struct.unpack('<HHHHB', payload[offset:offset + 9])
                if [left, top, width, height] != [0, 0, *dimensions]:
                    raise ValueError('Unexpected GIF frame bounds')
                frames += 1
                offset += 9 + (3 * (2 ** ((packed & 7) + 1)) if packed & 128 else 0)
                offset += 1  # LZW minimum code size, followed by data sub-blocks.
            elif marker == 0x21:
                offset += 1  # Extension label, followed by data sub-blocks.
            else:
                raise ValueError('Unexpected GIF block')
            while offset < len(payload):
                size = payload[offset]
                offset += 1
                if not size:
                    break
                offset += size
        raise ValueError('Truncated GIF image')
    if payload[:2] != b'\xff\xd8' or payload[-2:] != b'\xff\xd9':
        raise ValueError('Expected a JPEG image')
    offset = 2
    while offset + 4 <= len(payload):
        if payload[offset] != 0xff:
            raise ValueError('Invalid JPEG marker')
        marker = payload[offset + 1]
        length = int.from_bytes(payload[offset + 2:offset + 4], 'big')
        if length < 2 or offset + 2 + length > len(payload):
            raise ValueError('Invalid JPEG segment length')
        if marker in (0xc0, 0xc2):
            if length < 8:
                raise ValueError('Truncated JPEG frame')
            return [int.from_bytes(payload[offset + 7:offset + 9], 'big'),
                    int.from_bytes(payload[offset + 5:offset + 7], 'big')]
        if marker == 0xda:
            break
        offset += 2 + length
    raise ValueError('JPEG dimensions are missing')


def word_picture_package_geometry(path, case):
    """Require the authored A4 page, 12-point empty line and sole inline image."""
    ns = {'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
          'wp': 'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing',
          'a': 'http://schemas.openxmlformats.org/drawingml/2006/main',
          'pic': 'http://schemas.openxmlformats.org/drawingml/2006/picture',
          'r': 'http://schemas.openxmlformats.org/officeDocument/2006/relationships',
          'pr': 'http://schemas.openxmlformats.org/package/2006/relationships',
          'ct': 'http://schemas.openxmlformats.org/package/2006/content-types'}
    w = '{' + ns['w'] + '}'
    kind = case[5:]
    try:
        with ZipFile(path) as package:
            document = ET.fromstring(package.read('word/document.xml'))
            body = document.find('w:body', ns)
            if ([node.tag for node in body] != [w + 'p', w + 'p', w + 'sectPr']
                    or any(node.text for node in document.findall('.//w:t', ns))):
                raise ValueError('Expected two text-free paragraphs and one section')
            leading, drawing, section = body
            spacing = leading.find('w:pPr/w:spacing', ns)
            if (spacing.attrib != {w + 'before': '0', w + 'after': '0', w + 'line': '240', w + 'lineRule': 'exact'}
                    # Reopening removes the optional empty run but preserves
                    # the authored exact line; breaks or extra runs cannot pass.
                    or [node.tag for node in leading] not in ([w + 'pPr'], [w + 'pPr', w + 'r'])
                    or any(len(run.findall('w:t', ns)) != 1
                           or any(node.tag not in (w + 'rPr', w + 't') for node in run)
                           for run in leading.findall('w:r', ns))
                    or [node.tag for node in leading.find('w:pPr', ns)] != [w + 'spacing', w + 'ind', w + 'jc']
                    or leading.find('w:pPr/w:ind', ns).attrib != {w + 'left': '0', w + 'right': '0'}
                    or leading.find('w:pPr/w:jc', ns).get(w + 'val') != 'left'
                    or [node.tag for node in drawing] != [w + 'r']
                    or [node.tag for node in drawing[0]] != [w + 'drawing']):
                raise ValueError('Unexpected paragraph geometry')
            size, margins = section.find('w:pgSz', ns), section.find('w:pgMar', ns)
            if (set(size.attrib) != {w + 'w', w + 'h'}
                    or set(margins.attrib) != {w + name for name in ('top', 'bottom', 'left', 'right', 'header', 'footer')}
                    or section.find('w:cols', ns).get(w + 'num') != '1'
                    or section.findall('w:headerReference', ns) or section.findall('w:footerReference', ns)
                    or len(document.findall('.//w:drawing', ns)) != 1
                    or len(document.findall('.//wp:inline', ns)) != 1
                    or document.findall('.//wp:anchor', ns)):
                raise ValueError('Unexpected page or image structure')
            inline = drawing.find('w:r/w:drawing/wp:inline', ns)
            extent = inline.find('wp:extent', ns)
            graphic = inline.find('a:graphic/a:graphicData', ns)
            picture = graphic.find('pic:pic', ns)
            transform = picture.find('pic:spPr/a:xfrm', ns)
            offset, picture_extent = transform.find('a:off', ns), transform.find('a:ext', ns)
            blip = picture.find('pic:blipFill/a:blip', ns)
            embed = '{' + ns['r'] + '}embed'
            if (transform.attrib or set(blip.attrib) != {embed} or list(blip)
                    or set(inline.attrib) != {'distT', 'distB', 'distL', 'distR'}
                    or graphic.get('uri') != ns['pic'] or len(graphic) != 1
                    or len(document.findall('.//pic:pic', ns)) != 1
                    or document.findall('.//a:srcRect', ns)
                    or inline.find('wp:effectExtent', ns).attrib != {'l': '0', 't': '0', 'r': '0', 'b': '0'}):
                raise ValueError('Unexpected crop, rotation, effect or picture count')
            relations = ET.fromstring(package.read('word/_rels/document.xml.rels'))
            matches = [node for node in relations if node.get('Id') == blip.get(embed)]
            target = f'media/image1.{kind}'
            if (len(matches) != 1 or matches[0].get('Type') != ns['r'] + '/image'
                    or matches[0].get('Target') != target or matches[0].get('TargetMode') is not None):
                raise ValueError('Unexpected owning image relationship')
            media = 'word/' + target
            if [name for name in package.namelist() if name.startswith('word/media/')] != [media]:
                raise ValueError('Expected exactly one media part')
            types = ET.fromstring(package.read('[Content_Types].xml'))
            mime = [node.get('ContentType') for node in types.findall('ct:Default', ns)
                    if node.get('Extension') == kind]
            overrides = [node.get('ContentType') for node in types.findall('ct:Override', ns)
                         if node.get('PartName') == '/' + media]
            if mime != ['image/' + kind] or overrides != mime:
                raise ValueError('Unexpected image content type')
            actual = {'page_twips': [int(size.get(w + key)) for key in ('w', 'h')],
                      'margins_twips': [int(margins.get(w + key)) for key in ('top', 'bottom', 'left', 'right', 'header', 'footer')],
                      'leading_spacing_twips': [int(spacing.get(w + key)) for key in ('before', 'after', 'line')],
                      'leading_line_rule': spacing.get(w + 'lineRule'),
                      'inline_extent_emu': [int(extent.get(key)) for key in ('cx', 'cy')],
                      'inline_distances_emu': [int(inline.get(key)) for key in ('distT', 'distB', 'distL', 'distR')],
                      'picture_offset_emu': [int(offset.get(key)) for key in ('x', 'y')],
                      'picture_extent_emu': [int(picture_extent.get(key)) for key in ('cx', 'cy')],
                      'media_dimensions_pixels': picture_media_dimensions(package.read(media), kind),
                      'media_mime': mime[0]}
            if actual != picture_source_geometry(case):
                raise ValueError(f'Unexpected Word picture geometry: {actual}')
            return actual
    except (BadZipFile, KeyError, ET.ParseError, AttributeError, TypeError, ValueError, struct.error) as error:
        raise FidelityError(f'Host Word picture package geometry mismatch: {error}') from error


def picture_package_geometry(path, case):
    """Reject invisible clipped overflow as well as incorrect visible geometry.

    The bounds fixture touches the page edge: pixels alone cannot distinguish
    its authored extent from an over-wide picture clipped by the PDF page.
    Check the sole picture's raw OOXML transform independently for this corpus.
    """
    if case in ('word-jpeg', 'word-gif'):
        return word_picture_package_geometry(path, case)
    ns = {'p': 'http://schemas.openxmlformats.org/presentationml/2006/main',
          'a': 'http://schemas.openxmlformats.org/drawingml/2006/main',
          'r': 'http://schemas.openxmlformats.org/officeDocument/2006/relationships',
          'pr': 'http://schemas.openxmlformats.org/package/2006/relationships'}
    expected = picture_source_geometry(case)
    try:
        with ZipFile(path) as package:
            presentation = ET.fromstring(package.read('ppt/presentation.xml'))
            relations = ET.fromstring(package.read('ppt/_rels/presentation.xml.rels'))
            slides = presentation.findall('p:sldIdLst/p:sldId', ns)
            if len(slides) != 1:
                raise ValueError('Expected one slide')
            identifier = slides[0].get('{' + ns['r'] + '}id')
            targets = [rel for rel in relations if rel.get('Id') == identifier]
            if (len(targets) != 1 or targets[0].get('Target') != 'slides/slide1.xml'
                    or targets[0].get('TargetMode') is not None
                    or targets[0].get('Type') != ns['r'] + '/slide'):
                raise ValueError('Unexpected slide relationship')
            slide = ET.fromstring(package.read('ppt/slides/slide1.xml'))
        size = presentation.find('p:sldSz', ns)
        tree = slide.find('p:cSld/p:spTree', ns)
        shapes = [node for node in tree if node.tag not in
                  ('{' + ns['p'] + '}nvGrpSpPr', '{' + ns['p'] + '}grpSpPr')]
        if len(shapes) != 1 or shapes[0].tag != '{' + ns['p'] + '}pic':
            raise ValueError('Expected one ungrouped picture')
        transform = shapes[0].find('p:spPr/a:xfrm', ns)
        if transform.attrib:
            raise ValueError('Unexpected picture rotation or flip')
        offset, extent = transform.find('a:off', ns), transform.find('a:ext', ns)
        actual = {'page_emu': [int(size.get(key)) for key in ('cx', 'cy')],
                  'rect_emu': [int(node.get(key)) for node, key in
                               ((offset, 'x'), (offset, 'y'), (extent, 'cx'), (extent, 'cy'))]}
        if actual != expected:
            raise ValueError(f'Expected {expected}, found {actual}')
        return actual
    except (BadZipFile, KeyError, ET.ParseError, AttributeError, TypeError, ValueError) as error:
        raise FidelityError(f'Host picture package geometry mismatch: {error}') from error


def picture_raster_size(case, page_points):
    """Allow only LibreOffice's subpixel point-to-millimetre page rounding."""
    expected, _ = HOST_PICTURE_GEOMETRY[case]
    if (not isinstance(page_points, (list, tuple)) or len(page_points) != 2
            or any(type(value) not in (int, float) or not math.isfinite(value)
                   or abs(value - target) > 0.03 for value, target in zip(page_points, expected))):
        raise FidelityError('Host picture PDF page size differs from the authored page')
    # Poppler rounds the physical page up to whole pixels at 72 dpi. For
    # example, LibreOffice's 100.006 x 72 pt page yields 101 x 72 pixels.
    return [math.ceil(value) for value in page_points]


def validate_picture_evidence(evidence, case, fingerprint):
    """Validate measured values again when accepting a repeated-save series."""
    page, rectangle = HOST_PICTURE_GEOMETRY[case]
    x, y, width, height = rectangle
    count_keys = ('black_pixels', 'white_pixels', 'gray_pixels', 'colored_pixels',
                  'outside_nonwhite_pixels', 'interior_nonblack_pixels')
    raster_size = picture_raster_size(case, evidence.get('page_size_points')) if isinstance(evidence, dict) else None
    oracle = HOST_WORD_PICTURE_ORACLE if case in ('word-jpeg', 'word-gif') else HOST_PICTURE_ORACLE
    if (not isinstance(evidence, dict) or evidence.get('oracle') != oracle
            or evidence.get('case') != case or evidence.get('dpi') != 72
            or evidence.get('page_size') != raster_size
            or evidence.get('expected_page_size') != list(page)
            or evidence.get('expected_rect') != list(rectangle)
            or evidence.get('pixel_sha256') != fingerprint
            or evidence.get('source_geometry') != picture_source_geometry(case)
            or any(type(evidence.get(key)) is not int or evidence[key] < 0 for key in count_keys)):
        raise FidelityError('Missing or inconsistent host picture pixel evidence')
    bounds = evidence.get('black_bbox')
    if (not isinstance(bounds, list) or len(bounds) != 4
            or any(type(value) is not int for value in bounds)
            or any(abs(actual - expected) > 1 for actual, expected in
                   zip(bounds, (x, y, x + width, y + height)))
            or abs(evidence['black_pixels'] - width * height) > 2 * (width + height) + 4
            or sum(evidence[key] for key in count_keys[:3]) != raster_size[0] * raster_size[1]
            or any(evidence[key] != 0 for key in count_keys[3:])):
        raise FidelityError('Host picture pixels differ from the authored black rectangle')


def picture_pixel_evidence(case, width, height, pixels, source_geometry, page_points):
    """Measure the actual native raster; only a one-pixel edge band may vary."""
    page, rectangle = HOST_PICTURE_GEOMETRY[case]
    if [width, height] != picture_raster_size(case, page_points) or len(pixels) != width * height * 3:
        raise FidelityError('Host picture page dimensions differ from the authored page')
    x, y, rect_width, rect_height = rectangle
    right, bottom = x + rect_width, y + rect_height
    oracle = HOST_WORD_PICTURE_ORACLE if case in ('word-jpeg', 'word-gif') else HOST_PICTURE_ORACLE
    evidence = {'oracle': oracle, 'case': case, 'dpi': 72,
                'page_size': [width, height], 'expected_page_size': list(page),
                'page_size_points': list(page_points), 'expected_rect': list(rectangle),
                'source_geometry': source_geometry,
                'pixel_sha256': hashlib.sha256(struct.pack('>II', width, height) + pixels).hexdigest(),
                'black_pixels': 0, 'white_pixels': 0, 'gray_pixels': 0,
                'colored_pixels': 0, 'outside_nonwhite_pixels': 0, 'interior_nonblack_pixels': 0}
    bounds = [width, height, 0, 0]
    for position in range(width * height):
        rgb = pixels[position * 3:position * 3 + 3]
        low, high = min(rgb), max(rgb)
        black, white = high <= 16, low >= 239
        evidence['black_pixels' if black else 'white_pixels' if white else 'gray_pixels'] += 1
        evidence['colored_pixels'] += high - low > 2
        column, row = position % width, position // width
        cx, cy = column + 0.5, row + 0.5
        if black:
            bounds = [min(bounds[0], column), min(bounds[1], row),
                      max(bounds[2], column + 1), max(bounds[3], row + 1)]
        if cx < x - 1 or cx > right + 1 or cy < y - 1 or cy > bottom + 1:
            evidence['outside_nonwhite_pixels'] += not white
        elif x + 1 <= cx <= right - 1 and y + 1 <= cy <= bottom - 1:
            evidence['interior_nonblack_pixels'] += not black
    evidence['black_bbox'] = bounds
    validate_picture_evidence(evidence, case, evidence['pixel_sha256'])
    return evidence


def validate_record(record, *, root=None):
    pages = record.get('pages')
    text = record.get('text')
    pixels = record.get('pixel_sha256')
    if (type(pages) is not int or pages < 1 or not isinstance(text, str)
            or not isinstance(pixels, list)
            or len(pixels) != pages
            or any(not isinstance(digest, str) or not re.fullmatch(r'[0-9a-f]{64}', digest)
                   for digest in pixels)):
        raise FidelityError(f'Invalid or empty render evidence: {record.get("file")}')
    case = host_picture_case(record.get('file', ''), root)
    if case is not None:
        if pages != 1:
            raise FidelityError('Host picture corpus must render exactly one page')
        validate_picture_evidence(record.get('picture_pixel_evidence'), case, pixels[0])
    elif not text.strip():
        raise FidelityError(f'Invalid or empty render evidence: {record.get("file")}')


def compare_records(reference, actual, *, root=None):
    """Compare text, page count and decoded RGB fingerprints independently."""
    validate_record(reference, root=root)
    validate_record(actual, root=root)
    for key in ('pages', 'text', 'pixel_sha256', 'picture_pixel_evidence'):
        if reference.get(key) != actual.get(key):
            raise FidelityError(
                f'Render changed ({key}): {reference["file"]} -> {actual["file"]}')


def compare_page_order(reference, actual, order):
    """Require unchanged native page text and RGB pixels in an authored order."""
    validate_record(reference)
    if (len(order) != reference['pages']
            or any(type(page) is not int for page in order)
            or sorted(order) != list(range(1, reference['pages'] + 1))):
        raise FidelityError(f'Native page count/permutation mismatch: {reference["file"]}')
    # pdftotext emits one form feed after each page. Preserve every other
    # character, including layout whitespace; missing/blank pages cannot pass.
    text_pages = reference['text'].split('\f')
    if (len(text_pages) != reference['pages'] + 1 or text_pages[-1] != ''
            or any(not page.strip() for page in text_pages[:-1])):
        raise FidelityError(f'Incomplete native page text: {reference["file"]}')
    expected = dict(reference,
                    text=''.join(text_pages[page - 1] + '\f' for page in order),
                    pixel_sha256=[reference['pixel_sha256'][page - 1] for page in order])
    compare_records(expected, actual)


def section_page_order(case, root=None):
    # root retains the corpus identity even when it is itself the CLI input
    # directory. Record filenames remain relative to that input directory.
    context = Path(root) / case if root is not None else case
    if (context.parent.parent.name == 'fidelity-slide-sections'
            and context.parent.name in ('direct', 'isolate')):
        return SECTION_PAGE_ORDERS.get(case.name)
    return None


def table_grid_baseline(case, root=None):
    """Select authored native expectations for the exact merged-table corpus."""
    context = Path(root) / case if root is not None else case
    if (context.parent.parent.name == 'fidelity-table-grid'
            and context.parent.name in ('direct', 'isolate')
            and case.suffix == '.docx'
            and case.stem in ('unchanged', 'format', 'replace', 'unmerge')):
        name = 'source.docx' if case.stem == 'unchanged' else f'expected-{case.stem}.docx'
        return (case.parent.parent / name).as_posix()
    return None


def cycle_coverage(files, records, *, root=None):
    """Check exact corpus series membership, including failed/missing renders."""
    groups = defaultdict(list)
    singles = []
    for name in files:
        path = Path(name)
        match = re.fullmatch(r'(.+)-(\d+)', path.stem)
        if match:
            key = (path.parent / (match[1] + path.suffix)).as_posix()
            groups[key].append((int(match[2]), name))
        else:
            singles.append(name)
    failures = []
    comparisons = []
    compared_files = set()
    baseline_comparisons = 0
    page_order_comparisons = 0
    for key, entries in sorted(groups.items()):
        entries.sort()
        numbers = [number for number, _ in entries]
        start = 0 if 0 in numbers else 1
        expected = list(range(start, start + CYCLE_COUNT))
        info = {'case': key, 'expected_cycles': expected, 'actual_cycles': numbers,
                'files': [name for _, name in entries], 'baseline': None,
                'baseline_candidate': None, 'baseline_page_order': None, 'passed': False}
        comparisons.append(info)
        try:
            if numbers != expected:
                raise FidelityError(
                    f'Incomplete cycle group {key}: expected {expected}, found {numbers}')
            for _, name in entries:
                if name not in records:
                    raise FidelityError(f'Missing successful render for cycle file: {name}')
            reference = records[entries[0][1]]
            for _, name in entries[1:]:
                compare_records(reference, records[name], root=root)
            case = Path(key)
            candidates = []
            required_baseline = REQUIRED_SERIES_BASELINES.get(
                (case.parent.name, case.name))
            required_grid_baseline = table_grid_baseline(case, root)
            page_order = section_page_order(case, root)
            if page_order is not None:
                required_baseline = 'source.pptx'
                info['baseline_page_order'] = list(page_order)
            if required_grid_baseline is not None:
                candidates = [required_grid_baseline]
            elif required_baseline is not None:
                candidates = [case.with_name(required_baseline).as_posix()]
            elif case.stem == 'roundtrip':
                candidates = [case.with_name('edited' + case.suffix).as_posix()]
            elif case.stem in ('unchanged', 'imported'):
                candidates = [case.with_name(prefix + case.suffix).as_posix()
                              for prefix in ('input', 'source')]
            elif case.stem.endswith(('-unchanged', '-imported')):
                prefix = case.stem.rsplit('-', 1)[0]
                candidates = [case.with_name(prefix + '-' + label + case.suffix).as_posix()
                              for label in ('input', 'source')]
            baseline = next((name for name in candidates if name in files),
                            candidates[0] if candidates else None)
            info['baseline_candidate'] = baseline
            if (required_baseline is not None or required_grid_baseline is not None) and baseline not in files:
                raise FidelityError(f'Missing required native baseline: {baseline}')
            if baseline in files:
                if baseline not in records:
                    raise FidelityError(f'Missing successful baseline render: {baseline}')
                if page_order is None:
                    compare_records(records[baseline], reference, root=root)
                else:
                    compare_page_order(records[baseline], reference, page_order)
                    page_order_comparisons += 1
                info['baseline'] = baseline
                compared_files.add(baseline)
                baseline_comparisons += 1
            info['passed'] = True
            compared_files.update(name for _, name in entries)
        except FidelityError as error:
            failures.append({'case': key, 'error': str(error)})
    return {
        'cycle_groups': len(groups),
        'cycle_comparisons': comparisons,
        'baseline_comparisons': baseline_comparisons,
        'page_order_comparisons': page_order_comparisons,
        'render_only_files': sorted(name for name in singles if name not in compared_files),
        'failures': failures,
    }


def native_aux_groups(paths):
    """This exception is limited to one declared producer and seven exact names."""
    groups = defaultdict(list)
    for path in paths:
        if path.parent.name == NATIVE_AUX_CORPUS and path.name in NATIVE_AUX_FILES:
            groups[path.parent].append(path)
    return groups


def validate_native_aux_corpus(paths):
    names = {path.name for path in paths}
    if names != NATIVE_AUX_FILES:
        raise FidelityError(f'Incomplete native auxiliary corpus: {sorted(NATIVE_AUX_FILES - names)}')
    oracle_path = (Path(__file__).resolve().parents[2] / 'packages/quds_office_engine'
                   / 'tool/fidelity/auxiliary_content_control_oracle.py')
    specification = importlib.util.spec_from_file_location('native_aux_oracle', oracle_path)
    if specification is None or specification.loader is None:
        raise FidelityError('Independent native auxiliary oracle is unavailable')
    oracle = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(oracle)
    for path in paths:
        try:
            with ZipFile(path) as archive:
                if len(archive.namelist()) != len(set(archive.namelist())) or archive.testzip() is not None:
                    raise FidelityError(f'Invalid native auxiliary ZIP: {path}')
                parts = {name: archive.read(name) for name in archive.namelist()}
            if not {'[Content_Types].xml', '_rels/.rels', 'word/document.xml'} <= parts.keys():
                raise FidelityError(f'Incomplete native auxiliary package: {path}')
            for name, payload in parts.items():
                if name.endswith(('.xml', '.rels')):
                    ET.fromstring(payload)
            oracle.inspect_parts(parts, edited=path.name.startswith('edited-'))
        except (AssertionError, KeyError, ET.ParseError, BadZipFile, RuntimeError) as error:
            raise FidelityError(f'Native auxiliary structure is not qualified: {path}: {error}') from error


def matching_schema_receipts(paths, report_path):
    """Require clean SDK results for these exact paths and current file bytes."""
    if report_path is None:
        raise FidelityError('No Open XML SDK schema receipt supplied for native-only evidence')
    try:
        report = json.loads(Path(report_path).read_text(encoding='utf-8'))
    except (OSError, ValueError) as error:
        raise FidelityError(f'Cannot read Open XML SDK schema receipt: {error}') from error
    if not isinstance(report, dict) or not isinstance(report.get('Reports'), list):
        raise FidelityError('Malformed Open XML SDK schema receipt')
    entries = defaultdict(list)
    for entry in report['Reports']:
        if isinstance(entry, dict) and isinstance(entry.get('File'), str):
            entries[Path(entry['File']).resolve()].append(entry)
    qualified = {}
    for path in paths:
        candidates = entries[path.resolve()]
        if len(candidates) != 1:
            raise FidelityError(f'Missing or ambiguous exact-path SDK receipt: {path}')
        entry = candidates[0]
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if entry.get('Errors') != [] or 'Exception' in entry:
            raise FidelityError(f'Native auxiliary file did not pass SDK validation: {path}')
        if entry.get('Sha256') != digest:
            raise FidelityError(f'Stale or missing SDK byte hash: {path}')
        qualified[path] = digest
    return qualified


def known_native_import_rejection(error):
    expected_exit = (
        isinstance(error, subprocess.CalledProcessError) and error.returncode == 1
        or isinstance(error, MissingPdfError) and error.returncode == 0)
    if not expected_exit:
        return False
    diagnostic = conversion_diagnostics(error)
    return any('Error: source file could not be loaded' in diagnostic[stream]
               for stream in ('stdout', 'stderr'))


def render_document(path, root, output, index):
    """Retry only killed SOFFICE conversions, retaining every attempt's evidence.

    Each attempt uses a fresh profile/output and the exact original input bytes.
    Normal converter errors and all subsequent PDF/text/pixel checks fail as
    before; a killed Poppler process cannot qualify for this bounded retry.
    """
    path, root, output = (Path(value).resolve() for value in (path, root, output))
    input_sha256 = hashlib.sha256(path.read_bytes()).hexdigest()
    attempts = []

    def unchanged(attempt=None):
        try:
            current = hashlib.sha256(path.read_bytes()).hexdigest()
            if attempt is not None:
                attempt.update(input_sha256_after=current, input_unchanged=current == input_sha256)
            if current != input_sha256:
                raise FidelityError('Office input changed during native rendering; retry rejected')
        except (OSError, FidelityError) as error:
            error.conversion_attempts = attempts
            raise

    for number in range(SOFFICE_MAX_ATTEMPTS):
        unchanged()
        try:
            record = _render_document_once(path, root, output, index, attempts, input_sha256)
        except (OSError, subprocess.SubprocessError, FidelityError) as error:
            unchanged(attempts[-1] if attempts else None)
            error.conversion_attempts = attempts
            if (isinstance(error, subprocess.CalledProcessError)
                    and getattr(error, '_soffice_sigkill', False)
                    and error.returncode == SOFFICE_SIGKILL_RETURN_CODE
                    and number + 1 < SOFFICE_MAX_ATTEMPTS):
                continue
            raise
        unchanged(attempts[-1])
        record.update(input_sha256=input_sha256, conversion_attempts=attempts)
        return record


def _render_document_once(path, root, output, index, attempts, input_sha256):
    picture_case = host_picture_case(path)
    geometry = picture_package_geometry(path, picture_case) if picture_case is not None else None
    environment = dict(os.environ, LC_ALL='C')
    number = len(attempts) + 1
    with tempfile.TemporaryDirectory(prefix=f'render-{index:03d}-attempt-{number}-', dir=output) as temporary:
        work = Path(temporary)
        command = [office_binary(), f'-env:UserInstallation={(work / "profile").as_uri()}',
                   '--headless', '--convert-to', 'pdf', '--outdir', str(work), str(path)]
        attempt = {'attempt': number, 'command': command, 'input_sha256_before': input_sha256}
        attempts.append(attempt)
        try:
            conversion = subprocess.run(command, check=True, timeout=60, capture_output=True, env=environment)
        except (OSError, subprocess.SubprocessError) as error:
            attempt.update(status='failed', error=str(error), returncode=getattr(error, 'returncode', None),
                           stdout=diagnostic_text(getattr(error, 'stdout', None)),
                           stderr=diagnostic_text(getattr(error, 'stderr', None)))
            # Mark only this exact subprocess failure, never downstream PDF or
            # image commands with the same negative return code.
            if (SOFFICE_SIGKILL_RETURN_CODE is not None
                    and isinstance(error, subprocess.CalledProcessError)
                    and error.returncode == SOFFICE_SIGKILL_RETURN_CODE):
                error._soffice_sigkill = True
            raise
        attempt.update(status='converted', returncode=conversion.returncode,
                       stdout=diagnostic_text(conversion.stdout), stderr=diagnostic_text(conversion.stderr))
        pdf = work / (path.stem + '.pdf')
        if not pdf.is_file() or pdf.stat().st_size == 0:
            raise MissingPdfError(conversion)
        info = subprocess.check_output(['pdfinfo', str(pdf)], text=True, timeout=30,
                                       env=environment)
        page_match = re.search(r'^Pages:\s+(\d+)\s*$', info, re.MULTILINE)
        if not page_match:
            raise FidelityError('pdfinfo did not report a page count')
        text = subprocess.check_output(['pdftotext', '-layout', '-enc', 'UTF-8', str(pdf), '-'],
                                       text=True, timeout=30, env=environment)
        if not text.strip() and picture_case is None:
            raise FidelityError('Rendered fidelity PDF has no extractable text')
        if picture_case is not None and int(page_match[1]) != 1:
            raise FidelityError('Host picture corpus must render exactly one page')
        picture_page_points = None
        if picture_case is not None:
            size = re.search(r'^Page size:\s+([\d.]+) x ([\d.]+) pts\b', info, re.MULTILINE)
            if size is None:
                raise FidelityError('pdfinfo did not report host picture page dimensions')
            picture_page_points = [float(size[1]), float(size[2])]
            picture_raster_size(picture_case, picture_page_points)
        subprocess.run(['pdftoppm', '-r', '72', str(pdf), str(work / 'page')],
                       check=True, timeout=60, capture_output=True, env=environment)
        pages = ordered_pages(work, int(page_match[1]))
        dest = output / f'{index:03d}'
        dest.mkdir(exist_ok=True)
        # Only renderer-owned page artifacts are replaced. Source Office files
        # are never opened for writing, and conversion used a fresh directory.
        for old in dest.glob('page-*.png'):
            old.unlink()
        artifacts = []
        picture_evidence = None
        for number, ppm in enumerate(pages, 1):
            width, height, pixels = ppm_pixels(ppm.read_bytes())
            if picture_case is not None:
                picture_evidence = picture_pixel_evidence(
                    picture_case, width, height, pixels, geometry, picture_page_points)
            png = dest / f'page-{number:04d}.png'
            png.write_bytes(png_bytes(width, height, pixels))
            fingerprint = hashlib.sha256(struct.pack('>II', width, height) + pixels).hexdigest()
            artifacts.append({'page': number, 'width': width, 'height': height,
                              'png': png.relative_to(output).as_posix(),
                              'pixel_sha256': fingerprint})
        shutil.copyfile(pdf, dest / 'document.pdf')
        (dest / 'text.txt').write_text(text, encoding='utf-8')
        record = {'file': path.relative_to(root).as_posix(), 'pages': len(artifacts),
                  'text': text, 'pixel_sha256': [page['pixel_sha256'] for page in artifacts],
                  'pdf': (dest / 'document.pdf').relative_to(output).as_posix(),
                  'page_artifacts': artifacts}
        if picture_evidence is not None:
            record['picture_pixel_evidence'] = picture_evidence
        validate_record(record, root=root)
        return record


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input_directory', type=Path)
    parser.add_argument('output_directory', type=Path)
    parser.add_argument('--schema-report', type=Path,
                        help='Open XML SDK receipts, including exact file SHA-256 values')
    args = parser.parse_args(argv)
    root, output = args.input_directory.resolve(), args.output_directory.resolve()
    output.mkdir(parents=True, exist_ok=True)
    reports, failures = {}, []
    native_only = []
    excluded = set()
    processed = set()
    renderer = None
    paths = []
    try:
        paths = discover_inputs(root)
        renderer = subprocess.check_output([office_binary(), '--version'], text=True,
                                           timeout=30).strip()
        if not renderer:
            raise FidelityError('LibreOffice did not report a version')
        indexes = {path: index for index, path in enumerate(paths)}
        for directory, corpus_paths in native_aux_groups(paths).items():
            source = directory / 'source.docx'
            source_name = source.relative_to(root).as_posix()
            try:
                validate_native_aux_corpus(corpus_paths)
            except (OSError, ValueError, ImportError) as error:
                failures.append({'file': source_name, 'error': str(error)})
                continue
            processed.add(source)
            try:
                record = render_document(source, root, output, indexes[source])
                reports[source_name] = record
                print(f'{source_name}: rendered {record["pages"]} pages', flush=True)
            except (OSError, subprocess.SubprocessError, FidelityError) as error:
                if not known_native_import_rejection(error):
                    failures.append({'file': source_name, **failure_details(error)})
                    continue
                try:
                    receipts = matching_schema_receipts(corpus_paths, args.schema_report)
                except FidelityError as qualification:
                    failures.append({'file': source_name, **failure_details(error),
                                     'qualification_error': str(qualification)})
                    continue
                conversion = conversion_diagnostics(error)
                diagnostic = '\n'.join(conversion[stream] for stream in ('stdout', 'stderr')
                                       if conversion[stream])
                for path in corpus_paths:
                    name = path.relative_to(root).as_posix()
                    excluded.add(name)
                    native_only.append({'file': name, 'status': 'native_schema_only',
                                        'reason': NATIVE_AUX_REASON, 'source': source_name,
                                        'source_diagnostic': diagnostic,
                                        'source_conversion': conversion,
                                        'source_conversion_attempts': getattr(error, 'conversion_attempts', []),
                                        'schema_sha256': receipts[path]})
                    print(f'{name}: native_schema_only; no visual certification', flush=True)
        for index, path in enumerate(paths):
            name = path.relative_to(root).as_posix()
            if path in processed or name in excluded:
                continue
            try:
                record = render_document(path, root, output, index)
                reports[name] = record
                print(f'{name}: rendered {record["pages"]} pages', flush=True)
            except (OSError, subprocess.SubprocessError, FidelityError) as error:
                failures.append({'file': name, **failure_details(error)})
                print(f'{name}: {error}', flush=True)
    except (OSError, subprocess.SubprocessError, FidelityError) as error:
        failures.append(failure_details(error))
    names = [path.relative_to(root).as_posix() for path in paths]
    coverage = cycle_coverage([name for name in names if name not in excluded], reports,
                              root=root)
    failures.extend(coverage.pop('failures'))
    report = {'renderer': renderer, 'files': len(paths), 'rendered_files': len(reports),
              'soffice_retry_policy': {'maximum_attempts': SOFFICE_MAX_ATTEMPTS,
                                       'retry_returncode': SOFFICE_SIGKILL_RETURN_CODE,
                                       'scope': 'SOFFICE conversion only; unchanged input and fresh profile/output per attempt'},
              'picture_pixel_oracle_files': sum('picture_pixel_evidence' in record
                                                for record in reports.values()),
              'visual_input_files': len(paths) - len(excluded),
              'native_schema_only_files': len(native_only), 'native_schema_only': native_only,
              'schema_report': str(args.schema_report) if args.schema_report is not None else None,
              'pixel_fingerprint': 'SHA-256 of big-endian uint32 width/height followed by RGB bytes',
              **coverage, 'failures': failures, 'reports': list(reports.values())}
    (output / 'render-report.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    for failure in coverage['cycle_comparisons']:
        if not failure['passed']:
            print(f'{failure["case"]}: cycle comparison failed', flush=True)
    return 1 if failures else 0


if __name__ == '__main__':
    raise SystemExit(main())
