import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/archive_endpoint.dart';
import 'package:crisp_cloud/services/archive_publication_journal.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/archive_workspace.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'support/archive_endpoint_backend.dart';

final _modified = DateTime.utc(2025, 2, 3, 4, 5, 6);

Future<Uint8List> _archive(
  koni.ArchiveWriteFormat format,
  Map<String, List<int>> files, {
  String? password,
  bool names = false,
  Map<String, int> directories = const {},
  int mode = 0x1ed,
}) async {
  final sink = koni.BytesBuilderSink();
  final writer = koni.Archive.create(
    sink,
    format: format,
    options: koni.ArchiveWriteOptions(password: password, encryptHeader: names),
  );
  for (final directory in directories.entries) {
    await writer.addEntry(
      koni.ArchiveEntrySpec(
        path: directory.key,
        type: koni.ArchiveEntryType.directory,
        posixMode: directory.value,
        modified: _modified,
      ),
    );
  }
  for (final file in files.entries) {
    await writer.addBytes(
      koni.ArchiveEntrySpec(
        path: file.key,
        posixMode: mode,
        modified: _modified,
      ),
      Uint8List.fromList(file.value),
    );
  }
  await writer.close();
  await sink.close();
  return sink.takeBytes();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ArchiveEndpointTestBackend backend;
  late ArchivePublicationJournal journal;

  setUp(() {
    backend = ArchiveEndpointTestBackend();
    journal = ArchivePublicationJournal(storage: MemoryFileCollectionStorage());
  });

  Future<ArchiveWorkspace> open(
    String path, {
    ArchiveEndpointTestBackend? storage,
    List<String> nested = const [],
    List<String?>? passwords,
  }) async {
    final input = storage ?? backend;
    final workspace = await ArchiveWorkspace.openNested(
      input,
      (await input.stat(path))!,
      nested,
      passwords: passwords,
      journal: journal,
    );
    addTearDown(workspace.close);
    return workspace;
  }

  Future<({ArchiveWorkspace source, ArchiveEndpoint destination})> pair({
    bool reverse = false,
  }) async {
    final sourceName = reverse ? 'source.zip' : 'source.tar';
    final destinationName = reverse ? 'destination.tar' : 'destination.zip';
    backend.put(
      '/input/$sourceName',
      await _archive(
        reverse ? const koni.ZipWriteFormat() : const koni.TarWriteFormat(),
        {
          'folder/run': [1, 2, 3],
          'implicit/deep/data': [4, 5],
        },
        directories: {'folder': 0x1e8, 'empty': 0x1c0},
      ),
    );
    backend.put(
      '/out/$destinationName',
      await _archive(
        reverse ? const koni.TarWriteFormat() : const koni.ZipWriteFormat(),
        {
          'keep': [9],
        },
      ),
    );
    final source = await open('/input/$sourceName');
    final destination = ArchiveEndpoint.fromWorkspace(
      await open('/out/$destinationName'),
    );
    addTearDown(destination.close);
    return (source: source, destination: destination);
  }

  Future<ArchiveWorkspaceReview> stage(
    ArchiveWorkspace source,
    ArchiveEndpoint destination, {
    FileConflictPolicy conflict = FileConflictPolicy.keepBoth,
    String directory = '/',
    List<FileItem>? files,
  }) async {
    final plan = await destination.prepareArchiveCopy(
      source: source,
      files: files ?? source.list(),
      directory: directory,
      conflict: conflict,
    );
    expect(plan.errors, isEmpty);
    expect(plan.moveSources, isFalse);
    expect(plan.canStage, isTrue);
    return destination.stageImport(plan, control: FileOperationControl());
  }

  for (final reverse in [false, true]) {
    test(
      '${reverse ? 'ZIP to TAR' : 'TAR to ZIP'} copies a verified tree, empty directories, modes and times',
      () async {
        final (:source, :destination) = await pair(reverse: reverse);
        final sourceBytes = backend.files[source.file.path!]!;
        final original = backend.files[destination.workspace.file.path!]!;
        final review = await stage(source, destination);
        expect(backend.mutations, isEmpty);
        expect(backend.files[destination.workspace.file.path!], original);
        final result = await destination.commit(reviewed: review);
        expect(result.publishedFiles, 2);
        expect(result.removedSources, 0);
        expect(result.retainedSources, isEmpty);
        expect(result.receipt.file.path, destination.workspace.file.path);
        expect(backend.files[source.file.path!], sourceBytes);
        expect(source.dirty, isFalse);

        final reopened = await open(destination.workspace.file.path!);
        expect(await reopened.read('/folder/run'), [1, 2, 3]);
        expect(await reopened.read('/implicit/deep/data'), [4, 5]);
        expect(await reopened.read('/keep'), [9]);
        final empty = (await reopened.backend.stat('/empty'))!;
        expect(empty.isFolder, isTrue);
        expect(empty.updatedAt?.toUtc(), _modified);
        expect(
          (await reopened.backend.readMetadata('/empty')).mode! & 0xfff,
          0x1c0,
        );
        expect(
          (await reopened.backend.readMetadata('/folder')).mode! & 0xfff,
          0x1e8,
        );
        expect(
          (await reopened.backend.readMetadata('/folder/run')).mode! & 0xfff,
          0x1ed,
        );
        expect(
          (await reopened.backend.stat('/folder/run'))!.updatedAt?.toUtc(),
          _modified,
        );
      },
    );
  }

  for (final conflict in [
    FileConflictPolicy.keepBoth,
    FileConflictPolicy.replace,
    FileConflictPolicy.skip,
  ]) {
    test('copy obeys explicit ${conflict.name} collision handling', () async {
      backend.put(
        '/input/source.zip',
        await _archive(const koni.ZipWriteFormat(), {
          'same': [1],
          'new': [2],
        }),
      );
      backend.put(
        '/out/destination.tar',
        await _archive(const koni.TarWriteFormat(), {
          'same': [9],
        }),
      );
      final source = await open('/input/source.zip');
      final destination = ArchiveEndpoint.fromWorkspace(
        await open('/out/destination.tar'),
      );
      addTearDown(destination.close);
      final review = await stage(source, destination, conflict: conflict);
      await destination.commit(reviewed: review);
      final reopened = await open('/out/destination.tar');
      expect(
        await reopened.read('/same'),
        conflict == FileConflictPolicy.replace ? [1] : [9],
      );
      expect(await reopened.read('/new'), [2]);
      expect(
        reopened.list().length,
        conflict == FileConflictPolicy.keepBoth ? 3 : 2,
      );
    });
  }

  test(
    'copy retains independent original passwords and destination protection',
    () async {
      final sourceBytes = await _archive(
        const koni.SevenZWriteFormat(),
        {
          'secret': [1, 2],
        },
        password: 'source-secret',
        names: true,
      );
      backend.put('/input/source.7z', sourceBytes);
      backend.put(
        '/out/destination.zip',
        await _archive(const koni.ZipWriteFormat(), {
          'keep': [3],
        }, password: 'destination-secret'),
      );
      final source = await open(
        '/input/source.7z',
        passwords: ['source-secret'],
      );
      final destination = ArchiveEndpoint.fromWorkspace(
        await open('/out/destination.zip', passwords: ['destination-secret']),
      );
      addTearDown(destination.close);
      final review = await stage(source, destination);
      await destination.commit(reviewed: review);
      expect(backend.files['/input/source.7z'], sourceBytes);
      final reopened = await open(
        '/out/destination.zip',
        passwords: ['destination-secret'],
      );
      expect(reopened.encrypted, isTrue);
      expect(await reopened.read('/secret'), [1, 2]);
      await expectLater(
        open('/out/destination.zip', passwords: ['source-secret']),
        throwsA(isA<ArchivePasswordRequiredException>()),
      );
    },
  );

  test(
    'independent nested routes publish only the destination outer container',
    () async {
      backend.put(
        '/input/source.zip',
        await _archive(const koni.ZipWriteFormat(), {
          'nested/source.tar': await _archive(const koni.TarWriteFormat(), {
            'inside': [1, 2],
          }),
        }),
      );
      backend.put(
        '/out/destination.zip',
        await _archive(const koni.ZipWriteFormat(), {
          'nested/destination.zip': await _archive(
            const koni.ZipWriteFormat(),
            {
              'keep': [9],
            },
          ),
          'outer-keep': [8],
        }),
      );
      final source = await open(
        '/input/source.zip',
        nested: ['nested/source.tar'],
      );
      expect(source.nestedMemberPaths, ['nested/source.tar']);
      expect(source.outermost.nestedMemberPaths, isEmpty);
      final destination = ArchiveEndpoint.fromWorkspace(
        await open('/out/destination.zip', nested: ['nested/destination.zip']),
      );
      addTearDown(destination.close);
      final sourceBytes = backend.files['/input/source.zip'];
      final review = await stage(source, destination);
      final result = await destination.commit(reviewed: review);
      expect(result.receipt.file.path, '/out/destination.zip');
      expect(backend.files['/input/source.zip'], sourceBytes);
      expect(
        await (await open(
          '/out/destination.zip',
          nested: ['nested/destination.zip'],
        )).read('/inside'),
        [1, 2],
      );
      expect(await (await open('/out/destination.zip')).read('/outer-keep'), [
        8,
      ]);
    },
  );

  test(
    'same outer container is refused across independent and nested workspaces',
    () async {
      backend.put(
        '/out/both.zip',
        await _archive(const koni.ZipWriteFormat(), {
          'a.zip': await _archive(const koni.ZipWriteFormat(), {
            'first': [1],
          }),
          'b.zip': await _archive(const koni.ZipWriteFormat(), {
            'second': [2],
          }),
        }),
      );
      final source = await open('/out/both.zip', nested: ['a.zip']);
      final destination = ArchiveEndpoint.fromWorkspace(
        await open('/out/both.zip', nested: ['b.zip']),
      );
      addTearDown(destination.close);
      await expectLater(
        destination.prepareArchiveCopy(source: source, files: source.list()),
        throwsUnsupportedError,
      );
      await expectLater(
        destination.prepareArchiveCopy(
          source: destination.workspace,
          files: destination.workspace.list(),
        ),
        throwsUnsupportedError,
      );
      final outer = await open('/out/both.zip');
      await expectLater(
        destination.prepareArchiveCopy(source: outer, files: outer.list()),
        throwsUnsupportedError,
      );
      expect(backend.mutations, isEmpty);
    },
  );

  test(
    'native hard-link aliases are rejected as the same physical container',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'crisp-archive-copy-alias-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final sourceFile = File('${directory.path}/source.zip');
      final aliasFile = File('${directory.path}/alias.zip');
      final bytes = await _archive(const koni.ZipWriteFormat(), {
        'member': [1, 2],
      });
      await sourceFile.writeAsBytes(bytes, flush: true);
      final link = await Process.run('ln', [sourceFile.path, aliasFile.path]);
      expect(link.exitCode, 0, reason: '${link.stderr}');
      expect(
        await FileSystemEntity.identical(sourceFile.path, aliasFile.path),
        isTrue,
      );
      final local = LocalOperationBackend(
        LocalFileService(),
        isCurrent: () => true,
      );
      final source = await ArchiveWorkspace.open(
        local,
        (await local.stat(sourceFile.path))!,
      );
      addTearDown(source.close);
      final destination = await ArchiveEndpoint.open(
        containerBackend: local,
        containerFile: (await local.stat(aliasFile.path))!,
        journal: journal,
      );
      addTearDown(destination.close);
      await expectLater(
        destination.prepareArchiveCopy(source: source, files: source.list()),
        throwsUnsupportedError,
      );
      expect(await sourceFile.readAsBytes(), bytes);
      expect(await aliasFile.readAsBytes(), bytes);
      expect(journal.records, isEmpty);
    },
    skip: !Platform.isLinux && !Platform.isMacOS,
  );

  test(
    'generic copy and move cannot bypass the archive-source boundary',
    () async {
      final (:source, :destination) = await pair();
      for (final move in [false, true]) {
        await expectLater(
          destination.prepareImport(
            source: source.backend,
            files: source.list(),
            moveSources: move,
          ),
          throwsUnsupportedError,
        );
      }
      expect(backend.mutations, isEmpty);
    },
  );

  test(
    'read-only source storage can copy into a writable destination',
    () async {
      final (:source, :destination) = await pair();
      final input = ArchiveEndpointTestBackend()
        ..account = 'read-only-source'
        ..publicationSupported = false
        ..put('/input/read-only.tar', backend.files[source.file.path!]!);
      final readOnly = await open('/input/read-only.tar', storage: input);
      expect(readOnly.canUpdate, isFalse);
      final review = await stage(readOnly, destination);
      await destination.commit(reviewed: review);
      expect(await destination.workspace.read('/folder/run'), [1, 2, 3]);
      expect(input.mutations, isEmpty);
    },
  );

  test(
    'dirty source and source draft changes after planning are refused',
    () async {
      final (:source, :destination) = await pair();
      source.replace('/later', Uint8List.fromList([4]));
      await expectLater(
        destination.prepareArchiveCopy(source: source, files: source.list()),
        throwsStateError,
      );
      source.discardDraft();
      final plan = await destination.prepareArchiveCopy(
        source: source,
        files: source.list(),
      );
      source.replace('/later', Uint8List.fromList([5]));
      await expectLater(
        destination.stageImport(plan, control: FileOperationControl()),
        throwsStateError,
      );
      expect(destination.workspace.dirty, isFalse);
      expect(backend.mutations, isEmpty);
    },
  );

  for (final preserveVersion in [false, true]) {
    test(
      'source ${preserveVersion ? 'bytes with unchanged metadata' : 'version'} changed before staging is refused',
      () async {
        final (:source, :destination) = await pair();
        final plan = await destination.prepareArchiveCopy(
          source: source,
          files: source.list(),
        );
        final changed = Uint8List.fromList(backend.files[source.file.path!]!)
          ..[0] ^= 1;
        backend.put(
          source.file.path!,
          changed,
          preserveVersion: preserveVersion,
        );
        await expectLater(
          destination.stageImport(plan, control: FileOperationControl()),
          throwsStateError,
        );
        expect(destination.workspace.dirty, isFalse);
        expect(backend.mutations, isEmpty);
      },
    );
  }

  test('source modified after review prevents publication and restores destination', () async {
    final (:source, :destination) = await pair();
    final original = backend.files[destination.workspace.file.path!]!;
    final review = await stage(source, destination);
    final changed = Uint8List.fromList(backend.files[source.file.path!]!)
      ..[0] ^= 1;
    backend.put(source.file.path!, changed, preserveVersion: true);
    await expectLater(
      destination.commit(reviewed: review),
      throwsA(isA<ArchivePublicationException>()),
    );
    expect(backend.files[destination.workspace.file.path!], original);
    expect(backend.files[source.file.path!], changed);
    expect(destination.workspace.pendingPublication, isNotNull);
    expect(
      backend.mutations.where((value) => value.contains('/input/')),
      isEmpty,
    );
  });

  test('source change during destination staging is checked immediately before installation', () async {
    final (:source, :destination) = await pair();
    final original = backend.files[destination.workspace.file.path!]!;
    final sourceOriginal = backend.files[source.file.path!]!;
    final review = await stage(source, destination);
    var changed = false;
    backend.after = (action, path, target) {
      if (!changed && action == 'write' && path.contains('.crisp-archive-')) {
        changed = true;
        backend.put(
          source.file.path!,
          Uint8List.fromList(sourceOriginal)..[0] ^= 1,
          preserveVersion: true,
        );
      }
    };
    await expectLater(
      destination.commit(reviewed: review),
      throwsA(isA<ArchivePublicationException>()),
    );
    expect(changed, isTrue);
    expect(backend.files[destination.workspace.file.path!], original);
    expect(
      backend.mutations.where((value) => value.contains('/input/')),
      isEmpty,
    );
  });

  test(
    'changed source draft invalidates review before any physical writes',
    () async {
      final (:source, :destination) = await pair();
      final review = await stage(source, destination);
      source.replace('/draft', Uint8List.fromList([7]));
      await expectLater(destination.review(), throwsStateError);
      await expectLater(destination.commit(reviewed: review), throwsStateError);
      expect(backend.mutations, isEmpty);
    },
  );

  test(
    'source authority changes after review prevent physical publication',
    () async {
      final (:source, :destination) = await pair();
      final review = await stage(source, destination);
      backend.account = 'different-account';
      await expectLater(destination.commit(reviewed: review), throwsStateError);
      expect(backend.mutations, isEmpty);
    },
  );

  test('source closes after review without publishing a snapshot under expired authority', () async {
    final (:source, :destination) = await pair();
    final review = await stage(source, destination);
    await source.close();
    await expectLater(destination.commit(reviewed: review), throwsStateError);
    expect(backend.mutations, isEmpty);
  });

  test('cancelled staging adopts no source members', () async {
    final (:source, :destination) = await pair();
    final plan = await destination.prepareArchiveCopy(
      source: source,
      files: source.list(),
    );
    final control = FileOperationControl()..cancel();
    await expectLater(
      destination.stageImport(plan, control: control),
      throwsA(isA<FileOperationCancelled>()),
    );
    expect(destination.workspace.dirty, isFalse);
    expect(backend.mutations, isEmpty);
  });

  test(
    'source read failures leave the original destination and draft untouched',
    () async {
      final (:source, :destination) = await pair();
      final plan = await destination.prepareArchiveCopy(
        source: source,
        files: source.list(),
      );
      backend.before = (action, path, target) {
        if (action == 'read' && path == source.file.path) {
          throw StateError('Read failed.');
        }
      };
      await expectLater(
        destination.stageImport(plan, control: FileOperationControl()),
        throwsStateError,
      );
      expect(destination.workspace.dirty, isFalse);
      expect(backend.mutations, isEmpty);
    },
  );

  test(
    'source special permission bits cannot silently lose ownership semantics',
    () async {
      backend.put(
        '/input/privileged.tar',
        await _archive(const koni.TarWriteFormat(), {
          'privileged': [1],
        }, mode: 0x9ed),
      );
      backend.put(
        '/out/destination.zip',
        await _archive(const koni.ZipWriteFormat(), {
          'keep': [9],
        }),
      );
      final source = await open('/input/privileged.tar');
      final destination = ArchiveEndpoint.fromWorkspace(
        await open('/out/destination.zip'),
      );
      addTearDown(destination.close);
      final plan = await destination.prepareArchiveCopy(
        source: source,
        files: source.list(),
      );
      await expectLater(
        destination.stageImport(plan, control: FileOperationControl()),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(destination.workspace.dirty, isFalse);
      expect(backend.mutations, isEmpty);
    },
  );

  test(
    'failed destination publication never writes or removes the source',
    () async {
      final (:source, :destination) = await pair();
      final sourceOriginal = backend.files[source.file.path!]!;
      final destinationOriginal =
          backend.files[destination.workspace.file.path!]!;
      final review = await stage(source, destination);
      backend.before = (action, path, target) {
        if (action == 'write') throw StateError('Disk full.');
      };
      await expectLater(
        destination.commit(reviewed: review),
        throwsA(isA<ArchivePublicationException>()),
      );
      expect(backend.files[source.file.path!], sourceOriginal);
      expect(
        backend.files[destination.workspace.file.path!],
        destinationOriginal,
      );
      expect(
        backend.mutations.where((value) => value.contains('/input/')),
        isEmpty,
      );
    },
  );

  test('corrupt source member refuses the complete private import', () async {
    final (:source, :destination) = await pair();
    final damaged = await _archive(const koni.ZipWriteFormat(), {
      'damaged': [1, 2, 3, 4],
    });
    final header = ByteData.sublistView(damaged);
    final central = header.getUint32(damaged.length - 6, Endian.little);
    final local = header.getUint32(central + 42, Endian.little);
    final payload =
        local +
        30 +
        header.getUint16(local + 26, Endian.little) +
        header.getUint16(local + 28, Endian.little);
    damaged[payload] ^= 1;
    backend.put('/input/damaged.zip', damaged);
    final corrupt = await open('/input/damaged.zip');
    final plan = await destination.prepareArchiveCopy(
      source: corrupt,
      files: corrupt.list(),
    );
    await expectLater(
      destination.stageImport(plan, control: FileOperationControl()),
      throwsA(anything),
    );
    expect(destination.workspace.dirty, isFalse);
    expect(backend.files[source.file.path!], isNotNull);
    expect(backend.mutations, isEmpty);
  });

  test('oversized source members refuse planning before decoding', () async {
    final (:source, :destination) = await pair();
    final oversized = await _archive(const koni.ZipWriteFormat(), {
      'large': [1],
    });
    final header = ByteData.sublistView(oversized);
    final central = header.getUint32(oversized.length - 6, Endian.little);
    final local = header.getUint32(central + 42, Endian.little);
    header.setUint32(central + 24, kArchiveReadLimit + 1, Endian.little);
    header.setUint32(local + 22, kArchiveReadLimit + 1, Endian.little);
    backend.put('/input/large.zip', oversized);
    final large = await open('/input/large.zip');
    final plan = await destination.prepareArchiveCopy(
      source: large,
      files: large.list(),
    );
    expect(plan.canStage, isFalse);
    expect(plan.errors.join(' '), contains('64 MiB'));
    expect(backend.files[source.file.path!], isNotNull);
    expect(backend.mutations, isEmpty);
  });

  test(
    'late cancellation restores the original destination and retains source',
    () async {
      final (:source, :destination) = await pair();
      final original = backend.files[destination.workspace.file.path!]!;
      final sourceOriginal = backend.files[source.file.path!]!;
      final review = await stage(source, destination);
      var cancelled = false;
      backend.after = (action, path, target) {
        if (action == 'read' && path == source.file.path) cancelled = true;
      };
      await expectLater(
        destination.commit(reviewed: review, isCancelled: () => cancelled),
        throwsA(isA<ArchivePublicationException>()),
      );
      expect(cancelled, isTrue);
      expect(backend.files[destination.workspace.file.path!], original);
      expect(backend.files[source.file.path!], sourceOriginal);
    },
  );

  test(
    'stalled physical source verification cancels its read subscription',
    () async {
      final (:source, :destination) = await pair();
      final input = _StallingArchiveBackend()
        ..account = 'stalled-source'
        ..put('/input/stalled.tar', backend.files[source.file.path!]!);
      final stalled = await open('/input/stalled.tar', storage: input);
      final bounded = ArchiveEndpoint.fromWorkspace(
        destination.workspace,
        readInactivity: const Duration(milliseconds: 30),
      );
      addTearDown(bounded.close);
      final plan = await bounded.prepareArchiveCopy(
        source: stalled,
        files: stalled.list(),
      );
      input.stall = true;
      await expectLater(
        bounded.stageImport(plan, control: FileOperationControl()),
        throwsA(isA<TimeoutException>()),
      );
      expect(input.cancelled, isTrue);
      expect(destination.workspace.dirty, isFalse);
      expect(backend.mutations, isEmpty);
    },
  );

  test(
    'nested destination retains source guard through the outer publication',
    () async {
      final (:source, :destination) = await pair();
      backend.put(
        '/out/nested.zip',
        await _archive(const koni.ZipWriteFormat(), {
          'destination.zip': backend.files[destination.workspace.file.path!]!,
        }),
      );
      final nested = ArchiveEndpoint.fromWorkspace(
        await open('/out/nested.zip', nested: ['destination.zip']),
      );
      addTearDown(nested.close);
      final original = backend.files['/out/nested.zip'];
      final review = await stage(source, nested);
      var changed = false;
      backend.after = (action, path, target) {
        if (!changed && action == 'write' && path.contains('.crisp-archive-')) {
          changed = true;
          backend.put(
            source.file.path!,
            Uint8List.fromList(backend.files[source.file.path!]!)..[0] ^= 1,
            preserveVersion: true,
          );
        }
      };
      await expectLater(
        nested.commit(reviewed: review),
        throwsA(isA<ArchivePublicationException>()),
      );
      expect(changed, isTrue);
      expect(backend.files['/out/nested.zip'], original);
      expect(nested.workspace.pendingPublication, isNotNull);
      expect(
        backend.mutations.where((value) => value.contains('/input/')),
        isEmpty,
      );
    },
  );

  test(
    'source verification cannot bypass final destination candidate checks',
    () async {
      final (:source, :destination) = await pair();
      final original = backend.files[destination.workspace.file.path!]!;
      final review = await stage(source, destination);
      var changed = false;
      backend.after = (action, path, target) {
        if (action == 'read' && path == source.file.path) {
          final candidate = backend.files.keys.singleWhere(
            (path) => path.endsWith('.candidate'),
          );
          backend.put(
            candidate,
            Uint8List.fromList(backend.files[candidate]!)..[0] ^= 1,
            preserveVersion: true,
          );
          changed = true;
        }
      };
      await expectLater(
        destination.commit(reviewed: review),
        throwsA(isA<ArchivePublicationException>()),
      );
      expect(changed, isTrue);
      expect(backend.files[destination.workspace.file.path!], original);
      expect(
        backend.mutations.where(
          (value) =>
              value.contains('.candidate:${destination.workspace.file.path}'),
        ),
        isEmpty,
      );
    },
  );
}

class _StallingArchiveBackend extends ArchiveEndpointTestBackend {
  bool stall = false;
  bool cancelled = false;
  @override
  Stream<List<int>> readFile(FileItem file) {
    if (!stall) return super.readFile(file);
    return StreamController<List<int>>(onCancel: () => cancelled = true).stream;
  }
}
