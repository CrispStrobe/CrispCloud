// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';
import 'dart:typed_data';

import 'package:legacy_doc_parser/src/compound/cfbf_writer.dart';

/// Small, independent [MS-DOC] Word 97 FIB/CLX fixture with one UTF-16 piece.
Uint8List legacyWordFixture(
  String text, {
  bool encrypted = false,
  bool withOpaqueMacro = false,
}) {
  const textOffset = 1024;
  final secret = ascii.encode('UNREFERENCED DELETED SECRET');
  final word = Uint8List(textOffset + text.length * 2 + secret.length + 64);
  final fib = ByteData.sublistView(word);
  void u16(int offset, int value) =>
      fib.setUint16(offset, value, Endian.little);
  void u32(int offset, int value) =>
      fib.setUint32(offset, value, Endian.little);
  u16(0, 0xa5ec);
  u16(2, 0x00c1);
  u16(10, encrypted ? 0x0300 : 0x0200);
  u16(32, 14);
  u16(62, 22);
  u16(152, 93);
  u32(76, text.length);
  u32(0x1a2, 0);
  u32(0x1a6, 21);
  for (var i = 0; i < text.length; i++) {
    u16(textOffset + i * 2, text.codeUnitAt(i));
  }
  word.setRange(word.length - secret.length, word.length, secret);

  final table = Uint8List(21)..[0] = 2;
  final clx = ByteData.sublistView(table);
  clx.setUint32(1, 16, Endian.little); // Pcdt length.
  clx.setUint32(5, 0, Endian.little); // First CP.
  clx.setUint32(9, text.length, Endian.little); // Final CP.
  clx.setUint32(15, textOffset, Endian.little); // Uncompressed FcCompressed.
  final writer = CfbfWriter()
    ..addStream('WordDocument', word)
    ..addStream('1Table', table);
  if (withOpaqueMacro) {
    writer.addStream('Macros/VBA/Module1', Uint8List.fromList([1, 2, 3, 4]));
  }
  return writer.build();
}
