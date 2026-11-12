import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

// Independently generated reference samples. GNU ar: binutils 2.44, `ar rcD`,
// files a-very-long-file-name.txt and short. CPIO and XAR: libarchive 3.7.4,
// archive_write_set_format_cpio_newc / archive_write_set_format_xar; directory
// docs (0755), docs/hello.txt (0640), mtime 1700000000, nlink 1. The bytes are
// embedded so tests do not depend on host tools or native libraries.
Uint8List referenceGnuAr() => base64Decode(
  'ITxhcmNoPgovLyAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAyOCAgICAgICAgYAphLXZlcnktbG9uZy1maWxlLW5hbWUudHh0LwoKLzAgICAgICAgICAgICAgIDAgICAgICAgICAgIDAgICAgIDAgICAgIDY0NCAgICAgMjIgICAgICAgIGAKR05VIGxvbmcgbmFtZSBmaXh0dXJlCnNob3J0LyAgICAgICAgICAwICAgICAgICAgICAwICAgICAwICAgICA2NDQgICAgIDMgICAgICAgICBgCm9kZAo=',
);
Uint8List referenceNewc() => base64Decode(
  'MDcwNzAxMDAwMDAwMDAwMDAwNDFlZDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMTY1NTNmMTAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDA1MDAwMDAwMDBkb2NzAAAwNzA3MDEwMDAwMDAwMDAwMDA4MWEwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAxNjU1M2YxMDAwMDAwMDAxZTAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMGYwMDAwMDAwMGRvY3MvaGVsbG8udHh0AAAAAEluZGVwZW5kZW50IGNvbnRhaW5lciBmaXh0dXJlCgAAMDcwNzAxMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMTAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDBiMDAwMDAwMDBUUkFJTEVSISEhAAAAAA==',
);
Uint8List referenceXar() => base64Decode(
  'eGFyIQAcAAEAAAAAAAABpAAAAAAAAAOUAAAAAXicjZPNcqwgEIX3eQrKvUEQZWaKMbv7BJNNdgQapeLPlJKUk6e/gjJlanKr7oruAxw+u1vxMnct+oJxskN/TshzliDo1aBtX5+T18uf9JC8VE9ilmP1hIQb1LIgoUaQbrmROttBRTNapoSkhF5IecrIiVGBfx4JlxpQH9NnhyZ3a+GcTI0kid9BYjBmAldlAm9RUCf77c0FDoG3wNEjZMa2gKxesDebXi5P6UFNAocwiO52XUQ7gnLDeBM45GHH9oMG/+gaBK0LEi8Kgbu7+Gm1P+aXkNdrXse8i2XIQxnYhdITyU80e1tc4vfveOnKuwE30LbDs5vdjnrD9jd2xL8iR+aSZTvmB+gH6v/FRkJLJ9cQiRb62jVVXgq8hdvG1jj6s4exi/mui16MMxZnQV6vrVVhYPCc1t/2muB4Vo6qsV+g098HiGc650RTLQnlkgNn+YGpAhQwxkzJDOXqUMiljg9Gd5rZjVK5fz5BzDEryOKnGHk31LyX8sg1gNY5ywtKCQfCODECPzptNcT3Igrsu7qO8xYtLfY/lsDhN/sLvrkK0FHsdWehZGrY5g/HQcLhEusSdz83eJzzzEtJLUgFEnklCsn5eSWJmXmpRQppmRUlpUWpXAC1PguDeJyNk81yrCAQhfd5Csq9QRBlZoo=',
);

class PackageFixtureEntry {
  const PackageFixtureEntry(
    this.name,
    this.bytes, {
    this.mode = 0x81a4,
    this.links = 1,
    this.checksum,
  });
  final String name;
  final List<int> bytes;
  final int mode, links;
  final int? checksum;
}

/// Test constructor for controlled AR header/payload mutations. [bsdNames]
/// uses the BSD inline UTF-8 name encoding rather than a GNU name table.
Uint8List arFixture(
  List<PackageFixtureEntry> entries, {
  bool bsdNames = false,
}) {
  final output = BytesBuilder()..add(ascii.encode('!<arch>\n'));
  for (final entry in entries) {
    final nameBytes = utf8.encode(entry.name);
    final payload = bsdNames ? [...nameBytes, ...entry.bytes] : entry.bytes;
    final identifier = bsdNames ? '#1/${nameBytes.length}' : '${entry.name}/';
    if (identifier.length > 16) {
      throw ArgumentError('Use BSD names for this fixture.');
    }
    output.add(
      ascii.encode(
        '${identifier.padRight(16)}${'1700000000'.padRight(12)}'
        '${'0'.padRight(6)}${'0'.padRight(6)}'
        '${entry.mode.toRadixString(8).padRight(8)}'
        '${payload.length.toString().padRight(10)}`\n',
      ),
    );
    output.add(payload);
    if (payload.length.isOdd) output.addByte(10);
  }
  return output.takeBytes();
}

Uint8List cpioFixture(
  List<PackageFixtureEntry> entries, {
  bool crc = false,
  bool trailer = true,
}) {
  final output = BytesBuilder();
  var inode = 1;
  for (final entry in [
    ...entries,
    if (trailer) const PackageFixtureEntry('TRAILER!!!', [], mode: 0),
  ]) {
    final name = [...utf8.encode(entry.name), 0];
    final checksum =
        entry.checksum ??
        (crc
            ? entry.bytes.fold<int>(0, (sum, byte) => (sum + byte) & 0xffffffff)
            : 0);
    final fields = [
      inode++,
      entry.mode,
      0,
      0,
      entry.links,
      1700000000,
      entry.bytes.length,
      0,
      0,
      0,
      0,
      name.length,
      checksum,
    ];
    output.add(
      ascii.encode(
        '${crc ? '070702' : '070701'}'
        '${fields.map((f) => f.toRadixString(16).padLeft(8, '0')).join()}',
      ),
    );
    output.add(name);
    while (output.length % 4 != 0) {
      output.addByte(0);
    }
    output.add(entry.bytes);
    while (output.length % 4 != 0) {
      output.addByte(0);
    }
  }
  return output.takeBytes();
}

Uint8List xarFixture(String tocXml, {List<int> heap = const []}) {
  final toc = utf8.encode(
    '<?xml version="1.0" encoding="UTF-8"?><xar><toc>$tocXml</toc></xar>',
  );
  final packed = const ZLibEncoder().encode(toc);
  final header = ByteData(28)
    ..setUint32(0, 0x78617221)
    ..setUint16(4, 28)
    ..setUint16(6, 1)
    ..setUint64(8, packed.length)
    ..setUint64(16, toc.length)
    ..setUint32(24, 0);
  return Uint8List.fromList([
    ...header.buffer.asUint8List(),
    ...packed,
    ...heap,
  ]);
}

Uint8List xarMemberFixture(
  List<int> bytes, {
  String name = 'hello.txt',
  String encoding = 'application/octet-stream',
  int? declaredSize,
  bool invalidChecksum = false,
}) {
  final packed = switch (encoding) {
    'application/x-gzip' || 'application/zlib' => const ZLibEncoder().encode(bytes),
    'application/x-bzip2' => BZip2Encoder().encode(bytes),
    'application/x-xz' => XZEncoder().encode(bytes),
    _ => bytes,
  };
  return xarFixture(
    '<file id="1"><name>${const HtmlEscape().convert(name)}</name><type>file</type>'
    '<data><size>${declaredSize ?? bytes.length}</size><length>${packed.length}</length>'
    '<offset>0</offset><encoding style="$encoding"/>'
    '<archived-checksum style="sha256">${sha256.convert(packed)}</archived-checksum>'
    '<extracted-checksum style="sha256">${invalidChecksum ? '0' * 64 : sha256.convert(bytes)}</extracted-checksum>'
    '</data></file>',
    heap: packed,
  );
}
