import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'archive_iso_fixtures.dart';

/// Emits separately authored section chains for inspection by an external ISO
/// reader. It does not call a CrispCloud reader or writer.
Future<void> main(List<String> args) async {
  if (args.length != 1) throw ArgumentError('Supply an output directory.');
  final directory = Directory(args.single);
  await directory.create(recursive: true);
  final records = <Map<String, Object>>[];
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
    await File('${directory.path}/$name.iso').writeAsBytes(fixture.bytes);
    records.add({
      'image': '$name.iso',
      'imageSha256': sha256.convert(fixture.bytes).toString(),
      'memberName': name == 'joliet'
          ? '複数.txt'
          : name == 'rock-ridge'
          ? 'héllo.txt'
          : 'HELLO.TXT',
      'memberBytes': fixture.expected.length,
      'memberSha256': sha256.convert(fixture.expected).toString(),
    });
  }
  await File(
    '${directory.path}/manifest.json',
  ).writeAsString('${const JsonEncoder.withIndent('  ').convert(records)}\n');
}
