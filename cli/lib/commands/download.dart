// lib/commands/download.dart
//
// crisp download <remote> <local> [--provider <name>] [--progress] [--json]

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../adapters/cli_adapter_factory.dart';
import '../config/cli_config.dart';

class DownloadCommand extends Command<int> {
  @override
  final String name = 'download';

  @override
  final String description = 'Download a remote file to a local path.';

  @override
  String get invocation => 'crisp download <remote-path> <local-path> [options]';

  final CliConfig config;

  DownloadCommand(this.config) {
    argParser
      ..addOption(
        'provider',
        abbr: 'p',
        help: 'Provider name to use.',
      )
      ..addFlag(
        'progress',
        negatable: false,
        help: 'Show download progress.',
      )
      ..addFlag(
        'json',
        abbr: 'j',
        negatable: false,
        help: 'Output result as JSON.',
      );
  }

  @override
  Future<int> run() async {
    final args = argResults!;
    final rest = args.rest;

    if (rest.length < 2) {
      usageException('Usage: crisp download <remote-path> <local-path>');
    }

    final remotePath = rest[0];
    var localPath = rest[1];
    final providerName = config.resolveProviderName(args['provider'] as String?);
    final showProgress = args['progress'] as bool;
    final asJson = args['json'] as bool;

    // If local path is a directory, use the remote filename
    final localTarget = Directory(localPath);
    if (localTarget.existsSync()) {
      localPath = p.join(localPath, p.posix.basename(remotePath));
    }

    final providerCfg = config.providerConfig(providerName);
    if (providerCfg == null) {
      stderr.writeln('Unknown provider: $providerName');
      return 1;
    }

    final adapter = createAdapter(providerName, providerCfg);
    int lastPct = -1;

    void progressCallback(int received, int total) {
      if (!showProgress) return;
      final pct = total > 0 ? (received * 100 ~/ total) : 0;
      if (pct != lastPct) {
        lastPct = pct;
        stderr.write('\rDownloading: $pct%');
      }
    }

    try {
      await adapter.download(remotePath, localPath, onProgress: progressCallback);
      if (showProgress) stderr.writeln('');

      final bytes = File(localPath).lengthSync();
      final result = {
        'status': 'ok',
        'remote': remotePath,
        'local': localPath,
        'bytes': bytes,
        'provider': providerName,
      };

      if (asJson) {
        stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
      } else {
        stdout.writeln('Downloaded $bytes bytes → $localPath');
      }
      return 0;
    } catch (e) {
      stderr.writeln('Download failed: $e');
      return 1;
    } finally {
      await adapter.dispose();
    }
  }
}
