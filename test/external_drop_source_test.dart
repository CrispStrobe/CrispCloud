import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/services/external_drop_source.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/archive_creation_backend.dart';
import 'support/external_drop_fixture.dart';

Matcher failure(ExternalDropFailure value) => isA<ExternalDropException>()
    .having((error) => error.failure, 'failure', value);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('browser folders retain structure and stream bounded chunks through the copy engine', () async {
    final file = DropTestFile(
      'photo.bin',
      List.generate(160000, (i) => i % 256),
    );
    final source = await ExternalDropSource.prepare([
      DropTestDirectory('photos', [file]),
    ], browser: true);
    addTearDown(source.close);
    expect(source.backend.canRecover, isFalse);
    expect(source.backend.storageReference, isNull);
    expect(source.files.single.path, '/photos');
    final nested = (await source.backend.list('/photos')).single;
    final chunks = await source.backend.readFile(nested).toList();
    expect(chunks.every((chunk) => chunk.length <= 65536), isTrue);
    expect(chunks.expand((chunk) => chunk).toList(), file.data);
    final destination = ArchiveCreationBackend();
    final plan = await const FileOperationService().prepare(
      files: source.files,
      source: source.backend,
      destination: destination,
      targetDirectory: '/output',
      options: const FileOperationOptions(),
    );
    expect(plan.errors, isEmpty);
    await const FileOperationService().execute(
      plan,
      control: FileOperationControl(),
    );
    expect(destination.contents['/output/photos/photo.bin'], file.data);
    expect(file.byteReads, 0);
    expect(file.streamReads, greaterThan(0));
    await expectLater(
      source.backend.deleteFile(nested),
      throwsUnsupportedError,
    );
  });

  for (final name in ['../escape', '..', '.', 'a/b', r'a\b', 'bad\u0000name']) {
    test(
      'browser names cannot escape their captured tree: ${name.replaceAll('\u0000', 'NUL')}',
      () async {
        await expectLater(
          ExternalDropSource.prepare([
            DropTestFile(name, [1]),
          ], browser: true),
          throwsA(failure(ExternalDropFailure.invalidItems)),
        );
      },
    );
  }

  test(
    'duplicate browser root names fail before a writable operation exists',
    () async {
      await expectLater(
        ExternalDropSource.prepare([
          DropTestFile('same.txt', [1]),
          DropTestFile('same.txt', [2]),
        ], browser: true),
        throwsA(failure(ExternalDropFailure.duplicateNames)),
      );
    },
  );

  test(
    'a browser folder without a child manifest is rejected explicitly',
    () async {
      await expectLater(
        ExternalDropSource.prepare([
          DropItemFile(
            'missing-manifest',
            name: 'folder',
            mimeType: 'directory',
          ),
        ], browser: true),
        throwsA(failure(ExternalDropFailure.invalidItems)),
      );
    },
  );

  for (final declared in [1, 3]) {
    test(
      'browser stream length $declared cannot hide truncation or growth',
      () async {
        final source = await ExternalDropSource.prepare([
          DropTestFile('changed.bin', [1, 2], declaredLength: declared),
        ], browser: true);
        addTearDown(source.close);
        await expectLater(
          source.backend.readFile(source.files.single).drain<void>(),
          throwsA(failure(ExternalDropFailure.changed)),
        );
      },
    );
  }

  test('a closed source cannot be read or recovered later', () async {
    final source = await ExternalDropSource.prepare([
      DropTestFile('temporary.txt', [1]),
    ], browser: true);
    await source.close();
    expect(source.isCurrent, isFalse);
    await expectLater(
      source.backend.stat('/temporary.txt'),
      throwsA(failure(ExternalDropFailure.unavailable)),
    );
    await expectLater(
      source.backend.readFile(source.files.single).drain<void>(),
      throwsA(failure(ExternalDropFailure.unavailable)),
    );
    await source.close();
  });

  test('cancellation during browser metadata preparation rejects the captured source', () async {
    final delayed = DropTestFile('late.txt', [1])
      ..pendingLength = Completer<int>();
    var current = true;
    final pending = ExternalDropSource.prepare(
      [delayed],
      browser: true,
      canContinue: () => current,
    );
    current = false;
    delayed.pendingLength!.complete(1);
    await expectLater(
      pending,
      throwsA(failure(ExternalDropFailure.unavailable)),
    );
  });

  group('native inputs', () {
    late Directory directory;
    late File input;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('native-drop-');
      input = await File(p.join(directory.path, 'input.txt'))
          .writeAsString('content');
    });
    tearDown(() => directory.delete(recursive: true));

    test('native directories are discovered from actual file types', () async {
      final source = await ExternalDropSource.prepare([
        DropItemFile(directory.path),
      ]);
      addTearDown(source.close);
      expect(source.files.single.isFolder, isTrue);
      expect(
        (await source.backend.list(directory.path)).single.path,
        input.path,
      );
      final destination = ArchiveCreationBackend();
      final plan = await const FileOperationService().prepare(
        files: source.files,
        source: source.backend,
        destination: destination,
        targetDirectory: '/output',
        options: const FileOperationOptions(),
      );
      await const FileOperationService().execute(
        plan,
        control: FileOperationControl(),
      );
      expect(
        destination.contents['/output/${p.basename(directory.path)}/input.txt'],
        'content'.codeUnits,
      );
    });

    test(
      'native self-copy is rejected by the normal plan relationship checks',
      () async {
        final source = await ExternalDropSource.prepare([
          DropItemFile(input.path),
        ]);
        addTearDown(source.close);
        final destination = LocalOperationBackend(
          DropTestLocal(directory.path),
          isCurrent: () => true,
        );
        final plan = await const FileOperationService().prepare(
          files: source.files,
          source: source.backend,
          destination: destination,
          targetDirectory: directory.path,
          options: const FileOperationOptions(),
        );
        expect(plan.canExecute, isFalse);
        expect(
          plan.errors.any((error) => error.contains('into itself')),
          isTrue,
        );
        expect(await input.readAsString(), 'content');
      },
    );

    test(
      'distinct case-sensitive source names survive selection capture',
      () async {
        final upper = File(p.join(directory.path, 'Report.txt'));
        final lower = File(p.join(directory.path, 'report.txt'));
        await upper.writeAsString('upper');
        await lower.writeAsString('lower');
        if (await FileSystemEntity.identical(upper.path, lower.path)) {
          markTestSkipped('This temporary volume is not case-sensitive.');
          return;
        }
        final source = await ExternalDropSource.prepare([
          DropItemFile(upper.path),
          DropItemFile(lower.path),
          DropItemFile(upper.path),
        ]);
        addTearDown(source.close);
        expect(source.files.map((file) => file.path), [upper.path, lower.path]);
        expect(
          await source.backend
              .readFile(source.files.first)
              .expand((chunk) => chunk)
              .toList(),
          'upper'.codeUnits,
        );
        expect(
          await source.backend
              .readFile(source.files.last)
              .expand((chunk) => chunk)
              .toList(),
          'lower'.codeUnits,
        );
      },
    );

    test(
      'native file changes and paths outside the dropped roots are rejected',
      () async {
        final source = await ExternalDropSource.prepare([
          DropItemFile(input.path),
        ]);
        addTearDown(source.close);
        await expectLater(
          source.backend.stat(p.dirname(directory.path)),
          throwsA(failure(ExternalDropFailure.invalidItems)),
        );
        await input.writeAsString('changed content');
        await expectLater(
          source.backend.readFile(source.files.single).drain<void>(),
          throwsA(failure(ExternalDropFailure.changed)),
        );
      },
    );

    test(
      'drop bookmarks remain active until close and release exactly once',
      () async {
        final access = RecordingDropAccess();
        final source = await ExternalDropSource.prepare([
          DropItemFile(
            input.path,
            extraAppleBookmark: Uint8List.fromList([1, 2]),
          ),
        ], access: access);
        expect(access.started, [
          [1, 2],
        ]);
        expect(access.stopped, isEmpty);
        expect(
          await source.backend
              .readFile(source.files.single)
              .expand((chunk) => chunk)
              .toList(),
          'content'.codeUnits,
        );
        await source.close();
        await source.close();
        expect(access.stopped, [
          [1, 2],
        ]);
      },
    );

    test(
      'partial bookmark acquisition failure releases earlier access',
      () async {
        final access = RecordingDropAccess()..denyStart = 2;
        await expectLater(
          ExternalDropSource.prepare([
            DropItemFile(
              input.path,
              extraAppleBookmark: Uint8List.fromList([1]),
            ),
            DropItemFile(
              input.path,
              extraAppleBookmark: Uint8List.fromList([2]),
            ),
          ], access: access),
          throwsA(failure(ExternalDropFailure.unavailable)),
        );
        expect(access.stopped, [
          [1],
        ]);
      },
    );

    if (!Platform.isWindows) {
      test(
        'native links are rejected without following their targets',
        () async {
          final link = Link(p.join(directory.path, 'link'));
          await link.create(input.path);
          await expectLater(
            ExternalDropSource.prepare([DropItemFile(link.path)]),
            throwsA(failure(ExternalDropFailure.invalidItems)),
          );
        },
      );
    }
  });
}
