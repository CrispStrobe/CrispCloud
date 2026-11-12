// SPDX-License-Identifier: MPL-2.0
// A bounded native control: change only a one-section DOC's title-page flag.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:legacy_doc_parser/src/bounded_cfb_reader.dart';
import 'package:legacy_doc_parser/src/compound/cfbf_writer.dart';

({Uint8List bytes, Map<String, Object> changes}) enableHeaderTitlePage(
  Uint8List input,
) {
  final source = BoundedCfbReader(input);
  var word = Uint8List.fromList(source.readPath('WordDocument')!);
  var w = ByteData.sublistView(word);
  final tableName = w.getUint16(10, Endian.little) & 0x200 == 0
      ? '0Table'
      : '1Table';
  final table = Uint8List.fromList(source.readPath(tableName)!);
  final t = ByteData.sublistView(table);
  final offset = w.getUint32(154 + 6 * 8, Endian.little);
  final length = w.getUint32(158 + 6 * 8, Endian.little);
  if (length != 20) {
    throw StateError('Control requires exactly one source section.');
  }
  final sed = offset + 8;
  final fc = t.getUint32(sed + 2, Endian.little);
  final end = fc + 2 + w.getUint16(fc, Endian.little);
  if (end > word.length) throw StateError('Source SEPX is truncated.');
  var p = fc + 2;
  int? titlePage;
  while (p < end) {
    if (p + 2 > end) throw StateError('Source SEPX opcode is truncated.');
    final opcode = w.getUint16(p, Endian.little);
    p += 2;
    final size = switch (opcode >> 13) {
      0 || 1 => 1,
      2 || 4 || 5 => 2,
      3 => 4,
      7 => 3,
      _ =>
        p < end
            ? word[p++]
            : throw StateError('Source SEPX size is truncated.'),
    };
    if (p + size > end) throw StateError('Source SEPX operand is truncated.');
    if (opcode == 0x300a) {
      if (titlePage != null || word[p] != 0) {
        throw StateError('Control requires one inactive title-page setting.');
      }
      titlePage = p;
    }
    p += size;
  }
  final changes = <String, Object>{'opcode': '300a', 'new': 1};
  if (titlePage != null) {
    word[titlePage] = 1;
    changes.addAll({'old': 0, 'operandOffset': titlePage});
  } else {
    final old = word.sublist(fc + 2, end), next = word.length;
    if (old.length + 3 > 0xffff) throw StateError('Control SEPX is too large.');
    final extra = Uint8List(2 + old.length + 3);
    ByteData.sublistView(extra).setUint16(0, old.length + 3, Endian.little);
    extra.setRange(2, 2 + old.length, old);
    extra.setRange(2 + old.length, extra.length, [0x0a, 0x30, 1]);
    word = Uint8List.fromList([...word, ...extra]);
    w = ByteData.sublistView(word);
    w.setUint32(64, word.length, Endian.little); // cbMac, not a story length.
    t.setUint32(sed + 2, next, Endian.little);
    changes.addAll({'appended': true, 'priorSepx': fc, 'newSepx': next});
  }
  final root = source.root;
  final output = CfbfWriter(
    clsid: root.clsid,
    stateBits: root.stateBits,
    createdFiletime: root.createdFiletime,
    modifiedFiletime: root.modifiedFiletime,
  );
  void copy(CfbfDirectoryEntry parent, String prefix) {
    for (final entry in source.childrenOf(parent)) {
      final path = prefix.isEmpty ? entry.name : '$prefix/${entry.name}';
      if (entry.isStorage) {
        output.addStorage(
          path,
          clsid: entry.clsid,
          stateBits: entry.stateBits,
          createdFiletime: entry.createdFiletime,
          modifiedFiletime: entry.modifiedFiletime,
        );
        copy(entry, path);
      } else {
        output.addStream(
          path,
          path == 'WordDocument'
              ? word
              : path == tableName
              ? table
              : source.readEntry(entry),
          clsid: entry.clsid,
          stateBits: entry.stateBits,
          createdFiletime: entry.createdFiletime,
          modifiedFiletime: entry.modifiedFiletime,
        );
      }
    }
  }

  copy(root, '');
  return (bytes: output.build(), changes: changes);
}

void main(List<String> arguments) {
  if (arguments.length != 2) {
    throw ArgumentError(
      'Usage: header_textbox_titlepage.dart SOURCE.doc NEW.doc',
    );
  }
  final result = enableHeaderTitlePage(File(arguments[0]).readAsBytesSync());
  final destination = File(arguments[1])..createSync(exclusive: true);
  destination.writeAsBytesSync(result.bytes);
  stdout.writeln(jsonEncode(result.changes));
}
