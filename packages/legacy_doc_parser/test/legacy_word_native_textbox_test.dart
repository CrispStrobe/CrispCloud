// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:legacy_doc_parser/src/bounded_cfb_reader.dart';
import 'package:legacy_doc_parser/src/compound/cfbf_writer.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _v = 'urn:schemas-microsoft-com:vml';

Uint8List _source() =>
    File('test/fixtures/word_native/linked-textboxes.doc').readAsBytesSync();

Uint8List _mutate(void Function(ByteData word, Uint8List table) edit) {
  final source = BoundedCfbReader(_source());
  final word = Uint8List.fromList(source.readPath('WordDocument')!);
  final table = Uint8List.fromList(source.readPath('1Table')!);
  edit(ByteData.sublistView(word), table);
  final writer = CfbfWriter();
  void copy(CfbfDirectoryEntry parent, String prefix) {
    for (final entry in source.childrenOf(parent)) {
      final path = prefix.isEmpty ? entry.name : '$prefix/${entry.name}';
      if (entry.isStorage) {
        writer.addStorage(path);
        copy(entry, path);
      } else {
        writer.addStream(
          path,
          path == 'WordDocument'
              ? word
              : path == '1Table'
              ? table
              : source.readEntry(entry),
        );
      }
    }
  }

  copy(source.root, '');
  return writer.build();
}

void _declaredCount(ByteData word, Uint8List table, int count) {
  final offset = word.getUint32(154 + 56 * 8, Endian.little);
  final length = word.getUint32(158 + 56 * 8, Endian.little);
  expect(length, 56); // Two FTXBXS records, including the final spare.
  ByteData.sublistView(table).setUint32(offset + 12, count, Endian.little);
}

void _replace(Uint8List bytes, List<int> old, List<int> value) {
  final matches = <int>[];
  for (var index = 0; index <= bytes.length - old.length; index++) {
    if (List.generate(
      old.length,
      (i) => bytes[index + i] == old[i],
    ).every((v) => v)) {
      matches.add(index);
    }
  }
  expect(
    matches,
    hasLength(1),
    reason: 'Mutation must target one known native record',
  );
  bytes.setRange(matches.single, matches.single + value.length, value);
}

void main() {
  test('native two-shape chain recovers only its stale declared count', () {
    final document = parseLegacyWordDocument(_source());
    final reference = document.textboxReferences.single;
    expect(reference.declaredChainLength, 1);
    expect(reference.chainLength, 2);
    expect(reference.anchors.map((a) => a.chainIndex), [0, 1]);
    expect(reference.anchors.map((a) => a.shapeId), [1026, 1027]);
    expect(document.stories.single.plainText.split('FLOW-').length - 1, 24);
    expect(
      document.warnings,
      contains(LegacyWordWarning.unsupportedFormatting),
    );
    final result = convertLegacyWordDocument(document);
    final archive = ZipDecoder().decodeBytes(result.bytes);
    final xml = XmlDocument.parse(
      utf8.decode(archive.findFile('word/document.xml')!.content),
    );
    final text = xml
        .findAllElements('t', namespace: _w)
        .map((t) => t.innerText)
        .join();
    expect(text.split('FLOW-').length - 1, 24);
    final boxes = xml.findAllElements('textbox', namespace: _v).toList();
    expect(boxes, hasLength(2));
    expect(boxes[0].getAttribute('inset'), '6.0pt,3.0pt,6.0pt,3.0pt');
    expect(boxes[1].getAttribute('inset'), '12.0pt,6.0pt,3.0pt,9.0pt');
    expect(
      boxes[0].getAttribute('style'),
      contains('mso-next-textbox:#_legacyTextboxShape1027'),
    );
    expect(boxes[1].findAllElements('t', namespace: _w), isEmpty);
    final evidence = jsonDecode(
      utf8.decode(archive.findFile('word/evidence/manifest.json')!.content),
    );
    final chain = (evidence['records'] as List).singleWhere(
      (r) => r['kind'] == 'textboxChain',
    );
    expect(chain['declaredLength'], 1);
    expect(chain['resolvedLength'], 2);
  });

  test('conforming chain counts remain unchanged', () {
    final source = _mutate((word, table) => _declaredCount(word, table, 2));
    final reference = parseLegacyWordDocument(source).textboxReferences.single;
    expect(reference.chainLength, 2);
    expect(reference.declaredChainLength, 2);
  });

  for (final count in [0, 3, 4097]) {
    test('does not invent links for incompatible declared count $count', () {
      final source = _mutate(
        (word, table) => _declaredCount(word, table, count),
      );
      expect(() => parseLegacyWordDocument(source), throwsFormatException);
    });
  }

  for (final chainIndex in [0, 2, 4096]) {
    test('rejects duplicate, gapped or excessive chain index $chainIndex', () {
      final source = _mutate(
        (word, table) => _replace(
          table,
          [0, 0, 0x0d, 0xf0, 4, 0, 0, 0, 1, 0, 1, 0],
          [
            0,
            0,
            0x0d,
            0xf0,
            4,
            0,
            0,
            0,
            chainIndex & 255,
            chainIndex >> 8,
            1,
            0,
          ],
        ),
      );
      expect(() => parseLegacyWordDocument(source), throwsFormatException);
    });
  }

  for (final next in [0, 1026, 2048]) {
    test(
      'count recovery rejects missing, cyclic or unresolved next shape $next',
      () {
        final source = _mutate(
          (word, table) => _replace(
            table,
            [0x8a, 0, 3, 4, 0, 0],
            [0x8a, 0, next & 255, next >> 8, 0, 0],
          ),
        );
        expect(() => parseLegacyWordDocument(source), throwsFormatException);
      },
    );
  }
}
