#!/usr/bin/env python3
"""Independent ZIP/XML oracle for the native last-paragraph comment join.

Expected values are authored in comment_threads_expected.json. No Quds model,
serializer, generated hash, or producer snapshot supplies the expected mapping.
"""
import argparse
import json
from pathlib import Path
import posixpath
import re
import xml.etree.ElementTree as ET
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / 'test/fixtures/fidelity'
W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
W14 = 'http://schemas.microsoft.com/office/word/2010/wordml'
W15 = 'http://schemas.microsoft.com/office/word/2012/wordml'
REL = 'http://schemas.openxmlformats.org/package/2006/relationships'
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
EXT_REL = 'http://schemas.microsoft.com/office/2011/relationships/commentsExtended'
CT = 'http://schemas.openxmlformats.org/package/2006/content-types'
NS = {'w': W, 'w14': W14, 'w15': W15}


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def inspect_package(path):
    with ZipFile(path) as package:
        names = package.namelist()
        require(len(names) == len(set(names)), 'Duplicate ZIP names')

        def xml(part):
            require(part.lstrip('/') in names, f'Missing package part: {part}')
            return ET.fromstring(package.read(part.lstrip('/')))

        def related(owner, kind):
            rels = '/_rels/.rels' if owner == '/' else posixpath.join(
                posixpath.dirname(owner), '_rels', posixpath.basename(owner) + '.rels')
            matches = [rel for rel in xml(rels) if rel.get('Type') == kind]
            require(len(matches) == 1, f'Expected one {kind} relationship on {owner}')
            relation = matches[0]
            require(relation.get('TargetMode') != 'External', 'Native comment parts must be internal')
            target = relation.get('Target', '')
            require(bool(target), 'Empty relationship target')
            return posixpath.normpath(posixpath.join(posixpath.dirname(owner), target))

        main = related('/', R + '/officeDocument')
        comments_part = related(main, R + '/comments')
        extended_part = related(main, EXT_REL)
        main_rels = posixpath.join(posixpath.dirname(main), '_rels', posixpath.basename(main) + '.rels')
        require(not any(rel.get('Type') == R + '/styles' for rel in xml(main_rels)),
                'Unreferenced style defaults were added to the styles-less input')
        body = xml(main).find('w:body', NS)
        require(body is not None, 'Missing Word body')
        for paragraph in body.findall('w:p', NS):
            properties = paragraph.find('w:pPr', NS)
            require(properties is None or len(properties) == 0,
                    'Unrelated body paragraph formatting was introduced')
            for run in paragraph.findall('w:r', NS):
                properties = run.find('w:rPr', NS)
                require(properties is None or len(properties) == 0,
                        'Unrelated body run formatting was introduced')
        overrides = {node.get('PartName'): node.get('ContentType')
                     for node in xml('/[Content_Types].xml') if node.tag == '{' + CT + '}Override'}
        require(overrides.get(comments_part) ==
                'application/vnd.openxmlformats-officedocument.wordprocessingml.comments+xml',
                'Incorrect comments content type')
        # Fixed native MIME from Open XML SDK's independently maintained part
        # declaration: data/parts/WordprocessingCommentsExPart.json (v3.3.0).
        require(overrides.get(extended_part) ==
                'application/vnd.openxmlformats-officedocument.wordprocessingml.commentsExtended+xml',
                'Incorrect commentsExtended content type')
        comments = xml(comments_part)
        require(comments.tag == '{' + W + '}comments', 'Incorrect comments root')
        by_anchor, rows = {}, {}
        bold_reply = False
        for comment in comments.findall('w:comment', NS):
            identifier = int(comment.attrib['{' + W + '}id'])
            require(identifier not in rows, 'Duplicate comment IDs')
            paragraphs = list(comment.iter('{' + W + '}p'))
            require(bool(paragraphs), f'Comment {identifier} has no paragraph')
            anchor = paragraphs[-1].get('{' + W14 + '}paraId', '').upper()
            require(re.fullmatch(r'[0-9A-F]{8}', anchor) is not None,
                    f'Comment {identifier} has no valid last-paragraph anchor')
            require(anchor not in by_anchor, 'Duplicate last-paragraph anchors')
            by_anchor[anchor] = identifier
            rows[identifier] = {
                'id': identifier, 'paragraph_id': anchor, 'parent_id': None, 'resolved': False,
                'author': comment.get('{' + W + '}author', ''),
                'text': '\n'.join(''.join(t.text or '' for t in p.iter('{' + W + '}t'))
                                  for p in paragraphs),
            }
            if identifier == 7:
                for run in comment.iter('{' + W + '}r'):
                    bold = run.find('w:rPr/w:b', NS)
                    if (bold is not None and bold.get('{' + W + '}val', '1') in ('1', 'true', 'on')
                            and ''.join(t.text or '' for t in run.iter('{' + W + '}t'))
                            == 'Reply arrived first'):
                        bold_reply = True
        require(bool(rows), 'No comments to validate')
        require(bold_reply, 'Reply run bold formatting was lost')
        extensions = xml(extended_part)
        require(extensions.tag == '{' + W15 + '}commentsEx', 'Incorrect commentsExtended root')
        joined = set()
        for extension in extensions.findall('w15:commentEx', NS):
            anchor = extension.get('{' + W15 + '}paraId', '').upper()
            require(anchor in by_anchor, f'Extension anchor does not join a final paragraph: {anchor}')
            require(anchor not in joined, 'Duplicate commentEx anchor')
            joined.add(anchor)
            row = rows[by_anchor[anchor]]
            parent = extension.get('{' + W15 + '}paraIdParent')
            if parent is not None:
                parent = parent.upper()
                require(parent in by_anchor, f'Parent anchor does not join a final paragraph: {parent}')
                row['parent_id'] = by_anchor[parent]
            done = extension.get('{' + W15 + '}done', '0').lower()
            require(done in ('0', '1', 'true', 'false', 'on', 'off'), 'Invalid done flag')
            row['resolved'] = done in ('1', 'true', 'on')
        require(joined == set(by_anchor), 'Missing commentEx metadata for a comment')
        for identifier in rows:
            seen = set()
            current = identifier
            while current is not None:
                require(current not in seen, 'Cyclic comment parent graph')
                seen.add(current)
                current = rows[current]['parent_id']
        return {'main_part': main, 'comments_part': comments_part, 'extended_part': extended_part,
                'comments': [rows[key] for key in sorted(rows)]}


def verify_file(path, expected, mode):
    actual = inspect_package(path)
    for key in ('main_part', 'comments_part', 'extended_part'):
        require(actual[key] == expected[key], f'{path.name}: relocated owning part changed: {key}')
    require(actual['comments'] == expected[mode],
            f'{path.name}: comment mapping/state/text differs\n'
            + json.dumps({'actual': actual['comments'], 'expected': expected[mode]}, indent=2))


def verify_corpus(directory, expected):
    names = {f'threads-{mode}-{cycle}.docx' for mode in ('imported', 'edited') for cycle in (1, 2, 3)}
    names.add('threads-source.docx')
    actual = {path.name for path in directory.glob('*.docx')}
    require(actual == names, f'Comment corpus inventory: missing={sorted(names - actual)}, extra={sorted(actual - names)}')
    source = directory / 'threads-source.docx'
    require(source.read_bytes() == (FIXTURES / 'comment-threads.docx').read_bytes(),
            'Authored comment source was modified instead of copied exactly')
    verify_file(source, expected, 'imported')
    for mode in ('imported', 'edited'):
        for cycle in (1, 2, 3):
            verify_file(directory / f'threads-{mode}-{cycle}.docx', expected, mode)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path, nargs='?', default=ROOT / 'build/fidelity-comment-threads')
    args = parser.parse_args(argv)
    expected = json.loads((FIXTURES / 'comment_threads_expected.json').read_text())
    verify_file(FIXTURES / 'comment-threads.docx', expected, 'imported')
    verify_corpus(args.directory, expected)
    print('Comment thread oracle: authored source copy and all 6 import/edit cycle exports passed')


if __name__ == '__main__':
    main()
