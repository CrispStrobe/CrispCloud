import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../disk_usage.dart';
import 'package:crisp_catalog/crisp_catalog.dart';

class DuCommand extends Command<int> {
  DuCommand({DiskUsageScanner? scanner})
    : scanner = scanner ?? DiskUsageScanner() {
    argParser
      ..addOption(
        'top',
        abbr: 'n',
        defaultsTo: '20',
        help: 'Number of largest entries (1–10000).',
      )
      ..addFlag(
        'recursive',
        abbr: 'r',
        negatable: false,
        help: 'Rank entries at every depth; directory rows overlap.',
      )
      ..addFlag(
        'files-only',
        negatable: false,
        help: 'Find the largest individual files anywhere below the path.',
      )
      ..addFlag('dirs-only', negatable: false, help: 'Show only directories.')
      ..addOption(
        'max-entries',
        defaultsTo: '0',
        help:
            'Metadata entry budget including root; 0 scans without an entry cap.',
      )
      ..addOption(
        'max-depth',
        defaultsTo: '200',
        help:
            'Traversal depth budget (0–500); a limit produces partial totals.',
      )
      ..addFlag(
        'bytes',
        negatable: false,
        help: 'Print exact byte counts instead of human-readable sizes.',
      )
      ..addOption(
        'index',
        help:
            'Query a saved .crispindex database offline; path is relative within it.',
      )
      ..addFlag(
        'json',
        abbr: 'j',
        negatable: false,
        help: 'Write a structured metadata report.',
      );
  }
  final DiskUsageScanner scanner;

  @override
  String get name => 'du';
  @override
  String get description =>
      'Find the largest local files and folders (logical file sizes).';
  @override
  String get invocation =>
      '${runner?.executableName ?? 'crispcloud'} du [local-path] [options]';

  int _number(String name, int min, int max) {
    final value = int.tryParse(argResults![name] as String);
    if (value == null || value < min || value > max) {
      usageException('--$name must be an integer between $min and $max.');
    }
    return value;
  }

  @override
  Future<int> run() async {
    final args = argResults!;
    if (args.rest.length > 1) usageException('Specify one local path.');
    if (args['files-only'] == true && args['dirs-only'] == true) {
      usageException('Use either --files-only or --dirs-only.');
    }
    final top = _number('top', 1, 10000);
    final maxEntries = _number('max-entries', 0, 9007199254740991);
    final maxDepth = _number('max-depth', 0, 500);
    final path = args.rest.isEmpty ? '.' : args.rest.single;
    final json = args['json'] as bool;
    if (args['index'] case final String index) {
      try {
        final report = await const CrispCatalog().execute({
          'op': 'query',
          'index': index,
          'path': args.rest.isEmpty ? '' : args.rest.single,
          'top': top,
          'filesOnly': args['files-only'],
          'directoriesOnly': args['dirs-only'],
          'recursive': args['recursive'],
        });
        if (json) {
          stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
        } else {
          stdout.writeln(
            'Historical catalogue indexed at '
            '${DateTime.fromMillisecondsSinceEpoch((report['indexedAtUnix'] as int) * 1000, isUtc: true).toIso8601String()}; '
            'source availability has not been checked.',
          );
          for (final row in report['entries'] as List) {
            final bytes = row['bytes'] as int;
            stdout.writeln(
              '${row['complete'] == true ? '' : '>='}${args['bytes'] == true ? bytes : _human(bytes)}  ${row['type']}  ${jsonEncode(row['path'])}',
            );
          }
          stdout.writeln('Logical total: ${report['root']['bytes']} bytes.');
          if (report['complete'] != true) {
            stderr.writeln(
              'Catalogue is partial or its original coverage is unknown; use --json for diagnostics.',
            );
          }
        }
        return report['complete'] == true ? 0 : 1;
      } on CatalogException catch (e) {
        stderr.writeln(
          json
              ? jsonEncode({
                  'error': {'code': 'catalogue_failed', 'message': e.message},
                })
              : e,
        );
        return 1;
      }
    }
    var cancelled = false;
    StreamSubscription<ProcessSignal>? signal;
    try {
      try {
        signal = ProcessSignal.sigint.watch().listen((_) => cancelled = true);
      } on UnsupportedError {
        // Some hosts do not expose console signals.
      }
      final result = await scanner.scan(
        path,
        top: top,
        recursive: args['recursive'] as bool,
        filesOnly: args['files-only'] as bool,
        directoriesOnly: args['dirs-only'] as bool,
        maxEntries: maxEntries,
        maxDepth: maxDepth,
        isCancelled: () => cancelled,
      );
      if (json) {
        stdout.writeln(
          const JsonEncoder.withIndent('  ').convert(result.toJson()),
        );
      } else {
        final exact = args['bytes'] as bool;
        stdout.writeln('Largest entries in ${jsonEncode(result.root.path)}');
        stdout.writeln('Logical file sizes; links excluded.');
        for (final row in result.rows) {
          final size =
              '${row.complete ? '' : '>='}${exact ? row.bytes : _human(row.bytes)}';
          stdout.writeln(
            '${size.padLeft(13)}  ${row.kind == UsageKind.directory ? 'dir ' : 'file'}  ${jsonEncode(row.path)}',
          );
        }
        stdout.writeln(
          'Total: ${result.root.complete ? '' : '>='}${exact ? result.root.bytes : _human(result.root.bytes)}; '
          '${result.root.files} files, ${result.root.directories} directories, '
          '${result.linksSkipped} links skipped.',
        );
      }
      if (!result.root.complete && !json) {
        stderr.writeln(
          'Scan incomplete: ${result.issues.length + result.suppressedIssues} issues'
          '${result.cancelled ? ', interrupted' : ''}${result.limited ? ', scan limit reached' : ''}. '
          'Reported sizes are lower bounds; rankings may be incomplete. Use --json for details.',
        );
      }
      return result.cancelled ? 130 : (result.root.complete ? 0 : 1);
    } on FileSystemException {
      if (json) {
        stderr.writeln(
          jsonEncode({
            'error': {
              'code': 'root_unavailable',
              'path': path,
              'message':
                  'Cannot inspect the local path. Check that it exists and is accessible.',
            },
          }),
        );
      } else {
        stderr.writeln(
          'Cannot inspect ${jsonEncode(path)}. Check that it exists and is accessible.',
        );
      }
      return 1;
    } finally {
      await signal?.cancel();
    }
  }

  String _human(int bytes) {
    const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB', 'PiB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
  }
}
