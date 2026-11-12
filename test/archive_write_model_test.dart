import 'dart:typed_data';

import 'package:crisp_cloud/services/archive_types.dart';
import 'package:crisp_cloud/services/archive_write_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ArchiveWriteEntry file(
    String path, {
    int size = 3,
    Stream<List<int>> Function()? source,
  }) => ArchiveWriteEntry(
    path: path,
    isDirectory: false,
    size: size,
    readChunks: source ?? () => Stream.value([1, 2, 3]),
  );
  ArchiveWriteEntry directory(String path) =>
      ArchiveWriteEntry(path: path, isDirectory: true, size: 0);

  test('captured streams are repeatable, copied and chunk bounded', () async {
    final source = Uint8List.fromList([1, 2, 3, 4, 5]);
    final entry = file('file', size: 5, source: () => Stream.value(source));
    final chunks = await entry.openRead(chunkSize: 2).toList();
    source[0] = 9;
    expect(chunks, [
      [1, 2],
      [3, 4],
      [5],
    ]);
    expect(await entry.read(), [9, 2, 3, 4, 5]);
    await expectLater(
      entry.read(maxBytes: 4),
      throwsA(isA<ArchiveViewException>()),
    );
  });

  test('short, long and invalid captured payloads never succeed', () async {
    for (final data in [
      [1, 2],
      [1, 2, 3, 4],
      [1, 2, 256],
    ]) {
      await expectLater(
        file('file', source: () => Stream.value(data)).read(),
        throwsA(isA<ArchiveViewException>()),
      );
    }
  });

  test('names reject traversal, duplicate and file-parent ambiguity', () {
    for (final path in [
      '',
      '/abs',
      '../escape',
      'a//b',
      'a/./b',
      'C:/drive',
      'a\\b',
      'bad\u0000',
    ]) {
      expect(
        () => validateArchiveWriteEntries([file(path)]),
        throwsA(isA<ArchiveViewException>()),
      );
    }
    expect(
      () => validateArchiveWriteEntries([file('a'), file('a')]),
      throwsA(anything),
    );
    expect(
      () => validateArchiveWriteEntries([file('a'), file('a/b')]),
      throwsA(anything),
    );
    expect(
      () => validateArchiveWriteEntries([directory('a'), file('a/b')]),
      returnsNormally,
    );
    expect(
      () => validateArchiveWriteEntries([
        directory('a'),
      ], allowDirectories: false),
      throwsA(anything),
    );
    expect(
      () => validateArchiveWriteEntries([file('a/b')], allowDirectories: false),
      throwsA(anything),
    );
  });

  test(
    'names reject unpaired surrogates before UTF-8 can alias another path',
    () {
      for (final path in ['bad\ud800', 'bad\udc00', '\ud800x\udc00']) {
        expect(
          () => validateArchiveWriteEntries([file(path), file('bad�')]),
          throwsA(isA<ArchiveViewException>()),
        );
      }
      expect(
        () => validateArchiveWriteEntries([file('valid-🌍'), file('bad�')]),
        returnsNormally,
      );
    },
  );

  test('bounded output copies producer buffers and refuses overflow', () async {
    final chunk = Uint8List.fromList([1, 2, 3]);
    final output = await collectArchiveWrite((sink) async {
      await sink(chunk);
      chunk[0] = 9;
    }, maxBytes: 3);
    expect(output, [1, 2, 3]);
    await expectLater(
      collectArchiveWrite((sink) => sink(chunk), maxBytes: 2),
      throwsA(isA<ArchiveViewException>()),
    );
  });

  test(
    'viewer streams retain member identity, length, close and safety gates',
    () async {
      const member = ViewerArchiveMember(
        name: 'file',
        size: 3,
        isFile: true,
        isEncrypted: false,
        pathEscapedRoot: false,
        index: 0,
      );
      var buffered = false;
      var data = <int>[1, 2, 3];
      final archive = ViewerArchive.reader(
        formatName: 'test',
        members: [member],
        read: (_, __) async {
          buffered = true;
          return Uint8List.fromList(data);
        },
        streamReader: (_, __) => Stream.value(data),
        close: () async {},
      );
      expect(await archive.openMember(member, chunkSize: 2).toList(), [
        [1, 2],
        [3],
      ]);
      expect(buffered, isFalse);
      data = [1, 2];
      await expectLater(
        archive.openMember(member).drain<void>(),
        throwsA(anything),
      );
      data = [1, 2, 3, 4];
      await expectLater(
        archive.openMember(member).drain<void>(),
        throwsA(anything),
      );
      await expectLater(
        archive.openMember(member, maxBytes: 2).drain<void>(),
        throwsA(anything),
      );
      const forged = ViewerArchiveMember(
        name: 'other',
        size: 3,
        isFile: true,
        isEncrypted: false,
        pathEscapedRoot: false,
        index: 0,
      );
      await expectLater(
        archive.openMember(forged).drain<void>(),
        throwsA(anything),
      );
      await archive.close();
      await expectLater(
        archive.openMember(member).drain<void>(),
        throwsA(anything),
      );
    },
  );
}
