import 'dart:typed_data';

import 'package:archive/archive.dart' as ar;
import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/models/archive_endpoint.dart';
import 'package:crisp_cloud/services/archive_endpoint_policy.dart';
import 'package:crisp_cloud/services/archive_format_registry.dart';
import 'package:crisp_cloud/services/archive_service.dart';
import 'package:crisp_cloud/services/archive_streamed_reader.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/archive_viewer_streaming.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'support/archive_udf_reference_data.dart';
import 'support/dmg_fixture.dart';

void main() {
  test(
    'UDF extension is recognized without enabling create or rewrite controls',
    () {
      final capability = archiveFormatForName('contents.UDF')!;
      expect(capability.id, 'udf');
      expect(capability.canCreate, isFalse);
      expect(capability.canModify, isFalse);
      expect(ArchiveService.isArchive('contents.udf'), isTrue);
      expect(isStreamedArchiveViewerName('contents.udf'), isTrue);
      expect(
        matchesStreamedArchiveViewerSignature('contents.udf', const []),
        isTrue,
      );
    },
  );
  for (final fixture in udfReferenceImages.keys) {
    for (final name in ['disc.iso', 'disc.udf', 'misleading.dmg']) {
      test(
        '$fixture routes as UDF through $name and preserves its read-only policy',
        () async {
          final bytes = udfReferenceBytes(fixture);
          final archive = await openViewerArchive(
            bytes,
            name: name,
            maxMemberBytes: kArchiveStreamingLimit,
          );
          expect(archive.formatName, 'udf');
          expect(archive.maxStreamingMemberBytes, kArchiveStreamingLimit);
          for (final payload in udfReferencePayloads.entries) {
            final member = archive.members.singleWhere(
              (m) => m.name == payload.key,
            );
            expect(
              sha256.convert(await archive.readMember(member)).toString(),
              payload.value,
            );
          }
          final policy = await ArchiveEndpointPolicy.inspect(
            bytes,
            name,
            archive,
            null,
          );
          expect(policy.format, ArchiveEndpointFormat.readOnly);
          expect(policy.reason, contains('UDF'));
          await archive.close();
        },
      );
    }
  }
  for (final name in ['disc.iso', 'disc.udf']) {
    test(
      'native streamed $name preserves UDF namespace and refuses ISO rewrite',
      () async {
        final opened = await openStreamedArchiveSource(
          koni.MemoryByteSource(udfReferenceBytes('mastered-bridge')),
          name: name,
          inspectIsoForRewrite: true,
        );
        expect(opened.archive.formatName, 'udf');
        expect(opened.policy.format, ArchiveEndpointFormat.readOnly);
        expect(opened.policy.reason, contains('UDF'));
        expect(opened.archive.maxStreamingMemberBytes, kArchiveStreamingLimit);
        await opened.archive.close();
      },
    );
  }
  test(
    'recognized corrupt UDF on a bridge cannot silently fall back to ISO',
    () async {
      final bytes = udfReferenceBytes('mastered-bridge');
      bytes[256 * 2048 + 4] ^= 1;
      await expectLater(
        openViewerArchive(bytes, name: 'disc.iso'),
        throwsA(isA<ArchiveViewException>()),
      );
      await expectLater(
        openStreamedArchiveSource(
          koni.MemoryByteSource(bytes),
          name: 'disc.iso',
        ),
        throwsA(isA<ArchiveViewException>()),
      );
    },
  );
  test(
    'an ordinary ZIP signature takes priority over a misleading UDF suffix',
    () async {
      final data = Uint8List.fromList(
        ar.ZipEncoder().encode(
          ar.Archive()..addFile(ar.ArchiveFile.bytes('note.txt', [1, 2, 3])),
        ),
      );
      final archive = await openViewerArchive(data, name: 'not.udf');
      await expectLater(
        openStreamedArchiveSource(koni.MemoryByteSource(data), name: 'not.udf'),
        throwsA(predicate(useBoundedArchiveViewerFallback)),
      );
      expect(archive.formatName, 'zip');
      expect(await archive.readMember(archive.members.single), [1, 2, 3]);
      await archive.close();
    },
  );
  test('UDF partition browsing flows through an LZFSE DMG without losing raw partition access', () async {
    final image = udfReferenceBytes('derived-udf-only');
    final dmg = DmgFixture(image, method: 0x80000007, chunkBytes: 32768);
    final archive = await openViewerArchive(dmg.bytes, name: 'disc.dmg');
    final partition = archive.members.singleWhere(
      (m) => m.name.startsWith('partitions/'),
    );
    expect(partition.name, endsWith('.udf'));
    expect(await archive.readMember(partition), image);
    for (final payload in udfReferencePayloads.entries) {
      final member = archive.members.singleWhere(
        (m) =>
            m.name.startsWith('files/') && m.name.endsWith('/${payload.key}'),
      );
      expect(
        sha256.convert(await archive.readMember(member)).toString(),
        payload.value,
      );
    }
    await archive.close();
  });
}
