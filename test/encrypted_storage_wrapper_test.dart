import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/encryption_service.dart';
import 'package:crisp_cloud/services/encrypted_storage_wrapper.dart';

/// Simple mock that records what was uploaded and serves fixed download data.
class MockCloudClient implements CloudStorageClient {
  List<int>? lastUploadedData;
  String? lastUploadedFileName;
  String? lastUploadedPath;
  Uint8List? _downloadData;

  /// Set this to control what downloadFileBytes returns.
  set downloadData(Uint8List data) => _downloadData = data;

  @override String get providerName => 'MockProvider';
  @override String get rootPath => '/';
  @override bool get isAuthenticated => true;
  @override String? get userId => 'mock-user';
  @override String? get bucketId => null;

  @override bool get supportsStreaming => true;
  @override bool get supportsMultipart => true;
  @override bool get supportsVersioning => true;
  @override bool get supportsSharing => true;
  @override bool get supportsSearch => true;
  @override bool get supportsThumbnails => true;
  @override bool get supportsTrash => true;

  @override Future<void> login(String email, String password, {String? twoFactorCode}) async {}
  @override Future<bool> is2faNeeded(String email) async => false;
  @override Future<void> logout() async {}
  @override Future<Map<String, dynamic>?> resolvePath(String path) async => null;
  @override Future<Map<String, dynamic>> listPath(String path) async => {'folders': [], 'files': []};
  @override Future<void> createFolderPath(String path) async {}
  @override Future<void> deletePath(String path) async {}
  @override Future<void> movePath(String s, String t) async {}
  @override Future<void> renamePath(String p, String n) async {}

  @override
  Future<void> uploadFile(List<int> fileData, String fileName, String targetPath,
      {Function(int, int)? onProgress}) async {
    lastUploadedData = fileData;
    lastUploadedFileName = fileName;
    lastUploadedPath = targetPath;
    onProgress?.call(fileData.length, fileData.length);
  }

  @override
  Future<void> downloadFileByPath(String remotePath, String localPath,
      {Function(int, int)? onProgress}) async {}

  @override
  Future<Uint8List> downloadFileBytes(String remotePath,
      {Function(int, int)? onProgress}) async {
    if (_downloadData == null) {
      throw StateError('Set downloadData before calling downloadFileBytes');
    }
    onProgress?.call(_downloadData!.length, _downloadData!.length);
    return _downloadData!;
  }
}

void main() {
  late Uint8List testKey;
  late MockCloudClient mockClient;
  late EncryptedStorageWrapper wrapper;

  setUp(() {
    final salt = EncryptionService.generateSalt();
    testKey = EncryptionService.deriveKey('test-passphrase', salt,
        iterations: 1000);
    mockClient = MockCloudClient();
    wrapper = EncryptedStorageWrapper(
      inner: mockClient,
      encryptionKey: testKey,
    );
  });

  group('EncryptedStorageWrapper', () {
    // -----------------------------------------------------------------------
    // Provider name
    // -----------------------------------------------------------------------
    test('providerName includes "(Encrypted)"', () {
      expect(wrapper.providerName, equals('MockProvider (Encrypted)'));
    });

    // -----------------------------------------------------------------------
    // Capability flags
    // -----------------------------------------------------------------------
    group('capability flags', () {
      test('supportsSharing is false', () {
        expect(wrapper.supportsSharing, isFalse);
      });

      test('supportsSearch is false', () {
        expect(wrapper.supportsSearch, isFalse);
      });

      test('supportsThumbnails is false', () {
        expect(wrapper.supportsThumbnails, isFalse);
      });

      test('supportsMultipart is false', () {
        expect(wrapper.supportsMultipart, isFalse);
      });

      test('supportsStreaming delegates to inner', () {
        expect(wrapper.supportsStreaming, isTrue);
      });

      test('supportsVersioning delegates to inner', () {
        expect(wrapper.supportsVersioning, isTrue);
      });

      test('supportsTrash delegates to inner', () {
        expect(wrapper.supportsTrash, isTrue);
      });
    });

    // -----------------------------------------------------------------------
    // Upload encryption
    // -----------------------------------------------------------------------
    group('uploadFile', () {
      test('encrypts data before passing to inner client', () async {
        final original = Uint8List.fromList([1, 2, 3, 4, 5]);
        await wrapper.uploadFile(original, 'test.bin', '/remote');

        // The data passed to the inner client should NOT equal the original
        expect(mockClient.lastUploadedData, isNotNull);
        expect(mockClient.lastUploadedData, isNot(equals(original)));
        // It should be larger (nonce + tag overhead)
        expect(mockClient.lastUploadedData!.length,
            greaterThan(original.length));
      });

      test('does not encrypt filename by default', () async {
        await wrapper.uploadFile(
            Uint8List.fromList([1]), 'report.pdf', '/remote');
        expect(mockClient.lastUploadedFileName, equals('report.pdf'));
      });

      test('encrypts filename when encryptFilenames is true', () async {
        final encWrapper = EncryptedStorageWrapper(
          inner: mockClient,
          encryptionKey: testKey,
          encryptFilenames: true,
        );
        await encWrapper.uploadFile(
            Uint8List.fromList([1]), 'report.pdf', '/remote');
        expect(mockClient.lastUploadedFileName, isNot(equals('report.pdf')));
      });
    });

    // -----------------------------------------------------------------------
    // Download decryption
    // -----------------------------------------------------------------------
    group('downloadFileBytes', () {
      test('returns decrypted data', () async {
        final original = Uint8List.fromList([10, 20, 30, 40, 50]);
        // Encrypt the data so the mock returns valid ciphertext
        final encrypted = EncryptionService.encrypt(original, testKey);
        mockClient.downloadData = encrypted;

        final result = await wrapper.downloadFileBytes('/remote/file.bin');
        expect(result, equals(original));
      });
    });

    // -----------------------------------------------------------------------
    // Upload then download round-trip
    // -----------------------------------------------------------------------
    test('upload then download round-trips correctly', () async {
      final original = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);

      // Upload encrypts the data
      await wrapper.uploadFile(original, 'data.bin', '/remote');
      final uploadedBytes = Uint8List.fromList(mockClient.lastUploadedData!);

      // Simulate download returning the same encrypted bytes
      mockClient.downloadData = uploadedBytes;
      final downloaded = await wrapper.downloadFileBytes('/remote/data.bin');

      expect(downloaded, equals(original));
    });

    // -----------------------------------------------------------------------
    // Stream upload buffers and encrypts
    // -----------------------------------------------------------------------
    test('uploadStream buffers and encrypts', () async {
      final stream = Stream.fromIterable([
        [1, 2, 3],
        [4, 5, 6],
      ]);

      await wrapper.uploadStream(stream, 6, 'stream.bin', '/remote');

      // The uploaded data is encrypted (not [1,2,3,4,5,6])
      expect(mockClient.lastUploadedData, isNot(equals([1, 2, 3, 4, 5, 6])));

      // Verify it can be decrypted back
      mockClient.downloadData =
          Uint8List.fromList(mockClient.lastUploadedData!);
      final decrypted = await wrapper.downloadFileBytes('/remote/stream.bin');
      expect(decrypted, equals(Uint8List.fromList([1, 2, 3, 4, 5, 6])));
    });

    // -----------------------------------------------------------------------
    // downloadStream yields decrypted data
    // -----------------------------------------------------------------------
    test('downloadStream yields decrypted data', () async {
      final original = Uint8List.fromList([99, 100, 101]);
      mockClient.downloadData = EncryptionService.encrypt(original, testKey);

      final chunks =
          await wrapper.downloadStream('/remote/file.bin').toList();
      expect(chunks.length, 1);
      expect(chunks.first, equals(original));
    });

    // -----------------------------------------------------------------------
    // Pass-through properties
    // -----------------------------------------------------------------------
    test('delegates isAuthenticated to inner', () {
      expect(wrapper.isAuthenticated, isTrue);
    });

    test('delegates userId to inner', () {
      expect(wrapper.userId, equals('mock-user'));
    });

    test('delegates rootPath to inner', () {
      expect(wrapper.rootPath, equals('/'));
    });
  });
}
