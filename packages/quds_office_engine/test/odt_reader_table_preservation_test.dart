import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _ns =
    'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
    'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" '
    'xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" '
    'xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0" '
    'xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" '
    'xmlns:xlink="http://www.w3.org/1999/xlink" '
    'xmlns:foreign="urn:foreign"';

Uint8List _package(
  String styles, {
  String tableStyle = '',
  String rowStyle = '',
  String cellStyle = '',
  String columns = '',
}) {
  final zip = ZipWriter();
  zip.addFile(
    'mimetype',
    utf8.encode('application/vnd.oasis.opendocument.text'),
    store: true,
  );
  zip.addFile(
    'content.xml',
    utf8.encode(
      '<office:document-content $_ns>'
      '<office:automatic-styles>$styles</office:automatic-styles>'
      '<office:body><office:text><table:table $tableStyle>$columns'
      '<table:table-row $rowStyle><table:table-cell $cellStyle>'
      '<text:p>Value</text:p></table:table-cell></table:table-row>'
      '</table:table></office:text></office:body></office:document-content>',
    ),
  );
  return zip.close();
}

String _style(
  String name,
  String family,
  String properties, {
  String parent = '',
  String extra = '',
}) =>
    '<style:style style:name="$name" style:family="$family" '
    '${parent.isEmpty ? '' : 'style:parent-style-name="$parent"'} $extra>'
    '$properties</style:style>';

WmlTable _table(WmlDocument document) =>
    document.sections.single.blocks.whereType<WmlTable>().single;

WmlDocument _reopen(WmlDocument document) =>
    WordDeserializer().readBytes(WordSerializer().writeBytes(document));

Matcher get _refused =>
    throwsA(anyOf(isA<FormatException>(), isA<UnsupportedError>()));

void main() {
  test(
    'unused opaque structural styles do not reject supported tables',
    () async {
      final document = await OdtDocumentReader.readBytes(
        _package(
          _style(
            'Unused',
            'table',
            '<style:table-properties style:width="not-a-length">'
                '<style:background-image xlink:href="Pictures/background.png"/>'
                '</style:table-properties>',
            extra: 'foreign:behavior="unsupported"',
          ),
        ),
      );
      for (final current in [document, _reopen(document)]) {
        expect(_table(current).grid, [120]);
        expect(
          (_table(current).rows.single.cells.single.blocks.single
                  as WmlParagraph)
              .text,
          'Value',
        );
      }
    },
  );

  test(
    'matching explicit width and fixed columns survive DOCX reopening',
    () async {
      final document = await OdtDocumentReader.readBytes(
        _package(
          '${_style('T', 'table', '<style:table-properties style:width="144pt"/>')}'
          '${_style('C', 'table-column', '<style:table-column-properties style:column-width="2in"/>')}',
          tableStyle: 'table:style-name="T"',
          columns: '<table:table-column table:style-name="C"/>',
        ),
      );
      for (final current in [document, _reopen(document)]) {
        expect(_table(current).grid, [144]);
        expect(_table(current).rows.single.cells.single.width, 144);
      }
    },
  );

  test(
    'declared table width fills an unspecified column without loss',
    () async {
      final document = await OdtDocumentReader.readBytes(
        _package(
          _style('T', 'table', '<style:table-properties style:width="144pt"/>'),
          tableStyle: 'table:style-name="T"',
        ),
      );
      for (final current in [document, _reopen(document)]) {
        expect(_table(current).grid, [144]);
        expect(_table(current).rows.single.cells.single.width, 144);
      }
    },
  );

  test('conflicting explicitly fixed table and column widths refuse', () async {
    await expectLater(
      OdtDocumentReader.readBytes(
        _package(
          '${_style('T', 'table', '<style:table-properties style:width="144pt"/>')}'
          '${_style('C', 'table-column', '<style:table-column-properties style:column-width="120pt"/>')}',
          tableStyle: 'table:style-name="T"',
          columns: '<table:table-column table:style-name="C"/>',
        ),
      ),
      _refused,
    );
  });

  test('used structural styles retain supported inert metadata', () async {
    final document = await OdtDocumentReader.readBytes(
      _package(
        _style(
          'T',
          'table',
          '<style:table-properties table:align="center"/>',
          extra: 'style:class="extra" style:auto-update="false"',
        ),
        tableStyle: 'table:style-name="T"',
      ),
    );
    for (final current in [document, _reopen(document)]) {
      expect(_table(current).properties.alignment, WmlJustification.center);
    }
  });

  for (final width in ['not-a-length', '0pt']) {
    test('refuses invalid table width $width', () async {
      await expectLater(
        OdtDocumentReader.readBytes(
          _package(
            _style(
              'T',
              'table',
              '<style:table-properties style:width="$width"/>',
            ),
            tableStyle: 'table:style-name="T"',
          ),
        ),
        _refused,
      );
    });
  }

  test('sparse table and row descendants retain inherited controls', () async {
    final document = await OdtDocumentReader.readBytes(
      _package(
        '${_style('TB', 'table', '<style:table-properties table:align="center"/>')}'
        '${_style('T', 'table', '<style:table-properties style:width="120pt"/>', parent: 'TB')}'
        '${_style('RB', 'table-row', '<style:table-row-properties fo:keep-together="always"/>')}'
        '${_style('R', 'table-row', '<style:table-row-properties style:min-row-height="18pt"/>', parent: 'RB')}',
        tableStyle: 'table:style-name="T"',
        rowStyle: 'table:style-name="R"',
      ),
    );
    for (final current in [document, _reopen(document)]) {
      final table = _table(current);
      expect(table.properties.alignment, WmlJustification.center);
      expect(table.rows.single.cantSplit, isTrue);
      expect(table.rows.single.height, 18);
    }
  });

  test('explicit row auto clears inherited keep-together', () async {
    final document = await OdtDocumentReader.readBytes(
      _package(
        '${_style('RB', 'table-row', '<style:table-row-properties fo:keep-together="always"/>')}'
        '${_style('R', 'table-row', '<style:table-row-properties fo:keep-together="auto"/>', parent: 'RB')}',
        rowStyle: 'table:style-name="R"',
      ),
    );
    for (final current in [document, _reopen(document)]) {
      expect(_table(current).rows.single.cantSplit, isFalse);
    }
  });

  for (final override in ['', ' fo:background-color="transparent"']) {
    test(
      'cell fill distinguishes inherited and explicit transparent $override',
      () async {
        final document = await OdtDocumentReader.readBytes(
          _package(
            '${_style('CB', 'table-cell', '<style:table-cell-properties fo:background-color="#FF0000"/>')}'
            '${_style('C', 'table-cell', '<style:table-cell-properties$override/>', parent: 'CB')}',
            cellStyle: 'table:style-name="C"',
          ),
        );
        for (final current in [document, _reopen(document)]) {
          expect(
            _table(current).rows.single.cells.single.fillColor,
            override.isEmpty ? 'FF0000' : null,
          );
        }
      },
    );
  }

  for (final family in ['table', 'table-column', 'table-row', 'table-cell']) {
    Uint8List packageWithProperties(String properties, {String extra = ''}) =>
        _package(
          _style('Used', family, properties, extra: extra),
          tableStyle: family == 'table' ? 'table:style-name="Used"' : '',
          rowStyle: family == 'table-row' ? 'table:style-name="Used"' : '',
          cellStyle: family == 'table-cell' ? 'table:style-name="Used"' : '',
          columns: family == 'table-column'
              ? '<table:table-column table:style-name="Used"/>'
              : '',
        );

    test('refuses unsupported nested used $family properties', () async {
      await expectLater(
        OdtDocumentReader.readBytes(
          packageWithProperties(
            '<style:$family-properties><style:background-image '
            'xlink:href="Pictures/background.png"/></style:$family-properties>',
          ),
        ),
        _refused,
      );
    });

    test('refuses ambiguous duplicate used $family properties', () async {
      await expectLater(
        OdtDocumentReader.readBytes(
          packageWithProperties(
            '<style:$family-properties/><style:$family-properties/>',
          ),
        ),
        _refused,
      );
    });

    test('refuses unmodeled attributes on used $family definitions', () async {
      await expectLater(
        OdtDocumentReader.readBytes(
          packageWithProperties(
            '<style:$family-properties/>',
            extra: 'foreign:behavior="unsupported"',
          ),
        ),
        _refused,
      );
    });
  }
}
