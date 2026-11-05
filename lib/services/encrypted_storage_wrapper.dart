import '../models/storage_reference.dart';
import 'storage_identity.dart';

// lib/services/encrypted_storage_wrapper.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'cloud_storage_interface.dart';
import 'encryption_service.dart';
import 'gcm_transfer_stream.dart';
import 'transfer_spool.dart';
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
class EncryptedStorageWrapper
    with CloudTransferOperations
    implements
        CloudStorageClient,
        StorageNamespaceIdentity,
        FreshCloudDirectoryReader {
  @override
  String get storageNamespace =>
      'encrypted:${storageReferenceForClient(_inner).id}';

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
    // Preserve the public named argument while keeping the captured client private.
    // ignore: prefer_initializing_formals
  }) : _inner = inner,
       _key = Uint8List.fromList(encryptionKey),
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
  Future<Map<String, dynamic>> readDirectoryForEdit(String path) async {
    final listing = await _inner.listPathForEdit(path);
    final files = listing['files'];
    if (files is! List) return listing;
    return {
      ...listing,
      'files': [for (final entry in files) _withPlaintextSize(entry)],
    };
  }

  static dynamic _withPlaintextSize(dynamic entry) {
    if (entry is! Map ||
        entry['isFolder'] == true ||
        entry['type'] == 'folder') {
      return entry;
    }
    final metadata = entry['metadata'] is Map ? entry['metadata'] as Map : null;
    final size = int.tryParse(
      '${entry['downloadSize'] ?? metadata?['downloadSize'] ?? entry['size'] ?? metadata?['size']}',
    );
    if (size == null) return entry;
    // EncryptionService and both crypto backends use a 12-byte nonce and a
    // 16-byte GCM tag. Retain stored size for the editor's pre-download cap;
    // downloadStream yields plaintext, whose exact size excludes the envelope.
    return {...entry, 'downloadSize': size - 28};
  }

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
    final encrypted = await _crypto.encrypt(
      await _gcmKey(),
      Uint8List.fromList(fileData),
    );
    final uploadName = encryptFilenames
        ? EncryptionService.encryptFilename(fileName, _key)
        : fileName;
    await _inner.uploadFile(
      encrypted,
      uploadName,
      targetPath,
      onProgress: onProgress,
    );
  }

  // ---------------------------------------------------------------------------
  // Encrypted download
  // ---------------------------------------------------------------------------

  @override
  Future<Uint8List> downloadFileBytes(
    String remotePath, {
    Function(int, int)? onProgress,
  }) async {
    final encrypted = await _inner.downloadFileBytes(
      remotePath,
      onProgress: onProgress,
    );
    return _crypto.decrypt(await _gcmKey(), encrypted);
  }

  @override
  Future<void> downloadFileByPath(
    String remotePath,
    String localPath, {
    Function(int, int)? onProgress,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('Use downloadStream on web.');
    }
    final check = _captureTransfer();
    final spool = await createAuthenticatedGcmSpool(
      _inner.downloadStream(remotePath, onProgress: onProgress),
      _key,
      check,
    );
    try {
      check();
      final file = await File(localPath).create(recursive: true);
      final sink = file.openWrite();
      try {
        await sink.addStream(spool.openRead());
        await sink.flush();
      } finally {
        await sink.close();
      }
    } finally {
      await spool.dispose();
    }
  }

  // The existing wire format is one AES-GCM message. Decryption therefore
  // authenticates a private disk/browser spool before releasing plaintext.
  @override
  StorageTransferCapabilities get transferCapabilities =>
      StorageTransferCapabilities(
        boundedUpload: _inner.transferCapabilities.boundedUpload,
        boundedDownload: _inner.transferCapabilities.boundedDownload,
      );

  void Function() _captureTransfer() {
    final storage = storageReferenceForClient(_inner);
    void check() {
      if (!_inner.isAuthenticated ||
          storageReferenceForClient(_inner) != storage) {
        throw StateError(
          'The original encrypted-storage account is no longer available.',
        );
      }
    }

    check();
    return check;
  }

  @override
  Future<void> uploadStream(
    Stream<List<int>> dataStream,
    int length,
    String fileName,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    final check = _captureTransfer();
    final encrypted = encryptGcmTransfer(dataStream, length, _key, check);
    final spool = await createTransferSpool(
      encrypted,
      expectedLength: length + 28,
      checkpoint: () async => check(),
    );
    try {
      check();
      final uploadName = encryptFilenames
          ? EncryptionService.encryptFilename(fileName, _key)
          : fileName;
      await _inner.uploadStream(
        spool.openRead(),
        spool.length,
        uploadName,
        targetPath,
        onProgress: onProgress,
      );
      check();
    } finally {
      await spool.dispose();
    }
  }

  @override
  Stream<List<int>> downloadStream(
    String remotePath, {
    Function(int, int)? onProgress,
  }) {
    final check = _captureTransfer();
    return authenticatedGcmDownload(
      _inner.downloadStream(remotePath, onProgress: onProgress),
      _key,
      check,
    );
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
    final check = _captureTransfer();
    final spool = await createTransferSpool(
      downloadStream(sourcePath),
      checkpoint: () async => check(),
    );
    try {
      check();
      await uploadStream(
        spool.openRead(),
        spool.length,
        sourcePath.split('/').last,
        targetPath,
      );
      check();
    } finally {
      await spool.dispose();
    }
  }

  @override
  bool get supportsFullTextSearch => false; // encrypted content can't be searched server-side

  @override
  Future<List<Map<String, dynamic>>> fullTextSearch(
    String query,
    String remotePath,
  ) async => [];
}
