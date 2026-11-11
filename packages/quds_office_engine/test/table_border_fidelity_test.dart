import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

WmlDocument _source() => WordDeserializer().readBytes(
  File('test/fixtures/fidelity/table-borders.docx').readAsBytesSync(),
);

List<WmlTable> _tables(WmlDocument document) =>
    document.sections.first.blocks.whereType<WmlTable>().toList();

void _check(WmlDocument document, bool edited) {
  final tables = _tables(document);
  expect(tables.map((table) => table.properties.borders), <bool>[
    edited,
    !edited,
    false,
  ]);
  expect(
    document.footnotes.single.blocks
        .whereType<WmlTable>()
        .single
        .properties
        .borders,
    edited,
  );
  expect(
    tables.first.properties.sourcePropertiesXml,
    contains('Retained caption'),
  );
  if (edited) {
    expect(tables.first.properties.borderColor, '224466');
    expect(tables.first.properties.borderWidth, 1.5);
  } else {
    expect(tables[1].properties.borderColor, 'CC0000');
    expect(tables[1].properties.borderWidth, 1);
  }
}

void main() {
  for (final bool edited in <bool>[false, true]) {
    test(
      'native ${edited ? 'edited' : 'imported'} table borders survive three async saves',
      () async {
        WmlDocument document = _source();
        _check(document, false);
        if (edited) {
          final tables = _tables(document);
          tables.first.properties
            ..borders = true
            ..borderColor = '224466'
            ..borderWidth = 1.5;
          tables[1].properties.borders = false;
          document.footnotes.single.blocks
              .whereType<WmlTable>()
              .single
              .properties
            ..borders = true
            ..borderColor = '996633'
            ..borderWidth = 0.75;
        }
        for (var cycle = 1; cycle <= 3; cycle++) {
          final bytes = await OfficeIsolateSave.word(document);
          final output = File(
            'build/fidelity-table-borders/tables-${edited ? 'edited' : 'imported'}-$cycle.docx',
          );
          output.parent.createSync(recursive: true);
          output.writeAsBytesSync(bytes);
          document = WordDeserializer().readBytes(bytes);
          _check(document, edited);
        }
      },
    );
  }

  test('table clone retains sparse source properties independently', () {
    final original = _tables(_source()).first;
    final copy = WmlClone.table(original);
    expect(
      copy.properties.sourcePropertiesXml,
      original.properties.sourcePropertiesXml,
    );
    expect(copy.properties.importedValues, original.properties.importedValues);
    copy.properties.importedValues!['tblBorders'] = 'changed clone';
    expect(
      original.properties.importedValues!['tblBorders'],
      isNot('changed clone'),
    );
    copy.properties.borders = true;
    expect(original.properties.borders, isFalse);
  });

  test('new tables keep their explicit default borders', () {
    final table = WmlTable(
      grid: <double>[100],
      rows: <WmlTableRow>[
        WmlTableRow(
          cells: <WmlTableCell>[
            WmlTableCell(
              blocks: <WmlBlock>[
                WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'New table')]),
              ],
            ),
          ],
        ),
      ],
    );
    final doc = WmlDocument(
      sections: <WmlSection>[
        WmlSection(blocks: <WmlBlock>[table]),
      ],
    );
    final copy = WordDeserializer().readBytes(WordSerializer().writeBytes(doc));
    expect(_tables(copy).single.properties.borders, isTrue);
  });
}
