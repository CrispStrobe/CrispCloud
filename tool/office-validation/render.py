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
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tempfile
import zlib
from xml.etree import ElementTree as ET
from zipfile import BadZipFile, ZipFile

OFFICE_SUFFIXES = {'.docx', '.xlsx', '.pptx'}
CYCLE_COUNT = 3
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


def conversion_diagnostics(error):
    """Keep both output streams, including the zero-exit/no-PDF case."""
    if not isinstance(error, (MissingPdfError, subprocess.CalledProcessError)):
        return {}

    def text(value):
        return value.decode('utf-8', errors='replace') if isinstance(value, bytes) else value or ''

    return {'returncode': error.returncode, 'stdout': text(error.stdout),
            'stderr': text(error.stderr)}


def failure_details(error):
    return {'error': str(error), **conversion_diagnostics(error)}


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


def validate_record(record):
    pages = record.get('pages')
    text = record.get('text')
    pixels = record.get('pixel_sha256')
    if (type(pages) is not int or pages < 1 or not isinstance(text, str)
            or not text.strip() or not isinstance(pixels, list)
            or len(pixels) != pages
            or any(not isinstance(digest, str) or not re.fullmatch(r'[0-9a-f]{64}', digest)
                   for digest in pixels)):
        raise FidelityError(f'Invalid or empty render evidence: {record.get("file")}')


def compare_records(reference, actual):
    """Compare text, page count and decoded RGB fingerprints independently."""
    validate_record(reference)
    validate_record(actual)
    for key in ('pages', 'text', 'pixel_sha256'):
        if reference[key] != actual[key]:
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
                compare_records(reference, records[name])
            case = Path(key)
            candidates = []
            required_baseline = REQUIRED_SERIES_BASELINES.get(
                (case.parent.name, case.name))
            page_order = section_page_order(case, root)
            if page_order is not None:
                required_baseline = 'source.pptx'
                info['baseline_page_order'] = list(page_order)
            if required_baseline is not None:
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
            if required_baseline is not None and baseline not in files:
                raise FidelityError(f'Missing required native baseline: {baseline}')
            if baseline in files:
                if baseline not in records:
                    raise FidelityError(f'Missing successful baseline render: {baseline}')
                if page_order is None:
                    compare_records(records[baseline], reference)
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
    """Render in a fresh directory so stale artifacts cannot satisfy a check."""
    path, root, output = (Path(value).resolve() for value in (path, root, output))
    environment = dict(os.environ, LC_ALL='C')
    with tempfile.TemporaryDirectory(prefix=f'render-{index:03d}-', dir=output) as temporary:
        work = Path(temporary)
        conversion = subprocess.run(
            [office_binary(), f'-env:UserInstallation={(work / "profile").as_uri()}',
             '--headless', '--convert-to', 'pdf', '--outdir', str(work), str(path.resolve())],
            check=True, timeout=60, capture_output=True, env=environment)
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
        if not text.strip():
            raise FidelityError('Rendered fidelity PDF has no extractable text')
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
        for number, ppm in enumerate(pages, 1):
            width, height, pixels = ppm_pixels(ppm.read_bytes())
            png = dest / f'page-{number:04d}.png'
            png.write_bytes(png_bytes(width, height, pixels))
            fingerprint = hashlib.sha256(struct.pack('>II', width, height) + pixels).hexdigest()
            artifacts.append({'page': number, 'width': width, 'height': height,
                              'png': png.relative_to(output).as_posix(),
                              'pixel_sha256': fingerprint})
        shutil.copyfile(pdf, dest / 'document.pdf')
        (dest / 'text.txt').write_text(text, encoding='utf-8')
        return {'file': path.relative_to(root).as_posix(), 'pages': len(artifacts),
                'text': text, 'pixel_sha256': [page['pixel_sha256'] for page in artifacts],
                'pdf': (dest / 'document.pdf').relative_to(output).as_posix(),
                'page_artifacts': artifacts}


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
