import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _w = OfficeNamespaces.w;
const _x = 'urn:table-margin-test-extension';

String _margins(String width, {String prefix = 'w'}) =>
    '<$prefix:tblCellMar>'
    '${[
      for (final edge in ['top', 'left', 'bottom', 'right']) '<$prefix:$edge $prefix:w="$width" $prefix:type="dxa"/>',
    ].join()}'
    '</$prefix:tblCellMar>';

String _style(
  String id, {
  String properties = '',
  String basedOn = '',
  String extra = '',
  bool isDefault = false,
}) =>
    '<w:style w:type="table" w:styleId="$id"'
    '${isDefault ? ' w:default="1"' : ''}>'
    '$basedOn<w:tblPr>$properties</w:tblPr>$extra</w:style>';

OpcPackage _package(String properties, {String styles = ''}) {
  final package = OpcPackage.create(OpcPackageKind.word);
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="$_w" xmlns:m="$_w" xmlns:x="$_x">'
        '<w:body><w:tbl><w:tblPr>$properties</w:tblPr>'
        '<w:tblGrid><w:gridCol w:w="2400"/></w:tblGrid>'
        '<w:tr><w:tc><w:p><w:r><w:t>Cell</w:t></w:r></w:p></w:tc></w:tr>'
        '</w:tbl></w:body></w:document>',
      );
  if (styles.isNotEmpty) {
    (package.getPart('/word/styles.xml') ??
            package.createPart(
              '/word/styles.xml',
              OfficeContentTypes.wordStyles,
            ))
        .writeText('<w:styles xmlns:w="$_w" xmlns:x="$_x">$styles</w:styles>');
    if (package
            .relationshipsFor('/word/document.xml')
            .firstByType(RelationshipTypes.styles) ==
        null) {
      package
          .relationshipsFor('/word/document.xml')
          .add(type: RelationshipTypes.styles, target: 'styles.xml');
    }
  }
  return package;
}

WmlDocument _import(String properties, {String styles = ''}) =>
    WordDeserializer().read(_package(properties, styles: styles));

WmlTable _table(WmlDocument document) =>
    document.sections.single.blocks.whereType<WmlTable>().single;

WmlDocument _authored(double margin, {String? styleId}) => WmlDocument(
  sections: [
    WmlSection(
      blocks: [
        WmlTable(
          grid: [120],
          properties: WmlTableProps(cellMargin: margin, styleId: styleId),
          rows: [
            WmlTableRow(
              cells: [
                WmlTableCell(
                  blocks: [
                    WmlParagraph(inlines: [WmlRun(text: 'Cell')]),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);

WmlDocument _reopen(WmlDocument document) =>
    WordDeserializer().readBytes(WordSerializer().writeBytes(document));

List<XmlElement> _directMargins(WmlDocument document) {
  final xml = _table(document).properties.sourcePropertiesXml!;
  return XmlDocument.parse(xml).root!.childElements
      .where(
        (element) =>
            element.namespaceUri == _w && element.localName == 'tblCellMar',
      )
      .toList();
}

List<String> _marginXml(WmlDocument document) => [
  for (final margin in _directMargins(document))
    XmlDocument(root: margin.copy()).toXmlString(declaration: false),
];

String _stylesXml(WmlDocument document) => XmlDocument.parse(
  document.package!.getPart('/word/styles.xml')!.readText(),
).toXmlString(declaration: false);

void main() {
  group('authored uniform DOCX table margins', () {
    for (final margin in [0.0, 1.25, 4.0, 7.2, 1638.35]) {
      test('$margin points is explicit and survives repeated saves', () {
        var document = _authored(margin);
        for (var cycle = 0; cycle < 3; cycle++) {
          document = _reopen(document);
          expect(_table(document).properties.cellMargin, margin);
          final edges = _directMargins(document).single.childElements.toList();
          expect(edges.map((edge) => edge.localName), [
            'top',
            'left',
            'bottom',
            'right',
          ]);
          for (final edge in edges) {
            expect(edge.namespaceUri, _w);
            expect(edge.getAttribute('type', namespaceUri: _w), 'dxa');
            expect(
              edge.getAttribute('w', namespaceUri: _w),
              '${(margin * 20).round()}',
            );
          }
        }
      });
    }

    for (final margin in [-0.1, double.nan, double.infinity, 1638.4]) {
      test('invalid new margin $margin does not generate invalid XML', () {
        expect(
          () => WordSerializer().writeBytes(_authored(margin)),
          throwsArgumentError,
        );
      });
    }

    test('a newly authored scalar overrides a named table style', () {
      final document = _authored(4, styleId: 'Styled');
      document.package = _package(
        '',
        styles: _style('Styled', properties: _margins('160')),
      );
      final reopened = _reopen(document);
      expect(_table(reopened).properties.cellMargin, 4);
      expect(_directMargins(reopened), hasLength(1));
    });
  });

  group('direct uniform source margins', () {
    for (final width in ['0', '120', '32767', ' +00120 ']) {
      test('native width $width is projected and source remains sparse', () {
        var document = _import('${_margins(width)}<x:opaque x:value="keep"/>');
        final original = _marginXml(document);
        for (var cycle = 0; cycle < 3; cycle++) {
          expect(
            _table(document).properties.cellMargin,
            int.parse(width.trim()) / 20,
          );
          expect(_marginXml(document), original);
          _table(document).properties.alignment = WmlJustification.center;
          document = _reopen(document);
          expect(
            _table(document).properties.sourcePropertiesXml,
            contains('<x:opaque x:value="keep"/>'),
          );
        }
      });
    }

    test('native namespace aliases retain their original source', () {
      final document = _import(_margins('25', prefix: 'm'));
      final original = _marginXml(document);
      expect(_table(document).properties.cellMargin, 1.25);
      expect(_marginXml(_reopen(document)), original);
    });

    test(
      'an intentional scalar edit replaces only its direct margin subtree',
      () {
        final document = _import(
          '${_margins('120')}<x:opaque x:value="keep"/>',
        );
        _table(document).properties.cellMargin = 0;
        final reopened = _reopen(document);
        expect(_table(reopened).properties.cellMargin, 0);
        expect(_directMargins(reopened), hasLength(1));
        expect(
          _table(reopened).properties.sourcePropertiesXml,
          contains('<x:opaque x:value="keep"/>'),
        );
      },
    );
  });

  group('direct physical margins in layout', () {
    for (final hasVerticalPadding in [false, true]) {
      test('preserves and lays out the authored edges, vertical padding '
          '$hasVerticalPadding', () {
        final properties =
            '<w:tblCellMar>'
            '${hasVerticalPadding ? '<w:top w:w="40" w:type="dxa"/>' : ''}'
            '<w:left w:w="70" w:type="dxa"/>'
            '${hasVerticalPadding ? '<w:bottom w:w="180" w:type="dxa"/>' : ''}'
            '<w:right w:w="120" w:type="dxa"/></w:tblCellMar>';
        final document = _import(properties);
        final original = _marginXml(document);
        final engine = WordLayoutEngine(font: null, measure: (_, _, _) => 5);
        for (final version in [document, _reopen(document)]) {
          expect(_marginXml(version), original);
          final page = engine.layout(version).pages.single;
          final cell = page.frames.single;
          final line = page.lines.single;
          expect(line.boxX, cell.x + 3.5);
          expect(line.boxWidth, cell.width - 9.5);
          expect(line.y, cell.y + (hasVerticalPadding ? 2 : 0));
          expect(
            cell.height,
            closeTo(line.height + (hasVerticalPadding ? 11 : 0), 0.001),
          );
        }

        _table(document).properties.cellMargin = 8;
        for (final version in [document, _reopen(document)]) {
          final page = engine.layout(version).pages.single;
          final cell = page.frames.single;
          final line = page.lines.single;
          expect(line.boxX, cell.x + 8);
          expect(line.boxWidth, cell.width - 16);
          expect(line.y, cell.y + 8);
        }
      });
    }
  });

  group('table style margin inheritance', () {
    final parent = _style('Parent', properties: _margins('120'));
    final child = _style('Child', basedOn: '<w:basedOn w:val="Parent"/>');

    test('named inheritance stays inherited through unrelated saves', () {
      var document = _import(
        '<w:tblStyle w:val="Child"/>',
        styles: '$parent$child',
      );
      for (var cycle = 0; cycle < 3; cycle++) {
        expect(_table(document).properties.cellMargin, 6);
        expect(_directMargins(document), isEmpty);
        _table(document).properties.alignment = WmlJustification.right;
        document = _reopen(document);
      }
      final styles = document.package!.getPart('/word/styles.xml')!;
      styles.writeText(styles.readText().replaceAll('w:w="120"', 'w:w="160"'));
      final changedStyle = WordDeserializer().read(document.package!);
      expect(_table(changedStyle).properties.cellMargin, 8);
      expect(_directMargins(changedStyle), isEmpty);
    });

    test('child and direct exact values each override their parent', () {
      final styles =
          '$parent${_style('Child', basedOn: '<w:basedOn w:val="Parent"/>', properties: _margins('0'))}';
      expect(
        _table(
          _import('<w:tblStyle w:val="Child"/>', styles: styles),
        ).properties.cellMargin,
        0,
      );
      final direct = _import(
        '<w:tblStyle w:val="Child"/>${_margins('40')}',
        styles: styles,
      );
      expect(_table(_reopen(direct)).properties.cellMargin, 2);
    });

    test('unsupported child margins block a guessed parent uniform value', () {
      final styles =
          '$parent${_style('Child', basedOn: '<w:basedOn w:val="Parent"/>', properties: '<w:tblCellMar><w:top w:w="0" w:type="dxa"/></w:tblCellMar>')}';
      final document = _import('<w:tblStyle w:val="Child"/>', styles: styles);
      final sourceStyles = _stylesXml(document);
      expect(_table(document).properties.cellMargin, 4);
      final reopened = _reopen(document);
      expect(_table(reopened).properties.cellMargin, 4);
      expect(_directMargins(reopened), isEmpty);
      expect(_stylesXml(reopened), sourceStyles);
    });

    test('a unique default table style supplies an inherited scalar', () {
      var document = _import(
        '',
        styles: _style('Default', properties: _margins('140'), isDefault: true),
      );
      for (var cycle = 0; cycle < 2; cycle++) {
        expect(_table(document).properties.cellMargin, 7);
        expect(_directMargins(document), isEmpty);
        document = _reopen(document);
      }
    });

    test('ambiguous default styles do not invent a scalar', () {
      final document = _import(
        '',
        styles:
            '${_style('One', properties: _margins('0'), isDefault: true)}'
            '${_style('Two', properties: _margins('120'), isDefault: true)}',
      );
      expect(_table(document).properties.cellMargin, 4);
      expect(_directMargins(_reopen(document)), isEmpty);
    });

    test(
      'reusing a reader does not carry direct-margin ownership across documents',
      () {
        final reader = WordDeserializer();
        expect(
          _table(reader.read(_package(_margins('0')))).properties.cellMargin,
          0,
        );
        final inherited = reader.read(
          _package('<w:tblStyle w:val="Child"/>', styles: '$parent$child'),
        );
        expect(_table(inherited).properties.cellMargin, 6);
      },
    );
  });

  group('opaque source margin containers', () {
    final uniform = _margins('120');
    final invalid = <String, String>{
      'asymmetric': uniform.replaceFirst('w:w="120"', 'w:w="0"'),
      'incomplete': uniform.replaceFirst(
        '<w:left w:w="120" w:type="dxa"/>',
        '',
      ),
      'duplicate edge': uniform.replaceFirst(
        '</w:tblCellMar>',
        '<w:left w:w="120" w:type="dxa"/></w:tblCellMar>',
      ),
      'logical edges': uniform
          .replaceAll('w:left', 'w:start')
          .replaceAll('w:right', 'w:end'),
      'negative': _margins('-1'),
      'noninteger': _margins('120.0'),
      'nonfinite': _margins('NaN'),
      'overflow': _margins('32768'),
      'nil': uniform.replaceAll('w:type="dxa"', 'w:type="nil"'),
      'missing type': uniform.replaceAll(' w:type="dxa"', ''),
      'foreign edge': uniform.replaceFirst('<w:left ', '<x:left '),
      'foreign attribute': uniform.replaceFirst('w:w="120"', 'x:w="120"'),
      'extension root attribute': uniform.replaceFirst(
        '<w:tblCellMar>',
        '<w:tblCellMar x:mode="keep">',
      ),
      'nested content': uniform.replaceFirst(
        '<w:top w:w="120" w:type="dxa"/>',
        '<w:top w:w="120" w:type="dxa"><x:keep/></w:top>',
      ),
      'nonwhitespace text': uniform.replaceFirst(
        '<w:tblCellMar>',
        '<w:tblCellMar>active',
      ),
      'duplicate containers': '$uniform$uniform',
    };
    for (final entry in invalid.entries) {
      test('${entry.key} remains opaque through unrelated edits', () {
        var document = _import(
          '<w:tblStyle w:val="Zero"/>${entry.value}',
          styles: _style('Zero', properties: _margins('0')),
        );
        final original = _marginXml(document);
        for (var cycle = 0; cycle < 3; cycle++) {
          expect(_table(document).properties.cellMargin, 4);
          expect(_marginXml(document), original);
          _table(document).properties.alignment = WmlJustification.center;
          document = _reopen(document);
        }
      });
    }
  });

  group('margin style lookup obeys native XML ownership', () {
    final zero = _style('Zero', properties: _margins('0'));
    final invalidChildren = <String, String>{
      'foreign basedOn': _style('Child', basedOn: '<x:basedOn w:val="Zero"/>'),
      'nested basedOn': _style(
        'Child',
        basedOn: '<x:extension><w:basedOn w:val="Zero"/></x:extension>',
      ),
      'duplicate basedOn': _style(
        'Child',
        basedOn: '<w:basedOn w:val="Zero"/><w:basedOn w:val="Zero"/>',
      ),
      'foreign style':
          '<x:style w:type="table" w:styleId="Child"><w:basedOn w:val="Zero"/></x:style>',
      'nested style':
          '<x:extension>${_style('Child', properties: _margins('0'))}</x:extension>',
      'historical properties': _style(
        'Child',
        properties:
            '<w:tblPrChange><w:tblPr>${_margins('0')}</w:tblPr></w:tblPrChange>',
      ),
      'conditional properties': _style(
        'Child',
        extra:
            '<w:tblStylePr w:type="firstRow"><w:tblPr>${_margins('0')}</w:tblPr></w:tblStylePr>',
      ),
      'foreign properties': _style(
        'Child',
        extra: '<x:tblPr>${_margins('0')}</x:tblPr>',
      ),
      'outside properties': _style(
        'Child',
        extra: '<x:extension>${_margins('0')}</x:extension>',
      ),
    };
    for (final entry in invalidChildren.entries) {
      test('${entry.key} does not supply an effective table margin', () {
        final document = _import(
          '<w:tblStyle w:val="Child"/>',
          styles: '$zero${entry.value}',
        );
        final sourceStyles = _stylesXml(document);
        expect(_table(document).properties.cellMargin, 4);
        final reopened = _reopen(document);
        expect(_table(reopened).properties.cellMargin, 4);
        expect(_directMargins(reopened), isEmpty);
        expect(_stylesXml(reopened), sourceStyles);
      });
    }

    test('historical direct properties do not replace current margins', () {
      final document = _import(
        '<w:tblStyle w:val="Zero"/><w:tblPrChange><w:tblPr>'
        '${_margins('120')}</w:tblPr></w:tblPrChange>',
        styles: zero,
      );
      expect(_table(document).properties.cellMargin, 0);
      expect(_directMargins(document), isEmpty);
      final reopened = _reopen(document);
      expect(_table(reopened).properties.cellMargin, 0);
      expect(
        _table(reopened).properties.sourcePropertiesXml,
        contains('w:w="120"'),
      );
    });
  });
}
