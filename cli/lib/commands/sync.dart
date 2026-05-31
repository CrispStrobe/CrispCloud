// lib/commands/sync.dart
//
// crisp sync <local-dir> <remote-path> [--delete] [--provider <name>] [--dry-run] [--json]
//
// Direction: local → remote (one-way upload sync).
// Compares by filename presence only (v1 — not modification time / checksum).
// With --delete, remote files absent from local are removed.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../adapters/cli_adapter_factory.dart';
import '../adapters/cli_storage_client.dart';
import '../config/cli_config.dart';

class SyncCommand extends Command<int> {
  @override
  final String name = 'sync';

  @override
  final String description =
      'Sync a local directory to a remote path (local → remote).';

  @override
  String get invocation =>
      'crisp sync <local-dir> <remote-path> [--delete] [options]';

  final CliConfig config;

  SyncCommand(this.config) {
    argParser
      ..addOption('provider', abbr: 'p', help: 'Provider name.')
      ..addFlag(
        'delete',
        negatable: false,
        help: 'Delete remote files that are absent locally.',
      )
      ..addFlag(
        'dry-run',
        abbr: 'n',
        negatable: false,
        help: 'Show what would be done without actually doing it.',
      )
      ..addFlag(
        'json',
        abbr: 'j',
        negatable: false,
        help: 'Output result as JSON.',
      )
      ..addFlag(
        'verbose',
        abbr: 'v',
        negatable: false,
        help: 'Verbose output.',
      );
  }

  @override
  Future<int> run() async {
    final args = argResults!;
    final rest = args.rest;

    if (rest.length < 2) {
      usageException('Usage: crisp sync <local-dir> <remote-path>');
    }

    final localDir = rest[0];
    final remotePath = rest[1];
    final providerName = config.resolveProviderName(args['provider'] as String?);
    final delete = args['delete'] as bool;
    final dryRun = args['dry-run'] as bool;
    final asJson = args['json'] as bool;
    final verbose = args['verbose'] as bool;

    final localDirObj = Directory(localDir);
    if (!localDirObj.existsSync()) {
      stderr.writeln('Local directory not found: $localDir');
      return 1;
    }

    final providerCfg = config.providerConfig(providerName);
    if (providerCfg == null) {
      stderr.writeln('Unknown provider: $providerName');
      return 1;
    }

    final adapter = createAdapter(providerName, providerCfg);
    final log = <Map<String, dynamic>>[];

    try {
      // Get local files (shallow for v1)
      final localFiles = localDirObj
          .listSync()
          .whereType<File>()
          .map((f) => p.basename(f.path))
          .toSet();

      // Get remote files
      List<CliFileItem> remoteItems;
      try {
        remoteItems = await adapter.list(remotePath);
      } catch (_) {
        // Remote path may not exist yet — create it
        if (!dryRun) {
          await adapter.createDirectory(remotePath);
        }
        remoteItems = [];
      }
      final remoteFiles = {
        for (final i in remoteItems.where((i) => !i.isDirectory)) i.name: i
      };

      // Upload local files missing or outdated remotely
      for (final fileName in localFiles) {
        final localFile = File(p.join(localDir, fileName));
        if (!remoteFiles.containsKey(fileName)) {
          final action = {
            'action': 'upload',
            'file': fileName,
            'status': dryRun ? 'dry-run' : 'pending',
          };
          if (verbose || dryRun) {
            stderr.writeln('[UPLOAD] $fileName');
          }
          if (!dryRun) {
            try {
              final data = await localFile.readAsBytes();
              await adapter.upload(data, fileName, remotePath);
              action['status'] = 'ok';
            } catch (e) {
              action['status'] = 'error';
              action['error'] = e.toString();
              stderr.writeln('Failed to upload $fileName: $e');
            }
          }
          log.add(action);
        }
      }

      // Delete remote files absent locally (if --delete)
      if (delete) {
        for (final fileName in remoteFiles.keys) {
          if (!localFiles.contains(fileName)) {
            final action = {
              'action': 'delete',
              'file': fileName,
              'status': dryRun ? 'dry-run' : 'pending',
            };
            if (verbose || dryRun) {
              stderr.writeln('[DELETE] $fileName');
            }
            if (!dryRun) {
              try {
                await adapter.delete(remoteFiles[fileName]!.path);
                action['status'] = 'ok';
              } catch (e) {
                action['status'] = 'error';
                action['error'] = e.toString();
                stderr.writeln('Failed to delete $fileName: $e');
              }
            }
            log.add(action);
          }
        }
      }

      final summary = {
        'provider': providerName,
        'local': localDir,
        'remote': remotePath,
        'dry_run': dryRun,
        'uploaded': log.where((e) => e['action'] == 'upload').length,
        'deleted': log.where((e) => e['action'] == 'delete').length,
        'actions': log,
      };

      if (asJson) {
        stdout.writeln(const JsonEncoder.withIndent('  ').convert(summary));
      } else {
        final uploaded = log.where((e) => e['action'] == 'upload').length;
        final deleted = log.where((e) => e['action'] == 'delete').length;
        stdout.writeln(
          dryRun
              ? 'Dry run: would upload $uploaded, delete $deleted'
              : 'Sync complete: uploaded $uploaded, deleted $deleted',
        );
      }
      return 0;
    } catch (e) {
      stderr.writeln('Sync failed: $e');
      return 1;
    } finally {
      await adapter.dispose();
    }
  }
}
