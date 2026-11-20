import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Signature-independent identity of a signed thin 64-bit Mach-O library.
///
/// A code signature lives at the end of `__LINKEDIT`, after everything dyld
/// executes or binds. Replacing it (ad hoc → Apple Distribution or Developer
/// ID) changes exactly three header fields below the signature: the
/// `LC_CODE_SIGNATURE` `datasize` and the `__LINKEDIT` `vmsize`/`filesize`.
/// This digest is SHA-256 over the file prefix `[0, dataoff)` with those three
/// fields zeroed, so it is identical for every signature of the same code and
/// differs for any change to code, data, load commands, symbols or fixups.
///
/// Returns null when [bytes] is not a well-formed thin little-endian 64-bit
/// Mach-O with exactly one `LC_CODE_SIGNATURE` at the end of the file and one
/// `__LINKEDIT` segment ending there (fat files, unsigned files and anything
/// with data after the signature are rejected rather than guessed).
///
/// The build script proves the same equivalence independently with Apple's
/// tool: `codesign --remove-signature` of the shipped library must equal
/// `codesign --remove-signature` of the qualified library byte for byte.
String? machOCodeSha256(Uint8List bytes) {
  final layout = _MachOSignatureLayout.parse(bytes);
  if (layout == null) return null;
  final prefix = Uint8List.fromList(
    Uint8List.sublistView(bytes, 0, layout.signatureOffset),
  );
  for (final (offset, width) in layout.maskedFields) {
    prefix.fillRange(offset, offset + width, 0);
  }
  return sha256.convert(prefix).toString();
}

const _mhMagic64 = 0xfeedfacf;
const _lcSegment64 = 0x19;
const _lcCodeSignature = 0x1d;
const _machHeader64Bytes = 32;

final class _MachOSignatureLayout {
  _MachOSignatureLayout(this.signatureOffset, this.maskedFields);

  final int signatureOffset;
  final List<(int, int)> maskedFields;

  static _MachOSignatureLayout? parse(Uint8List bytes) {
    if (bytes.length < _machHeader64Bytes) return null;
    final data = ByteData.sublistView(bytes);
    int u32(int offset) => data.getUint32(offset, Endian.little);
    int u64(int offset) => data.getUint64(offset, Endian.little);
    if (u32(0) != _mhMagic64) return null;
    final commandCount = u32(16);
    final commandBytes = u32(20);
    final commandsEnd = _machHeader64Bytes + commandBytes;
    if (commandsEnd > bytes.length) return null;

    int? signatureCommand;
    int? linkeditCommand;
    final segmentEnds = <int>[];
    var offset = _machHeader64Bytes;
    for (var index = 0; index < commandCount; index++) {
      if (offset + 8 > commandsEnd) return null;
      final command = u32(offset);
      final size = u32(offset + 4);
      if (size < 8 || size % 8 != 0 || offset + size > commandsEnd) {
        return null;
      }
      if (command == _lcCodeSignature) {
        if (signatureCommand != null || size != 16) return null;
        signatureCommand = offset;
      } else if (command == _lcSegment64) {
        if (size < 72) return null;
        final name = String.fromCharCodes(
          bytes.sublist(offset + 8, offset + 24).takeWhile((b) => b != 0),
        );
        if (name == '__LINKEDIT') {
          if (linkeditCommand != null) return null;
          linkeditCommand = offset;
        } else {
          segmentEnds.add(u64(offset + 40) + u64(offset + 48));
        }
      }
      offset += size;
    }
    if (offset != commandsEnd ||
        signatureCommand == null ||
        linkeditCommand == null) {
      return null;
    }
    final signatureOffset = u32(signatureCommand + 8);
    final signatureBytes = u32(signatureCommand + 12);
    final linkeditOffset = u64(linkeditCommand + 40);
    final linkeditBytes = u64(linkeditCommand + 48);
    if (signatureBytes == 0 ||
        signatureOffset < commandsEnd ||
        signatureOffset + signatureBytes != bytes.length ||
        linkeditOffset > signatureOffset ||
        linkeditOffset + linkeditBytes != bytes.length ||
        segmentEnds.any((end) => end > signatureOffset)) {
      return null;
    }
    return _MachOSignatureLayout(signatureOffset, [
      (signatureCommand + 12, 4), // LC_CODE_SIGNATURE datasize
      (linkeditCommand + 32, 8), // __LINKEDIT vmsize
      (linkeditCommand + 48, 8), // __LINKEDIT filesize
    ]);
  }
}
