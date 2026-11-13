#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Verify retained independent-reader observations without executing converters."""
import hashlib
import io
import json
from pathlib import Path
import tarfile
import zipfile
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parent
W = '{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'


def require(value, message):
    if not value:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def nodes(value, kind):
    if isinstance(value, dict):
        return int(value.get('t') == kind) + sum(nodes(v, kind) for v in value.values())
    if isinstance(value, list):
        return sum(nodes(v, kind) for v in value)
    return 0


def note_counts(data):
    result = []
    with zipfile.ZipFile(io.BytesIO(data)) as package:
        for kind in ('footnote', 'endnote'):
            name = 'word/' + kind + 's.xml'
            if name not in package.namelist():
                result.append(0)
                continue
            root = ET.fromstring(package.read(name))
            result.append(sum(e.tag == W + kind and e.get(W + 'type', 'normal') == 'normal'
                              for e in root))
    return result


def main():
    manifest = json.loads((ROOT / 'manifest.json').read_bytes())
    archive = (ROOT / 'records.tar.xz').read_bytes()
    require(len(archive) == manifest['archiveBytes'] and sha(archive) == manifest['archiveSha256'],
            'Archive identity')
    with tarfile.open(fileobj=io.BytesIO(archive), mode='r:xz') as tf:
        members = tf.getmembers()
        require(all(m.isfile() for m in members), 'Regular members only')
        require(len({m.name for m in members}) == len(members), 'No duplicate member')
        files = {m.name: tf.extractfile(m).read() for m in members}
    expected = {r['path']: r for r in manifest['files']}
    require(set(files) == set(expected) and len(files) == manifest['fileCount'], 'Exact inventory')
    for path, data in files.items():
        require(len(data) == expected[path]['bytes'] and sha(data) == expected[path]['sha256'], path)
    read = lambda path: json.loads(files[path])
    inputs = read('probe-inputs.json')
    require(inputs['parserCommit'] == 'c5ff75e76163d9abbdd44a9f2a7c5ad210929289', 'Measured parser pin')
    require(inputs['archiveSha256'] == 'a7f916b919a5cce562ece30425472f5f7e8efa25d6a31076228dcb5961b1b626', 'Native source archive')
    require(len(inputs['files']) == 22, 'All selected inputs')
    for entry in inputs['files']:
        require(len(files[entry['path']]) == entry['bytes'] and sha(files[entry['path']]) == entry['sha256'], 'Input ' + entry['path'])
    for path in files:
        if path.startswith('outputs/') and path.endswith('.command.json'):
            r = read(path)
            require(r['inputsBefore'] == r['inputsAfter'] and r['inputsUnchanged'], 'Unchanged input ' + path)
            for name, digest in r['inputsBefore'].items():
                require(sha(files[name]) == digest, 'Exact command input ' + name)
            for stream in ('stdout', 'stderr'):
                out = r[stream]
                require(sha(files[out['path']]) == out['sha256'] and len(files[out['path']]) == out['bytes'], 'Output ' + path)
    pandoc_commands = [p for p in files if p.startswith('outputs-pandoc/') and p.endswith('.command.json')]
    require(len(pandoc_commands) == 36, 'Exact Pandoc execution count')
    for path in pandoc_commands:
        r = read(path)
        require(r['exitCode'] == 0, 'Pandoc exit ' + path)
        require(r['command'][:9] == ['/usr/bin/pandoc', '+RTS', '-N1', '-M256m', '-K32m', '-RTS', '--from=docx', '--to=' + Path(r['output']).suffix[1:].replace('md', 'markdown'), '--wrap=none'], 'Pandoc command ' + path)
        require(r['command'][9] == r['cwd'] + '/' + r['input'], 'Pandoc source argument')
        require(r['inputBeforeSha256'] == r['inputAfterSha256'] == sha(files[r['input']]), 'Pandoc input ' + path)
        require(r['outputSha256'] == sha(files[r['output']]) and r['outputBytes'] == len(files[r['output']]), 'Pandoc output ' + path)
        require(r['stderrSha256'] == sha(files[r['output'] + '.stderr.log']), 'Pandoc stderr ' + path)
    cases = ['word', 'table-borders', 'note-markers', 'bookmarks', 'poi-simple-table2', 'header-textbox-alias']
    for case in cases:
        for mode in ('text', 'docbook'):
            path = 'outputs/' + case + '/antiword-' + mode + '.command.json'
            r = read(path)
            require((r['exitCode'] == 0) == (case != 'header-textbox-alias'), 'Antiword result ' + path)
            options = ['-t', '-w', '0'] if mode == 'text' else ['-x', 'db']
            require(r['command'] == [r['cwd'] + '/antiword-src/antiword', '-m', 'UTF-8.txt', *options, r['cwd'] + '/inputs/' + case + '/source.doc'], 'Antiword argv ' + path)
    for view, count in [('authored', 2), ('libreoffice', 2), ('parser', 0)]:
        require(nodes(read('outputs-pandoc/word/' + view + '.json'), 'Link') == count, 'Link discrimination')
    before = read('outputs-pandoc/note-markers/authored.json')
    after = read('outputs-pandoc/note-markers/authored.roundtrip.json')
    require(before == after, 'Retained equal AST')
    require(note_counts(files['inputs/note-markers/authored.docx']) == [6, 3], 'Authored note types')
    require(note_counts(files['outputs-pandoc/note-markers/authored.roundtrip.docx']) == [9, 0], 'Loss hidden by equal AST')
    source = read('antiword-source.json')
    require(source['commit'] == '82515aad16ceedc1061ae3777acb99c90d3d3e08' and len(source['files']) == 178, 'Antiword source pin')
    for row in source['files']:
        data = files['antiword-source/' + row['path']]
        oid = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
        require(oid == row['gitBlob'], 'Antiword blob ' + row['path'])
    print(json.dumps({'verified': True, 'records': len(files), 'selectedInputs': 22,
                      'antiwordExecutions': 12, 'antiwordSuccesses': 10,
                      'pandocSuccessfulExecutions': 36, 'noteTypeLossDespiteEqualAst': True}, sort_keys=True))


if __name__ == '__main__':
    main()
