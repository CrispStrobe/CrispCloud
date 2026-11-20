import 'package:flutter/services.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

/// A licensed repository face with synthetic family-name metadata. Outlines,
/// style and metrics remain those of Liberation, never a proprietary font.
Future<Uint8List> installedFontFixture(
  String family, {
  String file = 'LiberationMono-Regular.ttf',
}) async {
  final asset = await rootBundle.load(
    'packages/quds_office_editor/fonts/$file',
  );
  var bytes = Uint8List.fromList(
    asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes),
  );
  var font = SfntFont.parse(bytes);
  // Append fresh table storage so long synthetic names are never truncated.
  final original = font.tables['name']!;
  final originalData = ByteData.sublistView(bytes);
  final raw = bytes.sublist(original.offset, original.offset + original.length);
  final nameData = ByteData.sublistView(raw);
  final stringBase = nameData.getUint16(4);
  final extra = <int>[];
  for (var i = 0; i < nameData.getUint16(2); i++) {
    final at = 6 + i * 12;
    final name = nameData.getUint16(at + 6);
    if (name != 1 && name != 16) continue;
    final platform = nameData.getUint16(at);
    final encoded = <int>[
      for (final unit in family.codeUnits)
        if (platform == 0 || platform == 3) ...[
          unit >> 8,
          unit & 255,
        ] else
          unit,
    ];
    nameData.setUint16(at + 8, encoded.length);
    nameData.setUint16(at + 10, raw.length + extra.length - stringBase);
    extra.addAll(encoded);
  }
  final offset = (bytes.length + 3) & ~3;
  final nameBytes = <int>[...raw, ...extra];
  final expanded = Uint8List((offset + nameBytes.length + 3) & ~3)
    ..setRange(0, bytes.length, bytes)
    ..setRange(offset, offset + nameBytes.length, nameBytes);
  final expandedData = ByteData.sublistView(expanded);
  for (var i = 0; i < originalData.getUint16(4); i++) {
    final at = 12 + i * 16;
    if (String.fromCharCodes(bytes.sublist(at, at + 4)) == 'name') {
      expandedData.setUint32(at + 8, offset);
      expandedData.setUint32(at + 12, nameBytes.length);
    }
  }
  bytes = expanded;
  font = SfntFont.parse(bytes);
  final table = font.tables['name']!;
  final data = ByteData.sublistView(bytes);
  final count = data.getUint16(table.offset + 2);
  final strings = table.offset + data.getUint16(table.offset + 4);
  for (var i = 0; i < count; i++) {
    final at = table.offset + 6 + i * 12;
    final platform = data.getUint16(at);
    final name = data.getUint16(at + 6);
    if (name != 1 && name != 16) continue;
    final encoded = <int>[
      for (final unit in family.codeUnits)
        if (platform == 0 || platform == 3) ...[
          unit >> 8,
          unit & 255,
        ] else
          unit,
    ];
    final length = data.getUint16(at + 8);
    if (encoded.length > length) {
      throw StateError('Synthetic family name exceeds fixture storage.');
    }
    final offset = strings + data.getUint16(at + 10);
    bytes.setRange(offset, offset + encoded.length, encoded);
    data.setUint16(at + 8, encoded.length);
  }

  // Keep both table checksums and the complete SFNT adjustment valid.
  final head = font.tables['head']!;
  data.setUint32(head.offset + 8, 0);
  int checksum(int offset, int length) {
    var sum = 0;
    for (var i = 0; i < length; i += 4) {
      var word = 0;
      for (var j = 0; j < 4; j++) {
        word = (word << 8) | (i + j < length ? bytes[offset + i + j] : 0);
      }
      sum = (sum + word) & 0xffffffff;
    }
    return sum;
  }

  for (var i = 0; i < data.getUint16(4); i++) {
    final at = 12 + i * 16;
    final offset = data.getUint32(at + 8);
    final length = data.getUint32(at + 12);
    data.setUint32(at + 4, checksum(offset, length));
  }
  data.setUint32(
    head.offset + 8,
    (0xb1b0afba - checksum(0, bytes.length)) & 0xffffffff,
  );
  return bytes;
}
