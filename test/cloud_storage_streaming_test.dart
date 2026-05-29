import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';

/// Mock client to test default streaming implementations
class MockCloudClient implements CloudStorageClient {
  List<int>? lastUploadedData;
  final Uint8List downloadData;

  MockCloudClient({Uint8List? downloadData})
      : downloadData = downloadData ?? Uint8List.fromList([1, 2, 3, 4, 5]);

  @override String get providerName => 'Mock';
  @override String get rootPath => '/';
  @override bool get isAuthenticated => true;
  @override String? get userId => 'test';
  @override String? get bucketId => null;

  @override Future<void> login(String email, String password, {String? twoFactorCode}) async {}
  @override Future<bool> is2faNeeded(String email) async => false;
  @override Future<void> logout() async {}
  @override Future<Map<String, dynamic>?> resolvePath(String path) async => null;
  @override Future<Map<String, dynamic>> listPath(String path) async => {'folders': [], 'files': []};
  @override Future<void> createFolderPath(String path) async {}
  @override Future<void> deletePath(String path) async {}
  @override Future<void> movePath(String sourcePath, String targetPath) async {}
  @override Future<void> renamePath(String path, String newName) async {}

  @override
  Future<void> uploadFile(List<int> fileData, String fileName, String targetPath, {Function(int, int)? onProgress}) async {
    lastUploadedData = fileData;
    onProgress?.call(fileData.length, fileData.length);
  }

  @override
  Future<void> downloadFileByPath(String remotePath, String localPath, {Function(int, int)? onProgress}) async {}

  @override
  Future<Uint8List> downloadFileBytes(String remotePath, {Function(int, int)? onProgress}) async {
    onProgress?.call(downloadData.length, downloadData.length);
    return downloadData;
  }
}

void main() {
  group('CloudStorageClient default streaming', () {
    test('uploadStream buffers stream and calls uploadFile', () async {
      final client = MockCloudClient();
      final stream = Stream.fromIterable([
        [1, 2, 3],
        [4, 5, 6],
      ]);

      await client.uploadStream(stream, 6, 'test.txt', '/remote');

      expect(client.lastUploadedData, [1, 2, 3, 4, 5, 6]);
    });

    test('downloadStream yields bytes from downloadFileBytes', () async {
      final data = Uint8List.fromList([10, 20, 30]);
      final client = MockCloudClient(downloadData: data);

      final chunks = await client.downloadStream('/remote/file.txt').toList();

      expect(chunks.length, 1);
      expect(chunks.first, data);
    });

    test('default capability flags are false', () {
      final client = MockCloudClient();
      expect(client.supportsStreaming, isFalse);
      expect(client.supportsMultipart, isFalse);
      expect(client.supportsVersioning, isFalse);
      expect(client.supportsSharing, isFalse);
      expect(client.supportsSearch, isFalse);
      expect(client.supportsThumbnails, isFalse);
      expect(client.supportsTrash, isTrue);
    });
  });
}
