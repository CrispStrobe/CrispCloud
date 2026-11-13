import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/models/archive_endpoint.dart';
import 'package:crisp_cloud/services/archive_creation_service.dart';
import 'package:crisp_cloud/services/archive_external_packer.dart';
import 'package:crisp_cloud/services/archive_external_packer_stub.dart' as stub;
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/archive_write_model.dart';
import 'package:crisp_cloud/services/archive_writer_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/archive_creation_backend.dart';

ArchiveExternalPackerInstallation _installation({
  ArchiveExternalPackerKind kind = ArchiveExternalPackerKind.sevenZip,
  Set<ArchiveExternalPackerFormat>? formats,
}) => ArchiveExternalPackerInstallation(
  configuration: ArchiveExternalPackerConfiguration(
    platform: 'linux',
    kind: kind,
    executable:
        '/tools/${kind == ArchiveExternalPackerKind.rar ? 'rar' : '7zz'}',
  ),
  identity: ArchiveExternalPackerIdentity(
    path: '/tools/7zz',
    length: 10,
    modified: DateTime.utc(2024),
    changed: DateTime.utc(2024),
    mode: 0x1c0,
    sha256: 'a' * 64,
  ),
  version: '23.01',
  formats:
      formats ??
      (kind == ArchiveExternalPackerKind.rar
          ? {ArchiveExternalPackerFormat.rar}
          : {
              ArchiveExternalPackerFormat.zip,
              ArchiveExternalPackerFormat.sevenZip,
            }),
);

class _Engine implements ArchiveExternalPackerEngine {
  @override
  String? platform = 'linux';
  int calls = 0;
  List<ArchiveWriteEntry> captured = [];
  Future<void> Function()? beforeWrite;
  List<ArchiveWriteEntry> Function(List<ArchiveWriteEntry>)? changeEntries;
  ArchiveEndpointFormat? wrongFormat;
  Uint8List? rawOutput;
  ArchiveExternalPackerOptions? options;
  @override
  Future<List<ArchiveExternalPackerConfiguration>> discover() async => [];
  @override
  Future<ArchiveExternalPackerInstallation> probe(
    ArchiveExternalPackerConfiguration configuration, {
    bool Function()? isCancelled,
  }) async => _installation(kind: configuration.kind);
  @override
  Future<void> write({
    required ArchiveExternalPackerInstallation installation,
    required ArchiveExternalPackerOptions options,
    required List<ArchiveWriteEntry> entries,
    required Future<void> Function(List<int>) sink,
    required int maxOutputBytes,
    bool Function()? isCancelled,
  }) async {
    calls++;
    this.options = options;
    captured = entries;
    await beforeWrite?.call();
    if (rawOutput != null) {
      await sink(rawOutput!);
      return;
    }
    await writeArchiveEntries(
      wrongFormat ??
          switch (options.format) {
            ArchiveExternalPackerFormat.zip => ArchiveEndpointFormat.zip,
            ArchiveExternalPackerFormat.sevenZip =>
              ArchiveEndpointFormat.sevenZip,
            ArchiveExternalPackerFormat.rar => ArchiveEndpointFormat.rar,
          },
      changeEntries?.call(entries) ?? entries,
      sink: sink,
      maxOutputBytes: maxOutputBytes,
      isCancelled: isCancelled,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Matcher failure(ArchiveExternalPackerFailure failure) => throwsA(
    isA<ArchiveExternalPackerException>().having(
      (e) => e.failure,
      'failure',
      failure,
    ),
  );
  Matcher creation(ArchiveCreationError code) => throwsA(
    isA<ArchiveCreationException>().having((e) => e.code, 'code', code),
  );

  group('machine-local tool preferences', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('only the versioned platform, kind and path are persisted', () async {
      final store = ArchiveExternalPackerStore('linux');
      final configuration = _installation().configuration;
      expect(await store.load(), isNull);
      await store.save(configuration);
      expect((await store.load())!.toJson(), configuration.toJson());
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getKeys(), {'archive_external_packer_v1_linux'});
      expect(jsonDecode(preferences.getString(preferences.getKeys().single)!), {
        'version': 1,
        'platform': 'linux',
        'kind': 'sevenZip',
        'executable': '/tools/7zz',
      });
      expect(await ArchiveExternalPackerStore('windows').load(), isNull);
      await store.reset();
      expect(await store.load(), isNull);
    });

    for (final raw in [
      'not json',
      '{}',
      '{"version":9}',
      jsonEncode({
        'version': 1,
        'platform': 'linux',
        'kind': 'sevenZip',
        'executable': '/tools/7zz',
        'password': 'secret',
      }),
    ]) {
      test('rejects malformed or expanded settings ${raw.length}', () async {
        SharedPreferences.setMockInitialValues({
          'archive_external_packer_v1_linux': raw,
        });
        await expectLater(
          ArchiveExternalPackerStore('linux').load(),
          failure(ArchiveExternalPackerFailure.invalidConfiguration),
        );
      });
    }

    test('does not save a configuration for another platform', () async {
      await expectLater(
        ArchiveExternalPackerStore('windows')
            .save(_installation().configuration),
        failure(ArchiveExternalPackerFailure.invalidConfiguration),
      );
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    });
  });

  group('fixed configuration validation', () {
    for (final path in [
      '7zz',
      '',
      '/tmp/7zz\n--evil',
      '/tmp/tool.cmd',
      '/tmp/tool.ps1',
      '/tmp/tool.bat',
    ]) {
      test(
        'rejects a relative, control or script path ${jsonEncode(path)}',
        () {
          expect(
            () => ArchiveExternalPackerConfiguration(
              platform: 'linux',
              kind: ArchiveExternalPackerKind.sevenZip,
              executable: path,
            ),
            failure(ArchiveExternalPackerFailure.invalidConfiguration),
          );
        },
      );
    }
    test('requires native Windows exe and excludes drive-relative paths', () {
      for (final path in [r'C:7zz.exe', r'C:\tools\rar.cmd', r'C:\tools\7zz']) {
        expect(
          () => ArchiveExternalPackerConfiguration(
            platform: 'windows',
            kind: ArchiveExternalPackerKind.sevenZip,
            executable: path,
          ),
          failure(ArchiveExternalPackerFailure.invalidConfiguration),
        );
      }
      expect(
        ArchiveExternalPackerConfiguration(
          platform: 'windows',
          kind: ArchiveExternalPackerKind.sevenZip,
          executable: r'C:\Program Files\7-Zip\7z.exe',
        ).executable,
        r'C:\Program Files\7-Zip\7z.exe',
      );
    });
    test('public failures never include process logs, paths or passwords', () {
      for (final value in ArchiveExternalPackerFailure.values) {
        expect(
          ArchiveExternalPackerException(value).toString(),
          'ArchiveExternalPackerException(${value.name})',
        );
      }
    });
  });

  group('shared verified creation boundary', () {
    late ArchiveCreationBackend backend;
    late _Engine engine;
    late ArchiveExternalPackerService service;
    setUp(() {
      backend = ArchiveCreationBackend()
        ..put(
          '/input/folder/日本語.txt',
          utf8.encode('original selected contents'),
        )
        ..put('/input/folder/empty', []);
      backend.directories.add('/input/folder/nested');
      engine = _Engine();
      service = ArchiveExternalPackerService(engine: engine);
    });
    Future<ArchiveCreationResult> create({
      ArchiveExternalPackerFormat format = ArchiveExternalPackerFormat.zip,
      ArchiveExternalPackerInstallation? installation,
      bool Function()? cancelled,
    }) async => service.create(
      source: backend,
      destination: backend,
      files: [(await backend.stat('/input/folder'))!],
      destinationDirectory: '/output',
      installation: installation ?? _installation(),
      options: ArchiveExternalPackerOptions(
        name: 'created${format.extension}',
        format: format,
        compression: ArchiveExternalPackerCompression.maximum,
      ),
      isCancelled: cancelled,
    );

    for (final format in ArchiveExternalPackerFormat.values) {
      test(
        '${format.name} candidate uses source capture and exact read-back before publication',
        () async {
          final result = await create(
            format: format,
            installation: _installation(
              kind: format == ArchiveExternalPackerFormat.rar
                  ? ArchiveExternalPackerKind.rar
                  : ArchiveExternalPackerKind.sevenZip,
            ),
          );
          expect(result.entryCount, 4);
          expect(engine.calls, 1);
          expect(
            engine.options!.compression,
            ArchiveExternalPackerCompression.maximum,
          );
          expect(engine.captured.map((e) => e.path).toSet(), {
            'folder',
            'folder/日本語.txt',
            'folder/empty',
            'folder/nested',
          });
          expect(engine.captured.every((e) => !e.path.startsWith('/')), isTrue);
          expect(backend.writes, [result.path]);
          final archive = await openViewerArchive(
            backend.contents[result.path]!,
            name: result.path,
          );
          try {
            expect(
              await archive.readMember(
                archive.members.singleWhere((e) => e.name.endsWith('日本語.txt')),
              ),
              backend.contents['/input/folder/日本語.txt'],
            );
          } finally {
            await archive.close();
          }
        },
      );
    }

    test(
      '7-Zip never inherits RAR create permission from a forged capability',
      () async {
        await expectLater(
          create(
            format: ArchiveExternalPackerFormat.rar,
            installation: _installation(
              formats: {ArchiveExternalPackerFormat.rar},
            ),
          ),
          failure(ArchiveExternalPackerFailure.unsupportedFormat),
        );
        expect(engine.calls, 0);
        expect(backend.writes, isEmpty);
      },
    );
    test('an absent capability prevents the writer from running', () async {
      await expectLater(
        create(
          installation: _installation(
            formats: {ArchiveExternalPackerFormat.sevenZip},
          ),
        ),
        failure(ArchiveExternalPackerFailure.unsupportedFormat),
      );
      expect(engine.calls, 0);
    });
    test('web and unavailable native builds cannot start a writer', () async {
      engine.platform = null;
      await expectLater(
        create(),
        failure(ArchiveExternalPackerFailure.unsupportedPlatform),
      );
      expect(engine.calls, 0);
      final unavailable = stub.createArchiveExternalPackerEngine();
      expect(unavailable.platform, isNull);
      expect(await unavailable.discover(), isEmpty);
      await expectLater(
        unavailable.probe(_installation().configuration),
        failure(ArchiveExternalPackerFailure.unsupportedPlatform),
      );
    });
    test(
      'an existing destination is not replaced and the tool never runs',
      () async {
        backend.put('/output/created.zip', [8, 9]);
        await expectLater(
          create(),
          creation(ArchiveCreationError.destinationExists),
        );
        expect(engine.calls, 0);
        expect(backend.contents['/output/created.zip'], [8, 9]);
      },
    );
    test('valid container with substituted content cannot publish', () async {
      engine.changeEntries = (entries) => [
        for (final entry in entries)
          entry.isDirectory
              ? entry
              : ArchiveWriteEntry(
                  path: entry.path,
                  isDirectory: false,
                  size: entry.size,
                  modified: entry.modified,
                  mode: entry.mode,
                  readChunks: () => Stream.value(List.filled(entry.size, 88)),
                ),
      ];
      await expectLater(
        create(),
        creation(ArchiveCreationError.verificationFailed),
      );
      expect(backend.writes, isEmpty);
      expect(backend.contents.keys.where((p) => p.contains('.stage')), isEmpty);
    });
    test(
      'valid container with an omitted empty directory cannot publish',
      () async {
        engine.changeEntries = (entries) =>
            entries.where((e) => e.path != 'folder/nested').toList();
        await expectLater(
          create(),
          creation(ArchiveCreationError.verificationFailed),
        );
        expect(backend.writes, isEmpty);
      },
    );
    test('container format must match the selected engine output', () async {
      engine.wrongFormat = ArchiveEndpointFormat.sevenZip;
      await expectLater(
        create(),
        creation(ArchiveCreationError.verificationFailed),
      );
      expect(backend.writes, isEmpty);
    });
    test('truncated output cannot publish', () async {
      engine.rawOutput = Uint8List.fromList([0x50, 0x4b, 3, 4]);
      await expectLater(
        create(),
        throwsA(
          anyOf(
            isA<ArchiveViewException>(),
            isA<ArchiveCreationException>().having(
              (e) => e.code,
              'code',
              ArchiveCreationError.verificationFailed,
            ),
          ),
        ),
      );
      expect(backend.writes, isEmpty);
    });
    test(
      'source content changed after packing is rejected at staging',
      () async {
        backend.beforeStageVerification = () => backend.put(
          '/input/folder/日本語.txt',
          utf8.encode('changed original contents!'),
        );
        await expectLater(
          create(),
          creation(ArchiveCreationError.sourceChanged),
        );
        expect(backend.writes, isEmpty);
      },
    );
    test('destination races cannot replace a newly created target', () async {
      backend.beforeStageVerification = () =>
          backend.put('/output/created.zip', [7, 7]);
      await expectLater(
        create(),
        throwsA(anyOf(isA<ArchiveCreationException>(), isA<StateError>())),
      );
      expect(backend.contents['/output/created.zip'], [7, 7]);
      expect(backend.writes, isEmpty);
    });
    test('cancellation before capture prevents the writer', () async {
      await expectLater(
        create(cancelled: () => true),
        creation(ArchiveCreationError.cancelled),
      );
      expect(engine.calls, 0);
      expect(backend.writes, isEmpty);
    });
  });
}
