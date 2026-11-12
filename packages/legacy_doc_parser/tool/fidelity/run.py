#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Measure real DOC imports against an already installed LibreOffice.

The original OOXML render, its native DOC bridge, our conversion, native
conversion, and successive binary imports are kept separately. Visual changes
on the original-to-binary bridge are measured before parser conversion. A native
DOCX interpretation is not a complete fidelity oracle. Completed stages remain
inspectable if a later stage fails.
"""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import time
import zlib

from oracle import ROOT, bbox_snapshot, compare_semantics, digest, load_corpus, snapshot
from goldens import MANIFEST as GOLDEN_MANIFEST, compare_golden, compare_render, load_goldens


def command(argv, *, timeout=50, cwd=None):
    result = subprocess.run([str(arg) for arg in argv], cwd=cwd, timeout=timeout,
                            capture_output=True, text=True, check=False)
    if result.returncode:
        raise RuntimeError(f'{Path(str(argv[0])).name} exited {result.returncode}: {(result.stderr or result.stdout)[-2400:]}')
    return result.stdout


def office_convert(office, source, target_dir, kind):
    target_dir.mkdir(parents=True, exist_ok=False)
    profile = target_dir / 'profile'
    user = profile / 'user'
    user.mkdir(parents=True)
    # Isolated profile; no macro or document-link update is requested.
    (user / 'registrymodifications.xcu').write_text('''<?xml version="1.0"?>
<oor:items xmlns:oor="http://openoffice.org/2001/registry">
<item oor:path="/org.openoffice.Office.Common/Security/Scripting"><prop oor:name="MacroSecurityLevel" oor:op="fuse"><value>3</value></prop><prop oor:name="DisableMacrosExecution" oor:op="fuse"><value>true</value></prop><prop oor:name="BlockUntrustedRefererLinks" oor:op="fuse"><value>true</value></prop></item>
<item oor:path="/org.openoffice.Office.Writer/Content/Update"><prop oor:name="Link" oor:op="fuse"><value>0</value></prop><prop oor:name="Field" oor:op="fuse"><value>false</value></prop><prop oor:name="Chart" oor:op="fuse"><value>false</value></prop></item>
</oor:items>''')
    conversion = {'doc': 'doc:MS Word 97', 'docx': 'docx:Office Open XML Text',
                  'pdf': 'pdf:writer_pdf_Export'}[kind]
    log = command([office, '-env:UserInstallation=' + profile.as_uri(), '--headless',
                   '--norestore', '--nodefault', '--convert-to', conversion,
                   '--outdir', target_dir, source])
    (target_dir / 'conversion.log').write_text(log)
    output = target_dir / (source.stem + '.' + kind)
    if not output.is_file() or output.stat().st_size == 0:
        raise RuntimeError('Native conversion returned without its output: ' + log[-1200:])
    if kind == 'pdf' and not output.read_bytes().startswith(b'%PDF-'):
        raise RuntimeError('Native PDF output has an invalid signature')
    return output


def stream_hash(stream):
    """Hash large raster streams without holding a whole page in memory."""
    sha256 = hashlib.sha256()
    size = 0
    for chunk in iter(lambda: stream.read(1024 * 1024), b''):
        sha256.update(chunk)
        size += len(chunk)
    return sha256.hexdigest(), size


def gzip_raster(source):
    """Publish a verified gzip, retaining the raw page until its receipt is saved."""
    target = source.with_suffix(source.suffix + '.gz')
    temporary = target.with_suffix(target.suffix + '.tmp')
    if target.exists() or target.is_symlink():
        raise FileExistsError(target)
    with source.open('rb') as raw:
        raw_hash, raw_size = stream_hash(raw)
    if not raw_size:
        raise ValueError('Native raster is empty: ' + source.name)
    # Exclusive creation avoids replacing an earlier recovery artifact. Open it
    # outside the try so a pre-existing temporary file is never removed below.
    stored = temporary.open('xb')
    try:
        with stored:
            # Empty filename and zero mtime make equal PPM bytes reproducible
            # within the same Python/zlib implementation.
            with source.open('rb') as raw, gzip.GzipFile(
                    filename='', mode='wb', fileobj=stored, mtime=0,
                    compresslevel=6) as compressed:
                shutil.copyfileobj(raw, compressed, length=1024 * 1024)
        # Read to EOF: this checks gzip's CRC/size trailer as well as our exact
        # PPM hash, so a completed but damaged archive cannot replace the page.
        with gzip.open(temporary, 'rb') as restored:
            restored_hash, restored_size = stream_hash(restored)
        with source.open('rb') as raw:
            current_hash, current_size = stream_hash(raw)
        if ((restored_hash, restored_size) != (raw_hash, raw_size)
                or (current_hash, current_size) != (raw_hash, raw_size)):
            raise ValueError('Compressed raster does not reproduce unchanged PPM bytes: ' + source.name)
        with temporary.open('rb') as compressed:
            stored_hash, stored_size = stream_hash(compressed)
        # This directory belongs to a new measurement. Refuse collisions rather
        # than overwriting an earlier artifact, including a dangling symlink.
        if target.exists() or target.is_symlink():
            raise FileExistsError(target)
        temporary.replace(target)
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise
    return {'path': target.name, 'compression': 'gzip',
            'sha256': stored_hash, 'sizeBytes': stored_size,
            'uncompressedSha256': raw_hash, 'uncompressedSizeBytes': raw_size}


def compressed_rasters(pdf, output, dpi, page_count):
    """Retain each completed page before creating the next uncompressed page."""
    manifest_path = output / 'raster-manifest.json'
    manifest = {'schema': 'legacy-doc-parser/raster-storage', 'version': 1,
                'storage': 'gzip', 'status': 'running', 'pdfSha256': digest(pdf),
                'rasterDpi': dpi, 'rasterColorSpace': 'RGB',
                'compressionLevel': 6, 'pythonVersion': platform.python_version(),
                'zlibVersion': zlib.ZLIB_RUNTIME_VERSION,
                'expectedPages': page_count, 'pages': []}
    write_json(manifest_path, manifest)
    try:
        info = command(['pdfinfo', pdf])
        info_path = output / 'pdfinfo.txt'
        info_path.write_text(info)
        manifest['pdfInfo'] = {'path': info_path.name, 'sha256': digest(info_path)}
        counts = [line.split(':', 1)[1].strip() for line in info.splitlines()
                  if line.startswith('Pages:')]
        if len(counts) != 1 or not counts[0].isdigit() or int(counts[0]) <= 0:
            raise RuntimeError('Cannot determine native PDF page count')
        manifest['pdfPageCount'] = int(counts[0])
        if manifest['pdfPageCount'] != page_count:
            raise RuntimeError('Native PDF/bbox page count disagrees')
        for index in range(1, page_count + 1):
            manifest['activePage'] = index
            write_json(manifest_path, manifest)
            prefix = output / f'page-{index:04d}'
            raw = prefix.with_suffix('.ppm')
            # Rendering one page bounds uncompressed scratch to one page,
            # including long documents. Pixel format and DPI remain unchanged.
            command(['pdftoppm', '-r', str(dpi), '-f', str(index), '-l', str(index),
                     '-singlefile', pdf, prefix])
            receipt = {'page': index, **gzip_raster(raw)}
            manifest['pages'].append(receipt)
            write_json(manifest_path, manifest)
            # Receipt and independently verified compressed bytes exist first.
            # On a failed write, leave the raw page and previous checkpoint.
            raw.unlink()
        manifest.pop('activePage', None)
        manifest['status'] = 'complete'
    except Exception as error:
        manifest.update(status='error', error=str(error), errorType=type(error).__name__)
        raise
    finally:
        write_json(manifest_path, manifest)
    return manifest['pages'], {'path': manifest_path.name, 'sha256': digest(manifest_path)}


def render(office, source, output, dpi, *, raster_storage='ppm'):
    if raster_storage not in ('ppm', 'gzip'):
        raise ValueError('Unknown raster storage: ' + str(raster_storage))
    pdf = office_convert(office, source, output, 'pdf')
    bbox = output / 'pages.xhtml'
    command(['pdftotext', '-bbox-layout', '-enc', 'UTF-8', pdf, bbox])
    text = command(['pdftotext', '-layout', '-enc', 'UTF-8', pdf, '-'])
    (output / 'pages.txt').write_text(text)
    pages = bbox_snapshot(bbox)
    # RGB detects color changes that can disappear in a luminance-only raster.
    if raster_storage == 'gzip':
        artifacts, manifest = compressed_rasters(pdf, output, dpi, len(pages))
        return {'pdfSha256': digest(pdf), 'pages': pages, 'text': text,
                'rasterSha256': [item['uncompressedSha256'] for item in artifacts],
                'rasterDpi': dpi, 'rasterColorSpace': 'RGB', 'rasterStorage': 'gzip',
                'rasterArtifacts': artifacts, 'rasterManifest': manifest}
    command(['pdftoppm', '-r', str(dpi), pdf, output / 'page'])
    rasters = sorted(output.glob('page-*.ppm'), key=lambda path: int(path.stem.rsplit('-', 1)[-1]))
    if len(pages) != len(rasters):
        raise RuntimeError('Native raster/page count disagrees')
    return {'pdfSha256': digest(pdf), 'pages': pages, 'text': text,
            'rasterSha256': [digest(path) for path in rasters], 'rasterDpi': dpi,
            'rasterColorSpace': 'RGB'}


def render_comparison(reference, actual):
    return compare_render(reference, actual)


def parser_convert(executable, source, destination):
    metadata = command([executable, source, destination], timeout=45)
    return json.loads(metadata)


def write_json(path, value):
    """Leave a complete prior checkpoint even if writing the next one stops."""
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(value, indent=2) + '\n')
    temporary.replace(path)


class StageRecorder:
    def __init__(self, result, path):
        self.result, self.path = result, path

    def __call__(self, name, action):
        entry = {'name': name, 'status': 'running'}
        self.result.setdefault('stages', []).append(entry)
        write_json(self.path, self.result)
        started = time.monotonic()
        try:
            value = action()
            if isinstance(value, Path):
                entry['artifact'] = str(value.relative_to(self.path.parent))
                entry['artifactSha256'] = digest(value)
            entry['status'] = 'complete'
            return value
        except Exception as error:
            entry.update(status='error', error=str(error), errorType=type(error).__name__)
            raise
        finally:
            entry['durationSeconds'] = round(time.monotonic() - started, 2)
            write_json(self.path, self.result)


def source_receipt(root=ROOT):
    """Hash repository build/measurement inputs, including a dirty worktree."""
    paths = [root / name for name in ('pubspec.yaml', 'pubspec.lock',
                                     '.dart_tool/package_config.json')]
    paths += list((root / 'lib').rglob('*.dart'))
    paths += list((root / 'tool/fidelity').glob('*.dart'))
    paths += list((root / 'tool/fidelity').glob('*.py'))
    paths += [root / 'tool/fidelity/corpus.json', root / GOLDEN_MANIFEST]
    files = {path.relative_to(root).as_posix(): digest(path)
             for path in sorted(set(paths)) if path.is_file()}
    encoded = json.dumps(files, sort_keys=True, separators=(',', ':')).encode()
    return {'files': files, 'sha256': hashlib.sha256(encoded).hexdigest(),
            'scope': 'Repository Dart sources, fidelity tools/corpus, dependency lock and package configuration.'}


def tool_receipt(executable, version_arguments=('--version',)):
    resolved = shutil.which(str(executable))
    path = Path(resolved if resolved is not None else executable).resolve()
    result = subprocess.run([str(path), *version_arguments], timeout=50,
                            capture_output=True, text=True, check=False)
    version = '\n'.join(value.strip() for value in (result.stdout, result.stderr) if value.strip())
    if result.returncode or not version:
        raise RuntimeError(f'Cannot record {path.name} version: {version[-1200:]}')
    return {'path': str(path), 'sha256': digest(path), 'version': version}


def requested_roundtrips(args):
    return 0 if args.no_roundtrip else getattr(args, 'roundtrip_cycles', 1)


def unchanged(path, expected):
    try:
        return path is not None and expected is not None and digest(path) == expected
    except OSError:
        return False


def case_has_errors(case):
    cycles = case.get('roundtripCycles', [])
    requested = case.get('roundtripCyclesRequested')
    return (case.get('status') != 'measured' or case.get('sourceUnchanged') is not True
            or case.get('binaryDocUnchanged') is not True
            or case.get('sourceFormat') not in ('doc', 'docx')
            or (case.get('sourceFormat') == 'docx'
                and (not isinstance(case.get('bridgePagination'), dict)
                     or not isinstance(case.get('bridgeChanges'), list)
                     or not case.get('renders', {}).get('original')))
            or (case.get('sourceFormat') == 'doc'
                and (case.get('bridgePagination') is not None or case.get('bridgeChanges') is not None))
            or not isinstance(requested, int) or requested < 0 or requested > 10
            or [cycle.get('index') for cycle in cycles] != list(range(1, requested + 1))
            or any(stage.get('status') != 'complete' for stage in case.get('stages', []))
            or any(cycle.get('status') != 'measured' or cycle.get('inputUnchanged') is not True
                   or cycle.get('binaryDocUnchanged') is not True for cycle in cycles))


def case_is_exact(case):
    """Require every completed comparison, including losses hidden by stability."""
    if case_has_errors(case):
        return False
    if any(case.get(key, {}).get('status') not in ('matched', 'not-recorded')
           for key in ('sourceGolden', 'parserAgainstSourceGolden')):
        return False
    if (case.get('semanticDifferencesFromNativeDoc') != []
            or case.get('bridgeChanges') not in (None, [])
            or (case.get('sourceFormat') == 'docx'
                and case.get('bridgePagination', {}).get('exactOnThisRenderer') is not True)
            or case.get('pagination', {}).get('exactOnThisRenderer') is not True
            or case.get('nativeConversionPagination', {}).get('exactOnThisRenderer') is not True):
        return False
    semantic_keys = ('bridgeChanges', 'semanticDifferencesFromNativeDoc',
                     'semanticDifferencesFromPreviousImport', 'semanticDifferencesFromFirstImport')
    render_keys = ('paginationFromBinaryDoc', 'paginationFromPreviousImport', 'paginationFromFirstImport')
    return all(all(cycle.get(key) == [] for key in semantic_keys)
               and all(cycle.get(key, {}).get('exactOnThisRenderer') is True for key in render_keys)
               for cycle in case.get('roundtripCycles', []))


def measure_case(case, args, executable, output, *, golden_catalog=None, environment=None):
    source = ROOT / case['path']
    source_format = source.suffix.lower().lstrip('.')
    original_hash = None
    result = {'id': case['id'], 'features': case['features'], 'sourceSha256': None,
              'sourceFormat': source_format,
              'rasterStorage': getattr(args, 'raster_storage', 'ppm'),
              'status': 'running', 'roundtripCyclesRequested': requested_roundtrips(args),
              'roundtripCycles': [], 'snapshots': {}, 'renders': {},
              'sourceGolden': {'status': 'not-recorded'},
              'parserAgainstSourceGolden': {'status': 'not-recorded'}}
    result['comparisonAttribution'] = {
        'bridgePagination': ({'referenceRender': 'original', 'actualRender': 'binary',
                              'path': 'Original DOCX -> native DOC bridge, rendered before parser import',
                              'parserInvolved': False}
                             if source_format == 'docx' else None),
        'bridgeChanges': ({'referenceSnapshot': 'original', 'actualSnapshot': 'native',
                           'path': 'Original DOCX -> native DOC -> native DOCX; includes native DOCX export interpretation',
                           'parserInvolved': False}
                          if source_format == 'docx' else None),
        'pagination': {'referenceRender': 'binary', 'actualRender': 'converted',
                       'path': 'Same binary DOC -> parser DOCX, opened by the same native renderer',
                       'parserInvolved': True},
        'nativeConversionPagination': {'referenceRender': 'binary', 'actualRender': 'native',
                                       'path': 'Same binary DOC -> native DOCX export',
                                       'parserInvolved': False},
        'semanticDifferencesFromNativeDoc': {
            'referenceSnapshot': 'native', 'actualSnapshot': 'converted',
            'path': 'Native DOCX and parser DOCX interpretations of the same binary DOC',
            'caveat': 'A difference does not by itself establish parser loss; native DOCX export may discard retained DOC data.',
            'parserInvolved': True},
    }
    started = time.monotonic()
    output.mkdir()
    stage = StageRecorder(result, output / 'result.json')
    bridge = None

    def semantic_snapshot(name, document):
        value = snapshot(document)
        target = output / (name + '-semantic.json')
        write_json(target, value)
        result['snapshots'][name] = {'path': target.name, 'sha256': digest(target),
                                     'documentSha256': digest(document)}
        return value

    def render_snapshot(name, document):
        value = render(args.office, document, output / ('render-' + name), args.dpi,
                       raster_storage=getattr(args, 'raster_storage', 'ppm'))
        target = output / (name + '-render.json')
        write_json(target, value)
        result['renders'][name] = {'path': target.name, 'sha256': digest(target),
                                   'documentSha256': digest(document)}
        return value

    try:
        original_hash = stage('source-receipt', lambda: digest(source))
        result['sourceSha256'] = original_hash
        if original_hash != case['sha256']:
            raise ValueError('Source no longer matches the corpus receipt.')
        if source_format == 'docx':
            original_snapshot = stage('original-semantics', lambda: semantic_snapshot('original', source))
            original_render = stage('original-render', lambda: render_snapshot('original', source))
            bridge = stage('binary-bridge', lambda: office_convert(args.office, source, output / 'bridge', 'doc'))
        else:
            bridge = output / 'source.doc'
            stage('copy-binary-source', lambda: Path(shutil.copyfile(source, bridge)))
            original_snapshot = None
            original_render = None
        result['binaryDocSha256'] = digest(bridge)
        binary_render = stage('binary-render', lambda: render_snapshot('binary', bridge))
        if golden_catalog is not None:
            result['sourceGolden'] = stage('source-golden', lambda: compare_golden(
                case['id'], result['binaryDocSha256'], binary_render,
                environment or {}, golden_catalog))
        result['bridgePagination'] = (render_comparison(original_render, binary_render)
                                      if original_render is not None else None)
        native = stage('native-docx', lambda: office_convert(args.office, bridge, output / 'native-docx', 'docx'))
        native_snapshot = stage('native-semantics', lambda: semantic_snapshot('native', native))
        result['bridgeChanges'] = (compare_semantics(original_snapshot, native_snapshot)
                                   if original_snapshot is not None else None)
        result['nativeDocxSha256'] = digest(native)
        converted = output / 'converted.docx'
        result['converter'] = stage('parser-import', lambda: parser_convert(executable, bridge, converted))
        ours_snapshot = stage('converted-semantics', lambda: semantic_snapshot('converted', converted))
        result['semanticDifferencesFromNativeDoc'] = compare_semantics(native_snapshot, ours_snapshot)
        result['convertedSha256'] = digest(converted)
        converted_render = stage('converted-render', lambda: render_snapshot('converted', converted))
        if golden_catalog is not None:
            result['parserAgainstSourceGolden'] = stage('parser-source-golden', lambda: compare_golden(
                case['id'], result['binaryDocSha256'], converted_render,
                environment or {}, golden_catalog))
        native_render = stage('native-render', lambda: render_snapshot('native', native))
        result['pagination'] = render_comparison(binary_render, converted_render)
        result['nativeConversionPagination'] = render_comparison(binary_render, native_render)
        previous, previous_snapshot, previous_render = converted, ours_snapshot, converted_render
        for index in range(1, result['roundtripCyclesRequested'] + 1):
            prefix = f'roundtrip-{index:02d}'
            directory = output / prefix
            directory.mkdir()
            cycle = {'index': index, 'status': 'running', 'inputSha256': digest(previous)}
            result['roundtripCycles'].append(cycle)
            cycle_binary = None
            try:
                cycle_binary = stage(prefix + '-bridge', lambda: office_convert(
                    args.office, previous, directory / 'binary', 'doc'))
                cycle['binaryDocSha256'] = digest(cycle_binary)
                cycle_native = stage(prefix + '-native-docx', lambda: office_convert(
                    args.office, cycle_binary, directory / 'native-docx', 'docx'))
                cycle_native_snapshot = stage(prefix + '-native-semantics', lambda: semantic_snapshot(
                    prefix + '-native', cycle_native))
                cycle['bridgeChanges'] = compare_semantics(previous_snapshot, cycle_native_snapshot)
                current = directory / 'import.docx'
                cycle['converter'] = stage(prefix + '-parser-import', lambda: parser_convert(
                    executable, cycle_binary, current))
                current_snapshot = stage(prefix + '-converted-semantics', lambda: semantic_snapshot(
                    prefix + '-converted', current))
                cycle['convertedSha256'] = digest(current)
                cycle['semanticDifferencesFromNativeDoc'] = compare_semantics(cycle_native_snapshot, current_snapshot)
                cycle['semanticDifferencesFromPreviousImport'] = compare_semantics(previous_snapshot, current_snapshot)
                cycle['semanticDifferencesFromFirstImport'] = compare_semantics(ours_snapshot, current_snapshot)
                current_binary_render = stage(prefix + '-binary-render', lambda: render_snapshot(
                    prefix + '-binary', cycle_binary))
                current_render = stage(prefix + '-converted-render', lambda: render_snapshot(
                    prefix + '-converted', current))
                cycle['paginationFromBinaryDoc'] = render_comparison(current_binary_render, current_render)
                cycle['paginationFromPreviousImport'] = render_comparison(previous_render, current_render)
                cycle['paginationFromFirstImport'] = render_comparison(converted_render, current_render)
                if index == 1:
                    # Keep the original single-roundtrip report fields available.
                    result['secondConverter'] = cycle['converter']
                    result['roundtripDifferences'] = cycle['semanticDifferencesFromFirstImport']
                cycle['status'] = 'measured'
            except Exception as error:
                cycle.update(status='error', error=str(error), errorType=type(error).__name__)
                raise
            finally:
                cycle['inputUnchanged'] = unchanged(previous, cycle['inputSha256'])
                cycle['binaryDocUnchanged'] = unchanged(cycle_binary, cycle.get('binaryDocSha256'))
                write_json(output / 'result.json', result)
            if not cycle['inputUnchanged'] or not cycle['binaryDocUnchanged']:
                raise ValueError('A roundtrip stage changed its input document.')
            previous, previous_snapshot, previous_render = current, current_snapshot, current_render
        result['status'] = 'measured'
    except Exception as error:
        result['status'] = 'error'
        result['error'] = str(error)
        result['errorType'] = type(error).__name__
    finally:
        result['sourceUnchanged'] = unchanged(source, original_hash)
        result['binaryDocUnchanged'] = unchanged(bridge, result.get('binaryDocSha256'))
        result['durationSeconds'] = round(time.monotonic() - started, 2)
        write_json(output / 'result.json', result)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--office', required=True, type=Path, help='Already installed soffice; nothing is downloaded')
    parser.add_argument('--dart', default='dart')
    parser.add_argument('--output', required=True, type=Path, help='New output directory; existing results are never overwritten')
    parser.add_argument('--case', action='append', default=[])
    parser.add_argument('--dpi', type=int, default=72, choices=(72, 96, 144))
    parser.add_argument('--raster-storage', choices=('ppm', 'gzip'), default='ppm',
                        help='Keep RGB PPM pages (default), or lossless gzip with one raw page at a time')
    parser.add_argument('--no-roundtrip', action='store_true')
    parser.add_argument('--roundtrip-cycles', type=int, default=1, choices=range(0, 11),
                        help='Successive DOCX -> native DOC -> parser imports (default: 1; 0 disables)')
    parser.add_argument('--require-exact', action='store_true', help='Fail on any measured rendering or semantic difference')
    args = parser.parse_args()
    args.output = args.output.resolve()
    args.office = args.office.resolve()
    corpus = load_corpus()
    known = {case['id'] for case in corpus['cases']}
    if set(args.case) - known:
        parser.error('Unknown corpus case: ' + ', '.join(sorted(set(args.case) - known)))
    args.output.mkdir(parents=True, exist_ok=False)
    os.environ.setdefault('TMPDIR', str(args.output / 'tmp'))
    Path(os.environ['TMPDIR']).mkdir(parents=True, exist_ok=True)
    executable = args.output / 'convert'
    try:
        git_head = command(['git', 'rev-parse', 'HEAD'], cwd=ROOT).strip()
        dirty = bool(command(['git', 'status', '--porcelain'], cwd=ROOT).strip())
    except (OSError, RuntimeError, subprocess.TimeoutExpired):
        git_head, dirty = None, None
    report = {'schema': 'legacy-doc-parser/fidelity-report', 'version': 4,
              'status': 'running', 'roundtripCyclesRequested': requested_roundtrips(args),
              'rasterStorage': args.raster_storage,
              'parserCommit': git_head, 'parserWorktreeDirty': dirty,
              'corpusSha256': digest(ROOT / 'tool/fidelity/corpus.json'),
              'method': 'Original DOCX render -> independent native DOC bridge render -> native DOCX and parser DOCX -> successive binary imports. Original-to-binary visual changes measured before parser import; each stage retained; no automatic golden update.',
              'cases': []}
    stage = StageRecorder(report, args.output / 'report.json')
    try:
        report['build'] = {'sources': source_receipt(), 'python': sys.version,
                           'platform': platform.platform()}
        report['build']['compiler'] = stage('compiler-version', lambda: tool_receipt(args.dart))
        report['build']['office'] = stage('office-version', lambda: tool_receipt(args.office))
        report['renderer'] = report['build']['office']['version']
        pdf_tools = ('pdftotext', 'pdftoppm') + (('pdfinfo',) if args.raster_storage == 'gzip' else ())
        for name in pdf_tools:
            report['build'][name] = stage(name + '-version', lambda name=name: tool_receipt(name, ('-v',)))
        golden_catalog = stage('source-golden-integrity', load_goldens)
        report['sourceGoldens'] = {'manifestSha256': digest(ROOT / GOLDEN_MANIFEST),
                                  'cases': sorted(golden_catalog['cases'])}
        argv = [args.dart, 'compile', 'exe', 'tool/fidelity/convert.dart', '-o', executable]
        report['build']['compileCommand'] = [str(value) for value in argv]
        compile_log = stage('compile', lambda: command(argv, cwd=ROOT))
        (args.output / 'compile.log').write_text(compile_log)
        report['build']['executable'] = {'path': executable.name, 'sha256': digest(executable)}
        after = source_receipt()
        report['build']['sourcesUnchangedDuringCompilation'] = after == report['build']['sources']
        if not report['build']['sourcesUnchangedDuringCompilation']:
            report['build']['sourcesAfterCompilation'] = after
            raise ValueError('Build inputs changed during compilation; executable provenance is ambiguous.')
        try:
            fonts = command(['fc-list', '--format', '%{family}|%{style}|%{file}\n'])
            report['fontInventorySha256'] = hashlib.sha256('\n'.join(sorted(fonts.splitlines())).encode()).hexdigest()
            (args.output / 'fonts.txt').write_text(fonts)
            font_paths = {line.rsplit('|', 1)[-1] for line in fonts.splitlines()}
            font_files = {path: digest(Path(path)) for path in sorted(font_paths)}
            report['fontFilesSha256'] = hashlib.sha256(
                json.dumps(font_files, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
            write_json(args.output / 'font-files.json', font_files)
        except (OSError, RuntimeError, subprocess.TimeoutExpired):
            report['fontInventorySha256'] = None
            report['fontFilesSha256'] = None
        report['goldenEnvironment'] = {
            'renderer': report['renderer'],
            'fontInventorySha256': report['fontInventorySha256'],
            'fontFilesSha256': report['fontFilesSha256'],
            'rasterizerVersion': report['build']['pdftoppm']['version'],
            'textExtractorVersion': report['build']['pdftotext']['version'],
        }
    except Exception as error:
        report.update(status='error', error=str(error), errorType=type(error).__name__)
        write_json(args.output / 'report.json', report)
        print(report['error'], flush=True)
        return 1
    for case in corpus['cases']:
        if args.case and case['id'] not in args.case:
            continue
        result = measure_case(case, args, executable, args.output / case['id'],
                              golden_catalog=golden_catalog, environment=report['goldenEnvironment'])
        report['cases'].append(result)
        write_json(args.output / 'report.json', report)
        pagination = result.get('pagination', {})
        bridge_pagination = result.get('bridgePagination')
        bridge_exact = (bridge_pagination.get('exactOnThisRenderer', False)
                        if bridge_pagination is not None else
                        'not-measured' if result.get('sourceFormat') == 'docx' else 'not-applicable')
        print(f"{case['id']}: {result['status']}; original-to-binary exact={bridge_exact}; parser pages {pagination.get('referencePages', '?')} -> {pagination.get('actualPages', '?')}; parser exact={pagination.get('exactOnThisRenderer', False)}", flush=True)
        if result.get('error'):
            print(result['error'], flush=True)
    errors = any(case_has_errors(case) for case in report['cases'])
    if args.require_exact:
        errors |= any(not case_is_exact(case) for case in report['cases'])
    report['status'] = 'error' if errors else 'measured'
    report['exactOnThisRenderer'] = all(case_is_exact(case) for case in report['cases'])
    write_json(args.output / 'report.json', report)
    return int(errors)


if __name__ == '__main__':
    raise SystemExit(main())
