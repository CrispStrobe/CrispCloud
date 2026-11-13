import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/services/archive_iso_reader.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:crypto/crypto.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'archive_iso_fixtures.dart';

/// Runs the same positional reader on the VM and actual compiled JavaScript.
Future<void> main() async {
  final hashes = <String, String>{};
  for (final name in ['primary', 'padded', 'joliet', 'rock-ridge']) {
    final fixture = IsoMultiExtentFixture(
      contents: [
        List.generate(5003, (i) => i % 251),
        List.generate(3199, (i) => 250 - i % 251),
        [1, 0, 2, 255, 3],
      ],
      joliet: name == 'joliet',
      rockRidgeName: name == 'rock-ridge' ? 'héllo.txt' : null,
      separateRecordSectors: name == 'padded',
    );
    final archive = await openIsoArchive(
      koni.MemoryByteSource(fixture.bytes),
      maxMemberBytes: 1024 * 1024,
    );
    try {
      final member = archive.members.single;
      final buffered = await archive.readMember(member);
      final streamed = <int>[
        await for (final chunk in archive.openMember(member, chunkSize: 257))
          ...chunk,
      ];
      final expected = sha256.convert(fixture.expected).toString();
      if (sha256.convert(buffered).toString() != expected ||
          sha256.convert(streamed).toString() != expected ||
          member.size != fixture.expected.length) {
        throw StateError('Multi-extent byte mismatch: $name');
      }
      hashes[name] = expected;
    } finally {
      await archive.close();
    }
  }

  final large = IsoMultiExtentFixture();
  const imageBytes = 6 * 1024 * 1024 * 1024;
  isoBoth32(large.bytes, 16 * 2048 + 80, imageBytes ~/ 2048);
  isoBoth32(large.bytes, large.recordOffsets.first + 10, 0xfffff800);
  isoBoth32(large.bytes, large.recordOffsets.last + 10, 4096);
  final source = _SparseSource(large.bytes, imageBytes);
  final archive = await openIsoArchive(source, maxMemberBytes: imageBytes);
  try {
    final member = archive.members.single;
    if (member.size != 4294969344) {
      throw StateError('Logical file size lost high bits.');
    }
    final prefix = await archive
        .openMember(member, maxBytes: imageBytes, chunkSize: 128)
        .take(2)
        .toList();
    if (prefix.length != 2 || prefix.any((chunk) => chunk.length != 128)) {
      throw StateError(
        'The large-file prefix was not streamed in bounded reads.',
      );
    }
  } finally {
    await archive.close();
  }

  var rejected = 0;
  for (final unfinished in [false, true]) {
    final fixture = IsoMultiExtentFixture();
    if (unfinished) {
      fixture.bytes[fixture.recordOffsets.last + 25] |= 0x80;
    } else {
      fixture.bytes[fixture.recordOffsets.last + 33] = 0x58;
    }
    try {
      final invalid = await openIsoArchive(
        koni.MemoryByteSource(fixture.bytes),
        maxMemberBytes: 1024,
      );
      await invalid.close();
      throw StateError('Invalid section chain was accepted.');
    } on ArchiveViewException {
      rejected++;
    }
  }
  // CLI output is the VM/JavaScript acceptance receipt.
  // ignore: avoid_print
  print(
    jsonEncode({
      'multiExtentHashes': hashes,
      'logicalSizeAbove4GiB': 4294969344,
      'largeFilePrefixBytesRead': 256,
      'malformedChainsRejected': rejected,
    }),
  );
}

class _SparseSource implements koni.ByteSource {
  _SparseSource(this.prefix, this.length);
  final Uint8List prefix;
  @override
  final int length;
  @override
  String get name => 'logical-large.iso';
  @override
  Future<Uint8List> read(int offset, int size) async {
    if (size > 2048 || offset < 0 || offset + size > length) {
      throw StateError('Unexpected sparse-source range.');
    }
    final bytes = Uint8List(size);
    if (offset < prefix.length) {
      final count = prefix.length - offset < size
          ? prefix.length - offset
          : size;
      bytes.setRange(0, count, prefix, offset);
    }
    return bytes;
  }

  @override
  Future<void> close() async {}
}
