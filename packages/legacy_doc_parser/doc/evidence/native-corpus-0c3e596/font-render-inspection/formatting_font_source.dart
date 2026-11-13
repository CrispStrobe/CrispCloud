import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:legacy_doc_parser/src/compound/cfbf_reader.dart';

String _sourceSha256(String path) {
  final result = Process.runSync('sha256sum', ['--', path]);
  final digest = result.stdout.toString().split(' ').first;
  if (result.exitCode != 0 || !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
    throw StateError('Unable to hash the retained source document');
  }
  return digest;
}

void main(List<String> args) {
  final bytes = File(args.single).readAsBytesSync(),
      doc = parseLegacyWordDocument(File(args.single).readAsBytesSync());
  final runs = <Map<String, Object?>>[];
  void scan(List<LegacyWordBlock> blocks) {
    for (final b in blocks) {
      if (b is LegacyWordParagraph) {
        for (final r in b.runs) {
          if (r.text.contains('Unicode') ||
              r.text.contains('東京') ||
              r.text.contains('😀')) {
            runs.add({
              'startCp': r.startCp,
              'endCp': r.endCp,
              'text': r.text,
              'utf16CodeUnits': r.text.codeUnits
                  .map((n) => n.toRadixString(16))
                  .toList(),
              'unicodeScalars': r.text.runes
                  .map((n) => n.toRadixString(16))
                  .toList(),
              'ascii': r.style.fontName,
              'nonAscii': r.style.scriptFonts?.nonAscii,
              'eastAsia': r.style.scriptFonts?.eastAsia,
              'complexScript': r.style.scriptFonts?.complexScript,
            });
          }
        }
      } else if (b is LegacyWordTable) {
        for (final row in b.rows) {
          for (final c in row.cells) {
            scan(c.blocks);
          }
        }
      }
    }
  }

  scan(doc.blocks);
  final cfb = CfbfFile.fromBytes(bytes), word = cfb.readStream('WordDocument')!;
  final wd = ByteData.sublistView(word);
  int u16(int n) => wd.getUint16(n, Endian.little);
  int u32(int n) => wd.getUint32(n, Endian.little);
  final pairStart = 34 + 2 * u16(32) + 2 + 4 * u16(34 + 2 * u16(32)) + 2;
  final tableName = (u16(10) & 0x200) != 0 ? '1Table' : '0Table';
  final table = cfb.readStream(tableName)!;
  final tableData = ByteData.sublistView(table);
  int tu16(int n) => tableData.getUint16(n, Endian.little);
  final fontStart = u32(pairStart + 15 * 8);
  int pos = fontStart;
  if (tu16(pos) == 0xffff) pos += 2;
  final count = tu16(pos), extra = tu16(pos + 2);
  pos += 4;
  final fonts = <Map<String, Object?>>[];
  for (var i = 0; i < count; i++) {
    final size = table[pos] + 1;
    final units = <int>[];
    for (var j = pos + 40; j < pos + size; j += 2) {
      final n = tu16(j);
      if (n == 0) break;
      units.add(n);
    }
    fonts.add({
      'index': i,
      'name': String.fromCharCodes(units),
      'tableOffset': pos,
      'ffnBytes': size,
    });
    pos += size + extra;
  }
  final stsh = u32(pairStart + 8);
  final headerLength = tu16(stsh);
  final defaults = <String, Object?>{};
  for (final (slot, offset) in [
    ('ascii', 14),
    ('eastAsia', 16),
    ('nonAscii', 18),
    ('complexScript', 20),
  ]) {
    if (headerLength >= offset) {
      final index = tableData.getInt16(stsh + offset, Endian.little);
      defaults[slot] = {
        'index': index,
        'name': index >= 0 && index < fonts.length
            ? fonts[index]['name']
            : null,
        'tableOffset': stsh + offset,
      };
    }
  }
  final raw = [];
  for (var i = 0; i + 3 < word.length; i++) {
    if (word[i] == 0x3d &&
        word[i + 1] == 0xd8 &&
        word[i + 2] == 0x00 &&
        word[i + 3] == 0xde) {
      raw.add(i);
    }
  }
  print(
    const JsonEncoder.withIndent('  ').convert({
      'source': args.single,
      'sourceSha256': _sourceSha256(args.single),
      'mainEmojiScalarCount': doc.plainText.runes
          .where((n) => n == 0x1f600)
          .length,
      'mainTokyoCount': '東京'.allMatches(doc.plainText).length,
      'selectedTable': tableName,
      'stylesheetTableOffset': stsh,
      'stylesheetHeaderLength': headerLength,
      'defaultFontSlots': defaults,
      'fontTable': fonts,
      'unicodeRuns': runs,
      'rawEmojiUtf16WordDocumentOffsets': raw,
    }),
  );
}
