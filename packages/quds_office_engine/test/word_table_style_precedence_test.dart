import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _w = OfficeNamespaces.w;

OpcPackage _package(String table, String styles) {
  final package = OpcPackage.create(OpcPackageKind.word);
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="$_w"><w:body>$table</w:body></w:document>',
      );
  package
      .createPart('/word/styles.xml', OfficeContentTypes.wordStyles)
      .writeText('<w:styles xmlns:w="$_w">$styles</w:styles>');
  package
      .relationshipsFor('/word/document.xml')
      .add(type: RelationshipTypes.styles, target: 'styles.xml');
  return package;
}

String _table({
  String style = 'Colored',
  String look = '<w:tblLook w:firstRow="1" w:noHBand="1"/>',
  String properties = '',
  String firstCell = '<w:p><w:r><w:t>Header</w:t></w:r></w:p>',
}) =>
    '<w:tbl><w:tblPr><w:tblStyle w:val="$style"/>'
    '$look$properties</w:tblPr>'
    '<w:tblGrid><w:gridCol w:w="2400"/></w:tblGrid>'
    '<w:tr><w:tc>$firstCell</w:tc></w:tr>'
    '<w:tr><w:tc><w:p><w:r><w:t>Body</w:t></w:r></w:p></w:tc></w:tr>'
    '</w:tbl>';

String _style({
  String id = 'Colored',
  String basedOn = '',
  String properties = '',
  String header = '<w:rPr><w:b/><w:color w:val="FFFFFF"/></w:rPr>',
  bool shaded = true,
}) =>
    '<w:style w:type="table" w:styleId="$id">$basedOn$properties'
    '<w:tblStylePr w:type="firstRow">$header'
    '${shaded ? '<w:tcPr><w:shd w:fill="336699"/></w:tcPr>' : ''}'
    '</w:tblStylePr></w:style>';

WmlTable _onlyTable(WmlDocument document) =>
    document.sections.single.blocks.whereType<WmlTable>().single;

WmlParagraph _header(WmlDocument document) => _onlyTable(
  document,
).rows.first.cells.single.blocks.whereType<WmlParagraph>().first;

WmlRun _headerRun(WmlDocument document) =>
    _header(document).inlines.whereType<WmlRun>().single;

void main() {
  group('conditional table run formatting', () {
    for (final shaded in [true, false]) {
      test('first-row color and bold apply with shading $shaded', () {
        final document = WordDeserializer().read(
          _package(_table(), _style(shaded: shaded)),
        );
        final table = _onlyTable(document);
        expect(_headerRun(document).properties.color, 'FFFFFF');
        expect(_headerRun(document).properties.bold, isTrue);
        expect(
          table.rows.first.cells.single.fillColor,
          shaded ? '336699' : null,
        );
        final body = table.rows.last.cells.single.blocks.single as WmlParagraph;
        expect(
          body.inlines.whereType<WmlRun>().single.properties.bold,
          isFalse,
        );
        expect(
          body.inlines.whereType<WmlRun>().single.properties.color,
          '000000',
        );
      });
    }

    for (final disabled in ['0', 'false', 'off']) {
      test('direct color and bold=$disabled survive import and export', () {
        var document = WordDeserializer().read(
          _package(
            _table(
              firstCell:
                  '<w:p><w:r><w:rPr><w:b w:val="$disabled"/>'
                  '<w:color w:val="CC0000"/></w:rPr>'
                  '<w:t>Direct</w:t></w:r></w:p>',
            ),
            _style(),
          ),
        );
        for (var cycle = 0; cycle < 3; cycle++) {
          final run = _headerRun(document);
          expect(run.properties.color, 'CC0000', reason: 'cycle $cycle');
          expect(run.properties.bold, isFalse, reason: 'cycle $cycle');
          document = WordDeserializer().readBytes(
            WordSerializer().writeBytes(document),
          );
        }
      });
    }

    test('child first-row false and color override the parent', () {
      final document = WordDeserializer().read(
        _package(
          _table(style: 'Child'),
          _style() +
              _style(
                id: 'Child',
                basedOn: '<w:basedOn w:val="Colored"/>',
                header:
                    '<w:rPr><w:b w:val="0"/>'
                    '<w:color w:val="222222"/></w:rPr>',
                shaded: false,
              ),
        ),
      );
      expect(_headerRun(document).properties.bold, isFalse);
      expect(_headerRun(document).properties.color, '222222');
      expect(_onlyTable(document).rows.first.cells.single.fillColor, '336699');
    });

    test('an omitted child bold declaration preserves the parent', () {
      final document = WordDeserializer().read(
        _package(
          _table(style: 'Child'),
          _style() +
              _style(
                id: 'Child',
                basedOn: '<w:basedOn w:val="Colored"/>',
                header: '<w:rPr><w:color w:val="222222"/></w:rPr>',
                shaded: false,
              ),
        ),
      );
      expect(_headerRun(document).properties.bold, isTrue);
      expect(_headerRun(document).properties.color, '222222');
    });

    test('firstRow disabled leaves header text and fill unchanged', () {
      final document = WordDeserializer().read(
        _package(
          _table(look: '<w:tblLook w:firstRow="0" w:noHBand="1"/>'),
          _style(),
        ),
      );
      expect(_headerRun(document).properties.bold, isFalse);
      expect(_headerRun(document).properties.color, '000000');
      expect(_onlyTable(document).rows.first.cells.single.fillColor, isNull);
    });

    test('an outer first-row style does not repaint a nested table', () {
      final nested = _table(
        style: 'Nested',
        look: '<w:tblLook w:firstRow="0" w:noHBand="1"/>',
      );
      final document = WordDeserializer().read(
        _package(
          _table(firstCell: '<w:p><w:r><w:t>Outer</w:t></w:r></w:p>$nested'),
          '${_style()}<w:style w:type="table" w:styleId="Nested"/>',
        ),
      );
      expect(_headerRun(document).properties.color, 'FFFFFF');
      final nestedTable = _onlyTable(
        document,
      ).rows.first.cells.single.blocks.whereType<WmlTable>().single;
      final paragraph =
          nestedTable.rows.first.cells.single.blocks.single as WmlParagraph;
      final run = paragraph.inlines.whereType<WmlRun>().single;
      expect(run.properties.color, '000000');
      expect(run.properties.bold, isFalse);
    });
  });

  group('direct table border width', () {
    final styles = _style(
      properties:
          '<w:tblPr><w:tblBorders><w:top w:val="single" '
          'w:sz="8" w:color="FFFFFF"/></w:tblBorders></w:tblPr>',
    );

    for (final color in ['', ' w:color="auto"']) {
      for (final size in [4, 16]) {
        test('direct size $size survives style color fallback $color', () {
          var document = WordDeserializer().read(
            _package(
              _table(
                properties:
                    '<w:tblBorders><w:top w:val="single" '
                    'w:sz="$size"$color/></w:tblBorders>',
              ),
              styles,
            ),
          );
          for (var cycle = 0; cycle < 3; cycle++) {
            final properties = _onlyTable(document).properties;
            expect(properties.borderColor, 'FFFFFF', reason: 'cycle $cycle');
            expect(properties.borderWidth, size / 8, reason: 'cycle $cycle');
            expect(properties.borders, isTrue);
            document = WordDeserializer().readBytes(
              WordSerializer().writeBytes(document),
            );
          }
        });
      }
    }

    test('an omitted direct size inherits the style size', () {
      final document = WordDeserializer().read(
        _package(
          _table(
            properties:
                '<w:tblBorders><w:top w:val="single" '
                'w:color="auto"/></w:tblBorders>',
          ),
          styles,
        ),
      );
      expect(_onlyTable(document).properties.borderColor, 'FFFFFF');
      expect(_onlyTable(document).properties.borderWidth, 1);
    });

    test('a direct border color and size both win over the style', () {
      final document = WordDeserializer().read(
        _package(
          _table(
            properties:
                '<w:tblBorders><w:top w:val="single" '
                'w:sz="16" w:color="CC0000"/></w:tblBorders>',
          ),
          styles,
        ),
      );
      expect(_onlyTable(document).properties.borderColor, 'CC0000');
      expect(_onlyTable(document).properties.borderWidth, 2);
    });

    test('explicit nil borders stay disabled', () {
      final document = WordDeserializer().read(
        _package(
          _table(
            properties: '<w:tblBorders><w:top w:val="nil"/></w:tblBorders>',
          ),
          styles,
        ),
      );
      expect(_onlyTable(document).properties.borders, isFalse);
    });
  });

  group('table paragraph spacing precedence', () {
    const defaults =
        '<w:docDefaults><w:pPrDefault><w:pPr>'
        '<w:spacing w:after="160" w:line="276" w:lineRule="auto"/>'
        '</w:pPr></w:pPrDefault></w:docDefaults>';

    for (final scenario in [
      (
        name: 'document defaults',
        table: '',
        paragraph: '',
        direct: '',
        after: 8.0,
        line: 1.15,
      ),
      (
        name: 'table style',
        table: '<w:pPr><w:spacing w:after="240" w:line="360"/></w:pPr>',
        paragraph: '',
        direct: '',
        after: 12.0,
        line: 1.5,
      ),
      (
        name: 'paragraph style',
        table: '<w:pPr><w:spacing w:after="240" w:line="360"/></w:pPr>',
        paragraph:
            '<w:style w:type="paragraph" w:styleId="Cell"><w:pPr><w:spacing w:after="400" w:line="480"/></w:pPr></w:style>',
        direct: '<w:pStyle w:val="Cell"/>',
        after: 20.0,
        line: 2.0,
      ),
      (
        name: 'direct zero and single',
        table: '<w:pPr><w:spacing w:after="240" w:line="360"/></w:pPr>',
        paragraph: '',
        direct: '<w:spacing w:after="0" w:line="240"/>',
        after: 0.0,
        line: 1.0,
      ),
    ]) {
      test('${scenario.name} retain their declared spacing', () {
        final document = WordDeserializer().read(
          _package(
            _table(
              firstCell:
                  '<w:p><w:pPr>${scenario.direct}</w:pPr>'
                  '<w:r><w:t>Cell</w:t></w:r></w:p>',
            ),
            '$defaults${_style(properties: scenario.table)}${scenario.paragraph}',
          ),
        );
        expect(_header(document).properties.spacingAfter, scenario.after);
        expect(_header(document).properties.lineSpacing, scenario.line);
      });
    }

    test('an otherwise unformatted styled cell keeps the compact fallback', () {
      final document = WordDeserializer().read(_package(_table(), _style()));
      expect(_header(document).properties.spacingAfter, 0);
      expect(_header(document).properties.lineSpacing, 1);
    });

    test('the compact fallback stays inherited after an untouched export', () {
      final document = WordDeserializer().read(_package(_table(), _style()));
      final saved = OpcPackage.openBytes(WordSerializer().writeBytes(document));
      final body = XmlDocument.parse(
        saved.getPart('/word/document.xml')!.readText(),
      ).root!.firstChild('body')!;
      final paragraph = body
          .firstChild('tbl')!
          .firstChild('tr')!
          .firstChild('tc')!
          .firstChild('p')!;
      expect(paragraph.firstChild('pPr')?.firstChild('spacing'), isNull);
      saved
          .getPart('/word/styles.xml')!
          .writeText(
            '<w:styles xmlns:w="$_w">'
            '${_style(properties: '<w:pPr><w:spacing w:after="240" w:line="360"/></w:pPr>')}'
            '</w:styles>',
          );
      final updated = WordDeserializer().read(saved);
      expect(_header(updated).properties.spacingAfter, 12);
      expect(_header(updated).properties.lineSpacing, 1.5);
    });
  });
}
