// lib/commands/share.dart
//
// crisp share <remote-path> [--expires <duration>] [--provider <name>] [--json]
//
// Generates a time-limited share link for a remote file.
// Duration format: 7d, 24h, 30m (days, hours, minutes). Default: 1h.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../adapters/cli_adapter_factory.dart';
import '../config/cli_config.dart';

class ShareCommand extends Command<int> {
  @override
  final String name = 'share';

  @override
  final String description =
      'Generate a time-limited share link for a remote file.';

  @override
  String get invocation => 'crisp share <remote-path> [--expires <duration>]';

  final CliConfig config;

  ShareCommand(this.config) {
    argParser
      ..addOption(
        'provider',
        abbr: 'p',
        help: 'Provider name.',
      )
      ..addOption(
        'expires',
        abbr: 'e',
        defaultsTo: '1h',
        help: 'Link expiry duration (e.g. 7d, 24h, 30m). Default: 1h.',
      )
      ..addFlag(
        'json',
        abbr: 'j',
        negatable: false,
        help: 'Output as JSON.',
      );
  }

  @override
  Future<int> run() async {
    final args = argResults!;
    final rest = args.rest;

    if (rest.isEmpty) {
      usageException('Usage: crisp share <remote-path>');
    }

    final remotePath = rest.first;
    final providerName = config.resolveProviderName(args['provider'] as String?);
    final expiresStr = args['expires'] as String;
    final asJson = args['json'] as bool;

    final expires = _parseDuration(expiresStr);
    if (expires == null) {
      stderr.writeln('Invalid duration "$expiresStr". Use: 7d, 24h, 30m');
      return 2;
    }

    final providerCfg = config.providerConfig(providerName);
    if (providerCfg == null) {
      stderr.writeln('Unknown provider: $providerName');
      return 1;
    }

    final adapter = createAdapter(providerName, providerCfg);
    try {
      final url = await adapter.share(remotePath, expires: expires);
      final expiresAt = DateTime.now().add(expires).toIso8601String();

      if (asJson) {
        stdout.writeln(const JsonEncoder.withIndent('  ').convert({
          'url': url,
          'expires_at': expiresAt,
          'path': remotePath,
          'provider': providerName,
        }));
      } else {
        stdout.writeln(url);
        stderr.writeln('Expires at: $expiresAt');
      }
      return 0;
    } on UnsupportedError catch (e) {
      stderr.writeln('This provider does not support sharing: $e');
      return 1;
    } catch (e) {
      stderr.writeln('Share failed: $e');
      return 1;
    } finally {
      await adapter.dispose();
    }
  }

  static Duration? _parseDuration(String s) {
    final m = RegExp(r'^(\d+)([dhm])$').firstMatch(s.trim());
    if (m == null) return null;
    final n = int.parse(m.group(1)!);
    switch (m.group(2)) {
      case 'd':
        return Duration(days: n);
      case 'h':
        return Duration(hours: n);
      case 'm':
        return Duration(minutes: n);
    }
    return null;
  }
}
