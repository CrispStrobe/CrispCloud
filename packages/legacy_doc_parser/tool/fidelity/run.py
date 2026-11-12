#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Measure real DOC imports against an already installed LibreOffice.

The original OOXML, its native DOC bridge, our conversion, native conversion,
and a second DOC import are kept separately. A bridge loss is never attributed
to our parser; a native DOCX round trip is not an exact-pagination oracle.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
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


def measure_case(case, args, executable, output):
    source = ROOT / case['path']
    original_hash = digest(source)
    result = {'id': case['id'], 'features': case['features'], 'sourceSha256': original_hash}
    started = time.monotonic()
    output.mkdir()
    try:
        if source.suffix == '.docx':
            bridge = office_convert(args.office, source, output / 'bridge', 'doc')
            original_snapshot = snapshot(source)
        else:
            bridge = output / 'source.doc'
            shutil.copyfile(source, bridge)
            original_snapshot = None
        result['binaryDocSha256'] = digest(bridge)
        native = office_convert(args.office, bridge, output / 'native-docx', 'docx')
        native_snapshot = snapshot(native)
        result['bridgeChanges'] = (compare_semantics(original_snapshot, native_snapshot)
                                   if original_snapshot is not None else None)
        result['nativeDocxSha256'] = digest(native)
        converted = output / 'converted.docx'
        result['converter'] = parser_convert(executable, bridge, converted)
        ours_snapshot = snapshot(converted)
        result['semanticDifferencesFromNativeDoc'] = compare_semantics(native_snapshot, ours_snapshot)
        result['convertedSha256'] = digest(converted)
        binary_render = render(args.office, bridge, output / 'render-source-doc', args.dpi)
        converted_render = render(args.office, converted, output / 'render-converted', args.dpi)
        native_render = render(args.office, native, output / 'render-native-docx', args.dpi)
        result['pagination'] = render_comparison(binary_render, converted_render)
        result['nativeConversionPagination'] = render_comparison(binary_render, native_render)
        for name, record in [('binary', binary_render), ('converted', converted_render), ('native', native_render)]:
            (output / (name + '-render.json')).write_text(json.dumps(record, indent=2) + '\n')
        if not args.no_roundtrip:
            second_doc = office_convert(args.office, converted, output / 'roundtrip-doc', 'doc')
            second = output / 'second-import.docx'
            result['secondConverter'] = parser_convert(executable, second_doc, second)
            result['roundtripDifferences'] = compare_semantics(ours_snapshot, snapshot(second))
        result['status'] = 'measured'
    except (ValueError, OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        result['status'] = 'error'
        result['error'] = str(error)
    finally:
        result['sourceUnchanged'] = digest(source) == original_hash
        result['durationSeconds'] = round(time.monotonic() - started, 2)
        (output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--office', required=True, type=Path, help='Already installed soffice; nothing is downloaded')
    parser.add_argument('--dart', default='dart')
    parser.add_argument('--output', required=True, type=Path, help='New output directory; existing results are never overwritten')
    parser.add_argument('--case', action='append', default=[])
    parser.add_argument('--dpi', type=int, default=72, choices=(72, 96, 144))
    parser.add_argument('--no-roundtrip', action='store_true')
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
    office_version = command([args.office, '--version']).strip()
    executable = args.output / 'convert'
    compile_log = command([args.dart, 'compile', 'exe', 'tool/fidelity/convert.dart', '-o', executable], cwd=ROOT)
    (args.output / 'compile.log').write_text(compile_log)
    try:
        fonts = command(['fc-list', '--format', '%{family}|%{style}|%{file}\n'])
        font_hash = hashlib.sha256('\n'.join(sorted(fonts.splitlines())).encode()).hexdigest()
        (args.output / 'fonts.txt').write_text(fonts)
    except (OSError, RuntimeError):
        font_hash = None
    try:
        git_head = command(['git', 'rev-parse', 'HEAD'], cwd=ROOT).strip()
        dirty = bool(command(['git', 'status', '--porcelain'], cwd=ROOT).strip())
    except (OSError, RuntimeError):
        git_head, dirty = None, None
    report = {'schema': 'legacy-doc-parser/fidelity-report', 'version': 1,
              'renderer': office_version, 'fontInventorySha256': font_hash,
              'parserCommit': git_head, 'parserWorktreeDirty': dirty,
              'corpusSha256': digest(ROOT / 'tool/fidelity/corpus.json'),
              'method': 'Independent DOC render + native DOCX + parser DOCX + second binary import. No automatic golden update.',
              'cases': []}
    for case in corpus['cases']:
        if args.case and case['id'] not in args.case:
            continue
        result = measure_case(case, args, executable, args.output / case['id'])
        report['cases'].append(result)
        (args.output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
        pagination = result.get('pagination', {})
        print(f"{case['id']}: {result['status']}; pages {pagination.get('referencePages', '?')} -> {pagination.get('actualPages', '?')}; exact={pagination.get('exactOnThisRenderer', False)}", flush=True)
        if result.get('error'):
            print(result['error'], flush=True)
    errors = any(case['status'] != 'measured' or not case['sourceUnchanged'] for case in report['cases'])
    if args.require_exact:
        errors |= any(not case.get('pagination', {}).get('exactOnThisRenderer') or
                      case.get('semanticDifferencesFromNativeDoc') or case.get('roundtripDifferences') for case in report['cases'])
    return int(errors)


if __name__ == '__main__':
    raise SystemExit(main())
