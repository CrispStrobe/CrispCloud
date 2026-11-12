#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Measure real DOC imports against an already installed LibreOffice.

The original OOXML, its native DOC bridge, our conversion, native conversion,
and successive binary imports are kept separately. A bridge loss is never
attributed to our parser; a native DOCX round trip is not an exact-pagination
oracle. Completed stages remain inspectable if a later stage fails.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import time

from oracle import ROOT, bbox_snapshot, compare_layout, compare_semantics, digest, load_corpus, snapshot


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


def render(office, source, output, dpi):
    pdf = office_convert(office, source, output, 'pdf')
    bbox = output / 'pages.xhtml'
    command(['pdftotext', '-bbox-layout', '-enc', 'UTF-8', pdf, bbox])
    text = command(['pdftotext', '-layout', '-enc', 'UTF-8', pdf, '-'])
    (output / 'pages.txt').write_text(text)
    command(['pdftoppm', '-r', str(dpi), '-gray', pdf, output / 'page'])
    rasters = sorted(output.glob('page-*.pgm'), key=lambda path: int(path.stem.rsplit('-', 1)[-1]))
    pages = bbox_snapshot(bbox)
    if len(pages) != len(rasters):
        raise RuntimeError('Native raster/page count disagrees')
    return {'pdfSha256': digest(pdf), 'pages': pages, 'text': text,
            'rasterSha256': [digest(path) for path in rasters], 'rasterDpi': dpi}


def render_comparison(reference, actual):
    result = compare_layout(reference['pages'], actual['pages'])
    result['rasterExactlyMatches'] = reference['rasterSha256'] == actual['rasterSha256']
    result['layoutTextExactlyMatches'] = reference['text'] == actual['text']
    # Exact is intentionally stricter than a subpoint bounding-box tolerance.
    result['exactOnThisRenderer'] = (result['rasterExactlyMatches'] and
                                    result['layoutTextExactlyMatches'] and
                                    result['maximumWordDriftPoints'] == 0 and
                                    result['pageDimensionsMatch'])
    return result


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
    paths.append(root / 'tool/fidelity/corpus.json')
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
            or not isinstance(requested, int) or requested < 0 or requested > 10
            or [cycle.get('index') for cycle in cycles] != list(range(1, requested + 1))
            or any(stage.get('status') != 'complete' for stage in case.get('stages', []))
            or any(cycle.get('status') != 'measured' or cycle.get('inputUnchanged') is not True
                   or cycle.get('binaryDocUnchanged') is not True for cycle in cycles))


def case_is_exact(case):
    """Require every completed comparison, including losses hidden by stability."""
    if case_has_errors(case):
        return False
    if (case.get('semanticDifferencesFromNativeDoc') != []
            or case.get('bridgeChanges') not in (None, [])
            or case.get('pagination', {}).get('exactOnThisRenderer') is not True
            or case.get('nativeConversionPagination', {}).get('exactOnThisRenderer') is not True):
        return False
    semantic_keys = ('bridgeChanges', 'semanticDifferencesFromNativeDoc',
                     'semanticDifferencesFromPreviousImport', 'semanticDifferencesFromFirstImport')
    render_keys = ('paginationFromBinaryDoc', 'paginationFromPreviousImport', 'paginationFromFirstImport')
    return all(all(cycle.get(key) == [] for key in semantic_keys)
               and all(cycle.get(key, {}).get('exactOnThisRenderer') is True for key in render_keys)
               for cycle in case.get('roundtripCycles', []))


def measure_case(case, args, executable, output):
    source = ROOT / case['path']
    original_hash = None
    result = {'id': case['id'], 'features': case['features'], 'sourceSha256': None,
              'status': 'running', 'roundtripCyclesRequested': requested_roundtrips(args),
              'roundtripCycles': [], 'snapshots': {}, 'renders': {}}
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
        value = render(args.office, document, output / ('render-' + name), args.dpi)
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
        if source.suffix == '.docx':
            original_snapshot = stage('original-semantics', lambda: semantic_snapshot('original', source))
            bridge = stage('binary-bridge', lambda: office_convert(args.office, source, output / 'bridge', 'doc'))
        else:
            bridge = output / 'source.doc'
            stage('copy-binary-source', lambda: Path(shutil.copyfile(source, bridge)))
            original_snapshot = None
        result['binaryDocSha256'] = digest(bridge)
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
        binary_render = stage('binary-render', lambda: render_snapshot('binary', bridge))
        converted_render = stage('converted-render', lambda: render_snapshot('converted', converted))
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
    report = {'schema': 'legacy-doc-parser/fidelity-report', 'version': 2,
              'status': 'running', 'roundtripCyclesRequested': requested_roundtrips(args),
              'parserCommit': git_head, 'parserWorktreeDirty': dirty,
              'corpusSha256': digest(ROOT / 'tool/fidelity/corpus.json'),
              'method': 'Independent DOC render + native DOCX + parser DOCX + successive binary imports. Each stage retained; no automatic golden update.',
              'cases': []}
    stage = StageRecorder(report, args.output / 'report.json')
    try:
        report['build'] = {'sources': source_receipt(), 'python': sys.version,
                           'platform': platform.platform()}
        report['build']['compiler'] = stage('compiler-version', lambda: tool_receipt(args.dart))
        report['build']['office'] = stage('office-version', lambda: tool_receipt(args.office))
        report['renderer'] = report['build']['office']['version']
        for name in ('pdftotext', 'pdftoppm'):
            report['build'][name] = stage(name + '-version', lambda name=name: tool_receipt(name, ('-v',)))
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
        except (OSError, RuntimeError, subprocess.TimeoutExpired):
            report['fontInventorySha256'] = None
    except Exception as error:
        report.update(status='error', error=str(error), errorType=type(error).__name__)
        write_json(args.output / 'report.json', report)
        print(report['error'], flush=True)
        return 1
    for case in corpus['cases']:
        if args.case and case['id'] not in args.case:
            continue
        result = measure_case(case, args, executable, args.output / case['id'])
        report['cases'].append(result)
        write_json(args.output / 'report.json', report)
        pagination = result.get('pagination', {})
        print(f"{case['id']}: {result['status']}; pages {pagination.get('referencePages', '?')} -> {pagination.get('actualPages', '?')}; exact={pagination.get('exactOnThisRenderer', False)}", flush=True)
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
