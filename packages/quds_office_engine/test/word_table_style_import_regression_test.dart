import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _w = OfficeNamespaces.w;
const _header =
    '<w:tblStylePr w:type="firstRow">'
    '<w:rPr><w:b/><w:color w:val="FFFFFF"/></w:rPr>'
    '<w:tcPr><w:shd w:fill="445566"/></w:tcPr></w:tblStylePr>';

WmlDocument _open(String body, String styles) {
  final package = OpcPackage.create(OpcPackageKind.word);
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="$_w"><w:body>$body<w:sectPr/></w:body></w:document>',
      );
  package.createPart(
    '/word/styles.xml',
    OfficeContentTypes.wordStyles,
    utf8.encode('<w:styles xmlns:w="$_w">$styles</w:styles>'),
  );
  return WordDeserializer().read(package);
}

String _table(String cells, {String style = 'Brand', String extra = ''}) =>
    '<w:tbl><w:tblPr><w:tblStyle w:val="$style"/>'
    '<w:tblLook w:firstRow="1" w:noHBand="1"/>$extra</w:tblPr>'
    '<w:tblGrid><w:gridCol w:w="4000"/></w:tblGrid>'
    '<w:tr><w:tc>$cells</w:tc></w:tr></w:tbl>';

Iterable<WmlParagraph> _paragraphs(Iterable<WmlBlock> blocks) sync* {
  for (final block in blocks) {
    if (block is WmlParagraph) {
      yield block;
    } else if (block is WmlTable) {
      for (final row in block.rows) {
        for (final cell in row.cells) {
          yield* _paragraphs(cell.blocks);
        }
      }
    }
  }
}

WmlRun _run(WmlDocument document, String text) =>
    _paragraphs(document.sections.first.blocks)
        .expand((p) => p.inlines.whereType<WmlRun>())
        .singleWhere((r) => r.text == text);

Iterable<XmlElement> _elements(XmlElement root, String name) sync* {
  if (root.localName == name && root.namespaceUri == _w) yield root;
  for (final child in root.childElements) {
    yield* _elements(child, name);
  }
}

void main() {
  test('header style preserves direct run color and explicit bold off', () {
    var document = _open(
      _table(
        '<w:p><w:r><w:rPr><w:b w:val="0"/>'
        '<w:color w:val="008844"/></w:rPr><w:t>Direct</w:t></w:r>'
        '<w:r><w:t>Inherited</w:t></w:r></w:p>',
      ),
      '<w:style w:type="table" w:styleId="Brand">$_header</w:style>',
    );
    for (var cycle = 0; cycle < 3; cycle++) {
      expect(_run(document, 'Direct').properties.color, '008844');
      expect(_run(document, 'Direct').properties.bold, isFalse);
      expect(_run(document, 'Inherited').properties.color, 'FFFFFF');
      expect(_run(document, 'Inherited').properties.bold, isTrue);
      document = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
    }
  });

  test('character style remains above conditional table run formatting', () {
    final document = _open(
      _table(
        '<w:p><w:r><w:rPr><w:rStyle w:val="Accent"/></w:rPr>'
        '<w:t>Character</w:t></w:r></w:p>',
      ),
      '<w:style w:type="table" w:styleId="Brand">$_header</w:style>'
      '<w:style w:type="character" w:styleId="Accent">'
      '<w:rPr><w:b/><w:color w:val="AA3300"/></w:rPr></w:style>',
    );
    expect(_run(document, 'Character').properties.color, 'AA3300');
    expect(_run(document, 'Character').properties.bold, isFalse);
  });

  test('child table region can turn inherited bold off', () {
    final document = _open(
      _table('<w:p><w:r><w:t>Child</w:t></w:r></w:p>', style: 'Child'),
      '<w:style w:type="table" w:styleId="Brand">$_header</w:style>'
      '<w:style w:type="table" w:styleId="Child"><w:basedOn w:val="Brand"/>'
      '<w:tblStylePr w:type="firstRow"><w:rPr><w:b w:val="0"/></w:rPr>'
      '</w:tblStylePr></w:style>',
    );
    expect(_run(document, 'Child').properties.bold, isFalse);
    expect(_run(document, 'Child').properties.color, 'FFFFFF');
  });

  test('automatic child region color overrides inherited explicit color', () {
    final document = _open(
      _table('<w:p><w:r><w:t>Automatic</w:t></w:r></w:p>', style: 'Child'),
      '<w:style w:type="table" w:styleId="Brand">$_header</w:style>'
      '<w:style w:type="table" w:styleId="Child"><w:basedOn w:val="Brand"/>'
      '<w:tblStylePr w:type="firstRow"><w:rPr><w:color w:val="auto"/></w:rPr>'
      '</w:tblStylePr></w:style>',
    );
    expect(_run(document, 'Automatic').properties.color, 'auto');
  });

  test('conditional run formatting does not require cell shading', () {
    final document = _open(
      _table('<w:p><w:r><w:t>Unshaded</w:t></w:r></w:p>'),
      '<w:style w:type="table" w:styleId="Brand">'
      '<w:tblStylePr w:type="firstRow"><w:rPr><w:b/>'
      '<w:color w:val="225588"/></w:rPr></w:tblStylePr></w:style>',
    );
    expect(_run(document, 'Unshaded').properties.bold, isTrue);
    expect(_run(document, 'Unshaded').properties.color, '225588');
  });

  test(
    'outer header formatting does not enter a separately styled nested table',
    () {
      final document = _open(
        _table(
          '<w:p><w:r><w:t>Outer</w:t></w:r></w:p>'
          '${_table('<w:p><w:r><w:t>Inner</w:t></w:r></w:p>', style: 'Inner')}',
        ),
        '<w:style w:type="table" w:styleId="Brand">$_header</w:style>'
        '<w:style w:type="table" w:styleId="Inner">'
        '<w:rPr><w:b w:val="0"/><w:color w:val="112233"/></w:rPr></w:style>',
      );
      expect(_run(document, 'Outer').properties.color, 'FFFFFF');
      expect(_run(document, 'Outer').properties.bold, isTrue);
      expect(_run(document, 'Inner').properties.color, '112233');
      expect(_run(document, 'Inner').properties.bold, isFalse);
    },
  );

  test(
    'table default spacing stays inherited when saved and style changes',
    () {
      final document = _open(
        _table('<w:p><w:r><w:t>Defaults</w:t></w:r></w:p>'),
        '<w:style w:type="table" w:styleId="Brand"/>',
      );
      final paragraph = _paragraphs(document.sections.first.blocks).single;
      expect(paragraph.properties.spacingAfter, 0);
      expect(paragraph.properties.lineSpacing, 1);
      final saved = WordSerializer().write(document);
      final xml = XmlDocument.parse(
        saved.getPart('/word/document.xml')!.readText(),
      ).root!;
      expect(
        _elements(xml, 'spacing'),
        isEmpty,
        reason: 'Import fallbacks must not become new direct formatting.',
      );
      saved
          .getPart('/word/styles.xml')!
          .writeText(
            '<w:styles xmlns:w="$_w"><w:style w:type="table" w:styleId="Brand">'
            '<w:pPr><w:spacing w:after="200" w:line="360"/></w:pPr>'
            '</w:style></w:styles>',
          );
      final reopened = WordDeserializer().read(saved);
      final changed = _paragraphs(reopened.sections.first.blocks).single;
      expect(changed.properties.spacingAfter, 10);
      expect(changed.properties.lineSpacing, 1.5);
    },
  );

  for (final (name, paragraphProperties, after, line)
      in <(String, String, double, double)>[
        ('table style', '', 8, 1.5),
        ('paragraph style', '<w:pStyle w:val="Body"/>', 2, 2),
        (
          'direct paragraph',
          '<w:pStyle w:val="Body"/><w:spacing w:after="60" w:line="300"/>',
          3,
          1.25,
        ),
      ]) {
    test('$name spacing remains above native table defaults', () {
      final document = _open(
        _table(
          '<w:p><w:pPr>$paragraphProperties</w:pPr><w:r><w:t>Spacing</w:t></w:r></w:p>',
        ),
        '<w:style w:type="table" w:styleId="Brand">'
        '<w:pPr><w:spacing w:after="160" w:line="360"/></w:pPr></w:style>'
        '<w:style w:type="paragraph" w:styleId="Body">'
        '<w:pPr><w:spacing w:after="40" w:line="480"/></w:pPr></w:style>',
      );
      final paragraph = _paragraphs(document.sections.first.blocks).single;
      expect(paragraph.properties.spacingAfter, after);
      expect(paragraph.properties.lineSpacing, line);
    });
  }

  test(
    'automatic direct border takes style color without replacing its width',
    () {
      final document = _open(
        _table(
          '<w:p><w:r><w:t>Border</w:t></w:r></w:p>',
          extra:
              '<w:tblBorders><w:top w:val="single" w:sz="16" w:color="auto"/></w:tblBorders>',
        ),
        '<w:style w:type="table" w:styleId="Brand"><w:tblPr><w:tblBorders>'
        '<w:top w:val="single" w:sz="8" w:color="FFFFFF"/>'
        '</w:tblBorders></w:tblPr></w:style>',
      );
      final table = document.sections.first.blocks.whereType<WmlTable>().single;
      expect(table.properties.borderColor, 'FFFFFF');
      expect(table.properties.borderWidth, 2);
    },
  );

  for (final value in ['none', 'nil']) {
    test('paragraph border $value does not acquire a visible color', () {
      final document = _open(
        '<w:p><w:pPr><w:pBdr><w:bottom w:val="$value" w:color="FF0000"/>'
            '</w:pBdr></w:pPr><w:r><w:t>Borderless</w:t></w:r></w:p>',
        '',
      );
      expect(document.paragraphs.single.properties.borderColor, isNull);
    });
  }

  test('visible automatic paragraph border retains the black fallback', () {
    final document = _open(
      '<w:p><w:pPr><w:pBdr><w:bottom w:val="single" w:color="auto"/>'
          '</w:pBdr></w:pPr><w:r><w:t>Bordered</w:t></w:r></w:p>',
      '',
    );
    expect(document.paragraphs.single.properties.borderColor, '000000');
  });
}
