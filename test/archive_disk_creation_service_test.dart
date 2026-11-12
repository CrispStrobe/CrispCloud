import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/archive_creation_service.dart';
import 'package:crisp_cloud/services/archive_dmg_reader.dart';
import 'package:crisp_cloud/services/archive_hfs_reader.dart';
import 'package:crisp_cloud/services/archive_hfs_writer.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/native_file_primitives.dart';
import 'package:crisp_cloud/services/storage_transfer_contract.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/io.dart' as koni;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/archive_creation_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const service = ArchiveCreationService();
  Matcher error(ArchiveCreationError code) => throwsA(
    isA<ArchiveCreationException>().having((error) => error.code, 'code', code),
  );

  Future<ArchiveCreationResult> create(
    ArchiveCreationBackend backend,
    ArchiveCreationFormat format, {
    ArchiveCreationBackend? destination,
    String selected = '/input/folder',
    bool Function()? isCancelled,
    void Function(ArchiveCreationProgress)? onProgress,
  }) async => service.create(
    source: backend,
    destination: destination ?? backend,
    files: [(await backend.stat(selected))!],
    destinationDirectory: '/output',
    options: ArchiveCreationOptions(
      name: 'selection${format.extension}',
      format: format,
      compression: format.defaultCompression,
    ),
    isCancelled: isCancelled,
    onProgress: onProgress,
  );

  for (final format in [
    ArchiveCreationFormat.hfsx,
    ArchiveCreationFormat.dmg,
  ]) {
    test(
      '${format.name} captures executable and directory modes without unrelated metadata',
      () async {
        final backend = _PermissionBackend()
          ..put('/input/folder/run.sh', utf8.encode('#!/bin/sh\nexit 0\n'))
          ..modes.addAll({
            '/input/folder': 0x1c0,
            '/input/folder/run.sh': 0x1ed,
          });
        final result = await create(backend, format);
        final archive = await openViewerArchive(
          backend.contents[result.path]!,
          name: result.path,
        );
        try {
          final folder = archive.members.singleWhere(
            (member) =>
                member.name == 'folder' || member.name.endsWith('/folder'),
          );
          final executable = archive.members.singleWhere(
            (member) => member.name.endsWith('folder/run.sh'),
          );
          expect(folder.posixMode, 0x4000 | 0x1c0);
          expect(executable.posixMode, 0x8000 | 0x1ed);
          expect(
            utf8.decode(await archive.readMember(executable)),
            '#!/bin/sh\nexit 0\n',
          );
        } finally {
          await archive.close();
        }
        expect(backend.metadataReads.toSet(), {
          '/input/folder',
          '/input/folder/run.sh',
        });
        expect(
          backend.metadataReads
              .where((path) => path.endsWith('/run.sh'))
              .length,
          greaterThan(1),
        );
      },
    );

    for (final changedPath in ['/input/folder', '/input/folder/run.sh']) {
      test(
        '${format.name} refuses publication when the mode of $changedPath changes',
        () async {
          final backend = _PermissionBackend()
            ..put('/input/folder/run.sh', [1, 2, 3])
            ..modes.addAll({
              '/input/folder': 0x1c0,
              '/input/folder/run.sh': 0x1ed,
            });
          var reachedStage = false;
          backend.beforeStageVerification = () {
            reachedStage = true;
            backend.modes[changedPath] = backend.modes[changedPath]! ^ 0x40;
          };
          await expectLater(
            create(backend, format),
            error(ArchiveCreationError.sourceChanged),
          );
          expect(reachedStage, isTrue);
          expect(backend.writes, isEmpty);
          expect(
            backend.contents.keys.where((path) => path.startsWith('/output/')),
            isEmpty,
          );
        },
      );
    }

    test(
      '${format.name} creation publishes normalized files and the proper disk view',
      () async {
        final backend = ArchiveCreationBackend()
          ..put('/input/folder/café.txt', utf8.encode('Complete data image.'))
          ..put('/input/folder/資料/empty.txt', []);
        backend.directories.add('/input/folder/empty-dir');
        final result = await create(backend, format);
        expect(backend.writes, [result.path]);
        expect(result.entryCount, 5);
        final archive = await openViewerArchive(
          backend.contents[result.path]!,
          name: result.path,
        );
        addTearDown(archive.close);
        final files = archive.members
            .where((m) => !m.name.startsWith('partitions/'))
            .toList();
        if (format == ArchiveCreationFormat.dmg) {
          expect(
            archive.members.where((m) => m.name.startsWith('partitions/')),
            hasLength(1),
          );
          expect(files.every((m) => m.name.startsWith('files/001-')), isTrue);
        }
        final names = files
            .map(
              (m) => format == ArchiveCreationFormat.dmg
                  ? m.name.split('/').skip(2).join('/')
                  : m.name,
            )
            .toSet();
        expect(names, {
          'folder',
          normalizeHfsArchivePath('folder/café.txt'),
          'folder/資料',
          'folder/資料/empty.txt',
          'folder/empty-dir',
        });
        final text = files.singleWhere(
          (m) => m.name.endsWith(normalizeHfsArchivePath('café.txt')),
        );
        expect(
          utf8.decode(await archive.readMember(text)),
          'Complete data image.',
        );
        expect(
          backend.contents.keys.where((path) => path.contains('.stage')),
          isEmpty,
        );
      },
    );

    test(
      '${format.name} rejects canonical Unicode collisions before publication',
      () async {
        final backend = ArchiveCreationBackend()
          ..put('/input/folder/é.txt', [1])
          ..put('/input/folder/e\u0301.txt', [2]);
        await expectLater(
          create(backend, format),
          error(ArchiveCreationError.duplicateName),
        );
        expect(backend.writes, isEmpty);
      },
    );

    test(
      '${format.name} notices same-size source changes on a verification reread',
      () async {
        final backend = _ChangingBackend()..put('/input/folder/one', [1, 2, 3]);
        await expectLater(
          create(backend, format),
          error(ArchiveCreationError.sourceChanged),
        );
        expect(backend.writes, isEmpty);
        expect(
          backend.contents.keys.where((path) => path.contains('.stage')),
          isEmpty,
        );
      },
    );

    test(
      '${format.name} rejects staged corruption without publishing a name',
      () async {
        final backend = ArchiveCreationBackend()
          ..put('/input/folder/one', [1, 2, 3]);
        backend.beforeStageVerification = () {
          final bytes = backend.contents['/output/.stage']!;
          bytes[bytes.length - 1] ^= 1;
        };
        await expectLater(
          create(backend, format),
          error(ArchiveCreationError.verificationFailed),
        );
        expect(backend.writes, isEmpty);
        expect(
          backend.contents.keys.where((path) => path.startsWith('/output/')),
          isEmpty,
        );
      },
    );

    test(
      '${format.name} rechecks source content immediately before committing',
      () async {
        final backend = ArchiveCreationBackend()
          ..put('/input/folder/one', [1, 2, 3]);
        backend.beforeStageVerification = () =>
            backend.put('/input/folder/one', [4, 5, 6]);
        await expectLater(
          create(backend, format),
          error(ArchiveCreationError.sourceChanged),
        );
        expect(backend.writes, isEmpty);
      },
    );

    test(
      '${format.name} cancellation at the staged-verification boundary refuses publication',
      () async {
        final backend = ArchiveCreationBackend()
          ..put('/input/folder/one', [1, 2, 3]);
        var cancelled = false;
        backend.beforeStageVerification = () => cancelled = true;
        await expectLater(
          create(backend, format, isCancelled: () => cancelled),
          error(ArchiveCreationError.cancelled),
        );
        expect(backend.writes, isEmpty);
        expect(
          backend.contents.keys.where((path) => path.startsWith('/output/')),
          isEmpty,
        );
      },
    );
  }

  test(
    'creation does not request permissions from an incapable source',
    () async {
      final backend = _PermissionBackend(advertisePermissions: false)
        ..put('/input/folder/run.sh', [1, 2, 3]);
      final result = await create(backend, ArchiveCreationFormat.hfsx);
      expect(backend.writes, [result.path]);
      expect(backend.metadataReads, isEmpty);
    },
  );

  test('a source that advertises permissions must supply a mode', () async {
    final backend = _PermissionBackend()
      ..put('/input/folder/run.sh', [1, 2, 3])
      ..modes['/input/folder'] = 0x1c0;
    await expectLater(
      create(backend, ArchiveCreationFormat.hfsx),
      error(ArchiveCreationError.unsupportedEntry),
    );
    expect(backend.metadataReads, contains('/input/folder/run.sh'));
    expect(backend.writes, isEmpty);
    expect(
      backend.contents.keys.where((path) => path.startsWith('/output/')),
      isEmpty,
    );
  });

  for (final special in [
    ('setuid file', '/input/folder/run.sh', 0x800),
    ('setgid directory', '/input/folder', 0x400),
  ]) {
    test('creation refuses ${special.$1} without captured ownership', () async {
      for (final format in [
        ArchiveCreationFormat.hfsx,
        ArchiveCreationFormat.dmg,
      ]) {
        final backend = _PermissionBackend()
          ..put('/input/folder/run.sh', [1, 2, 3])
          ..modes.addAll({
            '/input/folder': 0x1c0,
            '/input/folder/run.sh': 0x1ed,
          });
        backend.modes[special.$2] = backend.modes[special.$2]! | special.$3;
        await expectLater(
          create(backend, format),
          throwsA(
            isA<ArchiveViewException>().having(
              (error) => error.message,
              'reason',
              contains('ownership'),
            ),
          ),
        );
        expect(backend.writes, isEmpty);
        expect(
          backend.contents.keys.where((path) => path.startsWith('/output/')),
          isEmpty,
        );
      }
    });
  }

  test(
    'native executable and directory permissions survive HFSX and DMG creation',
    () async {
      SharedPreferences.setMockInitialValues({});
      final temporary = await Directory.systemTemp.createTemp(
        'crisp-disk-modes-',
      );
      final root = Directory(await temporary.resolveSymbolicLinks());
      addTearDown(() => root.delete(recursive: true));
      final folder = await Directory('${root.path}/scripts').create();
      final executable = await File('${folder.path}/run.sh')
          .writeAsString('#!/bin/sh\nprintf complete\n');
      final source = LocalOperationBackend(
        LocalFileService(),
        isCurrent: () => true,
      );
      await source.writeMetadata(
        folder.path,
        const TransferMetadata(mode: 0x1c0),
      );
      await source.writeMetadata(
        executable.path,
        const TransferMetadata(mode: 0x1ed),
      );
      expect((await folder.stat()).mode & 0xfff, 0x1c0);
      expect((await executable.stat()).mode & 0xfff, 0x1ed);
      for (final format in [
        ArchiveCreationFormat.hfsx,
        ArchiveCreationFormat.dmg,
      ]) {
        final destination = ArchiveCreationBackend();
        final result = await service.create(
          source: source,
          destination: destination,
          files: [(await source.stat(folder.path))!],
          destinationDirectory: '/output',
          options: ArchiveCreationOptions(
            name: 'native${format.extension}',
            format: format,
            compression: format.defaultCompression,
          ),
        );
        final archive = await openViewerArchive(
          destination.contents[result.path]!,
          name: result.path,
        );
        try {
          expect(
            archive.members
                .singleWhere((m) => m.name.endsWith('scripts'))
                .posixMode,
            0x4000 | 0x1c0,
          );
          expect(
            archive.members
                .singleWhere((m) => m.name.endsWith('scripts/run.sh'))
                .posixMode,
            0x8000 | 0x1ed,
          );
        } finally {
          await archive.close();
        }
      }
    },
    skip: !supportsNativePermissions,
  );

  test('HFSX and DMG service creation stream a >64 MiB source through native staging', () async {
    final source = _LargeSource();
    final directory = await Directory.systemTemp.createTemp(
      'crisp-created-disk-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final expected = await sha256.bind(source.bytes()).single;
    for (final format in [
      ArchiveCreationFormat.hfsx,
      ArchiveCreationFormat.dmg,
    ]) {
      final destination = _NativeDestination(directory);
      final result = await create(
        source,
        format,
        destination: destination,
        selected: '/input/large.bin',
      );
      expect(destination.writes, [result.path]);
      expect(destination.maxChunk, lessThanOrEqualTo(256 * 1024));
      final input = await koni.FileByteSource.open(
        destination.file(result.path).path,
      );
      final archive = format == ArchiveCreationFormat.dmg
          ? await openDmgArchive(input, maxMemberBytes: _LargeSource.size)
          : await openHfsArchive(input, maxMemberBytes: _LargeSource.size);
      try {
        final member = archive.members.singleWhere(
          (m) => m.name.endsWith('large.bin'),
        );
        expect(member.size, _LargeSource.size);
        final actual = await sha256
            .bind(
              archive.openMember(
                member,
                maxBytes: _LargeSource.size,
                chunkSize: 128 * 1024,
              ),
            )
            .single;
        expect(actual, expected);
      } finally {
        await archive.close();
      }
    }
    expect(source.reads, greaterThanOrEqualTo(6));
    expect(source.largestYield, lessThanOrEqualTo(65536));
    expect(File('${directory.path}/stage').existsSync(), isFalse);
  }, timeout: const Timeout(Duration(minutes: 3)));
}

class _PermissionBackend extends ArchiveCreationBackend {
  _PermissionBackend({this.advertisePermissions = true});
  final bool advertisePermissions;
  final modes = <String, int>{};
  final metadataReads = <String>[];

  @override
  StorageTransferCapabilities get capabilities =>
      StorageTransferCapabilities(permissions: advertisePermissions);

  @override
  Future<TransferMetadata> readMetadataFields(
    String path, {
    bool permissions = true,
    bool modified = true,
    bool accessed = true,
    bool created = true,
    bool ownership = true,
    bool extendedAttributes = true,
    bool acl = true,
    bool windowsAttributes = true,
  }) async {
    metadataReads.add(path);
    if (!advertisePermissions ||
        !permissions ||
        modified ||
        accessed ||
        created ||
        ownership ||
        extendedAttributes ||
        acl ||
        windowsAttributes) {
      throw StateError('Only advertised permission metadata may be requested.');
    }
    return TransferMetadata(mode: modes[path]);
  }
}

class _ChangingBackend extends ArchiveCreationBackend {
  int reads = 0;
  @override
  Stream<List<int>> readFile(FileItem file) async* {
    if (file.path == '/input/folder/one' && ++reads == 2) {
      put(file.path!, [4, 5, 6]);
    }
    yield* super.readFile(file);
  }
}

class _LargeSource extends ArchiveCreationBackend {
  static const size = 65 * 1024 * 1024 + 333;
  final block = Uint8List.fromList(List.generate(65536, (i) => i % 251));
  int reads = 0, largestYield = 0;
  @override
  Future<FileItem?> stat(String path) async => path == '/input/large.bin'
      ? FileItem(
          name: 'large.bin',
          path: path,
          isFolder: false,
          size: size,
          updatedAt: DateTime.utc(2026),
        )
      : super.stat(path);
  Stream<List<int>> bytes() async* {
    for (var at = 0; at < size; at += block.length) {
      final count = size - at < block.length ? size - at : block.length;
      if (count > largestYield) largestYield = count;
      yield Uint8List.sublistView(block, 0, count);
    }
  }

  @override
  Stream<List<int>> readFile(FileItem file) async* {
    if (file.path != '/input/large.bin') {
      throw StateError('Unexpected source read.');
    }
    reads++;
    yield* bytes();
  }
}

class _NativeDestination extends ArchiveCreationBackend {
  _NativeDestination(this.directory);
  final Directory directory;
  int maxChunk = 0;
  File file(String path) => File('${directory.path}/${paths.basename(path)}');
  @override
  Future<FileItem?> stat(String path) async {
    if (directories.contains(path)) return super.stat(path);
    final local = file(path);
    if (!await local.exists()) return null;
    return FileItem(
      name: paths.basename(path),
      path: path,
      isFolder: false,
      size: await local.length(),
      updatedAt: DateTime.utc(2026),
    );
  }

  @override
  Stream<List<int>> readFile(FileItem item) => file(item.path!).openRead();
  @override
  Future<void> writePreparedFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
    Future<void> Function(FileItem)? verifyStaged,
    Future<void> Function(Map<String, dynamic>)? checkpoint,
  }) async {
    if (replace || await stat(path) != null) throw StateError('Output exists.');
    const stage = '/output/stage';
    final output = await file(stage).open(mode: FileMode.write);
    try {
      try {
        await for (final bytes in data) {
          if (bytes.length > maxChunk) maxChunk = bytes.length;
          await output.writeFrom(bytes);
        }
        await output.flush();
      } finally {
        await output.close();
      }
      await verifyStaged?.call((await stat(stage))!);
      if (await stat(path) != null) throw StateError('Output exists.');
      await file(stage).rename(file(path).path);
      writes.add(path);
    } finally {
      if (await file(stage).exists()) await file(stage).delete();
    }
  }
}
