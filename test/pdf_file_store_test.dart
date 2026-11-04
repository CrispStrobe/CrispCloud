import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/file_cache_service.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/local_file_service_native.dart';
import 'package:crisp_cloud/services/pdf_edit_session.dart';
import 'package:crisp_cloud/services/pdf_file_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

Uint8List _bytes(int value) => Uint8List.fromList([37, 80, 68, 70, value]);

FileItem _file(String path) => FileItem(
      name: path.split('/').last,
      path: path,
      isFolder: false,
    );

void main() {
  group('remote PDF saves', () {
    late _Cloud client;
    late _Cache cache;
    late PdfFileStore store;

    setUp(() {
      client = _Cloud()..files['/docs/report.pdf'] = _bytes(1);
      cache = _Cache();
      store = PdfFileStore.remote(
        client: client,
        providerName: 'test-cloud',
        cache: cache,
        file: _file('/docs/report.pdf'),
      );
    });

    test('loads fresh bytes, saves through the captured client and invalidates',
        () async {
      expect(await store.load(), _bytes(1));
      expect(cache.reads, 0);
      expect(client.downloads, 1);

      expect(await store.save(_bytes(2)), PdfSaveOutcome.savedOriginal);
      expect(client.files['/docs/report.pdf'], _bytes(2));
      expect(client.uploads, ['/docs/report.pdf']);
      expect(cache.removed, ['test-cloud:/docs/report.pdf']);

      // Subsequent saves compare against the bytes just saved, not open-time.
      expect(await store.save(_bytes(3)), PdfSaveOutcome.savedOriginal);
      expect(client.files['/docs/report.pdf'], _bytes(3));
    });

    test('hash check catches same-size changes without metadata revisions',
        () async {
      await store.load();
      client.files['/docs/report.pdf'] = _bytes(9);
      await expectLater(
        store.save(_bytes(2)),
        throwsA(isA<PdfSaveConflictException>()),
      );
      expect(client.uploads, isEmpty);
      expect(client.files['/docs/report.pdf'], _bytes(9));
    });

    test('checks provider revision even when bytes have not changed', () async {
      client.revision = 'v1';
      await store.load();
      client.revision = 'v2';
      await expectLater(
        store.save(_bytes(2)),
        throwsA(isA<PdfSaveConflictException>()),
      );
      expect(client.downloads, 1, reason: 'A known revision conflict needs no GET');
      expect(client.uploads, isEmpty);
    });

    test('rejects a document changed during its initial read', () async {
      client.revision = 'v1';
      client.afterDownload = () => client.revision = 'v2';
      await expectLater(store.load(), throwsA(isA<PdfSaveConflictException>()));
      expect(client.uploads, isEmpty);
    });

    test('a missing or unreadable original is not recreated blindly', () async {
      await store.load();
      client.files.remove('/docs/report.pdf');
      await expectLater(
        store.save(_bytes(2)),
        throwsA(isA<PdfSaveConflictException>()),
      );
      expect(client.uploads, isEmpty);
    });

    test('an account switch cannot retarget an open document', () async {
      var stillCurrent = true;
      store = PdfFileStore.remote(
        client: client,
        providerName: 'test-cloud',
        cache: cache,
        file: _file('/docs/report.pdf'),
        isCurrentAccount: () => stillCurrent,
      );
      await store.load();
      stillCurrent = false;
      await expectLater(
        store.save(_bytes(2)),
        throwsA(isA<PdfAccountChangedException>()),
      );
      await expectLater(
        store.saveCopy(_bytes(2), 'copy.pdf'),
        throwsA(isA<PdfAccountChangedException>()),
      );
      expect(client.uploads, isEmpty);
    });

    test('detects relogin on the same mutable client object', () async {
      await store.load();
      client.accountUserId = 'another-user';
      await expectLater(
        store.save(_bytes(2)),
        throwsA(isA<PdfAccountChangedException>()),
      );
      expect(client.uploads, isEmpty);
    });

    test('Save copy rejects occupied targets and leaves the original baseline',
        () async {
      await store.load();
      client.files['/docs/copy.pdf'] = _bytes(8);
      await expectLater(
        store.saveCopy(_bytes(2), 'copy.pdf'),
        throwsA(isA<PdfSaveConflictException>()),
      );
      expect(client.files['/docs/copy.pdf'], _bytes(8));
      expect(await store.saveCopy(_bytes(2), 'new-copy'), PdfSaveOutcome.savedCopy);
      expect(client.files['/docs/new-copy.pdf'], _bytes(2));
      expect(client.files['/docs/report.pdf'], _bytes(1));
      expect(await store.save(_bytes(3)), PdfSaveOutcome.savedOriginal);
    });

    test('a masked lookup failure cannot overwrite an existing copy', () async {
      await store.load();
      client.files['/docs/copy.pdf'] = _bytes(8);
      client.maskResolveFailures = true;
      await expectLater(
        store.saveCopy(_bytes(2), 'copy.pdf'),
        throwsA(isA<PdfSaveConflictException>()),
      );
      expect(client.files['/docs/copy.pdf'], _bytes(8));
      expect(client.uploads, isEmpty);
    });

    test('copy creation fails closed on unavailable or masked folder listings',
        () async {
      await store.load();
      client.failListing = true;
      await expectLater(
        store.saveCopy(_bytes(2), 'copy.pdf'),
        throwsA(isA<PdfSaveConflictException>()),
      );
      client.failListing = false;
      for (final listing in <Map<String, dynamic>>[
        {'files': <dynamic>[], 'folders': <dynamic>[]},
        {'folders': <dynamic>[]},
        {
          'files': [null],
          'folders': <dynamic>[],
        },
      ]) {
        client.listingOverride = listing;
        await expectLater(
          store.saveCopy(_bytes(2), 'copy.pdf'),
          throwsA(isA<PdfSaveConflictException>()),
        );
      }
      expect(client.files['/docs/report.pdf'], _bytes(1));
      expect(client.uploads, isEmpty);
    });

    test('copy creation rejects case aliases and folder collisions', () async {
      await store.load();
      client.listingOverride = {
        'files': [
          {'name': 'report.pdf'},
        ],
        'folders': [
          {'name': 'COPY.PDF'},
        ],
      };
      await expectLater(
        store.saveCopy(_bytes(2), 'copy.pdf'),
        throwsA(isA<PdfSaveConflictException>()),
      );
      expect(client.uploads, isEmpty);
    });

    test('a changed original can be saved as a verified new copy', () async {
      await store.load();
      client.files['/docs/report.pdf'] = _bytes(9);
      expect(await store.saveCopy(_bytes(2), 'copy.pdf'), PdfSaveOutcome.savedCopy);
      expect(client.files['/docs/report.pdf'], _bytes(9));
      expect(client.files['/docs/copy.pdf'], _bytes(2));
    });

    test('a removed original cannot authorize an unverifiable copy destination',
        () async {
      await store.load();
      client.files.remove('/docs/report.pdf');
      await expectLater(
        store.saveCopy(_bytes(2), 'copy.pdf'),
        throwsA(isA<PdfSaveConflictException>()),
      );
      expect(client.uploads, isEmpty);
    });

    test('an account switch during copy verification blocks the write', () async {
      await store.load();
      client.afterListing = () => client.accountUserId = 'user-2';
      await expectLater(
        store.saveCopy(_bytes(2), 'copy.pdf'),
        throwsA(isA<PdfAccountChangedException>()),
      );
      expect(client.uploads, isEmpty);
    });

    test('copy names cannot traverse directories or name the original', () async {
      await store.load();
      for (final name in ['../report.pdf', '/report.pdf', r'..\report.pdf', '']) {
        await expectLater(store.saveCopy(_bytes(2), name), throwsArgumentError);
      }
      await expectLater(
        store.saveCopy(_bytes(2), 'report.pdf'),
        throwsA(isA<PdfSaveConflictException>()),
      );
      expect(client.uploads, isEmpty);
    });

    test('post-write metadata/cache failures do not turn a success into failure',
        () async {
      await store.load();
      client.failMetadataAfterUpload = true;
      cache.failRemove = true;
      expect(await store.save(_bytes(2)), PdfSaveOutcome.savedOriginal);
      expect(client.files['/docs/report.pdf'], _bytes(2));
      expect(cache.removed, ['test-cloud:/docs/report.pdf']);
    });

    test('refuses an oversized source before downloading it', () async {
      client.reportedSize = kPdfEditorInputLimitBytes + 1;
      await expectLater(store.load(), throwsA(isA<PdfFileTooLargeException>()));
      expect(client.downloads, 0);
    });

    test('a failed upload does not advance the overwrite baseline', () async {
      await store.load();
      client.failUpload = true;
      await expectLater(store.save(_bytes(2)), throwsStateError);
      client.failUpload = false;
      expect(await store.save(_bytes(2)), PdfSaveOutcome.savedOriginal);
    });

    test('the store rejects concurrent writes and reloads', () async {
      await store.load();
      client.uploadGate = Completer<void>();
      final saving = store.save(_bytes(2));
      await expectLater(
        store.saveCopy(_bytes(3), 'copy.pdf'),
        throwsA(isA<PdfSaveInProgressException>()),
      );
      await expectLater(
        store.load(),
        throwsA(isA<PdfSaveInProgressException>()),
      );
      client.uploadGate!.complete();
      expect(await saving, PdfSaveOutcome.savedOriginal);
      expect(client.uploads, ['/docs/report.pdf']);
    });

    test('a loading baseline cannot be replaced by another operation', () async {
      client.downloadGate = Completer<void>();
      final loading = store.load();
      await expectLater(store.load(), throwsStateError);
      await expectLater(store.saveCopy(_bytes(2), 'copy.pdf'), throwsStateError);
      client.downloadGate!.complete();
      expect(await loading, _bytes(1));
      expect(client.uploads, isEmpty);
    });
  });

  group('local PDF saves', () {
    late Directory dir;
    late File original;
    late PdfFileStore store;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('crisp_pdf_store_');
      original = File('${dir.path}/report.pdf');
      await original.writeAsBytes(_bytes(1));
      store = PdfFileStore.local(
        service: DesktopFileService(),
        file: _file(original.path),
      );
    });

    tearDown(() async => dir.delete(recursive: true));

    test('writes through the platform service and removes staging files',
        () async {
      await store.load();
      expect(await store.save(_bytes(2)), PdfSaveOutcome.savedOriginal);
      expect(await original.readAsBytes(), _bytes(2));
      expect(await dir.list().length, 1);
      expect(await store.save(_bytes(3)), PdfSaveOutcome.savedOriginal);
    });

    test('does not overwrite an external same-size edit', () async {
      await store.load();
      await original.writeAsBytes(_bytes(9));
      await expectLater(
        store.save(_bytes(2)),
        throwsA(isA<PdfSaveConflictException>()),
      );
      expect(await original.readAsBytes(), _bytes(9));
    });

    test('Save copy cannot truncate an existing file', () async {
      await store.load();
      final copy = File('${dir.path}/copy.pdf');
      await copy.writeAsBytes(_bytes(8));
      await expectLater(
        store.saveCopy(_bytes(2), 'copy.pdf'),
        throwsA(isA<PdfSaveConflictException>()),
      );
      expect(await copy.readAsBytes(), _bytes(8));
      expect(await store.saveCopy(_bytes(2), 'new.pdf'), PdfSaveOutcome.savedCopy);
      expect(await original.readAsBytes(), _bytes(1));
      expect(await File('${dir.path}/new.pdf').readAsBytes(), _bytes(2));
    });

    test('replacement preserves restrictive file permissions', () async {
      if (Platform.isWindows) return;
      final chmod = await Process.run('chmod', ['600', original.path]);
      expect(chmod.exitCode, 0);
      final mode = (await original.stat()).mode & 0xfff;
      await store.load();
      await store.save(_bytes(2));
      expect((await original.stat()).mode & 0xfff, mode);
    });

    test('parent rename access cannot bypass a read-only file mode', () async {
      if (Platform.isWindows) return;
      final chmod = await Process.run('chmod', ['400', original.path]);
      expect(chmod.exitCode, 0);
      await store.load();
      await expectLater(store.save(_bytes(2)), throwsA(isA<FileSystemException>()));
      expect(await original.readAsBytes(), _bytes(1));
      expect((await original.stat()).mode & 0xfff, 0x100);
      expect(await dir.list().length, 1, reason: 'Failed staging is removed');
    });

    test('symlink editing fails without replacing the link or its target',
        () async {
      if (Platform.isWindows) return;
      final link = Link('${dir.path}/link.pdf');
      await link.create(original.path);
      store = PdfFileStore.local(
        service: DesktopFileService(),
        file: _file(link.path),
      );
      await store.load();
      await expectLater(store.save(_bytes(2)), throwsA(isA<FileSystemException>()));
      expect(await link.exists(), isTrue);
      expect(await original.readAsBytes(), _bytes(1));
    });
  });

  test('fresh browser read and download outcome remain distinct from overwrite',
      () async {
    final service = _BrowserFiles();
    final store = PdfFileStore.local(
      service: service,
      file: _file('/picked/report.pdf'),
    );
    final session = PdfEditSession(initialBytes: await store.load());
    addTearDown(session.dispose);
    expect(service.freshReads, 1);
    expect(service.legacyReads, 0);
    session.updateBytes(_bytes(2));
    expect(await session.save(store.save), PdfSaveOutcome.downloadedCopy);
    expect(session.isDirty, isTrue);
    expect(service.current, _bytes(1));
    expect(service.freshReads, 2);
    expect(service.downloaded, _bytes(2));
  });
}

class _Cloud implements CloudStorageClient {
  final files = <String, Uint8List>{};
  final uploads = <String>[];
  int downloads = 0;
  String accountUserId = 'user-1';
  String? revision;
  int? reportedSize;
  bool failMetadataAfterUpload = false;
  bool failUpload = false;
  bool maskResolveFailures = false;
  bool failListing = false;
  Map<String, dynamic>? listingOverride;
  Completer<void>? downloadGate;
  Completer<void>? uploadGate;
  void Function()? afterDownload;
  void Function()? afterListing;

  @override
  bool get isAuthenticated => true;
  @override
  String? get userId => accountUserId;
  @override
  String? get bucketId => 'bucket-1';

  @override
  Future<Map<String, dynamic>?> resolvePath(String path) async {
    if (maskResolveFailures) return null;
    if (failMetadataAfterUpload && uploads.isNotEmpty) {
      throw StateError('Metadata temporarily unavailable');
    }
    final bytes = files[path];
    if (bytes == null) return null;
    return {
      'type': 'file',
      'size': reportedSize ?? bytes.length,
      if (revision != null) 'versionId': revision,
    };
  }

  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    if (failListing) throw StateError('Listing is unavailable');
    final listing = listingOverride ??
        {
          'files': [
            for (final entry in files.entries)
              if (p.posix.dirname(entry.key) == path)
                {'name': p.posix.basename(entry.key), 'size': entry.value.length},
          ],
          'folders': <Map<String, dynamic>>[],
        };
    afterListing?.call();
    return listing;
  }

  @override
  Future<Uint8List> downloadFileBytes(
    String remotePath, {
    Function(int, int)? onProgress,
  }) async {
    downloads++;
    await downloadGate?.future;
    final bytes = files[remotePath];
    if (bytes == null) throw StateError('File not found');
    final snapshot = Uint8List.fromList(bytes);
    afterDownload?.call();
    return snapshot;
  }

  @override
  Future<void> uploadFile(
    List<int> fileData,
    String fileName,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    if (failUpload) throw StateError('Upload failed');
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
    return _bytes(9);
  }

  @override
  Future<void> remove(String remotePath, String provider) async {
    removed.add('$provider:$remotePath');
    if (failRemove) throw StateError('Cache disk unavailable');
  }
}

class _BrowserFiles
    implements LocalFileService, LocalFileSaveReporter, FreshLocalFileReader {
  Uint8List current = _bytes(1);
  Uint8List? downloaded;
  int freshReads = 0;
  int legacyReads = 0;

  @override
  Future<Uint8List> readFileFresh(
    String path, {
    FileItem? fileItem,
    int? maxBytes,
  }) async {
    freshReads++;
    return Uint8List.fromList(current);
  }

  @override
  Future<Uint8List> readFile(String path, {FileItem? fileItem}) async {
    legacyReads++;
    return _bytes(9);
  }

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
