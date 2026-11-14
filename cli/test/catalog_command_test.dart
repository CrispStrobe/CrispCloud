import 'dart:convert';
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:crisp/cli_app.dart';
import 'package:crisp_catalog/crisp_catalog.dart';
import 'package:test/test.dart';

class _Output implements Stdout {
  final buffer = StringBuffer();
  @override
  void writeln([Object? value = '']) => buffer.writeln(value);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('$invocation');
}

void main() {
  late Directory tmp;
  late Directory root;
  late File db;
  late _Output output;
  late _Output errors;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('crisp_catalog_cli_');
    root = Directory('${tmp.path}/source')..createSync();
    Directory('${root.path}/folder').createSync();
    File('${root.path}/small').writeAsBytesSync(List.filled(3, 0));
    File('${root.path}/folder/large').writeAsBytesSync(List.filled(9, 0));
    db = File('${tmp.path}/volume.crispindex');
    output = _Output();
    errors = _Output();
  });
  tearDown(() => tmp.deleteSync(recursive: true));
  Future<int?> run(List<String> args) => IOOverrides.runZoned(
    () => buildRunner(
      configPath: '${tmp.path}/credentials-never-loaded',
    ).run(args),
    stdout: () => output,
    stderr: () => errors,
  );
  test(
    'scan, offline du, search and real CAF interchange use the Rust bridge',
    () async {
      expect(await run(['catalog', 'scan', root.path, '-o', db.path]), 0);
      expect(jsonDecode(output.buffer.toString())['bytes'], 12);
      output.buffer.clear();
      expect(await run(['catalog', 'search', db.path, 'large']), 0);
      expect(
        jsonDecode(output.buffer.toString())['entries'].single['bytes'],
        9,
      );
      output.buffer.clear();
      final caf = '${tmp.path}/volume.caf';
      expect(await run(['catalog', 'export', db.path, '-o', caf]), 0);
      expect(jsonDecode(output.buffer.toString())['version'], 8);
      output.buffer.clear();
      final imported = '${tmp.path}/imported.crispindex';
      expect(await run(['catalog', 'import', caf, '-o', imported]), 0);
      expect(jsonDecode(output.buffer.toString())['bytes'], 12);
      output.buffer.clear();
      root.deleteSync(recursive: true);
      expect(
        await run([
          'du',
          '--index',
          db.path,
          '--files-only',
          '--top',
          '1',
          '--json',
        ]),
        0,
      );
      final result = jsonDecode(output.buffer.toString());
      expect(result['historical'], true);
      expect(result['entries'].single['bytes'], 9);
      expect(result['root']['bytes'], 12);
    },
  );
  test(
    'imported CAF ranks offline without claiming known source coverage',
    () async {
      expect(await run(['catalog', 'scan', root.path, '-o', db.path]), 0);
      final caf = '${tmp.path}/portable.caf';
      expect(await run(['catalog', 'export', db.path, '-o', caf]), 0);
      final imported = '${tmp.path}/offline.crispindex';
      expect(await run(['catalog', 'import', caf, '-o', imported]), 0);
      root.deleteSync(recursive: true);
      output.buffer.clear();
      errors.buffer.clear();
      expect(
        await run([
          'du',
          '--index',
          imported,
          '--files-only',
          '--top',
          '1',
          '--json',
        ]),
        1,
        reason:
            'CAF cannot certify the original scan coverage, even when ranking succeeds.',
      );
      final report = jsonDecode(output.buffer.toString());
      expect(report['historical'], true);
      expect(report['complete'], false);
      expect(report['origin'], 'caf_import');
      expect(report['root']['bytes'], 12);
      expect(report['entries'].single['bytes'], 9);
      expect(report['entries'].single['complete'], true);
      expect(
        (report['issues'] as List).map((issue) => issue['code']),
        contains('caf_coverage_unknown'),
      );
      expect(report.containsKey('error'), false);
      expect(errors.buffer.toString(), isEmpty);
    },
  );

  test(
    'explicit budgets retain diagnostics and do not imply completeness',
    () async {
      expect(
        await run([
          'catalog',
          'scan',
          root.path,
          '-o',
          db.path,
          '--max-entries',
          '1',
        ]),
        1,
      );
      expect(jsonDecode(output.buffer.toString())['complete'], false);
      output.buffer.clear();
      expect(await run(['du', '--index', db.path, '--json']), 1);
      expect(
        jsonDecode(output.buffer.toString())['issues'].single['code'],
        'entry_limit',
      );
    },
  );
  test(
    'output collisions and missing indexes fail before claiming success',
    () async {
      expect(await run(['catalog', 'scan', root.path, '-o', db.path]), 0);
      final previous = db.readAsBytesSync();
      output.buffer.clear();
      expect(await run(['catalog', 'scan', root.path, '-o', db.path]), 1);
      expect(db.readAsBytesSync(), previous);
      expect(
        jsonDecode(errors.buffer.toString())['error']['code'],
        'catalogue_failed',
      );
      errors.buffer.clear();
      expect(await run(['du', '--index', '${tmp.path}/missing', '--json']), 1);
      expect(File('${tmp.path}/missing').existsSync(), false);
    },
  );
  test(
    'partial refresh preserves prior catalogue unless explicitly allowed',
    () async {
      expect(await run(['catalog', 'scan', root.path, '-o', db.path]), 0);
      final previous = db.readAsBytesSync();
      output.buffer.clear();
      expect(
        await run([
          'catalog',
          'scan',
          root.path,
          '-o',
          db.path,
          '--replace',
          '--max-entries',
          '1',
        ]),
        1,
      );
      expect(db.readAsBytesSync(), previous);
      errors.buffer.clear();
      expect(
        await run([
          'catalog',
          'scan',
          root.path,
          '-o',
          db.path,
          '--replace',
          '--max-entries',
          '1',
          '--allow-partial',
        ]),
        1,
      );
      expect(jsonDecode(output.buffer.toString())['complete'], false);
    },
  );
  test('numeric options and required arguments are validated', () async {
    for (final args in [
      ['catalog', 'scan', root.path, '-o', db.path, '--max-entries', '-1'],
      ['catalog', 'search', db.path, 'x', '--top', '0'],
      ['catalog', 'scan', root.path],
    ]) {
      await expectLater(run(args), throwsA(isA<UsageException>()));
    }
  });
  test(
    'independent Python Catfish Windows CAF keeps names and modern zero sizes',
    () async {
      final result = await const CrispCatalog().execute({
        'op': 'import',
        'path': 'test/fixtures/catalog/catfish-v8-windows.caf',
        'output': db.path,
      });
      expect(result['root'], r'C:\Archive');
      expect(result['bytes'], 12);
      expect(result['files'], 3);
      final query = await const CrispCatalog().execute({
        'op': 'query',
        'index': db.path,
        'filesOnly': true,
      });
      final entries = query['entries'] as List;
      expect(entries.map((e) => e['relativePath']), [
        'folder/nine.bin',
        'café.txt',
        'zero.txt',
      ]);
      expect(entries.last['bytes'], 0);
    },
  );
  test('native API rejects traversal and unknown operations', () async {
    await const CrispCatalog().execute({
      'op': 'scan',
      'path': root.path,
      'output': db.path,
    });
    await expectLater(
      const CrispCatalog().execute({
        'op': 'query',
        'index': db.path,
        'path': '../escape',
      }),
      throwsA(isA<CatalogException>()),
    );
    await expectLater(
      const CrispCatalog().execute({'op': 'unknown'}),
      throwsA(isA<CatalogException>()),
    );
  });
}
