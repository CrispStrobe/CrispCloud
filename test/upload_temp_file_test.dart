import 'dart:async';
import 'dart:io';

import 'package:crisp_cloud/services/upload_temp_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporary;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('upload-lifecycle-test-');
  });
  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  test('concurrent uploads of the same filename retain their own bytes until completion', () async {
    final bothReady = Completer<void>();
    final release = Completer<void>();
    final paths = <String>[];
    Future<List<int>> upload(int value) => withTemporaryUploadFile(
      'copy.wav',
      [value, value, value],
      (file) async {
        paths.add(file.path);
        if (paths.length == 2) bothReady.complete();
        await release.future;
        return file.readAsBytes();
      },
      temporaryDirectory: temporary.path,
    );
    final first = upload(1);
    final second = upload(2);
    await bothReady.future;
    expect(paths[0], isNot(paths[1]));
    expect(await Directory(temporary.path).list().length, 2);
    release.complete();
    expect(await first, [1, 1, 1]);
    expect(await second, [2, 2, 2]);
    expect(await temporary.list().toList(), isEmpty);
  });

  test(
    'an upload failure removes its temporary bytes without changing the error',
    () async {
      final failure = StateError('Network interrupted');
      await expectLater(
        withTemporaryUploadFile<void>('copy.wav', [1, 2, 3], (file) async {
          expect(await file.readAsBytes(), [1, 2, 3]);
          throw failure;
        }, temporaryDirectory: temporary.path),
        throwsA(same(failure)),
      );
      expect(await temporary.list().toList(), isEmpty);
    },
  );

  test(
    'a failed temporary write is cleaned before any upload starts',
    () async {
      var uploads = 0;
      await expectLater(
        withTemporaryUploadFile<void>(
          '${List.filled(512, 'x').join()}.wav',
          [1, 2, 3],
          (_) async {
            uploads++;
          },
          temporaryDirectory: temporary.path,
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(uploads, 0);
      expect(await temporary.list().toList(), isEmpty);
    },
  );

  test('a filename cannot escape its private upload directory', () async {
    await expectLater(
      withTemporaryUploadFile<void>(
        '../escape.wav',
        [1],
        (_) async {},
        temporaryDirectory: temporary.path,
      ),
      throwsArgumentError,
    );
    expect(await temporary.list().toList(), isEmpty);
  });
}
