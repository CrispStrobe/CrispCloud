#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Check actual native flow between linked boxes, including a binary DOC bridge.

The fixture contains eight unique markers in one editable story. The check
requires both boxes to contain text, each marker exactly once and in order.
Increasing only the first box's height must pull markers back from the second.
There are no renderer-generated goldens or assumed exact line-break counts.
"""
import argparse
from collections import Counter
import copy
import hashlib
import json
import os
from pathlib import Path
import subprocess

from oracle import ROOT, digest
from run import command, office_convert, parser_convert, render, render_comparison


MARKERS = ['FLOW_' + word for word in (
    'ONE', 'TWO', 'THREE', 'FOUR', 'FIVE', 'SIX', 'SEVEN', 'EIGHT')]


def frame_assignment(pages, first_height):
    if len(pages) != 1:
        raise ValueError('Linked-box probe must render on one page')
    words = [word for word in pages[0]['words'] if word['text'].startswith('FLOW_')]
    if Counter(word['text'] for word in words) != Counter(MARKERS):
        raise ValueError('Linked story lost, added or duplicated marker text')
    frames = [[], []]
    for word in words:
        left, top, right, bottom = word['box']
        frame = 0 if 72 <= left < 216 else 1 if 360 <= left < 504 else None
        if frame is None or right > (216 if frame == 0 else 504):
            raise ValueError('A marker escaped its authored frame horizontally')
        if top < 72 or bottom > 72 + (first_height if frame == 0 else 140):
            raise ValueError('A marker overflowed its authored frame vertically')
        frames[frame].append((top, word['text']))
    frames = [[word for _, word in sorted(frame)] for frame in frames]
    if not all(frames) or frames[0] + frames[1] != MARKERS:
        raise ValueError('Text did not flow in order through both frames')
    return frames


def verify_resize(small, large):
    before, after = frame_assignment(small, 42), frame_assignment(large, 70)
    if len(after[0]) <= len(before[0]):
        raise ValueError('Growing the first frame did not reflow text back into it')
    return {'small': before, 'large': after,
            'movedBack': after[0][len(before[0]):], 'passes': True}


def verify_placement(small, large):
    """Keep the original absolute authored bounds as a separate strict check."""
    return {'small': frame_assignment(small, 42),
            'large': frame_assignment(large, 70), 'passes': True}


def verify_relative_reflow(small, large, reference_small, reference_large):
    """Allow one disclosed common translation, without fixing frame separation.

    A shifted pair can still reflow. Anchor this one translation to FLOW_ONE
    in the independently rendered authored DOCX. Apply the same translation
    to every marker in both variants; independent box or variant shifts must
    not be normalized away. Absolute placement is always checked separately.
    """
    verify_placement(reference_small, reference_large)

    def anchor(pages):
        if len(pages) != 1:
            raise ValueError('Linked-box probe must render on one page')
        words = [word for word in pages[0]['words'] if word['text'].startswith('FLOW_')]
        if Counter(word['text'] for word in words) != Counter(MARKERS):
            raise ValueError('Linked story lost, added or duplicated marker text')
        return next(word['box'][:2] for word in words if word['text'] == MARKERS[0])

    def shift(pages, reference):
        if [page['size'] for page in pages] != [page['size'] for page in reference]:
            raise ValueError('Linked-box probe changed page dimensions')
        return [actual - expected for actual, expected in zip(anchor(pages), anchor(reference))]

    small_shift = shift(small, reference_small)
    large_shift = shift(large, reference_large)
    if any(abs(before - after) > 0.01 for before, after in zip(small_shift, large_shift)):
        raise ValueError('The two resized variants do not share one placement translation')

    def translated(pages):
        result = copy.deepcopy(pages)
        for page in result:
            for word in page['words']:
                word['box'] = [value - small_shift[index % 2]
                               for index, value in enumerate(word['box'])]
        return result

    result = verify_resize(translated(small), translated(large))
    result['translationFromAuthoredDocxPoints'] = small_shift
    result['method'] = 'One common translation only; absolute authored placement is checked separately.'
    return result


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
    report = {'schema': 'legacy-doc-parser/linked-textbox-reflow', 'version': 2,
              'renderer': command([args.office, '--version']).strip(),
              'method': 'Unique-marker positions, resize reflow and binary DOC bridge; no golden updates.',
              'variants': {}, 'checks': {}, 'errors': []}
    try:
        fonts = command(['fc-list', '--format', '%{family}|%{style}|%{file}\n'])
        report['fontInventorySha256'] = hashlib.sha256(
            '\n'.join(sorted(fonts.splitlines())).encode()).hexdigest()
        (output / 'fonts.txt').write_text(fonts)
        report['parserCommit'] = command(['git', 'rev-parse', 'HEAD'], cwd=ROOT).strip()
        report['parserWorktreeDirty'] = bool(command(['git', 'status', '--porcelain'], cwd=ROOT).strip())
        command([args.dart, 'run', 'tool/fidelity/textbox_probe.dart', output / 'inputs'], cwd=ROOT)
        executable = output / 'convert'
        command([args.dart, 'compile', 'exe', 'tool/fidelity/convert.dart', '-o', executable], cwd=ROOT)
        rendered = {name: {} for name in ('direct', 'binary', 'converted')}
        for name in ('small', 'large'):
            directory = output / name
            directory.mkdir()
            source = output / 'inputs' / (name + '.docx')
            before = digest(source)
            record = report['variants'][name] = {'sourceSha256': before}
            rendered['direct'][name] = render(args.office, source, directory / 'direct', 72)
            bridge = office_convert(args.office, source, directory / 'bridge', 'doc')
            record['binarySha256'] = digest(bridge)
            rendered['binary'][name] = render(args.office, bridge, directory / 'binary', 72)
            converted = directory / 'converted.docx'
            record['converter'] = parser_convert(executable, bridge, converted)
            rendered['converted'][name] = render(args.office, converted, directory / 'converted', 72)
            record['bridgePagination'] = render_comparison(rendered['direct'][name], rendered['binary'][name])
            record['parserPagination'] = render_comparison(rendered['binary'][name], rendered['converted'][name])
            record['sourceUnchanged'] = before == digest(source)
            if not record['sourceUnchanged']:
                raise ValueError('Source probe changed during native measurement')
            for route in rendered:
                (directory / (route + '-render.json')).write_text(
                    json.dumps(rendered[route][name], indent=2) + '\n')
        for route, variants in rendered.items():
            checks = report['checks'][route] = {}
            for name, check in (
                ('reflow', lambda: verify_relative_reflow(
                    variants['small']['pages'], variants['large']['pages'],
                    rendered['direct']['small']['pages'], rendered['direct']['large']['pages'])),
                ('placement', lambda: verify_placement(
                    variants['small']['pages'], variants['large']['pages'])),
            ):
                try:
                    checks[name] = check()
                except ValueError as error:
                    checks[name] = {'passes': False, 'error': str(error)}
                    report['errors'].append(route + '/' + name + ': ' + str(error))
            checks['passes'] = all(checks[name]['passes'] for name in ('reflow', 'placement'))
    except (ValueError, OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        report['errors'].append(str(error))
    finally:
        (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'checks': report['checks'], 'errors': report['errors']}, indent=2))
    return int(bool(report['errors']))


if __name__ == '__main__':
    raise SystemExit(main())
