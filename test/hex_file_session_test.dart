import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:madedit2_hex/hex_document.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/hex_file_session.dart';

class MemoryBackend extends FileOperationBackend {
  final files = <String, List<int>>{
    '/a.bin': [1, 2, 3, 4],
  };
  bool current = true, staged = true, fail = false, corrupt = false;
  Future<void> Function()? beforeVerify;
  int commits = 0;
  @override
  bool get supportsStagedVerification => staged;
  @override
  bool get isCurrent => current;
  @override
  String get label => 'Test backend';
  @override
  p.Context get paths => p.Context(style: p.Style.posix);
  FileItem item(String path) => FileItem(
    name: paths.basename(path),
    path: path,
    isFolder: false,
    size: files[path]!.length,
    uuid: path,
    updatedAt: DateTime.utc(2026),
  );
  @override
  Future<FileItem?> stat(String path) async =>
      files.containsKey(path) ? item(path) : null;
  @override
  Stream<List<int>> readFile(FileItem file) async* {
    final bytes = List<int>.of(files[file.path]!);
    for (var i = 0; i < bytes.length; i += 2) {
      yield bytes.sublist(i, i + 2 > bytes.length ? bytes.length : i + 2);
    }
  }

  @override
  Future<void> writePreparedFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
    Future<void> Function(FileItem)? verifyStaged,
    Future<void> Function(Map<String, dynamic>)? checkpoint,
  }) async {
    final bytes = <int>[];
    await for (final part in data) {
      bytes.addAll(part);
    }
    files['/stage'] = bytes;
    try {
      if (fail) throw StateError('simulated upload failure');
      if (corrupt && bytes.isNotEmpty) bytes[0] ^= 1;
      await beforeVerify?.call();
      await verifyStaged?.call(item('/stage'));
      await checkpoint?.call({'phase': 'committing'});
      if (!replace && files.containsKey(path))
        throw StateError('copy collision');
      files[path] = List.of(bytes);
      commits++;
      await checkpoint?.call({'phase': 'committed'});
    } finally {
      files.remove('/stage');
    }
  }

  @override
  Future<void> writeFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
  }) => throw StateError('Unstaged write must never be used');
  @override
  Future<List<FileItem>> list(String path) async =>
      files.keys.map(item).toList();
  @override
  Future<void> createDirectory(String path) async {}
  @override
  Future<void> deleteFile(FileItem file) async {
    files.remove(file.path);
  }

  @override
  Future<void> deleteEmptyDirectory(String path) async {}
}

void main() {
  test('streamed save is verified; original backing bytes remain immutable after save', () async {
    final backend = MemoryBackend();
    final session = await HexFileSession.open(
      backend: backend,
      file: backend.item('/a.bin'),
    );
    addTearDown(session.close);
    final doc = HexDocument(session.source);
    doc.overwrite(0, [9]);
    final saved = doc.snapshot;
    await session.save(saved);
    doc.markSaved(saved);
    expect(backend.files['/a.bin'], [9, 2, 3, 4]);
    expect(doc.isDirty, isFalse);
    expect(await session.source.read(0, 4), [1, 2, 3, 4]);
    doc.overwrite(1, [8]);
    await session.save(doc.snapshot);
    expect(backend.files['/a.bin'], [9, 8, 3, 4]);
  });
  test('same-length same-timestamp external edit is detected', () async {
    final backend = MemoryBackend();
    final session = await HexFileSession.open(
      backend: backend,
      file: backend.item('/a.bin'),
    );
    addTearDown(session.close);
    final doc = HexDocument(session.source)..overwrite(0, [9]);
    backend.files['/a.bin'] = [7, 2, 3, 4];
    await expectLater(
      session.save(doc.snapshot),
      throwsA(isA<HexSaveConflict>()),
    );
    expect(backend.files['/a.bin'], [7, 2, 3, 4]);
    expect(doc.isDirty, isTrue);
    expect(backend.commits, 0);
  });
  test('changes during staged upload stop replacement', () async {
    final backend = MemoryBackend();
    final session = await HexFileSession.open(
      backend: backend,
      file: backend.item('/a.bin'),
    );
    addTearDown(session.close);
    backend.beforeVerify = () async {
      backend.files['/a.bin'] = [4, 3, 2, 1];
    };
    final doc = HexDocument(session.source)..insert(2, [5]);
    await expectLater(
      session.save(doc.snapshot),
      throwsA(isA<HexSaveConflict>()),
    );
    expect(backend.commits, 0);
    expect(backend.files['/a.bin'], [4, 3, 2, 1]);
  });
  test(
    'failed or corrupt stage leaves original and dirty state intact',
    () async {
      for (final corrupt in [false, true]) {
        final backend = MemoryBackend()
          ..fail = !corrupt
          ..corrupt = corrupt;
        final session = await HexFileSession.open(
          backend: backend,
          file: backend.item('/a.bin'),
        );
        final doc = HexDocument(session.source)..overwrite(0, [9]);
        await expectLater(session.save(doc.snapshot), throwsStateError);
        expect(backend.files['/a.bin'], [1, 2, 3, 4]);
        expect(doc.isDirty, isTrue);
        await session.close();
      }
    },
  );
  test(
    'saving a snapshot does not acknowledge concurrent newer edits',
    () async {
      final backend = MemoryBackend();
      final session = await HexFileSession.open(
        backend: backend,
        file: backend.item('/a.bin'),
      );
      addTearDown(session.close);
      final doc = HexDocument(session.source)..overwrite(0, [9]);
      final saved = doc.snapshot;
      backend.beforeVerify = () async {
        doc.overwrite(1, [8]);
      };
      await session.save(saved);
      doc.markSaved(saved);
      expect(backend.files['/a.bin'], [9, 2, 3, 4]);
      expect(doc.isDirty, isTrue);
      expect(await doc.read(0, 4), [9, 8, 3, 4]);
    },
  );
  test(
    'save-copy never replaces existing names or marks original clean',
    () async {
      final backend = MemoryBackend();
      final session = await HexFileSession.open(
        backend: backend,
        file: backend.item('/a.bin'),
      );
      addTearDown(session.close);
      final doc = HexDocument(session.source)..delete(1, 2);
      expect(await session.saveCopy(doc.snapshot, 'copy.bin'), '/copy.bin');
      expect(backend.files['/copy.bin'], [1, 4]);
      expect(doc.isDirty, isTrue);
      await expectLater(
        session.saveCopy(doc.snapshot, 'copy.bin'),
        throwsA(isA<HexSaveConflict>()),
      );
      await expectLater(
        session.saveCopy(doc.snapshot, '../escape.bin'),
        throwsArgumentError,
      );
    },
  );
  test(
    'cancellation, account changes, unsafe backend and size cap reject saves',
    () async {
      final backend = MemoryBackend();
      final session = await HexFileSession.open(
        backend: backend,
        file: backend.item('/a.bin'),
        maxBytes: 8,
      );
      addTearDown(session.close);
      final doc = HexDocument(session.source)..overwrite(0, [9]);
      await expectLater(
        session.save(doc.snapshot, cancelled: () => true),
        throwsA(isA<HexOperationCancelled>()),
      );
      backend.current = false;
      await expectLater(
        session.save(doc.snapshot),
        throwsA(isA<HexSaveConflict>()),
      );
      backend.current = true;
      backend.staged = false;
      await expectLater(session.save(doc.snapshot), throwsUnsupportedError);
      backend.staged = true;
      doc.insert(0, List.filled(5, 0));
      await expectLater(session.save(doc.snapshot), throwsStateError);
      expect(backend.commits, 0);
    },
  );
}
