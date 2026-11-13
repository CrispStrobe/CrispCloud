// SPDX-License-Identifier: MPL-2.0
part of 'conversion.dart';

// MS-DOC 2.9.158 NilPICFAndBinData and 2.9.115 HFD; MS-OSHARED
// 2.3.7.1 Hyperlink Object and 2.3.7.9 HyperlinkString. A U+0001 in a
// field instruction can be referenced binary metadata, not an active object.
// Recognize only fully bounded targets corroborated by both the literal
// field instruction and its actual CFData/CPicLocation artifact.
extension _WordFieldBinaryMetadata on _StructuredWordWriter {
  String _fieldInstruction(LegacyWordField field) =>
      _fieldInstructions.putIfAbsent(
        field.id,
        () =>
            _internalHyperlinkInstruction(field) ??
            _externalHyperlinkInstruction(field) ??
            _referenceHyperlinkInstruction(field)?.$1 ??
            field.instruction,
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

  String? _externalHyperlinkInstruction(LegacyWordField field) {
    if (field.type.toUpperCase() != 'HYPERLINK') return null;
    final match = RegExp(
      r'^\s*HYPERLINK\s+(?:"([^"\x00-\x1f]+)"|([^\s"\\\x00-\x1f]+))\s*\x01\s*$',
      caseSensitive: false,
    ).firstMatch(field.instruction);
    if (match == null) return null;
    final target = match.group(1) ?? match.group(2)!;
    if (target.length > _maxHfdUrlUnits) return null;
    final marker = field.instruction.indexOf('\x01');
    final cp = field.startCp + 1 + marker;
    final artifact = _fieldBinaryData[cp];
    if (artifact == null ||
        artifact.source.streamPath != 'Data' ||
        artifact.source.structure != 'NilPICFAndBinData' ||
        artifact.source.offset < 0 ||
        artifact.source.length != artifact.bytes.length ||
        _externalHfdUrl(artifact.bytes) != target) {
      return null;
    }
    // No URL resolution, canonicalization or traversal. The field already
    // spells the exact stored URL; only its qualified binary marker is removed.
    return field.instruction.replaceRange(marker, marker + 1, ' ');
  }

  (String, bool)? _referenceHyperlinkInstruction(LegacyWordField field) {
    final type = field.type.toUpperCase();
    if (!const {'REF', 'PAGEREF', 'NOTEREF'}.contains(type)) return null;
    final match = RegExp(
      r'^\s*(REF|PAGEREF|NOTEREF)\s+(?:"([^"\x00-\x1f]+)"|([^\s"\x00-\x1f]+))\s+\\h\s*\x01\s*$',
      caseSensitive: false,
    ).firstMatch(field.instruction);
    if (match == null || match.group(1)!.toUpperCase() != type) return null;
    final target = match.group(2) ?? match.group(3)!;
    if (target.length > 255) return null;
    final marker = field.instruction.indexOf('\x01');
    final artifact = _fieldBinaryData[field.startCp + 1 + marker];
    if (artifact == null ||
        artifact.source.streamPath != 'Data' ||
        artifact.source.structure != 'NilPICFAndBinData' ||
        artifact.source.offset < 0 ||
        artifact.source.length != artifact.bytes.length) {
      return null;
    }
    final location = _referenceHfdLocation(artifact.bytes);
    if (location == null || location.$1 != target) return null;
    return (
      field.instruction.replaceRange(marker, marker + 1, ' '),
      location.$2,
    );
  }
}

ByteData? _hfdHeader(Uint8List bytes, int bits) {
  if (bytes.length < 93) return null;
  final data = ByteData.sublistView(bytes);
  if (data.getInt32(0, Endian.little) != bytes.length ||
      data.getUint16(4, Endian.little) != 68 ||
      bytes[68] != bits) {
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
  if (data.getUint32(85, Endian.little) != 2) return null;
  return data;
}

String? _internalHfdLocation(Uint8List bytes) {
  // 68-byte NilPICF, one HFDBits byte, CLSID, version/flags, then one
  // length-prefixed, NUL-terminated UTF-16 location (at most 255 units).
  if (bytes.length < 99 || bytes.length > 609) return null;
  final data = _hfdHeader(bytes, 0x08);
  if (data == null) return null;
  final flags = data.getUint32(89, Endian.little);
  if (flags != 0x08 && flags != 0x0a) return null;
  final length = data.getUint32(93, Endian.little);
  if (length < 2 || length > 256 || 97 + length * 2 != bytes.length) {
    return null;
  }
  return _hfdTerminatedString(data, 97, length);
}

(String, bool)? _referenceHfdLocation(Uint8List bytes) {
  if (bytes.length < 99 || bytes.length > 611) return null;
  final data = _hfdHeader(bytes, 0x08);
  if (data == null || data.getUint32(89, Endian.little) != 0x08) return null;
  final length = data.getUint32(93, Endian.little);
  if (length < 2 || length > 256) return null;
  final end = 97 + length * 2;
  final padded = end + 2 == bytes.length;
  // LibreOffice's InsertSpecialChar reference-field producer writes a 32-bit
  // zero after a location declared with a single UTF-16 terminator. Qualify
  // only that one extra zero word, never arbitrary trailing HFD contents.
  if (end != bytes.length &&
      !(padded && bytes[end] == 0 && bytes[end + 1] == 0)) {
    return null;
  }
  final location = _hfdTerminatedString(data, 97, length);
  return location == null ? null : (location, padded);
}

// A conservative allocation bound, not URL normalization or a scheme policy.
const _maxHfdUrlUnits = 32767;

String? _externalHfdUrl(Uint8List bytes) {
  // MS-OSHARED 2.3.7.2 / 2.3.7.6: one URLMoniker, no optional serialization
  // trailer, location/frame/display strings, GUID or creation timestamp.
  if (bytes.length < 117 || bytes.length > 113 + 2 * (_maxHfdUrlUnits + 1)) {
    return null;
  }
  final data = _hfdHeader(bytes, 0);
  if (data == null) return null;
  final flags = data.getUint32(89, Endian.little);
  if (flags != 0x01 && flags != 0x03) return null;
  const urlClsid = [
    0xe0,
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
  for (var i = 0; i < urlClsid.length; i++) {
    if (bytes[93 + i] != urlClsid[i]) return null;
  }
  final byteLength = data.getUint32(109, Endian.little);
  if (byteLength < 4 || byteLength.isOdd || 113 + byteLength != bytes.length) {
    return null;
  }
  return _hfdTerminatedString(data, 113, byteLength ~/ 2);
}

String? _hfdTerminatedString(ByteData data, int offset, int length) {
  final units = <int>[];
  for (var i = 0; i < length; i++) {
    final unit = data.getUint16(offset + i * 2, Endian.little);
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
