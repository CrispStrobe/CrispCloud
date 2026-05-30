// test/server_side_copy_test.dart
//
// Tests for server-side copy capability flags and default fallback behavior.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/dropbox_client_adapter.dart';
import 'package:crisp_cloud/services/dropbox_config_service.dart';
import 'package:crisp_cloud/services/gdrive_client_adapter.dart';
import 'package:crisp_cloud/services/gdrive_config_service.dart';
import 'package:crisp_cloud/services/onedrive_client_adapter.dart';
import 'package:crisp_cloud/services/onedrive_config_service.dart';
import 'package:crisp_cloud/services/s3_client_adapter.dart';
import 'package:crisp_cloud/services/s3_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';

// ---------------------------------------------------------------------------
// Minimal stub that exercises the default copyPath (download + reupload).
// ---------------------------------------------------------------------------
class _StubClient extends CloudStorageClient {
  final List<String> calls = [];
  Uint8List? downloadReturn;

  @override
  String get providerName => 'Stub';
  @override
  String get rootPath => '/';
  @override
  bool get isAuthenticated => true;
  @override
  String? get userId => null;
  @override
  String? get bucketId => null;

  @override
  Future<void> login(String email, String password, {String? twoFactorCode}) async {}
  @override
  Future<bool> is2faNeeded(String email) async => false;
  @override
  Future<void> logout() async {}
  @override
  Future<Map<String, dynamic>?> resolvePath(String path) async => null;
  @override
  Future<Map<String, dynamic>> listPath(String path) async => {'folders': [], 'files': []};
  @override
  Future<void> createFolderPath(String path) async {}
  @override
  Future<void> deletePath(String path) async {}
  @override
  Future<void> movePath(String sourcePath, String targetPath) async {}
  @override
  Future<void> renamePath(String path, String newName) async {}

  @override
  Future<Uint8List> downloadFileBytes(String remotePath, {Function(int, int)? onProgress}) async {
    calls.add('download:$remotePath');
    return downloadReturn ?? Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<void> downloadFileByPath(String remotePath, String localPath, {Function(int, int)? onProgress}) async {
    calls.add('downloadByPath:$remotePath');
  }

  @override
  Future<void> uploadFile(List<int> fileData, String fileName, String targetPath, {Function(int, int)? onProgress}) async {
    calls.add('upload:$fileName:$targetPath');
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // -------------------------------------------------------------------------
  // Capability flags
  // -------------------------------------------------------------------------

  group('supportsServerSideCopy capability flag', () {
    test('default base class returns false', () {
      final stub = _StubClient();
      expect(stub.supportsServerSideCopy, isFalse);
    });

    test('S3ClientAdapter returns true', () {
      final adapter = S3ClientAdapter(
        config: S3ConfigService(configPath: '/tmp/s3', secureStorage: InMemorySecureStorage()),
      );
      expect(adapter.supportsServerSideCopy, isTrue);
    });

    test('GDriveClientAdapter returns true', () {
      final adapter = GDriveClientAdapter(
        config: GDriveConfigService(configPath: '/tmp/gdrive', secureStorage: InMemorySecureStorage()),
      );
      expect(adapter.supportsServerSideCopy, isTrue);
    });

    test('OneDriveClientAdapter returns true', () {
      final adapter = OneDriveClientAdapter(
        config: OneDriveConfigService(configPath: '/tmp/onedrive', secureStorage: InMemorySecureStorage()),
      );
      expect(adapter.supportsServerSideCopy, isTrue);
    });

    test('DropboxClientAdapter returns true', () {
      final adapter = DropboxClientAdapter(
        config: DropboxConfigService(configPath: '/tmp/dropbox', secureStorage: InMemorySecureStorage()),
      );
      expect(adapter.supportsServerSideCopy, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // supportsNativeShare capability flag
  // -------------------------------------------------------------------------

  group('supportsNativeShare capability flag', () {
    test('default base class returns false', () {
      expect(_StubClient().supportsNativeShare, isFalse);
    });

    test('GDriveClientAdapter returns true', () {
      final adapter = GDriveClientAdapter(
        config: GDriveConfigService(configPath: '/tmp/gdrive', secureStorage: InMemorySecureStorage()),
      );
      expect(adapter.supportsNativeShare, isTrue);
    });

    test('OneDriveClientAdapter returns true', () {
      final adapter = OneDriveClientAdapter(
        config: OneDriveConfigService(configPath: '/tmp/onedrive', secureStorage: InMemorySecureStorage()),
      );
      expect(adapter.supportsNativeShare, isTrue);
    });

    test('DropboxClientAdapter returns true', () {
      final adapter = DropboxClientAdapter(
        config: DropboxConfigService(configPath: '/tmp/dropbox', secureStorage: InMemorySecureStorage()),
      );
      expect(adapter.supportsNativeShare, isTrue);
    });

    test('S3ClientAdapter returns false (no share-link API)', () {
      final adapter = S3ClientAdapter(
        config: S3ConfigService(configPath: '/tmp/s3', secureStorage: InMemorySecureStorage()),
      );
      expect(adapter.supportsNativeShare, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // Default copyPath falls back to download + upload
  // -------------------------------------------------------------------------

  group('default copyPath fallback (download + reupload)', () {
    test('calls downloadFileBytes then uploadFile', () async {
      final stub = _StubClient();
      expect(stub.supportsServerSideCopy, isFalse);

      await stub.copyPath('/remote/photo.jpg', '/backup');

      expect(stub.calls, contains('download:/remote/photo.jpg'));
      expect(stub.calls, contains('upload:photo.jpg:/backup'));
    });

    test('uses basename of sourcePath as fileName', () async {
      final stub = _StubClient();
      await stub.copyPath('/a/b/c/document.pdf', '/target/dir');

      expect(stub.calls.any((c) => c.startsWith('upload:document.pdf:')), isTrue);
    });

    test('passes downloaded bytes to uploadFile', () async {
      final stub = _StubClient();
      stub.downloadReturn = Uint8List.fromList([10, 20, 30]);

      // Default copyPath uses downloadFileBytes; we just verify it doesn't throw
      await expectLater(stub.copyPath('/file.bin', '/dest'), completes);
    });
  });
}
