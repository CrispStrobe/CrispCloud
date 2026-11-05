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
    // A newly installed sandboxed macOS app may not have its cache directory
    // yet. Only create this private temporary parent, never source directories.
    final root = Directory(p.normalize(p.absolute(parent)));
    await root.create(recursive: true);
    assertOrigin();
    return _workspace = await root.createTemp('crisp-media-');
  }

  @override
  Future<String> stage() => guard(() async {
    assertOrigin();
    if (_snapshot case final snapshot?) return snapshot;
    final directory = await workspace();
    var extension = p.extension(file.name).toLowerCase();
    if (!RegExp(r'^\.[a-z0-9]{1,12}$').hasMatch(extension))
      extension = '.media';
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
      if (!await local.beginStreamAccess(
        forWrite ? p.dirname(target) : target,
      )) {
        throw const MediaStoreException(MediaStoreFailure.accessDenied);
      }
      try {
        return await operation(target);
      } finally {
        await local.endStreamAccess();
      }
    } on FileSystemException catch (error) {
      final code = error.osError?.errorCode;
      if (error is PathAccessException ||
          code == 1 ||
          code == 5 ||
          code == 13) {
        throw const MediaStoreException(MediaStoreFailure.accessDenied);
      }
      rethrow;
    }
  }

  @override
  Future<void> readSnapshot(File destination) =>
      _withAccess(path, (sourcePath) async {
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

  Future<_MediaRemoteDirectory> _parentDirectory(
    MediaStoreFailure failure,
  ) async {
    assertOrigin();
    try {
      final listing = await client.listPathForEdit(p.posix.dirname(path));
      assertOrigin();
      return _parseDirectory(listing);
    } catch (_) {
      assertOrigin();
      throw MediaStoreException(failure);
    }
  }

  static _MediaRemoteDirectory _parseDirectory(Map<String, dynamic> listing) {
    // B2 exposes its next page; Azure exposes NextMarker. Several other
    // adapters consume all pages internally. Never interpret an unfinished
    // listing as evidence that an export name is unused.
    for (final key in const [
      'nextStartFileName',
      'nextFileName',
      'nextMarker',
      'NextMarker',
      'nextPageToken',
      'nextContinuationToken',
      'continuationToken',
      'nextCursor',
      'nextLink',
      '@odata.nextLink',
    ]) {
      final value = listing[key];
      if (value != null && '$value'.trim().isNotEmpty) {
        throw const MediaStoreException(
          MediaStoreFailure.unverifiedDestination,
        );
      }
    }
    for (final key in const [
      'hasMore',
      'has_more',
      'isTruncated',
      'IsTruncated',
      'hasNextPage',
    ]) {
      if (listing[key] == true || listing[key] == 'true') {
        throw const MediaStoreException(
          MediaStoreFailure.unverifiedDestination,
        );
      }
    }
    final rawFiles = listing['files'];
    final rawFolders = listing['folders'];
    if (rawFiles is! List ||
        (listing.containsKey('folders') && rawFolders is! List) ||
        (!listing.containsKey('folders') &&
            !listing.containsKey('nextStartFileName'))) {
      throw const MediaStoreException(MediaStoreFailure.unverifiedDestination);
    }
    final files = <Map<String, dynamic>>[];
    final folders = <Map<String, dynamic>>[];
    void addEntries(List entries, bool? defaultFolder) {
      for (final entry in entries) {
        if (entry is! Map) {
          throw const MediaStoreException(
            MediaStoreFailure.unverifiedDestination,
          );
        }
        final nested = entry['metadata'];
        final info = <String, dynamic>{
          if (nested is Map)
            for (final value in nested.entries)
              if (value.key is String) value.key as String: value.value,
          for (final value in entry.entries)
            if (value.key is String && value.value != null)
              value.key as String: value.value,
        };
        final name = info['name'];
        if (name is! String ||
            name.isEmpty ||
            name == '.' ||
            name == '..' ||
            name.contains('/')) {
          throw const MediaStoreException(
            MediaStoreFailure.unverifiedDestination,
          );
        }
        final bool? explicitFolder = info['isFolder'] is bool
            ? info['isFolder'] as bool
            : info['type'] == 'folder'
            ? true
            : info['type'] == 'file'
            ? false
            : null;
        final isFolder = explicitFolder ?? defaultFolder;
        // B2 combines files and folders into one list. Its entries all carry
        // isFolder; missing classification must not silently hide directories.
        if (isFolder == null) {
          throw const MediaStoreException(
            MediaStoreFailure.unverifiedDestination,
          );
        }
        (isFolder ? folders : files).add(info);
      }
    }

    addEntries(rawFiles, rawFolders is List ? false : null);
    if (rawFolders is List) addEntries(rawFolders, true);
    return (files: files, folders: folders);
  }

  Map<String, dynamic> _originalEntry(
    _MediaRemoteDirectory directory,
    MediaStoreFailure failure,
  ) {
    final originalName = p.posix.basename(path).toLowerCase();
    final matches = directory.files
        .where(
          (entry) => (entry['name'] as String).toLowerCase() == originalName,
        )
        .toList();
    if (matches.length != 1 ||
        directory.folders.any(
          (entry) => (entry['name'] as String).toLowerCase() == originalName,
        )) {
      // Duplicate Google Drive names cannot be addressed safely by the
      // generic path-based download API, even when one UUID is familiar.
      throw MediaStoreException(failure);
    }
    final info = matches.single;
    final identity = info['uuid'] ?? info['id'] ?? info['fileId'];
    if ((file.uuid?.isNotEmpty ?? false) &&
        identity != null &&
        '$identity'.isNotEmpty &&
        file.uuid != '$identity') {
      throw MediaStoreException(failure);
    }
    return info;
  }

  Future<Map<String, String>> _metadata() async {
    // resolvePath is not a common file-stat contract: Google Drive/pCloud only
    // resolve folders, and FTP guesses that any failed directory lookup is a
    // file. Use a fresh, complete parent listing for every provider instead.
    final directory = await _parentDirectory(
      MediaStoreFailure.sourceUnavailable,
    );
    final info = _originalEntry(directory, MediaStoreFailure.sourceUnavailable);
    // The captured FileItem's size may be stale. Require the fresh listing's
    // size before allowing an adapter to invoke a buffering download fallback.
    final size = int.tryParse('${info['size']}');
    if (size == null || size < 0) {
      throw const MediaStoreException(MediaStoreFailure.sourceUnavailable);
    }
    _MediaFileStoreBase.assertSize(size, inputLimitBytes);
    final downloadSize = int.tryParse('${info['downloadSize'] ?? size}');
    if (downloadSize == null || downloadSize < 0) {
      throw const MediaStoreException(MediaStoreFailure.sourceUnavailable);
    }
    _MediaFileStoreBase.assertSize(downloadSize, inputLimitBytes);
    return {
      'downloadSize': '$downloadSize',
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
        'id',
        'fileId',
        'content_hash',
        'sha1',
        'crc32Hash',
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
      expectedBytes: int.parse(before['downloadSize']!),
    );
    final after = await _metadata();
    if (before.keys.any((key) => before[key] != after[key])) {
      throw const MediaStoreException(MediaStoreFailure.sourceChanged);
    }
  }

  Future<void> _verifyDestination(String target) async {
    final directory = await _parentDirectory(
      MediaStoreFailure.unverifiedDestination,
    );
    _originalEntry(directory, MediaStoreFailure.unverifiedDestination);
    final targetName = p.posix.basename(target).toLowerCase();
    for (final entry in [...directory.files, ...directory.folders]) {
      if ((entry['name'] as String).toLowerCase() == targetName) {
        throw const MediaStoreException(MediaStoreFailure.nameConflict);
      }
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
          // Azure distinguishes a directory from a full blob key by its final
          // slash. Other adapters normalize/join this directory path.
          '${p.posix.dirname(target).replaceFirst(RegExp(r'/+$'), '')}/',
        );
        // Failure of housekeeping after a successful write must not encourage
        // a second upload. Invalidate even if the account changed while upload
        // was in flight: the cache key is shared by provider/path. Then report
        // the account change without claiming persistence to the new account.
        try {
          await cache.remove(target, providerName);
        } catch (error, stack) {
          _MediaFileStoreBase._log.warn(
            'Could not invalidate the media copy preview cache',
            error,
            stack,
          );
        }
        assertOrigin();
        return MediaSaveOutcome.savedCopy;
      });
}

typedef _MediaRemoteDirectory = ({
  List<Map<String, dynamic>> files,
  List<Map<String, dynamic>> folders,
});
