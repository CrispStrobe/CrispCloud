import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/services/archive_creation_service.dart';
import 'package:crisp_cloud/services/archive_tar_writer.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/archive_write_model.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/native_file_primitives.dart';
import 'package:crisp_cloud/services/storage_transfer_contract.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/io.dart' as koni;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/archive_creation_backend.dart';

const _mib = 1024 * 1024;
const _freshLimit = ArchiveCreationService.maxStreamedTarBytes;
const _fixedTime = '2026-01-02T03:04:05.000Z';

Matcher _creationError(ArchiveCreationError code) => throwsA(
  isA<ArchiveCreationException>().having((error) => error.code, 'code', code),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'large TAR eligibility requires both native bounded local endpoints',
    () {
      final native = _CapabilityBackend();
      for (final format in ArchiveCreationFormat.values) {
        expect(
          ArchiveCreationService.supportsStreamedTarCreation(
            format: format,
            source: native,
            destination: native,
          ),
          format == ArchiveCreationFormat.tar ||
              format == ArchiveCreationFormat.cbt,
          reason: format.name,
        );
      }
      for (final backend in [
        ArchiveCreationBackend(),
        _CapabilityBackend(local: false),
        _CapabilityBackend(provider: 'browser'),
        _CapabilityBackend(download: false),
      ]) {
        expect(
          ArchiveCreationService.supportsStreamedTarCreation(
            format: ArchiveCreationFormat.tar,
            source: backend,
            destination: native,
          ),
          isFalse,
        );
      }
      for (final backend in [
        ArchiveCreationBackend(),
        _CapabilityBackend(local: false),
        _CapabilityBackend(provider: 'browser'),
        _CapabilityBackend(download: false),
        _CapabilityBackend(upload: false),
        _CapabilityBackend(verification: false),
      ]) {
        expect(
          ArchiveCreationService.supportsStreamedTarCreation(
            format: ArchiveCreationFormat.cbt,
            source: native,
            destination: backend,
          ),
          isFalse,
        );
      }
    },
  );

  test('TAR output preflight includes headers and preserves default/rewrite bounds', () async {
    var sourceReads = 0, written = 0;
    ArchiveWriteEntry entry(int size) => ArchiveWriteEntry(
      path: 'large.bin',
      isDirectory: false,
      size: size,
      readChunks: () async* {
        sourceReads++;
        throw const _StopAfterPreflight();
      },
    );
    Future<void> sink(List<int> bytes) async => written += bytes.length;
    await expectLater(
      writeTarArchive([entry(256 * _mib)], sink: sink),
      throwsA(isA<ArchiveViewException>()),
    );
    await expectLater(
      writeTarArchive(
        [entry(_freshLimit)],
        sink: sink,
        maxOutputBytes: _freshLimit,
      ),
      throwsA(isA<ArchiveViewException>()),
    );
    expect(sourceReads, 0);
    expect(written, 0);
    await expectLater(
      writeTarArchive(
        [entry(_freshLimit - 1536)],
        sink: sink,
        maxOutputBytes: _freshLimit,
      ),
      throwsA(isA<_StopAfterPreflight>()),
    );
    expect(sourceReads, 1);
    expect(written, 512);
    for (final limit in [0, _freshLimit + 1]) {
      await expectLater(
        writeTarArchive([], sink: sink, maxOutputBytes: limit),
        throwsArgumentError,
      );
    }
    await expectLater(
      writeTarArchive(
        [],
        sink: sink,
        source: ArchiveRewriteInspection(container: {'package.kind': 'tar'}),
        maxOutputBytes: _freshLimit,
      ),
      throwsArgumentError,
    );
  });

  test('service rejects a header-overflowing 2 GiB selection before any source read', () async {
    final backend = _CapabilityBackend()
      ..put('/input/large.bin', [1])
      ..advertisedSizes['/input/large.bin'] = _freshLimit;
    await expectLater(
      const ArchiveCreationService().create(
        source: backend,
        destination: backend,
        files: [(await backend.stat('/input/large.bin'))!],
        destinationDirectory: '/output',
        options: const ArchiveCreationOptions(
          name: 'large.tar',
          format: ArchiveCreationFormat.tar,
          compression: ArchiveCreationCompression.none,
        ),
      ),
      throwsA(isA<ArchiveViewException>()),
    );
    expect(backend.sourceReads, 0);
    expect(backend.writes, isEmpty);
  });

  for (final format in [
    ArchiveCreationFormat.tar,
    ArchiveCreationFormat.cbt,
    ArchiveCreationFormat.tarGzip,
    ArchiveCreationFormat.zip,
    ArchiveCreationFormat.sevenZip,
  ]) {
    test(
      '${format.name} keeps the small-input limit without its eligible streaming path',
      () async {
        final backend =
            format == ArchiveCreationFormat.tar ||
                format == ArchiveCreationFormat.cbt
            ? ArchiveCreationBackend()
            : _CapabilityBackend(local: false);
        backend.put('/input/large.bin', [1]);
        backend.advertisedSizes['/input/large.bin'] = 65 * _mib;
        await expectLater(
          const ArchiveCreationService().create(
            source: backend,
            destination: backend,
            files: [(await backend.stat('/input/large.bin'))!],
            destinationDirectory: '/output',
            options: ArchiveCreationOptions(
              name: 'large${format.extension}',
              format: format,
              compression: format.defaultCompression,
            ),
          ),
          _creationError(ArchiveCreationError.tooLarge),
        );
        expect(backend.writes, isEmpty);
      },
    );
  }

  test(
    'TAR reader streams a large member lazily and retains the default read cap',
    () async {
      final source = await _VirtualTarSource.create(65 * _mib + 333);
      final archive = await openViewerArchiveSource(
        source,
        name: 'large.tar',
        maxMemberBytes: _freshLimit,
      );
      addTearDown(archive.close);
      final member = archive.members.single;
      final readsBefore = source.payloadBytesRead;
      source.largestRead = 0;
      await expectLater(
        archive.readMember(member),
        throwsA(isA<ArchiveViewException>()),
      );
      await expectLater(
        archive.openMember(member).drain<void>(),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(source.payloadBytesRead, readsBefore);
      final chunks = await archive
          .openMember(member, maxBytes: _freshLimit, chunkSize: 16384)
          .take(2)
          .toList();
      expect(chunks.map((chunk) => chunk.length), [16384, 16384]);
      expect(chunks.first, List.generate(16384, (at) => at % 251));
      expect(source.payloadBytesRead - readsBefore, 65536);
      expect(source.largestRead, lessThanOrEqualTo(65536));
      final afterCancellation = source.reads;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(
        source.reads,
        afterCancellation,
        reason: 'Cancelled streams must stop reading.',
      );
    },
  );

  test(
    'closing a streamed TAR rejects the next chunk and foreign member identity',
    () async {
      final source = await _VirtualTarSource.create(128 * 1024);
      final archive = await openViewerArchiveSource(source, name: 'closed.tar');
      addTearDown(archive.close);
      final member = archive.members.single;
      final iterator = StreamIterator(
        archive.openMember(member, chunkSize: 16384),
      );
      expect(await iterator.moveNext(), isTrue);
      await archive.close();
      await expectLater(
        iterator.moveNext(),
        throwsA(isA<ArchiveViewException>()),
      );
      await iterator.cancel();
      expect(source.closed, isTrue);

      final other = await openViewerArchiveSource(
        await _VirtualTarSource.create(128 * 1024),
        name: 'other.tar',
      );
      addTearDown(other.close);
      await expectLater(
        other.openMember(member).drain<void>(),
        throwsA(isA<ArchiveViewException>()),
      );
    },
  );

  test(
    'streaming cannot exceed the member limit chosen when TAR was opened',
    () async {
      final source = await _VirtualTarSource.create(128 * 1024);
      final archive = await openViewerArchiveSource(
        source,
        name: 'bounded.tar',
        maxMemberBytes: 1024,
      );
      addTearDown(archive.close);
      source.largestRead = 0;
      await expectLater(
        archive
            .openMember(archive.members.single, maxBytes: _freshLimit)
            .drain<void>(),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(source.largestRead, lessThanOrEqualTo(65536));
    },
  );

  group('native streamed TAR publication', () {
    late _NativeFixture fixture;
    setUp(() async => fixture = await _NativeFixture.create());
    tearDown(() async => fixture.dispose());

    for (final point in [
      'packing',
      'archive readback',
      'source recheck',
      'output hashing',
      'staging',
      'staged readback',
      'final source recheck',
    ]) {
      test(
        'cancellation during $point publishes nothing and removes staging',
        () async {
          var cancelled = false;
          await expectLater(
            fixture.createArchive(
              isCancelled: () => cancelled,
              onProgress: (progress) {
                final count = progress.completed;
                final input = fixture.size;
                final packed = fixture.archiveSize;
                cancelled = switch (point) {
                  'packing' =>
                    progress.phase == ArchiveCreationPhase.packing &&
                        count >= 65536,
                  'archive readback' =>
                    progress.phase == ArchiveCreationPhase.verifying &&
                        count >= 65536,
                  'source recheck' =>
                    progress.phase == ArchiveCreationPhase.verifying &&
                        count > input,
                  'output hashing' =>
                    progress.phase == ArchiveCreationPhase.verifying &&
                        count > 2 * input,
                  'staging' =>
                    progress.phase == ArchiveCreationPhase.saving &&
                        count >= 65536,
                  'staged readback' =>
                    progress.phase == ArchiveCreationPhase.saving &&
                        count > packed,
                  _ =>
                    progress.phase == ArchiveCreationPhase.saving &&
                        count > 2 * packed,
                };
              },
            ),
            _creationError(ArchiveCreationError.cancelled),
          );
          expect(cancelled, isTrue);
          expect(await fixture.output.exists(), isFalse);
          expect(await fixture.stagingNames(), isEmpty);
          expect(await fixture.input.length(), fixture.size);
        },
      );
    }

    for (final duringStage in [false, true]) {
      test(
        'same-size same-time source mutation ${duringStage ? 'at staging' : 'during verification'} prevents publication',
        () async {
          var changed = false;
          void change() {
            if (changed) return;
            changed = true;
            _changeBytePreservingMetadata(fixture.input, 0);
          }

          if (duringStage) {
            fixture.backend.beforeVerification = (_) async => change();
          }
          await expectLater(
            fixture.createArchive(
              onProgress: (progress) {
                if (!duringStage &&
                    progress.phase == ArchiveCreationPhase.verifying &&
                    progress.completed >= 65536) {
                  change();
                }
              },
            ),
            _creationError(ArchiveCreationError.sourceChanged),
          );
          expect(changed, isTrue);
          expect(await fixture.output.exists(), isFalse);
          expect(await fixture.stagingNames(), isEmpty);
        },
      );
    }

    test(
      'staged data corruption is detected before the exclusive commit',
      () async {
        fixture.backend.beforeVerification = (staged) async {
          _changeBytePreservingMetadata(File(staged.path!), 512);
        };
        await expectLater(
          fixture.createArchive(),
          _creationError(ArchiveCreationError.verificationFailed),
        );
        expect(await fixture.output.exists(), isFalse);
        expect(await fixture.stagingNames(), isEmpty);
      },
    );

    test(
      'a destination appearing at the native commit is never overwritten',
      () async {
        fixture.backend.beforeCommit = () async {
          await fixture.output.writeAsString('keep the late destination');
        };
        await expectLater(fixture.createArchive(), throwsA(isA<Exception>()));
        expect(
          await fixture.output.readAsString(),
          'keep the late destination',
        );
        expect(await fixture.stagingNames(), isEmpty);
      },
    );

    test(
      'cancellation after exclusive publication remains a successful creation',
      () async {
        var cancelled = false;
        fixture.backend.afterCommit = () => cancelled = true;
        final result = await fixture.createArchive(
          isCancelled: () => cancelled,
        );
        expect(cancelled, isTrue);
        expect(result.path, fixture.output.path);
        expect(await fixture.output.length(), result.bytes);
        expect(await fixture.stagingNames(), isEmpty);
      },
    );
  }, skip: !supportsNativeExclusiveRename);

  test(
    'native TAR exceeds 256 MiB and CBT exceeds 64 MiB with streamed verification and responsive progress',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'crisp-large-tar-',
      );
      final root = Directory(await temporary.resolveSymbolicLinks());
      addTearDown(() => root.delete(recursive: true));
      final input = await Directory(p.join(root.path, 'input')).create();
      final evidence = Platform.environment['CRISP_LARGE_TAR_REFERENCE_DIR'];
      final output = evidence == null
          ? await Directory(p.join(root.path, 'output')).create()
          : await Directory(evidence).create(recursive: true);
      final backend = _ObservedLocalBackend();
      final hashes = <String, String>{};
      final seeds = <String, int>{};
      for (final spec in [
        ('member-65MiB.bin', 65 * _mib + 333, 7),
        ('member-192MiB.bin', 192 * _mib + 777, 19),
      ]) {
        final file = File(p.join(input.path, spec.$1));
        hashes[file.path] = await _writePattern(file, spec.$2, spec.$3);
        seeds[file.path] = spec.$3;
      }
      await Directory(p.join(input.path, 'empty-folder')).create();
      final unicode = await Directory(p.join(input.path, '資料')).create();
      final empty = await File(p.join(unicode.path, 'empty.txt'))
          .writeAsBytes([]);
      await empty.setLastModified(DateTime.parse(_fixedTime));
      hashes[empty.path] = sha256.convert([]).toString();
      seeds[empty.path] = 0;
      final records = <Map<String, Object?>>[];

      for (final format in [
        ArchiveCreationFormat.tar,
        ArchiveCreationFormat.cbt,
      ]) {
        final selected = format == ArchiveCreationFormat.tar
            ? input.path
            : p.join(input.path, 'member-65MiB.bin');
        final expected = await _expectedMembers(selected, hashes, seeds);
        final payload = expected.fold<int>(
          0,
          (sum, member) => sum + (member['size']! as int),
        );
        final observed = _ProgressCapture();
        backend.resetObservations();
        late ArchiveCreationResult result;
        try {
          result = await const ArchiveCreationService().create(
            source: backend,
            destination: backend,
            files: [(await backend.stat(selected))!],
            destinationDirectory: output.path,
            options: ArchiveCreationOptions(
              name: 'native-large${format.extension}',
              format: format,
              compression: ArchiveCreationCompression.none,
            ),
            onProgress: observed.add,
          );
        } finally {
          observed.stop();
        }
        expect(
          result.bytes,
          greaterThan(
            format == ArchiveCreationFormat.tar ? 256 * _mib : 64 * _mib,
          ),
        );
        expect(backend.maxReadChunk, lessThanOrEqualTo(65536));
        expect(backend.maxWriteChunk, lessThanOrEqualTo(256 * 1024));
        expect(backend.stagedVerifications, 1);
        for (final member in expected.where(
          (member) => member['directory'] == false,
        )) {
          final sourcePath = p.join(
            p.dirname(selected),
            member['path']! as String,
          );
          expect(backend.reads[sourcePath], 3, reason: sourcePath);
        }
        for (final phase in [
          ArchiveCreationPhase.packing,
          ArchiveCreationPhase.verifying,
          ArchiveCreationPhase.saving,
        ]) {
          expect(observed.last[phase]!.completed, observed.last[phase]!.total);
          expect(observed.events[phase], greaterThan(5));
          expect(
            observed.timerTicks[phase] ?? 0,
            greaterThan(0),
            reason: '${phase.name} must allow UI timers.',
          );
        }
        expect(observed.last[ArchiveCreationPhase.packing]!.total, payload);
        expect(
          observed.last[ArchiveCreationPhase.verifying]!.total,
          2 * payload + result.bytes,
        );
        expect(
          observed.last[ArchiveCreationPhase.saving]!.total,
          2 * result.bytes + payload,
        );

        final archive = await openViewerArchiveSource(
          await koni.FileByteSource.open(result.path),
          name: result.path,
          maxMemberBytes: _freshLimit,
        );
        try {
          final expectedByName = {
            for (final member in expected) member['path']! as String: member,
          };
          expect(archive.members.length, expected.length);
          for (final member in archive.members) {
            final wanted = expectedByName.remove(member.name)!;
            expect(member.isFile, wanted['directory'] == false);
            expect(member.size, wanted['size']);
            if (member.isFile) {
              final digest = await sha256
                  .bind(archive.openMember(member, maxBytes: _freshLimit))
                  .single;
              expect(digest.toString(), wanted['sha256']);
            }
          }
          expect(expectedByName, isEmpty);
        } finally {
          await archive.close();
        }
        final outputHash = await sha256
            .bind(File(result.path).openRead())
            .single;
        records.add({
          'archive': p.basename(result.path),
          'bytes': result.bytes,
          'sha256': outputHash.toString(),
          'members': expected,
          'source_read_passes': 3,
          'max_source_or_staged_chunk': backend.maxReadChunk,
          'max_output_chunk': backend.maxWriteChunk,
          'progress': observed.toJson(),
        });
        // Visible in ordinary test logs; the optional manifest preserves the
        // same measured data for independent reference tools.
        stdout.writeln('STREAMED_TAR_EVIDENCE ${jsonEncode(records.last)}');
        if (format == ArchiveCreationFormat.tar) {
          // The CBT case selects only the smaller file. Release this generated
          // source before creating another private spool and staging file.
          await File(p.join(input.path, 'member-192MiB.bin')).delete();
        }
      }
      expect(
        await output
            .list()
            .where(
              (entry) => p.basename(entry.path).startsWith('.crisp-transfer-'),
            )
            .isEmpty,
        isTrue,
      );
      if (evidence != null) {
        await File(p.join(output.path, 'manifest.json')).writeAsString(
          '${const JsonEncoder.withIndent('  ').convert({'version': 1, 'cases': records})}\n',
        );
      }
    },
    skip: !supportsNativeExclusiveRename,
    timeout: const Timeout(Duration(minutes: 6)),
  );
}

class _CapabilityBackend extends ArchiveCreationBackend {
  _CapabilityBackend({
    this.local = true,
    this.provider = 'linux',
    this.download = true,
    this.upload = true,
    this.verification = true,
  });
  final bool local, download, upload, verification;
  final String provider;
  int sourceReads = 0;
  @override
  StorageReference get storageReference => StorageReference(
    kind: local ? 'local' : 'remote',
    provider: provider,
    accountKey: 'test',
  );
  @override
  StorageTransferCapabilities get capabilities => StorageTransferCapabilities(
    boundedDownload: download,
    boundedUpload: upload,
  );
  @override
  bool get supportsStagedVerification => verification;
  @override
  Stream<List<int>> readFile(FileItem file) {
    sourceReads++;
    return super.readFile(file);
  }
}

class _StopAfterPreflight implements Exception {
  const _StopAfterPreflight();
}

class _VirtualTarSource implements koni.ByteSource {
  _VirtualTarSource(this.header, this.size);
  final Uint8List header;
  final int size;
  int reads = 0, largestRead = 0, payloadBytesRead = 0;
  bool closed = false;
  static Future<_VirtualTarSource> create(int size) async {
    Uint8List? header;
    try {
      await writeTarArchive(
        [
          ArchiveWriteEntry(
            path: 'large.bin',
            isDirectory: false,
            size: size,
            readChunks: () => Stream.error(const _StopAfterPreflight()),
          ),
        ],
        sink: (bytes) async => header = Uint8List.fromList(bytes),
        maxOutputBytes: _freshLimit,
      );
    } on _StopAfterPreflight {
      // Capture only the emitted header; payload reads are generated by range.
    }
    return _VirtualTarSource(header!, size);
  }

  @override
  String get name => 'virtual.tar';
  @override
  int get length => 512 + ((size + 511) ~/ 512) * 512 + 1024;
  @override
  Future<Uint8List> read(int offset, int count) async {
    if (closed ||
        offset < 0 ||
        count < 0 ||
        offset + count > length ||
        count > 1024 * 1024) {
      throw StateError(
        'Invalid or unbounded virtual TAR read: $offset + $count.',
      );
    }
    reads++;
    if (count > largestRead) largestRead = count;
    final result = Uint8List(count);
    for (var index = 0; index < count; index++) {
      final at = offset + index;
      if (at < 512) {
        result[index] = header[at];
      } else if (at < 512 + size) {
        result[index] = (at - 512) % 251;
        payloadBytesRead++;
      }
    }
    return result;
  }

  @override
  Future<void> close() async => closed = true;
}

class _ObservedLocalBackend extends LocalOperationBackend {
  _ObservedLocalBackend() : super(LocalFileService(), isCurrent: () => true);
  final reads = <String, int>{};
  int maxReadChunk = 0, maxWriteChunk = 0, stagedVerifications = 0;
  Future<void> Function(FileItem)? beforeVerification;
  Future<void> Function()? beforeCommit;
  void Function()? afterCommit;
  void resetObservations() {
    reads.clear();
    maxReadChunk = maxWriteChunk = stagedVerifications = 0;
  }

  @override
  Stream<List<int>> readFile(FileItem file) async* {
    reads.update(file.path!, (count) => count + 1, ifAbsent: () => 1);
    await for (final chunk in super.readFile(file)) {
      if (chunk.length > maxReadChunk) maxReadChunk = chunk.length;
      yield chunk;
    }
  }

  @override
  Future<void> writePreparedFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
    Future<void> Function(FileItem)? verifyStaged,
    Future<void> Function(Map<String, dynamic>)? checkpoint,
  }) => super.writePreparedFile(
    path,
    data.map((chunk) {
      if (chunk.length > maxWriteChunk) maxWriteChunk = chunk.length;
      return chunk;
    }),
    length,
    replace: replace,
    verifyStaged: (staged) async {
      stagedVerifications++;
      await beforeVerification?.call(staged);
      await verifyStaged?.call(staged);
    },
    checkpoint: (state) async {
      if (state['phase'] == 'committing') await beforeCommit?.call();
      await checkpoint?.call(state);
      if (state['phase'] == 'committed') afterCommit?.call();
    },
  );
}

class _NativeFixture {
  _NativeFixture(this.root, this.input, this.output, this.backend);
  final Directory root;
  final File input, output;
  final _ObservedLocalBackend backend;
  final int size = 2 * _mib + 333;
  int get archiveSize => 512 + ((size + 511) ~/ 512) * 512 + 1024;
  static Future<_NativeFixture> create() async {
    final temporary = await Directory.systemTemp.createTemp(
      'crisp-tar-transaction-',
    );
    final root = Directory(await temporary.resolveSymbolicLinks());
    final input = File(p.join(root.path, 'input.bin'));
    final fixture = _NativeFixture(
      root,
      input,
      File(p.join(root.path, 'output.tar')),
      _ObservedLocalBackend(),
    );
    await _writePattern(input, fixture.size, 31);
    return fixture;
  }

  Future<ArchiveCreationResult> createArchive({
    bool Function()? isCancelled,
    void Function(ArchiveCreationProgress)? onProgress,
  }) async => const ArchiveCreationService().create(
    source: backend,
    destination: backend,
    files: [(await backend.stat(input.path))!],
    destinationDirectory: root.path,
    options: const ArchiveCreationOptions(
      name: 'output.tar',
      format: ArchiveCreationFormat.tar,
      compression: ArchiveCreationCompression.none,
    ),
    isCancelled: isCancelled,
    onProgress: onProgress,
  );
  Future<List<String>> stagingNames() async => [
    await for (final entity in root.list())
      if (p.basename(entity.path).startsWith('.crisp-transfer-')) entity.path,
  ];
  Future<void> dispose() => root.delete(recursive: true);
}

void _changeBytePreservingMetadata(File file, int offset) {
  final before = file.statSync();
  final handle = file.openSync(mode: FileMode.append);
  try {
    handle.setPositionSync(offset);
    handle.writeByteSync(255);
    handle.flushSync();
  } finally {
    handle.closeSync();
  }
  file.setLastModifiedSync(before.modified);
  expect(file.lengthSync(), before.size);
  expect(file.statSync().modified, before.modified);
}

Future<String> _writePattern(File file, int size, int seed) async {
  final block = Uint8List.fromList(
    List.generate(65536, (index) => (index + seed) % 251),
  );
  final digest = _DigestSink();
  final hash = sha256.startChunkedConversion(digest);
  final output = await file.open(mode: FileMode.write);
  try {
    for (var at = 0; at < size; at += block.length) {
      final count = size - at < block.length ? size - at : block.length;
      final chunk = Uint8List.sublistView(block, 0, count);
      hash.add(chunk);
      await output.writeFrom(chunk);
    }
  } finally {
    hash.close();
    await output.close();
  }
  await file.setLastModified(DateTime.parse(_fixedTime));
  return digest.value!;
}

class _DigestSink implements Sink<Digest> {
  String? value;
  @override
  void add(Digest digest) => value = digest.toString();
  @override
  void close() {}
}

Future<List<Map<String, Object?>>> _expectedMembers(
  String selected,
  Map<String, String> hashes,
  Map<String, int> seeds,
) async {
  final directory = await FileSystemEntity.isDirectory(selected);
  final paths = [
    selected,
    if (directory)
      ...await Directory(selected)
          .list(recursive: true, followLinks: false)
          .map((entry) => entry.path)
          .toList(),
  ]..sort();
  return [
    for (final path in paths)
      await (() async {
        final stat = await FileStat.stat(path);
        final folder = stat.type == FileSystemEntityType.directory;
        return <String, Object?>{
          'path': p
              .relative(path, from: p.dirname(selected))
              .replaceAll(p.separator, '/'),
          'directory': folder,
          'size': folder ? 0 : stat.size,
          'mode': stat.mode & 0xfff,
          'mtime': stat.modified.millisecondsSinceEpoch ~/ 1000,
          if (!folder) 'sha256': hashes[path],
          if (!folder) 'pattern_seed': seeds[path],
        };
      })(),
  ];
}

class _ProgressCapture {
  _ProgressCapture() {
    baselineRss = ProcessInfo.currentRss;
    peakRss = baselineRss;
    timer = Timer.periodic(const Duration(milliseconds: 5), (_) {
      sample();
      if (phase != null) {
        timerTicks.update(phase!, (count) => count + 1, ifAbsent: () => 1);
      }
    });
  }
  late final int baselineRss;
  late int peakRss;
  late final Timer timer;
  ArchiveCreationPhase? phase;
  final last = <ArchiveCreationPhase, ArchiveCreationProgress>{};
  final events = <ArchiveCreationPhase, int>{};
  final timerTicks = <ArchiveCreationPhase, int>{};
  void sample() {
    final current = ProcessInfo.currentRss;
    if (current > peakRss) peakRss = current;
  }

  void add(ArchiveCreationProgress progress) {
    sample();
    final previous = last[progress.phase];
    if (previous != null) {
      expect(progress.completed, greaterThanOrEqualTo(previous.completed));
      expect(progress.total, previous.total);
    }
    if (progress.total > 0) {
      expect(progress.completed, lessThanOrEqualTo(progress.total));
    }
    if (phase != null) {
      expect(progress.phase.index, greaterThanOrEqualTo(phase!.index));
    }
    phase = progress.phase;
    last[progress.phase] = progress;
    events.update(progress.phase, (count) => count + 1, ifAbsent: () => 1);
  }

  void stop() {
    timer.cancel();
    sample();
  }

  Map<String, Object?> toJson() => {
    'baseline_rss': baselineRss,
    'peak_sampled_rss': peakRss,
    'peak_rss_increase': peakRss - baselineRss,
    'phases': {
      for (final entry in last.entries)
        entry.key.name: {
          'completed': entry.value.completed,
          'total': entry.value.total,
          'events': events[entry.key],
          'timer_ticks': timerTicks[entry.key] ?? 0,
        },
    },
  };
}
