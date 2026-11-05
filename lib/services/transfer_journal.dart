import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/transfer_job.dart';
import '../utils/async_lock.dart';
import 'file_operation_service.dart';
import 'transfer_journal_storage.dart';
import 'transfer_journal_storage_web.dart'
    if (dart.library.io) 'transfer_journal_storage_io.dart'
    as platform;

/// Small append-only entry checkpoints avoid rewriting a large plan after
/// every file. Loading replays exactly the records flushed before interruption.
class TransferJournal {
  TransferJournal(this.storage);
  final TransferJournalStorage storage;
  final AsyncLock _lock = AsyncLock();
  final Map<String, TransferJobRecord> _jobs = {};
  final List<String> warnings = [];
  Future<void>? _initializing;
  int _sequence = 0;

  List<TransferJobRecord> get jobs =>
      _jobs.values.toList()..sort((a, b) => b.created.compareTo(a.created));
  TransferJobRecord? job(String id) => _jobs[id];
  Future<void> initialize() => _initializing ??= _load();

  Future<void> _load() async {
    final lines = await storage.readLines();
    final valid = <String>[];
    for (var i = 0; i < lines.length; i++) {
      try {
        final event = decodeTransferEvent(lines[i]);
        if (event['sequence'] != _sequence + 1) {
          throw const FormatException(
            'Transfer journal event sequence is inconsistent.',
          );
        }
        _apply(event);
        _sequence++;
        valid.add(lines[i]);
      } catch (error) {
        if (i != lines.length - 1) rethrow;
        warnings.add(
          'An incomplete last checkpoint was retained in the previous journal: $error',
        );
        await storage.rewrite(valid);
        _jobs.clear();
        _sequence = 0;
        for (final line in valid) {
          _apply(decodeTransferEvent(line));
          _sequence++;
        }
      }
    }
    // A prior process cannot still be running these closures. Review and bind
    // real accounts before resuming; startup never starts destructive work.
    for (final job in _jobs.values) {
      if (const [
        TransferJobStatus.running,
        TransferJobStatus.queued,
        TransferJobStatus.paused,
      ].contains(job.status)) {
        job.status = TransferJobStatus.interrupted;
        job.message = 'Interrupted. Review the saved plan to resume.';
      }
    }
  }

  Future<void> _append(Map<String, dynamic> values) async {
    final event = {'version': 1, 'sequence': _sequence + 1, ...values};
    await storage.append(encodeTransferEvent(event));
    _apply(event);
    _sequence++;
  }

  void _apply(Map<String, dynamic> event) {
    if (event['version'] != 1) {
      throw const FormatException('Unsupported transfer journal version.');
    }
    final id = event['id'] as String;
    switch (event['kind']) {
      case 'header':
        if (_jobs.containsKey(id)) {
          throw const FormatException('Duplicate transfer identifier.');
        }
        _jobs[id] = TransferJobRecord.fromHeaderJson(
          Map<String, dynamic>.from(event['job'] as Map),
        );
        if (_jobs[id]!.id != id) {
          throw const FormatException('Mismatched transfer identifier.');
        }
      case 'entries':
        final job = _jobs[id];
        if (job == null) {
          throw const FormatException('Transfer header is missing.');
        }
        for (final value in event['entries'] as List) {
          final entry = TransferEntryRecord.fromJson(
            Map<String, dynamic>.from(value as Map),
          );
          if (entry.index > job.entries.length ||
              entry.index >= job.expectedEntries) {
            throw const FormatException(
              'Transfer entries are incomplete or out of order.',
            );
          }
          if (entry.index == job.entries.length) {
            job.entries.add(entry);
          } else {
            job.entries[entry.index] = entry;
          }
        }
      case 'state':
        final job = _jobs[id];
        if (job == null) {
          throw const FormatException('Transfer header is missing.');
        }
        job.status = TransferJobStatus.values.byName(event['status'] as String);
        job.updated = DateTime.parse(event['updated'] as String);
        job.message = event['message'] as String?;
        job.priority = event['priority'] as int? ?? job.priority;
        job.queueOrder = event['queueOrder'] as int? ?? job.queueOrder;
        if (event['ready'] == true) {
          if (job.entries.length != job.expectedEntries) {
            throw const FormatException(
              'The persisted transfer plan is incomplete.',
            );
          }
          job.ready = true;
        }
      case 'dismiss':
        _jobs.remove(id);
      default:
        throw const FormatException('Unknown transfer journal event.');
    }
  }

  Future<TransferJobRecord> create(
    String id,
    FileOperationPlan plan, {
    int priority = 0,
  }) async {
    await initialize();
    return _lock.synchronized(() async {
      final now = DateTime.now().toUtc();
      final record = TransferJobRecord(
        id: id,
        created: now,
        source: plan.source.storageReference,
        destination: plan.destination.storageReference,
        sourceLabel: plan.source.label,
        destinationLabel: plan.destination.label,
        targetDirectory: plan.targetDirectory,
        options: plan.options,
        protectedDestinationPaths: plan.protectedDestinationPaths,
        expectedEntries: plan.entries.length,
        priority: priority,
        queueOrder: now.microsecondsSinceEpoch,
        canRecover:
            plan.source.canRecover &&
            plan.destination.canRecover &&
            plan.source.storageReference != null &&
            plan.destination.storageReference != null,
      );
      await _append({'kind': 'header', 'id': id, 'job': record.toHeaderJson()});
      await _saveEntries(id, plan.entries);
      await _append({
        'kind': 'state',
        'id': id,
        'status': TransferJobStatus.queued.name,
        'updated': now.toIso8601String(),
        'ready': true,
      });
      return _jobs[id]!;
    });
  }

  TransferEntryRecord snapshot(
    FileOperationEntry entry,
    int index, {
    String? phase,
  }) => TransferEntryRecord(
    index: index,
    source: entry.source,
    destination: entry.destination,
    existing: entry.existing,
    outcome: entry.outcome,
    phase: phase ?? entry.recovery?['phase'] as String? ?? entry.outcome.name,
    message: entry.message,
    recovery: Map.of(entry.recovery ?? const {}),
  );

  Future<void> _saveEntries(String id, List<FileOperationEntry> entries) async {
    for (var start = 0; start < entries.length; start += 128) {
      final end = (start + 128).clamp(0, entries.length);
      await _append({
        'kind': 'entries',
        'id': id,
        'entries': [
          for (var i = start; i < end; i++) snapshot(entries[i], i).toJson(),
        ],
      });
    }
  }

  Future<void> saveEntries(String id, List<FileOperationEntry> entries) async {
    await initialize();
    await _lock.synchronized(() => _saveEntries(id, entries));
  }

  Future<void> checkpoint(
    String id,
    int index,
    FileOperationEntry entry,
    String phase,
  ) async {
    await initialize();
    await _lock.synchronized(
      () => _append({
        'kind': 'entries',
        'id': id,
        'entries': [snapshot(entry, index, phase: phase).toJson()],
      }),
    );
  }

  Future<void> setStatus(
    String id,
    TransferJobStatus status, {
    String? message,
    int? priority,
    int? queueOrder,
  }) async {
    await initialize();
    await _lock.synchronized(
      () => _append({
        'kind': 'state',
        'id': id,
        'status': status.name,
        'message': message,
        'priority': priority,
        'queueOrder': queueOrder,
        'updated': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  }

  /// Explicit history maintenance keeps the write-ahead log bounded without
  /// losing any unfinished entry or replacing it with a summary.
  Future<void> compact() async {
    await initialize();
    await _lock.synchronized(() async {
      var sequence = 0;
      final lines = <String>[];
      void add(Map<String, dynamic> event) {
        lines.add(
          encodeTransferEvent({'version': 1, 'sequence': ++sequence, ...event}),
        );
      }

      for (final job in _jobs.values) {
        add({'kind': 'header', 'id': job.id, 'job': job.toHeaderJson()});
        for (var start = 0; start < job.entries.length; start += 128) {
          final end = (start + 128).clamp(0, job.entries.length);
          add({
            'kind': 'entries',
            'id': job.id,
            'entries': [
              for (var i = start; i < end; i++) job.entries[i].toJson(),
            ],
          });
        }
        if (job.ready) {
          add({
            'kind': 'state',
            'id': job.id,
            'status': job.status.name,
            'updated': job.updated.toUtc().toIso8601String(),
            'ready': true,
            'message': job.message,
          });
        }
      }
      await storage.rewrite(lines);
      _sequence = sequence;
    });
  }

  Future<void> dismiss(String id) async {
    await initialize();
    await _lock.synchronized(() => _append({'kind': 'dismiss', 'id': id}));
  }
}

String encodeTransferEvent(Map<String, dynamic> event) {
  final payload = jsonEncode(event);
  return jsonEncode({
    'payload': payload,
    'sha256': sha256.convert(utf8.encode(payload)).toString(),
  });
}

Map<String, dynamic> decodeTransferEvent(String line) {
  final envelope = jsonDecode(line) as Map;
  final payload = envelope['payload'] as String;
  if (envelope['sha256'] != sha256.convert(utf8.encode(payload)).toString()) {
    throw const FormatException('Transfer checkpoint checksum mismatch.');
  }
  return Map<String, dynamic>.from(jsonDecode(payload) as Map);
}

final transferJournalProvider = Provider<TransferJournal>(
  (ref) => TransferJournal(platform.createTransferJournalStorage()),
);
