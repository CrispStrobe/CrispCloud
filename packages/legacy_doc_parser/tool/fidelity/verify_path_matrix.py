#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Replay a retained path-matrix report without invoking any document tool.

This checks artifact/command bindings and recomputes derived observations. It is
an integrity verifier, not another independent DOC decoder or fidelity vote.
Version-1 Markdown metadata omissions are reported as a separate replay result;
the original report and its measured source identity are never rewritten.
"""
import argparse
from copy import deepcopy
import importlib.util
import json
from pathlib import Path
import re
import sys
from types import SimpleNamespace

from path_matrix import (Runner, ast_counts, ast_image_parts, differences,
                         file_record, normalized_ast, package_facts,
                         package_parts, require_format, sha)
from oracle import snapshot


def require(value, message):
    if not value:
        raise ValueError(message)


def read(path):
    return json.loads(path.read_bytes())


def load_observer(source, report):
    """Use the exact retained XML observer when its schema has since changed."""
    source = Path(source)
    for name in ('oracle.py', 'structure.py'):
        require(sha((source / name).read_bytes()) == report['sourceBefore']['files']['tool/fidelity/' + name],
                'Retained observer source identity: ' + name)

    def load(name):
        specification = importlib.util.spec_from_file_location('_matrix_retained_' + name, source / (name + '.py'))
        module = importlib.util.module_from_spec(specification)
        specification.loader.exec_module(module)
        return module

    previous = sys.modules.get('structure')
    try:
        sys.modules['structure'] = load('structure')
        return load('oracle')
    finally:
        if previous is None:
            sys.modules.pop('structure', None)
        else:
            sys.modules['structure'] = previous


def verify(directory, report=None, observer=None):
    directory = Path(directory).resolve()
    report = read(directory / 'report.json') if report is None else report
    require(report['schema'] == 'legacy-doc-parser/path-matrix'
            and report['version'] in (1, 2), 'Report schema/version')
    require(report['sourceBefore'] == report['sourceAfterBuild'] == report['sourceAfter'],
            'Measured source changed')
    encoded_sources = json.dumps(report['sourceBefore']['files'], sort_keys=True, separators=(',', ':')).encode()
    require(report['sourceBefore']['sha256'] == sha(encoded_sources), 'Source manifest digest')
    require(report['repository']['workingTreeStatus'] == '', 'Measurement was not a clean checkpoint')
    require(bool(report['cases']), 'Empty matrix')
    first = report['cases'][0]
    origin = Path(first['nodes']['source']['path']).parent.parent.parent
    commands = {}
    source_cwd = report['repository'].get('directory', report['commands'][0]['cwd'])
    for command in report['commands']:
        relative = Path(command['directory'])
        require(not relative.is_absolute() and '..' not in relative.parts,
                'Unsafe command directory')
        require(str(relative) not in commands, 'Duplicate command directory')
        commands[str(relative)] = command
        require(command['cwd'] == source_cwd, 'Command source working directory')
        folder = directory / relative
        require(read(folder / 'command.json') == command, 'Command/report binding: ' + str(relative))
        for stream in ('stdout', 'stderr'):
            if stream in command:
                require(file_record(folder / stream) == command[stream], 'Command stream binding: ' + str(relative))
        if command.get('returncode') is not None:
            success = command['returncode'] == 0 and not command.get('timedOut', False)
            require((command['status'] == 'success') == success, 'Command success interpretation')
        else:
            require(command['status'] == 'error', 'Missing process is an error')

    used_commands = set()

    def bind(relative, argv, label):
        key = str(relative)
        require(key in commands and commands[key]['argv'] == [str(a) for a in argv], label)
        used_commands.add(key)
        return commands[key]

    for name, tool in report['tools'].items():
        command = bind('tools/' + name, [tool['path'], '-h' if name == 'antiword' else '--version'], 'Tool version command')
        require(name == 'antiword' or command['status'] == 'success', 'Tool version execution')
        stream = 'stdout' if command['status'] == 'success' else 'stderr'
        version = (directory / 'tools' / name / stream).read_bytes().decode('utf-8', 'replace')[:10000]
        require(tool['version'] == version, 'Tool version output binding')
    if report['parserIdentity']['mode'] == 'compiled from recorded source':
        parser_executable = str(origin / 'parser')
        build = bind('build', [report['tools']['dart']['path'], 'compile', 'exe', 'tool/fidelity/convert.dart', '-o', parser_executable], 'Parser build command')
        require(build['status'] == 'success', 'Parser build execution')
        require(file_record(directory / 'parser') == {k: report['parserIdentity'][k] for k in ('bytes', 'sha256')}, 'Retained parser executable identity')
        executable_verified = True
    else:
        require(report['parserIdentity']['mode'] == 'supplied executable; caller must retain its build receipt', 'Parser build mode')
        parser_executable = report['parserIdentity']['path']
        executable_verified = False

    def output(relative):
        command = commands[str(relative)]
        require(command['status'] == 'success', 'Successful reader command required: ' + str(relative))
        return (directory / relative / 'stdout').read_bytes()

    cases_seen, projected, markdown, metadata_changes, reader_errors = set(), [], [], [], []
    documents = 0
    for case in report['cases']:
        name = case['id']
        require(re.fullmatch(r'[A-Za-z0-9_-]+', name) and name not in cases_seen, 'Unique safe case ID')
        cases_seen.add(name)
        require(read(directory / name / 'case.json') == case, 'Case/report binding: ' + name)
        require(case['status'] == 'completed', 'This verifier requires completed conversion paths')
        nodes = case['nodes']
        is_docx = nodes['source']['format'] == 'docx'
        binary = 'binary' if is_docx else 'source'
        expected = {'source': (None, 'source', 'docx' if is_docx else 'cfb'),
                    'native-docx': (binary, 'libreoffice', 'docx'),
                    'parser-docx': (binary, 'parser', 'docx'),
                    'native-to-binary': ('native-docx', 'libreoffice', 'cfb'),
                    'parser-to-binary': ('parser-docx', 'libreoffice', 'cfb')}
        if is_docx:
            expected.update({'docx-resave': ('source', 'libreoffice', 'docx'),
                             'binary': ('source', 'libreoffice', 'cfb')})
        for prefix in ('native', 'parser'):
            for importer, writer in (('native', 'libreoffice'), ('parser', 'parser')):
                expected[prefix + '-cycle-' + importer] = (prefix + '-to-binary', writer, 'docx')
        require(set(nodes) == set(expected), 'Complete path graph: ' + name)
        for identifier, node in nodes.items():
            source_id, writer, kind = expected[identifier]
            require((node['id'], node['from'], node['writer'], node['expectedFormat'])
                    == (identifier, source_id, writer, kind), 'Path attribution: ' + name + '/' + identifier)
            folder = directory / name / identifier
            require(node['status'] == 'success', 'This verifier requires completed conversion nodes')
            relative = Path(node['path']).relative_to(origin)
            require(relative.parent == Path(name) / identifier, 'Document path attribution')
            path = directory / relative
            require(file_record(path) == {k: node[k] for k in ('bytes', 'sha256')}, 'Document bytes: ' + str(relative))
            require_format(path, kind)
            require(node['format'] == kind, 'Document format binding')
            input_identity = {k: node['input'][k] for k in ('bytes', 'sha256')}
            parent = nodes[source_id] if source_id else case['source']
            require(input_identity == {k: parent[k] for k in ('bytes', 'sha256')}, 'Same-input path identity')
            require(node['inputAfter'] == input_identity, 'Converter source changed')
            require(node['input']['path'] == parent['path'], 'Parent path binding')
            if writer != 'source':
                command_path = Path(name) / identifier / 'command'
                if writer == 'parser':
                    command = bind(command_path, [parser_executable, parent['path'], node['path']], 'Parser conversion command')
                else:
                    original_folder = origin / name / identifier
                    conversion = 'doc:MS Word 97' if kind == 'cfb' else 'docx:Office Open XML Text'
                    command = bind(command_path, [report['tools']['office']['path'], '-env:UserInstallation=' + (original_folder / 'profile').as_uri(),
                        '--headless', '--norestore', '--nodefault', '--convert-to', conversion, '--outdir', original_folder, parent['path']], 'Native conversion command')
                    require(Path(node['path']).name == Path(parent['path']).stem + ('.doc' if kind == 'cfb' else '.docx'), 'Native output filename')
                require(command['status'] == 'success', 'Successful conversion command')
            if writer == 'parser':
                require(read(folder / 'command/stdout') == node['parserResult'], 'Parser result binding')
                require(command['argv'][1:] == [parent['path'], node['path']], 'Parser command source/output binding')
            documents += 1
            if kind == 'cfb':
                observation = node.get('antiword')
                if observation is not None:
                    relative_command = Path(name) / identifier / 'antiword'
                    command = bind(relative_command, [report['tools']['antiword']['path'], '-m', 'UTF-8.txt', '-t', '-w', '0', node['path']], 'Antiword reader command')
                    raw = (directory / relative_command / 'stdout').read_bytes()
                    if observation['status'] == 'success':
                        require(command['status'] == 'success' and observation['text'] == raw.decode('utf-8')
                                and observation['sha256'] == sha(raw), 'Antiword text binding')
                    else:
                        reader_errors.append({'node': identifier, 'reader': 'antiword', 'error': observation['error']})
                        if command['status'] == 'success':
                            try:
                                raw.decode('utf-8')
                            except UnicodeDecodeError:
                                pass
                            else:
                                raise ValueError('Unexplained Antiword reader error')
                continue
            facts = package_facts(path)
            require(node['facts'] == facts == read(folder / 'package-facts.json'), 'Package observation binding')
            observed = (observer.snapshot if observer else snapshot)(path)
            require(node['xmlSnapshot'] == observed == read(folder / 'xml-snapshot.json'), 'Typed XML observation binding')
            parts = package_parts(path)
            for view, observation in node['pandoc'].items():
                require(view in ('accept', 'reject', 'all'), 'Revision view')
                base = Path(name) / identifier / 'pandoc' / view
                require(observation['status'] == 'success', 'This verifier requires successful Pandoc projections')
                command = commands[str(base / 'read')]
                pandoc = report['tools']['pandoc']['path']
                bind(base / 'read', [pandoc, '+RTS', '-N1', '-M256m', '-K32m', '-RTS', '--sandbox', '--from=docx', '--to=json', '--track-changes=' + view, node['path']], 'Pandoc DOCX reader command')
                ast = json.loads(output(base / 'read'))
                require(ast == read(directory / base / 'ast.json'), 'Retained Pandoc AST')
                bindings = ast_image_parts(ast, parts)
                body = normalized_ast(ast, bindings)
                require(observation['bodyAst'] == body and observation['metadata'] == ast['meta']
                        and observation['images'] == bindings and observation['astCounts'] == ast_counts(ast['blocks'])
                        and observation['apiVersion'] == ast['pandoc-api-version'], 'Derived Pandoc observation')
                raw_markdown = output(base / 'write-markdown')
                bind(base / 'write-markdown', [pandoc, '--sandbox', '--from=json', '--to=markdown', '--wrap=none', origin / base / 'ast.json'], 'Markdown writer command')
                require(raw_markdown == (directory / base / 'output.md').read_bytes()
                        and observation['markdown'] == raw_markdown.decode('utf-8')
                        and observation['markdownSha256'] == sha(raw_markdown), 'Markdown byte binding')
                reread = json.loads(output(base / 'read-markdown'))
                bind(base / 'read-markdown', [pandoc, '--sandbox', '--from=markdown', '--to=json', origin / base / 'output.md'], 'Markdown reader command')
                require(reread == read(directory / base / 'markdown-ast.json'), 'Markdown reread binding')
                require(observation['markdownRoundtrip'] == differences(body, normalized_ast(reread, bindings)), 'Markdown body comparison')
                metadata_diff = differences(ast['meta'], reread['meta'])
                if report['version'] >= 2:
                    require(observation['markdownMetadata'] == reread['meta']
                            and observation['markdownMetadataRoundtrip'] == metadata_diff, 'Markdown metadata comparison')
                    require(observation['markdownRoundtripScope'] == 'body AST only; metadata is measured separately', 'Body comparison scope')
                if not metadata_diff['equal']:
                    metadata_changes.append({'case': name, 'node': identifier, 'view': view, 'difference': metadata_diff})
                markdown.append((observation, metadata_diff))
        views = list(next(n['pandoc'] for n in nodes.values() if 'pandoc' in n))
        runner = Runner.__new__(Runner)
        runner.options = SimpleNamespace(track_changes=views, antiword='antiword' in report['tools'])
        expected_comparisons = {'same-binary-importers': ('native-docx', 'parser-docx')}
        for prefix in ('native', 'parser'):
            expected_comparisons.update({
                prefix + '-cycle-importers': (prefix + '-cycle-native', prefix + '-cycle-parser'),
                prefix + '-cycle-vs-first': (prefix + '-docx', prefix + '-cycle-' + ('native' if prefix == 'native' else 'parser')),
                prefix + '-binary-text': (binary, prefix + '-to-binary')})
        if is_docx:
            for target in ('docx-resave', 'native-docx', 'parser-docx', 'native-cycle-native', 'parser-cycle-parser'):
                expected_comparisons['original-vs-' + target] = ('source', target)
            expected_comparisons['ooxml-vs-binary-bridge'] = ('docx-resave', 'native-docx')
        require(len(case['comparisons']) == len(expected_comparisons)
                and {c['id'] for c in case['comparisons']} == set(expected_comparisons), 'Complete comparison inventory')
        replay = {'nodes': nodes, 'comparisons': []}
        for comparison in case['comparisons']:
            require((comparison['before'], comparison['after']) == expected_comparisons[comparison['id']], 'Comparison source roles')
            runner.compare(replay, comparison['id'], comparison['before'], comparison['after'], comparison['attribution'])
            if observer and replay['comparisons'][-1].get('xmlStatus') == 'measured':
                replay['comparisons'][-1]['xmlFindings'] = observer.compare_semantics(
                    nodes[comparison['before']]['xmlSnapshot'], nodes[comparison['after']]['xmlSnapshot'])
            require(replay['comparisons'][-1] == comparison, 'Derived path comparison: ' + name + '/' + comparison['id'])
            projected.extend(p for p in comparison.get('pandoc', {}).values() if p['status'] == 'measured')

    comparisons = [c for case in report['cases'] for c in case['comparisons']]
    require(used_commands == set(commands), 'Complete command attribution inventory')
    error_key = lambda value: json.dumps(value, sort_keys=True)
    require(sorted(report['errors'], key=error_key) == sorted(reader_errors, key=error_key), 'Reader error inventory binding')
    summary = {'cases': len(report['cases']), 'comparisons': len(comparisons),
               'measuredPandocComparisons': len(projected), 'equalPandocAst': sum(p['ast']['equal'] for p in projected),
               'equalMarkdown': sum(p['markdownEqual'] for p in projected), 'executionErrors': len(report['errors']),
               'blockedComparisons': sum(c['status'] == 'blocked' for c in comparisons)}
    if report['version'] >= 2:
        summary.update(equalPandocMetadata=sum(p['metadata']['equal'] for p in projected),
                       measuredMarkdownRoundtrips=len(markdown),
                       changedMarkdownBodies=sum(not p['markdownRoundtrip']['equal'] for p, _ in markdown),
                       changedMarkdownMetadata=len(metadata_changes))
    require(report['summary'] == summary, 'Derived report summary')
    require(report['status'] == ('completed-with-errors' if report['errors'] else 'completed-discovery'), 'Completion is not fidelity')
    return {'reportVersion': report['version'], 'measuredCommit': report['repository']['commit'],
            'parserExecutableBytesVerified': executable_verified,
            'verifiedCommands': len(commands), 'verifiedDocuments': documents, 'verifiedComparisons': len(comparisons),
            'verifiedPandocProjections': len(markdown), 'markdownMetadataChanges': metadata_changes,
            'summary': summary, 'scope': 'Read-only artifact and observation replay; no converter rerun or independent correctness vote.'}


def self_test(directory, observer=None):
    """Reseal derived report/case observations while keeping original artifacts.

    Supplying matching altered case records bypasses the outer duplication
    check deliberately, so each control exercises an actual derived binding.
    No retained file is written or native/reader tool invoked.
    """
    global read
    original_read = read
    original = original_read(Path(directory) / 'report.json')
    controls = []

    def rejected(label, mutate, guard):
        global read
        changed = deepcopy(original)
        mutate(changed)
        cases = {c['id']: c for c in changed['cases']}
        command_records = {c['directory']: c for c in changed['commands']}

        def resealed(path):
            path = Path(path)
            if path.name == 'case.json' and path.parent.name in cases:
                return cases[path.parent.name]
            if path.name == 'command.json':
                relative = path.parent.relative_to(Path(directory).resolve()).as_posix()
                if relative in command_records:
                    return command_records[relative]
            return original_read(path)

        read = resealed
        try:
            verify(directory, changed, observer)
        except ValueError as error:
            require(guard in str(error), 'Wrong corruption guard for ' + label + ': ' + str(error))
            controls.append(label)
        else:
            raise ValueError('Accepted derived corruption: ' + label)
        finally:
            read = original_read

    def false_equality(report):
        comparison = next(c for case in report['cases'] for c in case['comparisons']
                          if any(not p['ast']['equal'] for p in c.get('pandoc', {}).values() if p['status'] == 'measured'))
        projection = next(p for p in comparison['pandoc'].values() if p['status'] == 'measured' and not p['ast']['equal'])
        projection['ast']['equal'] = True

    rejected('false AST equality', false_equality, 'Derived path comparison')
    rejected('wrong same-binary importer role', lambda r: r['cases'][0]['nodes']['parser-docx'].update({'from': 'parser-docx'}), 'Path attribution')
    def substituted_native(report):
        command = next(c for c in report['commands'] if c['directory'].endswith('/native-docx/command'))
        command['argv'][0] = '/usr/bin/true'
    rejected('substituted native executable', substituted_native, 'Native conversion command')
    def substituted_writer(report):
        command = next(c for c in report['commands'] if c['directory'].endswith('/write-markdown'))
        command['argv'][-1] = str(Path(command['argv'][-1]).with_name('unrelated.json'))
    rejected('substituted Markdown input', substituted_writer, 'Markdown writer command')
    if original['parserIdentity']['mode'] == 'compiled from recorded source':
        rejected('invented parser executable hash', lambda r: r['parserIdentity'].update(sha256='0' * 64), 'Retained parser executable identity')
    rejected('invented summary equality', lambda r: r['summary'].update(equalPandocAst=r['summary']['equalPandocAst'] + 1), 'Derived report summary')

    def changed_body(report):
        node = next(n for c in report['cases'] for n in c['nodes'].values() if n.get('pandoc'))
        next(iter(node['pandoc'].values()))['bodyAst'] = []

    rejected('empty body substituted for reader output', changed_body, 'Derived Pandoc observation')
    if original['errors']:
        rejected('erased reader error', lambda r: r['errors'].pop(), 'Reader error inventory binding')
    if original['version'] >= 2:
        def changed_metadata(report):
            node = next(n for c in report['cases'] for n in c['nodes'].values() if n.get('pandoc'))
            next(iter(node['pandoc'].values()))['markdownMetadata'] = {'invented': {'t': 'MetaString', 'c': 'wrong'}}
        rejected('invented Markdown metadata', changed_metadata, 'Markdown metadata comparison')
    return controls


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--self-test', action='store_true')
    parser.add_argument('--oracle-source', type=Path,
                        help='Directory with exact retained oracle.py and structure.py, checked against the measured source receipt')
    args = parser.parse_args()
    report = read(args.directory / 'report.json')
    observer = load_observer(args.oracle_source, report) if args.oracle_source else None
    result = verify(args.directory, report, observer)
    if args.self_test:
        result['corruptionControls'] = self_test(args.directory, observer)
    encoded = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
    if args.output:
        args.output.write_text(encoded, encoding='utf-8')
    print(encoded, end='')


if __name__ == '__main__':
    main()
