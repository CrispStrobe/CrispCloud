// lib/commands/ls.dart
//
// crisp ls [<path>] [--provider <name>] [--json] [--long] [--human]

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../adapters/cli_adapter_factory.dart';
import '../adapters/cli_storage_client.dart';
import '../config/cli_config.dart';

class LsCommand extends Command<int> {
  @override
  final String name = 'ls';

  @override
  final String description = 'List files and folders at a remote path.';

  @override
  String get invocation => 'crisp ls [<path>] [options]';

  final CliConfig config;

  LsCommand(this.config) {
    argParser
      ..addOption(
        'provider',
        abbr: 'p',
        help: 'Provider name to use (defaults to configured default).',
      )
      ..addFlag(
        'json',
        abbr: 'j',
        negatable: false,
        help: 'Output as JSON.',
      )
      ..addFlag(
        'long',
        abbr: 'l',
        negatable: false,
        help: 'Long listing format (size, modified date, type).',
      )
      ..addFlag(
        'human',
        negatable: false,
        help: 'Human-readable file sizes (with --long).',
      );
  }

  @override
  Future<int> run() async {
    final args = argResults!;
    final remotePath = args.rest.isNotEmpty ? args.rest.first : '/';
    final providerName = config.resolveProviderName(args['provider'] as String?);
    final asJson = args['json'] as bool;
    final long = args['long'] as bool;
    final human = args['human'] as bool;

    final providerCfg = config.providerConfig(providerName);
    if (providerCfg == null) {
      stderr.writeln('Unknown provider: $providerName');
      return 1;
    }

    final adapter = createAdapter(providerName, providerCfg);
    try {
      final items = await adapter.list(remotePath);

      if (asJson) {
        stdout.writeln(
          const JsonEncoder.withIndent('  ')
              .convert(items.map((i) => i.toJson()).toList()),
        );
      } else if (long) {
        _printLong(items, human: human);
      } else {
        _printShort(items);
      }
      return 0;
    } catch (e) {
      stderr.writeln('Error listing $remotePath: $e');
      return 1;
    } finally {
      await adapter.dispose();
    }
  }

  void _printShort(List<CliFileItem> items) {
    final dirs = items.where((i) => i.isDirectory).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final files = items.where((i) => !i.isDirectory).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    for (final d in dirs) {
      stdout.writeln('${d.name}/');
    }
    for (final f in files) {
      stdout.writeln(f.name);
    }
  }

  void _printLong(List<CliFileItem> items, {bool human = false}) {
    final sorted = [...items]
      ..sort((a, b) {
        if (a.isDirectory != b.isDirectory) {
          return a.isDirectory ? -1 : 1;
        }
        return a.name.compareTo(b.name);
      });

    // Compute column widths
    int maxSize = 4; // "Size" header length
    for (final i in sorted) {
      if (!i.isDirectory) {
        final s = human ? _humanSize(i.size ?? 0) : '${i.size ?? 0}';
        if (s.length > maxSize) maxSize = s.length;
      }
    }

    stdout.writeln(
      '${'Type'.padRight(6)}  ${'Size'.padLeft(maxSize)}  ${'Modified'.padRight(24)}  Name',
    );
    stdout.writeln('-' * 80);

    for (final item in sorted) {
      final type = item.isDirectory ? 'DIR' : 'file';
      final sizeStr = item.isDirectory
          ? '-'
          : (human ? _humanSize(item.size ?? 0) : '${item.size ?? 0}');
      final mod = item.modifiedAt ?? '-';
      stdout.writeln(
        '${type.padRight(6)}  ${sizeStr.padLeft(maxSize)}  ${mod.padRight(24)}  ${item.name}',
      );
    }
  }

  static String _humanSize(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double size = bytes.toDouble();
    int unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return unit == 0
        ? '${size.toStringAsFixed(0)} B'
        : '${size.toStringAsFixed(1)} ${units[unit]}';
  }
}
