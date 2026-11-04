import 'dart:typed_data';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/operation_progress.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/multi_cloud_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FixtureClient extends CloudStorageClient {
  final bool failBad;
  final uploaded = <String>[];
  _FixtureClient({this.failBad = false});

  @override
  String get providerName => 'Fixture';
  @override
  Future<Uint8List> downloadFileBytes(String remotePath,
      {Function(int, int)? onProgress}) async {
    if (failBad && remotePath.endsWith('bad.txt')) {
      throw Exception('fixture failure');
    }
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<void> uploadFile(List<int> data, String name, String target,
      {Function(int, int)? onProgress}) async {
    uploaded.add(name);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<void> waitForCompletion(OperationProgress operation) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!operation.isComplete) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('Transfer timed out');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  test('mixed cross-cloud batch fails without losing the successful file',
      () async {
    final service = MultiCloudService();
    addTearDown(service.dispose);
    final source = _FixtureClient(failBad: true);
    final target = _FixtureClient();
    final result = await service.transferBetweenClouds(
      sourceClient: source,
      sourcePath: '/',
      targetClient: target,
      targetPath: '/',
      files: [
        FileItem(name: 'good.txt', path: '/good.txt', isFolder: false, size: 3),
        FileItem(name: 'bad.txt', path: '/bad.txt', isFolder: false, size: 3),
      ],
    );
    await waitForCompletion(result);
    expect(result.status, OperationStatus.failed);
    expect(result.errorMessage, '1 of 2 files failed');
    expect(result.errorCode, TransferErrorCode.someFilesFailed);
    expect(result.files!.first.isComplete, isTrue);
    expect(result.files!.last.error, contains('fixture failure'));
    expect(target.uploaded, ['good.txt']);
  });

  test('successful cross-cloud batch still completes', () async {
    final service = MultiCloudService();
    addTearDown(service.dispose);
    final target = _FixtureClient();
    final result = await service.transferBetweenClouds(
      sourceClient: _FixtureClient(),
      sourcePath: '/',
      targetClient: target,
      targetPath: '/',
      files: [
        FileItem(name: 'good.txt', path: '/good.txt', isFolder: false, size: 3)
      ],
    );
    await waitForCompletion(result);
    expect(result.status, OperationStatus.completed);
    expect(result.errorMessage, isNull);
    expect(target.uploaded, ['good.txt']);
  });
}
