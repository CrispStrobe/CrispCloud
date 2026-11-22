import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/automation/operations/word_steps.dart'
    as native;
import 'package:test/test.dart';

const _w = OfficeNamespaces.w;
const _x = 'urn:cell-paragraph-formatting';
const _styles = '''
<w:style w:styleId="Normal" w:type="paragraph" w:default="1"><w:name w:val="Normal"/></w:style>
<w:style w:styleId="ReportHeading" w:type="paragraph"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:before="240"/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:color w:val="456789"/></w:rPr></w:style>
<w:style w:styleId="ReportBody" w:type="paragraph" w:customStyle="1"><w:name w:val="Report Body"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:after="180"/><w:shd w:val="clear" w:fill="336699"/></w:pPr></w:style>
<w:style w:styleId="CharacterOnly" w:type="character"><w:name w:val="Character only"/><w:rPr><w:b/></w:rPr></w:style>
''';

Uint8List _fixture({
  String properties = '',
  String styles = _styles,
  String? selected,
  String cellProperties = '<w:shd w:val="clear" w:fill="EEF1F4"/>',
  String rowProperties = '',
  bool secondTable = false,
}) {
  final package = OpcPackage.openBytes(
    (DocxDocumentBuilder()..paragraph('Template')).build(),
  );
  String cell(String paragraph, {String properties = ''}) =>
      '<w:tc><w:tcPr><w:tcW w:w="2400" w:type="dxa"/>$properties</w:tcPr>'
      '$paragraph</w:tc>';
  String table(String target) =>
      '<w:tbl><w:tblPr/><w:tblGrid><w:gridCol w:w="2400"/>'
      '<w:gridCol w:w="2400"/></w:tblGrid><w:tr>$rowProperties'
      '${cell(target, properties: cellProperties)}'
      '${cell('<w:p><w:r><w:t>Other cell</w:t></w:r></w:p>')}'
      '</w:tr></w:tbl>';
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="$_w" xmlns:x="$_x"><w:body>'
        '<w:p><w:r><w:t>Body before table</w:t></w:r></w:p>'
        '${table(selected ?? '<w:p><w:pPr>$properties</w:pPr><w:r>'
                '<w:rPr><w:i/></w:rPr><w:t>Selected cell</w:t></w:r></w:p>')}'
        '${secondTable ? table('<w:p><w:r><w:t>Second table</w:t></w:r></w:p>') : ''}'
        '<w:sectPr/></w:body></w:document>',
      );
  package
      .getPart('/word/styles.xml')!
      .writeText('<w:styles xmlns:w="$_w" xmlns:x="$_x">$styles</w:styles>');
  return package.save();
}

WmlDocument _read(Uint8List bytes) => WordDeserializer().readBytes(bytes);
WmlTable _table(WmlDocument doc, [int index = 0]) =>
    doc.sections.first.blocks.whereType<WmlTable>().elementAt(index);
WmlParagraph _target(WmlDocument doc, {int table = 0, int column = 0}) =>
    _table(doc, table).rows.first.cells[column].blocks.first as WmlParagraph;

Map<String, Object?> _selector([Map<String, Object?> extra = const {}]) => {
  'story': 'tableCell',
  'table': 0,
  'row': 0,
  'column': 0,
  'paragraph': 0,
  ...extra,
};

void _apply(WmlDocument doc, String op, Map<String, Object?> values) =>
    OfficeOperationCatalog.apply(doc, 'docx.$op', _selector(values));

XmlElement _nativeCell(Uint8List bytes, {int table = 0, int column = 0}) =>
    XmlDocument.parse(
          OpcPackage.openBytes(bytes).getPart('/word/document.xml')!.readText(),
        ).root!
        .firstChild('body', namespaceUri: _w)!
        .childrenNamed('tbl', namespaceUri: _w)
        .elementAt(table)
        .childrenNamed('tr', namespaceUri: _w)
        .first
        .childrenNamed('tc', namespaceUri: _w)
        .elementAt(column);

XmlElement _pPr(Uint8List bytes, {int table = 0, int column = 0}) =>
    _nativeCell(
      bytes,
      table: table,
      column: column,
    ).firstChild('p', namespaceUri: _w)!.firstChild('pPr', namespaceUri: _w)!;

Map<String, Uint8List> _parts(WmlDocument doc) => {
  for (final part in doc.package!.parts)
    part.uri: doc.package!.getPart(part.uri)!.readBytes(),
};

void _refuses(
  WmlDocument doc,
  String op,
  Map<String, Object?> arguments, {
  Matcher matcher = throwsUnsupportedError,
  bool lowLevel = false,
}) {
  final selected = _target(doc);
  final other = _target(doc, column: 1);
  final body = doc.sections.first.blocks.first as WmlParagraph;
  final paragraphs = [selected, other, body];
  final properties = [for (final p in paragraphs) p.properties];
  final inlines = [for (final p in paragraphs) p.inlines];
  final runProperties = [
    for (final p in paragraphs)
      for (final r in p.inlines.whereType<WmlRun>()) r.properties,
  ];
  final values = [
    for (final p in paragraphs)
      <Object?>[
        p.text,
        p.properties.styleId,
        p.properties.shadingFill,
        p.properties.sourcePropertiesXml,
        Map<String, String>.of(p.properties.importedValues ?? {}),
      ],
  ];
  final source = _parts(doc);
  expect(() {
    if (lowLevel) {
      native.applyStep(doc, {'op': op, ...arguments});
    } else {
      OfficeOperationCatalog.apply(doc, 'docx.$op', arguments);
    }
  }, matcher);
  for (var i = 0; i < paragraphs.length; i++) {
    final p = paragraphs[i];
    expect(p.properties, same(properties[i]));
    expect(p.inlines, same(inlines[i]));
    expect(<Object?>[
      p.text,
      p.properties.styleId,
      p.properties.shadingFill,
      p.properties.sourcePropertiesXml,
      Map<String, String>.of(p.properties.importedValues ?? {}),
    ], values[i]);
  }
  final runs = [
    for (final p in paragraphs)
      for (final r in p.inlines.whereType<WmlRun>()) r.properties,
  ];
  for (var i = 0; i < runs.length; i++) {
    expect(runs[i], same(runProperties[i]));
  }
  expect(_parts(doc), source);
}

void main() {
  for (final (request, id) in <(Map<String, Object?>, String)>[
    ({'builtin': -2}, 'ReportHeading'),
    ({'name': 'Report Body'}, 'ReportBody'),
    ({'name': 'report body'}, 'ReportBody'),
  ]) {
    test('cell paragraph style $request preserves target ownership', () {
      var doc = _read(_fixture());
      final paragraph = _target(doc);
      final cell = _table(doc).rows.first.cells.first;
      final originalProps = paragraph.properties;
      final inlines = paragraph.inlines;
      final run = inlines.single as WmlRun;
      final originalRunProps = run.properties;
      final otherProps = _target(doc, column: 1).properties;
      final otherRunProps =
          (_target(doc, column: 1).inlines.single as WmlRun).properties;
      final originalParts = _parts(doc);
      final originalStyles = XmlDocument.parse(
        doc.package!.getPart('/word/styles.xml')!.readText(),
      ).toXmlString(declaration: false);
      _apply(doc, 'paragraphStyle', request);
      expect(cell.blocks.single, same(paragraph));
      expect(paragraph.inlines, same(inlines));
      expect(paragraph.inlines.single, same(run));
      expect(paragraph.properties, isNot(same(originalProps)));
      expect(run.properties, isNot(same(originalRunProps)));
      expect(_target(doc, column: 1).properties, same(otherProps));
      expect(
        (_target(doc, column: 1).inlines.single as WmlRun).properties,
        same(otherRunProps),
      );
      expect(_parts(doc), originalParts);
      for (var cycle = 0; cycle < 3; cycle++) {
        final current = _target(doc);
        expect(current.properties.styleId, id);
        expect(current.text, 'Selected cell');
        expect((current.inlines.single as WmlRun).properties.italic, isTrue);
        if (id == 'ReportHeading') {
          expect((current.inlines.single as WmlRun).properties.bold, isTrue);
          expect(current.properties.spacingBefore, 12);
        } else {
          expect(current.properties.spacingAfter, 9);
          expect(current.properties.shadingFill, '336699');
        }
        expect(_target(doc, column: 1).text, 'Other cell');
        expect(_target(doc, column: 1).properties.styleId, isNull);
        final bytes = WordSerializer().writeBytes(doc);
        final direct = _pPr(bytes);
        expect(
          direct
              .firstChild('pStyle', namespaceUri: _w)!
              .getAttribute('val', namespaceUri: _w),
          id,
        );
        expect(direct.firstChild('spacing', namespaceUri: _w), isNull);
        expect(direct.firstChild('shd', namespaceUri: _w), isNull);
        expect(
          _nativeCell(bytes)
              .firstChild('tcPr', namespaceUri: _w)!
              .firstChild('shd', namespaceUri: _w)!
              .getAttribute('fill', namespaceUri: _w),
          'EEF1F4',
        );
        expect(
          XmlDocument.parse(
            OpcPackage.openBytes(bytes).getPart('/word/styles.xml')!.readText(),
          ).toXmlString(declaration: false),
          originalStyles,
        );
        doc = _read(bytes);
      }
    });
  }

  test(
    'second direct table is selected without touching earlier paragraphs',
    () {
      final doc = _read(_fixture(secondTable: true));
      _apply(doc, 'paragraphStyle', {'table': 1, 'builtin': -2});
      _apply(doc, 'paragraphShading', {'table': 1, 'color': 'ABCDEF'});
      expect(_target(doc, table: 1).properties.styleId, 'ReportHeading');
      expect(_target(doc, table: 1).properties.shadingFill, 'ABCDEF');
      expect(_target(doc).properties.styleId, isNull);
      expect(_target(doc).properties.shadingFill, isNull);
      expect(
        (doc.sections.first.blocks.first as WmlParagraph).text,
        'Body before table',
      );
    },
  );

  test(
    'native empty cell paragraph accepts style and shading without text',
    () {
      var doc = _read(_fixture(selected: '<w:p/>'));
      _apply(doc, 'paragraphStyle', {'name': 'Report Body'});
      _apply(doc, 'paragraphShading', {'color': 'auto'});
      for (var cycle = 0; cycle < 3; cycle++) {
        final target = _target(doc);
        expect(target.inlines, isEmpty);
        expect(target.text, isEmpty);
        expect(target.properties.styleId, 'ReportBody');
        expect(target.properties.spacingAfter, 9);
        expect(target.properties.shadingFill, isNull);
        final bytes = WordSerializer().writeBytes(doc);
        expect(
          _pPr(bytes)
              .firstChild('shd', namespaceUri: _w)!
              .getAttribute('fill', namespaceUri: _w),
          'auto',
        );
        doc = _read(bytes);
      }
    },
  );

  for (final color in ['336699', 'auto']) {
    test(
      'cell paragraph $color overrides style shading without pinning spacing',
      () {
        final doc = _read(
          _fixture(properties: '<w:pStyle w:val="ReportBody"/>'),
        );
        expect(_target(doc).properties.shadingFill, '336699');
        _apply(doc, 'paragraphShading', {'color': color});
        final bytes = WordSerializer().writeBytes(doc);
        expect(_pPr(bytes).firstChild('spacing', namespaceUri: _w), isNull);
        expect(
          _pPr(bytes)
              .firstChild('shd', namespaceUri: _w)!
              .getAttribute('fill', namespaceUri: _w),
          color,
        );
        final package = OpcPackage.openBytes(bytes);
        final styles = package.getPart('/word/styles.xml')!;
        styles.writeText(
          styles
              .readText()
              .replaceAll('336699', 'AA5500')
              .replaceAll('180', '600'),
        );
        var reopened = WordDeserializer().read(package);
        for (var cycle = 0; cycle < 2; cycle++) {
          expect(_target(reopened).properties.spacingAfter, 30);
          expect(
            _target(reopened).properties.shadingFill,
            color == 'auto' ? isNull : color,
          );
          expect(_target(reopened, column: 1).properties.shadingFill, isNull);
          reopened = _read(WordSerializer().writeBytes(reopened));
        }
      },
    );
  }

  test('same-value style assignment preserves sparse native marker metadata', () {
    final doc = _read(
      _fixture(
        properties:
            '<w:pStyle w:val="ReportBody" x:val="foreign" x:token="style">'
            '<x:metadata x:keep="yes"/></w:pStyle><w:keepNext x:token="keep"/>',
      ),
    );
    _apply(doc, 'paragraphStyle', {'name': 'Report Body'});
    final direct = _pPr(WordSerializer().writeBytes(doc));
    final marker = direct.firstChild('pStyle', namespaceUri: _w)!;
    expect(marker.getAttribute('val', namespaceUri: _w), 'ReportBody');
    expect(marker.getAttribute('val', namespaceUri: _x), 'foreign');
    expect(marker.getAttribute('token', namespaceUri: _x), 'style');
    expect(marker.firstChild('metadata', namespaceUri: _x), isNotNull);
    expect(
      direct
          .firstChild('keepNext', namespaceUri: _w)!
          .getAttribute('token', namespaceUri: _x),
      'keep',
    );
    expect(direct.firstChild('spacing', namespaceUri: _w), isNull);
    expect(direct.firstChild('shd', namespaceUri: _w), isNull);
  });

  test(
    'paragraph shading retains native aliases and opaque property metadata',
    () {
      var doc = _read(
        _fixture(
          properties:
              '<n:shd xmlns:n="$_w" xmlns:w="$_x" n:val="clear" n:fill="AABBCC" '
              'n:color="auto" x:fill="foreign" x:token="shading">'
              '<w:metadata w:keep="yes"><n:shd n:val="pct25" n:fill="445566"/></w:metadata>'
              '</n:shd><x:shd x:fill="opaque"/>',
        ),
      );
      _apply(doc, 'paragraphShading', {'color': '010203'});
      for (var cycle = 0; cycle < 3; cycle++) {
        final bytes = WordSerializer().writeBytes(doc);
        final direct = _pPr(bytes);
        final shading = direct.firstChild('shd', namespaceUri: _w)!;
        expect(shading.getAttribute('fill', namespaceUri: _w), '010203');
        expect(shading.getAttribute('fill', namespaceUri: _x), 'foreign');
        expect(shading.getAttribute('token', namespaceUri: _x), 'shading');
        expect(shading.getAttribute('color', namespaceUri: _w), 'auto');
        expect(
          shading
              .firstChild('metadata', namespaceUri: _x)!
              .firstChild('shd', namespaceUri: _w)!
              .getAttribute('fill', namespaceUri: _w),
          '445566',
        );
        expect(direct.firstChild('shd', namespaceUri: _x), isNotNull);
        expect(_target(doc).properties.shadingFill, '010203');
        doc = _read(bytes);
      }
    },
  );

  test(
    'pending text, run, style and paragraph writes survive both new operations',
    () {
      final doc = _read(_fixture());
      OfficeOperationCatalog.apply(doc, 'docx.tableCellRangeText', {
        'table': 0,
        'row': 0,
        'column': 0,
        'text': 'Updated report',
      });
      _apply(doc, 'runFormat', {'bold': true, 'color': '010203'});
      _apply(doc, 'paragraphFormat', {'before': 18, 'rtl': true});
      _apply(doc, 'paragraphStyle', {'name': 'Report Body'});
      _apply(doc, 'paragraphShading', {'color': 'auto'});
      _apply(doc, 'paragraphStyle', {'builtin': -2});
      final bytes = WordSerializer().writeBytes(doc);
      final target = _target(_read(bytes));
      expect(target.text, 'Updated report');
      expect(target.properties.styleId, 'ReportHeading');
      expect(target.properties.spacingBefore, 18);
      expect(target.properties.rightToLeft, isTrue);
      expect(target.properties.shadingFill, isNull);
      final run = target.inlines.single as WmlRun;
      expect(run.properties.bold, isTrue);
      expect(run.properties.italic, isTrue);
      expect(run.properties.color, '010203');
      expect(
        _pPr(bytes)
            .firstChild('shd', namespaceUri: _w)!
            .getAttribute('fill', namespaceUri: _w),
        'auto',
      );
    },
  );

  for (final op in ['paragraphStyle', 'paragraphShading']) {
    final values = <String, Object?>{
      if (op == 'paragraphStyle') 'builtin': -2 else 'color': 'ABCDEF',
    };
    test('$op detaches shared paragraph and run property objects', () {
      final doc = _read(_fixture());
      final target = _target(doc);
      final other = _target(doc, column: 1);
      final shared = target.properties;
      final sharedRun = (target.inlines.single as WmlRun).properties;
      other.properties = shared;
      (other.inlines.single as WmlRun).properties = sharedRun;
      final original = Map<String, String>.of(shared.importedValues ?? {});
      _apply(doc, op, values);
      expect(target.properties, isNot(same(shared)));
      expect(other.properties, same(shared));
      expect(shared.styleId, isNull);
      expect(shared.shadingFill, isNull);
      expect(shared.importedValues, original);
      expect((other.inlines.single as WmlRun).properties, same(sharedRun));
      expect(sharedRun.bold, isFalse);
      expect(sharedRun.italic, isTrue);
    });

    for (final missing in ['story', 'table', 'row', 'column', 'paragraph']) {
      test('$op requires explicit $missing without falling back', () {
        _refuses(
          _read(_fixture()),
          op,
          _selector(values)..remove(missing),
          matcher: throwsArgumentError,
        );
      });
    }
    for (final (label, invalid) in <(String, Map<String, Object?>)>[
      ('body coordinates', {'story': 'body'}),
      ('mixed header section', {'section': 0}),
      ('mixed note', {'note': 0}),
      ('mixed comment', {'comment': 0}),
      ('paragraph offset', {'paragraph': 1}),
      ('text offset', {'start': 0}),
      ('missing table', {'table': 1}),
      ('missing row', {'row': 1}),
      ('missing column', {'column': 2}),
      ('fractional column', {'column': 0.5}),
    ]) {
      test('$op refuses $label atomically', () {
        _refuses(
          _read(_fixture()),
          op,
          _selector({...values, ...invalid}),
          matcher: throwsArgumentError,
        );
      });
    }
    test('$op has the same explicit selector contract at native dispatch', () {
      _refuses(
        _read(_fixture()),
        op,
        _selector({...values, 'story': 'body'}),
        matcher: throwsArgumentError,
        lowLevel: true,
      );
    });
    for (final restriction in ['editing', 'formatting', 'tracking']) {
      test('$op refuses $restriction protection before native changes', () {
        final doc = _read(_fixture());
        if (restriction == 'editing') doc.restrictEditing = true;
        if (restriction == 'formatting') {
          doc.protectionFormattingRestricted = true;
        }
        if (restriction == 'tracking') doc.trackRevisions = true;
        _refuses(doc, op, _selector(values), lowLevel: true);
      });
    }
    test('$op refuses multi-paragraph cells instead of selecting a prefix', () {
      final doc = _read(_fixture());
      _table(doc).rows.first.cells.first.blocks.add(WmlParagraph());
      _refuses(doc, op, _selector(values));
    });
    test('$op refuses merged cell geometry', () {
      final doc = _read(_fixture());
      _table(doc).rows.first.cells.first.gridSpan = 2;
      _refuses(doc, op, _selector(values));
    });
    test('$op refuses shared paragraph ownership', () {
      final doc = _read(_fixture());
      _table(doc).rows.first.cells[1].blocks = [_target(doc)];
      _refuses(doc, op, _selector(values));
    });
    test('$op refuses cyclic table graphs before catalog traversal', () {
      final doc = _read(_fixture());
      _table(doc).rows.first.cells[1].blocks.add(_table(doc));
      _refuses(doc, op, _selector(values));
    });
    test('$op refuses opaque cell content', () {
      final doc = _read(
        _fixture(
          selected:
              '<w:p><w:hyperlink w:anchor="destination"><w:r><w:t>Linked</w:t></w:r></w:hyperlink></w:p>',
        ),
      );
      _refuses(doc, op, _selector(values));
    });
    test('$op refuses unpreserved native row metadata', () {
      final doc = _read(
        _fixture(rowProperties: '<w:trPr><w:tblHeader/></w:trPr>'),
      );
      _refuses(doc, op, _selector(values));
    });
  }

  for (final request in <Map<String, Object?>>[
    {'name': 'Missing'},
    {'name': 'Character only'},
    {'builtin': -99},
    {'builtin': -2, 'name': 'Report Body'},
    {},
  ]) {
    test(
      'invalid cell paragraph style $request leaves native/model state intact',
      () {
        _refuses(
          _read(_fixture()),
          'paragraphStyle',
          _selector(request),
          matcher: throwsArgumentError,
        );
      },
    );
  }
  for (final property in [
    '<w:shd w:val="pct25" w:fill="123456"/>',
    '<w:shd w:val="clear" w:fill="123456" w:themeFill="accent1"/>',
    '<w:shd w:val="clear" w:fill="123456"/><w:shd w:val="clear" w:fill="654321"/>',
  ]) {
    test('unsupported native shading $property fails before publication', () {
      _refuses(
        _read(_fixture(properties: property)),
        'paragraphShading',
        _selector({'color': 'ABCDEF'}),
      );
    });
  }
  for (final color in <Object?>[null, true, 0, 'ffffff', '#FFFFFF', 'AUTO']) {
    test('invalid paragraph color $color is atomic', () {
      _refuses(
        _read(_fixture()),
        'paragraphShading',
        _selector({'color': color}),
        matcher: throwsArgumentError,
      );
    });
  }
}
