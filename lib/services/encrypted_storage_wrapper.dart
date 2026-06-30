// lib/services/encrypted_storage_wrapper.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'cloud_storage_interface.dart';
import 'encryption_service.dart';
import 'web_crypto_provider.dart';
// On the web build, bulk AES-GCM runs on the browser's native crypto
// (~1000 MB/s vs ~1 MB/s for pointycastle in dart2js); native/VM keeps
// pointycastle.
import 'web_crypto_factory_io.dart'
    if (dart.library.js_interop) 'web_crypto_factory_web.dart';

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

  /// Crypto backend for BULK file data: native WebCrypto on the web build,
  /// pointycastle on the Dart VM / native. Injectable for tests.
  final WebCryptoProvider _crypto;

  /// The raw [_key] wrapped into an opaque GCM key handle, imported once and
  /// cached (cheap on pointycastle, a one-time importKey on WebCrypto).
  Future<Object>? _gcmKeyFuture;
  Future<Object> _gcmKey() => _gcmKeyFuture ??= _crypto.importKey(_key);

  EncryptedStorageWrapper({
    required CloudStorageClient inner,
    required Uint8List encryptionKey,
    this.encryptFilenames = false,
    WebCryptoProvider? cryptoProvider,
  })  : _inner = inner,
        _key = encryptionKey,
        _crypto = cryptoProvider ?? defaultWebCryptoProvider();

  // ---------------------------------------------------------------------------
  // Pass-through: authentication
  // ---------------------------------------------------------------------------

  @override
  Future<void> login(String email, String password, {String? twoFactorCode}) =>
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
  Future<Map<String, dynamic>> listPath(String path) => _inner.listPath(path);

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
        await _crypto.encrypt(await _gcmKey(), Uint8List.fromList(fileData));
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
    return _crypto.decrypt(await _gcmKey(), encrypted);
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
    final decrypted = await _crypto.decrypt(await _gcmKey(), encrypted);

    if (kIsWeb) {
      throw UnsupportedError('downloadFileByPath is not supported on web. '
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

  // ---------------------------------------------------------------------------
  // Pass-through: new CloudStorageClient methods
  // ---------------------------------------------------------------------------

  @override
  bool get supportsNativeShare => false; // Shared links serve encrypted data

  @override
  bool get supportsServerSideCopy => _inner.supportsServerSideCopy;

  @override
  Future<Uint8List?> getThumbnail(String remotePath) async => null;

  @override
  Future<Map<String, int>?> getQuota() => _inner.getQuota();

  @override
  Future<int> healthCheck() => _inner.healthCheck();

  @override
  Future<void> copyPath(String sourcePath, String targetPath) async {
    // Cannot use server-side copy because data is encrypted; download, re-encrypt, upload.
    final bytes = await downloadFileBytes(sourcePath);
    final fileName = sourcePath.split('/').last;
    await uploadFile(bytes, fileName, targetPath);
  }

  @override
  bool get supportsFullTextSearch =>
      false; // encrypted content can't be searched server-side

  @override
  Future<List<Map<String, dynamic>>> fullTextSearch(
          String query, String remotePath) async =>
      [];
}
