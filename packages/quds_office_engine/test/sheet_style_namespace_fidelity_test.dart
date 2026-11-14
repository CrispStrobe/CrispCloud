import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _x = OfficeNamespaces.x;
const _extension = 'urn:quds:test:style-extension';

String _nativeStyles({
  String prefix = '',
  bool foreignDefault = false,
  String alignment =
      '<Xalignment horizontal="right" vertical="bottom" wrapText="1" '
      'textRotation="15" indent="2" shrinkToFit="1" readingOrder="2"/>',
  bool rebindFontPrefix = false,
}) {
  final tag = prefix.isEmpty ? '' : '$prefix:';
  final fontPrefix = rebindFontPrefix ? 'f:' : tag;
  final fontBinding = rebindFontPrefix
      ? ' xmlns:f="$_x" xmlns:$prefix="$_extension"'
      : '';
  final rootBinding = prefix.isEmpty
      ? 'xmlns="$_x"'
      : 'xmlns:$prefix="$_x"${foreignDefault ? ' xmlns="$_extension"' : ''}';
  return '<${tag}styleSheet $rootBinding xmlns:e="$_extension" '
      'xmlns:mc="${OfficeNamespaces.mc}" mc:Ignorable="e">'
      '<e:fonts count="99"><e:font><e:sz val="99"/></e:font></e:fonts>'
      '<${tag}numFmts count="1">'
      '<${tag}numFmt numFmtId="164" formatCode="#,##0.0000"/>'
      '</${tag}numFmts>'
      '<${tag}fonts e:count="extension-count" count="1">'
      '<e:font><e:b/><e:sz val="99"/></e:font>'
      '<${fontPrefix}font$fontBinding>'
      '<${fontPrefix}b val="0"/>'
      '<${fontPrefix}i/><${fontPrefix}u val="double"/>'
      '<e:b val="extension-bold"/>'
      '<${fontPrefix}sz val="12" e:val="extension-size"/>'
      '<${fontPrefix}color theme="4" tint="0.25"/>'
      '<${fontPrefix}name val="Cambria"/>'
      '<${fontPrefix}family val="2"/>'
      '<${fontPrefix}charset val="1"/>'
      '<${fontPrefix}scheme val="minor"/>'
      '<e:sz val="extension-size"/>'
      '</${fontPrefix}font></${tag}fonts>'
      '<${tag}fills count="2">'
      '<e:fill><e:patternFill><e:fgColor rgb="FFFF0000"/>'
      '</e:patternFill></e:fill>'
      '<${tag}fill><${tag}patternFill patternType="none"/></${tag}fill>'
      '<${tag}fill><${tag}patternFill patternType="gray125"/></${tag}fill>'
      '</${tag}fills>'
      '<${tag}borders count="2"><${tag}border/>'
      '<${tag}border><${tag}bottom style="thin"/></${tag}border></${tag}borders>'
      '<${tag}cellStyleXfs count="1">'
      '<${tag}xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>'
      '</${tag}cellStyleXfs>'
      '<${tag}cellXfs count="1">'
      '<e:xf numFmtId="999" fontId="99"><e:alignment horizontal="left"/></e:xf>'
      '<${tag}xf e:fontId="extension-font" fontId="0" fillId="0" '
      'numFmtId="164" borderId="1" xfId="0" applyAlignment="0" '
      'e:applyAlignment="extension-alignment" quotePrefix="1">'
      '<e:alignment horizontal="extension-horizontal"/>'
      '${alignment.replaceAll('Xalignment', '${tag}alignment')}'
      '<${tag}protection locked="0" hidden="1"/>'
      '<${tag}extLst><${tag}ext uri="example"><e:xf fontId="88"/>'
      '</${tag}ext></${tag}extLst>'
      '</${tag}xf></${tag}cellXfs>'
      '</${tag}styleSheet>';
}

List<XmlElement> _entries(XmlElement root, String container, String entry) =>
    root
        .firstChild(container, namespaceUri: _x)!
        .childrenNamed(entry, namespaceUri: _x);

int _derive(
  SmlStyleSheet styles,
  int base, {
  SmlHAlign? align,
  String? fill,
  bool? bold,
  double? size,
}) => styles.xfFor(
  baseStyleIndex: base,
  align: align ?? styles.alignAt(base),
  fillRgb: fill ?? styles.fillAt(base),
  fontRgb: styles.fontAt(base),
  bold: bold ?? styles.boldAt(base),
  size: size ?? styles.sizeAt(base),
);

XmlElement _style(XmlElement root, int index) =>
    _entries(root, 'cellXfs', 'xf')[index];

XmlElement _font(XmlElement root, XmlElement style) => _entries(
  root,
  'fonts',
  'font',
)[int.parse(style.getAttribute('fontId', namespaceUri: '')!)];

void _assertNativeFont(XmlElement font, double size) {
  expect(font.namespaceUri, _x);
  expect(font.firstChild('b', namespaceUri: _x), isNotNull);
  expect(font.firstChild('i', namespaceUri: _x), isNotNull);
  expect(
    font
        .firstChild('u', namespaceUri: _x)!
        .getAttribute('val', namespaceUri: ''),
    'double',
  );
  expect(
    font
        .firstChild('sz', namespaceUri: _x)!
        .getAttribute('val', namespaceUri: ''),
    '$size',
  );
  expect(
    font
        .firstChild('sz', namespaceUri: _x)!
        .getAttribute('val', namespaceUri: _extension),
    'extension-size',
  );
  expect(
    font.firstChild('color', namespaceUri: _x)!.getAttribute('theme'),
    '4',
  );
  expect(
    font.firstChild('color', namespaceUri: _x)!.getAttribute('tint'),
    '0.25',
  );
  expect(
    font.firstChild('color', namespaceUri: _x)!.getAttribute('rgb'),
    isNull,
  );
  expect(
    font
        .firstChild('name', namespaceUri: _x)!
        .getAttribute('val', namespaceUri: ''),
    'Cambria',
  );
  expect(
    font
        .firstChild('family', namespaceUri: _x)!
        .getAttribute('val', namespaceUri: ''),
    '2',
  );
  expect(
    font
        .firstChild('charset', namespaceUri: _x)!
        .getAttribute('val', namespaceUri: ''),
    '1',
  );
  expect(
    font
        .firstChild('scheme', namespaceUri: _x)!
        .getAttribute('val', namespaceUri: ''),
    'minor',
  );
  expect(
    font
        .firstChild('b', namespaceUri: _extension)!
        .getAttribute('val', namespaceUri: ''),
    'extension-bold',
  );
  expect(
    font
        .firstChild('sz', namespaceUri: _extension)!
        .getAttribute('val', namespaceUri: ''),
    'extension-size',
  );
  expect(font.childElements.where((e) => e.namespaceUri.isEmpty), isEmpty);
}

void main() {
  for (final (label, prefix, foreignDefault, rebindFontPrefix) in [
    ('default namespace', '', false, false),
    ('prefixed namespace', 's', false, false),
    ('foreign default namespace', 's', true, false),
    ('rebound prefix in font', 's', true, true),
  ]) {
    test('edits retain native styles and extension nodes: $label', () {
      var styles = SmlStyleSheet.parse(
        _nativeStyles(
          prefix: prefix,
          foreignDefault: foreignDefault,
          rebindFontPrefix: rebindFontPrefix,
        ).replaceAll(RegExp(r'<(?:s:|f:)?b val="0"/>'), ''),
      );
      expect(styles.fontRgbs, hasLength(1));
      expect(styles.fillRgbs, ['', '']);
      expect(styles.cellXfsNumFmt, [164]);
      expect(styles.cellXfsAlign, [SmlHAlign.right]);
      expect(styles.fontBolds, [false]);
      expect(styles.fontSizes, [12]);
      var index = 0;
      for (var cycle = 0; cycle < 3; cycle++) {
        final size = 18.0 + cycle;
        index = _derive(
          styles,
          index,
          bold: true,
          size: size,
          align: SmlHAlign.center,
          fill: '112233',
        );
        final xml = styles.toXml();
        final root = XmlDocument.parse(xml).root!;
        expect(
          root
              .firstChild('fonts', namespaceUri: _extension)!
              .getAttribute('count'),
          '99',
        );
        final fonts = root.firstChild('fonts', namespaceUri: _x)!;
        expect(fonts.getAttribute('count', namespaceUri: ''), '${cycle + 2}');
        expect(
          fonts.getAttribute('count', namespaceUri: _extension),
          'extension-count',
        );
        expect(
          fonts.childrenNamed('font', namespaceUri: _extension),
          hasLength(1),
        );
        final style = _style(root, index);
        _assertNativeFont(_font(root, style), size);
        expect(style.getAttribute('numFmtId', namespaceUri: ''), '164');
        expect(style.getAttribute('borderId', namespaceUri: ''), '1');
        expect(style.getAttribute('quotePrefix', namespaceUri: ''), '1');
        expect(
          style.getAttribute('fontId', namespaceUri: _extension),
          'extension-font',
        );
        expect(
          style.getAttribute('applyAlignment', namespaceUri: _extension),
          'extension-alignment',
        );
        expect(
          style
              .firstChild('alignment', namespaceUri: _extension)!
              .getAttribute('horizontal'),
          'extension-horizontal',
        );
        final alignment = style.firstChild('alignment', namespaceUri: _x)!;
        expect(alignment.getAttribute('horizontal'), 'center');
        expect(alignment.getAttribute('vertical'), 'bottom');
        expect(alignment.getAttribute('wrapText'), '1');
        expect(alignment.getAttribute('textRotation'), '15');
        expect(alignment.getAttribute('indent'), '2');
        expect(alignment.getAttribute('shrinkToFit'), '1');
        expect(alignment.getAttribute('readingOrder'), '2');
        expect(
          style
              .firstChild('protection', namespaceUri: _x)!
              .getAttribute('hidden'),
          '1',
        );
        final fill = _entries(
          root,
          'fills',
          'fill',
        )[int.parse(style.getAttribute('fillId', namespaceUri: '')!)];
        expect(
          fill
              .firstChild('patternFill', namespaceUri: _x)!
              .firstChild('fgColor', namespaceUri: _x)!
              .getAttribute('rgb'),
          'FF112233',
        );
        styles = SmlStyleSheet.parse(xml);
        expect(styles.boldAt(index), isTrue);
        expect(styles.sizeAt(index), size);
        expect(styles.alignAt(index), SmlHAlign.center);
        expect(styles.fillAt(index), '112233');
      }
    });
  }

  test('horizontal alignment does not introduce vertical alignment', () {
    final styles = SmlStyleSheet.parse(_nativeStyles(alignment: ''));
    final index = _derive(styles, 0, align: SmlHAlign.center);
    final style = _style(XmlDocument.parse(styles.toXml()).root!, index);
    final alignment = style.firstChild('alignment', namespaceUri: _x)!;
    expect(alignment.getAttribute('horizontal'), 'center');
    expect(alignment.getAttribute('vertical'), isNull);
    expect(
      style.childElements
          .where((e) => e.namespaceUri == _x)
          .map((e) => e.localName),
      ['alignment', 'protection', 'extLst'],
    );
    expect(style.getAttribute('applyAlignment', namespaceUri: ''), '1');
  });

  test('new horizontal alignment retains the default vertical placement', () {
    final styles = SmlStyleSheet();
    final index = styles.xfFor(align: SmlHAlign.center);
    final alignment = _style(
      XmlDocument.parse(styles.toXml()).root!,
      index,
    ).firstChild('alignment', namespaceUri: _x)!;
    expect(alignment.getAttribute('horizontal'), 'center');
    expect(alignment.getAttribute('vertical'), isNull);
  });

  test('returning to general alignment keeps unrelated native properties', () {
    final styles = SmlStyleSheet.parse(_nativeStyles());
    final index = _derive(styles, 0, align: SmlHAlign.general);
    final style = _style(XmlDocument.parse(styles.toXml()).root!, index);
    final alignment = style.firstChild('alignment', namespaceUri: _x)!;
    expect(alignment.getAttribute('horizontal'), 'general');
    expect(alignment.getAttribute('vertical'), 'bottom');
    expect(alignment.getAttribute('wrapText'), '1');
    expect(style.getAttribute('applyAlignment', namespaceUri: ''), '1');
  });

  test(
    'font-only edits retain unmodeled horizontal alignment and size metadata',
    () {
      final styles = SmlStyleSheet.parse(
        _nativeStyles(
          alignment: '<Xalignment horizontal="distributed" vertical="top"/>',
        ),
      );
      final index = _derive(styles, 0, bold: true);
      final root = XmlDocument.parse(styles.toXml()).root!;
      final style = _style(root, index);
      final alignment = style.firstChild('alignment', namespaceUri: _x)!;
      expect(alignment.getAttribute('horizontal'), 'distributed');
      expect(alignment.getAttribute('vertical'), 'top');
      expect(style.getAttribute('applyAlignment', namespaceUri: ''), '0');
      expect(
        _font(root, style)
            .firstChild('sz', namespaceUri: _x)!
            .getAttribute('val', namespaceUri: _extension),
        'extension-size',
      );
    },
  );

  test(
    'missing style collections are inserted in schema order with bindings',
    () {
      final styles = SmlStyleSheet.parse(
        '<s:styleSheet xmlns:s="$_x" xmlns:e="$_extension">'
        '<e:fonts/><s:borders count="1"><s:border/></s:borders>'
        '<s:cellStyleXfs count="1"><s:xf/></s:cellStyleXfs>'
        '<s:extLst><s:ext uri="example"><e:fonts/></s:ext></s:extLst>'
        '</s:styleSheet>',
      );
      styles.xfFor(bold: true, fillRgb: '112233', align: SmlHAlign.center);
      final root = XmlDocument.parse(styles.toXml()).root!;
      expect(
        root.childElements
            .where((e) => e.namespaceUri == _x)
            .map((e) => e.localName),
        ['fonts', 'fills', 'borders', 'cellStyleXfs', 'cellXfs', 'extLst'],
      );
      expect(root.firstChild('fonts', namespaceUri: _extension), isNotNull);
      expect(SmlStyleSheet.parse(styles.toXml()).fontBolds, [false, true]);
    },
  );

  test('clearing the last direct style properties survives workbook saves', () {
    final workbook = SmlWorkbook();
    workbook.firstSheet.cellA1('A1')
      ..value = 'Clear the style'
      ..fontBold = true
      ..fontSize = 18
      ..fontRgb = '112233'
      ..fillRgb = '445566'
      ..horizontalAlign = SmlHAlign.center;
    var reopened = SheetDeserializer().readBytes(
      SheetSerializer().writeBytes(workbook),
    );
    reopened.firstSheet.cellA1('A1')
      ..fontBold = false
      ..fontSize = 11
      ..fontRgb = ''
      ..fillRgb = ''
      ..horizontalAlign = SmlHAlign.general;
    for (var cycle = 0; cycle < 3; cycle++) {
      reopened = SheetDeserializer().readBytes(
        SheetSerializer().writeBytes(reopened),
      );
      final cell = reopened.firstSheet.cellA1('A1');
      expect(cell.value, 'Clear the style');
      expect(cell.fontBold, isFalse);
      expect(cell.fontSize, 11);
      expect(cell.fontRgb, isEmpty);
      expect(cell.fillRgb, isEmpty);
      expect(cell.horizontalAlign, SmlHAlign.general);
    }
  });

  test(
    'prefixed imported styles keep cell formatting through workbook saves',
    () {
      final workbook = SmlWorkbook();
      workbook.firstSheet.cellA1('A1').value = 'Preserve formatting';
      final package = SheetSerializer().write(workbook);
      package
          .createPart('/xl/styles.xml', OfficeContentTypes.sheetStyles)
          .writeText(_nativeStyles(prefix: 's', foreignDefault: true));
      package
          .relationshipsFor('/xl/workbook.xml')
          .add(type: RelationshipTypes.styles, target: 'styles.xml');
      var reopened = SheetDeserializer().read(package);
      reopened.firstSheet.cellA1('A1')
        ..fontBold = true
        ..fontSize = 18
        ..horizontalAlign = SmlHAlign.center;
      for (var cycle = 0; cycle < 3; cycle++) {
        final saved = SheetSerializer().writeBytes(reopened);
        final root = XmlDocument.parse(
          OpcPackage.openBytes(saved).getPart('/xl/styles.xml')!.readText(),
        ).root!;
        reopened = SheetDeserializer().readBytes(saved);
        final cell = reopened.firstSheet.cellA1('A1');
        expect(cell.fontBold, isTrue);
        expect(cell.fontSize, 18);
        expect(cell.horizontalAlign, SmlHAlign.center);
        final style = _style(root, cell.styleIndex);
        _assertNativeFont(_font(root, style), 18);
        expect(
          style
              .firstChild('alignment', namespaceUri: _x)!
              .getAttribute('vertical'),
          'bottom',
        );
      }
    },
  );
}
