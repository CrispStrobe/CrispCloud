#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Attribute DOC/DOCX conversion and Markdown projection differences.

This is a discovery runner, not a golden updater. A successful process is not
an equality claim. Original inputs, every edge, reader output, and failed
command are retained. LibreOffice paths share one implementation family;
Pandoc's reader and writer also count as one family. Neither is ground truth.
"""
from collections import Counter
from copy import deepcopy
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import posixpath
import re
import shutil
import signal
import subprocess
import time
from urllib.parse import unquote, urlsplit
import xml.etree.ElementTree as ET
import zipfile

from oracle import compare_semantics, snapshot
from run import source_receipt

ROOT = Path(__file__).resolve().parents[2]
W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
REL = 'http://schemas.openxmlformats.org/package/2006/relationships'
MAX_BYTES = 64 * 1024 * 1024
MAX_ENTRIES = 4096
CFB_MAGIC = bytes.fromhex('d0cf11e0a1b11ae1')
PROFILE = '''<?xml version="1.0"?>
<oor:items xmlns:oor="http://openoffice.org/2001/registry">
<item oor:path="/org.openoffice.Office.Common/Security/Scripting"><prop oor:name="MacroSecurityLevel" oor:op="fuse"><value>3</value></prop><prop oor:name="DisableMacrosExecution" oor:op="fuse"><value>true</value></prop><prop oor:name="BlockUntrustedRefererLinks" oor:op="fuse"><value>true</value></prop></item>
<item oor:path="/org.openoffice.Office.Writer/Content/Update"><prop oor:name="Link" oor:op="fuse"><value>0</value></prop><prop oor:name="Field" oor:op="fuse"><value>false</value></prop><prop oor:name="Chart" oor:op="fuse"><value>false</value></prop></item>
</oor:items>'''


def sha(data):
    return hashlib.sha256(data).hexdigest()


def file_record(path):
    data = Path(path).read_bytes()
    return {'sha256': sha(data), 'bytes': len(data)}


def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + '.partial')
    temporary.write_text(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                    indent=2) + '\n', encoding='utf-8')
    temporary.replace(path)


def bounded_xml(data):
    if re.search(br'<!\s*(?:DOCTYPE|ENTITY)', data, re.I):
        raise ValueError('DTD/entity declarations are not allowed')
    root = ET.fromstring(data)
    stack, count = [(root, 1)], 0
    while stack:
        node, depth = stack.pop()
        count += 1
        if count > 250000 or depth > 128:
            raise ValueError('XML structural budget exceeded')
        stack.extend((child, depth + 1) for child in node)
    return root


def package_parts(path):
    path = Path(path)
    if path.stat().st_size > MAX_BYTES:
        raise ValueError('Source exceeds 64 MiB')
    with zipfile.ZipFile(path) as archive:
        infos = archive.infolist()
        names = [i.filename for i in infos]
        if len(infos) > MAX_ENTRIES or len(names) != len(set(names)):
            raise ValueError('Excessive or duplicate package entries')
        if sum(i.file_size for i in infos) > MAX_BYTES:
            raise ValueError('Expanded package exceeds 64 MiB')
        for name in names:
            p = PurePosixPath(name)
            if p.is_absolute() or '..' in p.parts or '\\' in name:
                raise ValueError('Unsafe package member')
        return {i.filename: archive.read(i) for i in infos if not i.is_dir()}


def sniff(path):
    """Check content, never accept an RTF file merely named .doc."""
    path = Path(path)
    if not path.is_file() or not 0 < path.stat().st_size <= MAX_BYTES:
        raise ValueError('Missing, empty or oversized document')
    with path.open('rb') as stream:
        prefix = stream.read(16)
    if prefix.startswith(CFB_MAGIC):
        # The importer must still validate the Word streams and FIB. This only
        # identifies the binary compound container, not every Word version.
        return 'cfb'
    if prefix.lstrip().startswith(b'{\\rtf'):
        return 'rtf'
    if prefix.startswith(b'PK'):
        parts = package_parts(path)
        if '[Content_Types].xml' not in parts or '_rels/.rels' not in parts:
            return 'zip-other'
        main = [n for n in bounded_xml(parts['_rels/.rels'])
                if n.tag == '{' + REL + '}Relationship'
                and n.get('Type', '').endswith('/officeDocument')
                and n.get('TargetMode') != 'External']
        if len(main) != 1:
            return 'zip-other'
        target = posixpath.normpath(unquote(main[0].get('Target', '')).lstrip('/'))
        if target not in parts:
            raise ValueError('Missing main package part')
        if bounded_xml(parts[target]).tag != '{' + W + '}document':
            return 'zip-other'
        types = bounded_xml(parts['[Content_Types].xml'])
        content_types = [n.get('ContentType') for n in types
                         if n.get('PartName') == '/' + target]
        return 'docx' if content_types == ['application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml'] else 'word-zip-other'
    return 'unknown'


def require_format(path, expected):
    actual = sniff(path)
    if actual != expected:
        raise ValueError(f'Expected {expected}, actual content is {actual}')
    return actual


def package_facts(path):
    """A deliberately small, namespace-aware loss lens outside Pandoc's AST.

    Counts are not a complete preservation oracle. The separate XML oracle
    records positions, joins, field instructions and editable structure.
    """
    parts = package_parts(path)
    counts = Counter()
    symbols, field_chunks, external_links = [], [], []
    for name, data in sorted(parts.items()):
        if not name.endswith(('.xml', '.rels')):
            continue
        root = bounded_xml(data)
        for node in root.iter():
            if node.tag.startswith('{' + W + '}'):
                kind = node.tag.rsplit('}', 1)[-1]
                if kind in ('footnote', 'endnote'):
                    if node.get('{' + W + '}type', 'normal') == 'normal':
                        counts[kind] += 1
                elif kind in ('hdr', 'ftr', 'comment', 'txbxContent', 'hyperlink',
                              'footnoteReference', 'endnoteReference', 'bookmarkStart',
                              'fldSimple', 'fldChar', 'sym', 'noBreakHyphen',
                              'softHyphen', 'tab', 'br', 'ins', 'del', 'moveFrom', 'moveTo'):
                    counts[kind] += 1
                if kind == 'sym':
                    symbols.append({k.rsplit('}', 1)[-1]: v for k, v in node.attrib.items()})
                if kind == 'instrText':
                    field_chunks.append(node.text or '')
                if kind == 'fldSimple':
                    field_chunks.append(node.get('{' + W + '}instr', ''))
            elif node.tag == '{' + REL + '}Relationship' and node.get('TargetMode') == 'External':
                external_links.append({'type': node.get('Type'), 'target': node.get('Target')})
    return {'counts': dict(sorted(counts.items())), 'symbols': symbols,
            'fieldInstructionChunks': field_chunks,
            'externalRelationships': sorted(external_links, key=lambda n: (n['type'], n['target']))}


def ast_counts(value):
    result = Counter()
    stack = [value]
    while stack:
        item = stack.pop()
        if isinstance(item, dict):
            if isinstance(item.get('t'), str):
                result[item['t']] += 1
            stack.extend(item.values())
        elif isinstance(item, list):
            stack.extend(item)
    return dict(sorted(result.items()))


def ast_image_parts(document, parts):
    """Resolve only exact, unambiguous embedded targets; never fetch a URL."""
    root_rels = bounded_xml(parts['_rels/.rels'])
    main = next(n.get('Target', '').lstrip('/') for n in root_rels
                if n.get('Type', '').endswith('/officeDocument') and n.get('TargetMode') != 'External')
    bindings = {}
    stack = [document]
    while stack:
        node = stack.pop()
        if isinstance(node, list):
            stack.extend(node)
        elif isinstance(node, dict):
            if node.get('t') == 'Image':
                source = node['c'][-1][0]
                parsed = urlsplit(source)
                candidates = []
                if not parsed.scheme and not parsed.netloc and not parsed.query and not parsed.fragment:
                    relative = unquote(parsed.path)
                    for target in (relative, posixpath.normpath(posixpath.join(posixpath.dirname(main), relative))):
                        if target in parts and target not in candidates:
                            candidates.append(target)
                if len(candidates) == 1:
                    target = candidates[0]
                    bindings[source] = {'part': target, **{'sha256': sha(parts[target]), 'bytes': len(parts[target])}}
                else:
                    bindings[source] = {'unresolved': True, 'candidates': candidates}
            stack.extend(node.values())
    return bindings


def normalized_ast(document, bindings):
    """Keep all AST semantics; replace only resolved image paths with bytes."""
    result = deepcopy(document.get('blocks', []))
    stack = [result]
    while stack:
        node = stack.pop()
        if isinstance(node, list):
            stack.extend(node)
        elif isinstance(node, dict):
            if node.get('t') == 'Image':
                target = node['c'][-1][0]
                if target in bindings and 'sha256' in bindings[target]:
                    node['c'][-1][0] = 'embedded-sha256:' + bindings[target]['sha256']
            stack.extend(node.values())
    return result


def differences(before, after, limit=80):
    """Bounded diagnostics; the count and equality decision are not truncated."""
    found, count = [], 0
    stack = [('$', before, after)]
    while stack:
        path, a, b = stack.pop()
        if not isinstance(a, (dict, list)) and type(a) is type(b) and a == b:
            continue
        if isinstance(a, dict) and isinstance(b, dict):
            for key in sorted(set(a) | set(b), reverse=True):
                if key not in a or key not in b:
                    stack.append((path + '/' + key,
                                  [key in a, a.get(key)], [key in b, b.get(key)]))
                else:
                    stack.append((path + '/' + key, a[key], b[key]))
        elif isinstance(a, list) and isinstance(b, list) and len(a) == len(b):
            stack.extend((path + '/' + str(i), a[i], b[i]) for i in reversed(range(len(a))))
        else:
            count += 1
            if len(found) < limit:
                def concise(value):
                    encoded = json.dumps(value, ensure_ascii=False, sort_keys=True)
                    return value if len(encoded) <= 1000 else {'preview': encoded[:1000], 'jsonSha256': sha(encoded.encode()), 'characters': len(encoded)}
                found.append({'path': path, 'before': concise(a), 'after': concise(b)})
    return {'equal': count == 0, 'count': count, 'truncated': count > len(found), 'differences': found}


class CommandFailure(RuntimeError):
    pass


class Runner:
    def __init__(self, options):
        self.options = options
        # Invocation and receipt identify the same resolved executable; a
        # caller's symlink spelling must not obscure command attribution.
        for name in ('office', 'pandoc', 'dart', 'parser', 'antiword'):
            if getattr(options, name, None) is not None:
                setattr(options, name, Path(getattr(options, name)).resolve())
        self.output = options.output.resolve()
        self.output.mkdir(parents=True, exist_ok=False)
        (self.output / 'tmp').mkdir()
        self.env = dict(os.environ, TMPDIR=str(self.output / 'tmp'), DART_SUPPRESS_ANALYTICS='true')
        if options.antiword_data:
            self.env['ANTIWORDHOME'] = str(options.antiword_data.resolve())
        self.report = {'schema': 'legacy-doc-parser/path-matrix', 'version': 2,
                       'status': 'running', 'comparisonMode': 'discovery; differences are not automatically parser defects',
                       'scope': ['typed OOXML observations', 'Pandoc body AST/Markdown', 'Pandoc metadata before and after Markdown', 'optional Antiword DOC text'],
                       'notMeasured': ['native rendering or Word layout', 'universal reader fidelity', 'Word editing behavior'],
                       'families': {'libreoffice': 'one family for DOC import/export and DOCX resave',
                                    'pandoc': 'one family for DOCX/Markdown readers and writers',
                                    'parser': 'subject legacy-doc-parser', 'antiword': 'independent bounded DOC text reader'},
                       'commands': [], 'cases': [], 'errors': [], 'tools': {},
                       'sourceBefore': source_receipt(ROOT)}
        self.report['repository'] = {
            'directory': str(ROOT),
            'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
            'tree': subprocess.check_output(['git', 'rev-parse', 'HEAD^{tree}'], cwd=ROOT, text=True).strip(),
            'workingTreeStatus': subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True),
        }
        self.checkpoint()

    def checkpoint(self):
        write_json(self.output / 'report.json', self.report)

    def command(self, argv, directory, timeout=60):
        directory = Path(directory)
        directory.mkdir(parents=True, exist_ok=False)
        argv = [str(a) for a in argv]
        record = {'argv': argv, 'cwd': str(ROOT), 'startedUtc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()), 'timeoutSeconds': timeout,
                  'directory': str(directory.relative_to(self.output)), 'status': 'running'}
        self.report['commands'].append(record)
        self.checkpoint()
        started = time.monotonic()
        try:
            process = subprocess.Popen(argv, cwd=ROOT, env=self.env, stdout=subprocess.PIPE,
                                       stderr=subprocess.PIPE, start_new_session=True)
        except OSError as error:
            record.update(status='error', error=str(error), returncode=None,
                          durationSeconds=round(time.monotonic() - started, 3))
            write_json(directory / 'command.json', record)
            self.checkpoint()
            raise CommandFailure(str(error)) from error
        timed_out = False
        try:
            stdout, stderr = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            stdout, stderr = process.communicate()
        (directory / 'stdout').write_bytes(stdout)
        (directory / 'stderr').write_bytes(stderr)
        record.update({'returncode': process.returncode, 'timedOut': timed_out,
                       'durationSeconds': round(time.monotonic() - started, 3),
                       'stdout': {'sha256': sha(stdout), 'bytes': len(stdout)},
                       'stderr': {'sha256': sha(stderr), 'bytes': len(stderr)},
                       'status': 'success' if process.returncode == 0 and not timed_out else 'error'})
        write_json(directory / 'command.json', record)
        self.checkpoint()
        if record['status'] != 'success':
            raise CommandFailure(f'{argv[0]} exited {process.returncode}; timedOut={timed_out}; see {directory}')
        return stdout

    def tools(self):
        for name, path in [('office', self.options.office), ('pandoc', self.options.pandoc), ('dart', self.options.dart), ('antiword', self.options.antiword)]:
            if path is None:
                continue
            path = path.resolve()
            version_args = ['-h'] if name == 'antiword' else ['--version']
            try:
                data = self.command([path, *version_args], self.output / 'tools' / name)
                version = data.decode('utf-8', 'replace')
            except CommandFailure:
                # Antiword's help convention uses a nonzero exit. Preserve it;
                # successful document reads remain separate observations.
                if name != 'antiword':
                    raise
                version = (self.output / 'tools' / name / 'stderr').read_text(errors='replace')
            self.report['tools'][name] = {'path': str(path), **file_record(path), 'version': version[:10000]}
        if self.options.parser:
            self.executable = self.options.parser.resolve()
            self.report['parserIdentity'] = {'mode': 'supplied executable; caller must retain its build receipt', 'path': str(self.executable), **file_record(self.executable)}
        else:
            self.executable = self.output / 'parser'
            self.command([self.options.dart, 'compile', 'exe', 'tool/fidelity/convert.dart', '-o', self.executable], self.output / 'build', timeout=180)
            self.report['parserIdentity'] = {'mode': 'compiled from recorded source', **file_record(self.executable)}
        self.report['sourceAfterBuild'] = source_receipt(ROOT)
        if self.report['sourceAfterBuild'] != self.report['sourceBefore']:
            raise ValueError('Source changed during compilation/setup')
        self.checkpoint()

    def office(self, source, folder, kind):
        folder.mkdir(parents=True, exist_ok=False)
        profile = folder / 'profile'
        (profile / 'user').mkdir(parents=True)
        (profile / 'user' / 'registrymodifications.xcu').write_text(PROFILE)
        conversion = {'cfb': 'doc:MS Word 97', 'docx': 'docx:Office Open XML Text'}[kind]
        self.command([self.options.office, '-env:UserInstallation=' + profile.as_uri(), '--headless', '--norestore', '--nodefault', '--convert-to', conversion, '--outdir', folder, source], folder / 'command')
        return folder / (source.stem + ('.doc' if kind == 'cfb' else '.docx'))

    def project(self, node, folder):
        path = Path(node['path'])
        if node['format'] == 'cfb':
            if self.options.antiword:
                try:
                    text = self.command([self.options.antiword, '-m', 'UTF-8.txt', '-t', '-w', '0', path], folder / 'antiword')
                    node['antiword'] = {'status': 'success', 'text': text.decode('utf-8'), **{'sha256': sha(text)}}
                except Exception as error:
                    node['antiword'] = {'status': 'error', 'error': str(error)}
                    self.report['errors'].append({'node': node['id'], 'reader': 'antiword', 'error': str(error)})
            return
        for key, reader, filename in [('facts', package_facts, 'package-facts.json'),
                                      ('xmlSnapshot', snapshot, 'xml-snapshot.json')]:
            try:
                node[key] = reader(path)
                write_json(folder / filename, node[key])
            except Exception as error:
                node[key] = None
                node[key + 'Error'] = str(error)
                self.report['errors'].append({'node': node['id'], 'reader': key, 'error': str(error)})
        parts = package_parts(path)
        node['pandoc'] = {}
        for view in self.options.track_changes:
            destination = folder / 'pandoc' / view
            try:
                raw = self.command([self.options.pandoc, '+RTS', '-N1', '-M256m', '-K32m', '-RTS', '--sandbox', '--from=docx', '--to=json', '--track-changes=' + view, path], destination / 'read')
                if len(raw) > MAX_BYTES:
                    raise ValueError('Pandoc AST exceeds budget')
                ast = json.loads(raw)
                if not isinstance(ast.get('blocks'), list) or not isinstance(ast.get('meta'), dict):
                    raise ValueError('Pandoc result has no block sequence or metadata map')
                ast_path = destination / 'ast.json'
                write_json(ast_path, ast)
                bindings = ast_image_parts(ast, parts)
                projected = normalized_ast(ast, bindings)
                markdown = self.command([self.options.pandoc, '--sandbox', '--from=json', '--to=markdown', '--wrap=none', ast_path], destination / 'write-markdown')
                (destination / 'output.md').write_bytes(markdown)
                reread_raw = self.command([self.options.pandoc, '--sandbox', '--from=markdown', '--to=json', destination / 'output.md'], destination / 'read-markdown')
                reread = json.loads(reread_raw)
                if not isinstance(reread.get('blocks'), list) or not isinstance(reread.get('meta'), dict):
                    raise ValueError('Markdown reread has no block sequence or metadata map')
                write_json(destination / 'markdown-ast.json', reread)
                md_projection = normalized_ast(reread, bindings)
                node['pandoc'][view] = {'status': 'success', 'apiVersion': ast.get('pandoc-api-version'),
                    'astCounts': ast_counts(ast['blocks']), 'bodyAst': projected,
                    'metadata': ast.get('meta', {}), 'images': bindings,
                    'markdown': markdown.decode('utf-8'), 'markdownSha256': sha(markdown),
                    'markdownRoundtrip': differences(projected, md_projection),
                    'markdownRoundtripScope': 'body AST only; metadata is measured separately',
                    'markdownMetadata': reread['meta'],
                    'markdownMetadataRoundtrip': differences(ast['meta'], reread['meta']),
                    'projectionScope': 'Pandoc body AST; equal AST does not preserve all OOXML stories, note kinds, field semantics or layout'}
            except Exception as error:
                node['pandoc'][view] = {'status': 'error', 'error': str(error)}
                self.report['errors'].append({'node': node['id'], 'reader': 'pandoc/' + view, 'error': str(error)})
            self.checkpoint()

    def add(self, case, identifier, source_id, writer, kind, original=None):
        folder = self.output / case['id'] / identifier
        record = {'id': identifier, 'from': source_id, 'writer': writer, 'expectedFormat': kind, 'status': 'running'}
        case['nodes'][identifier] = record
        self.checkpoint()
        if source_id and case['nodes'].get(source_id, {}).get('status') != 'success':
            record.update(status='blocked', error='Dependency did not complete: ' + source_id)
            self.checkpoint()
            return
        source = Path(original) if original else Path(case['nodes'][source_id]['path'])
        before = file_record(source)
        record['input'] = {'path': str(source), **before}
        try:
            if writer == 'source':
                folder.mkdir(parents=True, exist_ok=False)
                result = folder / source.name
                shutil.copyfile(source, result)
            elif writer == 'libreoffice':
                result = self.office(source, folder, kind)
            elif writer == 'parser':
                folder.mkdir(parents=True, exist_ok=False)
                result = folder / 'parser.docx'
                output = self.command([self.executable, source, result], folder / 'command')
                record['parserResult'] = json.loads(output)
            else:
                raise ValueError('Unknown conversion writer')
            require_format(result, kind)
            if file_record(source) != before:
                raise ValueError('Converter modified its source input')
            record.update(status='success', path=str(result), format=kind, **file_record(result))
            self.project(record, folder)
            if file_record(result) != {key: record[key] for key in ('sha256', 'bytes')}:
                raise ValueError('A reader modified the converted document')
        except Exception as error:
            record.update(status='error', error=str(error))
            self.report['errors'].append({'case': case['id'], 'node': identifier, 'error': str(error)})
        record['inputAfter'] = file_record(source)
        self.checkpoint()

    def compare(self, case, name, before_id, after_id, attribution):
        comparison = {'id': name, 'before': before_id, 'after': after_id, 'attribution': attribution,
                      'classification': 'difference is a candidate requiring source attribution'}
        case['comparisons'].append(comparison)
        before, after = case['nodes'].get(before_id), case['nodes'].get(after_id)
        if not before or not after or before['status'] != 'success' or after['status'] != 'success':
            comparison.update(status='blocked', equal=None)
            return
        comparison['status'] = 'measured'
        if before['format'] == after['format'] == 'docx':
            comparison['packageFacts'] = differences(before['facts'], after['facts']) if before['facts'] is not None and after['facts'] is not None else {'status': 'unavailable', 'equal': None}
            available = before['xmlSnapshot'] is not None and after['xmlSnapshot'] is not None
            comparison['xmlStatus'] = 'measured' if available else 'unavailable'
            comparison['xmlFindings'] = compare_semantics(before['xmlSnapshot'], after['xmlSnapshot']) if available else None
            comparison['pandoc'] = {}
            for view in self.options.track_changes:
                a, b = before['pandoc'][view], after['pandoc'][view]
                if a['status'] == b['status'] == 'success':
                    comparison['pandoc'][view] = {'status': 'measured', 'ast': differences(a['bodyAst'], b['bodyAst']),
                                                 'markdownEqual': a['markdown'] == b['markdown'],
                                                 'metadata': differences(a['metadata'], b['metadata'])}
                else:
                    comparison['pandoc'][view] = {'status': 'unavailable', 'equal': None}
        elif before['format'] == after['format'] == 'cfb' and self.options.antiword:
            a, b = before.get('antiword', {}), after.get('antiword', {})
            comparison['antiword'] = differences(a['text'], b['text']) if a.get('status') == b.get('status') == 'success' else {'equal': None, 'status': 'unavailable'}

    def case(self, source, identifier):
        if not re.fullmatch(r'[a-zA-Z0-9_-]+', identifier):
            raise ValueError('Case IDs must be path-safe')
        if any(c['id'] == identifier for c in self.report['cases']):
            raise ValueError('Duplicate case ID')
        source = source.resolve()
        kind = sniff(source)
        if kind not in ('docx', 'cfb'):
            raise ValueError('Input is not DOCX or a binary compound DOC candidate')
        case = {'id': identifier, 'source': {'path': str(source), **file_record(source)}, 'nodes': {}, 'comparisons': []}
        self.report['cases'].append(case)
        self.add(case, 'source', None, 'source', kind, source)
        if kind == 'docx':
            self.add(case, 'docx-resave', 'source', 'libreoffice', 'docx')
            self.add(case, 'binary', 'source', 'libreoffice', 'cfb')
            binary = 'binary'
        else:
            binary = 'source'
        self.add(case, 'native-docx', binary, 'libreoffice', 'docx')
        self.add(case, 'parser-docx', binary, 'parser', 'docx')
        self.add(case, 'native-to-binary', 'native-docx', 'libreoffice', 'cfb')
        self.add(case, 'parser-to-binary', 'parser-docx', 'libreoffice', 'cfb')
        for prefix in ('native', 'parser'):
            self.add(case, prefix + '-cycle-native', prefix + '-to-binary', 'libreoffice', 'docx')
            self.add(case, prefix + '-cycle-parser', prefix + '-to-binary', 'parser', 'docx')
        self.compare(case, 'same-binary-importers', 'native-docx', 'parser-docx', 'Same DOC; differences can belong to either DOC importer/DOCX writer')
        for prefix in ('native', 'parser'):
            self.compare(case, prefix + '-cycle-importers', prefix + '-cycle-native', prefix + '-cycle-parser', 'Same regenerated DOC; competing import interpretations')
            self.compare(case, prefix + '-cycle-vs-first', prefix + '-docx', prefix + '-cycle-' + ('native' if prefix == 'native' else 'parser'), 'Cumulative DOC export/import cycle, always compared with first DOCX')
            self.compare(case, prefix + '-binary-text', binary, prefix + '-to-binary', 'Independent Antiword text across the binary export path; not layout or complete story equivalence')
        if kind == 'docx':
            for target in ('docx-resave', 'native-docx', 'parser-docx', 'native-cycle-native', 'parser-cycle-parser'):
                self.compare(case, 'original-vs-' + target, 'source', target, 'Original authored DOCX remains the reference; cumulative path loss is not erased by later stability')
            self.compare(case, 'ooxml-vs-binary-bridge', 'docx-resave', 'native-docx', 'LibreOffice OOXML resave versus its additional binary-DOC path')
        if file_record(source) != {k: case['source'][k] for k in ('sha256', 'bytes')}:
            raise ValueError('Original fixture changed')
        for node in case['nodes'].values():
            if node['status'] == 'success' and file_record(node['path']) != {key: node[key] for key in ('sha256', 'bytes')}:
                raise ValueError('Retained intermediate changed: ' + node['id'])
        case['status'] = 'completed' if all(n['status'] == 'success' for n in case['nodes'].values()) else 'incomplete'
        write_json(self.output / identifier / 'case.json', case)
        self.checkpoint()

    def finish(self):
        self.report['sourceAfter'] = source_receipt(ROOT)
        if self.report['sourceBefore'] != self.report['sourceAfter']:
            self.report['errors'].append({'error': 'Repository source or configuration changed during measurement'})
        comparisons = [c for case in self.report['cases'] for c in case['comparisons']]
        projected = [p for c in comparisons for p in c.get('pandoc', {}).values() if p['status'] == 'measured']
        markdown = [p for case in self.report['cases'] for node in case['nodes'].values()
                    for p in node.get('pandoc', {}).values() if p['status'] == 'success']
        self.report['summary'] = {'cases': len(self.report['cases']), 'comparisons': len(comparisons),
            'measuredPandocComparisons': len(projected), 'equalPandocAst': sum(p['ast']['equal'] for p in projected),
            'equalPandocMetadata': sum(p['metadata']['equal'] for p in projected),
            'equalMarkdown': sum(p['markdownEqual'] for p in projected), 'executionErrors': len(self.report['errors']),
            'measuredMarkdownRoundtrips': len(markdown),
            'changedMarkdownBodies': sum(not p['markdownRoundtrip']['equal'] for p in markdown),
            'changedMarkdownMetadata': sum(not p['markdownMetadataRoundtrip']['equal'] for p in markdown),
            'blockedComparisons': sum(c['status'] == 'blocked' for c in comparisons)}
        self.report['status'] = 'completed-with-errors' if self.report['errors'] else 'completed-discovery'
        self.checkpoint()
        return 1 if self.report['errors'] else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--office', type=Path, required=True)
    parser.add_argument('--pandoc', type=Path, required=True)
    compiler = parser.add_mutually_exclusive_group(required=True)
    compiler.add_argument('--dart', type=Path)
    compiler.add_argument('--parser', type=Path)
    parser.add_argument('--antiword', type=Path)
    parser.add_argument('--antiword-data', type=Path)
    parser.add_argument('--track-changes', action='append', choices=['accept', 'reject', 'all'])
    parser.add_argument('--input', type=Path, action='append', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.track_changes = list(dict.fromkeys(args.track_changes or ['accept', 'reject', 'all']))
    runner = Runner(args)
    try:
        runner.tools()
        for index, path in enumerate(args.input):
            runner.case(path, f'{index + 1:02d}-' + re.sub(r'[^a-zA-Z0-9_-]', '-', path.stem))
        return runner.finish()
    except Exception as error:
        runner.report['status'] = 'failed'
        runner.report['errors'].append({'error': str(error)})
        runner.checkpoint()
        raise


if __name__ == '__main__':
    raise SystemExit(main())
