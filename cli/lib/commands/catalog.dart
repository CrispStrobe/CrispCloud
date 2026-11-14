import 'dart:convert';
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:crisp_catalog/crisp_catalog.dart';

class CatalogCommand extends Command<int> {
  CatalogCommand() {
    for (final op in ['scan', 'import', 'export', 'info', 'search']) {
      addSubcommand(_CatalogOperation(op));
    }
  }
  @override
  String get name => 'catalog';
  @override
  String get description =>
      'Persistent large-volume metadata indexes and Cathy/Catfish CAF interchange.';
}

class _CatalogOperation extends Command<int> {
  _CatalogOperation(this.name) {
    if (['scan', 'import', 'export'].contains(name)) {
      argParser
        ..addOption(
          'output',
          abbr: 'o',
          help: 'Destination catalogue database.',
        )
        ..addFlag(
          'replace',
          negatable: false,
          help: 'Replace an existing output after successful staging.',
        );
    }
    if (name == 'scan') {
      argParser
        ..addOption(
          'max-entries',
          defaultsTo: '0',
          help: '0 means no entry cap.',
        )
        ..addOption(
          'max-depth',
          defaultsTo: '0',
          help: '0 means no depth cap.',
        );
    }
    if (name == 'scan') {
      argParser.addFlag(
        'allow-partial',
        negatable: false,
        help: 'Allow a partial refresh to replace an existing catalogue.',
      );
    }
    if (name == 'export') {
      argParser.addFlag(
        'allow-lossy',
        negatable: false,
        help:
            'Acknowledge CAF cannot retain partial-scan or source-coverage diagnostics.',
      );
    }
    if (name == 'search') {
      argParser.addOption(
        'top',
        abbr: 'n',
        defaultsTo: '100',
        help: 'Maximum matches, 1..10000.',
      );
    }
  }
  @override
  final String name;
  @override
  String get description => switch (name) {
    'scan' =>
      'Index a local directory into a staged SQLite .crispindex database.',
    'import' => 'Import a Cathy/Catfish CAF as a historical catalogue.',
    'export' =>
      'Export observed files to classic CAF v8; unrepresentable names fail safely.',
    'info' => 'Show catalogue totals, age and coverage.',
    _ =>
      'Find paths in a saved catalogue without accessing its original source.',
  };
  @override
  String get invocation =>
      '${runner?.executableName ?? 'crispcloud'} catalog $name ${name == 'search' ? '<index> <text>' : '<path>'} [options]';
  int _number(String key, int max) {
    final n = int.tryParse(argResults![key] as String);
    if (n == null || n < 0 || n > max || (key == 'top' && n == 0)) {
      usageException('Invalid --$key.');
    }
    return n;
  }

  @override
  Future<int> run() async {
    final args = argResults!;
    if (args.rest.length != (name == 'search' ? 2 : 1)) {
      usageException('Check the required path arguments.');
    }
    if (['scan', 'import', 'export'].contains(name) && args['output'] == null) {
      usageException('Specify --output.');
    }
    final request = <String, Object?>{
      'op': name == 'search' ? 'query' : name,
      if (name == 'scan' || name == 'import')
        'path': args.rest.first
      else
        'index': args.rest.first,
      if (['scan', 'import', 'export'].contains(name)) ...{
        'output': args['output'],
        'replace': args['replace'],
      },
      if (name == 'scan') ...{
        'maxEntries': _number('max-entries', 9007199254740991),
        'allowPartial': args['allow-partial'],
        'maxDepth': _number('max-depth', 100000),
      },
      if (name == 'export') 'allowLossy': args['allow-lossy'],
      if (name == 'search') ...{
        'search': args.rest.last,
        'recursive': true,
        'top': _number('top', 10000),
      },
    };
    try {
      final result = await const CrispCatalog().execute(request);
      stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
      return name == 'scan' && result['complete'] == false ? 1 : 0;
    } on CatalogException catch (e) {
      stderr.writeln(
        jsonEncode({
          'error': {'code': 'catalogue_failed', 'message': e.message},
        }),
      );
      return 1;
    }
  }
}
