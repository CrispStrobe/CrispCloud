// lib/services/cloud_storage_interface.dart
import 'dart:async';
import 'dart:typed_data';

import 'dropbox_client_adapter.dart';
import 'log_service.dart';
import 'filen_client_adapter.dart';
import 'ftp_client_adapter.dart';
import 'gdrive_client_adapter.dart';
import 'internxt_client_adapter.dart';
import 'nextcloud_client_adapter.dart';
import 'onedrive_client_adapter.dart';
import 'pcloud_client_adapter.dart';
import 's3_client_adapter.dart';
import 'sftp_client_adapter.dart';
import 'webdav_client_adapter.dart';

/// Abstract interface for cloud storage providers
abstract class CloudStorageClient {
  // Authentication
  Future<void> login(String email, String password, {String? twoFactorCode});
  Future<bool> is2faNeeded(String email);
  Future<void> logout();
  bool get isAuthenticated;
  String? get userId;
  String? get bucketId;
  
  // Path operations
  Future<Map<String, dynamic>?> resolvePath(String path);
  Future<Map<String, dynamic>> listPath(String path);
  
  // File operations
  Future<void> uploadFile(
    List<int> fileData,
    String fileName,
    String targetPath, {
    Function(int, int)? onProgress,
  });
  
  Future<void> downloadFileByPath(
    String remotePath,
    String localPath, {
    Function(int, int)? onProgress,
  });

  /// Download a file and return its bytes directly (Used for Web downloads)
  Future<Uint8List> downloadFileBytes(String remotePath, {Function(int, int)? onProgress});
  
  // Folder operations
  Future<void> createFolderPath(String path);
  
  // Delete/Move/Rename operations
  Future<void> deletePath(String path);
  Future<void> movePath(String sourcePath, String targetPath);
  Future<void> renamePath(String path, String newName);
  
  // Provider-specific info
  String get providerName;
  String get rootPath;

  // Capability flags — providers override these
  bool get supportsStreaming => false;
  bool get supportsMultipart => false;
  bool get supportsVersioning => false;
  bool get supportsSharing => false;
  bool get supportsSearch => false;
  bool get supportsThumbnails => false;
  bool get supportsTrash => true;

  /// True if the provider has a native share-link API (GDrive, OneDrive, Dropbox).
  bool get supportsNativeShare => false;

  /// True if the provider supports server-side copy (no download+reupload needed).
  bool get supportsServerSideCopy => false;

  /// Fetch a provider-native thumbnail for a file. Returns bytes or null.
  /// Providers that support thumbnails (GDrive, OneDrive, Dropbox) override this.
  Future<Uint8List?> getThumbnail(String remotePath) async => null;

  /// Get storage quota info. Returns null if not supported.
  /// Keys: 'used' (bytes), 'total' (bytes), 'free' (bytes).
  Future<Map<String, int>?> getQuota() async => null;

  /// Ping/health check. Returns latency in milliseconds, or -1 on failure.
  Future<int> healthCheck() async {
    final sw = Stopwatch()..start();
    try {
      await resolvePath(rootPath);
      sw.stop();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return -1;
    }
  }

  /// Server-side copy a file from [sourcePath] to [targetPath].
  /// Default implementation downloads the file bytes and re-uploads them.
  /// Providers that support server-side copy should override this.
  Future<void> copyPath(String sourcePath, String targetPath) async {
    final fileName = sourcePath.split('/').last;
    final bytes = await downloadFileBytes(sourcePath);
    await uploadFile(bytes, fileName, targetPath);
  }

  /// Stream-based upload. Providers that support streaming override this.
  /// Default implementation buffers the stream and calls uploadFile.
  Future<void> uploadStream(
    Stream<List<int>> dataStream,
    int length,
    String fileName,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    // Default: buffer to memory and delegate to uploadFile
    final builder = BytesBuilder(copy: false);
    await for (final chunk in dataStream) {
      builder.add(chunk);
    }
    await uploadFile(builder.takeBytes(), fileName, targetPath, onProgress: onProgress);
  }

  /// Stream-based download. Returns a stream of chunks.
  /// Default implementation downloads all bytes then yields them as one chunk.
  Stream<List<int>> downloadStream(
    String remotePath, {
    Function(int, int)? onProgress,
  }) async* {
    final bytes = await downloadFileBytes(remotePath, onProgress: onProgress);
    yield bytes;
  }
}

enum CloudProvider {
  dropbox,
  filen,
  ftp,
  gdrive,
  internxt,
  nextcloud,
  onedrive,
  pcloud,
  s3,
  sftp,
  webdav
}

/// Factory for creating cloud storage clients
class CloudStorageFactory {
  static final _log = Log('CloudStorageFactory');

  // --- TOGGLE: Set this to false to disable Internxt globally ---
  static const bool isInternxtSupported = true;

  static CloudStorageClient create(CloudProvider provider, {required dynamic config}) {
    // Robust fallback: If Internxt is selected but disabled, force Filen or throw
    if (provider == CloudProvider.internxt && !isInternxtSupported) {
      _log.warn('Internxt is currently disabled. Defaulting to Filen.');
      // Fallback to Filen if config matches, otherwise throw safe error
      if (config.runtimeType.toString().contains('Filen')) {
         return FilenClientAdapter(config: config);
      }
    }

    try {
      switch (provider) {
        case CloudProvider.dropbox:
          return DropboxClientAdapter(config: config);
        case CloudProvider.filen:
          return FilenClientAdapter(config: config);
        case CloudProvider.ftp:
          return FTPClientAdapter(config: config);
        case CloudProvider.gdrive:
          return GDriveClientAdapter(config: config);
        case CloudProvider.onedrive:
          return OneDriveClientAdapter(config: config);
        case CloudProvider.s3:
          return S3ClientAdapter(config: config);
        case CloudProvider.sftp:
          return SFTPClientAdapter(config: config);
        case CloudProvider.webdav:
          return WebDavClientAdapter(config: config);
        case CloudProvider.internxt:
          if (isInternxtSupported) {
             return InternxtClientAdapter(config: config);
          } else {
             throw UnsupportedError('Internxt is disabled in this build.');
          }
        case CloudProvider.nextcloud:
          return NextcloudClientAdapter(config: config);
        case CloudProvider.pcloud:
          return PCloudClientAdapter(config: config);
      }
    } catch (e) {
      _log.error('Error creating client for $provider', e);
      // Emergency fallback to avoid crash
      // Assuming config is compatible with Filen or we just re-throw
      rethrow;
    }
  }
}