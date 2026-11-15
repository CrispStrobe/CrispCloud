import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart' show CfbfWriter;

import '../../packages/legacy_doc_parser/test/support/fib_extension_fixture.dart';
import 'structured_word_fixture.dart';

/// Minimal Word 6/95 body: a supported FIB and a counted Windows-1252 string.
/// It has no Word 97 formatting structures to preserve.
Uint8List word6RecoveryFixture({bool encrypted = false}) {
  const text = 'Legacy body text\rSecond paragraph\r';
  const textAt = 0x300;
  final word = Uint8List(textAt + text.length + 64);
  final fib = ByteData.sublistView(word);
  fib.setUint16(0, 0xa5dc, Endian.little);
  fib.setUint16(2, 101, Endian.little);
  fib.setUint16(10, encrypted ? 0x0100 : 0, Endian.little);
  fib.setUint32(0x18, textAt, Endian.little);
  fib.setUint32(0x1c, textAt + text.length, Endian.little);
  fib.setUint32(0x34, text.length, Endian.little);
  word.setAll(textAt, text.codeUnits);
  return (CfbfWriter()..addStream('WordDocument', word)).build();
}

/// Preserve the referenced Word/table streams but destroy the compound
/// directory. The fallback must recover only the counted main-body text.
Uint8List damagedWordRecoveryFixture() {
  final source = StructuredWordFixture(
    pieces: const [WordFixturePiece('Recovered body text\rSecond paragraph\r')],
  ).build();
  final header = ByteData.sublistView(source);
  final shift = header.getUint16(30, Endian.little);
  final sectorSize = 1 << shift;
  final directory = header.getUint32(48, Endian.little);
  final at = sectorSize * (directory + 1);
  source.fillRange(at, at + sectorSize, 0);
  return source;
}

/// Valid source inventory, but an unsupported counted FIB extension. This
/// reaches structured conversion before it falls back to the readable body.
Uint8List unsupportedStructureRecoveryFixture() => fibExtensionFixture(
  newVersion: 0xffff,
  words: 7,
  pairCount: 183,
  dopLength: 674,
);
