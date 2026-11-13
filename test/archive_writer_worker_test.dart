import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/models/archive_endpoint.dart';
import 'package:crisp_cloud/services/archive_creation_service.dart';
import 'package:crisp_cloud/services/archive_write_model.dart';
import 'package:crisp_cloud/services/archive_writer_worker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'support/archive_creation_backend.dart';
import 'support/verify_archive_writer_worker.dart';

void main() {
  test(
    'native writer worker roundtrips streamed formats and raw HFSX',
    verifyArchiveWorkerRoundTrips,
  );
  test(
    'native writer worker preserves buffered compression and protection options',
    verifyArchiveWorkerBufferedOptions,
  );
  for (final password in <String?>[null, 'worker protected ZIP']) {
    for (final method in [
      koni.ArchiveCompression.stored,
      koni.ArchiveCompression.deflate,
    ]) {
      test(
        '${password == null ? 'plain' : 'protected'} ZIP worker ${method.name} preserves modes and odd seconds',
        () async {
          final modified = DateTime.utc(2026, 11, 13, 10, 11, 17);
          final payload = Uint8List.fromList(
            List.generate(700003, (index) => (index * 37) % 251),
          );
          final entries = [
            ArchiveWriteEntry(
              path: 'folder',
              isDirectory: true,
              size: 0,
              mode: 0x1c0,
              modified: modified,
            ),
            ArchiveWriteEntry(
              path: 'folder/雪.sh',
              isDirectory: false,
              size: payload.length,
              mode: 0x1ed,
              modified: modified,
              readChunks: () => Stream.value(payload),
            ),
          ];
          final output = BytesBuilder(copy: false);
          var chunks = 0;
          await writeArchiveEntriesInWorker(
            ArchiveEndpointFormat.zip,
            entries,
            maxOutputBytes: 4 * 1024 * 1024,
            level: method == koni.ArchiveCompression.stored ? 0 : 6,
            entryCompression: method,
            password: password,
            sink: (bytes) async {
              expect(bytes.length, lessThanOrEqualTo(256 * 1024));
              chunks++;
              output.add(bytes);
            },
          );
          if (method == koni.ArchiveCompression.stored) {
            expect(chunks, greaterThan(1));
          }
          final archive = await koni.Archive.openBytes(
            output.takeBytes(),
            options: koni.ArchiveReadOptions(password: password),
          );
          try {
            expect(archive.entries.map((entry) => entry.path), [
              'folder',
              'folder/雪.sh',
            ]);
            expect(archive.entries.map((entry) => entry.posixMode), [
              0x1c0,
              0x1ed,
            ]);
            expect(
              archive.entries.every(
                (entry) => entry.modified!.isAtSameMomentAs(modified),
              ),
              isTrue,
            );
            final file = archive.entries.last;
            expect(file.isEncrypted, password != null);
            expect(await archive.readBytes(file), payload);
          } finally {
            await archive.close();
          }
        },
      );
    }
  }
  test(
    'custom packer callbacks cannot enter the background worker path',
    () async {
      final backend = ArchiveCreationBackend()..put('/input/file.txt', [1, 2]);
      final selected = (await backend.stat('/input/file.txt'))!;
      var writerCalls = 0;
      for (final format in [
        ArchiveCreationFormat.zip,
        ArchiveCreationFormat.sevenZip,
        ArchiveCreationFormat.rar,
      ]) {
        await expectLater(
          const ArchiveCreationService().create(
            source: backend,
            destination: backend,
            files: [selected],
            destinationDirectory: '/output',
            options: ArchiveCreationOptions(
              name: 'output${format.extension}',
              format: format,
              compression: format.defaultCompression,
            ),
            background: true,
            writer: ({
              required entries,
              required sink,
              required maxOutputBytes,
              isCancelled,
            }) async => writerCalls++,
          ),
          throwsA(
            isA<ArchiveCreationException>().having(
              (error) => error.code,
              'code',
              ArchiveCreationError.unsupportedOptions,
            ),
          ),
        );
      }
      expect(writerCalls, 0);
      expect(backend.writes, isEmpty);
      expect(backend.contents.keys, ['/input/file.txt']);
    },
  );
  test(
    'native writer worker retains opaque DMG preservation evidence',
    verifyArchiveWorkerPreservation,
  );
  test(
    'native writer worker pauses pulls and honors sink backpressure',
    verifyArchiveWorkerPauseAndBackpressure,
  );
  test(
    'native writer worker cancels stalled input and paused checkpoints',
    verifyArchiveWorkerCancellation,
  );
  test(
    'native writer worker rejects faults and cleans up crashed codec spools',
    verifyArchiveWorkerFailures,
  );
  for (final (kind, label) in [('zip', 'ZIP'), ('7z', '7z'), ('tgz', 'TGZ')]) {
    test(
      '$label worker streams and verifies a member beyond 2 GiB',
      () => verifyArchiveWorkerLarge(kind),
      skip: ![
        '1',
        kind,
      ].contains(Platform.environment['CRISP_ARCHIVE_WORKER_LARGE']),
      timeout: const Timeout(Duration(minutes: 20)),
    );
  }
}
