import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/editor_document.dart';
import 'package:crisp_cloud/services/file_comparison_service.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/local_file_service.dart';

import 'support/workflow_fake_client.dart';

class _RacingMergeClient extends WorkflowFakeClient {
  bool race = false;
  @override
  Future<void> uploadFile(
    List<int> bytes,
    String name,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    if (race && name.startsWith('.crisp-transfer-')) {
      put('/file.txt', 'external'.codeUnits);
    }
    await super.uploadFile(bytes, name, targetPath, onProgress: onProgress);
  }
}

void main() {
  test('an external edit during merge staging cannot be overwritten', () async {
    final client = _RacingMergeClient()..put('/file.txt', 'original'.codeUnits);
    final source = CloudOperationBackend(client, isCurrent: () => true);
    final session = await MergeDocumentSession.open(
      source,
      (await source.stat('/file.txt'))!,
    );
    client.race = true;
    await expectLater(session.save('merged'), throwsStateError);
    expect(client.files['/file.txt'], 'external'.codeUnits);
  });

  test('binary file comparison rejects files changed while reading', () async {
    final a = WorkflowFakeClient()..put('/a', [1, 2]);
    final b = WorkflowFakeClient()..put('/b', [1, 2]);
    final left = CloudOperationBackend(a, isCurrent: () => true);
    final right = CloudOperationBackend(b, isCurrent: () => true);
    await expectLater(
      compareBinaryFiles(
        left,
        (await left.stat('/a'))!,
        right,
        (await right.stat('/b'))!,
        onProgress: (_) => b.put('/b', [1, 2, 3]),
      ),
      throwsStateError,
    );
  });

  test('diff output reconstructs both input sequences for varied edits', () {
    final random = Random(1234);
    for (var trial = 0; trial < 100; trial++) {
      final left = List.generate(
        random.nextInt(50),
        (_) => 'line ${random.nextInt(12)}',
      );
      final right = List.generate(
        random.nextInt(50),
        (_) => 'line ${random.nextInt(12)}',
      );
      final rows = compareTextLines(left, right);
      expect(
        rows.where((row) => row.type != DiffType.added).map((row) => row.text),
        left,
      );
      expect(
        rows
            .where((row) => row.type != DiffType.removed)
            .map((row) => row.rightText ?? row.text),
        right,
      );
    }
  });

  test(
    'large unique and repeated inputs avoid a whole-document quadratic matrix',
    () {
      final left = List.generate(100000, (i) => 'line $i');
      final right = List.of(left)..[50000] = 'changed';
      final rows = compareTextLines(left, right);
      expect(differenceHunks(rows), hasLength(1));
      final repeated = compareTextLines(
        List.filled(20000, 'old'),
        List.filled(20000, 'new'),
      );
      expect(repeated.length, 40000);
      expect(differenceHunks(repeated), hasLength(1));
    },
  );

  test('ignore options retain the actual right text', () {
    final rows = compareTextLines(
      ['Hello  world'],
      ['hello world'],
      ignoreCase: true,
      ignoreWhitespace: true,
    );
    expect(rows.single.type, DiffType.equal);
    expect(rows.single.rightText, 'hello world');
  });

  test(
    'accepting a hunk merges only that region and preserves trailing newline',
    () {
      const left = 'start\nleft\nend\n';
      const right = 'start\nright\nend\n';
      final hunk = differenceHunks(
        compareTextLines(left.split('\n'), right.split('\n')),
      ).single;
      expect(mergeHunk(left, right, hunk), left);
    },
  );

  test('binary comparison handles unequal chunk boundaries, empty chunks and length differences', () async {
    final result = await compareBinaryStreams(
      Stream.fromIterable([
        [1],
        [],
        [2, 3, 4],
      ]),
      Stream.fromIterable([
        [1, 2],
        [9, 4, 5],
      ]),
    );
    expect(result.leftBytes, 4);
    expect(result.rightBytes, 5);
    expect(result.firstDifference, 2);
    expect(result.differingBytes, 2);
    final same = await compareBinaryStreams(
      Stream.fromIterable([
        [1, 2],
        [3],
      ]),
      Stream.fromIterable([
        [1],
        [2, 3],
      ]),
    );
    expect(same.equal, isTrue);
  });

  test('binary cancellation closes both streams', () async {
    var leftClosed = false, rightClosed = false, cancel = false;
    Stream<List<int>> left() async* {
      try {
        for (var i = 0; i < 10; i++) {
          yield [i];
        }
      } finally {
        leftClosed = true;
      }
    }

    Stream<List<int>> right() async* {
      try {
        for (var i = 0; i < 10; i++) {
          yield [i];
        }
      } finally {
        rightClosed = true;
      }
    }

    await expectLater(
      compareBinaryStreams(
        left(),
        right(),
        isCancelled: () => cancel,
        onProgress: (_) {
          cancel = true;
        },
      ),
      throwsStateError,
    );
    expect(leftClosed, isTrue);
    expect(rightClosed, isTrue);
  });

  test(
    'merge saves preserve UTF-16 and CRLF, and reject later external edits',
    () async {
      final temp = await Directory.systemTemp.createTemp('merge-document-');
      addTearDown(() => temp.delete(recursive: true));
      final file = File('${temp.path}/text.txt');
      const document = EditorDocument(
        text: 'before\n',
        encoding: EditorEncoding.utf16le,
        lineEnding: EditorLineEnding.crlf,
      );
      await file.writeAsBytes(document.encode());
      final source = LocalOperationBackend(
        LocalFileService(),
        isCurrent: () => true,
      );
      final item = (await source.stat(file.path))!;
      final session = await MergeDocumentSession.open(source, item);
      await session.save('merged\n');
      expect(await file.readAsBytes(), document.encode('merged\n'));
      await file.writeAsBytes(document.encode('external\n'));
      await expectLater(session.save('overwrite\n'), throwsStateError);
      expect(await file.readAsBytes(), document.encode('external\n'));
    },
  );

  test('merge rejects changed account without saving', () async {
    final temp = await Directory.systemTemp.createTemp('merge-account-');
    addTearDown(() => temp.delete(recursive: true));
    final file = File('${temp.path}/a.txt');
    await file.writeAsString('before');
    var current = true;
    final source = LocalOperationBackend(
      LocalFileService(),
      isCurrent: () => current,
    );
    final session = await MergeDocumentSession.open(
      source,
      FileItem(name: 'a.txt', path: file.path, isFolder: false, size: 6),
    );
    current = false;
    await expectLater(session.save('after'), throwsStateError);
    expect(await file.readAsString(), 'before');
  });
}
