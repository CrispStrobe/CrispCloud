import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/archive_browser_session.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/archive_workspace.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';

Uint8List _zip(Map<String, List<int>> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile.bytes(entry.key, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

class _Source extends FileOperationBackend {
  _Source(this.bytes);
  Uint8List bytes;
  bool current = true;
  bool failAfterData = false;
  int? declaredSize;
  String revision = 'one';
  int chunksRead = 0;
  void Function()? afterChunk;
  final calls = <String>[];
  @override
  Object get identity => this;
  @override
  String get label => 'Captured storage';
  @override
  p.Context get paths => p.posix;
  @override
  bool get isCurrent => current;
  @override
  Future<FileItem?> stat(String path) async {
    calls.add('stat:$path');
    if (path != '/outer.zip') {
      throw StateError('Virtual path reached storage: $path');
    }
    return FileItem(
      name: 'outer.zip',
      path: path,
      isFolder: false,
      size: declaredSize ?? bytes.length,
      metadata: {'revision': revision},
    );
  }

  @override
  Stream<List<int>> readFile(FileItem file) async* {
    calls.add('read:${file.path}');
    if (file.path != '/outer.zip') {
      throw StateError('Virtual path reached storage');
    }
    for (var offset = 0; offset < bytes.length; offset += 97) {
      final end = offset + 97 < bytes.length ? offset + 97 : bytes.length;
      chunksRead++;
      yield Uint8List.sublistView(bytes, offset, end);
      afterChunk?.call();
    }
    if (failAfterData) throw StateError('Late storage failure');
  }

  @override
  Future<List<FileItem>> list(String path) async => throw UnimplementedError();
  @override
  Future<void> createDirectory(String path) async => throw UnimplementedError();
  @override
  Future<void> writeFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
  }) async => throw UnimplementedError();
  @override
  Future<void> deleteFile(FileItem file) async => throw UnimplementedError();
  @override
  Future<void> deleteEmptyDirectory(String path) async =>
      throw UnimplementedError();
}

/// A valid ZIP whose central directory follows 257 MiB of padding. The test
/// generates padding as reusable chunks and never allocates the whole input.
class _LargeZipSource extends _Source {
  _LargeZipSource()
    : super(
        _zip({
          'small.txt': [9],
        }),
      ) {
    final endRecord = bytes.length - 22;
    final view = ByteData.sublistView(bytes);
    expect(view.getUint32(endRecord, Endian.little), 0x06054b50);
    directoryOffset = view.getUint32(endRecord + 16, Endian.little);
    trailing = Uint8List.fromList(bytes.sublist(directoryOffset));
    ByteData.sublistView(trailing).setUint32(
      trailing.length - 22 + 16,
      directoryOffset + padding,
      Endian.little,
    );
    declaredSize = bytes.length + padding;
  }
  static const padding = 257 * 1024 * 1024;
  late final int directoryOffset;
  late final Uint8List trailing;
  int largestChunk = 0;
  @override
  Stream<List<int>> readFile(FileItem file) async* {
    calls.add('read:${file.path}');
    yield Uint8List.sublistView(bytes, 0, directoryOffset);
    final block = Uint8List(64 * 1024);
    for (var remaining = padding; remaining > 0; remaining -= block.length) {
      chunksRead++;
      largestChunk = block.length;
      yield block;
    }
    yield trailing;
  }
}

void main() {
  test(
    'native browsing spools input beyond the browser memory budget',
    () async {
      final source = _LargeZipSource();
      final file = (await source.stat('/outer.zip'))!;
      await expectLater(
        ArchiveBrowserSession.open(source, file, spoolToDisk: false),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(source.chunksRead, 0);
      final opened = await ArchiveBrowserSession.open(source, file);
      final temporary = opened.temporaryPath!;
      expect(await File(temporary).length(), file.size);
      expect(source.largestChunk, 64 * 1024);
      expect(await opened.read('small.txt'), [9]);
      await opened.close();
      expect(await File(temporary).exists(), isFalse);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('workspace refuses a changed outer snapshot even when size and metadata match', () async {
    final source = _Source(
      _zip({
        'a.txt': [1, 2, 3],
      }),
    );
    final file = (await source.stat('/outer.zip'))!;
    final opened = await ArchiveBrowserSession.open(
      source,
      file,
      spoolToDisk: false,
    );
    addTearDown(opened.close);
    source.bytes = Uint8List.fromList(source.bytes);
    source.bytes[source.bytes.length - 1] ^= 1;
    await expectLater(
      ArchiveWorkspace.openNested(
        source,
        file,
        const [],
        expectedOuterFingerprint: opened.fingerprint,
      ),
      throwsStateError,
    );
  });

  test(
    'native opening retains one disk snapshot and nested reads stay inside it',
    () async {
      final nested = _zip({'folder/same.txt': utf8.encode('inner')});
      final source = _Source(
        _zip({'outer.txt': utf8.encode('outer'), 'nested/inner.zip': nested}),
      );
      final opened = await ArchiveBrowserSession.open(
        source,
        (await source.stat('/outer.zip'))!,
      );
      final temporary = opened.temporaryPath!;
      expect(await File(temporary).exists(), isTrue);
      expect(
        opened.list('').map((file) => file.name),
        unorderedEquals(['outer.txt', 'nested']),
      );
      final backend = opened.backend;
      final childFile = (await backend.stat('/nested/inner.zip'))!;
      final child = await ArchiveBrowserSession.open(
        backend,
        childFile,
        maxInputBytes: kArchiveReadLimit,
      );
      final nestedTemporary = child.temporaryPath!;
      expect(utf8.decode(await child.read('folder/same.txt')), 'inner');
      expect(source.calls.where((call) => call.startsWith('read:')), [
        'read:/outer.zip',
      ]);
      expect(source.calls.every((call) => call.endsWith('/outer.zip')), isTrue);
      await child.close();
      expect(await File(nestedTemporary).exists(), isFalse);
      expect(opened.isCurrent, isTrue);
      await opened.close();
      expect(await File(temporary).parent.exists(), isFalse);
      await expectLater(
        opened.read('outer.txt'),
        throwsA(isA<ArchiveViewException>()),
      );
    },
  );

  test('memory fallback rejects oversized, truncated, changed and late-failing streams', () async {
    final bytes = _zip({
      'a.txt': [1, 2, 3],
    });
    final tooLarge = _Source(bytes);
    await expectLater(
      ArchiveBrowserSession.open(
        tooLarge,
        (await tooLarge.stat('/outer.zip'))!,
        maxInputBytes: 2,
        spoolToDisk: false,
      ),
      throwsA(isA<ArchiveViewException>()),
    );
    expect(tooLarge.chunksRead, 0);
    final truncated = _Source(bytes)..declaredSize = bytes.length + 1;
    await expectLater(
      ArchiveBrowserSession.open(
        truncated,
        (await truncated.stat('/outer.zip'))!,
        spoolToDisk: false,
      ),
      throwsA(isA<ArchiveViewException>()),
    );
    final changed = _Source(bytes);
    changed.afterChunk = () => changed.revision = 'two';
    await expectLater(
      ArchiveBrowserSession.open(
        changed,
        (await changed.stat('/outer.zip'))!,
        spoolToDisk: false,
      ),
      throwsA(isA<ArchiveViewException>()),
    );
    final failure = _Source(bytes)..failAfterData = true;
    await expectLater(
      ArchiveBrowserSession.open(
        failure,
        (await failure.stat('/outer.zip'))!,
        spoolToDisk: false,
      ),
      throwsStateError,
    );
  });

  test(
    'cancellation and source revocation stop opening before publication',
    () async {
      final source = _Source(_zip({'a.txt': List.filled(4096, 7)}));
      var cancelled = false;
      source.afterChunk = () => cancelled = true;
      await expectLater(
        ArchiveBrowserSession.open(
          source,
          (await source.stat('/outer.zip'))!,
          isCancelled: () => cancelled,
        ),
        throwsStateError,
      );
      expect(source.chunksRead, lessThan(4));
      final openedSource = _Source(
        _zip({
          'a.txt': [1],
        }),
      );
      final opened = await ArchiveBrowserSession.open(
        openedSource,
        (await openedSource.stat('/outer.zip'))!,
      );
      addTearDown(opened.close);
      openedSource.current = false;
      expect(() => opened.list(''), throwsA(isA<ArchiveViewException>()));
      await expectLater(
        opened.read('a.txt'),
        throwsA(isA<ArchiveViewException>()),
      );
    },
  );

  test(
    'browser namespace rejects traversal, duplicate aliases and file ancestors',
    () async {
      for (final entries in [
        {
          '../outside.txt': [1],
        },
        {
          'a.txt': [1],
          './a.txt': [2],
        },
        {
          'directory': [1],
          'directory/child.txt': [2],
        },
      ]) {
        final source = _Source(_zip(entries));
        await expectLater(
          ArchiveBrowserSession.open(
            source,
            (await source.stat('/outer.zip'))!,
            spoolToDisk: false,
          ),
          throwsA(isA<ArchiveViewException>()),
        );
      }
    },
  );

  test(
    'member reads require the exact path and respect their requested cap',
    () async {
      final source = _Source(
        _zip({
          'one/same.txt': [1],
          'two/same.txt': [2, 3],
        }),
      );
      final opened = await ArchiveBrowserSession.open(
        source,
        (await source.stat('/outer.zip'))!,
        spoolToDisk: false,
      );
      addTearDown(opened.close);
      expect(await opened.read('two/same.txt'), [2, 3]);
      await expectLater(
        opened.read('same.txt'),
        throwsA(isA<ArchiveViewException>()),
      );
      await expectLater(
        opened.read('two/same.txt', maxBytes: 1),
        throwsA(isA<ArchiveViewException>()),
      );
    },
  );
}
