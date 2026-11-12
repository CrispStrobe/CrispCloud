// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import '../tool/fidelity/textbox_table_fixture.dart' as producer;
import 'support/textbox_table_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

XmlDocument _convert({
  required bool header,
  required bool anchorInTable,
  required int? marginTwips,
  required bool nested,
}) {
  final source = textboxTableFixture(
    header: header,
    anchorInTable: anchorInTable,
    marginTwips: marginTwips,
    nested: nested,
  );
  final document = parseLegacyWordDocument(source);
  final story = document.stories.singleWhere(
    (story) =>
        story.kind ==
        (header
            ? LegacyWordStoryKind.headerTextbox
            : LegacyWordStoryKind.textbox),
  );
  final table = story.blocks.whereType<LegacyWordTable>().single;
  expect(table.rows.single.originTwips, 480);
  expect(
    table.rows.single.cells.single.formatting.margins[LegacyWordBorderSide
        .left],
    marginTwips ?? 108,
  );
  final archive = ZipDecoder().decodeBytes(
    convertLegacyWordDocument(document).bytes,
  );
  final part = header ? 'word/header1.xml' : 'word/document.xml';
  return XmlDocument.parse(utf8.decode(archive.findFile(part)!.content));
}

List<int> _indents(XmlNode node) => [
  for (final indent in node.findAllElements('tblInd', namespace: _w))
    int.parse(indent.getAttribute('w', namespace: _w)!),
];

void main() {
  test('producer metadata matches each generated textbox table package', () {
    final temporary = Directory.systemTemp.createTempSync('textbox-tables-');
    addTearDown(() => temporary.deleteSync(recursive: true));
    final output = '${temporary.path}/fixtures';
    producer.main([output]);
    final cases =
        (jsonDecode(File('$output/cases.json').readAsStringSync())
                as List<Object?>)
            .cast<Map<String, Object?>>();
    expect(cases, hasLength(24));
    expect(cases.map((item) => item['id']).toSet(), hasLength(24));
    for (final item in cases) {
      final id = item['id']! as String;
      final archive = ZipDecoder().decodeBytes(
        File('$output/$id.docx').readAsBytesSync(),
      );
      final part = item['header'] == true
          ? 'word/header1.xml'
          : 'word/document.xml';
      final xml = XmlDocument.parse(
        utf8.decode(archive.findFile(part)!.content),
      );
      final box = xml.findAllElements('txbxContent', namespace: _w).single;
      final expected = (item['expectedTextboxIndentsTwips']! as List<Object?>)
          .cast<int>();
      final anchor = (item['expectedAnchorIndentsTwips']! as List<Object?>)
          .cast<int>();
      expect(_indents(box), expected, reason: id);
      expect(_indents(xml), [
        if (anchor.isNotEmpty) anchor.first,
        ...expected,
        ...anchor.skip(1),
      ], reason: id);
    }
  });

  for (final header in [false, true]) {
    for (final margin in [null, 0, 240]) {
      for (final nested in [false, true]) {
        test(
          '${header ? 'header' : 'body'} textbox margin $margin, nested $nested keeps its containing table context',
          () {
            final free = _convert(
              header: header,
              anchorInTable: false,
              marginTwips: margin,
              nested: nested,
            );
            final anchored = _convert(
              header: header,
              anchorInTable: true,
              marginTwips: margin,
              nested: nested,
            );
            final freeBox = free
                .findAllElements('txbxContent', namespace: _w)
                .single;
            final anchoredBox = anchored
                .findAllElements('txbxContent', namespace: _w)
                .single;
            final expected = [480, if (nested) 240];
            expect(_indents(freeBox), [480 + (margin ?? 108), if (nested) 240]);
            expect(_indents(anchoredBox), expected);
            expect(anchoredBox.innerText, freeBox.innerText);
            // The genuine nested anchor table follows the textbox event.
            // Its 360-twip indent checks restoration of the enclosing depth.
            expect(_indents(anchored), [960, ...expected, if (!nested) 360]);
            expect(
              anchored
                  .findAllElements('t', namespace: _w)
                  .map((text) => text.innerText),
              [
                'M',
                'BOX',
                'CELL',
                if (nested) 'INNER',
                'AFTER_BOX',
                if (!nested) 'ANCHOR_NESTED',
                'AFTER_ANCHOR',
              ],
            );
          },
        );
      }
    }
  }
}
