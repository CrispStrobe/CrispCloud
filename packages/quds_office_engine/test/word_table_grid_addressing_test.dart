import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/fidelity/office_steps.dart' as cli;

const _nativeTable = '''
<w:tbl><w:tblPr/><w:tblGrid>
<w:gridCol w:w="1200"/><w:gridCol w:w="1200"/>
<w:gridCol w:w="1200"/><w:gridCol w:w="1200"/>
</w:tblGrid>
<w:tr><w:tc><w:tcPr><w:gridSpan w:val="2"/><w:vMerge w:val="restart"/></w:tcPr>
<w:p><w:r><w:t>Master</w:t></w:r></w:p></w:tc>
<w:tc><w:p><w:r><w:t>Top neighbor</w:t></w:r></w:p></w:tc>
<w:tc><w:p><w:r><w:t>Top last</w:t></w:r></w:p></w:tc></w:tr>
<w:tr><w:tc><w:tcPr><w:gridSpan w:val="2"/><w:vMerge/></w:tcPr><w:p/></w:tc>
<w:tc><w:p><w:r><w:t>Bottom neighbor</w:t></w:r></w:p></w:tc>
<w:tc><w:p><w:r><w:t>Bottom last</w:t></w:r></w:p></w:tc></w:tr>
<w:tr><w:tc><w:p><w:r><w:t>Third first</w:t></w:r></w:p></w:tc>
<w:tc><w:p><w:r><w:t>Third second</w:t></w:r></w:p></w:tc>
<w:tc><w:tcPr><w:gridSpan w:val="2"/></w:tcPr>
<w:p><w:r><w:t>Third last</w:t></w:r></w:p></w:tc></w:tr></w:tbl>''';

const _omittedTable =
    '<w:tbl><w:tblPr/><w:tblGrid><w:gridCol w:w="1200"/>'
    '<w:gridCol w:w="1200"/><w:gridCol w:w="1200"/><w:gridCol w:w="1200"/>'
    '</w:tblGrid><w:tr><w:trPr><w:gridBefore w:val="1"/>'
    '<w:gridAfter w:val="1"/></w:trPr>'
    '<w:tc><w:p><w:r><w:t>First physical</w:t></w:r></w:p></w:tc>'
    '<w:tc><w:p><w:r><w:t>Second physical</w:t></w:r></w:p></w:tc>'
    '</w:tr></w:tbl>';

// tableCellText authors a new plain paragraph, including the public defaults:
// Arial 11pt, black, left aligned, 1.15 lines and 8pt after spacing. This native
// expectation replaces only the first cell's paragraph in the authored source;
// it never reads an engine export or serializes a model to create its baseline.
const _omittedEditedTable =
    '<w:tbl><w:tblPr/><w:tblGrid><w:gridCol w:w="1200"/>'
    '<w:gridCol w:w="1200"/><w:gridCol w:w="1200"/><w:gridCol w:w="1200"/>'
    '</w:tblGrid><w:tr><w:trPr><w:gridBefore w:val="1"/>'
    '<w:gridAfter w:val="1"/></w:trPr>'
    '<w:tc><w:p><w:pPr><w:spacing w:before="0" w:after="160" '
    'w:line="276" w:lineRule="auto"/><w:ind w:left="0" w:right="0"/>'
    '<w:jc w:val="left"/></w:pPr><w:r><w:rPr>'
    '<w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="Arial"/>'
    '<w:b w:val="0"/><w:i w:val="0"/><w:color w:val="000000"/>'
    '<w:sz w:val="22"/></w:rPr><w:t>Still editable</w:t></w:r></w:p></w:tc>'
    '<w:tc><w:p><w:r><w:t>Second physical</w:t></w:r></w:p></w:tc>'
    '</w:tr></w:tbl>';

OpcPackage _package([String body = _nativeTable]) {
  final package = OpcPackage.create(OpcPackageKind.word);
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="${OfficeNamespaces.w}"><w:body>$body'
        '<w:sectPr/></w:body></w:document>',
      );
  return package;
}

WmlDocument _source() => WordDeserializer().read(_package());
WmlTable _table(WmlDocument doc) =>
    doc.sections.single.blocks.single as WmlTable;
String _text(WmlTableCell cell) => WmlClone.plainTextOf(cell.blocks);
String _state(WmlDocument doc) => jsonEncode(cli.inspectWord(doc));

Map<String, Object?> _step(String op, Map<String, Object?> args) => {
  'op': op,
  'table': 0,
  'row': 1,
  ...args,
};

void _write(String name, List<int> bytes) {
  final file = File('build/fidelity-table-grid/$name.docx');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes);
}

void main() {
  test('all slots in a native two-dimensional merge resolve to its master', () {
    final table = _table(_source());
    expect(WordTable.supportsGridAddressing(table), isTrue);
    for (final row in [0, 1]) {
      for (final grid in [0, 1]) {
        final selected = WordTable.cellAtGrid(table, row, grid)!;
        expect((selected.row, selected.col), (0, 0));
        expect(selected.cell, same(table.rows.first.cells.first));
      }
    }
    final neighbor = WordTable.cellAtGrid(table, 1, 2)!;
    expect((neighbor.row, neighbor.col), (1, 1));
    expect(_text(neighbor.cell), 'Bottom neighbor');
    expect(WordTable.cellAtGrid(table, 1, 4), isNull);
    expect(WordTable.cellAtGrid(table, -1, 0), isNull);
  });

  test(
    'physical selectors retain their meaning while logical selectors edit masters',
    () {
      final doc = _source();
      final table = _table(doc);
      cli.applyStep(
        doc,
        _step('tableCellText', {'column': 1, 'text': 'Physical'}),
      );
      expect(_text(table.rows[1].cells[1]), 'Physical');
      expect(_text(table.rows[0].cells[0]), 'Master');
      cli.applyStep(
        doc,
        _step('tableCellText', {'gridColumn': 1, 'text': 'Logical'}),
      );
      expect(_text(table.rows[0].cells[0]), 'Logical');
      expect(_text(table.rows[1].cells[0]), '');
      expect(_text(table.rows[1].cells[1]), 'Physical');
      cli.applyStep(
        doc,
        _step('tableCellFormat', {'gridColumn': 1, 'fill': '123456'}),
      );
      expect(table.rows[0].cells[0].fillColor, '123456');
      expect(table.rows[1].cells[0].fillColor, isNull);
      expect(table.rows[1].cells[1].fillColor, isNull);
    },
  );

  for (final op in ['tableCellText', 'tableCellFormat', 'tableUnmerge']) {
    test('$op rejects ambiguous and invalid logical selectors atomically', () {
      final doc = _source();
      final before = _state(doc);
      final extra = op == 'tableCellText'
          ? {'text': 'Changed'}
          : <String, Object?>{};
      for (final args in <Map<String, Object?>>[
        {'column': 1, 'gridColumn': 1},
        {'gridColumn': -1},
        {'gridColumn': 4},
        {'gridColumn': 1.5},
        {'gridColumn': '1'},
        {},
      ]) {
        expect(
          () => cli.applyStep(doc, _step(op, {...args, ...extra})),
          throwsArgumentError,
        );
        expect(_state(doc), before);
      }
    });
  }

  test('invalid cell properties leave resolved native masters unchanged', () {
    final doc = _source();
    final before = _state(doc);
    expect(
      () => cli.applyStep(
        doc,
        _step('tableCellFormat', {
          'gridColumn': 1,
          'fill': 'ABCDEF',
          'width': 0,
        }),
      ),
      throwsArgumentError,
    );
    expect(_state(doc), before);
    expect(
      () => cli.applyStep(
        doc,
        _step('tableCellText', {'gridColumn': 1, 'text': 123}),
      ),
      throwsArgumentError,
    );
    expect(_state(doc), before);
  });

  test(
    'partial vertical merge rectangles reject without stranding continuations',
    () {
      final doc = _source();
      final table = _table(doc);
      final before = _state(doc);
      for (final row in [0, 1]) {
        expect(WordTable.canMerge(table, row, 0, row, 2), isFalse);
        expect(
          () => cli.applyStep(doc, {
            'op': 'tableMerge',
            'table': 0,
            'row': row,
            'gridColumn': 0,
            'endRow': row,
            'endGridColumn': 2,
          }),
          throwsArgumentError,
        );
        expect(_state(doc), before);
      }
      expect(
        WordTable.canMerge(table, 0, 0, 1, 1),
        isFalse,
        reason: 'The rectangle is one existing visible cell',
      );
    },
  );

  test(
    'a containing merge preserves ordered content and untouched neighbors',
    () {
      final doc = _source();
      final table = _table(doc);
      final before = _state(doc);
      expect(
        () => cli.applyStep(doc, {
          'op': 'tableMerge',
          'table': 0,
          'row': 0,
          'column': 0,
          'gridColumn': 0,
          'endRow': 1,
          'endGridColumn': 2,
        }),
        throwsArgumentError,
      );
      expect(_state(doc), before);
      final topLast = table.rows[0].cells.last;
      final bottomLast = table.rows[1].cells.last;
      final originalContinuation = table.rows[1].cells[0].blocks.single;
      cli.applyStep(doc, {
        'op': 'tableMerge',
        'table': 0,
        'row': 0,
        'gridColumn': 0,
        'endRow': 1,
        'endGridColumn': 2,
      });
      expect(table.rows[0].cells[0].gridSpan, 3);
      expect(
        WordTree.paragraphs(table.rows[0].cells[0].blocks).map((p) => p.text),
        ['Master', 'Top neighbor', 'Bottom neighbor'],
      );
      expect(table.rows[1].cells[0].blocks.single, same(originalContinuation));
      expect(table.rows[0].cells.last, same(topLast));
      expect(table.rows[1].cells.last, same(bottomLast));
      expect(WordTable.supportsGridAddressing(table), isTrue);
    },
  );

  for (final defect in [
    'orphan',
    'span mismatch',
    'shifted continuation',
    'ragged',
    'invalid span',
  ]) {
    test(
      '$defect topology rejects grid access and unmerge before mutation',
      () {
        final doc = _source();
        final table = _table(doc);
        switch (defect) {
          case 'orphan':
            table.rows[0].cells[0].vMerge = WmlVMerge.none;
          case 'span mismatch':
            table.rows[1].cells[0].gridSpan = 1;
            table.rows[1].cells[1].gridSpan = 2;
          case 'shifted continuation':
            final continuation = table.rows[1].cells.removeAt(0);
            table.rows[1].cells.insert(1, continuation);
          case 'ragged':
            table.rows[2].cells.removeLast();
          case 'invalid span':
            table.rows[2].cells[0].gridSpan = 0;
        }
        final before = _state(doc);
        expect(WordTable.supportsGridAddressing(table), isFalse);
        expect(() => WordTable.cellAtGrid(table, 1, 1), throwsArgumentError);
        expect(WordTable.canMerge(table, 0, 0, 1, 2), isFalse);
        expect(WordTable.canUnmerge(table, 1, 0), isFalse);
        WordTable.unmerge(table, 1, 0);
        expect(_state(doc), before);
      },
    );
  }

  test(
    'logical edit and continuation unmerge survive three direct/isolate saves',
    () async {
      var doc = _source();
      _write('source', _package().save());
      cli.applyStep(
        doc,
        _step('tableCellText', {'gridColumn': 1, 'text': 'Edited master'}),
      );
      cli.applyStep(doc, _step('tableUnmerge', {'gridColumn': 1}));
      for (var cycle = 0; cycle < 3; cycle++) {
        final bytes = cycle == 1
            ? await OfficeIsolateSave.word(doc)
            : WordSerializer().write(doc).save();
        _write('edited-${cycle + 1}', bytes);
        doc = WordDeserializer().readBytes(bytes);
        final table = _table(doc);
        expect(table.rows.take(2).map((row) => row.cells.length), [4, 4]);
        expect(_text(table.rows[0].cells[0]), 'Edited master');
        expect(_text(table.rows[1].cells[0]), '');
        expect(_text(table.rows[1].cells[2]), 'Bottom neighbor');
        expect(
          table.rows
              .take(2)
              .expand((row) => row.cells)
              .every(
                (cell) => cell.gridSpan == 1 && cell.vMerge == WmlVMerge.none,
              ),
          isTrue,
        );
        expect(WordTable.supportsGridAddressing(table), isTrue);
      }
    },
  );

  test(
    'inspect exposes both coordinate systems without changing physical cell order',
    () {
      final inspected = cli.inspectWord(_source());
      final table =
          (inspected['tables']! as List<Object?>).single
              as Map<String, Object?>;
      expect(table['gridAddressingSupported'], isTrue);
      final row =
          (table['rows']! as List<Object?>).first as Map<String, Object?>;
      final cells = (row['cells']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(cells.map((cell) => cell['column']), [0, 1, 2]);
      expect(cells.map((cell) => cell['gridColumn']), [0, 2, 3]);
      expect(cells.map((cell) => cell['endGridColumn']), [1, 2, 3]);
    },
  );

  test(
    'native omitted-grid source remains unchanged through three saves',
    () async {
      final package = _package(_omittedTable);
      _write('omitted-source', package.save());
      var doc = WordDeserializer().read(package);
      for (var cycle = 0; cycle < 3; cycle++) {
        final bytes = cycle == 1
            ? await OfficeIsolateSave.word(doc)
            : WordSerializer().write(doc).save();
        _write('omitted-${cycle + 1}', bytes);
        doc = WordDeserializer().readBytes(bytes);
        final row = _table(doc).rows.single;
        expect((row.gridBefore, row.gridAfter), (1, 1));
        expect(row.cells.map(_text), ['First physical', 'Second physical']);
      }
    },
  );

  test(
    'physical text edits preserve omitted-grid metadata through three saves',
    () async {
      final package = _package(_omittedTable);
      _write('omitted-edited-expected', _package(_omittedEditedTable).save());
      var doc = WordDeserializer().read(package);
      final clone = WmlClone.table(_table(doc));
      expect(
        (clone.rows.single.gridBefore, clone.rows.single.gridAfter),
        (1, 1),
      );
      cli.applyStep(
        doc,
        _step('tableCellText', {
          'row': 0,
          'column': 0,
          'text': 'Still editable',
        }),
      );
      for (var cycle = 0; cycle < 3; cycle++) {
        final table = _table(doc);
        expect(
          (table.rows.single.gridBefore, table.rows.single.gridAfter),
          (1, 1),
        );
        expect(_text(table.rows.single.cells.first), 'Still editable');
        final before = _state(doc);
        for (final mutate in <void Function()>[
          () => WordTable.insertRow(table, 0),
          () => WordTable.deleteRow(table, 0),
          () => WordTable.insertColumn(table, 0),
          () => WordTable.deleteColumn(table, 0),
          () => WordTable.autoFitContents(table),
          () => WordTable.autoFitWindow(table, 300),
          () => WordTable.autoFitFixed(table),
          () => WordTable.constrainToWidth(table, 100),
        ]) {
          expect(mutate, throwsUnsupportedError);
          expect(_state(doc), before);
        }
        for (final step in [
          _step('tableCellText', {'row': 0, 'gridColumn': 1, 'text': 'Wrong'}),
          _step('tableCellFormat', {
            'row': 0,
            'gridColumn': 1,
            'fill': 'ABCDEF',
          }),
          _step('tableMerge', {
            'row': 0,
            'column': 0,
            'endRow': 0,
            'endColumn': 1,
          }),
          {'op': 'tableColumnInsert', 'table': 0, 'column': 1},
        ]) {
          expect(() => cli.applyStep(doc, step), throwsArgumentError);
          expect(_state(doc), before);
        }
        final bytes = cycle == 1
            ? await OfficeIsolateSave.word(doc)
            : WordSerializer().write(doc).save();
        _write('omitted-edited-${cycle + 1}', bytes);
        final xml = OpcPackage.openBytes(
          bytes,
        ).getPart('/word/document.xml')!.readText();
        expect(xml, contains('w:gridBefore w:val="1"'));
        expect(xml, contains('w:gridAfter w:val="1"'));
        doc = WordDeserializer().readBytes(bytes);
      }
    },
  );

  test(
    'current row omissions do not come from nested prior row properties',
    () {
      final package = _package(
        '<w:tbl><w:tblPr/><w:tblGrid><w:gridCol w:w="1200"/>'
        '<w:gridCol w:w="1200"/></w:tblGrid><w:tr><w:trPr>'
        '<w:gridBefore w:val="1"/>'
        '<w:trPrChange w:id="1" w:author="Author"><w:trPr>'
        '<w:gridBefore w:val="9"/><w:gridAfter w:val="8"/>'
        '</w:trPr></w:trPrChange></w:trPr>'
        '<w:tc><w:p/></w:tc></w:tr></w:tbl>',
      );
      final row = _table(WordDeserializer().read(package)).rows.single;
      expect((row.gridBefore, row.gridAfter), (1, 0));
    },
  );

  for (final key in ['column', 'gridColumn']) {
    test('$key story replacement preflights a cross-cell bookmark', () {
      final doc = _source();
      final table = _table(doc);
      final master = table.rows[0].cells[0].blocks.single as WmlParagraph;
      final neighbor = table.rows[0].cells[1].blocks.single as WmlParagraph;
      master.inlines.insert(
        0,
        WmlBookmarkBoundary(id: '77', isStart: true, name: 'CrossCell'),
      );
      neighbor.inlines.add(WmlBookmarkBoundary(id: '77', isStart: false));
      final before = _state(doc);
      expect(
        () => cli.applyStep(
          doc,
          _step('tableCellText', {'row': 0, key: 0, 'text': 'Lost'}),
        ),
        throwsArgumentError,
      );
      expect(_state(doc), before);
      expect(table.rows[0].cells[0].blocks.single, same(master));
      expect(WordBookmarks.ranges(doc), hasLength(1));
    });
  }

  test(
    'whole in-cell bookmarks can be removed without dangling identities',
    () {
      final doc = _source();
      final cell = _table(doc).rows[0].cells[0];
      final paragraph = cell.blocks.single as WmlParagraph;
      paragraph.inlines.insert(
        0,
        WmlBookmarkBoundary(id: '78', isStart: true, name: 'InCell'),
      );
      paragraph.inlines.add(WmlBookmarkBoundary(id: '78', isStart: false));
      cli.applyStep(
        doc,
        _step('tableCellText', {'gridColumn': 1, 'text': 'Replacement'}),
      );
      expect(_text(cell), 'Replacement');
      expect(WordBookmarks.ranges(doc), isEmpty);
    },
  );

  test(
    'pending revisions cannot be detached and legacy later targets stay bound',
    () {
      final doc = _source();
      final cell = _table(doc).rows[0].cells[0];
      final paragraph = cell.blocks.single as WmlParagraph;
      final revision = WmlRevision(
        id: 1,
        kind: WmlRevisionKind.insert,
        paragraphIndex: 0,
        start: 0,
        end: 6,
        text: 'Master',
      );
      doc.revisions.add(revision);
      final before = _state(doc);
      expect(
        () => cli.applyStep(
          doc,
          _step('tableCellText', {'gridColumn': 1, 'text': 'Lost'}),
        ),
        throwsArgumentError,
      );
      expect(_state(doc), before);
      expect(
        revision.targetParagraph,
        isNull,
        reason: 'Rejected preflight does not capture legacy target metadata',
      );
      expect(cell.blocks.single, same(paragraph));
      doc.revisions.clear();
      cell.blocks.add(WmlParagraph(inlines: [WmlRun(text: 'Extra paragraph')]));
      final neighbor =
          _table(doc).rows[0].cells[1].blocks.single as WmlParagraph;
      final later = WmlRevision(
        id: 2,
        kind: WmlRevisionKind.insert,
        paragraphIndex: 2,
        start: 0,
        end: 3,
        text: 'Top',
      );
      doc.revisions.add(later);
      cli.applyStep(
        doc,
        _step('tableCellText', {'gridColumn': 1, 'text': 'Shorter story'}),
      );
      expect(WordRevisions.resolveParagraph(doc, later), same(neighbor));
      expect(later.accepted, isNull);
    },
  );
}
