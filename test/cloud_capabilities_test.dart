import 'dart:typed_data';

import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:flutter_test/flutter_test.dart';

class _FeatureClient extends CloudStorageClient {
  @override
  bool get supportsStreaming => true;
  @override
  bool get supportsSharing => true;
  @override
  bool get supportsTrash => false;

  @override
  String? get bucketId => null;
  @override
  bool get isAuthenticated => true;
  @override
  String get providerName => 'Feature test';
  @override
  String get rootPath => '/';
  @override
  String? get userId => 'test';
  @override
  Future<void> createFolderPath(String path) async {}
  @override
  Future<void> deletePath(String path) async {}
  @override
  Future<Uint8List> downloadFileBytes(String remotePath,
          {Function(int, int)? onProgress}) async =>
      Uint8List(0);
  @override
  Future<void> downloadFileByPath(String remotePath, String localPath,
      {Function(int, int)? onProgress}) async {}
  @override
  Future<bool> is2faNeeded(String email) async => false;
  @override
  Future<Map<String, dynamic>> listPath(String path) async => {};
  @override
  Future<void> login(String email, String password,
      {String? twoFactorCode}) async {}
  @override
  Future<void> logout() async {}
  @override
  Future<void> movePath(String sourcePath, String targetPath) async {}
  @override
  Future<void> renamePath(String path, String newName) async {}
  @override
  Future<Map<String, dynamic>?> resolvePath(String path) async => null;
  @override
  Future<void> uploadFile(
      List<int> fileData, String fileName, String targetPath,
      {Function(int, int)? onProgress}) async {}
}

void main() {
  test('capability contract mirrors adapter flags', () {
    final capabilities = _FeatureClient().capabilities;

    expect(capabilities.streaming, isTrue);
    expect(capabilities.sharing, isTrue);
    expect(capabilities.trash, isFalse);
    expect(capabilities.multipart, isFalse);
    expect(capabilities.highlights, contains('low-memory transfers'));
  });

  test('every provider has useful onboarding metadata', () {
    for (final provider in CloudProvider.values) {
      expect(provider.displayName, isNotEmpty);
      expect(provider.onboardingDescription, endsWith('.'));
      expect(provider.credentialHint, endsWith('.'));
    }
  });
}
