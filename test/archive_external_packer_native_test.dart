import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

        if (kind == ArchiveExternalPackerKind.sevenZip) {
          test('all 27 bounded profiles pass real Store, Normal and Maximum probes', () async {
            for (final dictionary
                in ArchiveExternalSevenZipProfile.dictionarySizesMiB) {
              for (final threads
                  in ArchiveExternalSevenZipProfile.threadCounts) {
                for (final solid
                    in ArchiveExternalSevenZipProfile.solidBlockSizesMiB) {
                  final profile = ArchiveExternalSevenZipProfile(
                    dictionaryMiB: dictionary,
                    threads: threads,
                    solidBlockMiB: solid,
                  );
                  final checked = await engine.probe(
                    installation.configuration,
                    sevenZipProfile: profile,
                  );
                  expect(checked.sevenZipProfile, profile);
                  expect(
                    checked.formats,
                    contains(ArchiveExternalPackerFormat.sevenZip),
                    reason:
                        'dictionary=$dictionary threads=$threads solid=$solid',
                  );
                }
              }
            }
            expect(
              await Directory(p.join(root.path, 'stages')).list().toList(),
              isEmpty,
            );
          }, timeout: const Timeout(Duration(minutes: 4)));

          test(
            'advanced options use the same verified publication boundary',
            () async {
              const profile = ArchiveExternalSevenZipProfile(
                dictionaryMiB: 4,
                threads: 4,
                solidBlockMiB: 16,
              );
              final checked = await engine.probe(
                installation.configuration,
                sevenZipProfile: profile,
              );
              final backend = ArchiveCreationBackend()
                ..put(
                  '/input/first.txt',
                  utf8.encode('same repeated text ' * 1024),
                )
                ..put(
                  '/input/second.txt',
                  utf8.encode('same repeated text ' * 2048),
                );
              final result = await ArchiveExternalPackerService(engine: engine)
                  .create(
                    source: backend,
                    destination: backend,
                    files: [
                      (await backend.stat('/input/first.txt'))!,
                      (await backend.stat('/input/second.txt'))!,
                    ],
                    destinationDirectory: '/output',
                    installation: checked,
                    options: const ArchiveExternalPackerOptions(
                      name: 'bounded.7z',
                      format: ArchiveExternalPackerFormat.sevenZip,
                      compression: ArchiveExternalPackerCompression.maximum,
                      sevenZipProfile: profile,
                    ),
                  );
              expect(result.path, '/output/bounded.7z');
              expect(result.entryCount, 2);
              expect(result.bytes, lessThan(4096));
            },
          );

          test(
            'solid blocks preserve the 64 MiB decoded-folder boundary',
            () async {
              const mib = 1024 * 1024;
              final sizes = {
                'a-small': 4 * mib,
                'b-middle': 24 * mib,
                'c-large': 64 * mib,
              };
              final chunk = Uint8List(64 * 1024);
              final entries = [
                for (final entry in sizes.entries)
                  ArchiveWriteEntry(
                    path: entry.key,
                    isDirectory: false,
                    size: entry.value,
                    modified: DateTime.utc(2024, 1, 2, 3, 4, 5),
                    mode: Platform.isWindows ? null : 0x180,
                    readChunks: () async* {
                      for (
                        var count = 0;
                        count < entry.value;
                        count += chunk.length
                      ) {
                        yield chunk;
                      }
                    },
                  ),
              ];
              for (final solid in [16, 32]) {
                final profile = ArchiveExternalSevenZipProfile(
                  dictionaryMiB: 1,
                  solidBlockMiB: solid,
                );
                final checked = await engine.probe(
                  installation.configuration,
                  sevenZipProfile: profile,
                );
                final bytes = await collectArchiveWrite(
                  (sink) => engine.write(
                    installation: checked,
                    options: ArchiveExternalPackerOptions(
                      name: 'bounded.7z',
                      format: ArchiveExternalPackerFormat.sevenZip,
                      sevenZipProfile: profile,
                    ),
                    entries: entries,
                    sink: sink,
                    maxOutputBytes: mib,
                  ),
                );
                final archive = await openViewerArchive(
                  bytes,
                  name: 'bounded.7z',
                );
                try {
                  expect(archive.members.length, sizes.length);
                  for (final member in archive.members) {
                    var count = 0;
                    await for (final data in archive.openMember(member)) {
                      expect(data.every((byte) => byte == 0), isTrue);
                      count += data.length;
                    }
                    expect(count, sizes[member.name]);
                  }
                } finally {
                  await archive.close();
                }
                // Independent vendor listing confirms actual folder grouping;
                // this is test-only, not an application command/output parser.
                final output = File(p.join(root.path, 'solid-$solid.7z'));
                await output.writeAsBytes(bytes);
                final listed = await Process.run(executable!, [
                  'l',
                  '-slt',
                  output.path,
                ]);
                expect(listed.exitCode, 0);
                final blocks = <int, int>{};
                for (final record in (listed.stdout as String).split(
                  RegExp(r'\r?\n\r?\n'),
                )) {
                  final block = RegExp(
                    r'^Block = (\d+)\r?$',
                    multiLine: true,
                  ).firstMatch(record);
                  final size = RegExp(
                    r'^Size = (\d+)\r?$',
                    multiLine: true,
                  ).firstMatch(record);
                  if (block != null && size != null) {
                    final id = int.parse(block.group(1)!);
                    blocks[id] = (blocks[id] ?? 0) + int.parse(size.group(1)!);
                  }
                }
                expect(
                  blocks.values.toSet(),
                  solid == 16
                      ? {4 * mib, 24 * mib, 64 * mib}
                      : {28 * mib, 64 * mib},
                );
                expect(
                  blocks.values.every(
                    (size) => size <= kArchiveExternalPackerMemberLimit,
                  ),
                  isTrue,
                );
              }

              // A tool ignoring the bounded-solid switch must still fail the
              // existing reader limit, even though every individual file fits.
              final ignoresSolid = NativeArchiveExternalPackerEngine(
                hasAccess: (_) async => true,
                stagingRoot: () async => p.join(root.path, 'stages'),
                runner: (request) => runArchiveExternalPackerProcess(
                  ArchiveExternalPackerInvocation(
                    executable: request.executable,
                    arguments: [
                      for (final argument in request.arguments)
                        argument.startsWith('-ms=') ? '-ms=on' : argument,
                    ],
                    directory: request.directory,
                    environment: request.environment,
                    timeout: request.timeout,
                    outputPath: request.outputPath,
                    maxOutputBytes: request.maxOutputBytes,
                    isCancelled: request.isCancelled,
                  ),
                ),
              );
              final unbounded = await collectArchiveWrite(
                (sink) => ignoresSolid.write(
                  installation: installation,
                  options: const ArchiveExternalPackerOptions(
                    name: 'unbounded.7z',
                    format: ArchiveExternalPackerFormat.sevenZip,
                  ),
                  entries: entries,
                  sink: sink,
                  maxOutputBytes: mib,
                ),
              );
              await expectLater(
                openViewerArchive(unbounded, name: 'unbounded.7z'),
                throwsA(isA<ArchiveViewException>().having(
                  (error) => error.code,
                  'resource limit',
                  ArchiveMessageCode.archiveLimit,
                )),
              );
            },
            timeout: const Timeout(Duration(minutes: 3)),
          );
        }
      },
      skip: executable == null
          ? 'Set the explicit installed engine path to run native CLI tests.'
          : false,
    );
  }
}
