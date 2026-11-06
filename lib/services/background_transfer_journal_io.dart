import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'background_transfer_journal_types.dart';
import 'native_journal_lease.dart';
import 'transfer_journal.dart';
import 'transfer_journal_storage.dart';
import 'transfer_journal_storage_io.dart';

Future<Directory> _root(String? path) async => Directory(
  path ??
      p.join(
        (await getApplicationSupportDirectory()).path,
        'transfer_jobs',
        'background',
      ),
);

/// Each background invocation owns a private write-ahead log and a native lease.
/// The foreground never opens an active writer's journal, even in another
/// isolate of the same process. A new invocation always gets a new directory.
Future<BackgroundTransferJournalRun> createBackgroundTransferJournalRun({
  String? rootPath,
}) async {
  final root = await _root(rootPath);
  await root.create(recursive: true);
  final directory = await root.createTemp('run-');
  final lease = await tryAcquireNativeJournalLease(
    p.join(directory.path, 'owner.lock'),
  );
  if (lease == null) {
    throw StateError('A new background journal is unexpectedly busy.');
  }
  try {
    // Publish an empty log only after owning the lease. Discovery ignores a
    // directory without a log so it cannot remove a run between mkdir and
    // lease acquisition. Closed runs with no transfers remain cleanable.
    final journalFile = File(p.join(directory.path, 'journal.jsonl'));
    await journalFile.writeAsString('', flush: true);
    var open = true;
    Future<void>? closing;
    final journal = TransferJournal(
      _LeasedStorage(
        NativeTransferJournalStorage(file: () async => journalFile),
        () => open,
      ),
    );
    await journal.initialize();
    return BackgroundTransferJournalRun(
      journal: journal,
      directoryPath: directory.path,
      close: () {
        return closing ??= journal.closeWrites().whenComplete(() {
          open = false;
          lease.close();
        });
      },
    );
  } catch (_) {
    lease.close();
    rethrow;
  }
}

class _LeasedStorage implements TransferJournalStorage {
  _LeasedStorage(this.storage, this.isOpen);
  final TransferJournalStorage storage;
  final bool Function() isOpen;
  void _check() {
    if (!isOpen()) throw StateError('The background journal lease has closed.');
  }

  @override
  Future<List<String>> readLines() {
    _check();
    return storage.readLines();
  }

  @override
  Future<void> append(String line) {
    _check();
    return storage.append(line);
  }

  @override
  Future<void> rewrite(List<String> lines) {
    _check();
    return storage.rewrite(lines);
  }
}

/// Import only runs whose OS lease can be acquired. Completion markers are
/// appended to the foreground journal, so partial import, cleanup failure and
/// repeated discovery never replay a job or overwrite its reviewed progress.
Future<BackgroundJournalImport> importBackgroundTransferJournals(
  TransferJournal destination, {
  String? rootPath,
}) async {
  if (rootPath == null && Platform.environment.containsKey('FLUTTER_TEST')) {
    return const BackgroundJournalImport();
  }
  final root = await _root(rootPath);
  if (!await root.exists()) return const BackgroundJournalImport();
  await destination.initialize();
  var imported = 0;
  var active = 0;
  final warnings = <String>[];
  await for (final entity in root.list(followLinks: false)) {
    if (entity is! Directory || !p.basename(entity.path).startsWith('run-')) {
      continue;
    }
    final journalFile = File(p.join(entity.path, 'journal.jsonl'));
    // Do not follow a substituted journal or run-directory link.
    if (await FileSystemEntity.type(entity.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      continue;
    }
    final journalKind = await FileSystemEntity.type(
      journalFile.path,
      followLinks: false,
    );
    if (journalKind != FileSystemEntityType.file &&
        journalKind != FileSystemEntityType.notFound) {
      warnings.add('Background journal is not a regular file: ${entity.path}');
      continue;
    }
    if (journalKind == FileSystemEntityType.notFound) {
      final previousKind = await FileSystemEntity.type(
        '${journalFile.path}.previous',
        followLinks: false,
      );
      // The creator may not have acquired its lease or published its empty log
      // yet. A previous regular log still permits crash recovery.
      if (previousKind == FileSystemEntityType.notFound) continue;
      if (previousKind != FileSystemEntityType.file) {
        warnings.add(
          'Background recovery journal is not a regular file: ${entity.path}',
        );
        continue;
      }
    }
    NativeJournalLease? lease;
    var complete = false;
    try {
      lease = await tryAcquireNativeJournalLease(
        p.join(entity.path, 'owner.lock'),
      );
      if (lease == null) {
        active++;
        continue;
      }
      final source = TransferJournal(
        NativeTransferJournalStorage(file: () async => journalFile),
      );
      await source.initialize();
      for (final job in source.jobs) {
        final id =
            'bg_${sha256.convert(utf8.encode('${p.basename(entity.path)}\u0000${job.id}'))}';
        if (await destination.importRecord(job, importedId: id)) imported++;
      }
      warnings.addAll(
        source.warnings.map((warning) => '${entity.path}: $warning'),
      );
      final reviewMarker = File(p.join(entity.path, 'needs-review.txt'));
      if (source.warnings.isNotEmpty) {
        await reviewMarker.writeAsString(
          source.warnings.join('\n'),
          flush: true,
        );
      }
      complete = !await reviewMarker.exists();
      if (!complete) {
        warnings.add(
          'Background journal diagnostics retained for review: ${entity.path}',
        );
      }
    } catch (error) {
      warnings.add(
        'Background transfer recovery retained ${entity.path}: $error',
      );
    } finally {
      lease?.close();
    }
    if (complete) {
      // A run is never reopened by its writer after releasing its lease. An
      // importer racing this cleanup only sees durable, idempotent imports.
      try {
        await entity.delete(recursive: true);
      } on FileSystemException catch (error) {
        if (await entity.exists()) {
          warnings.add('Imported journal retained for cleanup: $error');
        }
      }
    }
  }
  return BackgroundJournalImport(
    importedJobs: imported,
    activeRuns: active,
    warnings: List.unmodifiable(warnings),
  );
}
