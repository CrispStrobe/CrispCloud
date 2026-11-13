import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' as codecs;
import 'package:crisp_cloud/services/archive_created_zip_metadata.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:crisp_cloud/services/archive_write_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

final _modified = DateTime.utc(2026, 11, 13, 10, 11, 17);
final _payload = Uint8List.fromList(utf8.encode('executable payload\n' * 64));

List<ArchiveWriteEntry> _entries() => [
  ArchiveWriteEntry(
    path: 'folder',
    isDirectory: true,
    size: 0,
    mode: 0x1c0,
    modified: _modified,
  ),
  ArchiveWriteEntry(
    path: 'folder/雪.sh',
    isDirectory: false,
    size: _payload.length,
    mode: 0x1ed,
    modified: _modified,
    readChunks: () => Stream.value(_payload),
  ),
];

Uint8List _encode(
  List<ArchiveWriteEntry> entries, {
  String? password,
  int level = 6,
  bool streamed = true,
}) {
  final archive = codecs.Archive();
  for (final entry in entries) {
    final file = entry.isDirectory
        ? codecs.ArchiveFile.directory('${entry.path}/')
        : codecs.ArchiveFile.bytes(
            entry.path,
            entry.size == 0 ? Uint8List(0) : _payload,
          );
    file.mode = entry.mode ?? 0x1a4;
    file.lastModTime =
        (entry.modified ?? _modified).millisecondsSinceEpoch ~/ 1000;
    file.compression = level == 0
        ? codecs.CompressionType.none
        : codecs.CompressionType.deflate;
    archive.add(file);
  }
  return codecs.ZipEncoder(
    password: password,
    streamed: streamed,
  ).encodeBytes(archive, level: level);
}

int _central(Uint8List bytes) =>
    ByteData.sublistView(bytes).getUint32(bytes.length - 6, Endian.little);

void main() {
  for (final password in <String?>[null, 'protected 🔐']) {
    for (final level in [0, 1, 6, 9]) {
      test(
        'retains ${password == null ? 'plain' : 'AES'} level $level bytes, exact seconds and modes',
        () async {
          final entries = _entries();
          final bytes = _encode(entries, password: password, level: level);
          final before = Uint8List.fromList(bytes);
          final central = _central(bytes);
          finalizeCreatedZipMetadata(bytes, entries);
          // Every local record, compressed byte and encrypted tag is unchanged.
          expect(bytes.sublist(0, central), before.sublist(0, central));
          final archive = await koni.Archive.openBytes(
            bytes,
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
                (entry) => entry.modified!.isAtSameMomentAs(_modified),
              ),
              isTrue,
            );
            expect(archive.entries.last.isEncrypted, password != null);
            expect(await archive.readBytes(archive.entries.last), _payload);
          } finally {
            await archive.close();
          }
          final completed = Uint8List.fromList(bytes);
          finalizeCreatedZipMetadata(bytes, entries);
          expect(bytes, completed);
        },
      );
    }
  }

  test('accepts the encoder profile without data descriptors too', () async {
    final entries = _entries();
    final bytes = _encode(entries, streamed: false);
    finalizeCreatedZipMetadata(bytes, entries);
    final archive = await koni.Archive.openBytes(bytes);
    try {
      expect(archive.entries.last.posixMode, 0x1ed);
      expect(await archive.readBytes(archive.entries.last), _payload);
    } finally {
      await archive.close();
    }
  });

  for (final corruption in [
    'name',
    'local name',
    'mode',
    'type',
    'count',
    'directory bounds',
    'local bounds',
  ]) {
    test('rejects mismatched $corruption without changing any bytes', () {
      final entries = _entries();
      final bytes = _encode(entries, password: 'secret');
      final data = ByteData.sublistView(bytes);
      final central = _central(bytes);
      switch (corruption) {
        case 'name':
          bytes[central + 46] ^= 1;
        case 'local name':
          bytes[30] ^= 1;
        case 'mode':
          data.setUint32(central + 38, 0x1ff << 16 | 0x10, Endian.little);
        case 'type':
          data.setUint32(central + 38, 0xa1c0 << 16 | 0x10, Endian.little);
        case 'count':
          data.setUint16(bytes.length - 12, 3, Endian.little);
        case 'directory bounds':
          data.setUint32(bytes.length - 10, 0x7fffffff, Endian.little);
        case 'local bounds':
          data.setUint32(central + 42, bytes.length, Endian.little);
      }
      final corrupt = Uint8List.fromList(bytes);
      expect(
        () => finalizeCreatedZipMetadata(bytes, entries),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(bytes, corrupt);
    });
  }

  test(
    'rejects a captured namespace mismatch before modifying the candidate',
    () {
      final bytes = _encode(_entries());
      final before = Uint8List.fromList(bytes);
      final entries = _entries().reversed.toList();
      expect(
        () => finalizeCreatedZipMetadata(bytes, entries),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(bytes, before);
    },
  );

  for (final count in [65535, 65536]) {
    test('handles the genuine encoder ZIP64 count boundary at $count', () {
      final entries = [
        for (var i = 0; i < count; i++)
          ArchiveWriteEntry(
            path: 'f$i',
            isDirectory: false,
            size: 0,
            mode: 0x180,
            modified: _modified,
            readChunks: () => const Stream.empty(),
          ),
      ];
      final bytes = _encode(entries, level: 0);
      finalizeCreatedZipMetadata(bytes, entries);
      final data = ByteData.sublistView(bytes);
      var central = _central(bytes);
      if (count == 65536) {
        expect(central, 0xffffffff);
        final end64 = data.getUint32(bytes.length - 34, Endian.little);
        central = data.getUint32(end64 + 48, Endian.little);
      }
      expect(bytes[central + 5], 3);
      expect(data.getUint32(central + 38, Endian.little) >> 16, 0x8180);
    });
  }
}
