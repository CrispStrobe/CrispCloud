// SPDX-License-Identifier: MPL-2.0
// Companion to review_loss_audit.py, which pins the inspected binary inputs.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:legacy_doc_parser/src/bounded_cfb_reader.dart';
import 'package:xml/xml.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

void _require(bool condition, String message) {
  if (!condition) throw FormatException(message);
}

Map<String, Object> _binaryRecords(File source) {
  final bytes = source.readAsBytesSync();
  final cfb = BoundedCfbReader(bytes);
  final word = cfb.readPath('WordDocument')!;
  final fib = ByteData.sublistView(word);
  _require(
    fib.getUint16(32, Endian.little) == 14,
    'Audit requires the pinned Word 97 FIB layout.',
  );
  _require(
    fib.getUint16(62, Endian.little) == 22,
    'Audit requires the pinned FIB long-word layout.',
  );
  _require(
    fib.getUint16(152, Endian.little) > 112,
    'Audit requires extended comment FIB entries.',
  );
  final tableName = fib.getUint16(10, Endian.little) & 0x200 == 0
      ? '0Table'
      : '1Table';
  final table = cfb.readPath(tableName)!;
  final data = ByteData.sublistView(table);
  int offset(int index) => fib.getUint32(154 + index * 8, Endian.little);
  int length(int index) => fib.getUint32(158 + index * 8, Endian.little);
  for (final index in [4, 6, 33, 112]) {
    _require(
      offset(index) + length(index) <= table.length,
      'FIB range exceeds the table stream.',
    );
  }

  final clxLimit = offset(33) + length(33);
  var position = offset(33);
  var prcCount = 0;
  while (position < clxLimit && table[position] == 1) {
    _require(position + 3 <= clxLimit, 'Truncated Prc.');
    position += 3 + data.getUint16(position + 1, Endian.little);
    _require(position <= clxLimit, 'Prc exceeds CLX.');
    prcCount++;
  }
  _require(
    position + 5 <= clxLimit && table[position] == 2,
    'Missing Pcdt in CLX.',
  );
  final pcdSize = data.getUint32(position + 1, Endian.little);
  position += 5;
  _require(
    pcdSize >= 4 && (pcdSize - 4) % 12 == 0,
    'Invalid piece-table size.',
  );
  _require(position + pcdSize == clxLimit, 'Invalid piece-table extent.');
  final pieces = (pcdSize - 4) ~/ 12;
  final prms = [
    for (var index = 0; index < pieces; index++)
      data.getUint16(
        position + (pieces + 1) * 4 + index * 8 + 6,
        Endian.little,
      ),
  ];

  _require(length(6) >= 4 && (length(6) - 4) % 16 == 0, 'Invalid section PLC.');
  final sectionCount = (length(6) - 4) ~/ 16;
  final sections = <List<String>>[];
  for (var index = 0; index < sectionCount; index++) {
    final fc = data.getUint32(
      offset(6) + (sectionCount + 1) * 4 + index * 12 + 2,
      Endian.little,
    );
    if (fc == 0xffffffff) {
      sections.add([]);
      continue;
    }
    _require(fc + 2 <= word.length, 'Missing SEPX length.');
    final limit = fc + 2 + fib.getUint16(fc, Endian.little);
    _require(limit <= word.length, 'SEPX exceeds WordDocument.');
    var cursor = fc + 2;
    final opcodes = <String>[];
    while (cursor < limit) {
      _require(cursor + 2 <= limit, 'Truncated SEPX opcode.');
      final opcode = fib.getUint16(cursor, Endian.little);
      cursor += 2;
      opcodes.add(opcode.toRadixString(16).padLeft(4, '0'));
      final spra = opcode >> 13;
      if (spra == 6) {
        _require(cursor < limit, 'Missing SEPX operand length.');
      }
      final size = switch (spra) {
        0 || 1 => 1,
        2 || 4 || 5 => 2,
        3 => 4,
        7 => 3,
        _ => word[cursor++],
      };
      cursor += size;
      _require(cursor <= limit, 'SEPX operand exceeds its property group.');
    }
    sections.add(opcodes);
  }

  _require(
    length(4) == 0 || (length(4) >= 4 && (length(4) - 4) % 34 == 0),
    'Invalid comment-reference PLC.',
  );
  _require(length(112) % 18 == 0, 'Invalid ATRDPost10 array.');
  final commentRecords = <Map<String, int>>[];
  for (var index = 0; index < length(112) ~/ 18; index++) {
    final start = offset(112) + index * 18;
    commentRecords.add({
      'rawDate': data.getUint32(start, Endian.little),
      'depth': data.getUint32(start + 6, Endian.little),
      'parent': data.getInt32(start + 10, Endian.little),
      'flags': data.getUint32(start + 14, Endian.little),
    });
  }
  return {
    'bytes': bytes.length,
    'piecePropertyRecords': prcCount,
    'piecePrms': prms,
    'sectionPropertyCodes': sections,
    'commentReferenceCount': length(4) == 0 ? 0 : (length(4) - 4) ~/ 34,
    'extendedCommentRecords': commentRecords,
  };
}

List<Map<String, String?>> _revisionIds() {
  final revision = LegacyWordRevisionInfo(
    author: 'Audit author',
    time: DateTime.utc(2026, 11, 12, 8, 45),
  );
  LegacyWordTable table(int cp) => LegacyWordTable(
    startCp: cp,
    endCp: cp + 3,
    rows: [
      LegacyWordTableRow(
        heightTwips: 720,
        formattingRevision: LegacyWordTableRowFormattingRevision(
          previousProperties: const LegacyWordTableRowProperties(
            heightTwips: 240,
          ),
          revision: revision,
        ),
        cells: [
          LegacyWordTableCell(
            widthTwips: 1000,
            paragraphs: [
              LegacyWordParagraph(
                startCp: cp,
                endCp: cp + 2,
                runs: [
                  LegacyWordRun(
                    startCp: cp,
                    endCp: cp + 1,
                    text: 'X',
                    inserted: true,
                    insertionRevision: revision,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
  LegacyWordStory story(String id, LegacyWordStoryKind kind, int cp) =>
      LegacyWordStory(
        id: id,
        kind: kind,
        startCp: cp,
        endCp: cp + 3,
        blocks: [table(cp)],
        plainText: 'X',
        safeHtml: '',
      );
  final document = LegacyWordDocument(
    blocks: [
      LegacyWordParagraph(
        startCp: 0,
        endCp: 4,
        runs: [
          LegacyWordRun(
            startCp: 0,
            endCp: 3,
            text: 'ABC',
            inserted: true,
            insertionRevision: revision,
          ),
        ],
      ),
    ],
    sections: [const LegacyWordSection(startCp: 0, endCp: 4)],
    plainText: 'ABC',
    safeHtml: '',
    stories: [
      story('header', LegacyWordStoryKind.header, 10),
      story('footnote', LegacyWordStoryKind.footnote, 20),
      story('comment', LegacyWordStoryKind.comment, 30),
    ],
    noteReferences: [
      const LegacyWordNoteReference(
        id: 1,
        anchorCp: 1,
        storyId: 'footnote',
        endnote: false,
      ),
    ],
    commentReferences: [
      const LegacyWordCommentReference(
        id: 1,
        anchorCp: 2,
        storyId: 'comment',
        author: 'Audit author',
      ),
    ],
  );
  final package = ZipDecoder().decodeBytes(
    convertLegacyWordDocument(document).bytes,
  );
  final records = <Map<String, String?>>[];
  for (final file in package.files) {
    if (!file.name.startsWith('word/') || !file.name.endsWith('.xml')) continue;
    final xml = XmlDocument.parse(utf8.decode(file.content));
    for (final element in xml.descendants.whereType<XmlElement>()) {
      if (element.name.namespaceUri != _w ||
          !const {
            'ins',
            'del',
            'trPrChange',
            'pPrChange',
            'rPrChange',
            'sectPrChange',
          }.contains(element.name.local)) {
        continue;
      }
      records.add({
        'part': file.name,
        'kind': element.name.local,
        'id': element.getAttribute('id', namespace: _w),
      });
    }
  }
  _require(records.length == 9, 'Cross-story probe lost native revisions.');
  final identifiers = records.map((record) => record['id']).toSet();
  _require(
    identifiers.length == 9 && !identifiers.contains(null),
    'Cross-story probe has missing or duplicate revision IDs.',
  );
  return records;
}

void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError('Usage: review_loss_audit.dart SEALED_NATIVE_RUN');
  }
  print(
    jsonEncode({
      'binary': {
        for (final name in ['word-compatibility', 'comment-threads'])
          name: _binaryRecords(
            File('${arguments.single}/$name/bridge/$name.doc'),
          ),
      },
      'revisionIds': _revisionIds(),
    }),
  );
}
