import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/services/checksum_service.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';

import 'support/workflow_fake_client.dart';

void main() {
  test('incremental SHA-1, SHA-512 and CRC32 match standard vectors', () {
    for (final vector in [
      (
        ChecksumAlgorithm.sha1,
        'abc',
        'a9993e364706816aba3e25717850c26c9cd0d89d',
      ),
      (
        ChecksumAlgorithm.sha512,
        'abc',
        'ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f',
      ),
      (ChecksumAlgorithm.crc32, '123456789', 'cbf43926'),
    ]) {
      final accumulator = ChecksumAccumulator(vector.$1);
      for (final byte in vector.$2.codeUnits) {
        accumulator.add([byte]);
      }
      expect(accumulator.finish(), vector.$3);
      expect(accumulator.finish(), vector.$3);
    }
  });

  test('GNU manifests round-trip exact whitespace and escaped filenames', () {
    const digest = '900150983cd24fb0d6963f7d28e17f72';
    final names = [
      ' two  spaces .txt ',
      'back\\slash.txt',
      'line\nbreak.txt',
      'carriage\rreturn.txt',
    ];
    final text = ChecksumService.formatManifest(
      names.map((name) => ChecksumManifestEntry(name, digest)),
      ChecksumAlgorithm.md5,
    );
    expect(
      ChecksumService.parseManifest(
        text,
        ChecksumAlgorithm.md5,
      ).map((entry) => entry.filename),
      names,
    );
    expect(
      ChecksumService.parseManifest(
        '$digest *binary name.txt\n',
        ChecksumAlgorithm.md5,
      ).single.filename,
      'binary name.txt',
    );
    expect(
      () => ChecksumService.parseManifest(
        'malformed line',
        ChecksumAlgorithm.md5,
      ),
      throwsFormatException,
    );
    expect(
      () => ChecksumService.parseManifest(
        '\\$digest  bad\\xname\n',
        ChecksumAlgorithm.md5,
      ),
      throwsFormatException,
    );
  });

  test('captured cloud manifests preserve relative paths and verify SHA-1 correctly', () async {
    final client = WorkflowFakeClient()
      ..put('/one/same name.txt', 'abc'.codeUnits)
      ..put('/two/same name.txt', 'second'.codeUnits);
    final backend = CloudOperationBackend(
      client,
      isCurrent: () => client.current,
    );
    final output = await ChecksumService.createManifest(
      backend,
      [
        (await backend.stat('/one/same name.txt'))!,
        (await backend.stat('/two/same name.txt'))!,
      ],
      baseDirectory: '/',
      outputName: 'files.sha1',
      algorithm: ChecksumAlgorithm.sha1,
    );
    expect(
      utf8.decode(client.files[output]!),
      contains('a9993e364706816aba3e25717850c26c9cd0d89d  one/same name.txt'),
    );
    final results = await ChecksumService.verifyManifest(
      backend,
      (await backend.stat(output))!,
    );
    expect(results.every((result) => result.ok), true);
    client.put('/two/same name.txt', [1]);
    final changed = await ChecksumService.verifyManifest(
      backend,
      (await backend.stat(output))!,
    );
    expect(changed.map((result) => result.ok), [true, false]);
    await expectLater(
      ChecksumService.createManifest(
        backend,
        [(await backend.stat('/one/same name.txt'))!],
        baseDirectory: '/',
        outputName: 'files.sha1',
        algorithm: ChecksumAlgorithm.sha1,
      ),
      throwsStateError,
    );
  });

  test('SFV supports exact spaces and refuses ambiguous line breaks', () {
    final text = ChecksumService.formatManifest([
      const ChecksumManifestEntry('space  name.txt ', 'cbf43926'),
      const ChecksumManifestEntry(';comment name.txt', 'cbf43926'),
    ], ChecksumAlgorithm.crc32);
    expect(
      ChecksumService.parseManifest(
        text,
        ChecksumAlgorithm.crc32,
      ).map((entry) => entry.filename),
      ['space  name.txt ', './;comment name.txt'],
    );
    expect(
      () => ChecksumService.formatManifest([
        const ChecksumManifestEntry('bad\nname', 'cbf43926'),
      ], ChecksumAlgorithm.crc32),
      throwsFormatException,
    );
  });

  test(
    'malicious, duplicate and malformed manifest paths are rejected',
    () async {
      final client = WorkflowFakeClient()..put('/folder/a', [1]);
      final backend = CloudOperationBackend(client, isCurrent: () => true);
      final hash = ChecksumService.md5Hash(Uint8List.fromList([1]));
      for (final text in [
        '$hash  ../a\n',
        '$hash  /a\n',
        '$hash  C:/a\n',
        '$hash  a\n$hash  ./a\n',
        'junk\n',
      ]) {
        client.put('/folder/test.md5', utf8.encode(text));
        await expectLater(
          ChecksumService.verifyManifest(
            backend,
            (await backend.stat('/folder/test.md5'))!,
          ),
          throwsFormatException,
        );
      }
    },
  );

  test('stream cancellation, account loss and changed files cannot produce checksums', () async {
    final client = WorkflowFakeClient()
      ..put('/data', List.generate(64, (i) => i));
    final backend = CloudOperationBackend(
      client,
      isCurrent: () => client.current,
    );
    var cancelled = false;
    final file = (await backend.stat('/data'))!;
    await expectLater(
      ChecksumService.hashFile(
        backend,
        file,
        ChecksumAlgorithm.sha256,
        isCancelled: () => cancelled,
        onProgress: (_, _) => cancelled = true,
      ),
      throwsA(isA<FileIntegrityCancelled>()),
    );
    await expectLater(
      ChecksumService.hashFile(
        backend,
        file,
        ChecksumAlgorithm.sha256,
        onProgress: (_, _) => client.current = false,
      ),
      throwsStateError,
    );
    client.current = true;
    await expectLater(
      ChecksumService.hashFile(
        backend,
        file,
        ChecksumAlgorithm.sha256,
        onProgress: (_, _) => client.put('/data', [1]),
      ),
      throwsStateError,
    );
  });
}
