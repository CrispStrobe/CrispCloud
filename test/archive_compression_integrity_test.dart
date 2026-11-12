import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/services/archive_viewer_service.dart';

void main() {
  final payload = utf8.encode('A complete payload, never a partial success.');
  final compressed = <String, Uint8List>{
    'gz': Uint8List.fromList(const GZipEncoder().encode(payload)),
    'bz2': Uint8List.fromList(BZip2Encoder().encode(payload)),
    'xz': Uint8List.fromList(XZEncoder().encode(payload)),
    'zst': Uint8List.fromList(ZstdEncoder().encode(payload)),
  };

  for (final entry in compressed.entries) {
    final name = 'message.txt.${entry.key}';
    test('${entry.key}: verified complete single-file decode', () {
      final decoded = decompressSingleFile(entry.value, name);
      expect(decoded.innerName, 'message.txt');
      expect(decoded.data, payload);
    });

    test('${entry.key}: truncated single-file decode is an error', () {
      final truncated = entry.value.sublist(0, entry.value.length - 5);
      expect(
        () => decompressSingleFile(truncated, name),
        throwsA(isA<ArchiveViewException>()),
      );
    });

    test('${entry.key}: decompressed output remains bounded', () {
      expect(
        () => decompressSingleFile(entry.value, name, maxBytes: 8),
        throwsA(isA<ArchiveViewException>()),
      );
    });

    if (entry.key != 'gz') {
      test('${entry.key}: viewer refuses a truncated container', () async {
        await expectLater(
          openViewerArchive(
            entry.value.sublist(0, entry.value.length - 5),
            name: name,
          ),
          throwsA(isA<ArchiveViewException>()),
        );
      });
    }
  }

  test('viewer checks actual output length from a reader', () async {
    const member = ViewerArchiveMember(
      name: 'understated.txt',
      size: 1,
      isFile: true,
      isEncrypted: false,
      pathEscapedRoot: false,
      index: 0,
    );
    final archive = ViewerArchive.reader(
      formatName: 'test',
      members: [member],
      read: (_, __) async => Uint8List(16),
      close: () async {},
    );
    addTearDown(archive.close);
    await expectLater(
      archive.readMember(member, maxBytes: 8),
      throwsA(isA<ArchiveViewException>()),
    );
  });
}
