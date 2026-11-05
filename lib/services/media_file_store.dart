import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/file_item.dart';
import 'cloud_storage_interface.dart';
import 'file_cache_service.dart';
import 'local_file_service.dart';
import 'log_service.dart';

const kMediaLocalFileLimitBytes = 2 * 1024 * 1024 * 1024;

/// The shared cloud API may buffer even when supportsStreaming is true.
/// Keep its first media integration within a conservative transfer budget.
const kMediaRemoteTransferLimitBytes = 64 * 1024 * 1024;

enum MediaSaveOutcome { savedCopy }

enum MediaStoreFailure {
  accountChanged,
  tooLarge,
  invalidName,
  nameConflict,
  unverifiedDestination,
  sourceChanged,
  sourceUnavailable,
  accessDenied,
  busy,
  unsupported,
  notStaged,
  emptyOutput,
  invalidOutput,
}

class MediaStoreException implements Exception {
  const MediaStoreException(this.reason, {this.limitBytes});

  final MediaStoreFailure reason;
  final int? limitBytes;

  @override
  String toString() => 'MediaStoreException(${reason.name})';
}

/// A media editor's captured origin and private, file-based working directory.
///
/// [stage] bypasses preview caches and creates an immutable source snapshot.
/// Renderers write only to paths issued by [createOutputPath]. [saveCopy]
/// creates a separate file in the captured origin's directory; it never writes
/// the source. Failed saves keep the rendered file available for retry.
///
/// Local copies reserve an unused name with exclusive creation before writing.
/// As with the existing document writer, Dart cannot prevent another process
/// replacing that reservation. Cloud adapters have no conditional-create API:
/// remote copies reject existing names and require a verified parent listing,
/// but that is a preflight check, not an atomic no-overwrite guarantee. The host
/// should suggest a collision-resistant name for each export.
///
/// A remote account change aborts access. If it happens while an upload is
/// already in flight, the provider might have completed the copy; the host must
/// not report a clean save to the newly selected account. The host also owns
/// refreshing the originating panel after a successful copy.
///
/// Finish/cancel the renderer before [dispose]. Disposal waits for active store
/// operations and removes only this editor's private temporary directory.
abstract class MediaFileStore {
  MediaFileStore();

  factory MediaFileStore.local({
    required LocalFileService service,
    required FileItem file,
    int inputLimitBytes,
    int outputLimitBytes,
    String? temporaryDirectory,
  }) = _LocalMediaFileStore;

  factory MediaFileStore.remote({
    required CloudStorageClient client,
    required String providerName,
    required FileCacheService cache,
    required FileItem file,
    required bool Function() isCurrentAccount,
    int transferLimitBytes,
    String? temporaryDirectory,
  }) = _RemoteMediaFileStore;

  String get documentId;
  String get displayName;
  String get path;
  bool get isRemote;

  Future<String> stage();
  Future<String> createOutputPath(String extension);
  Future<MediaSaveOutcome> saveCopy(String renderedPath, String fileName);
  Future<void> dispose();
}

abstract class _MediaFileStoreBase extends MediaFileStore {
  _MediaFileStoreBase({
    required this.file,
    required this.path,
    required this.inputLimitBytes,
    required this.outputLimitBytes,
    required this.temporaryDirectory,
  }) {
    if (inputLimitBytes <= 0 || outputLimitBytes <= 0) {
      throw ArgumentError('Media file limits must be positive.');
    }
  }

  static const _log = Log('MediaFileStore');
  final FileItem file;
  @override
  final String path;
  final int inputLimitBytes;
  final int outputLimitBytes;
  final String? temporaryDirectory;
  Directory? _workspace;
  String? _snapshot;
  final Set<String> _outputs = {};
  int _outputSequence = 0;
  Future<void>? _activeOperation;
  Future<void>? _disposal;
  bool _disposed = false;

  @override
  String get displayName => file.name;

  void assertAvailable() {
    if (kIsWeb) throw const MediaStoreException(MediaStoreFailure.unsupported);
    if (_disposed) throw StateError('This media editor is closed.');
  }

  void assertOrigin() => assertAvailable();

  void assertStaged() {
    if (_snapshot == null) {
      throw const MediaStoreException(MediaStoreFailure.notStaged);
    }
  }

  Future<T> guard<T>(Future<T> Function() operation) async {
    assertAvailable();
    if (_activeOperation != null) {
      throw const MediaStoreException(MediaStoreFailure.busy);
    }
    final completed = Completer<void>();
    _activeOperation = completed.future;
    try {
      return await operation();
    } finally {
      _activeOperation = null;
      completed.complete();
    }
  }

  static void assertSize(int size, int limit) {
    if (size > limit) {
      throw MediaStoreException(MediaStoreFailure.tooLarge, limitBytes: limit);
    }
  }

  Future<Directory> workspace() async {
    if (_workspace case final directory?) return directory;
    final parent = temporaryDirectory ?? (await getTemporaryDirectory()).path;
    assertOrigin();
    return _workspace = await Directory(p.normalize(p.absolute(parent))).createTemp('crisp-media-');
  }

  @override
  Future<String> stage() => guard(() async {
    assertOrigin();
    if (_snapshot case final snapshot?) return snapshot;
    final directory = await workspace();
    var extension = p.extension(file.name).toLowerCase();
    if (!RegExp(r'^\.[a-z0-9]{1,12}$').hasMatch(extension)) extension = '.media';
    final destination = File(p.join(directory.path, 'source$extension'));
    try {
      await readSnapshot(destination);
      assertOrigin();
      _snapshot = destination.path;
      return destination.path;
    } catch (_) {
      await _removePartial(destination);
      rethrow;
    }
  });

  Future<void> readSnapshot(File destination);

  @override
  Future<String> createOutputPath(String extension) => guard(() async {
    assertOrigin();
    assertStaged();
    final normalized = extension.replaceFirst(RegExp(r'^\.'), '').toLowerCase();
    if (normalized != 'wav' && normalized != 'mp4') {
      throw const MediaStoreException(MediaStoreFailure.invalidOutput);
    }
    final directory = await workspace();
    final output = p.join(
      directory.path,
      'output-${++_outputSequence}.$normalized',
    );
    _outputs.add(p.normalize(p.absolute(output)));
    // Native encoders expect a new path, not a pre-created empty file.
    return output;
  });

  Future<File> verifiedOutput(String renderedPath) async {
    assertStaged();
    if (!_outputs.contains(p.normalize(p.absolute(renderedPath))) ||
        await FileSystemEntity.type(renderedPath, followLinks: false) !=
            FileSystemEntityType.file) {
      throw const MediaStoreException(MediaStoreFailure.invalidOutput);
    }
    final output = File(renderedPath);
    final length = await output.length();
    if (length == 0) {
      throw const MediaStoreException(MediaStoreFailure.emptyOutput);
    }
    assertSize(length, outputLimitBytes);
    return output;
  }

  String copyPath(String fileName, File output) {
    final name = fileName.trim();
    final extension = p.extension(output.path).toLowerCase();
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        name.endsWith('.') ||
        utf8.encode(name).length > 240 ||
        RegExp(r'[<>:"/\\|?*\x00-\x1f\x7f]').hasMatch(name) ||
        RegExp(
          r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)',
          caseSensitive: false,
        ).hasMatch(name) ||
        !name.toLowerCase().endsWith(extension)) {
      throw const MediaStoreException(MediaStoreFailure.invalidName);
    }
    final context = isRemote ? p.posix : p.context;
    if (name.toLowerCase() == context.basename(path).toLowerCase()) {
      throw const MediaStoreException(MediaStoreFailure.nameConflict);
    }
    return context.join(context.dirname(path), name);
  }

  /// Stream through a single disk write at a time. Do not collect chunks in an
  /// IOSink queue while a provider or filesystem supplies data faster than disk.
  Future<int> writeNewFile(
    Stream<List<int>> source,
    File destination, {
    required int limitBytes,
    int? expectedBytes,
  }) async {
    var created = false;
    RandomAccessFile? writer;
    try {
      assertOrigin();
      await destination.create(exclusive: true);
      created = true;
      writer = await destination.open(mode: FileMode.writeOnly);
      var written = 0;
      await for (final chunk in source) {
        assertOrigin();
        written += chunk.length;
        assertSize(written, limitBytes);
        await writer.writeFrom(chunk);
      }
      if (expectedBytes != null && written != expectedBytes) {
        throw const MediaStoreException(MediaStoreFailure.sourceChanged);
      }
      assertOrigin();
      await writer.flush();
      await writer.close();
      writer = null;
      return written;
    } catch (_) {
      try {
        await writer?.close();
      } catch (_) {
        // Preserve the transfer failure.
      }
      if (created) await _removePartial(destination);
      rethrow;
    }
  }

  static Future<void> _removePartial(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (error, stack) {
      _log.warn('Could not remove an incomplete media copy', error, stack);
    }
  }

  @override
  Future<void> dispose() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    await _activeOperation;
    final directory = _workspace;
    _workspace = null;
    _snapshot = null;
    _outputs.clear();
    if (directory == null) return;
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (error, stack) {
      _log.warn('Could not remove media editing temporary files', error, stack);
    }
  }
}

class _LocalMediaFileStore extends _MediaFileStoreBase {
  _LocalMediaFileStore({
    required this.service,
    required FileItem file,
    int inputLimitBytes = kMediaLocalFileLimitBytes,
    int outputLimitBytes = kMediaLocalFileLimitBytes,
    String? temporaryDirectory,
  }) : super(
         file: file,
         path: file.path ?? file.xFile?.path ?? file.name,
         inputLimitBytes: inputLimitBytes,
         outputLimitBytes: outputLimitBytes,
         temporaryDirectory: temporaryDirectory,
       );

  final LocalFileService service;

  @override
  bool get isRemote => false;
  @override
  String get documentId => 'local:$path';

  Future<T> _withAccess<T>(
    String target,
    Future<T> Function(String accessiblePath) operation, {
    bool forWrite = false,
  }) async {
    final local = service;
    try {
      if (local is LocalMediaFileAccess) {
        return await (local as LocalMediaFileAccess).withMediaFileAccess(
          target,
          operation,
          forWrite: forWrite,
        );
      }
      // Legacy integrations still acquire their stream access. Native services
      // use the per-operation interface above, including mobile bookmarks.
      if (!await local.beginStreamAccess(forWrite ? p.dirname(target) : target)) {
        throw const MediaStoreException(MediaStoreFailure.accessDenied);
      }
      try {
        return await operation(target);
      } finally {
        await local.endStreamAccess();
      }
    } on FileSystemException catch (error) {
      final code = error.osError?.errorCode;
      if (error is PathAccessException || code == 1 || code == 5 || code == 13) {
        throw const MediaStoreException(MediaStoreFailure.accessDenied);
      }
      rethrow;
    }
  }

  @override
  Future<void> readSnapshot(File destination) => _withAccess(path, (sourcePath) async {
    final source = File(sourcePath);
    final before = await source.stat();
    if (before.type != FileSystemEntityType.file) {
      throw const MediaStoreException(MediaStoreFailure.sourceUnavailable);
    }
    _MediaFileStoreBase.assertSize(before.size, inputLimitBytes);
    await writeNewFile(
      source.openRead(),
      destination,
      limitBytes: inputLimitBytes,
      expectedBytes: before.size,
    );
    final after = await source.stat();
    if (after.type != FileSystemEntityType.file ||
        before.size != after.size ||
        before.modified != after.modified) {
      throw const MediaStoreException(MediaStoreFailure.sourceChanged);
    }
  });

  @override
  Future<MediaSaveOutcome> saveCopy(String renderedPath, String fileName) =>
      guard(() async {
        final output = await verifiedOutput(renderedPath);
        final target = copyPath(fileName, output);
        return _withAccess(target, (accessiblePath) async {
          final destination = File(accessiblePath);
          // This check improves the error for directories and symlinks; the
          // exclusive create below is what rejects concurrent name collisions.
          if (await FileSystemEntity.type(accessiblePath, followLinks: false) !=
              FileSystemEntityType.notFound) {
            throw const MediaStoreException(MediaStoreFailure.nameConflict);
          }
          try {
            await writeNewFile(
              output.openRead(),
              destination,
              limitBytes: outputLimitBytes,
              expectedBytes: await output.length(),
            );
          } on FileSystemException catch (error) {
            if (const {17, 80, 183}.contains(error.osError?.errorCode)) {
              throw const MediaStoreException(MediaStoreFailure.nameConflict);
            }
            rethrow;
          }
          return MediaSaveOutcome.savedCopy;
        }, forWrite: true);
      });
}

class _RemoteMediaFileStore extends _MediaFileStoreBase {
  _RemoteMediaFileStore({
    required this.client,
    required this.providerName,
    required this.cache,
    required FileItem file,
    required this.isCurrentAccount,
    int transferLimitBytes = kMediaRemoteTransferLimitBytes,
    String? temporaryDirectory,
  }) : _userId = client.userId,
       _bucketId = client.bucketId,
       super(
         file: file,
         path: file.path ?? p.posix.join('/', file.name),
         inputLimitBytes: transferLimitBytes,
         outputLimitBytes: transferLimitBytes,
         temporaryDirectory: temporaryDirectory,
       );

  final CloudStorageClient client;
  final String providerName;
  final FileCacheService cache;
  final bool Function() isCurrentAccount;
  final String? _userId;
  final String? _bucketId;

  @override
  bool get isRemote => true;
  @override
  String get documentId => '$providerName:$_userId:$_bucketId:$path';

  @override
  void assertOrigin() {
    super.assertOrigin();
    if (!client.isAuthenticated ||
        client.userId != _userId ||
        client.bucketId != _bucketId ||
        !isCurrentAccount()) {
      throw const MediaStoreException(MediaStoreFailure.accountChanged);
    }
  }

  Future<Map<String, String>> _metadata() async {
    assertOrigin();
    final info = await client.resolvePath(path);
    assertOrigin();
    if (info == null || info['type'] == 'folder' || info['isFolder'] == true) {
      throw const MediaStoreException(MediaStoreFailure.sourceUnavailable);
    }
    // A provider that buffers its fallback download must not receive an
    // unbounded request. Listing size alone may be stale; require fresh size.
    final size = int.tryParse('${info['size']}');
    if (size == null || size < 0) {
      throw const MediaStoreException(MediaStoreFailure.sourceUnavailable);
    }
    _MediaFileStoreBase.assertSize(size, inputLimitBytes);
    return {
      for (final key in const [
        'size',
        'etag',
        'eTag',
        'version',
        'versionId',
        'revision',
        'rev',
        'updatedAt',
        'lastModified',
        'modificationTime',
        'uuid',
      ])
        if (info[key] != null) key: '${info[key]}',
    };
  }

  @override
  Future<void> readSnapshot(File destination) async {
    final before = await _metadata();
    assertOrigin();
    // Never infer bounded streaming from supportsStreaming. Some adapters
    // inherit a whole-byte fallback, so the remote limit applies to all of them.
    // Fresh size and post-read checks cannot stop an adapter itself buffering a
    // remote file that grows during download; directional bounded-stream
    // capabilities belong in the storage adapter API before raising this cap.
    await writeNewFile(
      client.downloadStream(path),
      destination,
      limitBytes: inputLimitBytes,
      expectedBytes: int.parse(before['size']!),
    );
    final after = await _metadata();
    if (before.keys.any((key) => before[key] != after[key])) {
      throw const MediaStoreException(MediaStoreFailure.sourceChanged);
    }
  }

  Future<void> _verifyDestination(String target) async {
    assertOrigin();
    final existing = await client.resolvePath(target);
    assertOrigin();
    if (existing != null) {
      throw const MediaStoreException(MediaStoreFailure.nameConflict);
    }
    // Adapters can collapse lookup failures into null. Require independent,
    // positive evidence that this is still the original's parent directory.
    final Map<String, dynamic> listing;
    try {
      listing = await client.listPath(p.posix.dirname(path));
    } catch (_) {
      assertOrigin();
      throw const MediaStoreException(MediaStoreFailure.unverifiedDestination);
    }
    assertOrigin();
    final files = listing['files'];
    final folders = listing['folders'];
    if (files is! List || folders is! List) {
      throw const MediaStoreException(MediaStoreFailure.unverifiedDestination);
    }
    final originalName = p.posix.basename(path).toLowerCase();
    final targetName = p.posix.basename(target).toLowerCase();
    var foundOriginal = false;
    for (final entry in [...files, ...folders]) {
      if (entry is! Map || entry['name'] is! String) {
        throw const MediaStoreException(MediaStoreFailure.unverifiedDestination);
      }
      if ((entry['name'] as String).toLowerCase() == targetName) {
        throw const MediaStoreException(MediaStoreFailure.nameConflict);
      }
    }
    for (final entry in files) {
      if ((entry['name'] as String).toLowerCase() == originalName) {
        foundOriginal = true;
        break;
      }
    }
    if (!foundOriginal) {
      throw const MediaStoreException(MediaStoreFailure.unverifiedDestination);
    }
  }

  Stream<List<int>> _uploadBytes(File output, int length) async* {
    var sent = 0;
    await for (final chunk in output.openRead()) {
      assertOrigin();
      sent += chunk.length;
      _MediaFileStoreBase.assertSize(sent, outputLimitBytes);
      if (sent > length) {
        throw const MediaStoreException(MediaStoreFailure.invalidOutput);
      }
      yield chunk;
    }
    if (sent != length) {
      throw const MediaStoreException(MediaStoreFailure.invalidOutput);
    }
    assertOrigin();
  }

  @override
  Future<MediaSaveOutcome> saveCopy(String renderedPath, String fileName) =>
      guard(() async {
        assertOrigin();
        final output = await verifiedOutput(renderedPath);
        final length = await output.length();
        final target = copyPath(fileName, output);
        await _verifyDestination(target);
        assertOrigin();
        await client.uploadStream(
          _uploadBytes(output, length),
          length,
          p.posix.basename(target),
          p.posix.dirname(target),
        );
        assertOrigin();
        // Failure of housekeeping after a successful write must not encourage
        // a second upload. Do not insert account-specific bytes into the cache.
        try {
          await cache.remove(target, providerName);
        } catch (error, stack) {
          _MediaFileStoreBase._log.warn(
            'Could not invalidate the media copy preview cache',
            error,
            stack,
          );
        }
        return MediaSaveOutcome.savedCopy;
      });
}
