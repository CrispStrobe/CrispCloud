import 'dart:typed_data';

import 'package:crisp_cloud/services/archive_types.dart';
import 'package:crisp_cloud/services/archive_udf_reader.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/archive_udf_fixture.dart' show udfRetag, udfPut32;
import 'support/archive_udf_reference_data.dart';
import 'support/archive_udf_web_acceptance.dart' as acceptance;

Future<void> _reject(Uint8List bytes) async {
  final source = acceptance.UdfReferenceSource(bytes);
  await expectLater(
    openUdfArchive(source, maxMemberBytes: 1024 * 1024),
    throwsA(isA<ArchiveViewException>()),
  );
  expect(source.closed, isTrue);
}

void main() {
  test(
    'independent mastered media, derived layouts and portable limits',
    acceptance.main,
  );

  test(
    'mastered file-set sequence validates its terminating descriptor CRC',
    () async {
      final bytes = udfReferenceBytes('mastered-bridge');
      bytes[258 * 2048 + 50] ^= 1;
      await _reject(bytes);
    },
  );

  test(
    'a second checksummed file-set descriptor is explicitly refused',
    () async {
      final bytes = udfReferenceBytes('derived-udf-only');
      bytes.setRange(258 * 2048, 259 * 2048, bytes, 257 * 2048);
      final second = Uint8List.sublistView(bytes, 258 * 2048, 259 * 2048);
      udfRetag(second, block: 1);
      await _reject(bytes);
    },
  );

  test('file-set extent cannot cross its mapped physical partition', () async {
    final bytes = udfReferenceBytes('mastered-bridge');
    final logical = Uint8List.sublistView(bytes, 35 * 2048, 36 * 2048);
    udfPut32(logical, 248, 1024 * 1024);
    udfRetag(logical);
    await _reject(bytes);
  });

  test(
    'exact metadata read budget succeeds and one byte less closes source',
    () async {
      final image = udfReferenceBytes('derived-fragmented');
      final baseline = acceptance.UdfReferenceSource(image);
      final first = await openUdfArchive(baseline, maxMemberBytes: 1024 * 1024);
      final budget = baseline.requested;
      await first.close();
      final exact = acceptance.UdfReferenceSource(image);
      final second = await openUdfArchive(
        exact,
        maxMemberBytes: 1024 * 1024,
        maxMetadataBytes: budget,
      );
      expect(exact.requested, budget);
      await second.close();
      final short = acceptance.UdfReferenceSource(image);
      await expectLater(
        openUdfArchive(
          short,
          maxMemberBytes: 1024 * 1024,
          maxMetadataBytes: budget - 1,
        ),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(short.closed, isTrue);
      expect(short.requested, lessThanOrEqualTo(budget - 1));
    },
  );

  test(
    'mastered nested directories share the total directory byte budget',
    () async {
      final bytes = udfReferenceBytes('mastered-bridge');
      final source = acceptance.UdfReferenceSource(bytes);
      await expectLater(
        openUdfArchive(
          source,
          maxMemberBytes: 1024 * 1024,
          maxDirectoryBytes: 335,
        ),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(source.closed, isTrue);
    },
  );

  test('entry budget counts directory rows as well as regular files', () async {
    final source = acceptance.UdfReferenceSource(
      udfReferenceBytes('mastered-bridge'),
    );
    await expectLater(
      openUdfArchive(source, maxMemberBytes: 1024 * 1024, maxEntries: 4),
      throwsA(isA<ArchiveViewException>()),
    );
    expect(source.closed, isTrue);
  });

  test(
    'caller cannot bypass the configured member cap after listing',
    () async {
      final source = acceptance.UdfReferenceSource(
        udfReferenceBytes('derived-fragmented'),
      );
      final archive = await openUdfArchive(source, maxMemberBytes: 16);
      final member = archive.members.singleWhere(
        (entry) => entry.name == 'hello.txt',
      );
      final reads = source.reads;
      await expectLater(
        archive.readMember(member, maxBytes: 1024),
        throwsA(isA<ArchiveViewException>()),
      );
      await expectLater(
        archive.openMember(member, maxBytes: 1024).toList(),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(source.reads, reads);
      await archive.close();
    },
  );
}
