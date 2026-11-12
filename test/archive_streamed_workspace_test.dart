import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/models/archive_endpoint.dart';
import 'package:crisp_cloud/services/archive_publication_journal.dart';
import 'package:crisp_cloud/services/archive_streaming_writer.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/archive_workspace.dart';
import 'package:crisp_cloud/services/archive_write_model.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/file_operation_service.dart'
    show FileOperationCancelled;
import 'package:crisp_cloud/services/installation_identity.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

final _modified = DateTime.utc(2026, 11, 12, 1, 2, 3);

ArchiveWriteEntry _fileEntry(String path, List<int> bytes) => ArchiveWriteEntry(
  path: path,
  isDirectory: false,
  size: bytes.length,
  modified: _modified,
  mode: 0x1a4,
  readChunks: () => Stream<List<int>>.value(bytes),
);

Future<File> _writeArchive(
  String path,
  ArchiveEndpointFormat format, {
  List<ArchiveWriteEntry>? entries,
}) async {
  final file = File(path);
  final output = await file.open(mode: FileMode.writeOnly);
  try {
    await writeStreamingArchiveEntries(
      format,
      entries ??
          [
            _fileEntry('folder/original.txt', utf8.encode('original')),
            _fileEntry('remove.txt', [1, 2, 3]),
            ArchiveWriteEntry(
              path: 'empty',
              isDirectory: true,
              size: 0,
              modified: _modified,
              mode: 0x1ed,
            ),
          ],
      sink: (bytes) async {
        await output.writeFrom(bytes);
      },
      maxOutputBytes: kArchiveStreamingLimit,
    );
    await output.flush();
  } finally {
    await output.close();
  }
  return file;
}

Future<Uint8List> _encryptedArchive(koni.ArchiveWriteFormat format) async {
  final sink = koni.BytesBuilderSink();
  final writer = koni.Archive.create(
    sink,
    format: format,
    options: const koni.ArchiveWriteOptions(
      password: 'original-password',
      encryptHeader: true,
    ),
  );
  await writer.addBytes(
    koni.ArchiveEntrySpec(
      path: 'original.txt',
      modified: _modified,
      posixMode: 0x1a4,
    ),
    Uint8List.fromList(utf8.encode('protected original')),
  );
  await writer.close();
  await sink.close();
  return sink.takeBytes();
}

Stream<List<int>> _zeroes(int size) async* {
  final chunk = Uint8List(256 * 1024);
  for (var position = 0; position < size; position += chunk.length) {
    final remaining = size - position;
    yield remaining < chunk.length
        ? Uint8List.sublistView(chunk, 0, remaining)
        : chunk;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await InstallationIdentityService.instance.initialize();
  });

  late Directory directory;
  late LocalOperationBackend local;
  late ArchivePublicationJournal journal;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'crisp-streamed-workspace-test-',
    );
    local = LocalOperationBackend(LocalFileService(), isCurrent: () => true);
    journal = ArchivePublicationJournal(storage: MemoryFileCollectionStorage());
    addTearDown(() => directory.delete(recursive: true));
  });

  Future<ArchiveWorkspace> open(File file, {String? password}) async {
    final workspace = await ArchiveWorkspace.open(
      local,
      (await local.stat(file.path))!,
      password: password,
      journal: journal,
    );
    addTearDown(workspace.close);
    return workspace;
  }

  for (final profile in [
    ('zip', ArchiveEndpointFormat.zip),
    ('7z', ArchiveEndpointFormat.sevenZip),
    ('tar', ArchiveEndpointFormat.tar),
    ('tgz', ArchiveEndpointFormat.tarGzip),
  ]) {
    test(
      '${profile.$1}: native folder edits publish a streamed review and reopen',
      () async {
        final file = await _writeArchive(
          p.join(directory.path, 'work.${profile.$1}'),
          profile.$2,
        );
        final original = await file.readAsBytes();
        final workspace = await open(file);
        expect(workspace.supportsLargeFiles, isTrue);
        expect(workspace.maxMemberBytes, kArchiveStreamingLimit);
        expect(workspace.canUpdate, local.capabilities.noReplaceMove);
        if (!workspace.canUpdate) return;

        final imported = File(p.join(directory.path, 'incoming.txt'));
        await imported.writeAsString('captured import');
        await imported.setLastModified(_modified);
        await workspace.addFiles(local, [(await local.stat(imported.path))!]);
        await imported.writeAsString('subsequent source change');
        expect(
          utf8.decode(await workspace.read('/incoming.txt')),
          'captured import',
        );
        workspace.rename('/folder', '/renamed');
        workspace.remove(['/remove.txt']);
        workspace.createDirectory(
          '/new-empty',
          modified: _modified,
          mode: 0x1ed,
        );
        workspace.replace(
          '/edited.txt',
          Uint8List.fromList(utf8.encode('edited')),
        );

        final review = await workspace.review();
        expect(review.isCurrent, isTrue);
        expect(review.spool?.isSealed, isTrue);
        expect(() => review.bytes, throwsStateError);
        expect(review.packedBytes, greaterThan(0));
        expect(
          (await sha256.bind(review.openRead()).single).toString(),
          review.sha256,
        );
        expect(
          review.changes.any(
            (change) => change.kind == ArchiveWorkspaceChangeKind.rename,
          ),
          isTrue,
        );
        expect(
          review.changes.any(
            (change) => change.kind == ArchiveWorkspaceChangeKind.remove,
          ),
          isTrue,
        );
        expect(await file.readAsBytes(), original);

        final receipt = await workspace.save(reviewed: review);
        expect(receipt, isNotNull);
        expect(workspace.dirty, isFalse);
        expect(
          (await sha256.bind(file.openRead()).single).toString(),
          review.sha256,
        );
        expect(
          utf8.decode(await workspace.read('/renamed/original.txt')),
          'original',
        );
        final retained = workspace.list('/renamed').single;
        expect(retained.updatedAt, _modified);
        final candidateSource = await review.spool!.openByteSource();
        await candidateSource.close();

        await workspace.close();
        expect(review.spool!.isSealed, isFalse);
        final reopened = await open(file);
        expect(reopened.list().map((entry) => entry.name).toSet(), {
          'renamed',
          'empty',
          'new-empty',
          'incoming.txt',
          'edited.txt',
        });
        expect(
          utf8.decode(await reopened.read('/incoming.txt')),
          'captured import',
        );
        expect(utf8.decode(await reopened.read('/edited.txt')), 'edited');
        expect(
          await directory
              .list()
              .map((entry) => p.basename(entry.path))
              .toList(),
          unorderedEquals(['work.${profile.$1}', 'incoming.txt']),
        );
      },
    );
  }

  test('a stale review is invalidated and its spool is retired after the next review', () async {
    final file = await _writeArchive(
      p.join(directory.path, 'work.zip'),
      ArchiveEndpointFormat.zip,
    );
    final workspace = await open(file);
    if (!workspace.canUpdate) return;
    workspace.replace('/first.txt', Uint8List.fromList([1]));
    final first = await workspace.review();
    workspace.replace('/second.txt', Uint8List.fromList([2]));
    expect(first.isCurrent, isFalse);
    await expectLater(workspace.save(reviewed: first), throwsStateError);
    final next = await workspace.review();
    expect(first.spool!.isSealed, isFalse);
    await expectLater(first.openRead().drain<void>(), throwsStateError);
    await workspace.save(reviewed: next);
    workspace.replace('/third.txt', Uint8List.fromList([3]));
    final third = await workspace.review();
    await workspace.save(reviewed: third);
    expect(next.spool!.isSealed, isFalse);
    expect(await workspace.read('/first.txt'), [1]);
    expect(await workspace.read('/second.txt'), [2]);
    expect(await workspace.read('/third.txt'), [3]);
  });

  for (final protected in [
    ('zip', const koni.ZipWriteFormat()),
    ('7z', const koni.SevenZWriteFormat()),
  ]) {
    test(
      '${protected.$1}: encrypted native sources retain the bounded password workflow',
      () async {
        final original = await _encryptedArchive(protected.$2);
        final file = File(p.join(directory.path, 'protected.${protected.$1}'));
        await file.writeAsBytes(original, flush: true);
        await expectLater(
          open(file),
          throwsA(isA<ArchivePasswordRequiredException>()),
        );
        await expectLater(
          open(file, password: 'wrong-password'),
          throwsA(isA<ArchivePasswordRequiredException>()),
        );
        final workspace = await open(file, password: 'original-password');
        expect(workspace.supportsLargeFiles, isFalse);
        expect(workspace.encrypted, isTrue);
        expect(workspace.maxMemberBytes, kArchiveReadLimit);
        if (!workspace.canUpdate) return;
        workspace.rename('/original.txt', '/renamed.txt');
        final review = await workspace.review();
        expect(review.spool, isNull);
        expect(review.bytes, isNotEmpty);
        await workspace.save(reviewed: review);
        await workspace.close();
        final reopened = await open(file, password: 'original-password');
        expect(reopened.encrypted, isTrue);
        expect(
          utf8.decode(await reopened.read('/renamed.txt')),
          'protected original',
        );
      },
    );
  }

  test('an externally changed native archive is retained when a reviewed save refuses it', () async {
    final file = await _writeArchive(
      p.join(directory.path, 'work.zip'),
      ArchiveEndpointFormat.zip,
    );
    final workspace = await open(file);
    if (!workspace.canUpdate) return;
    workspace.replace('/draft.txt', Uint8List.fromList([4]));
    final review = await workspace.review();
    await _writeArchive(
      file.path,
      ArchiveEndpointFormat.zip,
      entries: [
        _fileEntry('external.txt', utf8.encode('external replacement')),
      ],
    );
    final external = await file.readAsBytes();
    await expectLater(
      workspace.save(reviewed: review),
      throwsA(anyOf(isA<StateError>(), isA<ArchivePublicationException>())),
    );
    expect(await file.readAsBytes(), external);
    expect(workspace.dirty, isTrue);
    expect(await workspace.read('/draft.txt'), [4]);
  });

  test('cancelled review leaves the original intact and a completed save releases its cancellation callback', () async {
    final file = await _writeArchive(
      p.join(directory.path, 'work.tgz'),
      ArchiveEndpointFormat.tarGzip,
    );
    final original = await file.readAsBytes();
    final workspace = await open(file);
    if (!workspace.canUpdate) return;
    workspace.rename('/folder', '/renamed');
    var checkpoints = 0;
    await expectLater(
      workspace.review(isCancelled: () => ++checkpoints >= 5),
      throwsA(
        anyOf(
          isA<StateError>(),
          isA<ArchiveViewException>(),
          isA<FileOperationCancelled>(),
        ),
      ),
    );
    expect(checkpoints, greaterThanOrEqualTo(5));
    expect(await file.readAsBytes(), original);
    expect(workspace.dirty, isTrue);
    final review = await workspace.review();
    var cancelled = true;
    await expectLater(
      workspace.save(reviewed: review, isCancelled: () => cancelled),
      throwsA(isA<ArchiveViewException>()),
    );
    expect(await file.readAsBytes(), original);
    cancelled = false;
    await workspace.save(reviewed: review, isCancelled: () => cancelled);
    cancelled = true;
    expect(
      utf8.decode(await workspace.read('/renamed/original.txt')),
      'original',
    );
    workspace.replace('/next.txt', Uint8List.fromList([9]));
    await workspace.save();
    expect(await workspace.read('/next.txt'), [9]);
  });

  test(
    'native TGZ can review, publish and reopen a member larger than 2 GiB',
    () async {
      const size = 2 * 1024 * 1024 * 1024 + 17;
      final file = await _writeArchive(
        p.join(directory.path, 'large.tgz'),
        ArchiveEndpointFormat.tarGzip,
        entries: [
          ArchiveWriteEntry(
            path: 'large.bin',
            isDirectory: false,
            size: size,
            modified: _modified,
            mode: 0x1a4,
            readChunks: () => _zeroes(size),
          ),
        ],
      );
      final workspace = await open(file);
      if (!workspace.canUpdate) return;
      expect(workspace.list().single.size, size);
      await expectLater(
        workspace.read('/large.bin'),
        throwsA(isA<ArchiveViewException>()),
      );
      workspace.rename('/large.bin', '/renamed.bin');
      final review = await workspace.review();
      expect(review.spool?.isSealed, isTrue);
      expect(() => review.bytes, throwsStateError);
      await workspace.save(reviewed: review);
      await workspace.close();
      final reopened = await open(file);
      var decoded = 0;
      await for (final chunk in reopened.openRead('/renamed.bin')) {
        expect(chunk.length, lessThanOrEqualTo(256 * 1024));
        expect(chunk.every((byte) => byte == 0), isTrue);
        decoded += chunk.length;
      }
      expect(decoded, size);
    },
    skip: Platform.environment['CRISP_RUN_LARGE_ARCHIVE_TESTS'] != '1',
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
