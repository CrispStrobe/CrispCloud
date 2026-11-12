import 'dart:convert';

import '../models/archive_endpoint.dart';
import '../utils/async_lock.dart';
import 'archive_publication_lease.dart';
import 'archive_publication_lease_io.dart'
    if (dart.library.js_interop) 'archive_publication_lease_web.dart'
    as leases;
import 'archive_publication_storage_io.dart'
    if (dart.library.js_interop) 'archive_publication_storage_web.dart'
    as platform;
import 'file_collection_storage.dart';

/// A bounded, atomically published intent catalog. A failed CAS stops the
/// caller before any following filesystem mutation. Lost acknowledgements are
/// accepted only when the exact proposed catalog can be read back.
class ArchivePublicationJournal {
  ArchivePublicationJournal({
    FileCollectionStorage? storage,
    Future<ArchivePublicationLease?> Function(String)? acquireLease,
  }) : storage = storage ?? platform.createArchivePublicationStorage(),
       _acquireLease = acquireLease ?? leases.acquireArchivePublicationLease;
  static const maximumRecords = 256;
  static const maximumBytes = 4 * 1024 * 1024;
  static const key = 'archive-publications-v1';
  final FileCollectionStorage storage;
  final Future<ArchivePublicationLease?> Function(String) _acquireLease;
  Future<ArchivePublicationLease?> acquirePublication(String id) =>
      _acquireLease(id);
  final _lock = AsyncLock();
  Map<String, ArchivePublicationRecord> _records = {};
  String? _raw;
  bool _initialized = false;
  List<ArchivePublicationRecord> get records =>
      List.unmodifiable(_records.values);

  Future<void> initialize() => _lock.synchronized(_load);
  Future<void> _load() async {
    final raw = await storage.read(key, maxBytes: maximumBytes);
    final records = <String, ArchivePublicationRecord>{};
    if (raw != null) {
      final value = jsonDecode(raw);
      if (value is! Map ||
          value['version'] != 1 ||
          value['records'] is! List ||
          (value['records'] as List).length > maximumRecords) {
        throw const FormatException('Invalid archive publication journal.');
      }
      for (final item in value['records'] as List) {
        final record = ArchivePublicationRecord.fromJson(
          Map<String, dynamic>.from(item as Map),
        );
        if (records.containsKey(record.id)) {
          throw const FormatException('Duplicate archive publication record.');
        }
        records[record.id] = record;
      }
    }
    _raw = raw;
    _records = records;
    _initialized = true;
  }

  Future<void> write(
    ArchivePublicationRecord record, {
    bool begin = false,
    ArchivePublicationRecord? expected,
  }) => _lock.synchronized(() async {
    if (!_initialized) await _load();
    final next = Map<String, ArchivePublicationRecord>.of(_records);
    if (begin) {
      if (next.values.any(
        (old) =>
            !old.isFinished &&
            (old.published == null || old.hasDependency) &&
            old.id != record.id &&
            old.storage == record.storage &&
            old.original.path == record.original.path,
      )) {
        throw StateError(
          'Recover the unfinished archive publication before starting another edit.',
        );
      }
      // Completed records no longer own physical recovery files.
      next.removeWhere((_, value) => value.isFinished);
    } else if (expected == null ||
        jsonEncode(next[record.id]?.toJson()) !=
            jsonEncode(expected.toJson())) {
      throw StateError(
        'The archive publication intent changed. Reload before recovering it.',
      );
    }
    next[record.id] = record;
    if (next.length > maximumRecords) {
      throw StateError('Archive publication recovery limit reached.');
    }
    final raw = jsonEncode({
      'version': 1,
      'records': next.values.map((value) => value.toJson()).toList(),
    });
    if (utf8.encode(raw).length > maximumBytes) {
      throw StateError('Archive publication recovery exceeds its byte limit.');
    }
    var acknowledged = false;
    try {
      acknowledged = await storage.compareAndSwap(key, _raw, raw);
    } catch (_) {
      try {
        acknowledged = await storage.read(key, maxBytes: maximumBytes) == raw;
      } catch (_) {
        acknowledged = false;
      }
    }
    if (!acknowledged) {
      throw StateError(
        'Archive publication intent was not durably acknowledged. No further mutation is allowed.',
      );
    }
    _records = next;
    _raw = raw;
  });
}
