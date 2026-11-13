#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Replay sealed path observations and auxiliary controls without converters."""
import argparse
from contextlib import contextmanager
import hashlib
import importlib
import io
import json
from pathlib import Path, PurePosixPath
import subprocess
import sys
import tarfile
import tempfile
from xml.etree import ElementTree as ET
import zipfile

HERE = Path(__file__).resolve().parent
BASE = Path('/workspace/scratch/c1ca2a1344e9')
BASELINE_PIN = 'c05f187b99e46b6d8d1b6aed6610307f33e1725c'
BASELINE_TREE = 'f8dc52c5a9f0f6b7b25e598be2136d6d5d01d420'
OLD_RUNTIME = 'c5ff75e76163d9abbdd44a9f2a7c5ad210929289'
FIXED_PIN = '1b8cc9e28aa9f4da2d0f0fa9318758bce0e923f1'
FIXED_TREE = '8b826eb2239438565faefa718bd42da61107d95e'
SOURCE_INVENTORIES = {'c05f187b99e46b6d8d1b6aed6610307f33e1725c': {'files': 154, 'pathSetSha256': 'a078fc9d486b28c99abe025cefd46d2270b15aa17fdc189a6ff1b7aede2df144'}, '1b8cc9e28aa9f4da2d0f0fa9318758bce0e923f1': {'files': 159, 'pathSetSha256': '4a9817f9682e00b4b1765c6ad05b3910a7c1ae3accd302990bd1afe4a379837e'}}
W = '{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'
REPLAY_FILES = ['verify_path_matrix.py', 'path_matrix.py', 'oracle.py', 'structure.py', 'run.py', 'goldens.py']
REPLAY_DIGESTS = {'tool/fidelity/verify_path_matrix.py': 'f398a8c665e2fcccaf82f0f5fd7679c24f8e58164a54320ae73763d960a29aaf', 'tool/fidelity/path_matrix.py': '79855b1191b770988c0b179b1761793bec9ea21257e4d29785c13a54144515fb', 'tool/fidelity/oracle.py': 'cd089a5b807d90023e582f1e23e9c30581f39736452321886e66e489e0a85395', 'tool/fidelity/structure.py': '39cba5c9e7fe0e94e310cb0d32a6ac96698d618dd7dd02929188795a7f20f729', 'tool/fidelity/run.py': '580b4887e2ea3a9d8a5e9644a06ab1813d5f6f5695dddfed4d52c1eaa2b1bc8c', 'tool/fidelity/goldens.py': '96e40fc84e19232d065615f3699862b0a01fa8fe06de19996b931a542840e3b5'}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def identity(path):
    raw = Path(path).read_bytes()
    return {'bytes': len(raw), 'sha256': sha(raw)}


def read(path):
    return json.loads(Path(path).read_bytes())


def safe_name(name):
    path = PurePosixPath(name)
    return bool(name) and not path.is_absolute() and '..' not in path.parts and '\\' not in name


def unpack(root, name, destination):
    manifest = read(root / (name + '-manifest.json'))
    require(manifest['schema'] == 1 and manifest['archive'] == name + '.tar.xz', 'Archive schema/name')
    packed = (root / manifest['archive']).read_bytes()
    require(len(packed) == manifest['archiveBytes'] and sha(packed) == manifest['archiveSha256'], 'Archive bytes')
    rows = manifest['files']
    inventory = {r['path']: r for r in rows}
    require(len(inventory) == len(rows) == manifest['fileCount'] and manifest['rawBytes'] < 512 * 1024 * 1024,
            'Exact bounded member inventory')
    require(all(safe_name(n) for n in inventory), 'Safe manifest paths')
    files = {}
    with tarfile.open(fileobj=io.BytesIO(packed), mode='r:xz') as tf:
        members = tf.getmembers()
        require(len(members) == len({m.name for m in members}) == len(rows), 'Unique archive members')
        require({m.name for m in members} == set(inventory), 'Complete archive inventory')
        for member in members:
            row = inventory[member.name]
            require(member.isfile() and safe_name(member.name) and member.size == row['bytes'] and
                    oct(member.mode) == row['mode'], 'Safe exact archive entry')
            raw = tf.extractfile(member).read()
            require(len(raw) == row['bytes'] and sha(raw) == row['sha256'], 'Exact retained bytes: ' + member.name)
            files[member.name] = raw
    require(sum(map(len, files.values())) == manifest['rawBytes'], 'Retained byte total')
    for name_, raw in files.items():
        target = destination / name_
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(raw)
    # Executables remain retained as data. Replay never launches them.
    return manifest


def check_sources(folder, expected_pin, expected_tree, repository=None):
    report = read(folder / 'run/report.json')
    source = read(folder / 'source-identities.json')
    require(source['schema'] == 1 and source['commit'] == report['repository']['commit'] == expected_pin and
            source['tree'] == report['repository']['tree'] == expected_tree, 'Measured source identity')
    expected = report['sourceBefore']['files']
    names_digest = sha(json.dumps(sorted(expected), separators=(',', ':')).encode())
    require({'files': len(expected), 'pathSetSha256': names_digest} == SOURCE_INVENTORIES[expected_pin],
            'Complete immutable measured source inventory')
    if repository:
        tracked = subprocess.check_output(['git', 'ls-tree', '-rz', '--name-only', expected_pin], cwd=repository).decode().strip('\0').split('\0')
        selected = {n for n in tracked if n in {'pubspec.yaml', 'tool/fidelity/corpus.json', 'test/fixtures/fidelity/goldens/manifest.json'}
                    or (n.startswith('lib/') and n.endswith('.dart'))
                    or (str(PurePosixPath(n).parent) == 'tool/fidelity' and PurePosixPath(n).suffix in ('.dart', '.py'))}
        selected.update({'.dart_tool/package_config.json', 'pubspec.lock'})
        require(set(expected) == selected, 'Complete Git-derived compiler/harness source contract')
    source_cwd = report['repository'].get('directory', report['commands'][0]['cwd'])
    paths = dict(expected)
    for case in report['cases']:
        relative = Path(case['source']['path']).relative_to(source_cwd).as_posix()
        paths[relative] = case['source']['sha256']
    rows = {r['path']: r for r in source['files']}
    require(len(rows) == len(source['files']) and set(rows) == set(paths) and
            source['measuredSourceFiles'] == len(expected), 'Complete measured source and fixture inventory')
    for name, digest in paths.items():
        row = rows[name]
        raw = (folder / 'source' / name).read_bytes()
        require(safe_name(name) and row['sha256'] == sha(raw) == digest and row['bytes'] == len(raw), 'Source snapshot bytes')
        if name in {'.dart_tool/package_config.json', 'pubspec.lock'}:
            require(row['origin'] == 'retained generated resolution input' and row['gitBlob'] is None,
                    'Explicit generated resolution inputs')
        else:
            blob = hashlib.sha1(b'blob ' + str(len(raw)).encode() + b'\0' + raw).hexdigest()
            require(row['origin'] == 'committed Git object' and row['gitBlob'] == blob, 'Committed source blob identity')
            if repository:
                committed = subprocess.check_output(['git', 'show', expected_pin + ':' + name], cwd=repository)
                require(committed == raw, 'Exact published source bytes')
    for case in report['cases']:
        node = case['nodes']['source']
        relative = Path(case['source']['path']).relative_to(source_cwd)
        raw = (folder / 'source' / relative).read_bytes()
        require(raw == (folder / 'run' / case['id'] / 'source' / Path(node['path']).name).read_bytes(),
                'Original run fixture matches published source')
    if expected_pin == BASELINE_PIN:
        require(source['runtimeUnchangedFrom'] == OLD_RUNTIME, 'Baseline remains old runtime')
        if repository:
            trees = subprocess.check_output(['git', 'rev-parse', BASELINE_PIN + ':lib', OLD_RUNTIME + ':lib'],
                                            cwd=repository, text=True).splitlines()
            require(len(set(trees)) == 1 and trees[0] == source['libraryTree'], 'Original baseline library identity')
    return {'measuredFiles': len(expected), 'retainedSourceAndFixtureFiles': len(rows),
            'generatedResolutionFiles': 2}


@contextmanager
def replay_module(auxiliary, repository=None):
    receipt = read(auxiliary / 'replay-source.json')
    expected = {'tool/fidelity/' + n for n in REPLAY_FILES}
    require(receipt['schema'] == 1 and receipt['commit'] == FIXED_PIN and receipt['tree'] == FIXED_TREE and
            set(receipt['files']) == expected and receipt['files'] == REPLAY_DIGESTS, 'Exact replay source inventory')
    source = auxiliary / 'replay-source'
    for name, digest in receipt['files'].items():
        raw = (source / name).read_bytes()
        require(sha(raw) == digest, 'Immutable replay helper bytes')
        if repository:
            require(subprocess.check_output(['git', 'show', FIXED_PIN + ':' + name], cwd=repository) == raw,
                    'Published replay helper source')
    names = [n[:-3] for n in REPLAY_FILES]
    previous = {n: sys.modules.get(n) for n in names}
    for name in names:
        sys.modules.pop(name, None)
    sys.path.insert(0, str(source / 'tool/fidelity'))
    try:
        yield importlib.import_module('verify_path_matrix')
    finally:
        sys.path.pop(0)
        for name in names:
            sys.modules.pop(name, None)
            if previous[name] is not None:
                sys.modules[name] = previous[name]


def package(path):
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
        require(len(names) == len(set(names)), 'Unique OPC parts')
        return {n: z.read(n) for n in names}


def joins(path):
    parts = package(path)
    notes = ET.fromstring(parts['word/footnotes.xml'])
    doc = ET.fromstring(parts['word/document.xml'])
    by_id = {n.get(W + 'id'): ''.join(t.text or '' for t in n.iter(W + 't')) for n in notes}
    require(len(by_id) == len(notes), 'Unique note IDs')
    return [{'reference': n.get(W + 'id'), 'text': by_id.get(n.get(W + 'id'))}
            for n in doc.iter(W + 'footnoteReference')]


def check_note_order(auxiliary, baseline):
    folder = auxiliary / 'note-order'
    report = read(folder / 'report.json')
    require(report['schema'] == 'note-order-controlled-paths' and report['version'] == 1 and
            report['completed'] is True and report['sourceUnchanged'] is True, 'Completed note experiment')
    contract = ['NOTE-A:α', 'NOTE-B:β']
    require(report['contract'] == contract, 'Original note contract')
    require(report['script'] == identity(auxiliary / 'probe_note_order_paths.py'), 'Note experiment source script')
    baseline_report = read(baseline / 'run/report.json')
    require(report['parser']['sourceCommit'] == BASELINE_PIN and report['parser']['runtimeUnchangedFrom'] == OLD_RUNTIME and
            {k: report['parser'][k] for k in ('bytes', 'sha256')} == identity(baseline / 'run/parser'), 'Note experiment uses old measured parser')
    require(report['native'] == {k: baseline_report['tools']['office'][k] for k in ('path', 'bytes', 'sha256')},
            'Note experiment native executable binding')
    original = folder / 'original/original.docx'
    source_path = 'test/fixtures/fidelity/semantic-contracts/note-joins.docx'
    require(original.read_bytes() == (baseline / 'source' / source_path).read_bytes() and
            {k: report['source'][k] for k in ('bytes', 'sha256')} == identity(original), 'Exact unchanged note source')
    inputs = package(original)
    names = [('original', False, False), ('ids-only', True, False),
             ('order-only', False, True), ('ids-and-order', True, True)]
    require([c['name'] for c in report['cases']] == [n for n, _, _ in names], 'Complete note variant inventory')
    commands = {c['directory']: c for c in report['commands']}
    require(len(commands) == len(report['commands']) == 17, 'Exact note command inventory')
    root = BASE / 'note-order-paths-20261113'
    cwd = str(BASE / 'parser-path-matrix')
    used = set()

    def command(label, argv):
        require(label in commands, 'Required note command')
        row = commands[label]
        require(row['argv'] == [str(a) for a in argv] and row['cwd'] == cwd and
                row['returncode'] == 0 and row['timedOut'] is False, 'Exact successful note command')
        require(read(folder / label / 'command.json') == row, 'Note command/report binding')
        for stream in ('stdout', 'stderr'):
            require(identity(folder / label / stream) == row[stream], 'Note command log binding')
        used.add(label)

    office = report['native']['path']
    command('tools/office', [office, '--version'])
    require((folder / 'tools/office/stdout').read_bytes().decode() == baseline_report['tools']['office']['version'],
            'Same native note experiment version')
    result = {}
    for row, (name, renumber, reorder) in zip(report['cases'], names):
        require(row['renumberedIds'] is renumber and row['reorderedPart'] is reorder, 'Explicit note mutation labels')
        expected_parts = dict(inputs)
        if reorder:
            raw = expected_parts['word/footnotes.xml']
            bstart, astart, end = raw.index(b'<w:footnote w:id="7">'), raw.index(b'<w:footnote w:id="19">'), raw.index(b'</w:footnotes>')
            expected_parts['word/footnotes.xml'] = raw[:bstart] + raw[astart:end] + raw[bstart:astart] + raw[end:]
        if renumber:
            for part in ('word/document.xml', 'word/footnotes.xml'):
                expected_parts[part] = expected_parts[part].replace(b'w:id="19"', b'w:id="1"').replace(b'w:id="7"', b'w:id="2"')
        require(package(folder / name / (name + '.docx')) == expected_parts, 'Exact independent note input mutation')
        paths = {'source': name + '/' + name + '.docx', 'ooxml-resave': name + '/ooxml-resave/' + name + '.docx',
                 'binary': name + '/binary/' + name + '.doc', 'native-import': name + '/native-import/' + name + '.docx',
                 'parser-import': name + '/parser.docx'}
        require(set(row['nodes']) == set(paths), 'Complete note path inventory')
        result[name] = {}
        for role, path in paths.items():
            node = row['nodes'][role]
            require(node['path'] == path and {k: node[k] for k in ('bytes', 'sha256')} == identity(folder / path),
                    'Note artifact exact path and bytes')
            if role == 'binary':
                require((folder / path).read_bytes().startswith(bytes.fromhex('d0cf11e0a1b11ae1')), 'Actual binary note container')
                continue
            actual = joins(folder / path)
            expected_texts = contract if role == 'source' or renumber else list(reversed(contract))
            require(node['joins'] == actual and [j['text'] for j in actual] == expected_texts,
                    'Actual note anchor-to-content ownership')
            correct = [j['text'] for j in actual] == contract
            require(node['contractPreserved'] is correct, 'Note contract outcome')
            result[name][role] = correct
        for role, input_role, kind in [('ooxml-resave', 'source', 'docx:Office Open XML Text'),
                                       ('binary', 'source', 'doc:MS Word 97'),
                                       ('native-import', 'binary', 'docx:Office Open XML Text')]:
            destination = root / name / role
            command(name + '/' + role + '/command', [office, '-env:UserInstallation=' + (destination / 'profile').as_uri(),
                '--headless', '--norestore', '--nodefault', '--convert-to', kind, '--outdir', destination, root / paths[input_role]])
        command(name + '/parser-command', [BASE / 'path-matrix-baseline-c05f187b/parser', root / paths['binary'], root / paths['parser-import']])
    require(used == set(commands), 'Every note command attributed')
    return {'variants': 4, 'commands': 17, 'documents': 20, 'contracts': result,
            'scope': 'Independent input permutations; native OOXML resave already swaps the original nonsequential joins.'}


def check_metadata(auxiliary):
    folder = auxiliary / 'markdown-metadata'
    report = read(folder / 'report.json')
    require(report['schema'] == 'markdown-metadata-projection-controls' and report['version'] == 1,
            'Metadata experiment schema')
    require(report['input'] == {'path': 'metadata.docx', 'sha256': sha((folder / 'metadata.docx').read_bytes())}, 'Metadata input identity')
    parts = package(folder / 'metadata.docx')
    doc = ET.fromstring(parts['word/document.xml'])
    paragraphs = []
    for p in doc.find(W + 'body').findall(W + 'p'):
        style = p.find(W + 'pPr/' + W + 'pStyle')
        paragraphs.append((style.get(W + 'val'), ''.join(t.text or '' for t in p.iter(W + 't'))))
    require(paragraphs == [('Title', 'KEPT-TITLE'), ('Author', 'KEPT-AUTHOR'), ('Normal', 'BODY')], 'Authored metadata paragraph contract')
    styles = ET.fromstring(parts['word/styles.xml'])
    require({s.get(W + 'styleId'): s.find(W + 'name').get(W + 'val') for s in styles} ==
            {'Normal': 'Normal', 'Title': 'Title', 'Author': 'Author'}, 'Authored metadata styles')
    original = read(folder / 'read.stdout')
    expected_meta = {name: {'t': 'MetaInlines', 'c': [{'t': 'Str', 'c': value}]}
                     for name, value in [('author', 'KEPT-AUTHOR'), ('title', 'KEPT-TITLE')]}
    body = [{'t': 'Para', 'c': [{'t': 'Str', 'c': 'BODY'}]}]
    require(original == {'pandoc-api-version': [1, 23, 1], 'meta': expected_meta, 'blocks': body}, 'Actual DOCX metadata reader output')
    root = BASE / 'markdown-metadata-controls-20261113'
    pandoc = '/usr/bin/pandoc'
    argv = [[pandoc, '+RTS', '-N1', '-M256m', '-K32m', '-RTS', '--sandbox', '--from=docx', '--to=json', str(root / 'metadata.docx')]]
    for name in ('body', 'standalone'):
        argv += [[pandoc, '--sandbox', '--from=json', '--to=markdown', '--wrap=none',
                  *(['--standalone'] if name == 'standalone' else []), str(root / 'read.stdout')],
                 [pandoc, '--sandbox', '--from=markdown', '--to=json', str(root / (name + '.md'))]]
    require(len(report['commands']) == 5 and set(report['paths']) == {'body', 'standalone'}, 'Metadata command/path inventory')
    for command, expected in zip(report['commands'], argv):
        require(command['argv'] == expected and command['returncode'] == 0, 'Exact successful metadata command')
    require(read(folder / 'read.command.json') == report['commands'][0] and
            report['commands'][0]['sourceSha256'] == report['input']['sha256'], 'Metadata initial read receipt')
    for index, name in enumerate(('body', 'standalone')):
        reread = read(folder / (name + '.json'))
        expected = {'pandoc-api-version': [1, 23, 1], 'meta': {} if name == 'body' else expected_meta, 'blocks': body}
        require(reread == expected, 'Metadata reread preserves body and measures metadata separately')
        markdown = (folder / (name + '.md')).read_text()
        require(markdown == ('BODY\n' if name == 'body' else '---\nauthor: KEPT-AUTHOR\ntitle: KEPT-TITLE\n---\n\nBODY\n'),
                'Actual ordinary and standalone Markdown bytes')
        require(report['paths'][name] == {'bodyEqual': True, 'metadataEqual': name == 'standalone',
                'originalMetadata': expected_meta, 'rereadMetadata': expected['meta'], 'markdown': markdown}, 'Metadata loss remains explicit')
        for offset, stdout, stderr in [(0, name + '.md', name + '.stderr'), (1, name + '.json', name + '.read.stderr')]:
            row = report['commands'][1 + 2 * index + offset]
            require(row['stdoutSha256'] == sha((folder / stdout).read_bytes()) and
                    row['stderrSha256'] == sha((folder / stderr).read_bytes()), 'Metadata output receipt')
    return {'commands': 5, 'bodyEqualBothPaths': True, 'ordinaryMetadataPreserved': False,
            'standaloneMetadataPreserved': True,
            'scope': 'Prototype command records omit cwd/environment and complete per-command input receipts; outputs and recorded argv are retained.'}


def check_historical_reviews(auxiliary, baseline, replay):
    folder = auxiliary / 'independent-review'
    report_identity = identity(baseline / 'run/report.json')
    outcomes = []
    for suffix, accepted in [('f5afbcb4ddef', True), ('97cdd96b48f3', False)]:
        row = read(folder / ('argv-counterexample-' + suffix + '.json'))
        require(row['measuredRuntime'] == BASELINE_PIN and {k: row['report'][k] for k in ('bytes', 'sha256')} == report_identity,
                'Historical argv review uses original baseline')
        source = folder / ('verify_path_matrix-' + row['source']['sha256'] + '.py')
        require(identity(source) == {k: row['source'][k] for k in ('bytes', 'sha256')} and
                identity(folder / 'argv-counterexample.py') == row['reviewSource'], 'Historical argv review source')
        require(row['outcome']['accepted'] is accepted, 'Historical argv findings remain distinct')
        original, changed = row['originalCommand'], row['substitutedCommand']
        require(original['argv'][0] == '/opt/codex/runtimes/codex-primary-runtime/dependencies/bin/override/soffice' and
                changed == dict(original, argv=['/usr/bin/true', *original['argv'][1:]]), 'Exact historical argv counterexample')
        if not accepted:
            require(row['outcome']['rejection'] == 'Native conversion command', 'Historical argv correction guard')
        outcomes.append(accepted)
    row = read(folder / 'parser-hash-counterexample-review.json')
    require({k: row['report'][k] for k in ('bytes', 'sha256')} == report_identity and
            {k: row['retainedParser'][k] for k in ('bytes', 'sha256')} == identity(baseline / 'run/parser') and
            row['reviewSource'] == identity(folder / 'parser-hash-counterexample.py'), 'Historical parser review inputs')
    require(len(row['replays']) == 2 and [r['outcome']['accepted'] for r in row['replays']] == [True, False],
            'Historical parser findings remain distinct')
    for entry in row['replays']:
        source = folder / ('verify_path_matrix-' + entry['source']['sha256'] + '.py')
        require(identity(source) == {k: entry['source'][k] for k in ('bytes', 'sha256')}, 'Historical parser verifier snapshot')
        before, after = entry['originalParserIdentity'], entry['substitutedParserIdentity']
        require({k: before[k] for k in ('bytes', 'sha256')} == identity(baseline / 'run/parser') and
                after == dict(before, sha256='0' * 64), 'Exact historical parser hash substitution')
    require(row['replays'][1]['outcome']['rejection'] == 'Retained parser executable identity', 'Historical parser correction guard')
    metadata = read(folder / 'metadata-counterexample.json')
    old = read(folder / 'input-ast.json')
    new = read(folder / 'output-ast.json')
    require(metadata['sourceSha256'] == sha((baseline / 'source/tool/fidelity/path_matrix.py').read_bytes()) and
            metadata['returns'] == [0, 0] and metadata['markdown'] == (folder / 'output.md').read_text() == 'BODY\n', 'Original metadata counterexample')
    require(metadata['reportedBodyRoundtrip'] == replay.differences(replay.normalized_ast(old, {}), replay.normalized_ast(new, {})) and
            metadata['reportedBodyRoundtrip']['equal'] is True and
            metadata['unreportedMetadataDifference'] == replay.differences(old['meta'], new['meta']) and
            metadata['unreportedMetadataDifference']['equal'] is False, 'Historical body-equal metadata-loss finding')
    return {'argvBypassBeforeAndAfter': outcomes, 'parserHashBypassBeforeAndAfter': [True, False],
            'bodyEqualityMaskedMetadataLoss': True}


def verify_extracted(folders, repository=None, self_test=False):
    result = {'schema': 1, 'verified': True, 'scope': 'Artifact/source/derived-observation replay; no converter execution or universal fidelity claim.'}
    with replay_module(folders['auxiliary'], repository) as replay:
        for name, pin, tree in [('baseline', BASELINE_PIN, BASELINE_TREE), ('fixed', FIXED_PIN, FIXED_TREE)]:
            if name not in folders:
                continue
            folder = folders[name]
            source = check_sources(folder, pin, tree, repository)
            report = read(folder / 'run/report.json')
            observer_source = folder / ('observer' if name == 'baseline' else 'source/tool/fidelity')
            observer = replay.load_observer(observer_source, report)
            measured = replay.verify(folder / 'run', report, observer)
            measured['sourceSnapshot'] = source
            if name == 'baseline':
                historical = read(folder / 'historical-verification.json')
                require({k: v for k, v in historical.items() if k != 'corruptionControls'} ==
                        {k: v for k, v in measured.items() if k != 'sourceSnapshot'}, 'Original baseline replay outcome')
            if self_test:
                measured['corruptionControls'] = replay.self_test(folder / 'run', observer)
            result[name] = measured
        result['noteOrder'] = check_note_order(folders['auxiliary'], folders['baseline'])
        result['markdownMetadata'] = check_metadata(folders['auxiliary'])
        result['historicalReview'] = check_historical_reviews(folders['auxiliary'], folders['baseline'], replay)
    result['fixedMeasurementIncluded'] = 'fixed' in folders
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository', type=Path, help='Also bind all tracked source bytes to the exact immutable Git objects')
    parser.add_argument('--self-test', action='store_true', help='Replay the retained matrix verifier corruption controls')
    args = parser.parse_args()
    seal = read(HERE / 'seal.json')
    require(seal['schema'] == 1 and seal['baselineCommit'] == BASELINE_PIN and seal['fixedCommit'] == FIXED_PIN, 'Seal source identities')
    expected_archives = ['baseline', 'auxiliary', *(['fixed'] if seal['fixedMeasurementIncluded'] else [])]
    require(seal['archives'] == expected_archives, 'Exact archive scope')
    expected_files = {'README.md', 'build_evidence.py', 'verify.py', 'test_verifier.py'}
    for name in expected_archives:
        expected_files.update({name + '.tar.xz', name + '-manifest.json'})
    require(set(seal['files']) == expected_files, 'Complete helper/archive seal')
    for name, record in seal['files'].items():
        require(identity(HERE / name) == record, 'Sealed file: ' + name)
    with tempfile.TemporaryDirectory(prefix='conversion-path-evidence-') as directory:
        folders, manifests = {}, {}
        for name in expected_archives:
            folders[name] = Path(directory) / name
            manifests[name] = unpack(HERE, name, folders[name])
        result = verify_extracted(folders, args.repository, args.self_test)
        outcome = json.loads(json.dumps(result))
        for name in ('baseline', 'fixed'):
            if name in outcome:
                outcome[name].pop('corruptionControls', None)
        require(outcome == seal['result'], 'Exact sealed replay result')
        result['archives'] = {n: {k: v[k] for k in ('fileCount', 'rawBytes', 'archiveBytes', 'archiveSha256')}
                              for n, v in manifests.items()}
        result['gitChecked'] = args.repository is not None
        print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
