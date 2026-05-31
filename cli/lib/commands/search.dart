// lib/commands/search.dart
//
// crisp search <query> [--provider <name>] [--recursive] [--json]
//
// Searches for files whose names match the glob-style query pattern.
// With --recursive, descends into subdirectories.
// Does NOT download file contents (name-based only in v1).

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../adapters/cli_adapter_factory.dart';
import '../adapters/cli_storage_client.dart';
import '../config/cli_config.dart';

class SearchCommand extends Command<int> {
  @override
  final String name = 'search';

  @override
  final String description =
      'Search for files by name pattern at a remote path.';

  @override
  String get invocation =>
      'crisp search <pattern> [--path <remote-path>] [--recursive] [options]';

  final CliConfig config;

  SearchCommand(this.config) {
    argParser
      ..addOption('provider', abbr: 'p', help: 'Provider name.')
      ..addOption(
        'path',
        defaultsTo: '/',
        help: 'Remote path to search in.',
      )
      ..addFlag(
        'recursive',
        abbr: 'r',
        negatable: false,
        help: 'Recurse into subdirectories.',
      )
      ..addFlag(
        'json',
        abbr: 'j',
        negatable: false,
        help: 'Output results as JSON.',
      );
  }

  @override
  Future<int> run() async {
    final args = argResults!;
    final rest = args.rest;

    if (rest.isEmpty) {
      usageException('Usage: crisp search <pattern>');
    }

    final pattern = rest.first;
    final remotePath = args['path'] as String;
    final providerName = config.resolveProviderName(args['provider'] as String?);
    final recursive = args['recursive'] as bool;
    final asJson = args['json'] as bool;

    final providerCfg = config.providerConfig(providerName);
    if (providerCfg == null) {
      stderr.writeln('Unknown provider: $providerName');
      return 1;
    }

    final adapter = createAdapter(providerName, providerCfg);
    try {
      final results = <CliFileItem>[];
      await _search(adapter, remotePath, pattern, recursive, results);

      if (asJson) {
        stdout.writeln(
          const JsonEncoder.withIndent('  ')
              .convert(results.map((r) => r.toJson()).toList()),
        );
      } else {
        if (results.isEmpty) {
          stdout.writeln('No files matching "$pattern" found.');
        } else {
          for (final r in results) {
            stdout.writeln(r.path);
          }
        }
      }
      return 0;
    } catch (e) {
      stderr.writeln('Search failed: $e');
      return 1;
    } finally {
      await adapter.dispose();
    }
  }

  Future<void> _search(
    CliStorageClient adapter,
    String remotePath,
    String pattern,
    bool recursive,
    List<CliFileItem> results,
  ) async {
    final items = await adapter.list(remotePath);
    final regex = _globToRegex(pattern);

    for (final item in items) {
      if (!item.isDirectory && regex.hasMatch(item.name)) {
        results.add(item);
      }
      if (item.isDirectory && recursive) {
        await _search(adapter, item.path, pattern, recursive, results);
      }
    }
  }

  /// Exposed for tests.
  static RegExp buildRegexForTest(String glob) => _globToRegex(glob);

  /// Convert a simple glob pattern (*, ?, [set]) to a RegExp.
  static RegExp _globToRegex(String glob) {
    final sb = StringBuffer('^');
    for (int i = 0; i < glob.length; i++) {
      final ch = glob[i];
      switch (ch) {
        case '*':
          sb.write('.*');
        case '?':
          sb.write('.');
        case '[':
          // Pass character class through as-is until ']'
          final end = glob.indexOf(']', i + 1);
          if (end < 0) {
            sb.write(r'\[');
          } else {
            sb.write(glob.substring(i, end + 1));
            i = end;
          }
        case '.':
        case '+':
        case '^':
        case r'$':
        case '{':
        case '}':
        case '(':
        case ')':
        case '|':
        case r'\':
          sb.write(r'\');
          sb.write(ch);
        default:
          sb.write(ch);
      }
    }
    sb.write(r'$');
    return RegExp(sb.toString(), caseSensitive: false);
  }
}
