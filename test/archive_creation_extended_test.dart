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
      ..put('/input/Ünicode.txt', utf8.encode('captured source'))
      ..put('/input/empty', []);
  });

  Future<ArchiveCreationResult> create(
    ArchiveCreationFormat format,
    List<String> paths, {
    String? name,
  }) async => service.create(
    source: backend,
    destination: backend,
    files: [for (final path in paths) (await backend.stat(path))!],
    destinationDirectory: '/output',
    options: ArchiveCreationOptions(
      name: name ?? 'selection${format.extension}',
      format: format,
      compression: format.defaultCompression,
    ),
  );

  for (final format in ArchiveCreationFormat.values.where(
    (format) => format.singlePayload,
  )) {
    test(
      '${format.name} creates one payload with the output-derived name',
      () async {
        final result = await create(format, [
          '/input/Ünicode.txt',
        ], name: 'renamed.txt${format.extension}');
        final archive = await openViewerArchive(
          backend.contents[result.path]!,
          name: result.path,
        );
        addTearDown(archive.close);
        expect(archive.members.single.name, 'renamed.txt');
        expect(
          utf8.decode(await archive.readMember(archive.members.single)),
          'captured source',
        );
        expect(result.entryCount, 1);
        expect(backend.writes, [result.path]);
      },
    );

    test(
      '${format.name} accepts a file whose contents are another archive',
      () async {
        final inner = codecs.ZipEncoder().encode(
          codecs.Archive()..addFile(
            codecs.ArchiveFile.bytes(
              'inside.txt',
              utf8.encode('inner payload'),
            ),
          ),
        );
        backend.put('/input/inner.zip', inner);
        final result = await create(format, [
          '/input/inner.zip',
        ], name: 'inner.zip${format.extension}');
        expect(
          decompressSingleFile(
            backend.contents[result.path]!,
            result.path,
          ).data,
          inner,
        );
      },
    );

    test(
      '${format.name} refuses folders and multiple payloads before publication',
      () async {
        for (final paths in [
          ['/input/Ünicode.txt', '/input/empty'],
          ['/input'],
        ]) {
          await expectLater(
            create(format, paths),
            throwsA(
              isA<ArchiveCreationException>().having(
                (error) => error.code,
                'code',
                ArchiveCreationError.unsupportedEntry,
              ),
            ),
          );
        }
        expect(backend.writes, isEmpty);
      },
    );
  }

  test('AR creates flat UTF-8 members, including empty files', () async {
    final result = await create(ArchiveCreationFormat.ar, [
      '/input/Ünicode.txt',
      '/input/empty',
    ]);
    final archive = await openViewerArchive(
      backend.contents[result.path]!,
      name: result.path,
    );
    addTearDown(archive.close);
    expect(archive.members.map((member) => member.name).toSet(), {
      'Ünicode.txt',
      'empty',
    });
    expect(
      await archive.readMember(
        archive.members.firstWhere((m) => m.name == 'Ünicode.txt'),
      ),
      utf8.encode('captured source'),
    );
    await expectLater(
      create(ArchiveCreationFormat.ar, ['/input'], name: 'folders.ar'),
      throwsA(anything),
    );
    expect(backend.writes.length, 1);
  });

  for (final format in [
    ArchiveCreationFormat.tarLz4,
    ArchiveCreationFormat.tarLzma,
  ]) {
    test(
      '${format.name} creates a verified tree including empty folders',
      () async {
        await backend.createDirectory('/input/empty-folder');
        final result = await create(format, ['/input']);
        final archive = await openViewerArchive(
          backend.contents[result.path]!,
          name: result.path,
        );
        addTearDown(archive.close);
        expect(archive.formatName, 'tar');
        expect(
          archive.members.any(
            (member) =>
                !member.isFile &&
                member.name.replaceAll(RegExp(r'/+$'), '') ==
                    'input/empty-folder',
          ),
          isTrue,
        );
        final file = archive.members.singleWhere(
          (member) => member.name == 'input/Ünicode.txt',
        );
        expect(utf8.decode(await archive.readMember(file)), 'captured source');
        expect(backend.writes, [result.path]);
      },
    );
  }

  test('KMZ requires a top-level KML document', () async {
    await expectLater(
      create(ArchiveCreationFormat.kmz, ['/input/Ünicode.txt']),
      throwsA(isA<ArchiveViewException>()),
    );
    expect(backend.writes, isEmpty);
    backend.put(
      '/input/doc.kml',
      utf8.encode(
        '<kml xmlns="http://www.opengis.net/kml/2.2"><Document/></kml>',
      ),
    );
    final result = await create(ArchiveCreationFormat.kmz, [
      '/input/doc.kml',
      '/input/Ünicode.txt',
    ]);
    final archive = await openViewerArchive(
      backend.contents[result.path]!,
      name: result.path,
    );
    addTearDown(archive.close);
    expect(archive.members.map((m) => m.name).toSet(), {
      'doc.kml',
      'Ünicode.txt',
    });
  });

  for (final format in [
    ArchiveCreationFormat.jar,
    ArchiveCreationFormat.war,
    ArchiveCreationFormat.ear,
  ]) {
    test(
      '${format.name} refuses stale signature records and manifest digests',
      () async {
        backend.put('/input/META-INF/CERT.RSA', [1, 2, 3]);
        await expectLater(
          create(format, ['/input/META-INF']),
          throwsA(isA<ArchiveViewException>()),
        );
        backend.contents.remove('/input/META-INF/CERT.RSA');
        backend.put(
          '/input/META-INF/MANIFEST.MF',
          utf8.encode(
            'Manifest-Version: 1.0\r\n\r\nName: Main.class\r\nSHA-256-Digest: stale\r\n',
          ),
        );
        await expectLater(
          create(format, ['/input/META-INF']),
          throwsA(isA<ArchiveViewException>()),
        );
        expect(backend.writes, isEmpty);
      },
    );
  }

  test(
    'a changed same-length source is caught before compressed publication',
    () async {
      backend.beforeStageVerification = () =>
          backend.put('/input/Ünicode.txt', utf8.encode('modified source'));
      await expectLater(
        create(ArchiveCreationFormat.xz, ['/input/Ünicode.txt']),
        throwsA(
          isA<ArchiveCreationException>().having(
            (error) => error.code,
            'code',
            ArchiveCreationError.sourceChanged,
          ),
        ),
      );
      expect(backend.writes, isEmpty);
      expect(
        backend.contents.keys.any((path) => path.startsWith('/output/')),
        isFalse,
      );
    },
  );

  test('AR and compressed file formats expose only supported options', () {
    for (final format in [
      ArchiveCreationFormat.ar,
      ArchiveCreationFormat.gzip,
      ArchiveCreationFormat.xz,
    ]) {
      expect(
        () => ArchiveCreationOptions(
          name: 'file${format.extension}',
          format: format,
          compression: format.defaultCompression,
          password: 'secret',
        ).validate(),
        throwsA(anything),
      );
    }
    expect(
      () => const ArchiveCreationOptions(
        name: 'file.xz',
        format: ArchiveCreationFormat.xz,
        compression: ArchiveCreationCompression.none,
      ).validate(),
      throwsA(anything),
    );
  });
}
