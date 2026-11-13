import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/archive_browser_session.dart';
import 'package:crisp_cloud/services/archive_output_spool.dart';
import 'package:crisp_cloud/services/archive_output_spool_memory.dart'
    as memory;
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:crisp_cloud/services/archive_volume_backend.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;
import 'package:path/path.dart' as p;

import 'support/archive_volume_fixtures.dart';

class _Backend extends FileOperationBackend {
  _Backend({Uint8List? bytes}) {
    final parts = volumeSplitBytes(bytes ?? volumeReferenceSevenZip());
    for (var index = 0; index < parts.length; index++) {
      final name = 'fixture.7z.${(index + 1).toString().padLeft(3, '0')}';
      data['/set/$name'] = parts[index];
    }
  }
  final data = <String, Uint8List>{};
  final metadata = <String, Map<String, dynamic>>{};
  final sizes = <String, int>{};
  final uuids = <String, String>{};
  final links = <String>{}, folders = <String>{};
  final extras = <FileItem>[];
  final reads = <String>[];
  final mutations = <String>[];
  bool current = true, lateError = false, invalidBytes = false;
  bool reverseListing = false, mutableIdentity = false;
  Object identityValue = Object();
  int lists = 0;
  void Function(String path)? afterChunk;
  void Function(int number)? beforeList;
  List<FileItem> Function(List<FileItem>)? mapListing;

  FileItem item(String path) => FileItem(
    name: p.posix.basename(path),
    path: path,
    isFolder: folders.contains(path),
    isSymlink: links.contains(path),
    size: sizes[path] ?? data[path]!.length,
    uuid: uuids[path],
    updatedAt: DateTime.utc(2026, 1, 2),
    metadata: metadata.putIfAbsent(path, () => {'revision': 'one'}),
  );

  FileItem get selected => item('/set/fixture.7z.001');

  @override
  Object get identity => mutableIdentity ? identityValue : this;
  @override
  String get label => 'Captured volume storage';
  @override
  p.Context get paths => p.posix;
  @override
  bool get isCurrent => current;
  @override
  Future<FileItem?> stat(String path) async =>
      data.containsKey(path) ? item(path) : null;
  @override
  Future<List<FileItem>> list(String path) async {
    expect(path, '/set');
    lists++;
    beforeList?.call(lists);
    var result = [
      for (final key in data.keys)
        if (p.posix.dirname(key) == path) item(key),
      ...extras,
    ];
    if (reverseListing) result = result.reversed.toList();
    return mapListing?.call(result) ?? result;
  }

  @override
  Stream<List<int>> readFile(FileItem file) async* {
    reads.add(file.path!);
    final bytes = data[file.path!]!;
    for (var offset = 0; offset < bytes.length; offset += 17) {
      final count = bytes.length - offset < 17 ? bytes.length - offset : 17;
      yield Uint8List.sublistView(bytes, offset, offset + count);
      afterChunk?.call(file.path!);
    }
    if (invalidBytes) yield [-1];
    if (lateError) throw StateError('Late provider failure.');
  }

  @override
  Future<void> createDirectory(String path) async =>
      mutations.add('mkdir:$path');
  @override
  Future<void> writeFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
  }) async => mutations.add('write:$path');
  @override
  Future<void> deleteFile(FileItem file) async =>
      mutations.add('delete:${file.path}');
  @override
  Future<void> deleteEmptyDirectory(String path) async =>
      mutations.add('rmdir:$path');
}

class _StalledBackend extends _Backend {
  _StalledBackend(this.phase) {
    mutableIdentity = true;
  }
  final String phase;
  final entered = Completer<void>();
  final release = Completer<void>();
  Future<void> _stall() async {
    if (entered.isCompleted) return;
    entered.complete();
    await release.future;
  }

  @override
  Future<FileItem?> stat(String path) async {
    if (phase == 'stat' && !entered.isCompleted) await _stall();
    return super.stat(path);
  }

  @override
  Future<List<FileItem>> list(String path) async {
    if (phase == 'list' && lists == 0 || phase == 'final list' && lists == 1) {
      await _stall();
    }
    return super.list(path);
  }

  @override
  Stream<List<int>> readFile(FileItem file) async* {
    await for (final chunk in super.readFile(file)) {
      yield chunk;
      if (phase == 'read' && file.name.endsWith('.002')) await _stall();
    }
  }
}

class _TrackedSpool extends ArchiveOutputSpool {
  _TrackedSpool(this.inner);
  final ArchiveOutputSpool inner;
  int disposes = 0;
  bool failWrite = false, failDispose = false;
  @override
  int get length => inner.length;
  @override
  int get maxBytes => inner.maxBytes;
  @override
  bool get isSealed => inner.isSealed;
  @override
  Future<void> write(List<int> bytes) async {
    if (failWrite) throw StateError('Snapshot write failed.');
    await inner.write(bytes);
  }

  @override
  Future<void> finish() => inner.finish();
  @override
  Stream<List<int>> openRead({int chunkSize = 256 * 1024}) =>
      inner.openRead(chunkSize: chunkSize);
  @override
  Future<koni.ByteSource> openByteSource() => inner.openByteSource();
  @override
  Future<void> dispose() async {
    disposes++;
    await inner.dispose();
    if (failDispose) throw StateError('Snapshot cleanup failed.');
  }
}

class _Capture {
  final spools = <_TrackedSpool>[];
  bool failWrite = false, failDispose = false;
  void Function()? afterCreate;
  Future<ArchiveOutputSpool> create(int limit) async {
    final spool =
        _TrackedSpool(await memory.createArchiveOutputSpool(maxBytes: limit))
          ..failWrite = failWrite
          ..failDispose = failDispose;
    spools.add(spool);
    afterCreate?.call();
    return spool;
  }

  void expectDisposed() {
    for (final spool in spools) {
      expect(spool.disposes, 1);
      expect(spool.isSealed, isFalse);
    }
  }
}

Future<Uint8List> _read(ArchiveVolumeOpen opened, String name) =>
    opened.archive.readMember(
      opened.archive.members.singleWhere((member) => member.name == name),
    );

void main() {
  test(
    'backend captures every original part and hashes exact joined bytes',
    () async {
      final backend = _Backend()..reverseListing = true;
      backend.data['/set/unrelated.7z.001'] = Uint8List.fromList([1]);
      backend.data['/set/fixture.7z.notes'] = Uint8List.fromList([2]);
      final capture = _Capture();
      final opened = await openSevenZipVolumeArchive(
        backend,
        backend.selected,
        spoolToDisk: false,
        createSpool: capture.create,
      );
      expect(opened.archive.formatName, 'volumes/7z');
      expect(opened.parts.length, 4);
      expect(opened.file.name, 'fixture.7z.001');
      expect(
        opened.fingerprint,
        sha256.convert(volumeReferenceSevenZip()).toString(),
      );
      expect(backend.reads, [
        for (var n = 1; n <= 4; n++) '/set/fixture.7z.00$n',
      ]);
      expect(await _read(opened, 'first.txt'), volumeReferenceFirstFile());
      expect(
        utf8.decode(await _read(opened, 'nested/second.txt')),
        'Second member in another volume.\n',
      );
      expect(backend.lists, 2);
      expect(capture.spools.every((spool) => spool.isSealed), isTrue);
      expect(opened.archive.notices.join(' '), contains('Read-only'));
      await opened.archive.close();
      await opened.archive.close();
      capture.expectDisposed();
      expect(backend.mutations, isEmpty);
    },
  );

  test(
    'native supported profile retains streaming and closes all private parts',
    () async {
      final backend = _Backend();
      final captured = <ArchiveOutputSpool>[];
      final opened = await openSevenZipVolumeArchive(
        backend,
        backend.selected,
        createSpool: (limit) async {
          final spool = await ArchiveOutputSpool.create(maxBytes: limit);
          captured.add(spool);
          return spool;
        },
      );
      expect(opened.archive.maxStreamingMemberBytes, kArchiveStreamingLimit);
      expect(await _read(opened, 'first.txt'), volumeReferenceFirstFile());
      await opened.archive.close();
      expect(captured.every((spool) => !spool.isSealed), isTrue);
      for (final spool in captured) {
        await expectLater(spool.openByteSource(), throwsStateError);
      }
    },
  );

  test(
    'nonstreaming opening respects its smaller buffered member limit',
    () async {
      final backend = _Backend();
      final capture = _Capture();
      await expectLater(
        openSevenZipVolumeArchive(
          backend,
          backend.selected,
          streaming: false,
          maxMemberBytes: 120,
          createSpool: capture.create,
        ),
        throwsA(
          isA<ArchiveViewException>()
              .having((error) => error.code, 'code', ArchiveMessageCode.archiveLimit)
              .having((error) => error.message, 'detail', contains('coder output')),
        ),
      );
      capture.expectDisposed();
    },
  );

  test(
    'browsing session routes real backend names before randomized spooling',
    () async {
      final backend = _Backend();
      final session = await ArchiveBrowserSession.open(
        backend,
        backend.selected,
        spoolToDisk: false,
      );
      addTearDown(session.close);
      expect(session.archive.formatName, 'volumes/7z');
      expect(session.temporaryPath, isNull);
      expect(
        session.fingerprint,
        sha256.convert(volumeReferenceSevenZip()).toString(),
      );
      expect(await session.read('first.txt'), volumeReferenceFirstFile());
      final nested = await session.backend.stat('/nested/second.txt');
      expect(nested, isNotNull);
      expect(
        await session.backend
            .readFile(nested!)
            .expand((chunk) => chunk)
            .toList(),
        utf8.encode('Second member in another volume.\n'),
      );
      expect(backend.mutations, isEmpty);
    },
  );

  test(
    'a completed snapshot stays immutable if original part bytes change',
    () async {
      final backend = _Backend();
      final opened = await openSevenZipVolumeArchive(
        backend,
        backend.selected,
        spoolToDisk: false,
      );
      addTearDown(opened.archive.close);
      for (final key in backend.data.keys.toList()) {
        backend.data[key] = Uint8List(backend.data[key]!.length);
      }
      expect(await _read(opened, 'first.txt'), volumeReferenceFirstFile());
    },
  );

  test(
    'captured backend revocation still invalidates cached member reads',
    () async {
      final backend = _Backend();
      final capture = _Capture();
      final opened = await openSevenZipVolumeArchive(
        backend,
        backend.selected,
        spoolToDisk: false,
        createSpool: capture.create,
      );
      await _read(opened, 'first.txt');
      backend.current = false;
      await expectLater(
        _read(opened, 'first.txt'),
        throwsA(isA<ArchiveViewException>()),
      );
      await opened.archive.close();
      capture.expectDisposed();
    },
  );

  group('part manifest refusals', () {
    final mutations = <String, void Function(_Backend)>{
      'gap': (backend) => backend.data.remove('/set/fixture.7z.002'),
      'padding alias': (backend) =>
          backend.data['/set/fixture.7z.01'] = Uint8List(1),
      'mixed numbering width': (backend) =>
          backend.data['/set/fixture.7z.0002'] = backend.data.remove(
            '/set/fixture.7z.002',
          )!,
      'case alias': (backend) => backend.data['/set/Fixture.7z.002'] = backend
          .data
          .remove('/set/fixture.7z.002')!,
      'duplicate listing': (backend) =>
          backend.mapListing = (files) => [...files, files.first],
      'provider object alias': (backend) {
        backend.uuids['/set/fixture.7z.001'] = 'same-id';
        backend.uuids['/set/fixture.7z.002'] = 'same-id';
      },
      'different storage account': (backend) =>
          backend.mapListing = (files) => [
            files.first.copyWith(storageId: 'different-account'),
            ...files.skip(1),
          ],
      'link': (backend) => backend.links.add('/set/fixture.7z.002'),
      'directory': (backend) => backend.folders.add('/set/fixture.7z.002'),
      'empty part': (backend) => backend.sizes['/set/fixture.7z.002'] = 0,
      'unbounded numeric alias': (backend) =>
          backend.data['/set/fixture.7z.${'0' * 200}2'] = Uint8List(1),
      'wrong parent from provider': (backend) => backend.extras.add(
        FileItem(
          name: 'fixture.7z.005',
          path: '/elsewhere/fixture.7z.005',
          isFolder: false,
          size: 1,
        ),
      ),
      'provider name mismatch': (backend) => backend.extras.add(
        FileItem(
          name: 'fixture.7z.005',
          path: '/set/other',
          isFolder: false,
          size: 1,
        ),
      ),
    };
    for (final mutation in mutations.entries) {
      test('rejects ${mutation.key} before copying data', () async {
        final backend = _Backend();
        final selected = backend.selected;
        mutation.value(backend);
        final capture = _Capture();
        await expectLater(
          openSevenZipVolumeArchive(
            backend,
            selected,
            spoolToDisk: false,
            createSpool: capture.create,
          ),
          throwsA(isA<ArchiveViewException>()),
        );
        expect(backend.reads, isEmpty);
        expect(capture.spools, isEmpty);
        expect(backend.mutations, isEmpty);
      });
    }

    test(
      'selecting a later part is refused without silently changing selection',
      () async {
        final backend = _Backend();
        await expectLater(
          openSevenZipVolumeArchive(
            backend,
            backend.item('/set/fixture.7z.002'),
            spoolToDisk: false,
          ),
          throwsA(isA<ArchiveViewException>()),
        );
        expect(backend.reads, isEmpty);
      },
    );

    test('aggregate size is checked before creating any snapshot', () async {
      final backend = _Backend();
      for (final key in backend.data.keys) {
        backend.sizes[key] = 100 * 1024 * 1024;
      }
      final capture = _Capture();
      await expectLater(
        openSevenZipVolumeArchive(
          backend,
          backend.selected,
          spoolToDisk: false,
          createSpool: capture.create,
        ),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(backend.reads, isEmpty);
      expect(capture.spools, isEmpty);
    });
  });

  group('pending provider cancellation and cleanup', () {
    for (final phase in ['list', 'stat', 'read', 'final list']) {
      for (final stop in ['cancel', 'revoke', 'change account']) {
        test(
          '$stop while $phase is pending returns and disposes owned parts',
          () async {
            final backend = _StalledBackend(phase);
            final capture = _Capture();
            var cancelled = false;
            final result = Completer<Object?>();
            unawaited(
              openSevenZipVolumeArchive(
                backend,
                backend.selected,
                spoolToDisk: false,
                isCancelled: () => cancelled,
                createSpool: capture.create,
              ).then<void>(
                (opened) async {
                  await opened.archive.close();
                  result.complete(null);
                },
                onError: (Object error, StackTrace stack) {
                  result.complete(error);
                },
              ),
            );
            try {
              await backend.entered.future.timeout(const Duration(seconds: 2));
              switch (stop) {
                case 'cancel':
                  cancelled = true;
                case 'revoke':
                  backend.current = false;
                case 'change account':
                  backend.identityValue = Object();
              }
              final error = await result.future.timeout(
                const Duration(seconds: 3),
              );
              expect(error, isA<ArchiveViewException>());
              expect(
                backend.release.isCompleted,
                isFalse,
                reason: 'provider acknowledgement must not hold owned spools',
              );
              expect(capture.spools.length, switch (phase) {
                'read' => 2,
                'final list' => 4,
                _ => 0,
              });
              capture.expectDisposed();
              expect(backend.mutations, isEmpty);
            } finally {
              if (!backend.release.isCompleted) backend.release.complete();
              await result.future;
            }
          },
        );
      }
    }

    test(
      'late provider metadata errors are observed after cancellation',
      () async {
        final backend = _StalledBackend('stat');
        var cancelled = false;
        final result = Completer<Object?>();
        unawaited(
          openSevenZipVolumeArchive(
            backend,
            backend.selected,
            spoolToDisk: false,
            isCancelled: () => cancelled,
          ).then<void>(
            (opened) async {
              await opened.archive.close();
              result.complete(null);
            },
            onError: (Object error, StackTrace stack) {
              result.complete(error);
            },
          ),
        );
        await backend.entered.future;
        cancelled = true;
        expect(
          await result.future.timeout(const Duration(seconds: 3)),
          isA<ArchiveViewException>(),
        );
        backend.release.completeError(StateError('late provider error'));
        await Future<void>.delayed(Duration.zero);
      },
    );

    test(
      'inactive remote reads expire and dispose completed and current parts',
      () async {
        final backend = _StalledBackend('read');
        final capture = _Capture();
        try {
          await expectLater(
            openSevenZipVolumeArchive(
              backend,
              backend.selected,
              spoolToDisk: false,
              createSpool: capture.create,
              sourceInactivityTimeout: const Duration(milliseconds: 30),
            ),
            throwsA(
              isA<ArchiveViewException>().having(
                (error) => error.message,
                'message',
                contains('stopped responding'),
              ),
            ),
          );
          expect(capture.spools.length, 2);
          capture.expectDisposed();
        } finally {
          if (!backend.release.isCompleted) backend.release.complete();
        }
      },
    );

    test(
      'pending spool creation remains owned until its resource is returned',
      () async {
        final backend = _Backend();
        final capture = _Capture();
        final entered = Completer<void>(), release = Completer<void>();
        var cancelled = false, completed = false;
        final opening = openSevenZipVolumeArchive(
          backend,
          backend.selected,
          spoolToDisk: false,
          isCancelled: () => cancelled,
          createSpool: (limit) async {
            entered.complete();
            await release.future;
            return capture.create(limit);
          },
        );
        final result = expectLater(
          opening.whenComplete(() => completed = true),
          throwsA(isA<ArchiveViewException>()),
        );
        await entered.future;
        cancelled = true;
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(completed, isFalse);
        release.complete();
        await result;
        expect(capture.spools, hasLength(1));
        capture.expectDisposed();
      },
    );
  });

  group('capture validation and cleanup', () {
    final changes = <String, void Function(_Backend, String)>{
      'mutable revision': (backend, path) =>
          backend.metadata[path]!['revision'] = 'changed',
      'first part changes while reading a later part': (backend, path) {
        if (path.endsWith('.002')) {
          backend.metadata['/set/fixture.7z.001']!['revision'] = 'changed';
        }
      },
      'part removed': (backend, path) => backend.data.remove(path),
      'extra numeric sibling': (backend, path) =>
          backend.data['/set/fixture.7z.005'] = Uint8List(1),
      'backend revoked': (backend, path) => backend.current = false,
      'account identity replaced': (backend, path) =>
          backend.identityValue = Object(),
    };
    for (final change in changes.entries) {
      test('${change.key} aborts and disposes all snapshots', () async {
        final backend = _Backend()..mutableIdentity = true;
        backend.afterChunk = (path) => change.value(backend, path);
        final capture = _Capture();
        await expectLater(
          openSevenZipVolumeArchive(
            backend,
            backend.selected,
            spoolToDisk: false,
            createSpool: capture.create,
          ),
          throwsA(isA<ArchiveViewException>()),
        );
        capture.expectDisposed();
        expect(backend.mutations, isEmpty);
      });
    }

    test('missing final volume fails exact 7z extent after capture', () async {
      final backend = _Backend()..data.remove('/set/fixture.7z.004');
      final capture = _Capture();
      await expectLater(
        openSevenZipVolumeArchive(
          backend,
          backend.selected,
          spoolToDisk: false,
          createSpool: capture.create,
        ),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(backend.reads.length, 3);
      capture.expectDisposed();
    });

    test(
      'short/long provider streams and late errors never publish a listing',
      () async {
        for (final mode in ['short', 'long', 'late']) {
          final backend = _Backend();
          if (mode == 'short') backend.sizes['/set/fixture.7z.001'] = 98;
          if (mode == 'long') backend.sizes['/set/fixture.7z.001'] = 96;
          if (mode == 'late') backend.lateError = true;
          final capture = _Capture();
          await expectLater(
            openSevenZipVolumeArchive(
              backend,
              backend.selected,
              spoolToDisk: false,
              createSpool: capture.create,
            ),
            throwsA(anyOf(isA<ArchiveViewException>(), isA<StateError>())),
          );
          capture.expectDisposed();
        }
      },
    );

    test(
      'cancellation during capture closes the current and earlier snapshots',
      () async {
        final backend = _Backend();
        var cancelled = false;
        backend.afterChunk = (path) {
          if (path.endsWith('.002')) cancelled = true;
        };
        final capture = _Capture();
        await expectLater(
          openSevenZipVolumeArchive(
            backend,
            backend.selected,
            spoolToDisk: false,
            isCancelled: () => cancelled,
            createSpool: capture.create,
          ),
          throwsA(isA<ArchiveViewException>()),
        );
        expect(capture.spools.length, 2);
        capture.expectDisposed();
      },
    );

    test(
      'revocation during asynchronous spool creation disposes its result',
      () async {
        final backend = _Backend();
        final capture = _Capture()..afterCreate = () => backend.current = false;
        await expectLater(
          openSevenZipVolumeArchive(
            backend,
            backend.selected,
            spoolToDisk: false,
            createSpool: capture.create,
          ),
          throwsA(isA<ArchiveViewException>()),
        );
        expect(capture.spools.length, 1);
        capture.expectDisposed();
      },
    );

    test(
      'write failure and cleanup failure preserve the original error',
      () async {
        final backend = _Backend();
        final capture = _Capture()
          ..failWrite = true
          ..failDispose = true;
        await expectLater(
          openSevenZipVolumeArchive(
            backend,
            backend.selected,
            spoolToDisk: false,
            createSpool: capture.create,
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Snapshot write failed.',
            ),
          ),
        );
        capture.expectDisposed();
      },
    );
  });

  test(
    'header-encrypted volumes prompt and reopen from a fresh capture',
    () async {
      final bytes = File('test/fixtures/archives/header_encrypted.7z')
          .readAsBytesSync();
      final backend = _Backend(bytes: bytes);
      final firstCapture = _Capture();
      await expectLater(
        openSevenZipVolumeArchive(
          backend,
          backend.selected,
          createSpool: firstCapture.create,
        ),
        throwsA(isA<ArchivePasswordRequiredException>()),
      );
      firstCapture.expectDisposed();
      final secondCapture = _Capture();
      final opened = await openSevenZipVolumeArchive(
        backend,
        backend.selected,
        password: 'secret',
        createSpool: secondCapture.create,
      );
      expect(opened.archive.members, isNotEmpty);
      final first = opened.archive.members.firstWhere(
        (member) => member.isFile,
      );
      expect((await opened.archive.readMember(first)).length, first.size);
      await opened.archive.close();
      secondCapture.expectDisposed();
    },
  );
}
