import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/automation/office_operations.dart';
import 'package:test/test.dart';

import '../tool/fidelity/sheet_steps.dart' as legacy;

OfficeOperationDocument _formulaDocument(
  SmlWorkbook book, {
  int maxCellVisits = 100000,
}) => OfficeOperationDocument.open(
  SheetSerializer().writeBytes(book, recalculate: false),
  OfficeMacroFormat.xlsx,
  maxCellVisits: maxCellVisits,
);

void main() {
  test(
    'formula preflight refuses full-sheet SUM before dependency expansion',
    () async {
      final document = _formulaDocument(SmlWorkbook());
      document.apply('xlsx.cellFormula', {
        'cell': 'A1',
        'formula': '=SUM(A1:XFD1048576)',
      });
      await expectLater(
        document.save(recalculate: true),
        throwsA(isA<OfficeOperationLimitException>()),
      );
    },
  );

  test('formula preflight charges named and structured data ranges', () async {
    for (final structured in [false, true]) {
      final book = SmlWorkbook();
      final range = SmlRange.parse('A1:A1048576');
      final String formula;
      if (structured) {
        book.firstSheet.cellA1('A1').value = 'Amount';
        book.firstSheet.tables.add(SmlTable(name: 'Data', range: range));
        formula = '=SUM(Data[Amount])';
      } else {
        book.namedRanges.add(
          SmlNamedRange(
            name: 'Data',
            sheetName: book.firstSheet.name,
            range: range,
          ),
        );
        formula = '=SUM(Data)';
      }
      final document = _formulaDocument(book);
      document.apply('xlsx.cellFormula', {'cell': 'B1', 'formula': formula});
      await expectLater(
        document.save(recalculate: true),
        throwsA(isA<OfficeOperationLimitException>()),
        reason: structured ? 'Structured table range' : 'Defined range',
      );
    }
  });

  test('ordinary SUM and bounded literal text formulas recalculate', () async {
    final book = SmlWorkbook();
    book.firstSheet.cellA1('A1').value = 2;
    book.firstSheet.cellA1('A2').value = 3;
    final document = _formulaDocument(book);
    document.apply('xlsx.cellFormula', {
      'cell': 'B1',
      'formula': '=SUM(A1:A2)',
    });
    document.apply('xlsx.cellFormula', {
      'cell': 'B2',
      'formula': '=REPT("ok",3)',
    });
    final saved = SheetDeserializer().readBytes(
      await document.save(recalculate: true),
    );
    expect(saved.firstSheet.cellA1('B1').value, 5);
    expect(saved.firstSheet.cellA1('B2').value, 'okokok');
  });

  test('LET bindings do not resolve shadowed enormous named ranges', () async {
    final book = SmlWorkbook();
    book.namedRanges.add(
      SmlNamedRange(
        name: 'Data',
        sheetName: book.firstSheet.name,
        range: SmlRange.parse('A1:A1048576'),
      ),
    );
    final document = _formulaDocument(book);
    document.apply('xlsx.cellFormula', {
      'cell': 'B1',
      'formula': '=LET(Data,1,Data+1)',
    });
    final saved = SheetDeserializer().readBytes(
      await document.save(recalculate: true),
    );
    expect(saved.firstSheet.cellA1('B1').value, 2);
  });

  test(
    'formula preflight refuses dynamic references and unbounded generators',
    () async {
      for (final formula in [
        '=OFFSET(A1,0,0,1048576,16384)',
        '=INDIRECT("A1:XFD1048576")',
        '=_xlfn.INDIRECT("A1")',
        '=REPT("x",1000000000)',
        '=REPT("x",A2)',
        '=LET(N,1000000000,REPT("x","N"))',
        '=LET(CONCAT("N",""),1000000000,REPT("x","N"))',
        '=LET("X","N","X",1000000000,REPT("x","N"))',
        '=SUBSTITUTE("abc","",REPT("x",10000))',
        '=NETWORKDAYS(0,100000000)',
        '=NETWORKDAYS(A2,A3)',
        '=NETWORKDAYS("0001-01-01","999999-01-01")',
      ]) {
        final document = _formulaDocument(SmlWorkbook());
        document.apply('xlsx.cellFormula', {'cell': 'A1', 'formula': formula});
        await expectLater(
          document.save(recalculate: true),
          throwsA(isA<OfficeOperationLimitException>()),
          reason: formula,
        );
      }
    },
  );

  test('SEQUENCE charges its engine ceiling before calculation', () async {
    final document = _formulaDocument(SmlWorkbook(), maxCellVisits: 5000);
    document.apply('xlsx.cellFormula', {
      'cell': 'A1',
      'formula': '=SEQUENCE(2,2)',
    });
    await expectLater(
      document.save(recalculate: true),
      throwsA(isA<OfficeOperationLimitException>()),
    );
  });

  test('formula preflight bounds source, parser tokens, and nesting', () async {
    for (final formula in [
      '="${'x' * 8192}"',
      '${'(' * 65}1${')' * 65}',
      List<String>.filled(257, '1').join('+'),
      List<String>.filled(70, '1').join('+'),
    ]) {
      final document = _formulaDocument(SmlWorkbook());
      document.apply('xlsx.cellFormula', {'cell': 'A1', 'formula': formula});
      await expectLater(
        document.save(recalculate: true),
        throwsA(isA<OfficeOperationLimitException>()),
      );
    }
  });

  test(
    'format-only operations preserve existing dynamic formula caches',
    () async {
      final book = SmlWorkbook();
      book.firstSheet.cellA1('A1').value = 5;
      book.firstSheet.cellA1('B1')
        ..formula = 'INDIRECT("A1")'
        ..type = SmlCellType.formula
        ..value = 73;
      final document = _formulaDocument(book);
      document.apply('xlsx.cellFormat', {'cell': 'A1', 'bold': true});
      document.apply('xlsx.freeze', {'rows': 1});
      final saved = SheetDeserializer().readBytes(
        await document.save(recalculate: true),
      );
      expect(saved.firstSheet.cellA1('A1').fontBold, isTrue);
      expect(saved.firstSheet.cellA1('B1').formula, 'INDIRECT("A1")');
      expect(saved.firstSheet.cellA1('B1').value, 73);
    },
  );

  test(
    'ordinary unsupported formulas retain native caches on semantic edits',
    () async {
      final book = SmlWorkbook();
      book.firstSheet.cellA1('B1')
        ..formula = 'UNMODELED(1)'
        ..type = SmlCellType.formula
        ..value = 77;
      final document = _formulaDocument(book);
      document.apply('xlsx.cellValue', {'cell': 'A1', 'value': 5});
      final saved = SheetDeserializer().readBytes(
        await document.save(recalculate: true),
      );
      expect(saved.firstSheet.cellA1('A1').value, 5);
      expect(saved.firstSheet.cellA1('B1').value, 77);
    },
  );

  test(
    'private document enforces expanded byte limits on serialized output',
    () async {
      final bytes = SheetSerializer().writeBytes(
        SmlWorkbook(),
        recalculate: false,
      );
      final sourceSize = ZipReader.fromBytes(
        bytes,
      ).entries.fold<int>(0, (sum, entry) => sum + entry.uncompressedSize);
      final document = OfficeOperationDocument.open(
        bytes,
        OfficeMacroFormat.xlsx,
        maxExpandedBytes: sourceSize + 64,
      );
      document.apply('xlsx.cellValue', {'cell': 'A1', 'value': 'x' * 4096});
      await expectLater(
        document.save(),
        throwsA(isA<OfficeOperationLimitException>()),
      );
    },
  );

  test(
    'private operation document preserves catalog semantics and recalculation',
    () async {
      final bytes = SheetSerializer().writeBytes(
        SmlWorkbook(),
        recalculate: false,
      );
      final document = OfficeOperationDocument.open(
        bytes,
        OfficeMacroFormat.xlsx,
      );
      document.apply('xlsx.cellValue', {'cell': 'A1', 'value': 21});
      document.apply('xlsx.cellFormula', {'cell': 'A2', 'formula': '=A1*2'});
      final saved = SheetDeserializer().readBytes(
        await document.save(recalculate: true),
      );
      expect(saved.firstSheet.cellA1('A1').value, 21);
      expect(saved.firstSheet.cellA1('A2').value, 42);
    },
  );

  test(
    'private operation document edits native PPTX without decoding binary parts as XML',
    () async {
      final document = OfficeOperationDocument.open(
        File('test/fixtures/fidelity/native.pptx').readAsBytesSync(),
        OfficeMacroFormat.pptx,
      );
      document.apply('pptx.slideNotes', {'slide': 0, 'text': 'Macro notes'});
      final saved = SlideDeserializer().readBytes(await document.save());
      expect(saved.slides.first.notes, 'Macro notes');
    },
  );

  test(
    'merge budget rejects an enormous legal Excel range before allocation',
    () async {
      final bytes = SheetSerializer().writeBytes(
        SmlWorkbook(),
        recalculate: false,
      );
      final document = OfficeOperationDocument.open(
        bytes,
        OfficeMacroFormat.xlsx,
        maxCellVisits: 4,
      );
      expect(
        () => document.apply('xlsx.mergeCells', {'range': 'A1:XFD1048576'}),
        throwsA(isA<OfficeOperationLimitException>()),
      );
      final saved = SheetDeserializer().readBytes(await document.save());
      expect(saved.firstSheet.allCells, isEmpty);
      expect(saved.firstSheet.merges, isEmpty);
      expect(
        () => document.apply('xlsx.mergeCells', {'range': 'A1:XFE1'}),
        throwsArgumentError,
      );
    },
  );

  test('work budget accumulates table growth using current geometry', () async {
    final bytes = WordSerializer().writeBytes(WmlDocument());
    final document = OfficeOperationDocument.open(
      bytes,
      OfficeMacroFormat.docx,
      maxCellVisits: 6,
    );
    document.apply('docx.tableAdd', {'rows': 2, 'columns': 2, 'width': 100});
    document.apply('docx.tableRowInsert', {'table': 0, 'row': 2});
    expect(
      () => document.apply('docx.tableColumnInsert', {'table': 0, 'column': 2}),
      throwsA(isA<OfficeOperationLimitException>()),
    );
    final saved = WordDeserializer().readBytes(await document.save());
    final table = saved.sections.first.blocks.whereType<WmlTable>().single;
    expect(table.rows, hasLength(3));
    expect(table.grid, hasLength(2));
  });

  test('package preflight enforces expanded byte and part limits', () {
    final bytes = OpcPackage.create(OpcPackageKind.sheet).save();
    expect(
      () => OfficeOperationCatalog.open(
        bytes,
        OfficeMacroFormat.xlsx,
        maxExpandedBytes: 20,
      ),
      throwsA(isA<OfficeOperationLimitException>()),
    );
    expect(
      () => OfficeOperationCatalog.open(
        bytes,
        OfficeMacroFormat.xlsx,
        maxPackageParts: 1,
      ),
      throwsA(isA<OfficeOperationLimitException>()),
    );
  });

  test(
    'package preflight bounds actual inflation when declared length is zero',
    () {
      final writer = ZipWriter();
      writer.addFile(
        'payload.xml',
        Uint8List.fromList(List<int>.filled(8192, 65)),
      );
      final bytes = writer.close();
      final data = ByteData.sublistView(bytes);
      var patched = false;
      for (var at = 0; at + 46 <= bytes.length; at++) {
        if (data.getUint32(at, Endian.little) == zipCentralSig) {
          data.setUint32(at + 24, 0, Endian.little);
          patched = true;
          break;
        }
      }
      expect(patched, isTrue);
      expect(
        () => OfficeOperationCatalog.open(
          bytes,
          OfficeMacroFormat.xlsx,
          maxExpandedBytes: 1024,
        ),
        throwsA(isA<OfficeOperationLimitException>()),
      );
    },
  );

  test('package preflight rejects duplicate ZIP names', () {
    final writer = ZipWriter();
    writer.addFile('payload.xml', utf8.encode('<a/>'));
    writer.addFile('payload.xml', utf8.encode('<b/>'));
    expect(
      () => OfficeOperationCatalog.open(writer.close(), OfficeMacroFormat.xlsx),
      throwsA(isA<ZipDuplicateEntryException>()),
    );
  });

  test('catalog and legacy steps retain the same worksheet vocabulary', () {
    final book = SmlWorkbook();
    final prior = SmlWorkbook();
    const steps = <Map<String, Object?>>[
      {'op': 'cellValue', 'cell': 'A1', 'value': 7},
      {'op': 'cellFormula', 'cell': 'A2', 'formula': '=A1*2'},
      {'op': 'cellFormat', 'cell': 'A1', 'bold': true, 'fill': '12AB34'},
      {'op': 'freeze', 'rows': 1, 'columns': 1},
      {'op': 'renameSheet', 'name': 'Summary'},
    ];
    for (final step in steps) {
      legacy.applySheetStep(prior, step);
      final arguments = Map<String, Object?>.of(step)..remove('op');
      OfficeOperationCatalog.apply(book, 'xlsx.${step['op']}', arguments);
    }
    expect(OfficeOperationCatalog.inspect(book), legacy.inspectSheet(prior));
    expect(book.firstSheet.cellA1('A1').fontBold, isTrue);
    expect(book.firstSheet.cellA1('A1').fillRgb, '12AB34');
    expect(book.firstSheet.cellA1('A2').formula, 'A1*2');
    expect(
      () => OfficeOperationCatalog.fields(OfficeMacroFormat.xlsx)['custom'] =
          <String>[],
      throwsUnsupportedError,
    );
    expect(
      () => OfficeOperationCatalog.fields(
        OfficeMacroFormat.xlsx,
      )['cellValue']!.add('custom'),
      throwsUnsupportedError,
    );
  });

  test('unknown fields and cross-family tool names fail before editing', () {
    final book = SmlWorkbook();
    for (final arguments in <Map<String, Object?>>[
      {'cell': 'A1', 'value': 9, 'unexpected': true},
      {'cell': 'A1', 'value': 9, 'op': 'cellValue'},
    ]) {
      expect(
        () => OfficeOperationCatalog.apply(book, 'xlsx.cellValue', arguments),
        throwsArgumentError,
      );
    }
    for (final name in ['docx.cellValue', 'cellValue', 'xlsx.missing']) {
      expect(
        () => OfficeOperationCatalog.apply(book, name, {
          'cell': 'A1',
          'value': 9,
        }),
        throwsArgumentError,
      );
    }
    expect(book.firstSheet.allCells, isEmpty);
  });

  test('named worksheet selectors follow renames and reordering', () {
    final book = SmlWorkbook(
      sheets: <SmlWorksheet>[
        SmlWorksheet(name: 'Data', sheetId: 1),
        SmlWorksheet(name: 'Summary', sheetId: 2),
      ],
    );
    OfficeOperationCatalog.apply(book, 'xlsx.cellValue', {
      'sheet': 'sUmMaRy',
      'cell': 'A1',
      'value': 9,
    });
    OfficeOperationCatalog.apply(book, 'xlsx.renameSheet', {
      'sheet': 'summary',
      'name': 'Results',
    });
    OfficeOperationCatalog.apply(book, 'xlsx.sheetOrder', {
      'sheet': 'RESULTS',
      'to': 0,
    });
    legacy.applySheetStep(book, {
      'op': 'cellFormat',
      'sheet': 'results',
      'cell': 'A1',
      'bold': true,
    });
    expect(book.firstSheet.name, 'Results');
    expect(book.firstSheet.cellA1('A1').value, 9);
    expect(book.firstSheet.cellA1('A1').fontBold, isTrue);
    OfficeOperationCatalog.apply(book, 'xlsx.cellValue', {
      'sheet': 1,
      'cell': 'B1',
      'value': 12,
    });
    expect(book.sheets[1].name, 'Data');
    expect(book.sheets[1].cellA1('B1').value, 12);
    expect(
      () => OfficeOperationCatalog.apply(book, 'xlsx.cellValue', {
        'sheet': 'Summary',
        'cell': 'A1',
        'value': 99,
      }),
      throwsArgumentError,
    );
  });

  test('worksheet selectors reject missing ambiguous and invalid targets', () {
    final book = SmlWorkbook(
      sheets: <SmlWorksheet>[
        SmlWorksheet(name: 'Data', sheetId: 1),
        SmlWorksheet(name: 'DATA', sheetId: 2),
      ],
    );
    for (final selector in <Object?>['data', 'missing', '', null, 0.0, -1, 2]) {
      expect(
        () => OfficeOperationCatalog.apply(book, 'xlsx.cellValue', {
          'sheet': selector,
          'cell': 'A1',
          'value': 9,
        }),
        throwsArgumentError,
        reason: 'selector: $selector',
      );
    }
    expect(book.sheets.every((sheet) => sheet.allCells.isEmpty), isTrue);
  });

  test('image arguments are host keys and deny implicit file access', () {
    final document = WmlDocument();
    const arguments = <String, Object?>{
      'file': '/not/a/real/path.png',
      'width': 10,
      'height': 10,
    };
    expect(
      () => OfficeOperationCatalog.apply(document, 'docx.imageAdd', arguments),
      throwsUnsupportedError,
    );
    expect(document.visuals, isEmpty);
    final bytes = PngBytes.fromRgb(
      width: 1,
      height: 1,
      pixels: Uint8List.fromList([255, 0, 0]),
    );
    final expected = Uint8List.fromList(bytes);
    final resolved = <String>[];
    OfficeOperationCatalog.apply(
      document,
      'docx.imageAdd',
      arguments,
      resolveAsset: (key) {
        resolved.add(key);
        return bytes;
      },
    );
    bytes.fillRange(0, bytes.length, 0);
    expect(resolved, ['/not/a/real/path.png']);
    expect(document.visuals.single.visual.imageBytes, expected);
  });

  test('model protections and tracked changes deny macro editing', () {
    for (final document in [
      WmlDocument(restrictEditing: true),
      WmlDocument(protectionFormattingRestricted: true),
      WmlDocument(trackRevisions: true),
    ]) {
      expect(
        () => OfficeOperationCatalog.assertEditable(document),
        throwsUnsupportedError,
      );
    }
    final book = SmlWorkbook();
    book.firstSheet.protection = SmlSheetProtection();
    expect(
      () => OfficeOperationCatalog.apply(book, 'xlsx.cellValue', {
        'cell': 'A1',
        'value': 9,
      }),
      throwsUnsupportedError,
    );
    expect(book.firstSheet.allCells, isEmpty);
  });

  test(
    'native password-to-modify and workbook protection are not bypassed',
    () {
      final book = SmlWorkbook(
        package: OpcPackage.create(OpcPackageKind.sheet),
      );
      book.package!
          .getPart('/xl/workbook.xml')!
          .writeText(
            '<s:workbook xmlns:s="${OfficeNamespaces.x}">'
            '<s:workbookProtection/>'
            '</s:workbook>',
          );
      expect(
        () => OfficeOperationCatalog.assertEditable(book),
        returnsNormally,
      );
      book.package!
          .getPart('/xl/workbook.xml')!
          .writeText(
            '<s:workbook xmlns:s="${OfficeNamespaces.x}">'
            '<s:workbookProtection lockStructure="1"/>'
            '</s:workbook>',
          );
      expect(
        () => OfficeOperationCatalog.assertEditable(book),
        throwsUnsupportedError,
      );
      final presentation = PmlPresentation(
        package: OpcPackage.create(OpcPackageKind.slide),
      );
      presentation.package!
          .getPart('/ppt/presentation.xml')!
          .writeText(
            '<s:presentation xmlns:s="${OfficeNamespaces.p}">'
            '<s:modifyVerifier hashData="opaque" saltData="opaque"/>'
            '</s:presentation>',
          );
      expect(
        () => OfficeOperationCatalog.assertEditable(presentation),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'newly authored locked content controls are refused without a package',
    () {
      final document = WmlDocument();
      final control = WmlContentControlData(
        xml:
            '<q:sdt xmlns:q="${OfficeNamespaces.w}"><q:sdtPr>'
            '<q:lock q:val="sdtContentLocked"/>'
            '</q:sdtPr><q:sdtContent/></q:sdt>',
        sourcePartUri: '/word/document.xml',
        relationships: const <WmlOpaqueRelationship>[],
      );
      document.sections.first.blocks.add(
        WmlContentControlBlock(
          control: control,
          blocks: [
            WmlParagraph(inlines: [WmlRun(text: 'Original')]),
          ],
        ),
      );
      expect(
        () => OfficeOperationCatalog.apply(document, 'docx.replaceText', {
          'paragraph': 0,
          'text': 'Changed',
        }),
        throwsUnsupportedError,
      );
      expect(document.paragraphs.single.text, 'Original');
    },
  );

  test('open checks document family and keeps signature admission', () {
    final source = OpcPackage.create(OpcPackageKind.sheet);
    expect(
      () => OfficeOperationCatalog.open(source.save(), OfficeMacroFormat.docx),
      throwsFormatException,
    );
    source.createPart(
      '/_xmlsignatures/sig1.xml',
      'application/vnd.openxmlformats-package.digital-signature-xmlsignature+xml',
      utf8.encode('<signature/>'),
    );
    expect(
      () => OfficeOperationCatalog.open(source.save(), OfficeMacroFormat.xlsx),
      throwsFormatException,
    );
  });

  test(
    'catalog editing and save preserve opaque VBA bytes and package type',
    () async {
      final source = OpcPackage.openBytes(
        File('test/fixtures/fidelity/native.xlsx').readAsBytesSync(),
      );
      source.getPart('/xl/workbook.xml')!.contentType =
          'application/vnd.ms-excel.sheet.macroEnabled.main+xml';
      source.contentTypes.setOverride(
        '/xl/workbook.xml',
        'application/vnd.ms-excel.sheet.macroEnabled.main+xml',
      );
      final vba = Uint8List.fromList([0, 1, 2, 253, 254, 255]);
      source.createPart(
        '/xl/vbaProject.bin',
        'application/vnd.ms-office.vbaProject',
        vba,
      );
      source
          .relationshipsFor('/xl/workbook.xml')
          .add(
            type:
                'http://schemas.microsoft.com/office/2006/relationships/vbaProject',
            target: 'vbaProject.bin',
          );
      final document = OfficeOperationCatalog.open(
        source.save(),
        OfficeMacroFormat.xlsx,
      );
      OfficeOperationCatalog.apply(document, 'xlsx.cellValue', {
        'cell': 'A1',
        'value': 'Macro edit',
      });
      final saved = OpcPackage.openBytes(
        await OfficeOperationCatalog.save(document),
      );
      expect(saved.getPart('/xl/vbaProject.bin')!.readBytes(), vba);
      expect(
        saved.getPart('/xl/workbook.xml')!.contentType,
        contains('macroEnabled'),
      );
      expect(
        SheetDeserializer().read(saved).firstSheet.cellA1('A1').value,
        'Macro edit',
      );
    },
  );
}
