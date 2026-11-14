// SPDX-License-Identifier: MIT
// Original independent-reference and lifecycle acceptance, run on VM and JS.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import '../../lib/services/archive_types.dart';
import '../../lib/services/archive_udf_reader.dart';
import 'archive_udf_reference_data.dart';

var _checks = 0;
void check(bool condition, String message) {
  _checks++;
  if (!condition) throw StateError(message);
}

class UdfReferenceSource implements koni.ByteSource {
  UdfReferenceSource(this.bytes, {this.failAt});
  final Uint8List bytes;
  final int? failAt;
  var closed = false;
  var reads = 0;
  var requested = 0;
  var largestRequest = 0;
  final ranges = <(int, int)>[];

  @override
  int get length => bytes.length;
  @override
  String get name => 'independent.udf';
  @override
  Future<Uint8List> read(int offset, int length) async {
    if (closed) throw StateError('Read after close');
    if (failAt != null && offset >= failAt!) {
      throw StateError('Controlled source failure');
    }
    check(offset >= 0 && length >= 0 && offset <= bytes.length - length,
        'Reader requested bytes outside the image');
    reads++;
    requested += length;
    if (length > largestRequest) largestRequest = length;
    ranges.add((offset, length));
    return Uint8List.fromList(bytes.sublist(offset, offset + length));
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

Future<void> rejects(Uint8List bytes, String label) async {
  final source = UdfReferenceSource(bytes);
  var failed = false;
  try {
    final opened = await openUdfArchive(source, maxMemberBytes: 1024 * 1024);
    await opened.close();
  } on ArchiveViewException {
    failed = true;
  }
  check(failed, 'Malformed independent image accepted: $label');
  check(source.closed, 'Failure leaked source: $label');
}

Future<void> main() async {
  final results = <String, Object>{};
  for (final name in udfReferenceImages.keys) {
    final source = UdfReferenceSource(udfReferenceBytes(name));
    check(await hasUdfVolumeRecognition(source), 'UDF recognition: $name');
    check(!source.closed, 'Recognition must not close source');
    final archive = await openUdfArchive(source, maxMemberBytes: 1024 * 1024);
    check(archive.formatName == 'udf', 'Incorrect detected format');
    check(archive.members.length == 5, 'Expected four files and a directory');
    check(source.largestRequest <= 64 * 1024, 'Metadata request exceeded bound');
    check(source.ranges.every((r) => r.$1 + r.$2 <= 279 * 2048 || r.$1 >= 286 * 2048),
        'Open eagerly fetched original file contents');
    final hashes = <String, String>{};
    for (final member in archive.members.where((entry) => entry.isFile)) {
      final expected = udfReferencePayloads[member.name];
      check(expected != null, 'Unexpected file ${member.name}');
      final bytes = await archive.readMember(member);
      check(sha256.convert(bytes).toString() == expected,
          'Buffered payload mismatch $name/${member.name}');
      final streamed = <int>[];
      await for (final chunk in archive.openMember(member, chunkSize: 257)) {
        check(chunk.length <= 257, 'Stream did not preserve requested bound');
        streamed.addAll(chunk);
      }
      check(sha256.convert(streamed).toString() == expected,
          'Streamed payload mismatch $name/${member.name}');
      check(bytes.length == member.size, 'Incorrect member size');
      hashes[member.name] = expected!;
    }
    await archive.close();
    check(source.closed, 'Successful archive leaked source');
    results[name] = hashes;
  }

  final offsetBacking = Uint8List(udfReferenceBytes('derived-fragmented').length + 17);
  offsetBacking.setRange(9, offsetBacking.length - 8, udfReferenceBytes('derived-fragmented'));
  final view = Uint8List.sublistView(offsetBacking, 9, offsetBacking.length - 8);
  final before = sha256.convert(offsetBacking).toString();
  final viewArchive = await openUdfArchive(koni.MemoryByteSource(view), maxMemberBytes: 1024 * 1024);
  final payload = viewArchive.members.singleWhere((m) => m.name == 'nested/payload.bin');
  check(sha256.convert(await viewArchive.readMember(payload)).toString() == udfReferencePayloads[payload.name],
      'Offset typed-data view lost data');
  await viewArchive.close();
  check(sha256.convert(offsetBacking).toString() == before, 'Reader changed its input');

  for (final (at, label) in <(int, String)>[
    (256 * 2048 + 4, 'anchor tag checksum'),
    (32 * 2048 + 400, 'primary descriptor CRC'),
    (257 * 2048 + 420, 'file-set CRC'),
    (266 * 2048 + 180, 'file entry CRC'),
  ]) {
    final bytes = udfReferenceBytes('mastered-bridge');
    bytes[at] ^= 1;
    await rejects(bytes, label);
  }
  await rejects(Uint8List.sublistView(udfReferenceBytes('mastered-bridge'), 0, 256 * 2048), 'truncated anchor');

  final source = UdfReferenceSource(udfReferenceBytes('derived-fragmented'));
  final archive = await openUdfArchive(source, maxMemberBytes: 1024 * 1024);
  final member = archive.members.singleWhere((m) => m.name == 'nested/payload.bin');
  final readsBefore = source.reads;
  final prefix = await archive.openMember(member, chunkSize: 128).take(1).toList();
  check(prefix.length == 1 && prefix.single.length == 128, 'Cancelled prefix length');
  check(source.reads == readsBefore + 1, 'Cancellation read beyond first chunk');
  check(!source.closed, 'Cancelling one stream should retain archive source');
  await archive.close();

  final failing = UdfReferenceSource(udfReferenceBytes('mastered-bridge'), failAt: 32 * 2048);
  var failed = false;
  try {
    await openUdfArchive(failing, maxMemberBytes: 1024 * 1024);
  } on ArchiveViewException {
    failed = true;
  }
  check(failed && failing.closed, 'Source failure must close and report');
  // ignore: avoid_print
  print(jsonEncode({'groups': 11, 'checks': _checks, 'independentImages': results,
    'malformedIndependentImagesRejected': 5, 'sourceOwnership': true,
    'offsetViewsAndInputPreservation': true, 'cancelledStreamPrefixBytes': 128}));
}
