#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Compare native EMF/WMF compound fills with generated SVG previews.

The source has two nested rectangles with the same orientation. Alternate
fill must leave their center white; winding fill must make it black. The
interior samples are authored assertions, not generated raster goldens.
Requires installed LibreOffice, Poppler and PyMuPDF.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess

from oracle import ROOT, digest
from run import command, render


def fill_expectations(mode, samples):
    expected = {'outer': 'black', 'center': 'white' if mode == 'alternate' else 'black'}
    if samples != expected:
        raise ValueError(f'{mode} compound fill differs: expected {expected}, got {samples}')
    return {'passes': True, 'samples': samples}


def color_name(rgb):
    if all(value <= 8 for value in rgb):
        return 'black'
    if all(value >= 247 for value in rgb):
        return 'white'
    raise ValueError('Authored solid interior has an unexpected color: ' + str(rgb))


def page_samples(page, bounds):
    import fitz

    pixmap = page.get_pixmap(matrix=fitz.Matrix(2, 2), colorspace=fitz.csRGB, alpha=False)
    left, top, right, bottom = bounds
    return {name: color_name(pixmap.pixel(round(2 * (left + fraction * (right - left))),
                                          round(top + bottom)))
            for name, fraction in [('outer', 0.125), ('center', 0.5)]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--office', required=True, type=Path)
    parser.add_argument('--dart', default='dart')
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    os.environ.setdefault('TMPDIR', str(output / 'tmp'))
    Path(os.environ['TMPDIR']).mkdir(parents=True, exist_ok=True)
    report = {'schema': 'legacy-doc-parser/metafile-compound-fill', 'version': 1,
              'method': 'Native embedded EMF/WMF and generated SVG against authored interior fill assertions.',
              'cases': {}, 'errors': []}
    try:
        import fitz

        report['renderer'] = command([args.office, '--version']).strip()
        report['pdfSvgInspectorVersion'] = fitz.VersionBind
        report['parserCommit'] = command(['git', 'rev-parse', 'HEAD'], cwd=ROOT).strip()
        report['parserWorktreeDirty'] = bool(command(['git', 'status', '--porcelain'], cwd=ROOT).strip())
        command([args.dart, 'run', 'tool/fidelity/metafile_probe.dart', output / 'inputs'], cwd=ROOT)
        for format_name in ('emf32', 'emf16', 'wmf'):
            for mode in ('alternate', 'winding'):
                name = format_name + '-' + mode
                source = output / 'inputs' / (name + '.docx')
                case = report['cases'][name] = {
                    'sourceMetafileSha256': digest(source.with_suffix('.wmf' if format_name == 'wmf' else '.emf')),
                    'convertedDocxSha256': digest(source),
                    'previewSvgSha256': digest(source.with_suffix('.svg')),
                }
                try:
                    case['nativeRender'] = render(args.office, source, output / name, 72)
                    with fitz.open(output / name / (name + '.pdf')) as document:
                        if len(document) != 1:
                            raise ValueError('Authored metafile probe must render on one page')
                        paths = [path for path in document[0].get_drawings()
                                 if path['fill'] is not None and all(c < 0.01 for c in path['fill'])]
                        if not paths:
                            raise ValueError('Native metafile produced no black vector fill')
                        outer = max(paths, key=lambda path: path['rect'].get_area())['rect']
                        case['native'] = fill_expectations(mode, page_samples(document[0], outer))
                    with fitz.open(source.with_suffix('.svg')) as document:
                        case['preview'] = fill_expectations(mode, page_samples(document[0], [20, 10, 180, 90]))
                    case['sameInteriorColors'] = case['native']['samples'] == case['preview']['samples']
                    case['sourceUnchanged'] = digest(source) == case['convertedDocxSha256']
                    if not case['sourceUnchanged']:
                        raise ValueError('Converted probe changed during native measurement')
                except (ValueError, OSError, RuntimeError, subprocess.TimeoutExpired) as error:
                    case['error'] = str(error)
                    report['errors'].append(name + ': ' + str(error))
    except (ImportError, ValueError, OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        report['errors'].append(str(error))
    finally:
        (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'checks': {name: case.get('sameInteriorColors', False)
                                for name, case in report['cases'].items()},
                      'errors': report['errors']}, indent=2))
    return int(bool(report['errors']))


if __name__ == '__main__':
    raise SystemExit(main())
