import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

OpcPackage _native() => OpcPackage.openBytes(
  File(
    'test/fixtures/fidelity/sheet-normal-font-native.xlsx',
  ).readAsBytesSync(),
);

SmlColumnMetrics _measured(SmlNormalFont font) => const SmlColumnMetrics(
  maximumDigitWidthPx: 19,
  resolvedFontFamily: 'Liberation Mono',
);

XmlElement _columns(OpcPackage package) => XmlDocument.parse(
  package.getPart('/xl/worksheets/sheet1.xml')!.readText(),
).root!.firstChild('cols')!;

void main() {
  test('Normal selection follows builtin identity and both indexed links', () {
    final font = SheetDeserializer().read(_native()).styles!.normalFont!;
    // The first font, first style XF, first cell XF and English name all point
    // elsewhere. This fixture's localized built-in Normal resolves font 2.
    expect(font.family, 'Liberation Mono');
    expect(font.sizePoints, 24);
    expect(font.bold, isFalse);
    expect(font.italic, isFalse);
  });

  test('theme Latin font takes precedence over the cached font name', () {
    final package = _native();
    final source = package
        .getPart('/xl/styles.xml')!
        .readText()
        .replaceFirst(
          '<name val="Liberation Mono"/>',
          '<name val="Cached face"/><scheme val="minor"/>',
        );
    final faces = SmlStyleSheet.parseThemeFontFamilies(
      '<a:theme xmlns:a="${OfficeNamespaces.a}"><a:themeElements>'
      '<a:fontScheme name="Test"><a:majorFont><a:latin typeface="Major"/>'
      '</a:majorFont><a:minorFont><a:latin typeface="Minor"/>'
      '<a:ea typeface="Not the ASCII face"/></a:minorFont></a:fontScheme>'
      '</a:themeElements></a:theme>',
    );
    final styles = SmlStyleSheet.parse(source, themeFontFamilies: faces);
    expect(styles.normalFont!.family, 'Minor');
    expect(SmlStyleSheet.parse(source).normalFont!.family, 'Cached face');
  });

  test('bold and italic are measured properties of the selected Normal', () {
    final source = _native()
        .getPart('/xl/styles.xml')!
        .readText()
        .replaceFirst('<b val="0"/>', '<b/>')
        .replaceFirst('<i val="false"/>', '<i val="1"/>');
    final font = SmlStyleSheet.parse(source).normalFont!;
    expect(font.bold, isTrue);
    expect(font.italic, isTrue);
  });

  test('ambiguous, invalid and absent Normal links remain unresolved', () {
    final source = _native().getPart('/xl/styles.xml')!.readText();
    for (final broken in <String>[
      source.replaceFirst('builtinId="1"', 'builtinId="0"'),
      source.replaceFirst(
        'name="Standard" xfId="1"',
        'name="Standard" xfId="9"',
      ),
      source.replaceFirst('fontId="2"', 'fontId="99"'),
      source.replaceFirst('val="24"', 'val="NaN"'),
      source.replaceFirst('builtinId="0"', 'builtinId="3"'),
    ]) {
      expect(SmlStyleSheet.parse(broken).normalFont, isNull);
    }
    expect(SmlStyleSheet().normalFont, isNull);
  });

  test(
    'pure-engine unresolved opens preserve native widths and provenance',
    () {
      final book = SheetDeserializer().read(_native());
      expect(book.columnMetrics, isNull);
      expect(book.firstSheet.maximumDigitWidthPx, 7);
      expect(book.firstSheet.columnWidth(0), 61);
      expect(book.firstSheet.columnWidth(1), 61);
      expect(book.firstSheet.columnWidth(3), 72);
      expect(book.resolveColumnMetrics((_) => null), isFalse);
      expect(book.firstSheet.columnWidth(0), 61);
      expect(book.firstSheet.exportColumnWidth(0), 8.7109375);
      expect(book.firstSheet.exportColumnWidth(1), 8.72);
    },
  );

  test(
    'resolver projects native explicit and default widths before layout',
    () {
      final book = SheetDeserializer(
        columnMetricsResolver: _measured,
      ).read(_native());
      final sheet = book.firstSheet;
      expect(book.columnMetrics!.resolvedFontFamily, 'Liberation Mono');
      expect(
        book.columnMetrics!.substitutes(book.styles!.normalFont!),
        isFalse,
      );
      expect(sheet.maximumDigitWidthPx, 19);
      // Authored scalar expectations evaluated independently of engine helpers.
      expect(
        [for (var c = 0; c < 4; c++) sheet.columnWidth(c)],
        [165, 166, 418, 195],
      );
      expect(sheet.columnLeft(1), 165);
      expect(sheet.columnLeft(2), 331);
      expect(sheet.columnLeft(3), 749);
      expect(sheet.columnLeft(4), 944);
      for (final point in <(double, int)>[
        (164.9, 0),
        (165, 1),
        (330.9, 1),
        (331, 2),
        (748.9, 2),
        (749, 3),
        (943.9, 3),
        (944, 4),
      ]) {
        expect(sheet.columnAt(point.$1), point.$2);
      }
    },
  );

  test('base widths add pixel padding and omitted defaults remain bounded', () {
    final source = _native();
    final part = source.getPart('/xl/worksheets/sheet1.xml')!;
    part.writeText(
      part.readText().replaceFirst(' defaultColWidth="10.25"', ''),
    );
    final book = SheetDeserializer(
      columnMetricsResolver: _measured,
    ).read(source);
    expect(book.firstSheet.columnWidth(3), 157); // 8*19+5, no double padding.
    part.writeText(part.readText().replaceFirst('baseColWidth="8" ', ''));
    final omitted = SheetDeserializer(
      columnMetricsResolver: _measured,
    ).read(source);
    expect(omitted.firstSheet.columnWidth(3), 64);
  });

  test('zero native default width cannot divide hit-testing by zero', () {
    final source = _native();
    final part = source.getPart('/xl/worksheets/sheet1.xml')!;
    part.writeText(
      part.readText().replaceFirst(
        'defaultColWidth="10.25"',
        'defaultColWidth="0"',
      ),
    );
    final sheet = SheetDeserializer(
      columnMetricsResolver: _measured,
    ).read(source).firstSheet;
    expect(sheet.columnWidth(3), 0);
    expect(sheet.columnAt(748), 2);
    expect(sheet.columnAt(750), SmlWorksheet.excelColumnCount - 1);
    sheet.columnWidths.clear();
    expect(sheet.columnAt(1), SmlWorksheet.excelColumnCount - 1);
  });

  test(
    'late metric resolution preserves explicit API and direct pixel edits',
    () {
      final book = SheetDeserializer().read(_native());
      final sheet = book.firstSheet;
      sheet.setColumnWidth(0, 96);
      sheet.columnWidths[1] = 123;
      expect(book.resolveColumnMetrics(_measured), isTrue);
      expect(sheet.columnWidth(0), 96);
      expect(sheet.columnWidth(1), 123);
      expect(sheet.columnWidth(2), 418);
      expect(sheet.exportColumnWidth(0), 5.05078125);
      expect(sheet.exportColumnWidth(1), 6.47265625);
      expect(sheet.exportColumnWidth(2), 22);
      expect(sheet.exportColumnProperties(0)['customWidth'], '1');
      expect(sheet.exportColumnProperties(1)['customWidth'], '1');
    },
  );

  test(
    'direct pixel edits cannot regain stale native provenance at a later metric',
    () {
      final book = SheetDeserializer().read(_native());
      final sheet = book.firstSheet;
      sheet.columnWidths[1] =
          166; // Edited at MDW7; native 8.72 projects to 61.
      book.resolveColumnMetrics(
        _measured,
      ); // The old native width also maps to 166 at MDW19.
      expect(sheet.columnWidth(1), 166);
      book.resolveColumnMetrics(
        (_) => const SmlColumnMetrics(
          maximumDigitWidthPx: 12,
          resolvedFontFamily: 'Other face',
        ),
      );
      expect(sheet.columnWidth(1), 166); // Must not become native 8.72 -> 105.
      expect(sheet.captureColumn(1).nativeWidth, isNull);
    },
  );

  test(
    'column and grid snapshots discard mismatched direct-edit provenance',
    () {
      for (final grid in [false, true]) {
        final book = SheetDeserializer().read(_native());
        final sheet = book.firstSheet;
        sheet.columnWidths[1] = 166;
        final snapshot = sheet.captureColumn(1);
        final all = sheet.captureColumns();
        expect(snapshot.nativeWidth, isNull);
        expect(all[1]!.nativeWidth, isNull);
        book.resolveColumnMetrics(_measured);
        if (grid) {
          sheet.restoreColumns(all);
        } else {
          sheet.restoreColumn(1, snapshot);
        }
        book.resolveColumnMetrics(
          (_) => const SmlColumnMetrics(
            maximumDigitWidthPx: 12,
            resolvedFontFamily: 'Other face',
          ),
        );
        expect(sheet.columnWidth(1), 166);
      }
    },
  );

  test(
    'observed direct removals and export mismatches invalidate native association',
    () {
      final book = SheetDeserializer().read(_native());
      final sheet = book.firstSheet;
      sheet.columnWidths[1] = 166;
      sheet.exportColumnWidth(
        1,
      ); // Observe the mismatch before the caller edits again.
      sheet.columnWidths[1] = 61;
      book.resolveColumnMetrics(_measured);
      expect(sheet.columnWidth(1), 61);
      sheet.columnWidths.remove(0);
      book.resolveColumnMetrics(
        (_) => const SmlColumnMetrics(
          maximumDigitWidthPx: 12,
          resolvedFontFamily: 'Other face',
        ),
      );
      expect(sheet.captureColumn(0).nativeWidth, isNull);
      sheet.columnWidths[0] = 105;
      book.resolveColumnMetrics(_measured);
      expect(sheet.columnWidth(0), 105);
    },
  );

  test(
    'column history reprojects native states and preserves unrelated flags',
    () {
      final book = SheetDeserializer().read(_native());
      final sheet = book.firstSheet;
      final before = sheet.captureColumn(1);
      sheet.setColumnWidth(1, 96);
      final after = sheet.captureColumn(1);
      sheet.columnProperties[1]!['hidden'] = '1';
      book.resolveColumnMetrics(_measured);
      sheet.restoreColumn(1, before, widthOnly: true);
      expect(sheet.columnWidth(1), 166);
      expect(sheet.exportColumnWidth(1), 8.72);
      expect(sheet.columnProperties[1]!['hidden'], '1');
      sheet.restoreColumn(1, after, widthOnly: true);
      expect(sheet.columnWidth(1), 96);
      expect(sheet.exportColumnWidth(1), 5.05078125);
    },
  );

  test(
    'grid history preserves native widths across inserts and font resolution',
    () {
      final book = SheetDeserializer().read(_native());
      final sheet = book.firstSheet;
      final snapshot = sheet.captureColumns();
      sheet.insertCols(1);
      book.resolveColumnMetrics(_measured);
      sheet.restoreColumns(snapshot);
      expect(sheet.columnWidth(1), 166);
      expect(sheet.columnWidth(2), 418);
      expect(sheet.exportColumnWidth(1), 8.72);
      expect(sheet.exportColumnProperties(1)['customWidth'], '1');
    },
  );

  test(
    'new sheets inherit the measured metric before native serialization',
    () {
      final book = SheetDeserializer(
        columnMetricsResolver: _measured,
      ).read(_native());
      final added = SmlWorksheet(name: 'Added', sheetId: 2)
        ..setColumnWidth(0, 96);
      added.importColumnWidth(1, 8.72);
      book.sheets.add(added);
      final saved = SheetSerializer().write(book);
      expect(added.maximumDigitWidthPx, 19);
      expect(added.columnWidth(0), 96);
      expect(added.columnWidth(1), 166);
      final xml = XmlDocument.parse(
        saved.getPart(added.sourcePartUri!)!.readText(),
      );
      expect(
        xml.root!
            .firstChild('cols')!
            .childElements
            .map((col) => col.getAttribute('width')),
        ['5.05078125', '8.72'],
      );
    },
  );

  test('invalid metric results leave all sheets and provenance unchanged', () {
    final book = SheetDeserializer(
      columnMetricsResolver: _measured,
    ).read(_native());
    final prior = book.columnMetrics;
    final priorWidths = Map<int, double>.of(book.firstSheet.columnWidths);
    for (final bad in [
      const SmlColumnMetrics(
        maximumDigitWidthPx: 0,
        resolvedFontFamily: 'Face',
      ),
      const SmlColumnMetrics(maximumDigitWidthPx: 19, resolvedFontFamily: ''),
    ]) {
      expect(() => book.resolveColumnMetrics((_) => bad), throwsArgumentError);
      expect(book.columnMetrics, same(prior));
      expect(book.firstSheet.columnWidths, priorWidths);
    }
  });

  test('font substitution is explicit and remeasurement is stable', () {
    final book = SheetDeserializer(
      columnMetricsResolver: _measured,
    ).read(_native());
    const substitute = SmlColumnMetrics(
      maximumDigitWidthPx: 12,
      resolvedFontFamily: 'Another face',
    );
    book.resolveColumnMetrics((_) => substitute);
    expect(book.columnMetrics!.substitutes(book.styles!.normalFont!), isTrue);
    expect(book.firstSheet.columnWidth(2), 264);
    book.resolveColumnMetrics(_measured);
    expect(book.firstSheet.columnWidth(2), 418);
    expect(book.firstSheet.exportColumnWidth(1), 8.72);
    book.firstSheet.insertCols(0);
    book.firstSheet.deleteCols(0);
    expect(book.firstSheet.exportColumnWidth(1), 8.72);
  });

  test(
    'unchanged native widths and styles survive three direct/isolate saves',
    () async {
      var book = SheetDeserializer(
        columnMetricsResolver: _measured,
      ).read(_native());
      final output = Directory('build/fidelity-sheet-normal-font')
        ..createSync(recursive: true);
      for (var cycle = 1; cycle <= 3; cycle++) {
        final bytes = cycle == 2
            ? await OfficeIsolateSave.workbook(book)
            : SheetSerializer().writeBytes(book);
        File('${output.path}/unchanged-$cycle.xlsx').writeAsBytesSync(bytes);
        final package = OpcPackage.openBytes(bytes);
        expect(
          _columns(
            package,
          ).childElements.map((column) => column.getAttribute('width')),
          ['8.7109375', '8.72', '22.0'],
        );
        book = SheetDeserializer(
          columnMetricsResolver: _measured,
        ).read(package);
        expect(book.firstSheet.columnWidth(1), 166);
        expect(book.firstSheet.columnWidth(2), 418);
      }
    },
  );

  test(
    'native width precision and edited pixels survive three direct/isolate saves',
    () async {
      var book = SheetDeserializer(
        columnMetricsResolver: _measured,
      ).read(_native());
      book.firstSheet.setColumnWidth(2, 96);
      final output = Directory('build/fidelity-sheet-normal-font')
        ..createSync(recursive: true);
      File('${output.path}/source.xlsx').writeAsBytesSync(
        File(
          'test/fixtures/fidelity/sheet-normal-font-native.xlsx',
        ).readAsBytesSync(),
      );
      for (var cycle = 1; cycle <= 3; cycle++) {
        final bytes = cycle == 2
            ? await OfficeIsolateSave.workbook(book)
            : SheetSerializer().writeBytes(book);
        File('${output.path}/normal-font-$cycle.xlsx').writeAsBytesSync(bytes);
        final package = OpcPackage.openBytes(bytes);
        final columns = _columns(package).childElements.toList();
        expect(columns.map((column) => column.getAttribute('width')), [
          '8.7109375',
          '8.72',
          '5.05078125',
        ]);
        final format = XmlDocument.parse(
          package.getPart('/xl/worksheets/sheet1.xml')!.readText(),
        ).root!.firstChild('sheetFormatPr')!;
        expect(format.getAttribute('defaultColWidth'), '10.25');
        expect(format.getAttribute('baseColWidth'), '8');
        book = SheetDeserializer(
          columnMetricsResolver: _measured,
        ).read(package);
        expect(
          [for (var c = 0; c < 4; c++) book.firstSheet.columnWidth(c)],
          [165, 166, 96, 195],
        );
        expect(book.styles!.normalFont!.family, 'Liberation Mono');
        expect(book.styles!.normalFont!.sizePoints, 24);
      }
    },
  );
}
