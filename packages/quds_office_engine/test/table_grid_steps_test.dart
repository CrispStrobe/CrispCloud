import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/fidelity/office_steps.dart' as cli;
import '../tool/fidelity/step_input.dart';
import '../tool/fidelity/word_structure_steps.dart';

OpcPackage _sourcePackage({String file = 'table_grid_source.xml'}) =>
    OpcPackage.create(OpcPackageKind.word)
      ..getPart(
        '/word/document.xml',
      )!.writeText(File('test/fixtures/fidelity/$file').readAsStringSync());

WmlDocument _source() => WordDeserializer().read(_sourcePackage());

List<WmlTable> _tables(WmlDocument doc) =>
    bodyBlocks(doc).whereType<WmlTable>().toList();

void _script(WmlDocument doc, String phase) {
  for (final step in readSteps(
    'test/fixtures/fidelity/scripts/table-grid-$phase.json',
  )) {
    cli.applyStep(doc, step);
  }
}

String _text(WmlTableCell cell) =>
    WordTree.paragraphs(cell.blocks).map((p) => p.text).join('|');

void main() {
  for (final extra in [
    '<w:tcPrChange w:id="15" w:author="Author"><w:tcPr>'
        '<w:tcW w:w="7200" w:type="dxa"/></w:tcPr></w:tcPrChange>',
    '<e:tcW xmlns:e="urn:extension" e:w="9000" e:type="pct"/>',
  ]) {
    test(
      'historical or foreign width cannot replace the current native width: $extra',
      () {
        final package = _sourcePackage();
        final part = package.getPart('/word/document.xml')!;
        part.writeText(
          part.readText().replaceFirst('</w:tcPr>', '$extra</w:tcPr>'),
        );
        final cell = _tables(
          WordDeserializer().read(package),
        )[0].rows[0].cells[0];
        expect(cell.width, 180);
        expect(cell.sourceWidthXml, contains('3600'));
        expect(cell.sourceWidthXml, isNot(contains('7200')));
        expect(cell.sourceWidthXml, isNot(contains('urn:extension')));
      },
    );
  }

  test('duplicate current native widths reject instead of choosing one', () {
    final package = _sourcePackage();
    final part = package.getPart('/word/document.xml')!;
    part.writeText(
      part.readText().replaceFirst(
        '</w:tcPr>',
        '<w:tcW w:w="7200" w:type="dxa"/></w:tcPr>',
      ),
    );
    expect(() => WordDeserializer().read(package), throwsFormatException);
  });

  test('native width namespace does not depend on the w prefix', () {
    final package = _sourcePackage();
    final part = package.getPart('/word/document.xml')!;
    part.writeText(
      part.readText().replaceFirst(
        '<w:tcW w:w="3600" w:type="dxa"/>',
        '<x:tcW xmlns:x="${OfficeNamespaces.w}" x:w="3600" x:type="dxa"/>',
      ),
    );
    var doc = WordDeserializer().read(package);
    expect(_tables(doc)[0].rows[0].cells[0].width, 180);
    doc = WordDeserializer().readBytes(WordSerializer().writeBytes(doc));
    expect(_tables(doc)[0].rows[0].cells[0].width, 180);
  });

  test('native preferred cell widths survive import and deep clone', () {
    final table = _tables(_source()).first;
    expect(table.rows[0].cells[0].width, 180);
    expect(table.rows[0].cells[1].width, isNull);
    expect(table.rows[0].cells[1].sourceWidthXml, contains('pct'));
    final clone = WmlClone.table(table);
    for (var row = 0; row < table.rows.length; row++) {
      for (var column = 0; column < table.rows[row].cells.length; column++) {
        final before = table.rows[row].cells[column];
        final after = clone.rows[row].cells[column];
        expect(after, isNot(same(before)));
        expect(after.width, before.width);
        expect(after.sourceWidthXml, before.sourceWidthXml);
        expect(after.sourceWidthPoints, before.sourceWidthPoints);
      }
    }
  });

  test('unmerge redistributes preferred widths from the logical grid', () {
    final doc = _source();
    _script(doc, 'format');
    _script(doc, 'unmerge');
    final tables = _tables(doc);
    expect(tables[0].rows[0].cells.map((c) => c.width), [90, 90, null]);
    expect(tables[0].rows[1].cells.map((c) => c.width), [90, 90, 73.25]);
    expect(tables[1].rows[0].cells.map((c) => c.width), [30, 30, 30]);
    expect(tables[0].rows[0].cells[0].sourceWidthXml, isNull);
  });

  test('merge produces the combined logical-grid preferred width', () {
    final doc = _source();
    _script(doc, 'unmerge');
    cli.applyStep(doc, {
      'op': 'tableMerge',
      'table': 0,
      'row': 0,
      'column': 0,
      'endRow': 1,
      'endColumn': 1,
    });
    final table = _tables(doc).first;
    expect(table.rows[0].cells[0].width, 180);
    expect(table.rows[1].cells[0].width, 180);
  });

  for (final invalid in [double.nan, double.infinity, -1.0]) {
    test(
      'invalid preferred width $invalid rejects before mutating package parts',
      () {
        final doc = _source();
        final before = doc.package!.getPart('/word/document.xml')!.readText();
        _tables(doc)[1].rows[0].cells[0].width = invalid;
        expect(() => WordSerializer().writeBytes(doc), throwsArgumentError);
        expect(doc.package!.getPart('/word/document.xml')!.readText(), before);
      },
    );
  }

  test('inspect exposes physical cells, logical ranges and merge owners', () {
    final inspected = cli.inspectWord(_source());
    final tables = (inspected['tables']! as List<Object?>)
        .cast<Map<String, Object?>>();
    final rows = (tables.first['rows']! as List<Object?>)
        .cast<Map<String, Object?>>();
    final cells = (rows[1]['cells']! as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(cells[0]['gridColumn'], 0);
    expect(cells[0]['endGridColumn'], 1);
    expect(cells[0]['mergeOrigin'], {'row': 0, 'column': 0, 'gridColumn': 0});
    expect(cells[1]['column'], 1);
    expect(cells[1]['gridColumn'], 2);
    expect(cells[1]['mergeOrigin'], {'row': 1, 'column': 1, 'gridColumn': 2});
    expect(tables, hasLength(2));
  });

  test('logical selection edits the visible owner and nested actual cells', () {
    final doc = _source();
    final tables = _tables(doc);
    final origin = tables[0].rows[0].cells[0];
    final bold = (origin.blocks[0] as WmlParagraph).inlines
        .whereType<WmlRun>()
        .last;
    _script(doc, 'format');
    expect(origin.fillColor, 'DDEEFF');
    expect(tables[0].rows[1].cells[0].fillColor, isNull);
    expect(_text(tables[0].rows[1].cells[1]), 'Edited middle right');
    expect(_text(tables[1].rows[0].cells[1]), 'Edited nested tail');
    expect(tables[1].rows[0].cells[0].fillColor, 'EEDDCC');
    expect((origin.blocks[0] as WmlParagraph).inlines, contains(same(bold)));
    expect(WordBookmarks.byName(doc, 'MergedOrigin'), isNotNull);
    _script(doc, 'replace');
    expect(_text(origin), 'Replaced merged owner');
    expect(_text(tables[0].rows[1].cells[0]), '');
    expect(_tables(doc), hasLength(2));
  });

  test('physical column retains its original meaning after a leading span', () {
    final doc = _source();
    cli.applyStep(doc, {
      'op': 'tableCellText',
      'table': 0,
      'row': 0,
      'column': 1,
      'text': 'Physical tail',
    });
    expect(_text(_tables(doc)[0].rows[0].cells[1]), 'Physical tail');
    expect(
      _text(_tables(doc)[0].rows[0].cells[0]),
      'Merged origin|Rich second paragraph',
    );
  });

  test(
    'unmerge accepts any covered logical coordinate and retains rich blocks',
    () {
      final doc = _source();
      final origin = _tables(doc)[0].rows[0].cells[0];
      final blocks = List<WmlBlock>.of(origin.blocks);
      _script(doc, 'format');
      _script(doc, 'unmerge');
      final tables = _tables(doc);
      expect(tables[0].rows.map((r) => r.cells.length), [3, 3, 3]);
      expect(tables[1].rows.single.cells, hasLength(3));
      expect(origin.blocks, orderedEquals(blocks));
      expect(WordBookmarks.ranges(doc), hasLength(1));
      expect(_text(tables[0].rows[1].cells[2]), 'Edited middle right');
      expect(_text(tables[1].rows[0].cells[2]), 'Edited nested tail');
    },
  );

  for (final op in ['tableCellText', 'tableCellFormat', 'tableUnmerge']) {
    for (final selector in <Map<String, Object?>>[
      {},
      {'column': 0, 'gridColumn': 0},
      {'gridColumn': -1},
      {'gridColumn': 3},
      {'gridColumn': 0.5},
      {'gridColumn': '1'},
      {'gridColumn': null},
    ]) {
      test(
        '$op rejects ambiguous or invalid selector $selector atomically',
        () {
          final doc = _source();
          final before = jsonEncode(cli.inspectWord(doc));
          expect(
            () => cli.applyStep(doc, {
              'op': op,
              'table': 0,
              'row': 1,
              ...selector,
              if (op == 'tableCellText') 'text': 'Wrong',
              if (op == 'tableCellFormat') 'fill': 'FFFFFF',
            }),
            throwsArgumentError,
          );
          expect(jsonEncode(cli.inspectWord(doc)), before);
        },
      );
    }
  }

  for (final invalid in ['orphan', 'span', 'start', 'nonpositive', 'missing']) {
    test(
      'logical edit rejects $invalid geometry and leaves the model intact',
      () {
        final doc = _source();
        final table = _tables(doc).first;
        switch (invalid) {
          case 'orphan':
            table.rows[0].cells[0].vMerge = WmlVMerge.none;
          case 'span':
            table.rows[1].cells[0].gridSpan = 1;
          case 'start':
            table.rows[1].cells.insert(0, WordTable.emptyCell());
          case 'nonpositive':
            table.rows[0].cells[1].gridSpan = 0;
          case 'missing':
            table.rows[1].cells.removeLast();
        }
        final before = jsonEncode(cli.inspectWord(doc));
        expect(
          () => cli.applyStep(doc, {
            'op': 'tableCellText',
            'table': 0,
            'row': 1,
            'gridColumn': invalid == 'missing' ? 2 : 1,
            'text': 'Wrong',
          }),
          throwsArgumentError,
        );
        expect(jsonEncode(cli.inspectWord(doc)), before);
      },
    );
  }

  test(
    'cell replacement rejects cross-cell bookmarks before discarding content',
    () {
      final package = _sourcePackage();
      final part = package.getPart('/word/document.xml')!;
      part.writeText(
        part
            .readText()
            .replaceFirst('<w:bookmarkEnd w:id="31"/>', '')
            .replaceFirst(
              '<w:t>Top right</w:t>',
              '<w:t>Top right</w:t></w:r><w:bookmarkEnd w:id="31"/><w:r>',
            ),
      );
      final doc = WordDeserializer().read(package);
      final before = jsonEncode(cli.inspectWord(doc));
      expect(
        () => cli.applyStep(doc, {
          'op': 'tableCellText',
          'table': 0,
          'row': 1,
          'gridColumn': 0,
          'text': 'Wrong',
        }),
        throwsArgumentError,
      );
      expect(jsonEncode(cli.inspectWord(doc)), before);
      expect(WordBookmarks.ranges(doc), hasLength(1));
    },
  );

  test(
    'cell replacement rejects pending revisions without changing ownership',
    () {
      final doc = _source();
      final paragraph =
          _tables(doc)[0].rows[0].cells[0].blocks[0] as WmlParagraph;
      final index = doc.paragraphs.toList().indexOf(paragraph);
      final revision = WordRevisions.record(
        doc,
        kind: WmlRevisionKind.insert,
        paragraphIndex: index,
        start: 0,
        end: 6,
        text: 'Merged',
      );
      final before = jsonEncode(cli.inspectWord(doc));
      expect(
        () => cli.applyStep(doc, {
          'op': 'tableCellText',
          'table': 0,
          'row': 1,
          'gridColumn': 1,
          'text': 'Wrong',
        }),
        throwsArgumentError,
      );
      expect(jsonEncode(cli.inspectWord(doc)), before);
      expect(WordRevisions.resolveParagraph(doc, revision), same(paragraph));
    },
  );

  for (final isolate in [false, true]) {
    test(
      '${isolate ? 'isolate' : 'direct'} authored grid scripts survive three saves',
      () async {
        const root = 'build/fidelity-table-grid';
        writeOutput('$root/source.docx', _sourcePackage().save());
        for (final phase in ['format', 'replace', 'unmerge']) {
          writeOutput(
            '$root/expected-$phase.docx',
            _sourcePackage(file: 'table_grid_${phase}_expected.xml').save(),
          );
        }
        for (final phase in ['unchanged', 'format', 'replace', 'unmerge']) {
          var doc = _source();
          if (phase != 'unchanged') _script(doc, 'format');
          if (phase == 'replace' || phase == 'unmerge') _script(doc, phase);
          for (var cycle = 1; cycle <= 3; cycle++) {
            final bytes = isolate
                ? await OfficeIsolateSave.word(doc)
                : WordSerializer().writeBytes(doc);
            writeOutput(
              '$root/${isolate ? 'isolate' : 'direct'}/$phase-$cycle.docx',
              bytes,
            );
            doc = WordDeserializer().readBytes(bytes);
            final tables = _tables(doc);
            expect(tables, hasLength(2));
            expect(
              tables[0].rows[0].cells[0].fillColor,
              phase == 'unchanged' ? null : 'DDEEFF',
            );
            expect(
              tables[0].rows[1].cells.last.width,
              phase == 'unchanged' ? 90 : 73.25,
            );
            expect(
              tables[0].rows[0].cells.last.sourceWidthXml,
              contains('pct'),
            );
            expect(tables[0].rows[2].cells[1].sourceWidthXml, contains('auto'));
            expect(tables[0].rows[2].cells[2].sourceWidthXml, contains('nil'));
            expect(
              _text(tables[0].rows[0].cells[0]),
              phase == 'replace'
                  ? 'Replaced merged owner'
                  : 'Merged origin|Rich second paragraph',
            );
            expect(
              _text(tables[1].rows[0].cells.last),
              phase == 'unchanged' ? 'Nested tail' : 'Edited nested tail',
            );
            expect(
              tables[0].rows[0].cells,
              hasLength(phase == 'unmerge' ? 3 : 2),
            );
          }
        }
      },
    );
  }

  test(
    'CLI rejects an invalid logical edit without replacing an existing output',
    () async {
      final temp = Directory.systemTemp.createTempSync('table-grid-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final input = '${temp.path}/input.docx';
      final output = File('${temp.path}/output.docx')
        ..writeAsStringSync('KEEP');
      final script = File('${temp.path}/steps.json')
        ..writeAsStringSync(
          jsonEncode([
            {
              'op': 'tableCellText',
              'table': 0,
              'row': 1,
              'gridColumn': 2,
              'text': 'Valid',
            },
            {
              'op': 'tableCellFormat',
              'table': 0,
              'row': 1,
              'gridColumn': 9,
              'fill': '112233',
            },
          ]),
        );
      writeOutput(input, _sourcePackage().save());
      await expectLater(
        cli.execute(['modify', input, script.path, output.path]),
        throwsStateError,
      );
      expect(output.readAsStringSync(), 'KEEP');
    },
  );
}
