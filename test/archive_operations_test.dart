import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:crisp_cloud/services/archive_service.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';

void main() {
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('archive-ops-');
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });
  Uint8List zip(String path, String text) => Uint8List.fromList(
    ZipEncoder().encode(
      Archive()..addFile(ArchiveFile(path, text.length, text.codeUnits)),
    ),
  );

  test('traversal is rejected before any files are extracted', () async {
    final archive = Archive()
      ..addFile(ArchiveFile('safe.txt', 1, [1]))
      ..addFile(ArchiveFile('../escape.txt', 1, [2]));
    await expectLater(
      ArchiveService.extractArchiveBytes(
        'a.zip',
        Uint8List.fromList(ZipEncoder().encode(archive)),
        temp.path,
      ),
      throwsA(isA<ArchiveViewException>()),
    );
    expect(await temp.list().toList(), isEmpty);
  });

  test('existing destination files require explicit overwrite', () async {
    final file = File(p.join(temp.path, 'a.txt'));
    await file.writeAsString('original');
    await expectLater(
      ArchiveService.extractZipBytes(zip('a.txt', 'replacement'), temp.path),
      throwsA(isA<ArchiveViewException>()),
    );
    expect(await file.readAsString(), 'original');
    await ArchiveService.extractArchiveBytes(
      'a.zip',
      zip('a.txt', 'replacement'),
      temp.path,
      overwrite: true,
    );
    expect(await file.readAsString(), 'replacement');
  });

  test(
    'pre-existing symbolic link parents cannot escape extraction root',
    () async {
      final outside = await Directory.systemTemp.createTemp('archive-outside-');
      addTearDown(() => outside.delete(recursive: true));
      await Link(p.join(temp.path, 'linked')).create(outside.path);
      await expectLater(
        ArchiveService.extractZipBytes(
          zip('linked/escape.txt', 'no'),
          temp.path,
        ),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(await outside.list().toList(), isEmpty);
    },
    skip: Platform.isWindows
        ? 'Creating symlinks requires Windows privileges'
        : false,
  );

  test('TAR and compressed TAR dispatch to their actual decoders', () async {
    final archive = Archive()
      ..addFile(ArchiveFile('nested/a.txt', 5, 'hello'.codeUnits));
    final tar = Uint8List.fromList(TarEncoder().encode(archive));
    for (final variant in <String, Uint8List>{
      'a.tar': tar,
      'b.tar.gz': Uint8List.fromList(GZipEncoder().encode(tar)),
    }.entries) {
      final target = p.join(temp.path, variant.key);
      final paths = await ArchiveService.extractArchiveBytes(
        variant.key,
        variant.value,
        target,
      );
      expect(paths, hasLength(1));
      expect(await File(paths.single).readAsString(), 'hello');
    }
  });

  test('selected folders pack nested and empty directories once', () async {
    final folder = Directory(p.join(temp.path, 'folder'));
    await Directory(p.join(folder.path, 'empty')).create(recursive: true);
    final file = File(p.join(folder.path, 'a.txt'));
    await file.writeAsString('packed');
    final bytes = await ArchiveService.createZip([
      folder.path,
      file.path,
    ], basePath: temp.path);
    final archive = ZipDecoder().decodeBytes(bytes);
    expect(
      archive.map((entry) => entry.name),
      unorderedEquals(['folder/', 'folder/empty/', 'folder/a.txt']),
    );
    final destination = p.join(temp.path, 'out');
    await ArchiveService.extractZipBytes(bytes, destination);
    expect(
      await File(p.join(destination, 'folder/a.txt')).readAsString(),
      'packed',
    );
    expect(
      await Directory(p.join(destination, 'folder/empty')).exists(),
      isTrue,
    );
  });

  test('selected member extraction excludes unrelated entries', () async {
    final archive = Archive()
      ..addFile(ArchiveFile('docs/a.txt', 1, [1]))
      ..addFile(ArchiveFile('private.txt', 1, [2]));
    final paths = await ArchiveService.extractArchiveBytes(
      'a.zip',
      Uint8List.fromList(ZipEncoder().encode(archive)),
      temp.path,
      selectedPaths: {'docs'},
    );
    expect(paths, [p.join(temp.path, 'docs/a.txt')]);
    expect(await File(p.join(temp.path, 'private.txt')).exists(), isFalse);
  });

  test(
    '7z fixture can be extracted through the shared bounded reader',
    () async {
      final paths = await ArchiveService.extractArchive(
        'test/fixtures/archives/sample.7z',
        temp.path,
      );
      expect(paths, isNotEmpty);
      expect(await File(paths.first).length(), greaterThan(0));
    },
  );
}
