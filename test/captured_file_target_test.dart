import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/services/captured_file_target.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/file_cache_service.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/services/storage_identity.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(String value) => Uint8List.fromList(utf8.encode(value));
final _file = FileItem(
  name: 'report.txt',
  path: '/docs/report.txt',
  isFolder: false,
);

class _Cloud extends Fake
    implements CloudStorageClient, StorageNamespaceIdentity {
  _Cloud({this.userId = 'account', this.storageNamespace = 'host:22'});
  @override
  String? userId;
  @override
  final String storageNamespace;
  @override
  String get providerName => 'Test';
  @override
  String? get bucketId => 'bucket';
  @override
  String get rootPath => '/';
  @override
  bool get isAuthenticated => true;
  Uint8List data = _bytes('original');
  int writes = 0;
  bool unreadable = false;
  @override
  Future<Map<String, dynamic>?> resolvePath(String path) async => {
    'size': data.length,
  };
  @override
  Future<Uint8List> downloadFileBytes(
    String remotePath, {
    Function(int, int)? onProgress,
  }) async {
    if (unreadable) throw StateError('Disconnected');
    return Uint8List.fromList(data);
  }

  @override
  Future<void> uploadFile(
    List<int> bytes,
    String name,
    String folder, {
    Function(int, int)? onProgress,
  }) async {
    expect('$folder/$name', _file.path);
    data = Uint8List.fromList(bytes);
    writes++;
  }
}

class _Cache extends Fake implements FileCacheService {
  @override
  Future<void> remove(String remotePath, String provider) async {}
}

class _Browser extends Fake
    implements LocalFileService, FreshLocalFileReader, LocalFileSaveReporter {
  Uint8List original = _bytes('original');
  @override
  Future<Uint8List> readFileFresh(
    String path, {
    FileItem? fileItem,
    int? maxBytes,
  }) async => Uint8List.fromList(original);
  @override
  Future<LocalFileSaveResult> saveFileWithResult(
    String path,
    Uint8List data, {
    bool overwrite = true,
  }) async => LocalFileSaveResult.downloadedCopy;
}

CapturedFileTarget _target(_Cloud client, {bool Function()? current}) =>
    CapturedFileTarget.remote(
      reference: FileReference(
        storage: storageReferenceForClient(client),
        path: _file.path!,
      ),
      client: client,
      cache: _Cache(),
      file: _file,
      isCurrent: current ?? () => true,
    );

void main() {
  test(
    'same connected account and namespace has stable serializable identity',
    () {
      final a = storageReferenceForClient(_Cloud());
      final b = storageReferenceForClient(_Cloud());
      expect(a, b);
      expect(StorageReference.fromJson(jsonDecode(jsonEncode(a.toJson()))), a);
      expect(jsonEncode(a.toJson()), isNot(contains('host:22')));
      expect(a.persistent, isTrue);
    },
  );

  test('ports, namespaces and accounts cannot alias', () {
    final a = storageReferenceForClient(_Cloud());
    expect(
      storageReferenceForClient(_Cloud(storageNamespace: 'host:2222')),
      isNot(a),
    );
    expect(storageReferenceForClient(_Cloud(userId: 'other')), isNot(a));
    final first = FileReference(storage: a, path: '/same');
    final second = FileReference(
      storage: storageReferenceForClient(_Cloud(userId: 'other')),
      path: '/same',
    );
    expect(first.id, isNot(second.id));
  });

  test(
    'unidentified accounts are session-only and never alias other clients',
    () {
      final a = _Cloud(userId: null);
      final ref = storageReferenceForClient(a);
      expect(ref.persistent, isFalse);
      expect(storageReferenceForClient(a), ref);
      expect(storageReferenceForClient(_Cloud(userId: null)), isNot(ref));
    },
  );

  test('remote panel sources distinguish identically named accounts', () {
    final a = RemotePanelSource(
      providerName: 'Test',
      client: _Cloud(),
      path: '/',
    );
    final b = RemotePanelSource(
      providerName: 'Test',
      client: _Cloud(),
      path: '/',
    );
    expect(a, isNot(b));
    expect(a.withPath('/'), a);
  });

  test(
    'text saves use the original captured client and update the baseline',
    () async {
      final original = _Cloud();
      final other = _Cloud(userId: 'other');
      final target = _target(original);
      expect(await target.load(), _bytes('original'));
      expect(
        await target.save(_bytes('edited')),
        FileWriteOutcome.savedOriginal,
      );
      expect(
        await target.save(_bytes('edited again')),
        FileWriteOutcome.savedOriginal,
      );
      expect(original.data, _bytes('edited again'));
      expect(other.writes, 0);
    },
  );

  test(
    'same-size external changes block a save even without revision metadata',
    () async {
      final client = _Cloud();
      final target = _target(client);
      await target.load();
      client.data = _bytes('external');
      await expectLater(
        target.save(_bytes('edited')),
        throwsA(isA<FileTargetConflict>()),
      );
      expect(client.writes, 0);
    },
  );

  test(
    'account changes and unreadable originals never authorize a write',
    () async {
      final client = _Cloud();
      var current = true;
      final target = _target(client, current: () => current);
      await target.load();
      current = false;
      await expectLater(
        target.save(_bytes('edited')),
        throwsA(isA<FileTargetConflict>()),
      );
      current = true;
      client.unreadable = true;
      await expectLater(
        target.save(_bytes('edited')),
        throwsA(isA<FileTargetConflict>()),
      );
      expect(client.writes, 0);
    },
  );

  test('relogin on the same client cannot redirect a save', () async {
    final client = _Cloud();
    final target = _target(client);
    await target.load();
    client.userId = 'different';
    await expectLater(
      target.save(_bytes('edited')),
      throwsA(isA<FileTargetConflict>()),
    );
    expect(client.writes, 0);
  });

  test(
    'browser download remains a copy and does not change the original baseline',
    () async {
      final service = _Browser();
      final target = CapturedFileTarget.local(
        reference: FileReference(
          storage: storageReferenceForSource(const LocalPanelSource('/')),
          path: _file.path!,
        ),
        service: service,
        file: _file,
        isCurrent: () => true,
      );
      await target.load();
      expect(
        await target.save(_bytes('edited')),
        FileWriteOutcome.downloadedCopy,
      );
      expect(
        await target.save(_bytes('again')),
        FileWriteOutcome.downloadedCopy,
      );
      expect(service.original, _bytes('original'));
    },
  );

  test('file references reject malformed persisted paths', () {
    expect(() => FileReference.fromJson({'path': ''}), throwsFormatException);
    expect(
      () => StorageReference.fromJson({'version': 99}),
      throwsFormatException,
    );
  });
}
