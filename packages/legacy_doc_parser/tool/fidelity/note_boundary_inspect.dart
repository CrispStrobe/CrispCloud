// SPDX-License-Identifier: MPL-2.0
// Diagnostic adapter: normal parser/converter plus literal note PLC/CLX data.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:legacy_doc_parser/src/bounded_cfb_reader.dart';

Map<String, Object?> block(LegacyWordBlock value) => switch (value) {
  LegacyWordParagraph() => {
    'kind': 'p',
    'start': value.startCp,
    'end': value.endCp,
    'text': value.runs.map((r) => r.text).join(),
    'before': value.style.spaceBeforeTwips,
    'after': value.style.spaceAfterTwips,
  },
  LegacyWordTable() => {
    'kind': 'tbl',
    'start': value.startCp,
    'end': value.endCp,
    'cells': [
      for (final row in value.rows)
        for (final cell in row.cells) cell.blocks.map(block).toList(),
    ],
  },
};

void main(List<String> args) {
  if (args.isEmpty || args.length > 2) {
    throw ArgumentError(
      'Usage: note_boundary_inspect.dart SOURCE.doc [NEW.docx]',
    );
  }
  final result = <Object>[];
  for (final path in args.take(1)) {
    final bytes = File(path).readAsBytesSync();
    final doc = parseLegacyWordDocument(bytes);
    final cfb = BoundedCfbReader(bytes);
    final wordBytes = cfb.readPath('WordDocument')!;
    final word = ByteData.sublistView(wordBytes);
    int w16(int offset) => word.getUint16(offset, Endian.little);
    int w32(int offset) => word.getUint32(offset, Endian.little);
    final tableBytes = cfb.readPath(
      w16(10) & 0x200 != 0 ? '1Table' : '0Table',
    )!;
    final table = ByteData.sublistView(tableBytes);
    int t16(int offset) => table.getUint16(offset, Endian.little);
    int t32(int offset) => table.getUint32(offset, Endian.little);
    (int, int) pair(int index) => (w32(154 + index * 8), w32(158 + index * 8));
    final lengths = [
      for (final index in [3, 4, 5, 7, 8, 9, 10]) w32(64 + index * 4),
    ];
    final units = List<int>.filled(lengths.reduce((a, b) => a + b), 0);
    var at = pair(33).$1;
    while (tableBytes[at] == 1) {
      at += 3 + t16(at + 1);
    }
    final count = (t32(at + 1) - 4) ~/ 12;
    at += 5;
    final records = at + (count + 1) * 4;
    for (var i = 0; i < count; i++) {
      final start = t32(at + i * 4), end = t32(at + (i + 1) * 4);
      final packed = t32(records + i * 8 + 2);
      final compressed = packed & 0x40000000 != 0;
      final offset = (packed & 0x3fffffff) ~/ (compressed ? 2 : 1);
      for (var cp = start; cp < end && cp < units.length; cp++) {
        units[cp] = compressed
            ? wordBytes[offset + cp - start]
            : w16(offset + (cp - start) * 2);
      }
    }
    final ranges = <Object>[];
    for (final endnote in [false, true]) {
      final index = endnote ? 4 : 1;
      if (lengths[index] == 0) continue;
      final base = lengths.take(index).fold(0, (a, b) => a + b);
      final (off, size) = pair(endnote ? 47 : 3);
      final cps = [for (var i = 0; i < size; i += 4) t32(off + i)];
      ranges.add({
        'kind': endnote ? 'endnote' : 'footnote',
        'base': base,
        'length': lengths[index],
        'cps': cps,
        'raw': String.fromCharCodes(units.sublist(base, base + lengths[index])),
        'notes': [
          for (var i = 0; i < cps.length - 2; i++)
            {
              'start': base + cps[i],
              'end': base + cps[i + 1],
              'units': units.sublist(base + cps[i], base + cps[i + 1]),
              'followingUnit': units[base + cps[i + 1]],
            },
        ],
      });
    }
    final converted = convertLegacyWordDocument(doc);
    if (args.length == 2) {
      File(args[1]).createSync(exclusive: true);
      File(args[1]).writeAsBytesSync(converted.bytes);
    }
    result.add({
      'ranges': ranges,
      'warnings': doc.warnings.map((w) => w.name).toList(),
      'counts': converted.preservedCounts,
      'limitations': converted.limitations.map((l) => l.name).toList(),
      'stories': [
        for (final story in doc.stories)
          if (story.kind == LegacyWordStoryKind.footnote ||
              story.kind == LegacyWordStoryKind.endnote)
            {
              'id': story.id,
              'start': story.startCp,
              'end': story.endCp,
              'blocks': story.blocks.map(block).toList(),
            },
      ],
    });
  }
  print(jsonEncode(result.single));
}
