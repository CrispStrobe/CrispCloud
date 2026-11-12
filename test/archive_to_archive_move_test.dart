import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' as codec;
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/archive_container_publisher.dart';
import 'package:crisp_cloud/services/archive_endpoint.dart';
import 'package:crisp_cloud/services/archive_publication_journal.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/archive_workspace.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/installation_identity.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/archive_endpoint_backend.dart';

class _NativeMoveBackend extends LocalOperationBackend {
  _NativeMoveBackend(bool Function() current)
    : super(LocalFileService(), isCurrent: current);

  FutureOr<void> Function(FileItem file, String destination)? beforeMove;
  FutureOr<void> Function(FileItem file, String destination)? afterMove;
  final moves = <String>[];

  @override
  Future<bool> moveNoReplace(FileItem file, String destination) async {
    await beforeMove?.call(file, destination);
    final moved = await super.moveNoReplace(file, destination);
    if (moved) moves.add('${file.path}:$destination');
    await afterMove?.call(file, destination);
    return moved;
  }
}

Future<Uint8List> _archive(
  koni.ArchiveWriteFormat format,
  Map<String, List<int>> files, {
  Map<String, int> directories = const {},
  String? password,
  bool names = false,
}) async {
  final sink = koni.BytesBuilderSink();
  final writer = koni.Archive.create(
    sink,
    format: format,
    options: koni.ArchiveWriteOptions(password: password, encryptHeader: names),
  );
  final modified = DateTime.utc(2025, 2, 3, 4, 5, 6);
  for (final directory in directories.entries) {
    await writer.addEntry(
      koni.ArchiveEntrySpec(
        path: directory.key,
        type: koni.ArchiveEntryType.directory,
        posixMode: directory.value,
        modified: modified,
      ),
    );
  }
  for (final file in files.entries) {
    await writer.addBytes(
      koni.ArchiveEntrySpec(
        path: file.key,
        posixMode: 0x1a0,
        modified: modified,
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
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await InstallationIdentityService.instance.initialize();
  });

  late Directory directory;
  late _NativeMoveBackend backend;
  late ArchivePublicationJournal journal;
  late bool current;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('crisp-archive-move-');
    current = true;
    backend = _NativeMoveBackend(() => current);
    journal = ArchivePublicationJournal(storage: MemoryFileCollectionStorage());
    await Directory('${directory.path}/source').create();
    await Directory('${directory.path}/destination').create();
  });
  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Future<ArchiveWorkspace> source(
    Uint8List bytes, {
    String name = 'input.zip',
    String? password,
    List<String> nested = const [],
  }) async {
    final file = File('${directory.path}/source/$name');
    await file.writeAsBytes(bytes, flush: true);
    final workspace = await ArchiveWorkspace.openNested(
      backend,
      (await backend.stat(file.path))!,
      nested,
      passwords: [password],
      journal: journal,
    );
    addTearDown(workspace.close);
    return workspace;
  }

  Future<ArchiveEndpoint> destination(
    Uint8List bytes, {
    String name = 'output.zip',
    String? password,
    List<String> nested = const [],
  }) async {
    final file = File('${directory.path}/destination/$name');
    await file.writeAsBytes(bytes, flush: true);
    final endpoint = await ArchiveEndpoint.open(
      containerBackend: backend,
      containerFile: (await backend.stat(file.path))!,
      nestedMembers: nested,
      passwords: [password],
      journal: journal,
    );
    addTearDown(endpoint.close);
    return endpoint;
  }

  Future<({ArchiveWorkspace source, ArchiveEndpoint destination})>
  pair() async => (
    source: await source(
      await _archive(
        const koni.ZipWriteFormat(),
        {
          'chosen/a.txt': [1, 2, 3],
          'chosen/b.txt': [4, 5],
          'keep.txt': [9],
        },
        directories: {'chosen/empty': 0x1c0},
      ),
    ),
    destination: await destination(
      await _archive(const koni.TarWriteFormat(), {
        'destination-keep.txt': [8],
      }),
      name: 'output.tar',
    ),
  );

  Future<ArchiveEndpointMoveReview> prepare(
    ArchiveWorkspace source,
    ArchiveEndpoint destination, {
    List<FileItem>? files,
    FileConflictPolicy conflict = FileConflictPolicy.keepBoth,
  }) async {
    final plan = await destination.prepareArchiveMove(
      source: source,
      files:
          files ??
          source.list().where((file) => file.name == 'chosen').toList(),
      conflict: conflict,
    );
    expect(plan.isArchiveMove, isTrue);
    expect(plan.moveSources, isFalse);
    expect(plan.errors, isEmpty);
    return destination.stageArchiveMove(plan, control: FileOperationControl());
  }

  Future<ViewerArchive> read(String path, {String? password}) async {
    final reader = await openViewerArchive(
      await File(path).readAsBytes(),
      name: backend.paths.basename(path),
      password: password,
    );
    addTearDown(reader.close);
    return reader;
  }

  Future<Uint8List> member(ViewerArchive reader, String name) =>
      reader.readMember(
        reader.members.firstWhere(
          (member) => member.name.replaceAll(RegExp(r'/+$'), '') == name,
        ),
      );

  test(
    'reviews two candidates, then publishes destination before source removal',
    () async {
      final (:source, :destination) = await pair();
      final sourcePath = source.file.path!;
      final destinationPath = destination.workspace.file.path!;
      final oldSource = await File(sourcePath).readAsBytes();
      final oldDestination = await File(destinationPath).readAsBytes();
      final sourceRevision = source.revision;
      final review = await prepare(source, destination);
      expect(source.dirty, isFalse);
      expect(source.revision, sourceRevision);
      expect(review.sourceReview.workspace, isNot(same(source)));
      expect(
        review.sourceReview.changes.every(
          (change) => change.kind == ArchiveWorkspaceChangeKind.remove,
        ),
        isTrue,
      );
      expect(
        review.removedSourcePaths,
        containsAll([
          '/chosen/a.txt',
          '/chosen/b.txt',
          '/chosen/empty',
          '/chosen',
        ]),
      );
      expect(await File(sourcePath).readAsBytes(), oldSource);
      expect(await File(destinationPath).readAsBytes(), oldDestination);
      expect(backend.moves, isEmpty);
      final phases = <ArchiveMovePhase>[];
      final result = await destination.commitArchiveMove(
        reviewed: review,
        onPhase: phases.add,
      );
      expect(result.disposition, ArchiveMoveDisposition.moved);
      expect(result.sourceReceipt, isNotNull);
      expect(result.sourceRecovery, isNull);
      expect(result.publishedFiles, 2);
      expect(result.removedSources, 2);
      expect(result.retainedSources, isEmpty);
      expect(phases, [
        ArchiveMovePhase.destinationPublication,
        ArchiveMovePhase.sourcePublication,
      ]);
      final destinationInstall = backend.moves.indexWhere(
        (move) => move.endsWith(':$destinationPath'),
      );
      final sourceBackup = backend.moves.indexWhere(
        (move) => move.startsWith('$sourcePath:'),
      );
      expect(destinationInstall, greaterThanOrEqualTo(0));
      expect(sourceBackup, greaterThan(destinationInstall));
      final sourceReader = await read(sourcePath);
      expect(sourceReader.members.map((member) => member.name), ['keep.txt']);
      expect(await member(sourceReader, 'keep.txt'), [9]);
      final destinationReader = await read(destinationPath);
      expect(await member(destinationReader, 'chosen/a.txt'), [1, 2, 3]);
      expect(await member(destinationReader, 'chosen/b.txt'), [4, 5]);
      expect(await member(destinationReader, 'destination-keep.txt'), [8]);
      final empty = destinationReader.members.firstWhere(
        (member) =>
            member.name.replaceAll(RegExp(r'/+$'), '') == 'chosen/empty',
      );
      expect(empty.isFile, isFalse);
      expect(empty.posixMode! & 0xfff, 0x1c0);
      final dependency = result.sourceReceipt!.record.dependency!;
      expect(dependency.receiptId, result.receipt.record.id);
      expect(dependency.sha256, result.receipt.sha256);
      expect(result.sourceReceipt!.record.toJson()['version'], 2);
      expect(source.dirty, isFalse);
    },
  );

  for (final conflict in [
    FileConflictPolicy.keepBoth,
    FileConflictPolicy.replace,
    FileConflictPolicy.skip,
  ]) {
    test('${conflict.name} removes only members actually copied', () async {
      final input = await source(
        await _archive(const koni.ZipWriteFormat(), {
          'chosen/a.txt': [1],
          'chosen/b.txt': [2],
          'keep': [9],
        }),
      );
      final output = await destination(
        await _archive(const koni.ZipWriteFormat(), {
          'chosen/a.txt': [3],
        }),
      );
      final review = await prepare(input, output, conflict: conflict);
      final result = await output.commitArchiveMove(reviewed: review);
      expect(result.disposition, ArchiveMoveDisposition.moved);
      final original = await read(input.file.path!);
      final target = await read(output.workspace.file.path!);
      expect(await member(target, 'chosen/b.txt'), [2]);
      expect(
        original.members.any((member) => member.name == 'chosen/b.txt'),
        isFalse,
      );
      if (conflict == FileConflictPolicy.skip) {
        expect(await member(original, 'chosen/a.txt'), [1]);
        expect(await member(target, 'chosen/a.txt'), [3]);
        expect(result.removedSources, 1);
        expect(
          result.retainedSources,
          containsAll(['/chosen', '/chosen/a.txt']),
        );
      } else {
        expect(
          original.members.any((member) => member.name == 'chosen/a.txt'),
          isFalse,
        );
        expect(result.removedSources, 2);
        if (conflict == FileConflictPolicy.replace) {
          expect(await member(target, 'chosen/a.txt'), [1]);
        } else {
          expect(await member(target, 'chosen/a.txt'), [3]);
          final additions = target.members
              .where(
                (member) =>
                    member.isFile &&
                    member.name != 'chosen/a.txt' &&
                    member.name != 'chosen/b.txt',
              )
              .toList();
          expect(additions, hasLength(1));
          expect(await target.readMember(additions.single), [1]);
        }
      }
    });
  }

  test('empty-directory moves retain unselected source content', () async {
    final input = await source(
      await _archive(
        const koni.ZipWriteFormat(),
        {
          'keep': [9],
        },
        directories: {'chosen': 0x1c0},
      ),
    );
    final output = await destination(
      await _archive(const koni.ZipWriteFormat(), {
        'keep': [8],
      }),
    );
    final review = await prepare(input, output);
    final result = await output.commitArchiveMove(reviewed: review);
    expect(result.disposition, ArchiveMoveDisposition.moved);
    expect(result.removedSources, 0);
    expect(
      (await read(input.file.path!)).members.map((member) => member.name),
      ['keep'],
    );
    expect(
      (await read(output.workspace.file.path!)).members.any(
        (member) =>
            !member.isFile &&
            member.name.replaceAll(RegExp(r'/+$'), '') == 'chosen',
      ),
      isTrue,
    );
  });

  test(
    'keeps independent source and destination passwords and original policies',
    () async {
      final input = await source(
        await _archive(const koni.ZipWriteFormat(), {
          'chosen': [1, 2],
          'keep': [9],
        }, password: 'source-password'),
        password: 'source-password',
      );
      final output = await destination(
        await _archive(
          const koni.SevenZWriteFormat(),
          {
            'keep': [8],
          },
          password: 'destination-password',
          names: true,
        ),
        name: 'output.7z',
        password: 'destination-password',
      );
      final review = await prepare(input, output);
      final result = await output.commitArchiveMove(reviewed: review);
      expect(result.disposition, ArchiveMoveDisposition.moved);
      final original = await read(
        input.file.path!,
        password: 'source-password',
      );
      final target = await read(
        output.workspace.file.path!,
        password: 'destination-password',
      );
      expect(original.members.map((member) => member.name), ['keep']);
      expect(await member(target, 'chosen'), [1, 2]);
      expect(output.workspace.encrypted, isTrue);
      expect(output.workspace.encryptNames, isTrue);
      expect(review.sourceReview.workspace.encrypted, isTrue);
      final stored = (journal.storage as MemoryFileCollectionStorage).values;
      expect('$stored', isNot(contains('source-password')));
      expect('$stored', isNot(contains('destination-password')));
    },
  );

  test(
    'removing all protected ZIP file data is refused before either publication',
    () async {
      final input = await source(
        await _archive(const koni.ZipWriteFormat(), {
          'chosen': [1],
        }, password: 'secret'),
        password: 'secret',
      );
      final output = await destination(
        await _archive(const koni.ZipWriteFormat(), {
          'keep': [8],
        }),
      );
      final oldSource = await File(input.file.path!).readAsBytes();
      final oldTarget = await File(output.workspace.file.path!).readAsBytes();
      await expectLater(prepare(input, output), throwsStateError);
      expect(await File(input.file.path!).readAsBytes(), oldSource);
      expect(await File(output.workspace.file.path!).readAsBytes(), oldTarget);
      expect(input.dirty, isFalse);
      expect(output.workspace.dirty, isFalse);
      expect(backend.moves, isEmpty);
    },
  );

  test(
    'combined candidate limit fails without leaving an imported draft',
    () async {
      final (:source, :destination) = await pair();
      final plan = await destination.prepareArchiveMove(
        source: source,
        files: source.list().where((file) => file.name == 'chosen').toList(),
      );
      await expectLater(
        destination.stageArchiveMove(
          plan,
          control: FileOperationControl(),
          maxCandidateBytes: 1,
        ),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(destination.workspace.dirty, isFalse);
      expect(source.dirty, isFalse);
      expect(backend.moves, isEmpty);
    },
  );

  test(
    'generic import and commit cannot bypass a paired move review',
    () async {
      final (:source, :destination) = await pair();
      final plan = await destination.prepareArchiveMove(
        source: source,
        files: source.list().where((file) => file.name == 'chosen').toList(),
      );
      expect(
        () => destination.stageImport(plan, control: FileOperationControl()),
        throwsStateError,
      );
      final review = await destination.stageArchiveMove(
        plan,
        control: FileOperationControl(),
      );
      expect(
        () => destination.commit(reviewed: review.destinationReview),
        throwsStateError,
      );
      await expectLater(
        review.sourceReview.workspace.save(reviewed: review.sourceReview),
        throwsStateError,
      );
      await expectLater(
        review.sourceReview.workspace.save(
          reviewed: review.sourceReview,
          sourceRemovalAuthority: Object(),
        ),
        throwsStateError,
      );
      // Discarding the shadow cannot expose an unguarded route to publish
      // further removals from this owned source workspace.
      final shadow = review.sourceReview.workspace;
      shadow.discardDraft();
      shadow.remove(['/chosen']);
      await expectLater(shadow.save(), throwsStateError);
      expect(backend.moves, isEmpty);
    },
  );

  for (final change in ['source-draft', 'removal-draft', 'destination-draft']) {
    test(
      '$change changes invalidate the paired review before publication',
      () async {
        final (:source, :destination) = await pair();
        final review = await prepare(source, destination);
        final changed = switch (change) {
          'source-draft' => source,
          'removal-draft' => review.sourceReview.workspace,
          _ => destination.workspace,
        };
        changed.createDirectory('/later');
        await expectLater(
          destination.commitArchiveMove(reviewed: review),
          throwsStateError,
        );
        expect(backend.moves, isEmpty);
      },
    );
  }

  test('cancelling preparation preserves both physical originals', () async {
    final (:source, :destination) = await pair();
    final plan = await destination.prepareArchiveMove(
      source: source,
      files: source.list().where((file) => file.name == 'chosen').toList(),
    );
    final control = FileOperationControl()..cancel();
    await expectLater(
      destination.stageArchiveMove(plan, control: control),
      throwsA(isA<FileOperationCancelled>()),
    );
    expect(backend.moves, isEmpty);
    expect(source.dirty, isFalse);
    expect(destination.workspace.dirty, isFalse);
  });

  test(
    'cancellation before destination publication has no physical mutations',
    () async {
      final (:source, :destination) = await pair();
      final review = await prepare(source, destination);
      await expectLater(
        destination.commitArchiveMove(
          reviewed: review,
          isCancelled: () => true,
        ),
        throwsA(isA<FileOperationCancelled>()),
      );
      expect(backend.moves, isEmpty);
    },
  );

  test('cancellation after destination installation returns a verified copy outcome', () async {
    final (:source, :destination) = await pair();
    final review = await prepare(source, destination);
    final oldSource = await File(source.file.path!).readAsBytes();
    var cancelled = false;
    backend.afterMove = (file, target) {
      if (target == destination.workspace.file.path &&
          file.path!.endsWith('.candidate')) {
        cancelled = true;
      }
    };
    final result = await destination.commitArchiveMove(
      reviewed: review,
      isCancelled: () => cancelled,
    );
    expect(result.disposition, ArchiveMoveDisposition.destinationOnly);
    expect(result.sourceReceipt, isNull);
    expect(result.sourceRecovery, isNull);
    expect(result.removedSources, 0);
    expect(result.retainedSources, contains('/chosen/a.txt'));
    expect(await File(source.file.path!).readAsBytes(), oldSource);
    expect(
      await member(
        await read(destination.workspace.file.path!),
        'chosen/a.txt',
      ),
      [1, 2, 3],
    );
  });

  test('source replacement after copy publication returns destination-only without source mutation', () async {
    final (:source, :destination) = await pair();
    final review = await prepare(source, destination);
    final replacement = await _archive(const koni.ZipWriteFormat(), {
      'external': [7],
    });
    backend.afterMove = (file, target) async {
      if (target == destination.workspace.file.path &&
          file.path!.endsWith('.candidate')) {
        await File(source.file.path!).writeAsBytes(replacement, flush: true);
      }
    };
    final result = await destination.commitArchiveMove(reviewed: review);
    expect(result.disposition, ArchiveMoveDisposition.destinationOnly);
    expect(await File(source.file.path!).readAsBytes(), replacement);
    expect(
      backend.moves.any((move) => move.startsWith('${source.file.path}:')),
      isFalse,
    );
    expect(
      await member(
        await read(destination.workspace.file.path!),
        'chosen/a.txt',
      ),
      [1, 2, 3],
    );
  });

  test(
    'source permission changes after destination publication retain a copy',
    () async {
      final (:source, :destination) = await pair();
      final review = await prepare(source, destination);
      final oldSource = await File(source.file.path!).readAsBytes();
      final original = (await backend.stat(source.file.path!))!;
      final result = await destination.commitArchiveMove(
        reviewed: review,
        onPhase: (phase) {
          if (phase == ArchiveMovePhase.sourcePublication) {
            final changed = Process.runSync('chmod', [
              '700',
              source.file.path!,
            ]);
            expect(changed.exitCode, 0, reason: '${changed.stderr}');
          }
        },
      );
      expect(result.disposition, ArchiveMoveDisposition.destinationOnly);
      expect(result.sourceRecovery, isNull);
      expect(result.warnings.join('\n'), contains('native source identity'));
      expect(await File(source.file.path!).readAsBytes(), oldSource);
      expect(
        sameArchiveFile(original, await backend.stat(source.file.path!)),
        isTrue,
      );
      expect(
        backend.moves.any((move) => move.startsWith('${source.file.path}:')),
        isFalse,
      );
      expect(
        await member(
          await read(destination.workspace.file.path!),
          'chosen/a.txt',
        ),
        [1, 2, 3],
      );
    },
    skip: !Platform.isLinux && !Platform.isMacOS,
  );

  test('source draft changing during backup prevents removal candidate installation', () async {
    final (:source, :destination) = await pair();
    final review = await prepare(source, destination);
    final oldSource = await File(source.file.path!).readAsBytes();
    var changed = false;
    backend.beforeMove = (file, target) {
      if (!changed &&
          file.path == source.file.path &&
          target.endsWith('.original')) {
        changed = true;
        source.createDirectory('/late-draft');
      }
    };
    final result = await destination.commitArchiveMove(reviewed: review);
    expect(changed, isTrue);
    expect(result.disposition, ArchiveMoveDisposition.sourceRecoveryRequired);
    expect(result.sourceReceipt, isNull);
    expect(result.sourceRecovery!.dependency, isNotNull);
    expect(await File(source.file.path!).readAsBytes(), oldSource);
    expect(source.dirty, isTrue);
    expect(
      backend.moves.any(
        (move) =>
            move.endsWith('.candidate:${source.file.path}') &&
            move.contains('/source/'),
      ),
      isFalse,
    );
    expect(
      await member(
        await read(destination.workspace.file.path!),
        'chosen/a.txt',
      ),
      [1, 2, 3],
    );
  });

  test(
    'destination replacement before source phase refuses all source removal',
    () async {
      final (:source, :destination) = await pair();
      final review = await prepare(source, destination);
      final oldSource = await File(source.file.path!).readAsBytes();
      final changed = await _archive(const koni.TarWriteFormat(), {
        'external': [7],
      });
      final result = await destination.commitArchiveMove(
        reviewed: review,
        onPhase: (phase) {
          if (phase == ArchiveMovePhase.sourcePublication) {
            File(destination.workspace.file.path!)
                .writeAsBytesSync(changed, flush: true);
          }
        },
      );
      expect(result.disposition, isNot(ArchiveMoveDisposition.moved));
      expect(result.removedSources, 0);
      expect(await File(source.file.path!).readAsBytes(), oldSource);
      expect(
        await File(destination.workspace.file.path!).readAsBytes(),
        changed,
      );
      expect(
        backend.moves.any((move) => move.startsWith('${source.file.path}:')),
        isFalse,
      );
    },
  );

  test('failed source installation restores original and recovery remains destination-bound', () async {
    final (:source, :destination) = await pair();
    final review = await prepare(source, destination);
    final oldSource = await File(source.file.path!).readAsBytes();
    var fail = true;
    backend.beforeMove = (file, target) {
      if (fail &&
          target == source.file.path &&
          file.path!.endsWith('.candidate')) {
        fail = false;
        throw StateError('Simulated source install failure.');
      }
    };
    final result = await destination.commitArchiveMove(reviewed: review);
    expect(result.disposition, ArchiveMoveDisposition.sourceRecoveryRequired);
    expect(result.sourceRecovery, isNotNull);
    expect(result.retainedSources, isEmpty);
    expect(result.sourceReceipt, isNull);
    expect(await File(source.file.path!).readAsBytes(), oldSource);
    expect(
      await member(
        await read(destination.workspace.file.path!),
        'chosen/a.txt',
      ),
      [1, 2, 3],
    );
    final persisted = ArchivePublicationRecord.fromJson(
      result.sourceRecovery!.toJson(),
    );
    final currentDestination = (await backend.stat(
      destination.workspace.file.path!,
    ))!;
    expect(
      persisted.dependency!.file.updatedAt!.isAtSameMomentAs(
        currentDestination.updatedAt!,
      ),
      isTrue,
    );
    expect(
      sameArchiveFile(persisted.dependency!.file, currentDestination),
      isTrue,
      reason: 'Reloaded UTC timestamps must match native local timestamps.',
    );
    final recovered = await ArchiveContainerPublisher(
      backend,
      journal,
    ).recover(result.sourceRecovery!, ArchiveRecoveryAction.finishPublication);
    expect(recovered, isNotNull);
    expect(
      (await read(source.file.path!)).members.map((member) => member.name),
      ['keep.txt'],
    );
  });

  test('destination loss after source installation retains backup for guarded restoration', () async {
    final (:source, :destination) = await pair();
    final review = await prepare(source, destination);
    final oldSource = await File(source.file.path!).readAsBytes();
    final changed = await _archive(const koni.TarWriteFormat(), {
      'external': [7],
    });
    backend.afterMove = (file, target) async {
      if (target == source.file.path && file.path!.endsWith('.candidate')) {
        await File(destination.workspace.file.path!)
            .writeAsBytes(changed, flush: true);
      }
    };
    final result = await destination.commitArchiveMove(reviewed: review);
    expect(result.disposition, ArchiveMoveDisposition.sourceRecoveryRequired);
    expect(result.removedSources, 0);
    expect(result.retainedSources, isEmpty);
    final record = result.sourceRecovery!;
    expect(
      await File(record.backupPath(backend.paths)).readAsBytes(),
      oldSource,
    );
    final recovery = ArchiveContainerPublisher(backend, journal);
    final inspection = await recovery.inspect(record);
    expect(inspection.canFinish, isFalse);
    expect(inspection.canRestore, isTrue);
    expect(
      await recovery.recover(record, ArchiveRecoveryAction.restoreOriginal),
      isNull,
    );
    expect(await File(source.file.path!).readAsBytes(), oldSource);
    expect(await File(destination.workspace.file.path!).readAsBytes(), changed);
  });

  test(
    'failed destination publication never starts source publication',
    () async {
      final (:source, :destination) = await pair();
      final review = await prepare(source, destination);
      final oldSource = await File(source.file.path!).readAsBytes();
      final oldDestination = await File(destination.workspace.file.path!)
          .readAsBytes();
      var fail = true;
      backend.beforeMove = (file, target) {
        if (fail &&
            target == destination.workspace.file.path &&
            file.path!.endsWith('.candidate')) {
          fail = false;
          throw StateError('Simulated destination install failure.');
        }
      };
      await expectLater(
        destination.commitArchiveMove(reviewed: review),
        throwsA(isA<ArchivePublicationException>()),
      );
      expect(await File(source.file.path!).readAsBytes(), oldSource);
      expect(
        await File(destination.workspace.file.path!).readAsBytes(),
        oldDestination,
      );
      expect(
        backend.moves.any((move) => move.startsWith('${source.file.path}:')),
        isFalse,
      );
    },
  );

  test('same physical archive and hard-link aliases are refused', () async {
    final (:source, :destination) = await pair();
    final same = ArchiveEndpoint.fromWorkspace(source);
    addTearDown(same.close);
    await expectLater(
      same.prepareArchiveMove(source: source, files: source.list()),
      throwsUnsupportedError,
    );
    final aliasPath = '${directory.path}/destination/alias.zip';
    final linked = await Process.run('ln', [source.file.path!, aliasPath]);
    expect(linked.exitCode, 0, reason: '${linked.stderr}');
    final alias = await ArchiveEndpoint.open(
      containerBackend: backend,
      containerFile: (await backend.stat(aliasPath))!,
      journal: journal,
    );
    addTearDown(alias.close);
    await expectLater(
      alias.prepareArchiveMove(source: source, files: source.list()),
      throwsUnsupportedError,
    );
    expect(destination.workspace.dirty, isFalse);
    expect(backend.moves, isEmpty);
  }, skip: !Platform.isLinux && !Platform.isMacOS);

  for (final nestedSource in [false, true]) {
    test(
      'nested ${nestedSource ? 'source' : 'destination'} remains outside move scope',
      () async {
        final inner = await _archive(const koni.ZipWriteFormat(), {
          'chosen': [1],
          'keep': [9],
        });
        final outer = await _archive(const koni.ZipWriteFormat(), {
          'inner.zip': inner,
        });
        final input = await source(
          nestedSource ? outer : inner,
          nested: nestedSource ? ['inner.zip'] : [],
        );
        final output = await destination(
          nestedSource ? inner : outer,
          nested: nestedSource ? [] : ['inner.zip'],
        );
        await expectLater(
          output.prepareArchiveMove(source: input, files: input.list()),
          throwsUnsupportedError,
        );
        expect(backend.moves, isEmpty);
      },
    );
  }

  test(
    'non-native source and replacement-only compression profiles are refused',
    () async {
      final output = await destination(
        await _archive(const koni.ZipWriteFormat(), {
          'keep': [8],
        }),
      );
      final remote = ArchiveEndpointTestBackend()
        ..put(
          '/input/source.zip',
          await _archive(const koni.ZipWriteFormat(), {
            'chosen': [1],
          }),
        );
      final remoteSource = await ArchiveWorkspace.open(
        remote,
        (await remote.stat('/input/source.zip'))!,
        journal: journal,
      );
      addTearDown(remoteSource.close);
      await expectLater(
        output.prepareArchiveMove(
          source: remoteSource,
          files: remoteSource.list(),
        ),
        throwsUnsupportedError,
      );
      final compressed = await source(
        Uint8List.fromList(const codec.GZipEncoder().encode([1, 2, 3])),
        name: 'one.gz',
      );
      await expectLater(
        output.prepareArchiveMove(source: compressed, files: compressed.list()),
        throwsUnsupportedError,
      );
      expect(backend.moves, isEmpty);
    },
  );

  test('both endpoints must start with clean drafts', () async {
    final (:source, :destination) = await pair();
    source.createDirectory('/draft');
    await expectLater(
      destination.prepareArchiveMove(source: source, files: source.list()),
      throwsUnsupportedError,
    );
    source.discardDraft();
    destination.workspace.createDirectory('/draft');
    await expectLater(
      destination.prepareArchiveMove(source: source, files: source.list()),
      throwsUnsupportedError,
    );
    expect(backend.moves, isEmpty);
  });

  test('verified removal rejects mismatched bytes atomically', () async {
    final input = await source(
      await _archive(const koni.ZipWriteFormat(), {
        'a': [1],
        'b': [2],
      }),
    );
    final revision = input.revision;
    await expectLater(
      input.stageVerifiedMemberRemoval(
        [
          ArchiveWorkspaceRemoval(
            path: '/a',
            isDirectory: false,
            size: 1,
            sha256: sha256.convert([1]).toString(),
          ),
          ArchiveWorkspaceRemoval(
            path: '/b',
            isDirectory: false,
            size: 1,
            sha256: sha256.convert([9]).toString(),
          ),
        ],
        expectedRevision: revision,
        publicationAuthority: Object(),
      ),
      throwsStateError,
    );
    expect(input.revision, revision);
    expect(input.dirty, isFalse);
    expect(await input.read('/a'), [1]);
    expect(await input.read('/b'), [2]);
  });

  test(
    'removal authority alone cannot publish without a destination dependency',
    () async {
      final input = await source(
        await _archive(const koni.ZipWriteFormat(), {
          'a': [1],
          'keep': [9],
        }),
      );
      final authority = Object();
      await input.stageVerifiedMemberRemoval(
        [
          ArchiveWorkspaceRemoval(
            path: '/a',
            isDirectory: false,
            size: 1,
            sha256: sha256.convert([1]).toString(),
          ),
        ],
        expectedRevision: input.revision,
        publicationAuthority: authority,
      );
      final review = await input.review();
      await expectLater(
        input.save(reviewed: review, sourceRemovalAuthority: authority),
        throwsStateError,
      );
      expect(backend.moves, isEmpty);
      expect(await member(await read(input.file.path!), 'a'), [1]);
    },
  );
}
