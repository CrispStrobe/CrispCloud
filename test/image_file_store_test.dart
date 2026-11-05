import 'dart:async';
import 'dart:typed_data';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/file_cache_service.dart';
import 'package:crisp_cloud/services/image_edit_session.dart';
import 'package:crisp_cloud/services/image_file_store.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/image_editor_fixture.dart';

FileItem _file(String path) =>
    FileItem(name: path.split('/').last, path: path, isFolder: false);

void main() {
  group('image cloud persistence contract', () {
    late _Cloud client;
    late _Cache cache;
    late ImageFileStore store;
    late Uint8List original;

    setUp(() {
      original = buildImageEditorFixture();
      client = _Cloud()..files['/photos/sample.png'] = original;
      cache = _Cache();
      store = ImageFileStore.remote(
        client: client,
        providerName: 'fixture-cloud',
        cache: cache,
        file: _file('/photos/sample.png'),
      );
    });

    test(
      'loads fresh bytes and saves through the captured account/path',
      () async {
        expect(store.isRemote, isTrue);
        expect(
          store.documentId,
          'fixture-cloud:user-1:bucket-1:/photos/sample.png',
        );
        expect(await store.load(), original);
        expect(cache.reads, 0);
        expect(client.downloads, 1);
        final edited = buildImageEditorFixture(seed: 1);
        expect(await store.save(edited), ImageSaveOutcome.savedOriginal);
        expect(client.uploads, ['/photos/sample.png']);
        expect(client.files['/photos/sample.png'], edited);
        expect(cache.removed, ['fixture-cloud:/photos/sample.png']);
        // Advance the baseline only after the first actual write succeeds.
        final later = buildImageEditorFixture(seed: 2);
        expect(await store.save(later), ImageSaveOutcome.savedOriginal);
        expect(client.files['/photos/sample.png'], later);
      },
    );

    test('same-length external changes cannot be overwritten', () async {
      await store.load();
      final changed = Uint8List.fromList(original)..[original.length - 1] ^= 1;
      client.files['/photos/sample.png'] = changed;
      await expectLater(
        store.save(buildImageEditorFixture(seed: 1)),
        throwsA(isA<ImageSaveConflictException>()),
      );
      expect(client.uploads, isEmpty);
      expect(client.files['/photos/sample.png'], changed);
    });

    test(
      'provider revision changes are checked before a second download',
      () async {
        client.revision = 'v1';
        await store.load();
        client.revision = 'v2';
        await expectLater(
          store.save(buildImageEditorFixture(seed: 1)),
          throwsA(isA<ImageSaveConflictException>()),
        );
        expect(client.downloads, 1);
        expect(client.uploads, isEmpty);
      },
    );

    test('an account switch cannot retarget an image save', () async {
      var current = true;
      store = ImageFileStore.remote(
        client: client,
        providerName: 'fixture-cloud',
        cache: cache,
        file: _file('/photos/sample.png'),
        isCurrentAccount: () => current,
      );
      await store.load();
      current = false;
      await expectLater(
        store.save(buildImageEditorFixture(seed: 1)),
        throwsA(isA<ImageAccountChangedException>()),
      );
      current = true;
      client.accountUserId = 'user-2';
      await expectLater(
        store.save(buildImageEditorFixture(seed: 1)),
        throwsA(isA<ImageAccountChangedException>()),
      );
      expect(client.uploads, isEmpty);
    });

    test(
      'failed upload keeps edits dirty and allows retry against the original',
      () async {
        final session = ImageEditSession(
          initialBytes: await store.load(),
          format: ImageFileFormat.png,
        )..updateRevision(1);
        addTearDown(session.dispose);
        client.failUpload = true;
        await expectLater(
          session.save(
            export: () async => buildImageEditorFixture(seed: 1),
            write: store.save,
          ),
          throwsStateError,
        );
        expect(session.isDirty, isTrue);
        expect(client.files['/photos/sample.png'], original);
        client.failUpload = false;
        expect(
          await session.save(
            export: () async => buildImageEditorFixture(seed: 1),
            write: store.save,
          ),
          ImageSaveOutcome.savedOriginal,
        );
        expect(session.isDirty, isFalse);
      },
    );

    test(
      'enforces the image-specific input budget before downloading',
      () async {
        client.reportedSize = kImageEditorInputLimitBytes + 1;
        await expectLater(
          store.load(),
          throwsA(
            isA<ImageEditException>().having(
              (error) => error.reason,
              'reason',
              ImageEditFailure.inputTooLarge,
            ),
          ),
        );
        expect(client.downloads, 0);
      },
    );

    test('wrong-format exports cannot reach the provider', () async {
      await store.load();
      await expectLater(
        store.save(buildImageEditorFixture(format: ImageFileFormat.jpeg)),
        throwsA(
          isA<ImageEditException>().having(
            (error) => error.reason,
            'reason',
            ImageEditFailure.formatMismatch,
          ),
        ),
      );
      expect(client.uploads, isEmpty);
    });

    test('invalid input never establishes an editable baseline', () async {
      client.files['/photos/sample.png'] = imageTestAnimatedPng();
      await expectLater(
        store.load(),
        throwsA(
          isA<ImageEditException>().having(
            (error) => error.reason,
            'reason',
            ImageEditFailure.animatedImage,
          ),
        ),
      );
      await expectLater(
        store.save(buildImageEditorFixture()),
        throwsStateError,
      );
      expect(client.uploads, isEmpty);
    });

    test(
      'concurrent saves/reloads cannot discard an active save baseline',
      () async {
        await store.load();
        final upload = Completer<void>();
        client.uploadGate = upload;
        final saving = store.save(buildImageEditorFixture(seed: 1));
        await client.uploadStarted.future;
        await expectLater(
          store.load(),
          throwsA(isA<ImageSaveInProgressException>()),
        );
        await expectLater(
          store.save(buildImageEditorFixture(seed: 2)),
          throwsA(isA<ImageSaveInProgressException>()),
        );
        upload.complete();
        await saving;
        client.uploadGate = null;
        expect(
          await store.save(buildImageEditorFixture(seed: 2)),
          ImageSaveOutcome.savedOriginal,
        );
      },
    );

    test(
      'post-write cache failure does not turn a successful write into failure',
      () async {
        await store.load();
        cache.failRemove = true;
        expect(
          await store.save(buildImageEditorFixture(seed: 1)),
          ImageSaveOutcome.savedOriginal,
        );
        expect(client.uploads, hasLength(1));
        expect(cache.removed, hasLength(1));
      },
    );
  });

  test(
    'browser download keeps the image dirty and uses fresh source reads',
    () async {
      final service = _BrowserFiles();
      final store = ImageFileStore.local(
        service: service,
        file: _file('/picked/sample.png'),
      );
      final session = ImageEditSession(
        initialBytes: await store.load(),
        format: ImageFileFormat.png,
      )..updateRevision(1);
      addTearDown(session.dispose);
      expect(service.readLimits, [kImageEditorInputLimitBytes]);
      final edited = buildImageEditorFixture(seed: 1);
      expect(
        await session.save(export: () async => edited, write: store.save),
        ImageSaveOutcome.downloadedCopy,
      );
      expect(service.current, buildImageEditorFixture());
      expect(service.downloaded, edited);
      expect(service.readLimits, [
        kImageEditorInputLimitBytes,
        kImageEditorOutputLimitBytes,
      ]);
      expect(session.isDirty, isTrue);
      expect(session.savedRevision, 0);
    },
  );
}

class _Cloud implements CloudStorageClient {
  final files = <String, Uint8List>{};
  final uploads = <String>[];
  final uploadStarted = Completer<void>();
  Completer<void>? uploadGate;
  int downloads = 0;
  int? reportedSize;
  String? revision;
  String accountUserId = 'user-1';
  bool failUpload = false;

  @override
  bool get isAuthenticated => true;
  @override
  String? get userId => accountUserId;
  @override
  String? get bucketId => 'bucket-1';

  @override
  Future<Map<String, dynamic>?> resolvePath(String path) async {
    final bytes = files[path];
    if (bytes == null) return null;
    return {
      'type': 'file',
      'size': reportedSize ?? bytes.length,
      if (revision != null) 'versionId': revision,
    };
  }

  @override
  Future<Uint8List> downloadFileBytes(
    String remotePath, {
    Function(int, int)? onProgress,
  }) async {
    downloads++;
    final bytes = files[remotePath];
    if (bytes == null) throw StateError('Not found');
    return Uint8List.fromList(bytes);
  }

  @override
  Future<void> uploadFile(
    List<int> fileData,
    String fileName,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    if (failUpload) throw StateError('Upload failed');
    if (!uploadStarted.isCompleted) uploadStarted.complete();
    await uploadGate?.future;
    final target = '$targetPath/$fileName';
    uploads.add(target);
    files[target] = Uint8List.fromList(fileData);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Cache extends FileCacheService {
  int reads = 0;
  bool failRemove = false;
  final removed = <String>[];

  @override
  Future<List<int>?> get(String remotePath, String provider) async {
    reads++;
    throw StateError('Editor reads must not use preview cache');
  }

  @override
  Future<void> remove(String remotePath, String provider) async {
    removed.add('$provider:$remotePath');
    if (failRemove) throw StateError('Cache unavailable');
  }
}

class _BrowserFiles
    implements LocalFileService, LocalFileSaveReporter, FreshLocalFileReader {
  final Uint8List current = buildImageEditorFixture();
  final readLimits = <int?>[];
  Uint8List? downloaded;

  @override
  Future<Uint8List> readFileFresh(
    String path, {
    FileItem? fileItem,
    int? maxBytes,
  }) async {
    readLimits.add(maxBytes);
    return Uint8List.fromList(current);
  }

  @override
  Future<Uint8List> readFile(String path, {FileItem? fileItem}) async =>
      throw StateError('Do not read the stale browser File snapshot');

  @override
  Future<LocalFileSaveResult> saveFileWithResult(
    String path,
    Uint8List data, {
    bool overwrite = true,
  }) async {
    downloaded = Uint8List.fromList(data);
    return LocalFileSaveResult.downloadedCopy;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
