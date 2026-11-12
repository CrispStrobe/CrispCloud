import 'dart:async';
import 'dart:typed_data';

import 'package:crisp_cloud/models/archive_endpoint.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/archive_container_publisher.dart';
import 'package:crisp_cloud/services/archive_publication_journal.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/installation_identity.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/archive_endpoint_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await InstallationIdentityService.instance.initialize();
  });

  final original = Uint8List.fromList(List.generate(8197, (i) => i % 251));
  final candidate = Uint8List.fromList(
    List.generate(1024 * 1024 + 27, (i) => (i * 17) % 253),
  );
  late _ChunkObservingBackend backend;
  late MemoryFileCollectionStorage storage;
  late ArchivePublicationJournal journal;
  late ArchiveContainerPublisher publisher;
  setUp(() {
    backend = _ChunkObservingBackend()..put('/out/stream.zip', original);
    storage = MemoryFileCollectionStorage();
    journal = ArchivePublicationJournal(storage: storage);
    publisher = ArchiveContainerPublisher(backend, journal);
  });

  Future<ArchivePublicationReceipt> publish({
    Stream<List<int>> Function()? openRead,
    int? length,
    String? hash,
    bool Function()? isCancelled,
    ArchivePublicationRecord? retry,
  }) async => publisher.publishStream(
    original: (await backend.stat('/out/stream.zip'))!,
    originalSha256: sha256.convert(original).toString(),
    length: length ?? candidate.length,
    candidateSha256: hash ?? sha256.convert(candidate).toString(),
    openRead: openRead ?? () => Stream.value(candidate),
    isCancelled: isCancelled,
    retry: retry,
  );

  void expectOriginalRetained() {
    expect(backend.files['/out/stream.zip'], original);
    expect(
      backend.mutations.where((mutation) => mutation.startsWith('move:')),
      isEmpty,
    );
    expect(publisher.activeRecord?.candidate, isNull);
  }

  test(
    'streamed publication uses bounded chunks and verified recovery receipt',
    () async {
      var opened = 0;
      final phases = <ArchivePublicationPhase>[];
      final receipt = await publisher.publishStream(
        original: (await backend.stat('/out/stream.zip'))!,
        originalSha256: sha256.convert(original).toString(),
        length: candidate.length,
        candidateSha256: sha256.convert(candidate).toString(),
        openRead: () async* {
          opened++;
          // A large provider-owned chunk is split before the upload sees it.
          yield candidate;
        },
        onPhase: phases.add,
      );
      expect(opened, 1);
      expect(backend.uploadedChunks, greaterThan(1));
      expect(backend.largestUploadChunk, lessThanOrEqualTo(256 * 1024));
      expect(backend.uploadedBytes, candidate.length);
      expect(backend.declaredLength, candidate.length);
      expect(backend.files.keys, ['/out/stream.zip']);
      expect(backend.files['/out/stream.zip'], candidate);
      expect(backend.modes['/out/stream.zip'], 0x180);
      expect(receipt.record.candidateBytes, candidate.length);
      expect(receipt.record.phase, ArchivePublicationPhase.complete);
      expect(receipt.cleanupPending, isFalse);
      expect(phases, contains(ArchivePublicationPhase.candidateWritten));
      expect(phases, contains(ArchivePublicationPhase.backedUp));
      expect(phases, contains(ArchivePublicationPhase.published));
      await publisher.verifyReceipt(receipt);
      final restarted = ArchivePublicationJournal(storage: storage);
      await restarted.initialize();
      expect(
        restarted.records.single.candidateSha256,
        receipt.record.candidateSha256,
      );
    },
  );

  for (final failure in ['short', 'growing', 'changed', 'invalid-byte']) {
    test('$failure candidate is rejected before any original move', () async {
      final bytes = Uint8List.fromList(List.generate(17, (i) => i));
      final chunks = switch (failure) {
        'short' => <List<int>>[bytes.sublist(0, 16)],
        'growing' => <List<int>>[
          bytes,
          [17],
        ],
        'changed' => <List<int>>[List<int>.filled(17, 8)],
        _ => <List<int>>[List<int>.filled(17, 256)],
      };
      await expectLater(
        publish(
          length: bytes.length,
          hash: sha256.convert(bytes).toString(),
          openRead: () => Stream.fromIterable(chunks),
        ),
        throwsA(isA<ArchivePublicationException>()),
      );
      expectOriginalRetained();
      expect(backend.mutations, isEmpty);
      expect(journal.records.single.phase, ArchivePublicationPhase.prepared);
    });
  }

  test(
    'same-size staged corruption cannot publish a valid source stream',
    () async {
      backend.before = (action, path, destination) {
        if (action == 'write') {
          backend.put('$path.upload', Uint8List(candidate.length));
        }
      };
      await expectLater(publish(), throwsA(isA<ArchivePublicationException>()));
      expectOriginalRetained();
      expect(backend.uploadedBytes, candidate.length);
    },
  );

  test(
    'cancellation during upload closes the source and keeps the original',
    () async {
      var cancelled = false;
      var closed = false;
      await expectLater(
        publish(
          openRead: () async* {
            try {
              yield candidate.sublist(0, 65536);
              cancelled = true;
              yield candidate.sublist(65536);
            } finally {
              closed = true;
            }
          },
          isCancelled: () => cancelled,
        ),
        throwsA(isA<ArchivePublicationException>()),
      );
      expect(closed, isTrue);
      expect(backend.uploadedBytes, 65536);
      expectOriginalRetained();
      expect(backend.mutations, isEmpty);
    },
  );

  test(
    'multi-gigabyte candidate is consumed lazily and can stop after one chunk',
    () async {
      const length = 2 * 1024 * 1024 * 1024 + 4096;
      var opened = false;
      var cancelled = false;
      await expectLater(
        publish(
          length: length,
          // Cancellation happens before a full fingerprint is evaluated; no
          // multi-gigabyte buffer or misleading successful receipt is created.
          hash: '0' * 64,
          openRead: () async* {
            opened = true;
            yield Uint8List(65536);
            cancelled = true;
            yield Uint8List(65536);
          },
          isCancelled: () => cancelled,
        ),
        throwsA(isA<ArchivePublicationException>()),
      );
      expect(opened, isTrue);
      expect(backend.declaredLength, length);
      expect(backend.uploadedBytes, 65536);
      expect(publisher.activeRecord?.candidateBytes, length);
      expectOriginalRetained();
      final restarted = ArchivePublicationJournal(storage: storage);
      await restarted.initialize();
      expect(restarted.records.single.candidateBytes, length);
    },
  );

  test(
    'retained verified candidate retries without reopening its spool',
    () async {
      var failInstallation = true;
      backend.before = (action, path, destination) {
        if (failInstallation &&
            action == 'move' &&
            path.endsWith('.candidate')) {
          failInstallation = false;
          throw StateError('Interrupted candidate install.');
        }
      };
      await expectLater(publish(), throwsA(isA<ArchivePublicationException>()));
      expect(backend.files['/out/stream.zip'], original);
      final retry = publisher.activeRecord!;
      expect(retry.phase, ArchivePublicationPhase.restored);
      final receipt = await publish(
        retry: retry,
        openRead: () => throw StateError('Verified staging must be reusable.'),
      );
      expect(receipt.record.phase, ArchivePublicationPhase.complete);
      expect(backend.files.keys, ['/out/stream.zip']);
      expect(backend.files['/out/stream.zip'], candidate);
    },
  );

  test('invalid length or fingerprint fails before opening candidate or journaling', () async {
    var opened = false;
    for (final length in [
      -1,
      ArchivePublicationRecord.maximumContainerBytes + 1,
    ]) {
      await expectLater(
        publish(
          length: length,
          openRead: () {
            opened = true;
            return const Stream.empty();
          },
        ),
        throwsFormatException,
      );
    }
    await expectLater(
      publish(hash: 'not-a-fingerprint'),
      throwsFormatException,
    );
    expect(opened, isFalse);
    expect(backend.mutations, isEmpty);
    expect(journal.records, isEmpty);
    expect(backend.files['/out/stream.zip'], original);
  });

  test(
    'stream failure retains a reviewable intent without deleting the original',
    () async {
      await expectLater(
        publish(
          openRead: () async* {
            yield candidate.sublist(0, 12);
            throw const FileOperationCancelled();
          },
        ),
        throwsA(isA<ArchivePublicationException>()),
      );
      expectOriginalRetained();
      expect(journal.records.single.phase, ArchivePublicationPhase.prepared);
    },
  );
}

class _ChunkObservingBackend extends ArchiveEndpointTestBackend {
  int uploadedChunks = 0;
  int uploadedBytes = 0;
  int largestUploadChunk = 0;
  int? declaredLength;

  @override
  Future<void> writePreparedFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
    Future<void> Function(FileItem)? verifyStaged,
    Future<void> Function(Map<String, dynamic>)? checkpoint,
  }) {
    declaredLength = length;
    Stream<List<int>> observed() async* {
      await for (final chunk in data) {
        uploadedChunks++;
        uploadedBytes += chunk.length;
        if (chunk.length > largestUploadChunk) {
          largestUploadChunk = chunk.length;
        }
        yield chunk;
      }
    }

    return super.writePreparedFile(
      path,
      observed(),
      length,
      replace: replace,
      verifyStaged: verifyStaged,
      checkpoint: checkpoint,
    );
  }
}
