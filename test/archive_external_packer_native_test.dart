import 'dart:convert';
import 'dart:io';

import 'package:crisp_cloud/services/archive_external_packer.dart';
import 'package:crisp_cloud/services/archive_external_packer_io.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/archive_write_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/archive_creation_backend.dart';

/// Opt in with an explicitly installed, separately obtained vendor binary.
/// Neither the application nor its tests download or bundle an executable.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final kind in ArchiveExternalPackerKind.values) {
    final executable =
        Platform.environment[kind == ArchiveExternalPackerKind.sevenZip
            ? 'CRISPCLOUD_TEST_7ZZ'
            : 'CRISPCLOUD_TEST_RAR'];
    group(
      'installed ${kind.name} native adapter',
      () {
        late Directory root;
        late NativeArchiveExternalPackerEngine engine;
        late ArchiveExternalPackerInstallation installation;
        setUpAll(() async {
          final temporary = await Directory.systemTemp.createTemp(
            'packer-native-',
          );
          root = Directory(await temporary.resolveSymbolicLinks());
          engine = NativeArchiveExternalPackerEngine(
            hasAccess: (_) async => true,
            stagingRoot: () async => p.join(root.path, 'stages'),
          );
          installation = await engine.probe(
            ArchiveExternalPackerConfiguration(
              platform: Platform.operatingSystem,
              kind: kind,
              executable: executable!,
            ),
          );
        });
        tearDownAll(() async => root.delete(recursive: true));

        test(
          'actual owned process probes every compression and metadata profile',
          () async {
            expect(
              installation.formats,
              kind == ArchiveExternalPackerKind.sevenZip
                  ? {
                      ArchiveExternalPackerFormat.zip,
                      ArchiveExternalPackerFormat.sevenZip,
                    }
                  : {ArchiveExternalPackerFormat.rar},
            );
            expect(
              await Directory(p.join(root.path, 'stages')).list().toList(),
              isEmpty,
            );
          },
        );

        test(
          'exact selected files pass the normal staged publication pipeline',
          () async {
            final backend = ArchiveCreationBackend()
              ..put(
                '/input/folder/日本語.txt',
                utf8.encode('compressed text ' * 2048),
              )
              ..put('/input/folder/@literal.txt', [1, 2, 3])
              ..put('/input/-switch-like.txt', [4, 5, 6]);
            backend.directories.add('/input/folder/empty');
            final service = ArchiveExternalPackerService(engine: engine);
            for (final format in installation.formats) {
              for (final compression
                  in ArchiveExternalPackerCompression.values) {
                final result = await service.create(
                  source: backend,
                  destination: backend,
                  files: [
                    (await backend.stat('/input/folder'))!,
                    (await backend.stat('/input/-switch-like.txt'))!,
                  ],
                  destinationDirectory: '/output',
                  installation: installation,
                  options: ArchiveExternalPackerOptions(
                    name:
                        '${format.name}-${compression.name}${format.extension}',
                    format: format,
                    compression: compression,
                  ),
                );
                final archive = await openViewerArchive(
                  backend.contents[result.path]!,
                  name: result.path,
                );
                try {
                  expect(
                    archive.members
                        .map((m) => m.name.replaceFirst(RegExp(r'/+$'), ''))
                        .toSet(),
                    {
                      'folder',
                      'folder/日本語.txt',
                      'folder/@literal.txt',
                      'folder/empty',
                      '-switch-like.txt',
                    },
                  );
                  final payload = archive.members.singleWhere(
                    (m) => m.name.endsWith('日本語.txt'),
                  );
                  expect(
                    await archive.readMember(payload),
                    backend.contents['/input/folder/日本語.txt'],
                  );
                  if (compression != ArchiveExternalPackerCompression.store) {
                    expect(result.bytes, lessThan(4096));
                  }
                } finally {
                  await archive.close();
                }
              }
            }
            expect(backend.contents['/input/-switch-like.txt'], [4, 5, 6]);
            expect(
              await Directory(p.join(root.path, 'stages')).list().toList(),
              isEmpty,
            );
          },
        );

        test(
          'literal wildcard and shell characters are data in 7-Zip list files',
          () async {
            if (kind != ArchiveExternalPackerKind.sevenZip ||
                Platform.isWindows) {
              return;
            }
            final names = [
              '-switch',
              '@list',
              'dollar\$(value)',
              'semi;colon',
              'quote"inside',
              'literal?star*',
              'snow-雪',
            ];
            final entries = [
              for (final name in names)
                ArchiveWriteEntry(
                  path: name,
                  isDirectory: false,
                  size: 3,
                  modified: DateTime.utc(2024, 1, 2, 3, 4, 5),
                  mode: 0x180,
                  readChunks: () => Stream.value([1, 2, 3]),
                ),
            ];
            for (final format in installation.formats) {
              final bytes = await collectArchiveWrite(
                (sink) => engine.write(
                  installation: installation,
                  options: ArchiveExternalPackerOptions(
                    name: 'test${format.extension}',
                    format: format,
                  ),
                  entries: entries,
                  sink: sink,
                  maxOutputBytes: 1024 * 1024,
                ),
              );
              final archive = await openViewerArchive(
                bytes,
                name: 'test${format.extension}',
              );
              try {
                expect(
                  archive.members.map((m) => m.name).toSet(),
                  names.toSet(),
                );
              } finally {
                await archive.close();
              }
            }
          },
        );
      },
      skip: executable == null
          ? 'Set the explicit installed engine path to run native CLI tests.'
          : false,
    );
  }
}
