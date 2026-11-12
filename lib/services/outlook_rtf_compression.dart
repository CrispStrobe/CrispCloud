import 'dart:typed_data';

enum OutlookRtfErrorCode { malformed, unsupportedCompression, resourceLimit }

class OutlookRtfException implements Exception {
  const OutlookRtfException(this.code);
  final OutlookRtfErrorCode code;
  @override
  String toString() => 'OutlookRtfException(${code.name})';
}

const kOutlookRtfLimit = 8 * 1024 * 1024;

// Protocol constants from [MS-OXRTFCP] 2.1.3, 2.2 and 3.2.2.1. Authored
// implementation; no third-party decompressor is bundled. The CR/LF at offsets
// 168/169 and the initial write offset of 207 are part of the wire format.
const _seed =
    r'{\rtf1\ansi\mac\deff0\deftab720{\fonttbl;}{\f0\fnil \froman '
    r'\fswiss \fmodern \fscript \fdecor MS Sans SerifSymbolArialTimes New '
    r'RomanCourier{\colortbl\red0\green0\blue0'
    '\r\n'
    r'\par \pard\plain\f0\fs20\b\i\u\tab\tx';

final _crcTable = List<int>.generate(256, (index) {
  var value = index;
  for (var bit = 0; bit < 8; bit++) {
    value = (value >>> 1) ^ ((value & 1) == 0 ? 0 : 0xedb88320);
  }
  return value;
}, growable: false);

/// Decodes PidTagRtfCompressed (0x10090102). LZFu validates the declared size,
/// initialized dictionary references, overlapping copies, end marker and CRC
/// over all contents (including permitted padding). MELA follows the spec's
/// recommended read-to-end behavior and MUST NOT validate its CRC field.
Uint8List decompressOutlookRtf(Uint8List bytes) {
  Never malformed() =>
      throw const OutlookRtfException(OutlookRtfErrorCode.malformed);
  if (bytes.length > kOutlookRtfLimit + 16) {
    throw const OutlookRtfException(OutlookRtfErrorCode.resourceLimit);
  }
  if (bytes.length < 16) malformed();
  final header = ByteData.sublistView(bytes);
  final compressedSize = header.getUint32(0, Endian.little);
  final rawSize = header.getUint32(4, Endian.little);
  final type = header.getUint32(8, Endian.little);
  if (compressedSize < 12 || compressedSize + 4 != bytes.length) malformed();
  if (type == 0x414c454d) {
    return Uint8List.fromList(bytes.sublist(16)).asUnmodifiableView();
  }
  if (type != 0x75465a4c) {
    throw const OutlookRtfException(OutlookRtfErrorCode.unsupportedCompression);
  }
  if (rawSize > kOutlookRtfLimit) {
    throw const OutlookRtfException(OutlookRtfErrorCode.resourceLimit);
  }
  var crc = 0;
  for (var i = 16; i < bytes.length; i++) {
    crc = (crc >>> 8) ^ _crcTable[(crc ^ bytes[i]) & 0xff];
  }
  if ((crc & 0xffffffff) != header.getUint32(12, Endian.little)) malformed();
  final dictionary = Uint8List(4096)..setAll(0, _seed.codeUnits);
  var write = _seed.length;
  var initialized = write;
  var input = 16;
  var produced = 0;
  // The specified empty-stream encoding emits one NUL before its end marker.
  final output = Uint8List(rawSize == 0 ? 1 : rawSize);
  int read() {
    if (input >= bytes.length) malformed();
    return bytes[input++];
  }

  void emit(int value) {
    if (produced >= output.length) malformed();
    output[produced++] = value;
    dictionary[write] = value;
    write = (write + 1) & 0xfff;
    if (initialized < 4096) initialized++;
  }

  while (true) {
    final control = read();
    for (var bit = 1; bit <= 0x80; bit <<= 1) {
      if ((control & bit) == 0) {
        emit(read());
      } else {
        final reference = (read() << 8) | read();
        var offset = reference >>> 4;
        if (offset == write) {
          if (produced == rawSize) return output.asUnmodifiableView();
          if (rawSize == 0 && produced == 1 && output[0] == 0) {
            return Uint8List(0).asUnmodifiableView();
          }
          malformed();
        }
        final length = (reference & 0xf) + 2;
        for (var index = 0; index < length; index++) {
          if (offset >= initialized) malformed();
          emit(dictionary[offset]);
          offset = (offset + 1) & 0xfff;
        }
      }
    }
  }
}
