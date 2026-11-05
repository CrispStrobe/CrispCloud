import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/file_cache_service.dart';
import 'package:crisp_cloud/services/local_file_service_native.dart';
import 'package:crisp_cloud/services/media_file_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

FileItem _file(String path) =>
    FileItem(name: p.basename(path), path: path, isFolder: false);

Matcher _failure(MediaStoreFailure reason) => throwsA(
  isA<MediaStoreException>().having((error) => error.reason, 'reason', reason),
);

Uint8List _bytes(int seed, [int length = 4096]) =>
    Uint8List.fromList(List.generate(length, (index) => (index + seed) % 256));

Future<String> _rendered(MediaFileStore store, {int seed = 2, int length = 2048}) async {
  final path = await store.createOutputPath('wav');
  await File(path).writeAsBytes(_bytes(seed, length), flush: true);
  return path;
}

void main() {
  group('local media snapshots and copies', () {
    late Directory directory;
    late Directory temporary;
    late File original;
    late _ScopedFiles service;
    late MediaFileStore store;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('media-local-test-');
      temporary = await Directory(p.join(directory.path, 'temporary')).create();
      original = await File(p.join(directory.path, 'source.wav'))
          .writeAsBytes(_bytes(1), flush: true);
      service = _ScopedFiles();
      store = MediaFileStore.local(
        service: service,
        file: _file(original.path),
        temporaryDirectory: temporary.path,
      );
    });

    tearDown(() async {
      await store.dispose();
      await directory.delete(recursive: true);
    });

    test('stages a private immutable file without reading all bytes through the service', () async {
      final snapshot = await store.stage();
      expect(snapshot, isNot(original.path));
      expect(await File(snapshot).readAsBytes(), _bytes(1));
      expect(service.accesses, [(original.path, false)]);
      expect(service.activeScopes, 0);

      await original.writeAsBytes(_bytes(7));
      expect(await File(snapshot).readAsBytes(), _bytes(1));
      expect(await store.stage(), snapshot, reason: 'One snapshot per edit session');
      expect(service.accesses, hasLength(1));
    });

    test('two editors and two renders never share a temporary path', () async {
      final other = MediaFileStore.local(
        service: service,
        file: _file(original.path),
        temporaryDirectory: temporary.path,
      );
      addTearDown(other.dispose);
      final first = await store.stage();
      final second = await other.stage();
      expect(p.dirname(first), isNot(p.dirname(second)));
      expect(await store.createOutputPath('.wav'), isNot(await store.createOutputPath('wav')));
      await store.dispose();
      expect(await File(first).exists(), isFalse);
      expect(await File(second).exists(), isTrue);
      expect(await original.exists(), isTrue);
    });

    test('exports a copy under a write scope and leaves the source and render intact', () async {
      final snapshot = await store.stage();
      final output = await _rendered(store);
      final copy = File(p.join(directory.path, 'edited-63ab.wav'));
      expect(await store.saveCopy(output, p.basename(copy.path)), MediaSaveOutcome.savedCopy);
      expect(await copy.readAsBytes(), _bytes(2, 2048));
      expect(await original.readAsBytes(), _bytes(1));
      expect(await File(output).readAsBytes(), _bytes(2, 2048));
      expect(service.accesses, [(original.path, false), (copy.path, true)]);
      expect(service.activeScopes, 0);

      await store.dispose();
      expect(await Directory(p.dirname(snapshot)).exists(), isFalse);
      expect(await copy.readAsBytes(), _bytes(2, 2048));
    });

    test('an existing file or directory cannot be overwritten and retry uses the same render', () async {
      await store.stage();
      final output = await _rendered(store);
      final existing = await File(p.join(directory.path, 'copy.wav')).writeAsBytes(_bytes(9));
      await expectLater(store.saveCopy(output, 'copy.wav'), _failure(MediaStoreFailure.nameConflict));
      expect(await existing.readAsBytes(), _bytes(9));
      await Directory(p.join(directory.path, 'folder.wav')).create();
      await expectLater(store.saveCopy(output, 'folder.wav'), _failure(MediaStoreFailure.nameConflict));
      expect(await File(output).exists(), isTrue);
      expect(await store.saveCopy(output, 'retry.wav'), MediaSaveOutcome.savedCopy);
      expect(await File(p.join(directory.path, 'retry.wav')).readAsBytes(), _bytes(2, 2048));
    });

    test('concurrent editors reserve the destination exclusively', () async {
      final other = MediaFileStore.local(
        service: service,
        file: _file(original.path),
        temporaryDirectory: temporary.path,
      );
      addTearDown(other.dispose);
      await Future.wait([store.stage(), other.stage()]);
      final outputs = await Future.wait([
        _rendered(store, seed: 3),
        _rendered(other, seed: 5),
      ]);
      Future<Object> save(MediaFileStore editor, String output) async {
        try {
          return await editor.saveCopy(output, 'same-name.wav');
        } catch (error) {
          return error;
        }
      }

      final results = await Future.wait([
        save(store, outputs[0]),
        save(other, outputs[1]),
      ]);
      expect(results.whereType<MediaSaveOutcome>().toList(), [MediaSaveOutcome.savedCopy]);
      expect(results.whereType<MediaStoreException>().single.reason, MediaStoreFailure.nameConflict);
      expect(
        await File(p.join(directory.path, 'same-name.wav')).readAsBytes(),
        anyOf(_bytes(3, 2048), _bytes(5, 2048)),
      );
      expect(await original.readAsBytes(), _bytes(1));
    });

    test('rejects source name, path traversal, invalid names and misleading extensions', () async {
      await store.stage();
      final output = await _rendered(store);
      for (final name in ['source.wav', 'SOURCE.WAV']) {
        await expectLater(store.saveCopy(output, name), _failure(MediaStoreFailure.nameConflict));
      }
      for (final name in [
        '../escape.wav',
        'sub/copy.wav',
        r'sub\copy.wav',
        'nul.wav',
        'bad:name.wav',
        'bad\u0000.wav',
        'copy.mp4',
        '..',
        '',
      ]) {
        await expectLater(store.saveCopy(output, name), _failure(MediaStoreFailure.invalidName));
      }
      expect(await original.readAsBytes(), _bytes(1));
    });

    test('requires a staged session and an owned, nonempty rendered file', () async {
      await expectLater(store.createOutputPath('wav'), _failure(MediaStoreFailure.notStaged));
      final snapshot = await store.stage();
      await expectLater(store.createOutputPath('../wav'), _failure(MediaStoreFailure.invalidOutput));
      await expectLater(store.saveCopy(original.path, 'copy.wav'), _failure(MediaStoreFailure.invalidOutput));
      await expectLater(store.saveCopy(snapshot, 'copy.wav'), _failure(MediaStoreFailure.invalidOutput));
      final empty = await store.createOutputPath('wav');
      await File(empty).create();
      await expectLater(store.saveCopy(empty, 'copy.wav'), _failure(MediaStoreFailure.emptyOutput));
      expect(await File(p.join(directory.path, 'copy.wav')).exists(), isFalse);
    });

    test('neither an output symlink nor a destination symlink can replace another file', () async {
      if (Platform.isWindows) return;
      await store.stage();
      final outputLink = await store.createOutputPath('wav');
      await Link(outputLink).create(original.path);
      await expectLater(store.saveCopy(outputLink, 'copy.wav'), _failure(MediaStoreFailure.invalidOutput));
      final output = await _rendered(store);
      final destination = Link(p.join(directory.path, 'linked.wav'));
      await destination.create(original.path);
      await expectLater(store.saveCopy(output, 'linked.wav'), _failure(MediaStoreFailure.nameConflict));
      expect(await destination.exists(), isTrue);
      expect(await original.readAsBytes(), _bytes(1));
    });

    test('checks fresh local input and rendered output sizes', () async {
      await store.dispose();
      store = MediaFileStore.local(
        service: service,
        file: _file(original.path).copyWith(size: 1),
        inputLimitBytes: 4095,
        temporaryDirectory: temporary.path,
      );
      await expectLater(store.stage(), _failure(MediaStoreFailure.tooLarge));
      expect(await original.readAsBytes(), _bytes(1));
      await store.dispose();
      store = MediaFileStore.local(
        service: service,
        file: _file(original.path),
        outputLimitBytes: 2047,
        temporaryDirectory: temporary.path,
      );
      await store.stage();
      final output = await _rendered(store);
      await expectLater(store.saveCopy(output, 'copy.wav'), _failure(MediaStoreFailure.tooLarge));
      expect(await File(output).exists(), isTrue);
      expect(await File(p.join(directory.path, 'copy.wav')).exists(), isFalse);
    });

    test('a denied write keeps the render for retry and releases scopes', () async {
      await store.stage();
      final output = await _rendered(store);
      service.denyWrites = true;
      await expectLater(store.saveCopy(output, 'copy.wav'), _failure(MediaStoreFailure.accessDenied));
      expect(service.activeScopes, 0);
      expect(await File(output).exists(), isTrue);
      service.denyWrites = false;
      expect(await store.saveCopy(output, 'copy.wav'), MediaSaveOutcome.savedCopy);
    });

    test('overlapping operations cannot delete or replace an in-flight save', () async {
      await store.stage();
      final output = await _rendered(store);
      service.writeGate = Completer<void>();
      final saving = store.saveCopy(output, 'copy.wav');
      await service.writeStarted.future;
      await expectLater(store.saveCopy(output, 'second.wav'), _failure(MediaStoreFailure.busy));
      await expectLater(store.stage(), _failure(MediaStoreFailure.busy));
      await expectLater(store.createOutputPath('wav'), _failure(MediaStoreFailure.busy));
      service.writeGate!.complete();
      expect(await saving, MediaSaveOutcome.savedCopy);
      expect(await File(p.join(directory.path, 'copy.wav')).readAsBytes(), _bytes(2, 2048));
    });
  });

  group('remote media copies', () {
    late Directory temporary;
    late _Cloud client;
    late _Cache cache;
    late MediaFileStore store;
    var current = true;

    setUp(() async {
      temporary = await Directory.systemTemp.createTemp('media-remote-test-');
      client = _Cloud()..files['/media/source.wav'] = _bytes(1);
      cache = _Cache();
      current = true;
      store = MediaFileStore.remote(
        client: client,
        providerName: 'fixture-cloud',
        cache: cache,
        file: _file('/media/source.wav'),
        isCurrentAccount: () => current,
        temporaryDirectory: temporary.path,
      );
    });

    tearDown(() async {
      await store.dispose();
      await temporary.delete(recursive: true);
    });

    test('stages fresh chunks, creates a separate copy, and invalidates only its cache key', () async {
      final snapshot = await store.stage();
      expect(await File(snapshot).readAsBytes(), _bytes(1));
      expect(client.downloads, 1);
      expect(cache.reads, 0);
      final output = await _rendered(store);
      expect(await store.saveCopy(output, 'edited-65ad.wav'), MediaSaveOutcome.savedCopy);
      expect(client.files['/media/source.wav'], _bytes(1));
      expect(client.files['/media/edited-65ad.wav'], _bytes(2, 2048));
      expect(client.uploads, ['/media/edited-65ad.wav']);
      expect(cache.removed, ['fixture-cloud:/media/edited-65ad.wav']);
    });

    test('a streaming flag cannot bypass the conservative remote transfer limit', () async {
      client.reportedSize = kMediaRemoteTransferLimitBytes + 1;
      expect(client.supportsStreaming, isTrue);
      await expectLater(
        store.stage(),
        throwsA(isA<MediaStoreException>()
            .having((error) => error.reason, 'reason', MediaStoreFailure.tooLarge)
            .having((error) => error.limitBytes, 'limit', kMediaRemoteTransferLimitBytes)),
      );
      expect(client.downloads, 0);
    });

    test('the remote output budget is checked before destination queries or upload', () async {
      await store.dispose();
      store = MediaFileStore.remote(
        client: client,
        providerName: 'fixture-cloud',
        cache: cache,
        file: _file('/media/source.wav'),
        isCurrentAccount: () => current,
        transferLimitBytes: 4096,
        temporaryDirectory: temporary.path,
      );
      await store.stage();
      final output = await _rendered(store, length: 4097);
      await expectLater(store.saveCopy(output, 'copy.wav'), _failure(MediaStoreFailure.tooLarge));
      expect(client.uploads, isEmpty);
      expect(await File(output).exists(), isTrue);
    });

    test('unknown or missing fresh source metadata never starts a buffering fallback', () async {
      client.hideSize = true;
      await expectLater(store.stage(), _failure(MediaStoreFailure.sourceUnavailable));
      expect(client.downloads, 0);
      client.hideSize = false;
      client.hideMetadata = true;
      await expectLater(store.stage(), _failure(MediaStoreFailure.sourceUnavailable));
      expect(client.downloads, 0);
    });

    test('counts received bytes even when metadata understates the file', () async {
      await store.dispose();
      store = MediaFileStore.remote(
        client: client,
        providerName: 'fixture-cloud',
        cache: cache,
        file: _file('/media/source.wav'),
        isCurrentAccount: () => current,
        transferLimitBytes: 2048,
        temporaryDirectory: temporary.path,
      );
      client.reportedSize = 1;
      await expectLater(store.stage(), _failure(MediaStoreFailure.tooLarge));
      expect(await temporary.list(recursive: true).where((entry) => entry is File).toList(), isEmpty);
    });

    test('rejects changed revisions and removes interrupted download files before retry', () async {
      client.revision = 'v1';
      client.afterDownload = () => client.revision = 'v2';
      await expectLater(store.stage(), _failure(MediaStoreFailure.sourceChanged));
      expect(await temporary.list(recursive: true).where((entry) => entry is File).toList(), isEmpty);
      client.afterDownload = null;
      client.failDownload = true;
      await expectLater(store.stage(), throwsStateError);
      expect(await temporary.list(recursive: true).where((entry) => entry is File).toList(), isEmpty);
      client.failDownload = false;
      expect(await File(await store.stage()).readAsBytes(), _bytes(1));
    });

    test('account binding is checked before and after staging and before persistence', () async {
      current = false;
      await expectLater(store.stage(), _failure(MediaStoreFailure.accountChanged));
      expect(client.downloads, 0);
      current = true;
      client.afterDownload = () => current = false;
      await expectLater(store.stage(), _failure(MediaStoreFailure.accountChanged));
      current = true;
      client.afterDownload = null;
      await store.stage();
      final output = await _rendered(store);
      client.accountUserId = 'different-user';
      await expectLater(store.saveCopy(output, 'copy.wav'), _failure(MediaStoreFailure.accountChanged));
      expect(client.uploads, isEmpty);
      client.accountUserId = 'user-1';
      client.afterListing = () => current = false;
      await expectLater(store.saveCopy(output, 'copy.wav'), _failure(MediaStoreFailure.accountChanged));
      expect(client.uploads, isEmpty);
    });

    test('a switch during an upload is not reported as a clean save to the new account', () async {
      await store.stage();
      final output = await _rendered(store);
      client.afterUpload = () => current = false;
      await expectLater(store.saveCopy(output, 'copy.wav'), _failure(MediaStoreFailure.accountChanged));
      // The generic provider API cannot revoke an upload already sent. The
      // honest result is uncertain persistence, with the render kept for review.
      expect(client.files['/media/copy.wav'], _bytes(2, 2048));
      expect(client.files['/media/source.wav'], _bytes(1));
      expect(await File(output).exists(), isTrue);
    });

    test('a failed upload preserves the rendered file for retry', () async {
      await store.stage();
      final output = await _rendered(store);
      client.failUpload = true;
      await expectLater(store.saveCopy(output, 'copy.wav'), throwsStateError);
      expect(client.files.containsKey('/media/copy.wav'), isFalse);
      expect(await File(output).readAsBytes(), _bytes(2, 2048));
      client.failUpload = false;
      expect(await store.saveCopy(output, 'copy.wav'), MediaSaveOutcome.savedCopy);
      expect(client.uploads, ['/media/copy.wav']);
    });

    test('existing names, including case variants hidden by lookup, are protected', () async {
      await store.stage();
      final output = await _rendered(store);
      client.files['/media/copy.wav'] = _bytes(9);
      await expectLater(store.saveCopy(output, 'copy.wav'), _failure(MediaStoreFailure.nameConflict));
      await expectLater(store.saveCopy(output, 'COPY.WAV'), _failure(MediaStoreFailure.nameConflict));
      await expectLater(store.saveCopy(output, 'SOURCE.WAV'), _failure(MediaStoreFailure.nameConflict));
      expect(client.files['/media/copy.wav'], _bytes(9));
      expect(client.uploads, isEmpty);
    });

    test('a null lookup and an unverified or missing original listing cannot authorize upload', () async {
      await store.stage();
      final output = await _rendered(store);
      client.hideMetadata = true;
      client.listingOverride = {'files': <dynamic>[], 'folders': <dynamic>[]};
      await expectLater(store.saveCopy(output, 'copy.wav'), _failure(MediaStoreFailure.unverifiedDestination));
      client.listingOverride = {'files': [{'name': 'source.wav'}]};
      await expectLater(store.saveCopy(output, 'copy.wav'), _failure(MediaStoreFailure.unverifiedDestination));
      client.failListing = true;
      await expectLater(store.saveCopy(output, 'copy.wav'), _failure(MediaStoreFailure.unverifiedDestination));
      expect(client.uploads, isEmpty);
    });

    test('a post-save cache failure does not turn a completed copy into a retry', () async {
      await store.stage();
      final output = await _rendered(store);
      cache.failRemove = true;
      expect(await store.saveCopy(output, 'copy.wav'), MediaSaveOutcome.savedCopy);
      expect(client.uploads, ['/media/copy.wav']);
    });

    test('dispose waits for an active download and cleans only its private directory', () async {
      final unrelated = await File(p.join(temporary.path, 'unrelated')).writeAsString('keep');
      client.downloadGate = Completer<void>();
      final loading = store.stage();
      final failedLoad = expectLater(loading, throwsStateError);
      await client.downloadStarted.future;
      var closed = false;
      final closing = store.dispose().then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      client.downloadGate!.complete();
      await failedLoad;
      await closing;
      expect(await unrelated.readAsString(), 'keep');
      expect(await temporary.list().length, 1);
      await expectLater(store.stage(), throwsStateError);
      await store.dispose();
    });
  });
}

class _ScopedFiles extends DesktopFileService {
  final accesses = <(String, bool)>[];
  int activeScopes = 0;
  bool denyWrites = false;
  Completer<void>? writeGate;
  final writeStarted = Completer<void>();

  @override
  Future<Uint8List> readFile(String path, {FileItem? fileItem}) =>
      throw StateError('The media editor must use file streaming.');

  @override
  Future<void> saveFile(String path, Uint8List data) =>
      throw StateError('The media editor must use file streaming.');

  @override
  Future<T> withMediaFileAccess<T>(
    String path,
    Future<T> Function(String accessiblePath) operation, {
    bool forWrite = false,
  }) async {
    accesses.add((path, forWrite));
    activeScopes++;
    try {
      if (forWrite) {
        if (!writeStarted.isCompleted) writeStarted.complete();
        await writeGate?.future;
        if (denyWrites) {
          throw FileSystemException('Denied', path, const OSError('Denied', 13));
        }
      }
      return await operation(path);
    } finally {
      activeScopes--;
    }
  }
}

class _Cloud extends CloudStorageClient {
  final files = <String, Uint8List>{};
  final uploads = <String>[];
  int downloads = 0;
  String accountUserId = 'user-1';
  String? revision;
  int? reportedSize;
  bool hideSize = false;
  bool hideMetadata = false;
  bool failDownload = false;
  bool failUpload = false;
  bool failListing = false;
  Map<String, dynamic>? listingOverride;
  Completer<void>? downloadGate;
  final downloadStarted = Completer<void>();
  void Function()? afterDownload;
  void Function()? afterListing;
  void Function()? afterUpload;

  @override
  bool get isAuthenticated => true;
  @override
  String? get userId => accountUserId;
  @override
  String? get bucketId => 'bucket-1';
  @override
  bool get supportsStreaming => true;

  @override
  Future<Map<String, dynamic>?> resolvePath(String path) async {
    if (hideMetadata) return null;
    final bytes = files[path];
    if (bytes == null) return null;
    return {
      'type': 'file',
      if (!hideSize) 'size': reportedSize ?? bytes.length,
      if (revision != null) 'versionId': revision,
    };
  }

  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    if (failListing) throw StateError('Unavailable listing');
    final listing = listingOverride ?? {
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
  Stream<List<int>> downloadStream(String remotePath, {Function(int, int)? onProgress}) async* {
    downloads++;
    if (!downloadStarted.isCompleted) downloadStarted.complete();
    await downloadGate?.future;
    final bytes = Uint8List.fromList(files[remotePath]!);
    for (var offset = 0; offset < bytes.length; offset += 1024) {
      yield bytes.sublist(offset, (offset + 1024).clamp(0, bytes.length).toInt());
      if (failDownload) throw StateError('Interrupted download');
    }
    afterDownload?.call();
  }

  @override
  Future<void> uploadFile(
    List<int> fileData,
    String fileName,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    if (failUpload) throw StateError('Upload failed');
    final target = p.posix.join(targetPath, fileName);
    uploads.add(target);
    files[target] = Uint8List.fromList(fileData);
    afterUpload?.call();
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
    if (failRemove) throw StateError('Cache unavailable');
  }
}
