// lib/services/encrypted_storage_wrapper.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'cloud_storage_interface.dart';
import 'encryption_service.dart';

/// Wraps any [CloudStorageClient] to transparently encrypt data before upload
/// and decrypt after download. All cryptography is performed client-side.
///
/// Usage:
/// ```dart
/// final salt = EncryptionService.generateSalt();
/// final key  = EncryptionService.deriveKey('my passphrase', salt);
/// final wrapper = EncryptedStorageWrapper(
///   inner: myCloudClient,
///   encryptionKey: key,
/// );
/// ```
class EncryptedStorageWrapper implements CloudStorageClient {
  final CloudStorageClient _inner;
  final Uint8List _key;

  /// Access the unwrapped inner client (used by disableEncryption).
  CloudStorageClient get inner => _inner;

  /// When true, filenames are also encrypted (base64url encoded).
  final bool encryptFilenames;

  EncryptedStorageWrapper({
    required CloudStorageClient inner,
    required Uint8List encryptionKey,
    this.encryptFilenames = false,
  })  : _inner = inner,
        _key = encryptionKey;

  // ---------------------------------------------------------------------------
  // Pass-through: authentication
  // ---------------------------------------------------------------------------

  @override
  Future<void> login(String email, String password,
          {String? twoFactorCode}) =>
      _inner.login(email, password, twoFactorCode: twoFactorCode);

  @override
  Future<bool> is2faNeeded(String email) => _inner.is2faNeeded(email);

  @override
  Future<void> logout() => _inner.logout();

  @override
  bool get isAuthenticated => _inner.isAuthenticated;

  @override
  String? get userId => _inner.userId;

  @override
  String? get bucketId => _inner.bucketId;

  // ---------------------------------------------------------------------------
  // Provider info
  // ---------------------------------------------------------------------------

  @override
  String get providerName => '${_inner.providerName} (Encrypted)';

  @override
  String get rootPath => _inner.rootPath;

  // ---------------------------------------------------------------------------
  // Capability flags
  // ---------------------------------------------------------------------------

  @override
  bool get supportsStreaming => _inner.supportsStreaming;

  @override
  bool get supportsMultipart => false; // Encryption breaks multipart

  @override
  bool get supportsVersioning => _inner.supportsVersioning;

  @override
  bool get supportsSharing => false; // Shared links would serve encrypted data

  @override
  bool get supportsSearch => false; // Server cannot search encrypted content

  @override
  bool get supportsThumbnails => false; // Server cannot generate thumbnails

  @override
  bool get supportsTrash => _inner.supportsTrash;

  // ---------------------------------------------------------------------------
  // Pass-through: navigation / folder operations
  // ---------------------------------------------------------------------------

  @override
  Future<Map<String, dynamic>?> resolvePath(String path) =>
      _inner.resolvePath(path);

  @override
  Future<Map<String, dynamic>> listPath(String path) =>
      _inner.listPath(path);

  @override
  Future<void> createFolderPath(String path) => _inner.createFolderPath(path);

  @override
  Future<void> deletePath(String path) => _inner.deletePath(path);

  @override
  Future<void> movePath(String sourcePath, String targetPath) =>
      _inner.movePath(sourcePath, targetPath);

  @override
  Future<void> renamePath(String path, String newName) =>
      _inner.renamePath(path, newName);

  // ---------------------------------------------------------------------------
  // Encrypted upload
  // ---------------------------------------------------------------------------

  @override
  Future<void> uploadFile(
    List<int> fileData,
    String fileName,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    final encrypted =
        EncryptionService.encrypt(Uint8List.fromList(fileData), _key);
    final uploadName = encryptFilenames
        ? EncryptionService.encryptFilename(fileName, _key)
        : fileName;
    await _inner.uploadFile(encrypted, uploadName, targetPath,
        onProgress: onProgress);
  }

  // ---------------------------------------------------------------------------
  // Encrypted download
  // ---------------------------------------------------------------------------

  @override
  Future<Uint8List> downloadFileBytes(String remotePath,
      {Function(int, int)? onProgress}) async {
    final encrypted =
        await _inner.downloadFileBytes(remotePath, onProgress: onProgress);
    return EncryptionService.decrypt(encrypted, _key);
  }

  @override
  Future<void> downloadFileByPath(
    String remotePath,
    String localPath, {
    Function(int, int)? onProgress,
  }) async {
    // Download encrypted bytes, decrypt, then write to local path.
    final encrypted =
        await _inner.downloadFileBytes(remotePath, onProgress: onProgress);
    final decrypted = EncryptionService.decrypt(encrypted, _key);

    if (kIsWeb) {
      throw UnsupportedError(
          'downloadFileByPath is not supported on web. '
          'Use downloadFileBytes instead.');
    }

    final file = await File(localPath).create(recursive: true);
    await file.writeAsBytes(decrypted);
  }

  // ---------------------------------------------------------------------------
  // Stream-based (buffers for GCM, which needs full plaintext)
  // ---------------------------------------------------------------------------

  @override
  Future<void> uploadStream(
    Stream<List<int>> dataStream,
    int length,
    String fileName,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    // GCM requires the full plaintext, so buffer the stream first.
    final builder = BytesBuilder(copy: false);
    await for (final chunk in dataStream) {
      builder.add(chunk);
    }
    await uploadFile(builder.takeBytes(), fileName, targetPath,
        onProgress: onProgress);
  }

  @override
  Stream<List<int>> downloadStream(
    String remotePath, {
    Function(int, int)? onProgress,
  }) async* {
    final decrypted =
        await downloadFileBytes(remotePath, onProgress: onProgress);
    yield decrypted;
  }
}
