import 'dart:convert';

import 'package:archive/archive.dart' as codecs;
import 'package:crisp_cloud/services/archive_creation_service.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/archive_creation_backend.dart';

void main() {
  const service = ArchiveCreationService();
  late ArchiveCreationBackend backend;

  setUp(() {
    backend = ArchiveCreationBackend()
      ..put('/input/folder/Ünicode.txt', utf8.encode('A complete archive.\n'))
      ..put('/input/folder/empty.txt', []);
    backend.directories.add('/input/folder/empty');
  });

  Future<ArchiveCreationResult> create(
    ArchiveCreationFormat format, {
    ArchiveCreationCompression? compression,
    String? password,
    bool hideNames = false,
    bool Function()? cancelled,
    void Function(ArchiveCreationProgress)? progress,
  }) async => service.create(
    source: backend,
    destination: backend,
    files: [(await backend.stat('/input/folder'))!],
    destinationDirectory: '/output',
    options: ArchiveCreationOptions(
      name: 'selection${format.extension}',
      format: format,
      compression: compression ?? format.defaultCompression,
      password: password,
      encryptNames: hideNames,
    ),
    isCancelled: cancelled,
    onProgress: progress,
  );

  Matcher error(ArchiveCreationError code) => throwsA(
    isA<ArchiveCreationException>().having((value) => value.code, 'code', code),
  );

  for (final format in ArchiveCreationFormat.values) {
    test(
      '${format.name} preserves recursive Unicode, empty files and directories',
      () async {
        final result = await create(format);
        expect(result.entryCount, 4);
        final archive = await openViewerArchive(
          backend.contents[result.path]!,
          name: result.path,
        );
        addTearDown(archive.close);
        expect(
          archive.members
              .map((entry) => entry.name.replaceFirst(RegExp(r'/+$'), ''))
              .toSet(),
          {'folder', 'folder/Ünicode.txt', 'folder/empty.txt', 'folder/empty'},
        );
        final text = archive.members.singleWhere(
          (entry) => entry.name.endsWith('Ünicode.txt'),
        );
        expect(
          utf8.decode(await archive.readMember(text)),
          'A complete archive.\n',
        );
        expect(backend.writes, [result.path]);
        expect(
          backend.contents.keys.where((path) => path.contains('.stage')),
          isEmpty,
        );
      },
    );
  }

  for (final format in [
    ArchiveCreationFormat.zip,
    ArchiveCreationFormat.sevenZip,
  ]) {
    test(
      '${format.name} password encrypts content and wrong passwords fail',
      () async {
        const password = 'correct horse 🔐';
        final result = await create(format, password: password);
        final bytes = backend.contents[result.path]!;
        final protected = await openViewerArchive(
          bytes,
          name: result.path,
          password: password,
        );
        addTearDown(protected.close);
        final member = protected.members.singleWhere(
          (entry) => entry.name.endsWith('Ünicode.txt'),
        );
        expect(member.isEncrypted, isTrue);
        expect(
          utf8.decode(await protected.readMember(member)),
          'A complete archive.\n',
        );
        final missing = await openViewerArchive(bytes, name: result.path);
        addTearDown(missing.close);
        await expectLater(
          missing.readMember(
            missing.members.singleWhere(
              (entry) => entry.name.endsWith('Ünicode.txt'),
            ),
          ),
          throwsA(isA<ArchivePasswordRequiredException>()),
        );
        final wrong = await openViewerArchive(
          bytes,
          name: result.path,
          password: 'incorrect',
        );
        addTearDown(wrong.close);
        await expectLater(
          wrong.readMember(
            wrong.members.singleWhere(
              (entry) => entry.name.endsWith('Ünicode.txt'),
            ),
          ),
          throwsA(isA<ArchivePasswordRequiredException>()),
        );
      },
    );
  }

  test('7z can encrypt filenames and requires the password at open', () async {
    final result = await create(
      ArchiveCreationFormat.sevenZip,
      password: 'secret',
      hideNames: true,
    );
    await expectLater(
      openViewerArchive(backend.contents[result.path]!, name: result.path),
      throwsA(isA<ArchivePasswordRequiredException>()),
    );
    final opened = await openViewerArchive(
      backend.contents[result.path]!,
      name: result.path,
      password: 'secret',
    );
    addTearDown(opened.close);
    expect(opened.members.length, 4);
  });

  test('ZIP levels are real and store writes uncompressed members', () async {
    backend.put(
      '/input/folder/large.txt',
      utf8.encode('repeated content ' * 16000),
    );
    final stored = await create(
      ArchiveCreationFormat.zip,
      compression: ArchiveCreationCompression.none,
    );
    final storeBytes = backend.contents.remove(stored.path)!;
    final maximum = await create(
      ArchiveCreationFormat.zip,
      compression: ArchiveCreationCompression.maximum,
    );
    expect(
      backend.contents[maximum.path]!.length,
      lessThan(storeBytes.length ~/ 10),
    );
    final decoded = codecs.ZipDecoder().decodeBytes(storeBytes, verify: true);
    expect(
      decoded.findFile('folder/large.txt')!.compression,
      codecs.CompressionType.none,
    );
  });

  test(
    'TGZ levels and 7z methods all roundtrip without relabelling a codec',
    () async {
      backend.put(
        '/input/folder/large.txt',
        utf8.encode('repeated content ' * 200),
      );
      for (final format in [
        ArchiveCreationFormat.tarGzip,
        ArchiveCreationFormat.sevenZip,
      ]) {
        for (final compression in format.compressions) {
          final result = await create(format, compression: compression);
          final archive = await openViewerArchive(
            backend.contents.remove(result.path)!,
            name: result.path,
          );
          expect(
            archive.members.any((entry) => entry.name == 'folder/large.txt'),
            isTrue,
          );
          await archive.close();
        }
      }
    },
  );

  test('overlapping parent and child selections are packed once', () async {
    final result = await service.create(
      source: backend,
      destination: backend,
      files: [
        (await backend.stat('/input/folder/Ünicode.txt'))!,
        (await backend.stat('/input/folder'))!,
      ],
      destinationDirectory: '/output',
      options: const ArchiveCreationOptions(name: 'overlap.zip'),
    );
    expect(result.entryCount, 4);
  });

  test(
    'existing output is retained and never renamed or overwritten',
    () async {
      backend.put('/output/selection.zip', [1, 2, 3]);
      await expectLater(
        create(ArchiveCreationFormat.zip),
        error(ArchiveCreationError.destinationExists),
      );
      expect(backend.contents['/output/selection.zip'], [1, 2, 3]);
      expect(backend.writes, isEmpty);
    },
  );

  test(
    'same-size and same-time source changes during staging block publication',
    () async {
      final original = backend.contents['/input/folder/Ünicode.txt']!;
      backend.beforeStageVerification = () => backend.put(
        '/input/folder/Ünicode.txt',
        List.filled(original.length, 7),
      );
      await expectLater(
        create(ArchiveCreationFormat.zip),
        error(ArchiveCreationError.sourceChanged),
      );
      expect(backend.writes, isEmpty);
      expect(backend.contents.containsKey('/output/selection.zip'), isFalse);
      expect(
        backend.contents.keys.where((path) => path.contains('.stage')),
        isEmpty,
      );
    },
  );

  test(
    'new children during packing prevent a silently incomplete archive',
    () async {
      var changed = false;
      await expectLater(
        create(
          ArchiveCreationFormat.zip,
          progress: (progress) {
            if (!changed && progress.phase == ArchiveCreationPhase.verifying) {
              changed = true;
              backend.put('/input/folder/late.txt', [8]);
            }
          },
        ),
        error(ArchiveCreationError.sourceChanged),
      );
      expect(backend.writes, isEmpty);
    },
  );

  test(
    'cancellation before and during verification publishes nothing',
    () async {
      await expectLater(
        create(ArchiveCreationFormat.zip, cancelled: () => true),
        error(ArchiveCreationError.cancelled),
      );
      var cancel = false;
      await expectLater(
        create(
          ArchiveCreationFormat.zip,
          cancelled: () => cancel,
          progress: (progress) {
            if (progress.phase == ArchiveCreationPhase.verifying) cancel = true;
          },
        ),
        error(ArchiveCreationError.cancelled),
      );
      expect(backend.writes, isEmpty);
    },
  );

  test(
    'storage loss and cancellation while staged keep the output absent',
    () async {
      backend.beforeStageVerification = () => backend.current = false;
      await expectLater(
        create(ArchiveCreationFormat.zip),
        error(ArchiveCreationError.sourceUnavailable),
      );
      expect(backend.writes, isEmpty);
      backend.current = true;
      var cancel = false;
      backend.beforeStageVerification = () => cancel = true;
      await expectLater(
        create(ArchiveCreationFormat.zip, cancelled: () => cancel),
        error(ArchiveCreationError.cancelled),
      );
      expect(backend.writes, isEmpty);
    },
  );

  test(
    'symbolic links and per-file limits fail before an output write',
    () async {
      backend.links.add('/input/folder/link');
      await expectLater(
        create(ArchiveCreationFormat.zip),
        error(ArchiveCreationError.unsupportedEntry),
      );
      backend.links.clear();
      backend.advertisedSizes['/input/folder/Ünicode.txt'] =
          kArchiveReadLimit + 1;
      await expectLater(
        create(ArchiveCreationFormat.zip),
        error(ArchiveCreationError.tooLarge),
      );
      expect(backend.writes, isEmpty);
    },
  );

  test(
    'output inside a selected folder is rejected before reading contents',
    () async {
      await expectLater(
        service.create(
          source: backend,
          destination: backend,
          files: [(await backend.stat('/input/folder'))!],
          destinationDirectory: '/input/folder',
          options: const ArchiveCreationOptions(name: 'inside.zip'),
        ),
        error(ArchiveCreationError.invalidDestination),
      );
      expect(backend.writes, isEmpty);
    },
  );

  test(
    'TGZ rejects decoded contents beyond the viewer container limit',
    () async {
      backend.advertisedSizes['/input/folder/Ünicode.txt'] =
          kArchiveReadLimit ~/ 2;
      backend.advertisedSizes['/input/folder/empty.txt'] =
          kArchiveReadLimit ~/ 2 + 1;
      await expectLater(
        create(ArchiveCreationFormat.tarGzip),
        error(ArchiveCreationError.tooLarge),
      );
      expect(backend.writes, isEmpty);
    },
  );

  test(
    'duplicate member names from separate folders fail without overwriting',
    () async {
      backend.put('/other/Ünicode.txt', [4, 5]);
      await expectLater(
        service.create(
          source: backend,
          destination: backend,
          files: [
            (await backend.stat('/input/folder/Ünicode.txt'))!,
            (await backend.stat('/other/Ünicode.txt'))!,
          ],
          destinationDirectory: '/output',
          options: const ArchiveCreationOptions(name: 'duplicates.zip'),
        ),
        error(ArchiveCreationError.duplicateName),
      );
      expect(backend.writes, isEmpty);
    },
  );

  test(
    'corrupt staged bytes are rejected before the final name is published',
    () async {
      backend.beforeStageVerification = () {
        final staged = backend.contents['/output/.stage']!;
        backend.put('/output/.stage', [staged.first ^ 1, ...staged.skip(1)]);
      };
      await expectLater(
        create(ArchiveCreationFormat.zip),
        error(ArchiveCreationError.verificationFailed),
      );
      expect(backend.writes, isEmpty);
      expect(backend.contents.containsKey('/output/selection.zip'), isFalse);
    },
  );

  test('path traversal, mismatched extensions and unsupported security options fail closed', () {
    for (final name in [
      '../out.zip',
      '/out.zip',
      'bad\\out.zip',
      'NUL.zip',
      'out.tar',
      ' out.zip',
    ]) {
      expect(
        () => ArchiveCreationOptions(name: name).validate(),
        error(ArchiveCreationError.invalidName),
      );
    }
    for (final options in [
      const ArchiveCreationOptions(
        name: 'file.tar',
        format: ArchiveCreationFormat.tar,
        compression: ArchiveCreationCompression.none,
        password: 'no',
      ),
      const ArchiveCreationOptions(name: 'file.zip', password: ''),
      const ArchiveCreationOptions(
        name: 'file.zip',
        password: 'no',
        encryptNames: true,
      ),
      const ArchiveCreationOptions(
        name: 'file.7z',
        format: ArchiveCreationFormat.sevenZip,
        compression: ArchiveCreationCompression.maximum,
      ),
    ]) {
      expect(options.validate, error(ArchiveCreationError.unsupportedOptions));
    }
  });
}
