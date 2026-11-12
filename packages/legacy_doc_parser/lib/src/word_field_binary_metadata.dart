// SPDX-License-Identifier: MPL-2.0
part of 'conversion.dart';

// MS-DOC 2.9.158 NilPICFAndBinData and 2.9.115 HFD; MS-OSHARED
// 2.3.7.1 Hyperlink Object and 2.3.7.9 HyperlinkString. A U+0001 in a
// field instruction can be referenced binary metadata, not an active object.
// Recognize only a fully bounded internal location corroborated by both the
// literal HYPERLINK instruction and its actual CFData/CPicLocation artifact.
extension _WordFieldBinaryMetadata on _StructuredWordWriter {
  String _fieldInstruction(LegacyWordField field) =>
      _fieldInstructions.putIfAbsent(
        field.id,
        () => _internalHyperlinkInstruction(field) ?? field.instruction,
      );

  String? _internalHyperlinkInstruction(LegacyWordField field) {
    if (field.type.toUpperCase() != 'HYPERLINK') return null;
    final match = RegExp(
      r'^\s*HYPERLINK\s+\\l\s+(?:"([^"\x00-\x1f]+)"|([^\s"\x00-\x1f]+))\s*\x01\s*$',
      caseSensitive: false,
    ).firstMatch(field.instruction);
    if (match == null) return null;
    final anchor = match.group(1) ?? match.group(2)!;
    if (anchor.length > 255) return null;
    final marker = field.instruction.indexOf('\x01');
    final cp = field.startCp + 1 + marker;
    final artifact = _fieldBinaryData[cp];
    if (artifact == null ||
        artifact.source.streamPath != 'Data' ||
        artifact.source.structure != 'NilPICFAndBinData' ||
        artifact.source.offset < 0 ||
        artifact.source.length != artifact.bytes.length ||
        _internalHfdLocation(artifact.bytes) != anchor) {
      return null;
    }
    // Preserve every original UTF-16 offset used by nested-field/event slicing.
    return field.instruction.replaceRange(marker, marker + 1, ' ');
  }
}

String? _internalHfdLocation(Uint8List bytes) {
  // 68-byte NilPICF, one HFDBits byte, CLSID, version/flags, then one
  // length-prefixed, NUL-terminated UTF-16 location (at most 255 units).
  if (bytes.length < 99 || bytes.length > 609) return null;
  final data = ByteData.sublistView(bytes);
  if (data.getInt32(0, Endian.little) != bytes.length ||
      data.getUint16(4, Endian.little) != 68 ||
      bytes[68] != 0x08) {
    return null;
  }
  const clsid = [
    0xd0,
    0xc9,
    0xea,
    0x79,
    0xf9,
    0xba,
    0xce,
    0x11,
    0x8c,
    0x82,
    0x00,
    0xaa,
    0x00,
    0x4b,
    0xa9,
    0x0b,
  ];
  for (var i = 0; i < clsid.length; i++) {
    if (bytes[69 + i] != clsid[i]) return null;
  }
  final flags = data.getUint32(89, Endian.little);
  if (data.getUint32(85, Endian.little) != 2 ||
      (flags != 0x08 && flags != 0x0a)) {
    return null;
  }
  final length = data.getUint32(93, Endian.little);
  if (length < 2 || length > 256 || 97 + length * 2 != bytes.length) {
    return null;
  }
  final units = <int>[];
  for (var i = 0; i < length; i++) {
    final unit = data.getUint16(97 + i * 2, Endian.little);
    if (i == length - 1) {
      if (unit != 0) return null;
    } else {
      if (unit < 0x20 || unit == 0xfffe || unit == 0xffff) return null;
      units.add(unit);
    }
  }
  final value = String.fromCharCodes(units);
  if (value.runes.any((rune) => rune >= 0xd800 && rune <= 0xdfff)) {
    return null;
  }
  return value;
}
