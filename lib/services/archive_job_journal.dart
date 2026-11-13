import 'dart:convert';

import '../models/archive_job.dart';
import '../utils/async_lock.dart';
import 'archive_publication_storage_io.dart'
    if (dart.library.js_interop) 'archive_publication_storage_web.dart'
    as platform;
import 'file_collection_storage.dart';

/// Job intent survives process loss. Candidate bytes and passwords are never
/// stored here. A lost write acknowledgement is accepted only by exact readback.
class ArchiveJobJournal {
  ArchiveJobJournal({FileCollectionStorage? storage})
    : storage = storage ?? platform.createArchivePublicationStorage();
  static const key = 'archive-creation-jobs-v1';
  static const maximumJobs = 128;
  static const maximumBytes = 4 * 1024 * 1024;
  final FileCollectionStorage storage;
  final _lock = AsyncLock();
  String? _raw;
  List<ArchiveJobRecord> _records = [];
  bool _loaded = false;
  bool _paused = false;
  bool get paused => _paused;
  List<ArchiveJobRecord> get records => List.unmodifiable(_records);

  Future<void> load() => _lock.synchronized(_load);
  Future<void> _load() async {
    final raw = await storage.read(key, maxBytes: maximumBytes);
    final records = <ArchiveJobRecord>[];
    var paused = false;
    if (raw != null) {
      final value = jsonDecode(raw);
      if (value is! Map ||
          value['version'] != 1 ||
          value['records'] is! List ||
          value['paused'] is! bool ||
          (value['records'] as List).length > maximumJobs) {
        throw const FormatException('Invalid archive job journal.');
      }
      final ids = <String>{};
      for (final saved in value['records'] as List) {
        final record = ArchiveJobRecord.fromJson(
          Map<String, dynamic>.from(saved as Map),
        );
        if (!ids.add(record.id))
          throw const FormatException('Duplicate archive job.');
        records.add(record);
      }
      paused = value['paused'] as bool;
    }
    _raw = raw;
    _records = records;
    _paused = paused;
    _loaded = true;
  }

  Future<void> replace(List<ArchiveJobRecord> records, {bool? paused}) =>
      _lock.synchronized(() async {
        if (!_loaded) await _load();
        final owned = List<ArchiveJobRecord>.unmodifiable(records);
        if (owned.length > maximumJobs ||
            owned.map((r) => r.id).toSet().length != owned.length) {
          throw StateError(
            'Archive job history is full or contains duplicate jobs.',
          );
        }
        // Round-trip validation prevents callers from publishing unvalidated states.
        for (final record in owned) {
          ArchiveJobRecord.fromJson(Map<String, dynamic>.from(record.toJson()));
        }
        final nextPaused = paused ?? _paused;
        final raw = jsonEncode({
          'version': 1,
          'paused': nextPaused,
          'records': owned.map((r) => r.toJson()).toList(),
        });
        if (utf8.encode(raw).length > maximumBytes) {
          throw StateError('Archive job history exceeds its metadata limit.');
        }
        var acknowledged = false;
        try {
          acknowledged = await storage.compareAndSwap(key, _raw, raw);
        } catch (_) {
          try {
            acknowledged =
                await storage.read(key, maxBytes: maximumBytes) == raw;
          } catch (_) {
            /* Preserve the last known intent; no worker may commit. */
          }
        }
        if (!acknowledged) {
          throw StateError(
            'Archive job checkpoint was not durably acknowledged. Reload the job history before continuing.',
          );
        }
        _raw = raw;
        _records = owned;
        _paused = nextPaused;
      });
}
