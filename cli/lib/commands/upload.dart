// lib/commands/upload.dart
//
// crisp upload <local> <remote> [--provider <name>] [--json] [--progress]

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../adapters/cli_adapter_factory.dart';
import '../config/cli_config.dart';

class UploadCommand extends Command<int> {
  @override
  final String name = 'upload';

  @override
  final String description = 'Upload a local file to a remote path.';

  @override
  String get invocation => 'crisp upload <local-file> <remote-dir> [options]';

  final CliConfig config;

  UploadCommand(this.config) {
    argParser
      ..addOption(
        'provider',
        abbr: 'p',
        help: 'Provider name to use.',
      )
      ..addFlag(
        'progress',
        negatable: false,
        help: 'Show upload progress.',
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
      usageException('Usage: crisp upload <local-file> <remote-dir>');
    }

    final localPath = rest[0];
    final remotePath = rest[1];
    final providerName = config.resolveProviderName(args['provider'] as String?);
    final showProgress = args['progress'] as bool;
    final asJson = args['json'] as bool;

    final localFile = File(localPath);
    if (!localFile.existsSync()) {
      stderr.writeln('Local file not found: $localPath');
      return 1;
    }

    final providerCfg = config.providerConfig(providerName);
    if (providerCfg == null) {
      stderr.writeln('Unknown provider: $providerName');
      return 1;
    }

    final fileName = p.basename(localPath);
    final data = await localFile.readAsBytes();
    final adapter = createAdapter(providerName, providerCfg);

    int lastPct = -1;
    void progressCallback(int sent, int total) {
      if (!showProgress) return;
      final pct = total > 0 ? (sent * 100 ~/ total) : 0;
      if (pct != lastPct) {
        lastPct = pct;
        stderr.write('\rUploading $fileName: $pct%');
      }
    }

    try {
      await adapter.upload(data, fileName, remotePath, onProgress: progressCallback);
      if (showProgress) stderr.writeln('');

      final result = {
        'status': 'ok',
        'local': localPath,
        'remote': p.posix.join(remotePath, fileName),
        'bytes': data.length,
        'provider': providerName,
      };

      if (asJson) {
        stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
      } else {
        stdout.writeln('Uploaded ${data.length} bytes → $providerName:${p.posix.join(remotePath, fileName)}');
      }
      return 0;
    } catch (e) {
      stderr.writeln('Upload failed: $e');
      return 1;
    } finally {
      await adapter.dispose();
    }
  }
}
