import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'file_collection_storage.dart';
import 'native_journal_lease.dart';

FileCollectionStorage createFileCollectionStorage({
  required Future<SharedPreferences> Function() preferences,
}) => Platform.environment.containsKey('FLUTTER_TEST')
    ? PreferencesFileCollectionStorage(preferences)
    : NativeFileCollectionStorage();

class NativeFileCollectionStorage
    implements FileCollectionStorage, FileCollectionStorageBatchWriter {
  NativeFileCollectionStorage({Future<Directory> Function()? directory})
    : _directory = directory ?? _defaultDirectory;
  final Future<Directory> Function() _directory;
  Future<Directory>? _resolvedDirectory;
  static Future<Directory> _defaultDirectory() async => Directory(
    p.join(
      (await getApplicationSupportDirectory()).path,
      'file_collections_v2',
    ),
  );
  Future<Directory> _storageDirectory() {
    final previous = _resolvedDirectory;
    if (previous != null) return previous;
    final resolving = Future<Directory>.sync(_directory);
    _resolvedDirectory = resolving;
    // A transient platform/path-provider failure must not poison this instance.
    resolving.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {
        if (identical(_resolvedDirectory, resolving)) {
          _resolvedDirectory = null;
        }
      },
    );
    return resolving;
  }

  Future<File> _file(String key) async => File(
    p.join(
      (await _storageDirectory()).path,
      '${sha256.convert(utf8.encode(key))}.json',
    ),
  );
  @override
  Future<String?> read(String key, {required int maxBytes}) async {
    final file = await _file(key);
    if (!await file.exists()) {
      return null;
    }
    if (await file.length() > maxBytes) {
      throw const FormatException(
        'Saved collection record exceeds its size limit.',
      );
    }
    final bytes = BytesBuilder(copy: false);
    await for (final part in file.openRead(0, maxBytes + 1)) {
      bytes.add(part);
      if (bytes.length > maxBytes) {
        throw const FormatException(
          'Saved collection record exceeds its size limit.',
        );
      }
    }
    return utf8.decode(bytes.takeBytes());
  }

  @override
  Future<void> write(String key, String value) =>
      writePreparedRecord(FileCollectionStorageRecord(key, value));

  /// Persist an already encoded record with the same durable publication as a
  /// normal write. Subclasses may wrap it while retaining these semantics.
  Future<void> writePreparedRecord(FileCollectionStorageRecord record) async {
    final file = await _file(record.key);
    await file.parent.create(recursive: true);
    final pending = File('${file.path}.${const Uuid().v4()}.pending');
    try {
      await pending.writeAsBytes(record.bytes, flush: true);
      await pending.rename(file.path);
    } finally {
      if (await pending.exists()) {
        await pending.delete();
      }
    }
  }

  @override
  Future<void> writeBatch(List<FileCollectionStorageRecord> records) async {
    final batch = List<FileCollectionStorageRecord>.unmodifiable(records);
    FileCollectionStorageBatch.validate(batch);
    // Future.wait's default non-eager error mode drains all four (or fewer)
    // writes before callers begin cleaning up a failed unpublished revision.
    await Future.wait([
      for (final record in batch)
        Future<void>.sync(() => writePreparedRecord(record)),
    ]);
  }

  @override
  Future<void> remove(String key) async {
    final file = await _file(key);
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<bool> compareAndSwap(
    String key,
    String? expected,
    String value,
  ) async {
    final file = await _file(key);
    await file.parent.create(recursive: true);
    // File.lock uses process-scoped fcntl locks on Unix. The shared native
    // lease uses flock / exclusive Windows handles, including across isolates.
    final lock = await tryAcquireNativeJournalLease('${file.path}.lock');
    if (lock == null) {
      return false;
    }
    try {
      final current = await read(key, maxBytes: 8 * 1024 * 1024);
      if (current != expected) {
        return false;
      }
      await write(key, value);
      return true;
    } finally {
      lock.close();
    }
  }
}
