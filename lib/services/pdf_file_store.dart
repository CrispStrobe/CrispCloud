import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import 'cloud_storage_interface.dart';
import 'file_cache_service.dart';
import 'local_file_service.dart';
import 'log_service.dart';
import 'pdf_edit_session.dart';

export 'pdf_edit_session.dart' show PdfSaveOutcome;

const kPdfEditorInputLimitBytes = 64 * 1024 * 1024;
const kPdfEditorOutputLimitBytes = 128 * 1024 * 1024;

class PdfSaveConflictException implements Exception {
  const PdfSaveConflictException(this.message);
  final String message;

  @override
  String toString() => message;
}

class PdfAccountChangedException implements Exception {
  const PdfAccountChangedException();

  @override
  String toString() =>
      'The storage account changed. Reopen the document before saving to it.';
}

class PdfFileTooLargeException implements Exception {
  const PdfFileTooLargeException(this.limitBytes);
  final int limitBytes;

  @override
  String toString() =>
      'This PDF exceeds the ${limitBytes ~/ (1024 * 1024)} MiB editing limit.';
}

/// The file/account captured when an editor is opened.
///
/// Loading bypasses the preview cache. Overwrite checks compare both available
/// revision metadata and a fresh content hash, including for providers without
/// ETags. The shared cloud API has no conditional-write operation: this is a
/// preflight conflict check, NOT an atomic compare-and-swap. The same narrow
/// check/write race exists for local paths. Save a separate copy when that race
/// is unacceptable; a future conditional-write capability belongs in the
/// storage adapters rather than the PDF widget.
abstract class PdfFileStore {
  factory PdfFileStore.local({
    required LocalFileService service,
    required FileItem file,
    int inputLimitBytes = kPdfEditorInputLimitBytes,
    int outputLimitBytes = kPdfEditorOutputLimitBytes,
  }) = _LocalPdfFileStore;

  factory PdfFileStore.remote({
    required CloudStorageClient client,
    required String providerName,
    required FileCacheService cache,
    required FileItem file,
    bool Function()? isCurrentAccount,
    int inputLimitBytes = kPdfEditorInputLimitBytes,
    int outputLimitBytes = kPdfEditorOutputLimitBytes,
  }) = _RemotePdfFileStore;

  String get documentId;
  String get displayName;
  String get path;
  bool get isRemote;

  /// Reads fresh, complete bytes and establishes the overwrite baseline.
  Future<Uint8List> load();

  /// Writes the original only if a fresh read still matches the baseline.
  Future<PdfSaveOutcome> save(Uint8List bytes);

  /// Creates [fileName] in the original's directory, leaving the editor bound
  /// to the original. Existing targets are rejected, and neither a copy nor a
  /// download marks the original as saved. Remote creation also has a check/
  /// write race without provider-native create-only support; use unique names.
  /// Remote copies require a verified parent listing containing the original:
  /// adapters can otherwise report lookup errors as nonexistent destinations.
  Future<PdfSaveOutcome> saveCopy(Uint8List bytes, String fileName);
}

abstract class _PdfFileStoreBase implements PdfFileStore {
  _PdfFileStoreBase(
    this.file,
    this.path, {
    required this.inputLimitBytes,
    required this.outputLimitBytes,
  });
  final FileItem file;
  // Other host editors can reuse the conflict/account/write contract without
  // inheriting the PDF memory budget. PDF callers retain the original defaults.
  final int inputLimitBytes;
  final int outputLimitBytes;
  @override
  final String path;

  String? baselineDigest;
  bool _writing = false;
  bool _loading = false;

  @override
  String get displayName => file.name;

  void assertLoaded() {
    if (baselineDigest == null) {
      throw StateError('Load the PDF before saving it.');
    }
  }

  Future<T> guardWrite<T>(Future<T> Function() operation) async {
    if (_writing) throw const PdfSaveInProgressException();
    if (_loading) throw StateError('Wait for the PDF to finish loading.');
    _writing = true;
    try {
      return await operation();
    } finally {
      _writing = false;
    }
  }

  Future<T> guardLoad<T>(Future<T> Function() operation) async {
    if (_writing) throw const PdfSaveInProgressException();
    if (_loading) throw StateError('The PDF is already loading.');
    _loading = true;
    try {
      return await operation();
    } finally {
      _loading = false;
    }
  }

  String copyPath(String name) {
    var fileName = name.trim();
    if (fileName.isEmpty ||
        fileName == '.' ||
        fileName == '..' ||
        RegExp(r'[<>:"/\\|?*\x00-\x1f]').hasMatch(fileName)) {
      throw ArgumentError(
        'Enter a filename without directories or separators.',
      );
    }
    if (!fileName.toLowerCase().endsWith('.pdf')) fileName = '$fileName.pdf';
    final context = isRemote || kIsWeb ? p.posix : p.context;
    final target = context.join(context.dirname(path), fileName);
    if (context.equals(target, path)) {
      throw const PdfSaveConflictException(
        'Choose a different filename to save a separate copy.',
      );
    }
    return target;
  }

  static String digest(Uint8List bytes) => sha256.convert(bytes).toString();

  static void assertSize(int size, int limit) {
    if (size > limit) throw PdfFileTooLargeException(limit);
  }

  Uint8List outputSnapshot(Uint8List bytes) {
    assertSize(bytes.length, outputLimitBytes);
    return Uint8List.fromList(bytes).asUnmodifiableView();
  }
}

class _LocalPdfFileStore extends _PdfFileStoreBase {
  _LocalPdfFileStore({
    required this.service,
    required FileItem file,
    int inputLimitBytes = kPdfEditorInputLimitBytes,
    int outputLimitBytes = kPdfEditorOutputLimitBytes,
  }) : super(
         file,
         file.path ?? file.xFile?.path ?? file.name,
         inputLimitBytes: inputLimitBytes,
         outputLimitBytes: outputLimitBytes,
       );

  final LocalFileService service;

  @override
  bool get isRemote => false;
  @override
  String get documentId => 'local:$path';

  Future<Uint8List> _read(int limit) async {
    Future<Uint8List> read() =>
        service.readFileForEdit(path, fileItem: file, maxBytes: limit);
    try {
      return await read();
    } on FileSystemException catch (error) {
      final code = error.osError?.errorCode;
      if (kIsWeb ||
          (error is! PathAccessException && code != 1 && code != 13)) {
        rethrow;
      }
      if (!await service.ensureAccess(path)) rethrow;
      return read();
    }
  }

  @override
  Future<Uint8List> load() => guardLoad(() async {
    // fileLength/readFileForEdit checks current size, including FSA handles.
    final bytes = await _read(inputLimitBytes);
    _PdfFileStoreBase.assertSize(bytes.length, inputLimitBytes);
    baselineDigest = _PdfFileStoreBase.digest(bytes);
    return Uint8List.fromList(bytes);
  });

  @override
  Future<PdfSaveOutcome> save(Uint8List bytes) => guardWrite(() async {
    assertLoaded();
    final snapshot = outputSnapshot(bytes);
    Uint8List current;
    try {
      current = await _read(outputLimitBytes);
    } catch (_) {
      throw const PdfSaveConflictException(
        'The original file could not be verified. Save a separate copy.',
      );
    }
    if (_PdfFileStoreBase.digest(current) != baselineDigest) {
      throw const PdfSaveConflictException(
        'The original file changed outside this editor. Save a separate copy.',
      );
    }
    final result = await service.saveFileReportingResult(path, snapshot);
    if (result == LocalFileSaveResult.downloadedCopy) {
      return PdfSaveOutcome.downloadedCopy;
    }
    baselineDigest = _PdfFileStoreBase.digest(snapshot);
    return PdfSaveOutcome.savedOriginal;
  });

  @override
  Future<PdfSaveOutcome> saveCopy(Uint8List bytes, String fileName) =>
      guardWrite(() async {
        final snapshot = outputSnapshot(bytes);
        final target = copyPath(fileName);
        try {
          final result = await service.saveFileReportingResult(
            target,
            snapshot,
            overwrite: false,
          );
          return result == LocalFileSaveResult.downloadedCopy
              ? PdfSaveOutcome.downloadedCopy
              : PdfSaveOutcome.savedCopy;
        } on FileSystemException catch (error) {
          if (error.osError?.errorCode == 17 ||
              error.osError?.errorCode == 80 ||
              error.osError?.errorCode == 183) {
            throw const PdfSaveConflictException(
              'A file already exists with that name. Choose another filename.',
            );
          }
          rethrow;
        }
      });
}

class _RemotePdfFileStore extends _PdfFileStoreBase {
  _RemotePdfFileStore({
    required this.client,
    required this.providerName,
    required this.cache,
    required FileItem file,
    this.isCurrentAccount,
    int inputLimitBytes = kPdfEditorInputLimitBytes,
    int outputLimitBytes = kPdfEditorOutputLimitBytes,
  }) : _userId = client.userId,
       _bucketId = client.bucketId,
       super(
         file,
         file.path ?? p.posix.join('/', file.name),
         inputLimitBytes: inputLimitBytes,
         outputLimitBytes: outputLimitBytes,
       );

  static const _log = Log('PdfFileStore');
  final CloudStorageClient client;
  final String providerName;
  final FileCacheService cache;
  final bool Function()? isCurrentAccount;
  final String? _userId;
  final String? _bucketId;
  Map<String, String> _revision = const {};

  @override
  bool get isRemote => true;
  @override
  String get documentId => '$providerName:$_userId:$_bucketId:$path';

  void _assertAccount() {
    if (!client.isAuthenticated ||
        client.userId != _userId ||
        client.bucketId != _bucketId ||
        (isCurrentAccount != null && !isCurrentAccount!())) {
      throw const PdfAccountChangedException();
    }
  }

  Future<Map<String, String>> _metadata(int limit) async {
    final info = await client.resolvePath(path);
    if (info == null) return const {};
    if (info['type'] == 'folder') {
      throw const PdfSaveConflictException('The PDF path is now a directory.');
    }
    final size = int.tryParse('${info['size']}');
    if (size != null) _PdfFileStoreBase.assertSize(size, limit);
    return {
      for (final key in const [
        'etag',
        'eTag',
        'version',
        'versionId',
        'revision',
        'rev',
        'updatedAt',
        'modificationTime',
        'lastModified',
        'size',
        'uuid',
      ])
        if (info[key] != null) key: '${info[key]}',
    };
  }

  static bool _changed(Map<String, String> before, Map<String, String> after) =>
      before.keys.any(
        (key) => after.containsKey(key) && before[key] != after[key],
      );

  Future<Uint8List> _download(int limit) async {
    final bytes = await client.downloadFileBytes(path);
    _PdfFileStoreBase.assertSize(bytes.length, limit);
    return bytes;
  }

  @override
  Future<Uint8List> load() => guardLoad(() async {
    _assertAccount();
    final before = await _metadata(inputLimitBytes);
    final bytes = await _download(inputLimitBytes);
    final after = await _metadata(inputLimitBytes);
    _assertAccount();
    if (_changed(before, after)) {
      throw const PdfSaveConflictException(
        'The PDF changed while it was opening. Reopen the current file.',
      );
    }
    _revision = after.isEmpty ? before : after;
    baselineDigest = _PdfFileStoreBase.digest(bytes);
    return Uint8List.fromList(bytes);
  });

  @override
  Future<PdfSaveOutcome> save(Uint8List bytes) => guardWrite(() async {
    assertLoaded();
    _assertAccount();
    final snapshot = outputSnapshot(bytes);
    final before = await _metadata(outputLimitBytes);
    if (_changed(_revision, before)) _throwConflict();
    Uint8List current;
    try {
      current = await _download(outputLimitBytes);
    } catch (_) {
      throw const PdfSaveConflictException(
        'The original PDF could not be verified. Save a separate copy.',
      );
    }
    if (_PdfFileStoreBase.digest(current) != baselineDigest) _throwConflict();
    final after = await _metadata(outputLimitBytes);
    if (_changed(before, after)) _throwConflict();
    _assertAccount();

    // The generic upload API has no If-Match/precondition. Do not claim
    // that the above check makes this overwrite atomic.
    await client.uploadFile(
      snapshot,
      p.posix.basename(path),
      p.posix.dirname(path),
    );
    baselineDigest = _PdfFileStoreBase.digest(snapshot);
    // Once upload succeeded, a cache/metadata failure must not turn it
    // into a failed save and encourage a duplicate write.
    _revision = const {};
    try {
      _revision = await _metadata(outputLimitBytes);
    } catch (error, stack) {
      _log.warn('Could not refresh PDF revision after upload', error, stack);
    }
    await _invalidate(path);
    return PdfSaveOutcome.savedOriginal;
  });

  @override
  Future<PdfSaveOutcome> saveCopy(Uint8List bytes, String fileName) =>
      guardWrite(() async {
        _assertAccount();
        final snapshot = outputSnapshot(bytes);
        final target = copyPath(fileName);
        await _verifyCopyDestination(target);
        _assertAccount();
        await client.uploadFile(
          snapshot,
          p.posix.basename(target),
          p.posix.dirname(target),
        );
        await _invalidate(target);
        return PdfSaveOutcome.savedCopy;
      });

  Future<void> _verifyCopyDestination(String target) async {
    if (await client.resolvePath(target) != null) _throwCopyExists();

    // Several adapters collapse missing paths and access/network failures to
    // null. A null lookup alone must never authorize an overwrite. List the
    // directory independently and require positive evidence that this is the
    // original's folder. This also rejects adapters that hide list errors by
    // returning empty arrays. If the original disappeared, keep the edits and
    // let the host offer a download instead of guessing that a name is free.
    final Map<String, dynamic> listing;
    try {
      listing = await client.listPath(p.posix.dirname(path));
    } catch (_) {
      throw const PdfSaveConflictException(
        'The destination folder could not be verified. Download a copy instead.',
      );
    }
    final files = listing['files'];
    final folders = listing['folders'];
    if (files is! List || folders is! List) _throwUnverifiedCopy();
    final originalName = p.posix.basename(path).toLowerCase();
    final targetName = p.posix.basename(target).toLowerCase();
    var foundOriginal = false;
    for (final entry in [...files, ...folders]) {
      if (entry is! Map || entry['name'] is! String) _throwUnverifiedCopy();
      final name = (entry['name'] as String).toLowerCase();
      // Be conservative for providers with case-insensitive filenames.
      if (name == targetName) _throwCopyExists();
    }
    for (final entry in files) {
      if ((entry['name'] as String).toLowerCase() == originalName) {
        foundOriginal = true;
        break;
      }
    }
    if (!foundOriginal) _throwUnverifiedCopy();
  }

  Never _throwCopyExists() => throw const PdfSaveConflictException(
    'A file already exists with that name. Choose another filename.',
  );

  Never _throwUnverifiedCopy() => throw const PdfSaveConflictException(
    'The original PDF is missing from the destination listing. '
    'Download a copy instead.',
  );

  Future<void> _invalidate(String remotePath) async {
    try {
      // The current preview cache is keyed by provider/path, not by account.
      // Invalidate it rather than injecting account-specific edited bytes into
      // that shared key. The next preview obtains the current remote file.
      await cache.remove(remotePath, providerName);
    } catch (error, stack) {
      _log.warn('Could not invalidate the PDF preview cache', error, stack);
    }
  }

  Never _throwConflict() => throw const PdfSaveConflictException(
    'The remote PDF changed outside this editor. Save a separate copy.',
  );
}
