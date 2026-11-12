#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Reproduce the narrowly attributed review losses in sealed checkpoint 8060ac1."""
import argparse
from collections import Counter
import hashlib
import json
import lzma
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
ARCHIVE_SHA = '093d6652f07b71435d3898808b85c8c0fd0ac71ff3c5dc6c6c359fcdcc64b731'
REPORT_SHA = 'f25907c90cdfa8985fa45a585a4620ea6580f07244e395da76d8320ecb82fbc7'
SEALED_COMMIT = '8060ac13317754819ebec82ec7232ba6304cb038'
NAMES = ('word-compatibility', 'comment-threads')


def digest(data):
    return hashlib.sha256(data).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def checked(path, expected):
    data = path.read_bytes()
    require(digest(data) == expected, f'Input hash mismatch: {path}')
    return data


def difference(case, field, prop):
    found = [d for d in case[field] or [] if d['property'] == prop]
    require(len(found) == 1, f'Expected one {field}/{prop} difference.')
    return found[0]


def items(value):
    return [item for story in value for item in story['items']]


def audit(report_path, native_run, dart):
    raw_report = lzma.decompress(checked(report_path, ARCHIVE_SHA))
    require(digest(raw_report) == REPORT_SHA, 'Uncompressed report hash mismatch.')
    report = json.loads(raw_report)
    require(report['parserCommit'] == SEALED_COMMIT, 'Wrong sealed parser commit.')
    selected = {case['id']: case for case in report['cases'] if case['id'] in NAMES}
    raw_docs = {}
    for name in NAMES:
        case = selected[name]
        base = native_run / name
        raw_docs[name] = checked(base / 'bridge' / f'{name}.doc', case['binaryDocSha256'])
        checked(base / 'native-docx' / f'{name}.docx', case['nativeDocxSha256'])
        checked(base / 'converted.docx', case['convertedSha256'])
        for snapshot in case['snapshots'].values():
            checked(base / snapshot['path'], snapshot['sha256'])

    files = sorted([*ROOT.joinpath('lib').rglob('*.dart'),
                    ROOT / 'pubspec.yaml', ROOT / 'pubspec.lock',
                    Path(__file__).resolve(), Path(__file__).with_suffix('.dart')])
    source_hashes = {str(path.relative_to(ROOT)): digest(path.read_bytes()) for path in files}
    source_identity = digest(json.dumps(source_hashes, sort_keys=True, separators=(',', ':')).encode())
    observation = json.loads(subprocess.check_output(
        [dart, 'run', 'tool/fidelity/review_loss_audit.dart', str(native_run)], cwd=ROOT))
    require(source_hashes == {str(path.relative_to(ROOT)): digest(path.read_bytes()) for path in files},
            'Audit source changed during the probe.')

    word = selected['word-compatibility']
    change = difference(word, 'bridgeChanges', 'revisions')
    old_revisions = items(change['reference'])
    require(len(old_revisions) == 1 and old_revisions[0]['kind'] == 'sectPrChange'
            and not change['actual'], 'Unexpected section-review bridge result.')
    require(not any(d['property'] == 'revisions' for d in word['semanticDifferencesFromNativeDoc']),
            'Unexpected parser section-review difference.')
    for name in NAMES:
        raw = observation['binary'][name]
        require(raw['piecePropertyRecords'] == 0 and raw['piecePrms'] == [0],
                'A piece property could carry additional review history.')
    word_raw = observation['binary']['word-compatibility']
    require(not {'3239', 'd243'} & {op for section in word_raw['sectionPropertyCodes'] for op in section},
            'Binary section history exists and needs separate analysis.')
    for encoding in ('ascii', 'utf-16le'):
        require('Independent Fixture'.encode(encoding) not in raw_docs['word-compatibility'],
                'Source section-review author survived in the binary.')
        require('Reply arrived first'.encode(encoding) not in raw_docs['comment-threads'],
                'Reply text survived in the binary.')

    comments = selected['comment-threads']
    bridge = difference(comments, 'bridgeChanges', 'comments')
    parser = difference(comments, 'semanticDifferencesFromNativeDoc', 'comments')
    original, native, converted = items(bridge['reference']), items(bridge['actual']), items(parser['actual'])
    require(len(original) == 3 and len(native) == len(converted) == 2,
            'Unexpected comment counts.')
    require(original[0]['text'] == 'Reply arrived first' and original[0]['parent'] == 1
            and original[1]['done'] is True and not native[0]['done'],
            'Unexpected source thread or resolved state.')
    require(native == items(parser['reference']), 'Native comparison stages disagree.')
    date_changes = []
    for before, after in zip(native, converted):
        require({k: v for k, v in before.items() if k != 'date'} ==
                {k: v for k, v in after.items() if k != 'date'},
                'Parser changed comment content or relationships.')
        if before['date'] != after['date']:
            require(before['date'] == after['date'] + 'Z', 'Comment wall-clock date changed.')
            date_changes.append({'native': before['date'], 'parser': after['date']})
    comment_raw = observation['binary']['comment-threads']
    require(comment_raw['commentReferenceCount'] == 2
            and comment_raw['extendedCommentRecords'] == [
                {'rawDate': 2816545344, 'depth': 0, 'parent': 0, 'flags': 0},
                {'rawDate': 0, 'depth': 0, 'parent': 0, 'flags': 0}],
            'Unexpected binary comment records.')

    cycles = {}
    for name in NAMES:
        case_cycles = selected[name]['roundtripCycles']
        require(len(case_cycles) == 3, 'Audit requires all three recorded cycles.')
        for cycle in case_cycles:
            require(cycle['status'] == 'measured' and not any(
                d['property'] in ('comments', 'revisions')
                for d in cycle['semanticDifferencesFromPreviousImport']),
                'A later cycle introduced a comment/revision difference.')
        cycles[name] = {'completed': 3, 'additionalCommentOrRevisionDifferences': 0}
    expected_parts = Counter({('word/document.xml', 'ins'): 3,
                              ('word/header1.xml', 'trPrChange'): 1,
                              ('word/header1.xml', 'ins'): 1,
                              ('word/footnotes.xml', 'trPrChange'): 1,
                              ('word/footnotes.xml', 'ins'): 1,
                              ('word/comments.xml', 'trPrChange'): 1,
                              ('word/comments.xml', 'ins'): 1})
    records = observation['revisionIds']
    require(Counter((r['part'], r['kind']) for r in records) == expected_parts,
            'Revision-ID probe lost a story or revision kind.')
    require(len({r['id'] for r in records}) == 9, 'Revision identifiers are not unique.')
    return {
        'schema': 'legacy-doc-parser/review-loss-audit', 'version': 1,
        'sealedCheckpoint': {'parserCommit': SEALED_COMMIT,
                             'archiveSha256': ARCHIVE_SHA, 'reportSha256': REPORT_SHA},
        'documentHashes': {name: {key: selected[name][key] for key in (
            'sourceSha256', 'binaryDocSha256', 'nativeDocxSha256', 'convertedSha256')}
            for name in NAMES},
        'binaryObservations': observation['binary'],
        'attribution': {
            'word-compatibility': {'classification': 'native-docx-to-doc-bridge-loss',
                                   'originalSectionRevision': old_revisions[0],
                                   'nativeAndParserSectionRevisions': 0,
                                   'sectionReviewAuthorAbsentAsciiAndUtf16': True},
            'comment-threads': {'classification': 'native-docx-to-doc-bridge-loss',
                                'originalComments': original, 'nativeComments': native,
                                'parserCommentsEqualExceptDateZone': True,
                                'replyTextAbsentAsciiAndUtf16': True,
                                'dateDifferences': date_changes,
                                'dateInterpretation': 'DTTM has no stored time-zone offset.'}},
        'recordedCycles': cycles,
        'crossStoryRevisionIds': {'purpose': 'Identifier allocation only; not native review semantics.',
                                 'records': records, 'unique': True,
                                 'sourceCommit': subprocess.check_output(
                                     ['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                                 'sourceWorktreeDirty': bool(subprocess.check_output(
                                     ['git', 'status', '--porcelain'], cwd=ROOT, text=True).strip()),
                                 'sourceManifestSha256': source_identity,
                                 'sourceFileCount': len(source_hashes),
                                 'sourceFiles': source_hashes,
                                 'dartVersion': subprocess.check_output([dart, '--version'], text=True).strip(),
                                 'sourceUnchangedDuringProbe': True},
        'limits': ['No renderer was rerun for this audit.',
                   'The ID probe uses the separately identified current source, not sealed 8060ac1.',
                   'Raw binary inspection is restricted to these hash-pinned fixture layouts.',
                   'No resolved-state bit, ink strokes, move identity, or full review semantics are inferred.'],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', required=True, type=Path)
    parser.add_argument('--native-run', required=True, type=Path)
    parser.add_argument('--dart', default='dart')
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    require(not args.output.exists(), 'Refusing to overwrite an existing audit receipt.')
    result = audit(args.report.resolve(), args.native_run.resolve(), args.dart)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('x') as output:
        output.write(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'status': 'passed', 'attributedCases': 2, 'uniqueRevisionIds': 9}))


if __name__ == '__main__':
    main()
