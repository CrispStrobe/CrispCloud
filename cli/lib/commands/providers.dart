// lib/commands/providers.dart
//
// crisp providers [--json]
//
// Lists all configured provider aliases with their type and host/endpoint.
// Does NOT reveal credentials.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../config/cli_config.dart';

class ProvidersCommand extends Command<int> {
  @override
  final String name = 'providers';

  @override
  final String description = 'List all configured cloud storage providers.';

  final CliConfig config;

  ProvidersCommand(this.config) {
    argParser.addFlag(
      'json',
      abbr: 'j',
      negatable: false,
      help: 'Output as JSON.',
    );
  }

  @override
  Future<int> run() async {
    final args = argResults!;
    final asJson = args['json'] as bool;
    final defaultProv = config.defaultProvider;
    final names = config.providerNames();

    if (names.isEmpty) {
      if (asJson) {
        stdout.writeln('[]');
      } else {
        stdout.writeln('No providers configured. Run: crisp connect <type> <identity>');
      }
      return 0;
    }

    final rows = <Map<String, dynamic>>[];
    for (final name in names) {
      final cfg = config.providerConfig(name) ?? {};
      final type = cfg['type'] as String? ?? '?';

      // Build a safe summary — omit credentials
      String info = '';
      switch (type.toLowerCase()) {
        case 's3':
          info = '${cfg['endpoint'] ?? ''}/${cfg['bucket'] ?? ''}';
        case 'sftp':
          info = '${cfg['username'] ?? ''}@${cfg['host'] ?? ''}:${cfg['port'] ?? '22'}';
        case 'webdav':
          info = '${cfg['username'] ?? ''}@${cfg['host'] ?? ''}';
        default:
          info = type;
      }

      rows.add({
        'name': name,
        'type': type,
        'info': info,
        'default': name == defaultProv,
      });
    }

    if (asJson) {
      stdout.writeln(const JsonEncoder.withIndent('  ').convert(rows));
    } else {
      final nameW = rows.map((r) => (r['name'] as String).length).reduce((a, b) => a > b ? a : b);
      final typeW = rows.map((r) => (r['type'] as String).length).reduce((a, b) => a > b ? a : b);

      for (final row in rows) {
        final isDefault = row['default'] as bool;
        final marker = isDefault ? '*' : ' ';
        stdout.writeln(
          '$marker ${(row['name'] as String).padRight(nameW)}  '
          '${(row['type'] as String).padRight(typeW)}  ${row['info']}',
        );
      }
      if (defaultProv != null) {
        stderr.writeln('(* = default provider)');
      }
    }
    return 0;
  }
}
