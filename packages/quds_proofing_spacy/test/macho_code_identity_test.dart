import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy.dart';
import 'package:test/test.dart';

const _headerBytes = 32;
const _codeEnd = 256;
const _signatureOffset = 320;

/// A minimal signed thin arm64 Mach-O: `__TEXT` [0, 256), `__LINKEDIT`
/// [256, end) whose last [signatureBytes] bytes are the code signature.
Uint8List _macho({
  int signatureBytes = 48,
  int signatureFill = 0xA5,
  int codeFill = 0x11,
  int linkeditFill = 0x22,
  int magic = 0xfeedfacf,
  bool signature = true,
  int textFileBytes = _codeEnd,
  int trailing = 0,
}) {
  final commands = signature ? 3 : 2;
  final commandBytes = 72 + 72 + (signature ? 16 : 0);
  final end = _signatureOffset + (signature ? signatureBytes : 0);
  final bytes = Uint8List(end + trailing);
  final data = ByteData.sublistView(bytes);
  void u32(int offset, int value) =>
      data.setUint32(offset, value, Endian.little);
  void u64(int offset, int value) =>
      data.setUint64(offset, value, Endian.little);
  void segment(int at, String name, int fileOffset, int fileBytes) {
    u32(at, 0x19);
    u32(at + 4, 72);
    bytes.setRange(at + 8, at + 8 + name.length, name.codeUnits);
    u64(at + 24, fileOffset); // vmaddr
    u64(at + 32, (fileBytes + 0x3fff) & ~0x3fff); // vmsize
    u64(at + 40, fileOffset);
    u64(at + 48, fileBytes);
  }

  u32(0, magic);
  u32(4, 0x0100000c); // CPU_TYPE_ARM64
  u32(12, 6); // MH_DYLIB
  u32(16, commands);
  u32(20, commandBytes);
  final commandsEnd = _headerBytes + commandBytes;
  bytes.fillRange(commandsEnd, _codeEnd, codeFill);
  bytes.fillRange(_codeEnd, _signatureOffset, linkeditFill);
  bytes.fillRange(_signatureOffset, end, signatureFill);
  segment(_headerBytes, '__TEXT', 0, textFileBytes);
  segment(_headerBytes + 72, '__LINKEDIT', _codeEnd, end - _codeEnd);
  if (signature) {
    final at = _headerBytes + 144;
    u32(at, 0x1d);
    u32(at + 4, 16);
    u32(at + 8, _signatureOffset);
    u32(at + 12, signatureBytes);
  }
  return bytes;
}

void main() {
  test('the code digest ignores the signature and covers everything else', () {
    final adHoc = _macho();
    final digest = machOCodeSha256(adHoc)!;
    // Re-signing: other signature bytes and size (which also changes the
    // __LINKEDIT sizes) keep the code digest.
    expect(
      machOCodeSha256(_macho(signatureBytes: 4096, signatureFill: 0x5A)),
      digest,
    );
    // Definition: SHA-256 of [0, dataoff) with three size fields zeroed.
    final masked = Uint8List.fromList(adHoc.sublist(0, _signatureOffset));
    masked.fillRange(_headerBytes + 144 + 12, _headerBytes + 144 + 16, 0);
    masked.fillRange(_headerBytes + 72 + 32, _headerBytes + 72 + 40, 0);
    masked.fillRange(_headerBytes + 72 + 48, _headerBytes + 72 + 56, 0);
    expect(digest, sha256.convert(masked).toString());
    // Code, symbol/fixup data and every other header byte are covered.
    expect(machOCodeSha256(_macho(codeFill: 0x12)), isNot(digest));
    expect(machOCodeSha256(_macho(linkeditFill: 0x23)), isNot(digest));
    final flags = _macho();
    flags[24] ^= 1;
    expect(machOCodeSha256(flags), isNot(digest));
  });

  test('anything but one signed thin 64-bit Mach-O is rejected', () {
    expect(machOCodeSha256(_macho(signature: false)), isNull);
    expect(machOCodeSha256(_macho(magic: 0xcafebabe)), isNull);
    expect(machOCodeSha256(_macho(magic: 0xfeedface)), isNull);
    expect(machOCodeSha256(Uint8List(16)), isNull);
    // Data after the signature, or a segment reaching into it, is not
    // hidden behind the mask.
    expect(machOCodeSha256(_macho(trailing: 16)), isNull);
    expect(
      machOCodeSha256(_macho(textFileBytes: _signatureOffset + 8)),
      isNull,
    );
    // Truncated load commands.
    final truncated = _macho();
    ByteData.sublistView(truncated).setUint32(20, 4096, Endian.little);
    expect(machOCodeSha256(truncated), isNull);
    // A second LC_CODE_SIGNATURE is ambiguous.
    final twice = _macho();
    ByteData.sublistView(twice)
      ..setUint32(_headerBytes + 72, 0x1d, Endian.little)
      ..setUint32(_headerBytes + 76, 16, Endian.little);
    expect(machOCodeSha256(twice), isNull);
  });

  // Optional check on the real qualified library (not committed: 2.3 MB),
  // for example the file build_macos_app.sh downloads:
  //   QUDS_SPACY_MACOS_LIBRARY=.../libcrispembed-spacy.dylib dart test
  final library = Platform.environment['QUDS_SPACY_MACOS_LIBRARY'];
  test(
    'the qualified macOS library has the recorded code digest',
    () {
      final bytes = File(library!).readAsBytesSync();
      expect(sha256.convert(bytes).toString(), spacyGrammarMacosBundledSha256);
      expect(machOCodeSha256(bytes), spacyGrammarMacosBundledCodeSha256);
    },
    skip: library == null || library.isEmpty
        ? 'set QUDS_SPACY_MACOS_LIBRARY to the qualified library'
        : false,
  );
}
