import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

OpcPackage _nativePackage() => OpcPackage.openBytes(
  File('test/fixtures/fidelity/native.xlsx').readAsBytesSync(),
);

Iterable<XmlElement> _descendants(XmlElement root, String name) sync* {
  for (final child in root.childElements) {
    if (child.localName == name) yield child;
    yield* _descendants(child, name);
  }
}

void _assertDrawingSchema(OpcPackage package) {
  final rels = package.relationshipsFor('/xl/worksheets/sheet1.xml');
  final drawing = rels.byType(RelationshipTypes.drawing).single;
  final part = package.getPart(rels.resolve(drawing))!;
  final xml = XmlDocument.parse(part.readText());
  final frame = _descendants(xml.root!, 'graphicFrame').single;
  expect(frame.firstChild('xfrm')!.namespaceUri, OfficeNamespaces.xdr);
  expect(frame.firstChild('xfrm')!.firstChild('off'), isNotNull);
  expect(frame.firstChild('xfrm')!.firstChild('ext'), isNotNull);
}

void main() {
  test('absolute drawing targets remain a single relationship on save', () {
    var book = SheetDeserializer().read(_nativePackage());
    for (var cycle = 1; cycle <= 3; cycle++) {
      final package = SheetSerializer().write(book);
      _assertDrawingSchema(package);
      book = SheetDeserializer().read(package);
      expect(book.firstSheet.drawings, hasLength(1));
    }
  });

  test('repairs equivalent absolute and relative drawing relationships', () {
    final source = _nativePackage();
    source
        .relationshipsFor('/xl/worksheets/sheet1.xml')
        .add(
          type: RelationshipTypes.drawing,
          target: '../drawings/drawing1.xml',
        );
    final package = SheetSerializer().write(SheetDeserializer().read(source));
    _assertDrawingSchema(package);
  });

  test('pivot cache relationship survives removal of invalid root r:id', () {
    var book = SheetDeserializer().read(_nativePackage());
    for (var cycle = 1; cycle <= 3; cycle++) {
      final package = SheetSerializer().write(book);
      final pivot = XmlDocument.parse(
        package.getPart('/xl/pivotTables/pivotTable1.xml')!.readText(),
      ).root!;
      expect(
        pivot.getAttribute('id', namespaceUri: OfficeNamespaces.r),
        isNull,
      );
      expect(pivot.getAttribute('cacheId'), '1');
      expect(pivot.firstChild('dataFields')!.childElements, hasLength(1));
      final cache = package
          .relationshipsFor('/xl/pivotTables/pivotTable1.xml')
          .byType('${OfficeNamespaces.r}/pivotCacheDefinition')
          .single;
      expect(
        package.getPart(
          package
              .relationshipsFor('/xl/pivotTables/pivotTable1.xml')
              .resolve(cache),
        ),
        isNotNull,
      );
      book = SheetDeserializer().read(package);
      expect(book.sheets[1].pivots.single.name, 'NativePivot');
    }
  });

  test('font edits retain imported formatting and use schema child order', () {
    final package = _nativePackage();
    final part = package.getPart('/xl/styles.xml')!;
    final source = XmlDocument.parse(part.readText());
    final formats = source.root!.firstChild('numFmts')!;
    formats
      ..setAttribute('count', '1')
      ..addChild(
        XmlElement(localName: 'numFmt')
          ..setAttribute('numFmtId', '164')
          ..setAttribute('formatCode', '#,##0.0000;[Red](#,##0.0000)'),
      );
    source.root!
        .firstChild('cellXfs')!
        .childElements
        .elementAt(2)
        .setAttribute('numFmtId', '164');
    final font = source.root!.firstChild('fonts')!.childElements.first;
    font.children.insert(2, XmlElement(localName: 'i'));
    font.children.insert(5, XmlElement(localName: 'u'));
    part.writeText(source.toXmlString());
    var book = SheetDeserializer().read(package);
    book.firstSheet.cellA1('B2')
      ..fontBold = true
      ..fontSize = 16
      ..fontRgb = 'A1B2C3'
      ..horizontalAlign = SmlHAlign.center;
    final evidence = Directory('build/fidelity-schema')
      ..createSync(recursive: true);
    for (var cycle = 1; cycle <= 3; cycle++) {
      final bytes = SheetSerializer().writeBytes(book);
      File('${evidence.path}/sheet-style-$cycle.xlsx').writeAsBytesSync(bytes);
      final saved = OpcPackage.openBytes(bytes);
      final styles = XmlDocument.parse(
        saved.getPart('/xl/styles.xml')!.readText(),
      );
      final sheet = XmlDocument.parse(
        saved.getPart('/xl/worksheets/sheet1.xml')!.readText(),
      );
      final cell = _descendants(
        sheet.root!,
        'c',
      ).singleWhere((cell) => cell.getAttribute('r') == 'B2');
      final xf = styles.root!
          .firstChild('cellXfs')!
          .childElements
          .elementAt(int.parse(cell.getAttribute('s')!));
      expect(xf.getAttribute('numFmtId'), '164');
      expect(xf.getAttribute('borderId'), '1');
      final edited = styles.root!
          .firstChild('fonts')!
          .childElements
          .elementAt(int.parse(xf.getAttribute('fontId')!));
      expect(edited.childElements.map((element) => element.localName), [
        'b',
        'i',
        'u',
        'sz',
        'color',
        'name',
        'family',
        'scheme',
      ]);
      expect(edited.firstChild('name')!.getAttribute('val'), 'Calibri');
      expect(edited.firstChild('scheme')!.getAttribute('val'), 'minor');
      expect(edited.firstChild('color')!.getAttribute('rgb'), 'FFA1B2C3');
      expect(edited.firstChild('sz')!.getAttribute('val'), '16.0');
      expect(
        styles.root!
            .firstChild('numFmts')!
            .childElements
            .single
            .getAttribute('formatCode'),
        '#,##0.0000;[Red](#,##0.0000)',
      );
      _assertDrawingSchema(saved);
      book = SheetDeserializer().read(saved);
    }
  });

  test('newly generated font children follow the font schema sequence', () {
    final styles = SmlStyleSheet();
    styles.xfFor(fontRgb: '112233', bold: true, size: 18);
    final xml = XmlDocument.parse(styles.toXml());
    expect(
      xml.root!
          .firstChild('fonts')!
          .childElements
          .last
          .childElements
          .map((element) => element.localName),
      ['b', 'sz', 'color', 'name'],
    );
  });

  test('stored column widths use the ISO maximum-digit-width formula', () {
    // Published ISO example: eight displayed characters, with padding,
    // are stored as 8.7109375 and rendered as 61 pixels for Calibri 11.
    expect(SmlWorksheet.columnWidthFromExcel(8.7109375), 61);
    expect(SmlWorksheet.columnWidthFromExcel(22), 154);
    expect(
      SmlWorksheet.columnWidthFromExcel(SmlWorksheet.excelDefaultColumnWidth),
      64,
    );
    for (final mdw in [5, 7, 9, 12]) {
      for (final pixels in [8, 61, 64, 96, 154, 800]) {
        final width = SmlWorksheet.columnWidthToExcel(
          pixels.toDouble(),
          maximumDigitWidth: mdw,
        );
        expect(
          SmlWorksheet.columnWidthFromExcel(width, maximumDigitWidth: mdw),
          pixels,
        );
      }
    }
  });

  test(
    'untouched width precision survives save cycles and column insertion',
    () {
      var book = SheetDeserializer().read(_nativePackage());
      book.firstSheet.importColumnWidth(1, 8.7109375);
      book.firstSheet.importColumnWidth(2, 8.72);
      expect(book.firstSheet.columnWidth(0), 154);
      expect(book.firstSheet.columnWidth(1), 61);
      expect(book.firstSheet.columnWidth(2), 61);
      book.firstSheet.insertCols(0);
      book.firstSheet.deleteCols(0);
      for (var cycle = 1; cycle <= 3; cycle++) {
        final bytes = SheetSerializer().writeBytes(book);
        final saved = OpcPackage.openBytes(bytes);
        final columns = XmlDocument.parse(
          saved.getPart('/xl/worksheets/sheet1.xml')!.readText(),
        ).root!.firstChild('cols')!.childElements.toList();
        expect(columns, hasLength(3));
        expect(columns.map((c) => c.getAttribute('width')), [
          '22.0',
          '8.7109375',
          '8.72',
        ]);
        book = SheetDeserializer().read(saved);
      }
    },
  );

  test('an edited column exports the requested 96-pixel width', () {
    var book = SheetDeserializer().read(_nativePackage());
    book.firstSheet.columnWidths[0] = 96;
    for (var cycle = 1; cycle <= 3; cycle++) {
      final saved = SheetSerializer().write(book);
      final col = XmlDocument.parse(
        saved.getPart('/xl/worksheets/sheet1.xml')!.readText(),
      ).root!.firstChild('cols')!.childElements.single;
      final raw = double.parse(col.getAttribute('width')!);
      // Independent authored expectation for Calibri 11, not a reader call.
      expect(raw, 13.7109375);
      expect(((raw * 256 + 18) / 256 * 7).floor(), 96);
      book = SheetDeserializer().read(saved);
      expect(book.firstSheet.columnWidth(0), 96);
    }
  });

  test(
    'column flags and default styles survive edits and width-less ranges',
    () {
      final source = _nativePackage();
      final part = source.getPart('/xl/worksheets/sheet1.xml')!;
      final xml = XmlDocument.parse(part.readText());
      final cols = xml.root!.firstChild('cols')!;
      cols.children.clear();
      cols.addChild(
        XmlElement(localName: 'col')
          ..setAttribute('min', '1')
          ..setAttribute('max', '2')
          ..setAttribute('width', '22')
          ..setAttribute('customWidth', '0')
          ..setAttribute('hidden', '1')
          ..setAttribute('outlineLevel', '2')
          ..setAttribute('collapsed', '1')
          ..setAttribute('style', '2')
          ..setAttribute('bestFit', '1')
          ..setAttribute('phonetic', '1'),
      );
      cols.addChild(
        XmlElement(localName: 'col')
          ..setAttribute('min', '3')
          ..setAttribute('max', '3')
          ..setAttribute('hidden', '1')
          ..setAttribute('style', '1'),
      );
      part.writeText(xml.toXmlString());
      var book = SheetDeserializer().read(source);
      book.firstSheet.columnWidths[0] = 96;
      book.firstSheet.insertCols(1);
      expect(book.firstSheet.columnProperties[2]!['outlineLevel'], '2');
      expect(book.firstSheet.columnProperties[3]!['style'], '1');
      book.firstSheet.deleteCols(1);
      final evidence = Directory('build/fidelity-schema')
        ..createSync(recursive: true);
      for (var cycle = 1; cycle <= 3; cycle++) {
        final bytes = SheetSerializer().writeBytes(book);
        File(
          '${evidence.path}/column-metadata-$cycle.xlsx',
        ).writeAsBytesSync(bytes);
        final saved = OpcPackage.openBytes(bytes);
        final columns = XmlDocument.parse(
          saved.getPart('/xl/worksheets/sheet1.xml')!.readText(),
        ).root!.firstChild('cols')!.childElements.toList();
        expect(columns, hasLength(3));
        expect(columns[0].getAttribute('width'), '13.7109375');
        expect(columns[0].getAttribute('customWidth'), '1');
        expect(columns[1].getAttribute('width'), '22.0');
        expect(columns[1].getAttribute('customWidth'), '0');
        for (final column in columns.take(2)) {
          expect(column.getAttribute('hidden'), '1');
          expect(column.getAttribute('outlineLevel'), '2');
          expect(column.getAttribute('collapsed'), '1');
          expect(column.getAttribute('style'), '2');
          expect(column.getAttribute('bestFit'), '1');
          expect(column.getAttribute('phonetic'), '1');
        }
        expect(columns[2].getAttribute('width'), isNull);
        expect(columns[2].getAttribute('hidden'), '1');
        expect(columns[2].getAttribute('style'), '1');
        book = SheetDeserializer().read(saved);
      }
    },
  );
}
