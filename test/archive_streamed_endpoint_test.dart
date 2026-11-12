import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' as codec;
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/archive_endpoint.dart';
import 'package:crisp_cloud/services/archive_publication_journal.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/installation_identity.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/storage_transfer_contract.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

Future<Uint8List> _originalArchive(String extension) async {
  if (extension == '7z') {
    final output = koni.BytesBuilderSink();
    final writer = koni.Archive.create(
      output,
      format: const koni.SevenZWriteFormat(),
    );
    await writer.addBytes(
      koni.ArchiveEntrySpec(path: 'keep.bin'),
      Uint8List.fromList([1, 2, 3]),
    );
    await writer.close();
    await output.close();
    return output.takeBytes();
  }
  final archive = codec.Archive()
    ..addFile(codec.ArchiveFile.bytes('keep.bin', [1, 2, 3]));
  if (extension == 'tgz') {
    return Uint8List.fromList(gzip.encode(codec.TarEncoder().encode(archive)));
  }
  return Uint8List.fromList(codec.ZipEncoder().encode(archive));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await InstallationIdentityService.instance.initialize();
  });

  Future<
    ({ArchiveEndpoint endpoint, File container, LocalOperationBackend local})
  >
  open(String extension) async {
    final directory = await Directory.systemTemp.createTemp(
      'crisp-streamed-import-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final container = File(p.join(directory.path, 'destination.$extension'));
    await container.writeAsBytes(
      await _originalArchive(extension),
      flush: true,
    );
    final local = LocalOperationBackend(
      LocalFileService(),
      isCurrent: () => true,
    );
    final endpoint = await ArchiveEndpoint.open(
      containerBackend: local,
      containerFile: (await local.stat(container.path))!,
      journal: ArchivePublicationJournal(
        storage: MemoryFileCollectionStorage(),
      ),
    );
    addTearDown(endpoint.close);
    expect(endpoint.workspace.supportsLargeFiles, isTrue);
    expect(endpoint.workspace.canUpdate, isTrue);
    return (endpoint: endpoint, container: container, local: local);
  }

  for (final extension in ['zip', '7z', 'tgz']) {
    test(
      '$extension native import adopts streamed content and publishes a verified member',
      () async {
        final (:endpoint, :container, :local) = await open(extension);
        final original = await container.readAsBytes();
        final bytes = Uint8List.fromList(
          List.generate(512 * 1024 + 17, (i) => (i * 19) % 251),
        );
        final source = File(p.join(container.parent.path, 'new.bin'));
        await source.writeAsBytes(bytes, flush: true);
        await source.setLastModified(DateTime.utc(2026, 1, 2, 3, 4, 5));
        final plan = await endpoint.prepareImport(
          source: local,
          files: [(await local.stat(source.path))!],
        );
        expect(plan.errors, isEmpty);
        final reviewed = await endpoint.stageImport(
          plan,
          control: FileOperationControl(),
        );
        expect(await container.readAsBytes(), original);
        expect(endpoint.workspace.expandedBytes, bytes.length + 3);
        expect(
          (await sha256.bind(endpoint.workspace.openRead('/new.bin')).first)
              .toString(),
          sha256.convert(bytes).toString(),
        );
        final receipt = await endpoint.commit(reviewed: reviewed);
        expect(receipt.publishedFiles, 1);
        expect(receipt.removedSources, 0);
        expect(receipt.receipt.cleanupPending, isFalse);
        expect(await source.exists(), isTrue);
        expect(await endpoint.workspace.read('/keep.bin'), [1, 2, 3]);
        expect(
          (await sha256.bind(endpoint.workspace.openRead('/new.bin')).first)
              .toString(),
          sha256.convert(bytes).toString(),
        );
      },
    );
  }

  test('native ZIP imports a member beyond the old 64 MiB boundary through the normal endpoint', () async {
    final (:endpoint, :container, :local) = await open('zip');
    final source = File(p.join(container.parent.path, 'large.bin'));
    final handle = await source.open(mode: FileMode.write);
    const length = 65 * 1024 * 1024 + 17;
    try {
      await handle.truncate(length);
      await handle.writeFrom([12, 34, 56]);
      await handle.setPosition(length - 4);
      await handle.writeFrom([65, 43, 21, 9]);
      await handle.flush();
    } finally {
      await handle.close();
    }
    final hash = (await sha256.bind(source.openRead()).first).toString();
    final plan = await endpoint.prepareImport(
      source: local,
      files: [(await local.stat(source.path))!],
    );
    expect(plan.canStage, isTrue, reason: plan.errors.join('\n'));
    final reviewed = await endpoint.stageImport(
      plan,
      control: FileOperationControl(),
    );
    expect((await endpoint.workspace.backend.stat('/large.bin'))!.size, length);
    final result = await endpoint.commit(reviewed: reviewed);
    expect(result.publishedFiles, 1);
    expect((await endpoint.workspace.backend.stat('/large.bin'))!.size, length);
    expect(
      (await sha256.bind(endpoint.workspace.openRead('/large.bin')).first)
          .toString(),
      hash,
    );
    expect(await source.length(), length);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('multi-gigabyte source reaches streaming copy and cancellation leaves a clean draft', () async {
    final (:endpoint, :container, local: _) = await open('zip');
    final original = await container.readAsBytes();
    final control = FileOperationControl();
    final source = _StreamSource(
      length: 2 * 1024 * 1024 * 1024 + 4096,
      contents: (read) async* {
        yield Uint8List(65536);
        control.cancel();
        yield Uint8List(65536);
      },
    );
    final plan = await endpoint.prepareImport(
      source: source,
      files: [source.file],
    );
    expect(plan.canStage, isTrue, reason: plan.errors.join('\n'));
    await expectLater(
      endpoint.stageImport(plan, control: control),
      throwsA(anything),
    );
    expect(source.reads, 1);
    expect(endpoint.workspace.dirty, isFalse);
    expect(endpoint.workspace.list().map((item) => item.name), ['keep.bin']);
    expect(await container.readAsBytes(), original);
  });

  test('changed source after private copying is refused before adopting any spools', () async {
    final (:endpoint, :container, local: _) = await open('zip');
    final original = await container.readAsBytes();
    final source = _StreamSource(
      length: 257,
      contents: (read) =>
          Stream.value(Uint8List.fromList(List.filled(257, read == 1 ? 1 : 9))),
    );
    final plan = await endpoint.prepareImport(
      source: source,
      files: [source.file],
    );
    await expectLater(
      endpoint.stageImport(plan, control: FileOperationControl()),
      throwsA(anything),
    );
    expect(source.reads, greaterThanOrEqualTo(2));
    expect(endpoint.workspace.dirty, isFalse);
    expect(endpoint.workspace.list().map((item) => item.name), ['keep.bin']);
    expect(await container.readAsBytes(), original);
  });

  test(
    'planning accounts for retained content and subtracts replaced members',
    () async {
      final (:endpoint, container: _, local: _) = await open('zip');
      final source = _StreamSource(
        name: 'keep.bin',
        length: endpoint.workspace.maxExpandedBytes,
        contents: (_) =>
            throw StateError('Planning must not read payload bytes.'),
      );
      final add = await endpoint.prepareImport(
        source: source,
        files: [source.file],
      );
      expect(add.canStage, isFalse);
      expect(add.errors.join(' '), contains('retained archive contents'));
      final replace = await endpoint.prepareImport(
        source: source,
        files: [source.file],
        conflict: FileConflictPolicy.replace,
      );
      expect(replace.canStage, isTrue, reason: replace.errors.join('\n'));
      expect(source.reads, 0);
    },
  );

  for (final invalid in ['short', 'growing', 'invalid-byte']) {
    test('$invalid import cannot adopt a partial native member', () async {
      final (:endpoint, :container, local: _) = await open('zip');
      final original = await container.readAsBytes();
      final source = _StreamSource(
        length: 17,
        contents: (_) => Stream.value(switch (invalid) {
          'short' => List<int>.filled(16, 1),
          'growing' => List<int>.filled(18, 1),
          _ => List<int>.filled(17, 256),
        }),
      );
      final plan = await endpoint.prepareImport(
        source: source,
        files: [source.file],
      );
      await expectLater(
        endpoint.stageImport(plan, control: FileOperationControl()),
        throwsA(anything),
      );
      expect(endpoint.workspace.dirty, isFalse);
      expect(endpoint.workspace.expandedBytes, 3);
      expect(await container.readAsBytes(), original);
    });
  }

  test('a later failed member discards the whole private import and permits a fresh plan', () async {
    final (:endpoint, :container, local: _) = await open('zip');
    final original = await container.readAsBytes();
    final source = _TwoFileSource();
    final plan = await endpoint.prepareImport(
      source: source,
      files: [source.file, source.second],
    );
    await expectLater(
      endpoint.stageImport(plan, control: FileOperationControl()),
      throwsA(anything),
    );
    expect(endpoint.workspace.dirty, isFalse);
    expect(endpoint.workspace.expandedBytes, 3);
    expect(await container.readAsBytes(), original);
    final retry = await endpoint.prepareImport(
      source: source,
      files: [source.file],
    );
    final reviewed = await endpoint.stageImport(
      retry,
      control: FileOperationControl(),
    );
    expect(reviewed.isCurrent, isTrue);
    expect(await endpoint.workspace.read('/new.bin'), [4, 5, 6]);
    expect(await container.readAsBytes(), original);
  });
}

class _StreamSource extends FileOperationBackend {
  _StreamSource({
    required int length,
    required this.contents,
    String name = 'new.bin',
  }) : file = FileItem(
         name: name,
         path: '/input/$name',
         isFolder: false,
         size: length,
         metadata: const {'version': 'captured'},
       );
  final FileItem file;
  final Stream<List<int>> Function(int read) contents;
  int reads = 0;
  @override
  Object get identity => this;
  @override
  String get label => 'Captured streaming fixture';
  @override
  bool get isCurrent => true;
  @override
  StorageTransferCapabilities get capabilities =>
      const StorageTransferCapabilities(boundedDownload: true);
  @override
  p.Context get paths => p.posix;
  @override
  Future<FileItem?> stat(String path) async => path == file.path ? file : null;
  @override
  Future<List<FileItem>> list(String path) async =>
      path == '/input' ? [file] : [];
  @override
  Stream<List<int>> readFile(FileItem file) => contents(++reads);
  @override
  Future<void> createDirectory(String path) async =>
      throw UnsupportedError('read only');
  @override
  Future<void> writeFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
  }) async => throw UnsupportedError('read only');
  @override
  Future<void> deleteFile(FileItem file) async =>
      throw UnsupportedError('read only');
  @override
  Future<void> deleteEmptyDirectory(String path) async =>
      throw UnsupportedError('read only');
}

class _TwoFileSource extends _StreamSource {
  _TwoFileSource() : super(length: 3, contents: (_) => Stream.value([4, 5, 6]));
  final second = FileItem(
    name: 'short.bin',
    path: '/input/short.bin',
    isFolder: false,
    size: 2,
    metadata: const {'version': 'captured'},
  );

  @override
  Future<FileItem?> stat(String path) async =>
      path == second.path ? second : super.stat(path);

  @override
  Stream<List<int>> readFile(FileItem file) =>
      file.path == second.path ? Stream.value([7]) : super.readFile(file);
}
