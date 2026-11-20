import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';

/// Limits for optional installed TrueType faces, before parser/allocation work.
const int maxInstalledFontBytes = 16 * 1024 * 1024;
const int maxInstalledFamilyBytes = 64 * 1024 * 1024;
const int maxInstalledFontCollectionBytes = 128 * 1024 * 1024;

class InstalledFontData {
  const InstalledFontData(this.font, this.weight, this.italic);

  final SfntFont font;
  final int weight;
  final bool italic;
}

bool validInstalledFontFamily(String family) =>
    family.trim().isNotEmpty &&
    family.length <= 256 &&
    !family.contains(RegExp(r'[\x00-\x1f\x7f]'));

/// Validate actual font metadata rather than trusting a file's name.
/// Collections, CFF/variable/color faces and mismatched families retain fallback.
InstalledFontData? parseInstalledFont(String family, Uint8List bytes) {
  if (!validInstalledFontFamily(family) ||
      bytes.length < 12 ||
      bytes.length > maxInstalledFontBytes) {
    return null;
  }
  final signature = ByteData.sublistView(bytes).getUint32(0);
  if (signature != 0x00010000 && signature != 0x74727565) return null;
  try {
    final font = SfntFont.parse(bytes);
    if (font.familyName.trim().toLowerCase() != family.trim().toLowerCase() ||
        !font.hasTable('glyf') ||
        !font.hasTable('loca') ||
        font.hasTable('fvar') ||
        font.hasTable('COLR') ||
        font.hasTable('CBDT') ||
        font.hasTable('sbix') ||
        font.unitsPerEm < 16 ||
        font.unitsPerEm > 16384 ||
        font.glyphIdFor(0x41) == 0) {
      return null;
    }
    final style = font.tables['OS/2'];
    if (style == null || style.length < 64) return null;
    final data = ByteData.sublistView(font.bytes);
    final weight = data.getUint16(style.offset + 4);
    if (weight < 1 || weight > 1000) return null;
    final italic = data.getUint16(style.offset + 62) & 1 != 0;
    return InstalledFontData(font, weight, italic);
  } on Object {
    return null;
  }
}
