import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

// Synthetic packages, not installed LibreOffice/Zotero captures. Coverage follows
// ODF 1.3 Part 3 section 9.1.5 and span attributes 19.680/19.682. Covered cells
// may contain stored content in ODF; refusing it is this reader's bounded,
// no-loss conversion policy, not a claim that all such ODF is invalid.
const _office = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _text = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _table = 'urn:oasis:names:tc:opendocument:xmlns:table:1.0';
const _style = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _fo = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';
const _meta = 'urn:oasis:names:tc:opendocument:xmlns:meta:1.0';
const _namespaces =
    'xmlns:office="$_office" xmlns:text="$_text" xmlns:table="$_table" '
    'xmlns:style="$_style" xmlns:fo="$_fo" xmlns:meta="$_meta"';

const _styles =
    '<style:style style:name="Em" style:family="text">'
    '<style:text-properties fo:font-style="italic"/></style:style>'
    '<style:style style:name="Fill" style:family="table-cell">'
    '<style:table-cell-properties fo:background-color="#ffeedd"/></style:style>'
    '<style:style style:name="SameFill" style:family="table-cell">'
    '<style:table-cell-properties fo:background-color="#FFEEDD"/></style:style>'
    '<style:style style:name="OtherFill" style:family="table-cell">'
    '<style:table-cell-properties fo:background-color="#112233"/></style:style>'
    '<style:style style:name="C1" style:family="table-column">'
    '<style:table-column-properties style:column-width="72pt"/></style:style>'
    '<style:style style:name="C2" style:family="table-column">'
    '<style:table-column-properties style:column-width="108pt"/></style:style>'
    '<style:style style:name="C3" style:family="table-column">'
    '<style:table-column-properties style:column-width="144pt"/></style:style>';

Map<String, Object?> _citationData(String id) => {
  'citationID': id,
  'citationItems': [
    {
      'id': 'http://zotero.org/users/42/items/ABCD1234',
      'uris': ['http://zotero.org/users/42/items/ABCD1234'],
      'locator': '12–14',
      'label': 'page',
      'prefix': 'see ',
      'suffix': ' RNDabcdefghij',
      'suppress-author': true,
      'itemData': {
        'id': 17,
        'type': 'book',
        'title': 'العربية 😀 & <quoted>',
        'futureItemData': {'keep': true},
      },
      'futureItem': ['retained', 9],
    },
  ],
  'properties': {
    'plainCitation': '(Same)',
    'noteIndex': 0,
    'futureProperty': {'keep': 'yes'},
  },
  'futureRoot': {
    'retain': [true, null, 3],
  },
};

String _name(String id) =>
    'ZOTERO_ITEM CSL_CITATION ${jsonEncode(_citationData(id))} '
    'RND${id.padRight(10, '0')}';

String _start(String id) =>
    '<text:reference-mark-start text:name="${encodeXmlAttribute(_name(id))}"/>';

String _end(String id) =>
    '<text:reference-mark-end text:name="${encodeXmlAttribute(_name(id))}"/>';

String _mark(String id) =>
    '${_start(id)}(<text:span text:style-name="Em">Same</text:span>)${_end(id)}';

const _bibliographyData = <String, Object?>{
  'uncited': <Object?>[],
  'omitted': <Object?>[],
  'custom': <Object?>[],
  'futureBibliography': <String, Object?>{'retain': true},
};

String _bibliography() {
  final name =
      'ZOTERO_BIBL ${jsonEncode(_bibliographyData)} '
      'CSL_BIBLIOGRAPHY RNDabcdefghij';
  return '<text:section text:name="${encodeXmlAttribute(name)}">'
      '<text:p>Old first entry.</text:p><text:p>Old second entry.</text:p>'
      '</text:section>';
}

Uint8List _package(String body, {String styles = _styles}) {
  final writer = ZipWriter();
  writer.addFile(
    'mimetype',
    utf8.encode('application/vnd.oasis.opendocument.text'),
    store: true,
  );
  writer.addFile(
    'content.xml',
    utf8.encode(
      '<office:document-content $_namespaces>'
      '<office:automatic-styles>$styles</office:automatic-styles>'
      '<office:body><office:text>$body</office:text></office:body>'
      '</office:document-content>',
    ),
  );
  final preferences = jsonEncode({
    'dataVersion': 4,
    'style': {'styleID': 'http://www.zotero.org/styles/apa', 'locale': 'de-DE'},
    'prefs': {'fieldType': 'ReferenceMark', 'noteType': 0},
    'futurePreferences': {'preserve': true, 'opaque': 'x' * 350},
  });
  final properties = StringBuffer();
  for (var offset = 0, index = 1; offset < preferences.length; index++) {
    final end = (offset + 255).clamp(0, preferences.length);
    properties.write(
      '<meta:user-defined meta:name="ZOTERO_PREF_$index">'
      '${encodeXmlText(preferences.substring(offset, end))}'
      '</meta:user-defined>',
    );
    offset = end;
  }
  writer.addFile(
    'meta.xml',
    utf8.encode(
      '<office:document-meta $_namespaces><office:meta>'
      '$properties</office:meta></office:document-meta>',
    ),
  );
  return writer.close();
}

String _cell(String contents, {String attributes = ''}) =>
    '<table:table-cell $attributes>$contents</table:table-cell>';

String _row(String cells, {String attributes = ''}) =>
    '<table:table-row $attributes>$cells</table:table-row>';

String _tableXml(String rows, {String columns = ''}) =>
    '<table:table>$columns$rows</table:table>';

const _covered = '<table:covered-table-cell/>';

String _combinedTable({String? origin}) => _tableXml(
  _row(
        _cell(
              origin ?? '<text:p>Before ${_mark('origin')} after</text:p>',
              attributes:
                  'table:number-columns-spanned="2" table:number-rows-spanned="2" '
                  'table:style-name="Fill"',
            ) +
            _covered +
            _cell('<text:p>${_mark('right')}</text:p>'),
      ) +
      _row(_covered + _covered + _cell('<text:p>${_mark('lower')}</text:p>')) +
      _row(
        _cell(
              '<text:p>${_mark('wide')}</text:p>',
              attributes: 'table:number-columns-spanned="3"',
            ) +
            _covered +
            _covered,
      ),
  columns:
      '<table:table-column table:style-name="C1"/>'
      '<table:table-column table:style-name="C2"/>'
      '<table:table-column table:style-name="C3"/>',
);

WmlDocument _reopen(WmlDocument document) =>
    WordDeserializer().readBytes(WordSerializer().writeBytes(document));

WmlTable _bodyTable(WmlDocument document) =>
    document.sections.single.blocks.whereType<WmlTable>().single;

WmlParagraph _paragraph(WmlTableCell cell) =>
    cell.blocks.whereType<WmlParagraph>().single;

WmlZoteroField _field(WmlDocument document, String id) => WordZotero.fields(
  document,
).singleWhere((field) => field.citation?.citationId == id);

WmlRun _runContaining(WmlParagraph paragraph, String text) => paragraph.inlines
    .whereType<WmlRun>()
    .singleWhere((run) => run.text.contains(text));

Object? _call(
  WordZoteroCitingSession session,
  String command, [
  List<Object?> arguments = const [],
]) => session.handle(command, ['merged-odt', ...arguments]);

List<Map<String, Object>> _wireFields(WordZoteroCitingSession session) =>
    (_call(session, 'Document.getFields', ['Http']) as List<Object?>)
        .cast<Map<String, Object>>();

String _wireCitationId(Map<String, Object> field) {
  final code = field['code'] as String;
  final data =
      jsonDecode(code.substring(code.indexOf('{'), code.lastIndexOf('}') + 1))
          as Map<String, Object?>;
  return data['citationID'] as String;
}

void _checkCombinedGeometry(WmlTable table) {
  expect(table.grid, [72, 108, 144]);
  expect(table.rows.map((row) => row.cells.length), [2, 2, 1]);
  expect(
    table.rows.map((row) => row.cells.map((cell) => cell.gridSpan).toList()),
    [
      [2, 1],
      [2, 1],
      [3],
    ],
  );
  expect(table.rows[0].cells[0].vMerge, WmlVMerge.restart);
  expect(table.rows[1].cells[0].vMerge, WmlVMerge.cont);
  expect(table.rows[0].cells[1].vMerge, WmlVMerge.none);
  expect(table.rows[1].cells[1].vMerge, WmlVMerge.none);
  expect(table.rows[2].cells.single.vMerge, WmlVMerge.none);
  expect(table.rows[0].cells.map((cell) => cell.width), [180, 144]);
  expect(table.rows[1].cells.map((cell) => cell.width), [180, 144]);
  expect(table.rows[2].cells.single.width, 324);
  expect(table.rows[0].cells[0].fillColor, 'FFEEDD');
  expect(table.rows[1].cells[0].fillColor, 'FFEEDD');
  expect(_paragraph(table.rows[1].cells[0]).text, isEmpty);
  for (final row in table.rows) {
    expect(row.cells.fold<int>(0, (sum, cell) => sum + cell.gridSpan), 3);
  }
}

Matcher get _refused =>
    throwsA(anyOf(isA<FormatException>(), isA<UnsupportedError>()));

String _verticalTable(int rows, int columns, {String? firstContents}) {
  final first = List.generate(
    columns,
    (column) => _cell(
      column == 0 && firstContents != null
          ? firstContents
          : '<text:p>Cell</text:p>',
      attributes: 'table:number-rows-spanned="$rows"',
    ),
  ).join();
  final continuations = List<String>.generate(
    rows - 1,
    (_) => _row(List<String>.filled(columns, _covered).join()),
  ).join();
  return _tableXml(_row(first) + continuations);
}

void main() {
  test(
    'combined spans retain four equal-looking citations at exact owners',
    () async {
      final bytes = _package(_combinedTable());
      final before = Uint8List.fromList(bytes);
      var document = await OdtDocumentReader.readBytes(bytes);
      for (var cycle = 0; cycle < 3; cycle++) {
        final table = _bodyTable(document);
        _checkCombinedGeometry(table);
        final expectedOwners = <String, WmlParagraph>{
          'origin': _paragraph(table.rows[0].cells[0]),
          'right': _paragraph(table.rows[0].cells[1]),
          'lower': _paragraph(table.rows[1].cells[1]),
          'wide': _paragraph(table.rows[2].cells[0]),
        };
        final fields = WordZotero.fields(document);
        expect(fields.map((field) => field.citation!.citationId), [
          'origin',
          'right',
          'lower',
          'wide',
        ]);
        expect(
          fields.map((field) => field.cachedText),
          List.filled(4, '(Same)'),
        );
        for (final entry in expectedOwners.entries) {
          final field = _field(document, entry.key);
          expect(identical(field.paragraph, entry.value), isTrue);
          expect(field.canEdit, isTrue);
          expect(field.metadata, _citationData(entry.key));
          expect(field.citation!.items.single.locator, '12–14');
          expect(field.citation!.items.single.suppressAuthor, isTrue);
          expect(
            _runContaining(field.paragraph, 'Same').properties.italic,
            isTrue,
          );
          expect(
            identical(field.paragraph, _paragraph(table.rows[1].cells[0])),
            isFalse,
          );
        }
        expect(_field(document, 'origin').start, 7);
        expect(
          _field(document, 'origin').paragraph.text,
          'Before (Same) after',
        );
        final session = WordZoteroCitingSession(
          document: document,
          documentId: 'merged-odt',
          insertionParagraph: expectedOwners['origin']!,
        );
        final wire = _wireFields(session);
        expect(wire.map(_wireCitationId), expectedOwners.keys);
        expect(wire.map((field) => field['id']).toSet(), hasLength(4));
        expect(wire.map((field) => field['noteIndex']), [0, 0, 0, 0]);
        expect(wire.map((field) => field['adjacent']), [
          false,
          false,
          false,
          false,
        ]);
        session.assertUnchanged();
        if (cycle < 2) document = _reopen(document);
      }
      expect(bytes, before);
    },
  );

  test(
    'merged owners survive staged refresh, DOCX reopen, locator edit and unlink',
    () async {
      var document = _reopen(
        await OdtDocumentReader.readBytes(
          _package(_combinedTable() + _bibliography()),
        ),
      );
      final originalTable = _bodyTable(document);
      final originalOwner = originalTable.rows[0].cells[0];
      final originalText = document.paragraphs.map((p) => p.text).toList();
      final session = WordZoteroCitingSession(
        document: document,
        documentId: 'merged-odt',
        insertionParagraph: _paragraph(originalOwner),
      );
      final wire = _wireFields(session);
      for (final field in wire.where(
        (f) => (f['code'] as String).startsWith('ITEM'),
      )) {
        final id = _wireCitationId(field);
        final citation = _field(document, id).citation!;
        final html = '<b>Updated $id</b>';
        final updated = citation.withItems(
          citation.items,
          plainCitation: 'Updated $id',
          formattedCitation: html,
        );
        _call(session, 'Field.setCode', [
          field['id'],
          'ITEM CSL_CITATION ${jsonEncode(updated.toJson())}',
        ]);
        _call(session, 'Field.setText', [field['id'], html, true]);
      }
      final bibliography = wire.singleWhere(
        (field) => (field['code'] as String).startsWith('BIBL'),
      );
      _call(session, 'Document.setBibliographyStyle', [
        -720,
        720,
        480,
        240,
        <int>[720],
        1,
      ]);
      _call(session, 'Field.setCode', [
        bibliography['id'],
        'BIBL ${jsonEncode(_bibliographyData)} CSL_BIBLIOGRAPHY',
      ]);
      _call(session, 'Field.setText', [
        bibliography['id'],
        '<div class="csl-entry">Updated <i>Book</i>.</div>'
            '<div class="csl-entry">Second <b>Book</b>.</div>',
        true,
      ]);
      _call(session, 'Document.setDocumentData', [
        _call(session, 'Document.getDocumentData'),
      ]);
      expect(document.paragraphs.map((p) => p.text), originalText);
      _call(session, 'Document.complete');
      session.prepareReview();
      session.apply();
      expect(identical(_bodyTable(document), originalTable), isTrue);
      expect(
        identical(_bodyTable(document).rows[0].cells[0], originalOwner),
        isTrue,
      );
      _checkCombinedGeometry(_bodyTable(document));
      document = _reopen(document);
      for (final id in ['origin', 'right', 'lower', 'wide']) {
        final field = _field(document, id);
        expect(field.cachedText, 'Updated $id');
        expect(field.canEdit, isTrue);
        expect(
          _runContaining(field.paragraph, 'Updated').properties.bold,
          isTrue,
        );
        expect(
          field.citation!.toJson()['futureRoot'],
          _citationData(id)['futureRoot'],
        );
      }
      final bibliographyField = WordZotero.fields(
        document,
      ).singleWhere((field) => field.kind == ZoteroFieldKind.bibliography);
      expect(bibliographyField.metadata, _bibliographyData);
      expect(bibliographyField.cachedText, 'Updated Book.\nSecond Book.');
      expect(bibliographyField.paragraphs, hasLength(2));
      expect(
        bibliographyField.paragraphs.every(
          (paragraph) =>
              paragraph.properties.indent.hanging == 36 &&
              paragraph.properties.lineSpacing == 2,
        ),
        isTrue,
      );
      final origin = _field(document, 'origin');
      final changed = ZoteroCitationItem.fromJson({
        ...origin.citation!.items.single.toJson(),
        'locator': '99',
      });
      WordZotero.updateCitation(
        origin,
        origin.citation!.withItems([changed], plainCitation: origin.cachedText),
      );
      document = _reopen(document);
      expect(_field(document, 'origin').citation!.items.single.locator, '99');
      final unlinkedText = _field(document, 'origin').paragraph.text;
      WordZotero.unlink(_field(document, 'origin'));
      document = _reopen(document);
      _checkCombinedGeometry(_bodyTable(document));
      expect(
        _paragraph(_bodyTable(document).rows[0].cells[0]).text,
        unlinkedText,
      );
      expect(
        WordZotero.fields(document)
            .where((field) => field.kind == ZoteroFieldKind.citation)
            .map((field) => field.citation!.citationId),
        ['right', 'lower', 'wide'],
      );
      final preferences =
          jsonDecode(WordZoteroDocumentData.read(document))
              as Map<String, Object?>;
      expect(preferences['futurePreferences'], {
        'preserve': true,
        'opaque': 'x' * 350,
      });
      expect(
        (preferences['prefs'] as Map<String, Object?>)['fieldType'],
        'Field',
      );
    },
  );

  for (final kind in ['footnote', 'endnote']) {
    test(
      'authored $kind and nested merged table retain anchored citation order',
      () async {
        final nested = _tableXml(
          _row(
                _cell(
                  '<text:p>${_mark('nested')}</text:p>',
                  attributes: 'table:number-rows-spanned="2"',
                ),
              ) +
              _row(_covered),
        );
        final outer = _tableXml(
          _row(
            _cell(
                  '<text:p>${_mark('note')}</text:p>$nested',
                  attributes: 'table:number-columns-spanned="2"',
                ) +
                _covered,
          ),
        );
        final bytes = _package(
          '<text:p>${_mark('before')} '
          '<text:note text:id="authored" text:note-class="$kind">'
          '<text:note-citation>1</text:note-citation><text:note-body>'
          '<text:p>Authored note prose.</text:p>$outer'
          '</text:note-body></text:note> ${_mark('after')}</text:p>',
        );
        final document = await OdtDocumentReader.readBytes(bytes);
        for (final current in [document, _reopen(document)]) {
          final note =
              (kind == 'footnote' ? current.footnotes : current.endnotes)
                  .single;
          final outerTable = note.blocks.whereType<WmlTable>().single;
          final owner = outerTable.rows.single.cells.single;
          expect(owner.gridSpan, 2);
          final nestedTable = owner.blocks.whereType<WmlTable>().single;
          expect(nestedTable.rows.first.cells.single.vMerge, WmlVMerge.restart);
          expect(nestedTable.rows.last.cells.single.vMerge, WmlVMerge.cont);
          expect(_paragraph(nestedTable.rows.last.cells.single).text, isEmpty);
          final noteParagraph = owner.blocks.first as WmlParagraph;
          expect(
            identical(_field(current, 'note').paragraph, noteParagraph),
            isTrue,
          );
          expect(owner.blocks.whereType<WmlParagraph>(), hasLength(2));
          expect(owner.blocks.last, isA<WmlParagraph>());
          expect((owner.blocks.last as WmlParagraph).text, isEmpty);
          expect(
            identical(
              _field(current, 'nested').paragraph,
              _paragraph(nestedTable.rows.first.cells.single),
            ),
            isTrue,
          );
          expect(
            note.blocks.whereType<WmlParagraph>().single.text,
            'Authored note prose.',
          );
          expect(note.endnote, kind == 'endnote');
          final body = current.sections.single.blocks
              .whereType<WmlParagraph>()
              .single;
          final anchor = body.inlines.whereType<WmlRun>().singleWhere(
            (run) => run.noteRefId != null,
          );
          expect(anchor.noteRefId, note.id);
          final session = WordZoteroCitingSession(
            document: current,
            documentId: 'merged-odt',
            insertionParagraph: body,
          );
          final wire = _wireFields(session);
          expect(wire.map(_wireCitationId), [
            'before',
            'note',
            'nested',
            'after',
          ]);
          expect(wire.map((field) => field['noteIndex']), [0, 1, 1, 0]);
          expect(
            WordZotero.fields(current).every((field) => field.canEdit),
            isTrue,
          );
          session.assertUnchanged();
        }
      },
    );
  }

  test('matching covered fill and XML whitespace do not add an owner', () async {
    final document = await OdtDocumentReader.readBytes(
      _package(
        _tableXml(
          _row(
            '${_cell('<text:p>${_mark('filled')}</text:p>', attributes: 'table:number-columns-spanned="2" table:style-name="Fill"')}<table:covered-table-cell table:style-name="SameFill"> \n\t\r </table:covered-table-cell>',
          ),
        ),
      ),
    );
    for (final current in [document, _reopen(document)]) {
      final table = _bodyTable(current);
      expect(table.rows.single.cells, hasLength(1));
      expect(table.rows.single.cells.single.gridSpan, 2);
      expect(table.rows.single.cells.single.fillColor, 'FFEEDD');
      expect(WordZotero.fields(current), hasLength(1));
      expect(_field(current, 'filled').canEdit, isTrue);
    }
  });

  final ordinary = _cell('<text:p>Cell</text:p>');
  final wide = _cell(
    '<text:p>Wide</text:p>',
    attributes: 'table:number-columns-spanned="2"',
  );
  final tall = _cell(
    '<text:p>Tall</text:p>',
    attributes: 'table:number-rows-spanned="2"',
  );
  final invalidCoverage = <String, String>{
    'missing covered position': _tableXml(_row(wide)),
    'orphan covered position': _tableXml(_row(_covered)),
    'ordinary cell overlapping horizontal origin': _tableXml(
      _row(wide + ordinary),
    ),
    'ordinary cell overlapping vertical origin': _tableXml(
      _row(tall) + _row(ordinary),
    ),
    'span collides with prior vertical origin': _tableXml(
      _row(ordinary + tall) + _row(wide + _covered),
    ),
    'span exceeds actual final row': _tableXml(_row(tall)),
    'extra orphan covered position': _tableXml(
      _row(wide + _covered + _covered),
    ),
    'declared grid is too narrow': _tableXml(
      _row(wide + _covered),
      columns: '<table:table-column/>',
    ),
    'covered fill conflicts with origin': _tableXml(
      _row(
        '${_cell('<text:p>Cell</text:p>', attributes: 'table:number-columns-spanned="2" table:style-name="Fill"')}<table:covered-table-cell table:style-name="OtherFill"/>',
      ),
    ),
    'repeated origin': _tableXml(
      _row(
        _cell(
          '<text:p>Cell</text:p>',
          attributes: 'table:number-columns-repeated="2"',
        ),
      ),
    ),
    'repeated covered positions': _tableXml(
      _row(
        '${_cell('<text:p>Cell</text:p>', attributes: 'table:number-columns-spanned="3"')}<table:covered-table-cell table:number-columns-repeated="2"/>',
      ),
    ),
    'repeated row': _tableXml(
      _row(ordinary, attributes: 'table:number-rows-repeated="2"'),
    ),
  };
  for (final entry in invalidCoverage.entries) {
    test('refuses ${entry.key} without changing source bytes', () async {
      final bytes = _package(entry.value);
      final before = Uint8List.fromList(bytes);
      await expectLater(OdtDocumentReader.readBytes(bytes), _refused);
      expect(bytes, before);
    });
  }

  final hiddenPayloads = <String, String>{
    'hidden prose': '<text:p>Hidden</text:p>',
    'empty paragraph': '<text:p/>',
    'hidden citation': '<text:p>${_mark('hidden')}</text:p>',
    'explicit tab': '<text:p><text:tab/></text:p>',
    'nested table': _tableXml(_row(ordinary)),
    'direct text': 'Hidden',
    'nonbreaking space': '\u00a0',
    'zero width space': '\u200b',
  };
  for (final entry in hiddenPayloads.entries) {
    test('refuses covered ${entry.key} instead of discarding it', () async {
      final bytes = _package(
        _tableXml(
          _row(
            '$wide<table:covered-table-cell>${entry.value}</table:covered-table-cell>',
          ),
        ),
      );
      final before = Uint8List.fromList(bytes);
      await expectLater(OdtDocumentReader.readBytes(bytes), _refused);
      expect(bytes, before);
    });
  }

  test('citation cannot end in a covered cell with a different owner', () async {
    final bytes = _package(
      _tableXml(
        _row(
          '${_cell('<text:p>${_start('crossing')}Citation</text:p>', attributes: 'table:number-columns-spanned="2"')}<table:covered-table-cell><text:p>${_end('crossing')}</text:p></table:covered-table-cell>',
        ),
      ),
    );
    await expectLater(OdtDocumentReader.readBytes(bytes), _refused);
  });

  for (final dimension in ['columns', 'rows']) {
    for (final value in [
      '0',
      '-1',
      '1.5',
      'NaN',
      '99999999999999999999999999',
    ]) {
      test('refuses $dimension span $value', () async {
        final bytes = _package(
          _tableXml(
            _row(
              _cell(
                '<text:p>Cell</text:p>',
                attributes: 'table:number-$dimension-spanned="$value"',
              ),
            ),
          ),
        );
        await expectLater(OdtDocumentReader.readBytes(bytes), _refused);
      });
    }
  }

  test(
    'generated vertical continuations consume the native paragraph budget',
    () async {
      final bytes = _package(_verticalTable(3, 1));
      final document = await OdtDocumentReader.readBytes(
        bytes,
        limits: const OdfZoteroLimits(maxParagraphs: 3),
      );
      expect(_bodyTable(document).rows, hasLength(3));
      expect(document.paragraphs, hasLength(3));
      await expectLater(
        OdtDocumentReader.readBytes(
          bytes,
          limits: const OdfZoteroLimits(maxParagraphs: 2),
        ),
        throwsA(isA<OdfZoteroLimitException>()),
      );
    },
  );

  test(
    'cell budget counts 4096 native origins and continuations together',
    () async {
      final document = await OdtDocumentReader.readBytes(
        _package(_verticalTable(128, 32)),
      );
      final table = _bodyTable(document);
      expect(table.grid, hasLength(32));
      expect(table.rows, hasLength(128));
      expect(
        table.rows.fold<int>(0, (sum, row) => sum + row.cells.length),
        4096,
      );
      expect(
        table.rows.first.cells.every(
          (cell) => cell.vMerge == WmlVMerge.restart,
        ),
        isTrue,
      );
      expect(
        table.rows.last.cells.every((cell) => cell.vMerge == WmlVMerge.cont),
        isTrue,
      );
      await expectLater(
        OdtDocumentReader.readBytes(_package(_verticalTable(129, 32))),
        throwsA(isA<OdfZoteroLimitException>()),
      );
    },
  );

  test('nested table cells share the parent continuation budget', () async {
    final nested = _tableXml(_row(ordinary));
    await expectLater(
      OdtDocumentReader.readBytes(
        _package(
          _verticalTable(
            128,
            32,
            firstContents: '<text:p>Outer</text:p>$nested',
          ),
        ),
      ),
      throwsA(isA<OdfZoteroLimitException>()),
    );
  });

  test('row budget permits 256 actual rows and refuses the 257th', () async {
    final document = await OdtDocumentReader.readBytes(
      _package(_verticalTable(256, 1)),
    );
    expect(_bodyTable(document).rows, hasLength(256));
    final tooMany = _verticalTable(
      256,
      1,
    ).replaceFirst('</table:table>', '${_row(ordinary)}</table:table>');
    await expectLater(
      OdtDocumentReader.readBytes(_package(tooMany)),
      throwsA(isA<OdfZoteroLimitException>()),
    );
  });
}
