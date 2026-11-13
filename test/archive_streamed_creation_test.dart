import 'dart:async';
import 'dart:io';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/services/archive_creation_service.dart';
import 'package:crisp_cloud/services/archive_streamed_reader.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/installation_identity.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/native_file_primitives.dart';
import 'package:crisp_cloud/services/storage_transfer_contract.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/io.dart' as koni;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/archive_creation_backend.dart';

const _mib = 1024 * 1024;
final _modified = DateTime.utc(2026, 1, 2, 3, 4, 5);
const _formats = [
  ArchiveCreationFormat.zip,
  ArchiveCreationFormat.sevenZip,
  ArchiveCreationFormat.tarGzip,
  ArchiveCreationFormat.rar,
];

Matcher _creationError(ArchiveCreationError code) => throwsA(
  isA<ArchiveCreationException>().having((error) => error.code, 'code', code),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await InstallationIdentityService.instance.initialize();
  });

  test('common streaming eligibility requires native bounded storage in both directions', () {
    final native = _CapabilityBackend();
    const expectedFormats = {
      ArchiveCreationFormat.zip,
      ArchiveCreationFormat.cbz,
      ArchiveCreationFormat.kmz,
      ArchiveCreationFormat.jar,
      ArchiveCreationFormat.war,
      ArchiveCreationFormat.ear,
      ArchiveCreationFormat.sevenZip,
      ArchiveCreationFormat.cb7,
      ArchiveCreationFormat.rar,
      ArchiveCreationFormat.cbr,
      ArchiveCreationFormat.tarGzip,
    };
    for (final format in ArchiveCreationFormat.values) {
      expect(
        ArchiveCreationService.supportsStreamedCreation(
          format: format,
          source: native,
          destination: native,
          compression: format.defaultCompression,
        ),
        expectedFormats.contains(format),
        reason: format.name,
      );
    }
    for (final format in _formats) {
      for (final source in [
        _CapabilityBackend(local: false),
        _CapabilityBackend(provider: 'browser'),
        _CapabilityBackend(download: false),
        ArchiveCreationBackend(),
      ]) {
        expect(
          ArchiveCreationService.supportsStreamedCreation(
            format: format,
            source: source,
            destination: native,
            compression: format.defaultCompression,
          ),
          isFalse,
        );
      }
      for (final destination in [
        _CapabilityBackend(local: false),
        _CapabilityBackend(provider: 'browser'),
        _CapabilityBackend(download: false),
        _CapabilityBackend(upload: false),
        _CapabilityBackend(verification: false),
        ArchiveCreationBackend(),
      ]) {
        expect(
          ArchiveCreationService.supportsStreamedCreation(
            format: format,
            source: native,
            destination: destination,
            compression: format.defaultCompression,
          ),
          isFalse,
        );
      }
    }
    expect(
      ArchiveCreationService.supportsStreamedCreation(
        format: ArchiveCreationFormat.sevenZip,
        source: native,
        destination: native,
        compression: ArchiveCreationCompression.deflate,
      ),
      isFalse,
    );
  });

  for (final format in [
    ArchiveCreationFormat.zip,
    ArchiveCreationFormat.sevenZip,
  ]) {
    test(
      '${format.name} encrypted creation retains its bounded input guard',
      () async {
        final backend = _CapabilityBackend()
          ..put('/input/large.bin', [1])
          ..advertisedSizes['/input/large.bin'] = 65 * _mib;
        expect(
          ArchiveCreationService.supportsStreamedCreation(
            format: format,
            source: backend,
            destination: backend,
            password: 'private test password',
            compression: format.defaultCompression,
          ),
          isFalse,
        );
        await expectLater(
          const ArchiveCreationService().create(
            source: backend,
            destination: backend,
            files: [(await backend.stat('/input/large.bin'))!],
            destinationDirectory: '/output',
            options: ArchiveCreationOptions(
              name: 'protected${format.extension}',
              format: format,
              compression: format.defaultCompression,
              password: 'private test password',
            ),
          ),
          _creationError(ArchiveCreationError.tooLarge),
        );
        expect(backend.reads, 0);
        expect(backend.writes, isEmpty);
      },
    );
  }

  for (final format in _formats) {
    group('native ${format.label} creation', () {
      late _NativeFixture fixture;
      setUp(() async => fixture = await _NativeFixture.create(format));
      tearDown(() => fixture.dispose());

      test(
        'default compression creates valid content with native metadata',
        () async {
          final expected = await fixture.expectedMembers(includeFolder: true);
          final result = await fixture.createArchive(
            includeFolder: true,
            compression: format.defaultCompression,
          );
          await _verifyMembers(result, expected, fixture.backend);
          expect(fixture.backend.stagedVerifications, 1);
          expect(await fixture.stagingNames(), isEmpty);
        },
      );

      for (final phase in [
        ArchiveCreationPhase.packing,
        ArchiveCreationPhase.verifying,
        ArchiveCreationPhase.saving,
      ]) {
        test(
          'cancelling during ${phase.name} leaves the source and no published output',
          () async {
            final originalHash = await fixture.sourceHash();
            var cancelled = false;
            await expectLater(
              fixture.createArchive(
                isCancelled: () => cancelled,
                onProgress: (progress) {
                  if (progress.phase == phase && progress.completed >= 65536) {
                    cancelled = true;
                  }
                },
              ),
              _creationError(ArchiveCreationError.cancelled),
            );
            expect(cancelled, isTrue);
            expect(await fixture.output.exists(), isFalse);
            expect(await fixture.stagingNames(), isEmpty);
            expect(await fixture.sourceHash(), originalHash);
          },
        );
      }

      for (final duringStage in [false, true]) {
        test(
          'same-size same-time source change ${duringStage ? 'at staging' : 'after packing'} refuses publication',
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
                      progress.phase == ArchiveCreationPhase.verifying) {
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

      test('corrupt staged output is refused by independent readback before commit', () async {
        fixture.backend.beforeVerification = (staged) async {
          _changeBytePreservingMetadata(File(staged.path!), 0);
        };
        await expectLater(
          fixture.createArchive(),
          _creationError(ArchiveCreationError.verificationFailed),
        );
        expect(await fixture.output.exists(), isFalse);
        expect(await fixture.stagingNames(), isEmpty);
      });

      test(
        'an existing output is retained before reading any source',
        () async {
          await fixture.output.writeAsString('keep the existing archive');
          await expectLater(
            fixture.createArchive(),
            _creationError(ArchiveCreationError.destinationExists),
          );
          expect(
            await fixture.output.readAsString(),
            'keep the existing archive',
          );
          expect(fixture.backend.sourceReads, 0);
          expect(fixture.backend.stagedVerifications, 0);
        },
      );

      test('an output created at the exclusive commit boundary is never overwritten', () async {
        fixture.backend.beforeCommit = () async {
          await fixture.output.writeAsString('keep the concurrent archive');
        };
        await expectLater(fixture.createArchive(), throwsA(isA<Exception>()));
        expect(
          await fixture.output.readAsString(),
          'keep the concurrent archive',
        );
        expect(await fixture.stagingNames(), isEmpty);
      });

      test(
        'cancellation after publication remains a completed creation',
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
      '${format.label} creates and independently hashes real members and output above 64 MiB',
      () async {
        final fixture = await _NativeFixture.create(
          format,
          size: 65 * _mib + 4097,
        );
        addTearDown(fixture.dispose);
        final expected = await fixture.expectedMembers(includeFolder: true);
        final progress = <ArchiveCreationPhase, ArchiveCreationProgress>{};
        final result = await fixture.createArchive(
          includeFolder: true,
          // Stored blocks prove the output itself crosses the former cap, too.
          compression: ArchiveCreationCompression.none,
          onProgress: (value) {
            final previous = progress[value.phase];
            if (previous != null) {
              expect(value.completed, greaterThanOrEqualTo(previous.completed));
              expect(value.total, previous.total);
            }
            expect(
              value.completed,
              lessThanOrEqualTo(
                value.total == 0 ? value.completed : value.total,
              ),
            );
            progress[value.phase] = value;
          },
        );
        expect(result.bytes, greaterThan(64 * _mib));
        expect(await fixture.output.length(), result.bytes);
        expect(fixture.backend.maxReadChunk, lessThanOrEqualTo(65536));
        expect(fixture.backend.maxWriteChunk, lessThanOrEqualTo(256 * 1024));
        expect(fixture.backend.stagedVerifications, 1);
        for (final phase in [
          ArchiveCreationPhase.packing,
          ArchiveCreationPhase.verifying,
          ArchiveCreationPhase.saving,
        ]) {
          expect(progress[phase], isNotNull);
          expect(progress[phase]!.completed, progress[phase]!.total);
        }
        await _verifyMembers(result, expected, fixture.backend);
        expect(await fixture.stagingNames(), isEmpty);
        if (format == ArchiveCreationFormat.sevenZip) {
          // Exercise the actual default LZMA2 path with the same large source,
          // separately from the stored profile proving the output-size bound.
          await fixture.output.delete();
          final compressed = await fixture.createArchive(
            includeFolder: true,
            compression: ArchiveCreationCompression.lzma2,
          );
          await _verifyMembers(compressed, expected, fixture.backend);
          expect(await fixture.stagingNames(), isEmpty);
        }
      },
      skip: !supportsNativeExclusiveRename,
      timeout: const Timeout(Duration(minutes: 8)),
    );

    // Explicit acceptance gate, omitted from ordinary CI runs. It writes and
    // verifies real files; the source is sparse, output/staging consume disk.
    // Run with --dart-define=CRISP_RUN_2G_ARCHIVE_TESTS=true.
    test(
      '${format.label} publishes a member and archive beyond 2 GiB',
      () async {
        const length = 2 * 1024 * _mib + 4097;
        final fixture = await _NativeFixture.create(format, size: length);
        addTearDown(fixture.dispose);
        final expected = await fixture.expectedMembers();
        final result = await fixture.createArchive(
          compression: ArchiveCreationCompression.none,
        );
        expect(result.bytes, greaterThan(2 * 1024 * _mib));
        expect(await fixture.output.length(), result.bytes);
        expect(fixture.backend.maxReadChunk, lessThanOrEqualTo(65536));
        expect(fixture.backend.maxWriteChunk, lessThanOrEqualTo(256 * 1024));
        await _verifyMembers(result, expected, fixture.backend);
        expect(await fixture.stagingNames(), isEmpty);
      },
      skip:
          !supportsNativeExclusiveRename ||
          !const bool.fromEnvironment('CRISP_RUN_2G_ARCHIVE_TESTS'),
      timeout: const Timeout(Duration(minutes: 45)),
    );
  }
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
  int reads = 0;
  @override
  StorageReference get storageReference => StorageReference(
    kind: local ? 'local' : 'remote',
    provider: provider,
    accountKey: 'streamed-creation-capabilities',
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
    reads++;
    return super.readFile(file);
  }
}

class _ObservedLocalBackend extends LocalOperationBackend {
  _ObservedLocalBackend() : super(LocalFileService(), isCurrent: () => true);
  int sourceReads = 0,
      maxReadChunk = 0,
      maxWriteChunk = 0,
      stagedVerifications = 0;
  Future<void> Function(FileItem)? beforeVerification;
  Future<void> Function()? beforeCommit;
  void Function()? afterCommit;

  @override
  Stream<List<int>> readFile(FileItem file) async* {
    sourceReads++;
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
  _NativeFixture(
    this.format,
    this.root,
    this.directory,
    this.input,
    this.backend,
  );
  final ArchiveCreationFormat format;
  final Directory root, directory;
  final File input;
  final _ObservedLocalBackend backend;
  File get output => File(p.join(root.path, 'created${format.extension}'));

  static Future<_NativeFixture> create(
    ArchiveCreationFormat format, {
    int size = 2 * _mib + 37,
  }) async {
    final temporary = await Directory.systemTemp.createTemp(
      'crisp-streamed-create-',
    );
    final root = Directory(await temporary.resolveSymbolicLinks());
    final directory = await Directory(p.join(root.path, 'source')).create();
    final input = File(p.join(directory.path, 'payload.bin'));
    final handle = await input.open(mode: FileMode.write);
    try {
      await handle.truncate(size);
      await handle.writeFrom([11, 22, 33, 44]);
      await handle.setPosition(size - 4);
      await handle.writeFrom([55, 66, 77, 88]);
      await handle.flush();
    } finally {
      await handle.close();
    }
    await Directory(p.join(directory.path, 'empty')).create();
    final unicode = await Directory(p.join(directory.path, '資料')).create();
    await File(p.join(unicode.path, 'empty.txt')).writeAsBytes([]);
    final backend = _ObservedLocalBackend();
    for (final entry
        in await directory.list(recursive: true, followLinks: false).toList()) {
      if (backend.capabilities.permissions) {
        await backend.writeMetadata(
          entry.path,
          TransferMetadata(mode: entry is Directory ? 0x1e8 : 0x1a0),
        );
      }
      if (entry is File) {
        await entry.setLastModified(_modified);
      } else {
        await backend.writeMetadata(
          entry.path,
          TransferMetadata(modified: _modified),
        );
      }
    }
    await backend.writeMetadata(
      directory.path,
      TransferMetadata(modified: _modified),
    );
    return _NativeFixture(format, root, directory, input, backend);
  }

  Future<ArchiveCreationResult> createArchive({
    bool includeFolder = false,
    ArchiveCreationCompression compression = ArchiveCreationCompression.none,
    bool Function()? isCancelled,
    void Function(ArchiveCreationProgress)? onProgress,
  }) async => const ArchiveCreationService().create(
    source: backend,
    destination: backend,
    files: [(await backend.stat(includeFolder ? directory.path : input.path))!],
    destinationDirectory: root.path,
    options: ArchiveCreationOptions(
      name: p.basename(output.path),
      format: format,
      compression: compression,
    ),
    isCancelled: isCancelled,
    onProgress: onProgress,
  );

  Future<Map<String, _ExpectedMember>> expectedMembers({
    bool includeFolder = false,
  }) async {
    final selected = includeFolder ? directory.path : input.path;
    final paths = [
      selected,
      if (includeFolder)
        ...await directory
            .list(recursive: true, followLinks: false)
            .map((entry) => entry.path)
            .toList(),
    ];
    return {
      for (final path in paths)
        p
            .relative(path, from: p.dirname(selected))
            .replaceAll(p.separator, '/'): await _ExpectedMember.capture(
          path,
        ),
    };
  }

  Future<String> sourceHash() async =>
      (await sha256.bind(input.openRead()).single).toString();
  Future<List<String>> stagingNames() async => [
    await for (final item in root.list())
      if (p.basename(item.path).startsWith('.crisp-transfer-')) item.path,
  ];
  Future<void> dispose() => root.delete(recursive: true);
}

class _ExpectedMember {
  const _ExpectedMember(
    this.directory,
    this.size,
    this.mode,
    this.modified,
    this.hash,
  );
  final bool directory;
  final int size, mode;
  final DateTime modified;
  final String? hash;
  static Future<_ExpectedMember> capture(String path) async {
    final stat = await FileStat.stat(path);
    final directory = stat.type == FileSystemEntityType.directory;
    return _ExpectedMember(
      directory,
      directory ? 0 : stat.size,
      stat.mode & 0xfff,
      stat.modified,
      directory
          ? null
          : (await sha256.bind(File(path).openRead()).single).toString(),
    );
  }
}

Future<void> _verifyMembers(
  ArchiveCreationResult result,
  Map<String, _ExpectedMember> expected,
  _ObservedLocalBackend backend,
) async {
  final opened = await openStreamedArchiveSource(
    await koni.FileByteSource.open(result.path),
    name: p.basename(result.path),
    maxBytes: kArchiveStreamingLimit,
  );
  try {
    final members = {
      for (final member in opened.archive.members)
        member.name.replaceFirst(RegExp(r'/+$'), ''): member,
    };
    expect(members.keys.toSet(), expected.keys.toSet());
    expect(result.entryCount, expected.length);
    for (final entry in expected.entries) {
      final member = members[entry.key]!;
      final wanted = entry.value;
      expect(member.isFile, !wanted.directory, reason: entry.key);
      expect(member.size, wanted.size, reason: entry.key);
      expect(
        member.modified?.isAtSameMomentAs(wanted.modified),
        isTrue,
        reason: entry.key,
      );
      if (backend.capabilities.permissions) {
        expect(
          member.posixMode == null ? null : member.posixMode! & 0xfff,
          wanted.mode,
          reason: entry.key,
        );
      }
      if (member.isFile) {
        final hash = await sha256
            .bind(
              opened.archive.openMember(
                member,
                maxBytes: kArchiveStreamingLimit,
              ),
            )
            .single;
        expect(hash.toString(), wanted.hash, reason: entry.key);
      }
    }
  } finally {
    await opened.archive.close();
  }
}

void _changeBytePreservingMetadata(File file, int offset) {
  final stat = file.statSync();
  final handle = file.openSync(mode: FileMode.append);
  try {
    handle.setPositionSync(offset);
    handle.writeByteSync(254);
    handle.flushSync();
  } finally {
    handle.closeSync();
  }
  file.setLastModifiedSync(stat.modified);
  expect(file.lengthSync(), stat.size);
  expect(file.statSync().modified, stat.modified);
}
