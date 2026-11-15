import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _x = OfficeNamespaces.x;

String _styles({bool prefixed = false}) {
  final tag = prefixed ? 's:' : '';
  final binding = prefixed ? 'xmlns:s="$_x"' : 'xmlns="$_x"';
  return '<${tag}styleSheet $binding xmlns:e="urn:test:extension">'
      '<${tag}fonts count="1"><${tag}font><${tag}sz val="11"/>'
      '<${tag}name val="Calibri"/></${tag}font></${tag}fonts>'
      '<${tag}fills count="2">'
      '<${tag}fill><${tag}patternFill patternType="none"/></${tag}fill>'
      '<${tag}fill><${tag}patternFill patternType="gray125"/></${tag}fill>'
      '</${tag}fills><${tag}borders count="1"><${tag}border/></${tag}borders>'
      '<${tag}cellXfs count="4">'
      '<e:xf><e:alignment wrapText="false"/></e:xf>'
      '<${tag}xf fontId="0" fillId="0" numFmtId="0" borderId="0">'
      '<${tag}alignment horizontal="right" vertical="top" wrapText="1"/>'
      '</${tag}xf>'
      '<${tag}xf fontId="0" fillId="0" numFmtId="0" borderId="0">'
      '<${tag}alignment wrapText="0"/></${tag}xf>'
      '<${tag}xf fontId="0" fillId="0" numFmtId="0" borderId="0">'
      '<${tag}alignment wrapText="true"/></${tag}xf>'
      '<${tag}xf fontId="0" fillId="0" numFmtId="0" borderId="0"/>'
      '</${tag}cellXfs></${tag}styleSheet>';
}

int _derive(SmlStyleSheet styles, int base, {SmlHAlign? align, bool? wrap}) =>
    styles.xfFor(
      baseStyleIndex: base,
      align: align ?? styles.alignAt(base),
      fillRgb: styles.fillAt(base),
      fontRgb: styles.fontAt(base),
      bold: styles.boldAt(base),
      size: styles.sizeAt(base),
      wrapText: wrap,
    );

XmlElement _alignment(String xml, int index) =>
    XmlDocument.parse(xml).root!
        .firstChild('cellXfs', namespaceUri: _x)!
        .childrenNamed('xf', namespaceUri: _x)[index]
        .firstChild('alignment', namespaceUri: _x)!;

void main() {
  for (final prefixed in [false, true]) {
    test('wrap flags keep exact XF indices (prefixed=$prefixed)', () {
      final styles = SmlStyleSheet.parse(_styles(prefixed: prefixed));
      expect(styles.cellXfsWrap, [true, false, true, false]);
      expect(
        [for (var i = 0; i < 4; i++) styles.wrapAt(i)],
        [true, false, true, false],
      );
      expect(styles.wrapAt(-1), isFalse);
      expect(styles.wrapAt(4), isFalse);
    });
  }

  test('new unwrapped format does not reuse an existing wrapped format', () {
    final styles = SmlStyleSheet(cellXfsWrap: [true]);
    final plain = styles.xfFor();
    expect(plain, isNot(0));
    expect(styles.wrapAt(plain), isFalse);
    expect(styles.xfFor(wrapText: true), 0);
    expect(styles.xfFor(), plain);
    expect(styles.cellXfsWrap, [true, false]);
  });

  test('alignment edits retain inherited wrap across repeated exports', () {
    var styles = SmlStyleSheet.parse(_styles());
    var index = _derive(styles, 0, align: SmlHAlign.center);
    final count = styles.cellXfsAlign.length;
    for (var cycle = 0; cycle < 3; cycle++) {
      expect(styles.wrapAt(index), isTrue);
      final xml = styles.toXml();
      final alignment = _alignment(xml, index);
      expect(alignment.getAttribute('wrapText'), '1');
      expect(alignment.getAttribute('horizontal'), 'center');
      expect(alignment.getAttribute('vertical'), 'top');
      styles = SmlStyleSheet.parse(xml);
      index = _derive(styles, index);
      expect(styles.cellXfsAlign.length, count);
    }
  });

  test('explicit wrap false overrides a wrapped native style', () {
    var styles = SmlStyleSheet.parse(_styles());
    var index = _derive(styles, 0, wrap: false);
    expect(index, isNot(0));
    final count = styles.cellXfsAlign.length;
    for (var cycle = 0; cycle < 3; cycle++) {
      final xml = styles.toXml();
      final alignment = _alignment(xml, index);
      expect(alignment.getAttribute('wrapText'), '0');
      expect(alignment.getAttribute('horizontal'), 'right');
      expect(alignment.getAttribute('vertical'), 'top');
      styles = SmlStyleSheet.parse(xml);
      expect(styles.wrapAt(index), isFalse);
      index = _derive(styles, index, wrap: false);
      expect(styles.cellXfsAlign.length, count);
    }
  });

  test('a wrap-only edit creates a style and survives XLSX roundtrip', () {
    var book = SmlWorkbook();
    book.firstSheet.cellA1('A1')
      ..value = 'Two\nlines'
      ..wrapText = true;
    for (var cycle = 0; cycle < 3; cycle++) {
      final package = SheetSerializer().write(book);
      expect(package.getPart('/xl/styles.xml'), isNotNull);
      book = SheetDeserializer().read(package);
      final cell = book.firstSheet.cellA1('A1');
      expect(cell.asString, 'Two\nlines');
      expect(book.styles!.wrapAt(cell.styleIndex), isTrue);
      expect(book.styles!.cellXfsAlign.length, 2);
    }
  });

  test('HTML table headers and cells retain wrap without growing styles', () {
    var book = LegacySheetReader.readBytes(
      Uint8List.fromList(
        utf8.encode(
          '<html><body><table><tr><th>Heading</th></tr>'
          '<tr><td>Body</td></tr></table></body></html>',
        ),
      ),
    );
    int? count;
    for (var cycle = 0; cycle < 3; cycle++) {
      book = SheetDeserializer().readBytes(SheetSerializer().writeBytes(book));
      final heading = book.firstSheet.cellA1('A1');
      final body = book.firstSheet.cellA1('A2');
      for (final cell in [heading, body]) {
        expect(book.styles!.wrapAt(cell.styleIndex), isTrue);
        expect(cell.fontSize, 10);
      }
      expect(heading.fontBold, isTrue);
      expect(heading.horizontalAlign, SmlHAlign.center);
      expect(body.fontBold, isFalse);
      count ??= book.styles!.cellXfsAlign.length;
      expect(book.styles!.cellXfsAlign.length, count);
    }
  });
}
