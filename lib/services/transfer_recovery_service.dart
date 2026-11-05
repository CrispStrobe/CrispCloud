import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/file_item.dart';
import '../models/transfer_job.dart';
import 'file_operation_service.dart';
import 'transfer_journal.dart';

String? transferFileVersion(FileItem file) {
  for (final key in ['version', 'versionId', 'eTag', 'etag', 'rev', 'cTag']) {
    if (file.metadata?[key] != null) return file.metadata![key].toString();
  }
  return null;
}

String? _stableObjectId(FileItem file) {
  final id = file.uuid;
  if (id == null ||
      id == file.path ||
      id.startsWith('/') ||
      RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(id)) {
    return null;
  }
  return id;
}

bool sameTransferVersion(FileItem before, FileItem after) =>
    before.isFolder == after.isFolder &&
    (before.isSymlink == true) == (after.isSymlink == true) &&
    before.symlinkTarget == after.symlinkTarget &&
    (before.isFolder || (before.size == null || before.size == after.size)) &&
    (before.isFolder ||
        before.updatedAt == null ||
        (after.updatedAt != null &&
            before.updatedAt!.isAtSameMomentAs(after.updatedAt!))) &&
    transferFileVersion(before) == transferFileVersion(after) &&
    (_stableObjectId(before) == null ||
        _stableObjectId(before) == _stableObjectId(after));

void _check(FileOperationBackend backend, FileOperationControl control) {
  if (!backend.isCurrent) {
    throw StateError('The original storage account is no longer connected.');
  }
  if (control.isCancelled) throw const FileOperationCancelled();
}

Future<String> transferDigest(
  FileOperationBackend backend,
  FileItem file,
  FileOperationControl control, {
  int? prefixLength,
}) async {
  await control.checkpoint();
  _check(backend, control);
  if (file.isSymlink == true) {
    return sha256.convert(utf8.encode('link:${file.symlinkTarget}')).toString();
  }
  if (file.isFolder) throw StateError('A directory is not a content stream.');
  var count = 0;
  Stream<List<int>> contents() async* {
    if (prefixLength == 0) return;
    await for (final chunk in control.bind(backend.readFile(file))) {
      await control.checkpoint();
      _check(backend, control);
      final remaining = prefixLength == null
          ? chunk.length
          : prefixLength - count;
      final part = chunk.length > remaining
          ? chunk.sublist(0, remaining)
          : chunk;
      count += part.length;
      yield part;
      if (prefixLength != null && count == prefixLength) break;
    }
  }

  final digest = await sha256.bind(contents()).first;
  final expected = prefixLength ?? file.size;
  if (expected != null && count != expected) {
    throw StateError('The source length changed while validating it.');
  }
  final current = await backend.stat(file.path!);
  if (current == null || !sameTransferVersion(file, current)) {
    throw StateError('The file changed while validating its contents.');
  }
  return digest.toString();
}

/// Connects operation checkpoints to the durable log. Native/legacy files use
/// a source digest; providers with immutable revision tokens keep fast copies
/// server-side and record the confirmed destination version instead.
class JournaledTransferRunner {
  const JournaledTransferRunner(this.journal);
  final TransferJournal journal;

  Future<void> execute(
    String id,
    FileOperationPlan plan, {
    required FileOperationControl control,
    FileConflictResolver? resolveConflict,
    DetailedFileConflictResolver? resolveDetailedConflict,
    void Function(FileOperationEntry, int, int?)? onProgress,
    void Function(FileOperationEntry)? onEntryComplete,
    void Function(FileOperationEntry, String)? onPhase,
  }) async {
    await journal.setStatus(id, TransferJobStatus.running);
    final indices = {
      for (var i = 0; i < plan.entries.length; i++) plan.entries[i]: i,
    };
    final validated = <FileOperationEntry>{};
    try {
      await const FileOperationService().execute(
        plan,
        control: control,
        resolveConflict: resolveConflict,
        resolveDetailedConflict: resolveDetailedConflict,
        onProgress: onProgress,
        onEntryComplete: onEntryComplete,
        checkpoint: (entry, phase) async {
          entry.recovery = {
            ...?entry.recovery,
            'phase': phase,
            if (const [
              'writing',
              'committing',
              'backingUp',
              'renamingExisting',
              'deletingSource',
              'deletingSourceDirectory',
            ].contains(phase))
              'lastMutationPhase': phase,
          };
          onPhase?.call(entry, phase);
          if (const ['writing', 'finishingCopy'].contains(phase) &&
              !entry.source.isFolder &&
              validated.add(entry)) {
            final current = await plan.source.stat(entry.source.path!);
            if (current == null ||
                !sameTransferVersion(entry.source, current)) {
              throw StateError(
                'The source changed after the transfer was planned.',
              );
            }
            final expected = entry.recovery?['sourceSha256'] as String?;
            if (expected != null ||
                transferFileVersion(entry.source) == null ||
                entry.source.isSymlink == true) {
              final digest = await transferDigest(
                plan.source,
                current,
                control,
              );
              if (expected != null && digest != expected) {
                throw StateError(
                  'The source contents changed since the saved transfer.',
                );
              }
              entry.recovery = {...?entry.recovery, 'sourceSha256': digest};
            }
          }
          if (const ['backingUp', 'renamingExisting'].contains(phase) &&
              entry.existing != null) {
            final current = await plan.destination.stat(entry.existing!.path!);
            if (current == null ||
                !sameTransferVersion(entry.existing!, current)) {
              throw StateError('The destination changed before replacement.');
            }
            entry.recovery = {
              ...?entry.recovery,
              'backupSha256': await transferDigest(
                plan.destination,
                current,
                control,
              ),
            };
          }
          if (const ['staged', 'committing', 'verified'].contains(phase) &&
              !entry.source.isFolder) {
            final current = await plan.source.stat(entry.source.path!);
            if (current == null ||
                !sameTransferVersion(entry.source, current)) {
              throw StateError(
                'The source changed during transfer; it was retained.',
              );
            }
            final content = entry.recovery?['contentSha256'];
            final source = entry.recovery?['sourceSha256'];
            if (entry.recovery?['append'] != true &&
                content != null &&
                source != null &&
                content != source) {
              throw StateError(
                'Copied bytes no longer match the source captured before transfer.',
              );
            }
          }
          if (phase == 'verified' && !entry.source.isFolder) {
            final written = await plan.destination.stat(entry.destination);
            if (written == null) {
              throw StateError('The destination is missing after copying.');
            }
            var digest = entry.recovery?['contentSha256'] as String?;
            final sourceDigest = entry.recovery?['sourceSha256'] as String?;
            if (digest == null &&
                (sourceDigest != null ||
                    transferFileVersion(written) == null)) {
              digest = await transferDigest(plan.destination, written, control);
              if (sourceDigest != null &&
                  entry.recovery?['append'] != true &&
                  digest != sourceDigest) {
                throw StateError(
                  'The copied destination differs from the captured source.',
                );
              }
            }
            entry.recovery = {
              ...?entry.recovery,
              'destinationSnapshot': transferFileJson(written),
              if (digest != null) 'contentSha256': digest,
              'dataVerified': true,
            };
          }
          await journal.checkpoint(id, indices[entry]!, entry, phase);
        },
      );
      await journal.saveEntries(id, plan.entries);
      final waiting = plan.entries.any(
        (entry) => entry.outcome == FileOperationOutcome.needsDecision,
      );
      final failed = plan.entries.any((entry) => entry.failed);
      final cancelled =
          control.isCancelled ||
          plan.entries.any(
            (entry) => entry.outcome == FileOperationOutcome.cancelled,
          );
      await journal.setStatus(
        id,
        waiting
            ? TransferJobStatus.waitingForDecision
            : failed
            ? TransferJobStatus.failed
            : cancelled
            ? TransferJobStatus.cancelled
            : TransferJobStatus.completed,
        message: waiting
            ? 'Waiting for a conflict decision.'
            : failed
            ? 'Some items need review. Completed items are retained.'
            : cancelled
            ? 'Stopped. Review saved progress to resume.'
            : null,
      );
    } catch (error) {
      await journal.setStatus(id, TransferJobStatus.failed, message: '$error');
      rethrow;
    }
  }
}

enum TransferRecoveryMode { retryRemaining, restartIncomplete }

class TransferRecoveryPreview {
  const TransferRecoveryPreview({
    required this.plan,
    required this.issues,
    required this.actions,
  });
  final FileOperationPlan plan;
  final Map<int, String> issues;
  final Map<int, String> actions;

  FileOperationPlan excluding(Set<int> skipped) {
    final rows = <FileOperationEntry>[];
    for (var i = 0; i < plan.entries.length; i++) {
      final old = plan.entries[i];
      final entry =
          FileOperationEntry(
              old.source,
              old.destination,
              existing: old.existing,
            )
            ..outcome = skipped.contains(i)
                ? FileOperationOutcome.skipped
                : old.outcome
            ..message = skipped.contains(i)
                ? 'Excluded during recovery review.'
                : old.message
            ..recovery = old.recovery == null ? null : Map.of(old.recovery!);
      rows.add(entry);
    }
    return FileOperationPlan(
      source: plan.source,
      destination: plan.destination,
      targetDirectory: plan.targetDirectory,
      protectedDestinationPaths: plan.protectedDestinationPaths,
      options: plan.options,
      entries: rows,
      errors: [
        ...plan.errors,
        for (final issue in issues.entries)
          if (!skipped.contains(issue.key)) issue.value,
      ],
    );
  }
}

/// Builds a read-only recovery preview. Ambiguous destinations and changed
/// sources are issues, never an invitation to overwrite/delete automatically.
class TransferRecoveryService {
  const TransferRecoveryService();

  Future<TransferRecoveryPreview> prepare(
    TransferJobRecord job, {
    required FileOperationBackend source,
    required FileOperationBackend destination,
    required FileOperationControl control,
    TransferRecoveryMode mode = TransferRecoveryMode.retryRemaining,
    void Function(int, int)? onProgress,
  }) async {
    if (!job.ready ||
        job.entries.length != job.expectedEntries ||
        !job.canRecover ||
        job.source != source.storageReference ||
        job.destination != destination.storageReference ||
        !source.isCurrent ||
        !destination.isCurrent) {
      throw StateError(
        'Reconnect the exact original source and destination before recovering this transfer.',
      );
    }
    final protected = FileOperationPlan(
      source: source,
      destination: destination,
      targetDirectory: job.targetDirectory,
      options: job.options,
      entries: [],
      errors: [],
      protectedDestinationPaths: job.protectedDestinationPaths,
    );
    final rows = <FileOperationEntry>[];
    final issues = <int, String>{};
    final actions = <int, String>{};
    for (final saved in job.entries) {
      await control.checkpoint();
      _check(source, control);
      _check(destination, control);
      final entry =
          FileOperationEntry(
              saved.source,
              saved.destination,
              existing: saved.existing,
            )
            ..outcome = saved.outcome
            ..message = saved.message
            ..recovery = (Map<String, dynamic>.of(saved.recovery)
              ..remove('resumeAfterCommit')
              ..remove('resumeStagePath'));
      rows.add(entry);
      onProgress?.call(rows.length, job.entries.length);
      if (const [
            FileOperationOutcome.copied,
            FileOperationOutcome.moved,
            FileOperationOutcome.skipped,
            FileOperationOutcome.filtered,
          ].contains(saved.outcome) ||
          (saved.outcome == FileOperationOutcome.directoryCreated &&
              job.options.kind == FileOperationKind.copy)) {
        actions[saved.index] = 'Keep previous ${saved.outcome.name} result';
        continue;
      }
      entry.outcome = FileOperationOutcome.pending;
      entry.message = null;
      try {
        if (!source.paths.isAbsolute(saved.source.path!) ||
            !destination.paths.isAbsolute(saved.destination)) {
          throw StateError('The saved transfer contains a relative path.');
        }
        protected.assertDestinationUnprotected(saved.destination);
        final current = await source.stat(saved.source.path!);
        final target = await destination.stat(saved.destination);
        final expectedDigest =
            saved.recovery['contentSha256'] as String? ??
            (saved.recovery['append'] == true
                ? null
                : saved.recovery['sourceSha256'] as String?);
        var targetVerified = false;
        if (target != null &&
            !target.isFolder &&
            (target.isSymlink == true) == (saved.source.isSymlink == true)) {
          if (expectedDigest != null) {
            targetVerified =
                await transferDigest(destination, target, control) ==
                expectedDigest;
          } else if (saved.recovery['dataVerified'] == true &&
              saved.recovery['destinationSnapshot'] is Map) {
            final snapshot = transferFileFromJson(
              Map<String, dynamic>.from(
                saved.recovery['destinationSnapshot'] as Map,
              ),
            );
            targetVerified =
                transferFileVersion(snapshot) != null &&
                sameTransferVersion(snapshot, target);
          } else if (current == null && _stableObjectId(saved.source) != null) {
            targetVerified =
                _stableObjectId(saved.source) == _stableObjectId(target) &&
                transferFileVersion(saved.source) != null &&
                transferFileVersion(saved.source) ==
                    transferFileVersion(target);
          }
        }
        if (current == null) {
          if (job.options.kind == FileOperationKind.move && targetVerified) {
            entry.outcome = FileOperationOutcome.moved;
            entry.message = 'Recovered a confirmed move after interruption.';
            actions[saved.index] = entry.message!;
            continue;
          }
          if (saved.source.isFolder &&
              target?.isFolder == true &&
              saved.recovery['lastMutationPhase'] ==
                  'deletingSourceDirectory') {
            entry.outcome = FileOperationOutcome.moved;
            actions[saved.index] = 'Recovered empty-directory cleanup';
            continue;
          }
          throw StateError(
            'Source is missing and completion cannot be verified: ${saved.source.path}',
          );
        }
        if (!sameTransferVersion(saved.source, current)) {
          throw StateError(
            'Source changed since the saved transfer: ${saved.source.path}',
          );
        }
        final sourceDigest = saved.recovery['sourceSha256'] as String?;
        if (sourceDigest != null &&
            await transferDigest(source, current, control) != sourceDigest) {
          throw StateError(
            'Source contents changed since the saved transfer: ${saved.source.path}',
          );
        }
        if (!saved.source.isFolder &&
            targetVerified &&
            mode == TransferRecoveryMode.retryRemaining) {
          entry.recovery = {
            ...?entry.recovery,
            'resumeAfterCommit': true,
            'contentSha256':
                expectedDigest ??
                await transferDigest(destination, target!, control),
          };
          actions[saved.index] =
              'Keep verified copy; finish metadata and source cleanup';
          continue;
        }
        if (target != null &&
            mode == TransferRecoveryMode.retryRemaining &&
            !saved.source.isFolder &&
            !targetVerified &&
            (saved.existing == null ||
                !sameTransferVersion(saved.existing!, target))) {
          throw StateError(
            'Destination changed or has an unconfirmed copy: ${saved.destination}',
          );
        }
        final stagePath = saved.recovery['stagedPath'] as String?;
        if (mode == TransferRecoveryMode.retryRemaining &&
            stagePath != null &&
            !saved.source.isFolder) {
          final parent = destination.paths.dirname(saved.destination);
          final relative = destination.paths.relative(stagePath, from: parent);
          if (!destination.isWithin(parent, stagePath) ||
              !destination.paths
                  .split(relative)
                  .first
                  .startsWith('.crisp-transfer-')) {
            throw StateError(
              'The saved staging path is outside the reviewed destination.',
            );
          }
          final staged = await destination.stat(stagePath);
          if (staged != null) {
            if (staged.isFolder ||
                staged.isSymlink == true ||
                staged.size == null ||
                current.size == null ||
                staged.size! > current.size! ||
                await transferDigest(destination, staged, control) !=
                    await transferDigest(
                      source,
                      current,
                      control,
                      prefixLength: staged.size,
                    )) {
              throw StateError(
                'The saved partial copy does not match the original source.',
              );
            }
            entry.recovery = {...?entry.recovery, 'resumeStagePath': stagePath};
            actions[saved.index] =
                'Resume from ${staged.size} verified staged bytes';
          } else {
            actions[saved.index] = 'Retry remaining item';
          }
        } else {
          actions[saved.index] = mode == TransferRecoveryMode.restartIncomplete
              ? 'Restart this incomplete item; review any conflict'
              : 'Retry remaining item';
        }
      } catch (error) {
        issues[saved.index] = error.toString();
        actions[saved.index] = 'Needs review';
      }
    }
    final options = FileOperationOptions.fromJson({
      ...job.options.toJson(),
      // Restarts that would touch an existing destination require a new choice.
      if (mode == TransferRecoveryMode.restartIncomplete)
        'fileConflict': FileConflictPolicy.ask.name,
    });
    return TransferRecoveryPreview(
      plan: FileOperationPlan(
        source: source,
        destination: destination,
        targetDirectory: job.targetDirectory,
        protectedDestinationPaths: job.protectedDestinationPaths,
        options: options,
        entries: rows,
        errors: [],
      ),
      issues: issues,
      actions: actions,
    );
  }

  Future<void> restoreBackup(
    TransferJobRecord job,
    TransferEntryRecord entry,
    FileOperationBackend destination,
    FileOperationControl control, {
    Future<void> Function(String phase)? checkpoint,
  }) async {
    if (job.destination != destination.storageReference ||
        !destination.isCurrent) {
      throw StateError(
        'Reconnect the original destination before restoring a recovery copy.',
      );
    }
    final path =
        entry.recovery['backupPath'] as String? ??
        entry.recovery['renamedExistingPath'] as String?;
    final expected = entry.recovery['backupSha256'] as String?;
    if (path == null ||
        expected == null ||
        !destination.isWithin(
          destination.paths.dirname(entry.destination),
          path,
        )) {
      throw StateError('There is no verified backup for this item.');
    }
    final existing = await destination.stat(entry.destination);
    if (existing != null) {
      if (entry.phase == 'restoringBackup' &&
          await destination.stat(path) == null &&
          await transferDigest(destination, existing, control) == expected) {
        await checkpoint?.call('backupRestored');
        return;
      }
      throw StateError(
        'The original destination is occupied. Move it aside before restoring.',
      );
    }
    final backup = await destination.stat(path);
    if (backup == null ||
        await transferDigest(destination, backup, control) != expected) {
      throw StateError('The saved backup changed or is unavailable.');
    }
    final plan = FileOperationPlan(
      source: destination,
      destination: destination,
      targetDirectory: job.targetDirectory,
      options: job.options,
      entries: [],
      errors: [],
      protectedDestinationPaths: job.protectedDestinationPaths,
    );
    plan.assertDestinationUnprotected(path);
    plan.assertDestinationUnprotected(entry.destination);
    await control.checkpoint();
    _check(destination, control);
    await checkpoint?.call('restoringBackup');
    final currentBackup = await destination.stat(path);
    if (currentBackup == null || !sameTransferVersion(backup, currentBackup)) {
      throw StateError('The recovery copy changed before restoration.');
    }
    await destination.renameExisting(backup, entry.destination);
    final restored = await destination.stat(entry.destination);
    if (restored == null ||
        await transferDigest(destination, restored, control) != expected) {
      throw StateError(
        'The restored copy needs review; its contents could not be confirmed.',
      );
    }
    await checkpoint?.call('backupRestored');
  }
}
