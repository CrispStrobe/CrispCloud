import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _w = OfficeNamespaces.w;
const _x = 'urn:tab-test';

Uint8List _fixture(String properties, {String styles = '', String? body}) {
  final package = OpcPackage.openBytes(
    (DocxDocumentBuilder()..paragraph('Template')).build(),
  );
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="$_w" xmlns:x="$_x" '
        'xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006">'
        '<w:body>${body ?? '<w:p><w:pPr>$properties</w:pPr>'
                '<w:r><w:t>Original</w:t></w:r></w:p>'}'
        '<w:sectPr/></w:body></w:document>',
      );
  if (styles.isNotEmpty) {
    package
        .getPart('/word/styles.xml')!
        .writeText('<w:styles xmlns:w="$_w" xmlns:x="$_x">$styles</w:styles>');
  }
  package
      .getPart('/word/settings.xml')!
      .writeText(
        '<w:settings xmlns:w="$_w" xmlns:x="$_x">'
        '<w:defaultTabStop w:val="960"/><x:keep x:value="settings"/>'
        '</w:settings>',
      );
  return package.save();
}

const _styles =
    '<w:docDefaults><w:pPrDefault><w:pPr><w:tabs>'
    '<w:tab w:pos="360" w:val="left"/>'
    '</w:tabs></w:pPr></w:pPrDefault></w:docDefaults>'
    '<w:style w:type="paragraph" w:styleId="Base"><w:pPr><w:tabs>'
    '<w:tab w:pos="720" w:val="right" w:leader="dot"/>'
    '<w:tab w:pos="1080" w:val="bar"/>'
    '<w:tab w:pos="1440" w:val="center"/>'
    '</w:tabs></w:pPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="Derived">'
    '<w:basedOn w:val="Base"/><w:pPr><w:tabs>'
    '<w:tab w:pos="360" w:val="clear"/>'
    '<w:tab w:pos="720" w:val="decimal" w:leader="hyphen"/>'
    '<w:tab w:pos="1800" w:val="left"/>'
    '</w:tabs></w:pPr></w:style>';
const _direct =
    '<w:pStyle w:val="Derived"/><w:keepNext x:value="keep"/>'
    '<w:tabs x:value="container"><w:tab w:pos="1440" w:val="clear" '
    'x:value="cleared"/><w:tab w:pos="2160" w:val="left" '
    'x:value="direct"/></w:tabs>';

WmlDocument _read(Uint8List bytes) => WordDeserializer().readBytes(bytes);
List<(double, String, String)> _tabs(WmlParagraph paragraph) => [
  for (final tab in paragraph.properties.tabs)
    (tab.position, tab.alignment.name, tab.leader.name),
];
XmlElement _properties(Uint8List bytes) =>
    XmlDocument.parse(
          OpcPackage.openBytes(bytes).getPart('/word/document.xml')!.readText(),
        ).root!
        .firstChild('body', namespaceUri: _w)!
        .firstChild('p', namespaceUri: _w)!
        .firstChild('pPr', namespaceUri: _w)!;
XmlElement _nativeTabs(Uint8List bytes) =>
    _properties(bytes).firstChild('tabs', namespaceUri: _w)!;
List<XmlElement> _stops(Uint8List bytes) =>
    _nativeTabs(bytes).childrenNamed('tab', namespaceUri: _w);
String? _attr(XmlElement node, String name) =>
    node.getAttribute(name, namespaceUri: _w);
OfficeMacro _plan(List<OfficeMacroStep> steps) => OfficeMacro(
  name: 'Native tab operations',
  format: OfficeMacroFormat.docx,
  steps: steps,
);
OfficeMacroStep _add(
  num position, {
  String alignment = 'left',
  String leader = 'none',
}) => OfficeMacroStep(
  tool: 'docx.tabStop',
  arguments: {
    'paragraph': 0,
    'position': position,
    'alignment': alignment,
    'leader': leader,
  },
);
OfficeMacroStep _clear() =>
    OfficeMacroStep(tool: 'docx.clearTabStops', arguments: {'paragraph': 0});

void main() {
  test('tab cascade is additive by position and preserves native source', () {
    var bytes = _fixture(_direct, styles: _styles);
    for (var cycle = 0; cycle < 3; cycle++) {
      final document = _read(bytes);
      expect(_tabs(document.paragraphs.single), [
        (36.0, 'decimal', 'hyphen'),
        (90.0, 'left', 'none'),
        (108.0, 'left', 'none'),
      ]);
      bytes = WordSerializer().writeBytes(document);
      expect(_stops(bytes).map((s) => _attr(s, 'pos')), ['1440', '2160']);
      expect(_attr(_stops(bytes).first, 'val'), 'clear');
      expect(
        OpcPackage.openBytes(bytes).getPart('/word/styles.xml')!.readText(),
        contains('<w:tab w:pos="1080" w:val="bar"/>'),
      );
    }
  });

  test(
    'upsert owns one position, retains inherited stops and same-stop metadata',
    () async {
      final session = OfficeMacroSession(
        _fixture(
          '<w:pStyle w:val="Derived"/><w:keepNext x:value="keep"/>'
          '<w:tabs x:value="container">'
          '<w:tab w:pos="720" w:val="left" w:leader="dot" '
          'x:val="foreign" x:value="existing"><x:child/></w:tab>'
          '<x:tab w:pos="1260" w:val="bar" x:value="foreign-tab"/>'
          '<w:tab w:pos="2160" w:val="right"/></w:tabs>',
          styles: _styles,
        ),
        format: OfficeMacroFormat.docx,
      );
      await session.run(
        _plan([
          _add(63, alignment: 'right', leader: 'underscore'),
          _add(36, alignment: 'center'),
          _add(63, alignment: 'decimal', leader: 'hyphen'),
        ]),
      );
      var bytes = session.bytes;
      for (var cycle = 0; cycle < 3; cycle++) {
        final document = _read(bytes);
        expect(_tabs(document.paragraphs.single), [
          (36.0, 'center', 'none'),
          (63.0, 'decimal', 'hyphen'),
          (72.0, 'center', 'none'),
          (90.0, 'left', 'none'),
          (108.0, 'right', 'none'),
        ]);
        final stops = _stops(bytes);
        expect(stops.map((s) => _attr(s, 'pos')).toSet(), {
          '720',
          '1260',
          '2160',
        });
        final changed = stops.singleWhere((s) => _attr(s, 'pos') == '720');
        expect(changed.getAttribute('val', namespaceUri: _x), 'foreign');
        expect(changed.getAttribute('value', namespaceUri: _x), 'existing');
        expect(changed.firstChild('child', namespaceUri: _x), isNotNull);
        expect(_attr(changed, 'leader'), 'none');
        expect(
          _nativeTabs(bytes).firstChild('tab', namespaceUri: _x),
          isNotNull,
        );
        expect(
          _properties(bytes).firstChild('keepNext', namespaceUri: _w),
          isNotNull,
        );
        bytes = WordSerializer().writeBytes(document);
      }
    },
  );

  test(
    'clear all suppresses inherited bar and custom tabs, retaining defaults',
    () async {
      final input = _fixture(_direct, styles: _styles);
      final original = OpcPackage.openBytes(input);
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      await session.run(_plan([_clear()]));
      var bytes = session.bytes;
      for (var cycle = 0; cycle < 3; cycle++) {
        final document = _read(bytes);
        expect(document.paragraphs.single.properties.tabs, isEmpty);
        final stops = _stops(bytes);
        expect(stops.map((s) => _attr(s, 'pos')).toSet(), {
          '720',
          '1080',
          '1440',
          '1800',
          '2160',
        });
        expect(stops.map((s) => _attr(s, 'val')), everyElement('clear'));
        expect(stops.map((s) => _attr(s, 'leader')), everyElement(isNull));
        final direct = stops.singleWhere((s) => _attr(s, 'pos') == '2160');
        expect(direct.getAttribute('value', namespaceUri: _x), 'direct');
        final package = OpcPackage.openBytes(bytes);
        expect(
          package.getPart('/word/settings.xml')!.readText(),
          original.getPart('/word/settings.xml')!.readText(),
        );
        expect(
          XmlDocument.parse(
            package.getPart('/word/styles.xml')!.readText(),
          ).toXmlString(declaration: false),
          XmlDocument.parse(
            original.getPart('/word/styles.xml')!.readText(),
          ).toXmlString(declaration: false),
        );
        bytes = WordSerializer().writeBytes(document);
      }
      await session.run(_plan([_clear(), _add(36, leader: 'dot')]));
      expect(_tabs(_read(session.bytes).paragraphs.single), [
        (36.0, 'left', 'dot'),
      ]);
    },
  );

  test('same-value upsert is direct and style changes remain live elsewhere', () {
    final document = _read(
      _fixture('<w:pStyle w:val="Derived"/>', styles: _styles),
    );
    OfficeOperationCatalog.apply(document, 'docx.tabStop', {
      'paragraph': 0,
      'position': 36,
      'alignment': 'decimal',
      'leader': 'hyphen',
    });
    var bytes = WordSerializer().writeBytes(document);
    expect(_stops(bytes).map((s) => _attr(s, 'pos')), ['720']);
    final package = OpcPackage.openBytes(bytes);
    package
        .getPart('/word/styles.xml')!
        .writeText(
          '<w:styles xmlns:w="$_w">${_styles.replaceAll('w:pos="720" w:val="decimal" w:leader="hyphen"', 'w:pos="720" w:val="center" w:leader="underscore"').replaceAll('w:pos="1800" w:val="left"', 'w:pos="1800" w:val="right"')}</w:styles>',
        );
    bytes = package.save();
    final updated = _read(bytes);
    expect(_tabs(updated.paragraphs.single), [
      (36.0, 'decimal', 'hyphen'),
      (72.0, 'center', 'none'),
      (90.0, 'right', 'none'),
    ]);
  });

  test(
    'new style positions after ClearAll remain live; old positions stay cleared',
    () {
      final document = _read(
        _fixture('<w:pStyle w:val="Derived"/>', styles: _styles),
      );
      OfficeOperationCatalog.apply(document, 'docx.clearTabStops', {
        'paragraph': 0,
      });
      final part = document.package!.getPart('/word/styles.xml')!;
      part.writeText(
        part.readText().replaceFirst(
          '<w:tab w:pos="1800" w:val="left"/>',
          '<w:tab w:pos="1800" w:val="right"/><w:tab w:pos="2520" w:val="center"/>',
        ),
      );
      WordDeserializer().refreshStyles(document);
      expect(_tabs(document.paragraphs.single), [(126.0, 'center', 'none')]);
      expect(
        _tabs(_read(WordSerializer().writeBytes(document)).paragraphs.single),
        [(126.0, 'center', 'none')],
      );
    },
  );

  test(
    'foreign and nested lookalikes do not enter tab projection or get removed',
    () async {
      final session = OfficeMacroSession(
        _fixture(
          '<x:tabs><w:tab w:pos="1200" w:val="center"/></x:tabs>'
          '<x:metadata><w:tabs><w:tab w:pos="1800" w:val="right"/></w:tabs></x:metadata>'
          '<w:tabs><x:tab w:pos="3000" w:val="decimal"/>'
          '<x:metadata><w:tab w:pos="3600" w:val="right"/></x:metadata>'
          '<w:tab w:pos="720" w:val="left"/></w:tabs>',
        ),
        format: OfficeMacroFormat.docx,
      );
      expect(_tabs(_read(session.bytes).paragraphs.single), [
        (36.0, 'left', 'none'),
      ]);
      await session.run(_plan([_add(72), _clear()]));
      final properties = _properties(session.bytes);
      expect(properties.firstChild('tabs', namespaceUri: _x), isNotNull);
      expect(properties.firstChild('metadata', namespaceUri: _x), isNotNull);
      expect(
        _nativeTabs(session.bytes).firstChild('tab', namespaceUri: _x),
        isNotNull,
      );
      expect(
        _nativeTabs(session.bytes).firstChild('metadata', namespaceUri: _x),
        isNotNull,
      );
      expect(_tabs(_read(session.bytes).paragraphs.single), isEmpty);
    },
  );

  test(
    'native pPr/default layers win over preceding foreign lookalikes',
    () async {
      final styles =
          '<w:docDefaults><x:pPrDefault><w:pPr><w:tabs><w:tab w:pos="1800" '
          'w:val="right"/></w:tabs></w:pPr></x:pPrDefault>'
          '<w:pPrDefault><x:pPr><w:tabs><w:tab w:pos="2160" w:val="right"/>'
          '</w:tabs></x:pPr><w:pPr><w:tabs><w:tab w:pos="360" w:val="left"/>'
          '</w:tabs></w:pPr></w:pPrDefault></w:docDefaults>'
          '<w:style w:type="paragraph" w:styleId="Base">'
          '<x:pPr><w:tabs><w:tab w:pos="2520" w:val="decimal"/></w:tabs></x:pPr>'
          '<w:pPr><w:tabs><w:tab w:pos="720" w:val="center"/></w:tabs>'
          '</w:pPr></w:style>';
      final session = OfficeMacroSession(
        _fixture('<w:pStyle w:val="Base"/>', styles: styles),
        format: OfficeMacroFormat.docx,
      );
      expect(_tabs(_read(session.bytes).paragraphs.single), [
        (18.0, 'left', 'none'),
        (36.0, 'center', 'none'),
      ]);
      await session.run(_plan([_add(72), _clear()]));
      expect(_stops(session.bytes).map((s) => _attr(s, 'pos')).toSet(), {
        '360',
        '720',
        '1440',
      });
      expect(_tabs(_read(session.bytes).paragraphs.single), isEmpty);
    },
  );

  test('custom Word prefix retains namespace-qualified metadata', () async {
    final session = OfficeMacroSession(
      _fixture(
        '<n:tabs xmlns:n="$_w" x:metadata="keep">'
        '<n:tab n:pos="720" n:val="right" x:val="opaque"/></n:tabs>',
      ),
      format: OfficeMacroFormat.docx,
    );
    await session.run(
      _plan([_add(36, alignment: 'center', leader: 'dot'), _add(-12.5)]),
    );
    final document = _read(session.bytes);
    expect(_tabs(document.paragraphs.single), [
      (-12.5, 'left', 'none'),
      (36.0, 'center', 'dot'),
    ]);
    expect(
      _nativeTabs(session.bytes).getAttribute('metadata', namespaceUri: _x),
      'keep',
    );
    expect(
      _stops(session.bytes)
          .singleWhere((s) => _attr(s, 'pos') == '720')
          .getAttribute('val', namespaceUri: _x),
      'opaque',
    );
  });

  for (final position in [-1584.0, -72.15, 0.0, 72.15, 1584.0]) {
    test('exact signed twip position $position survives save/reopen', () async {
      final session = OfficeMacroSession(
        _fixture(''),
        format: OfficeMacroFormat.docx,
      );
      await session.run(_plan([_add(position)]));
      expect(_tabs(_read(session.bytes).paragraphs.single), [
        (position, 'left', 'none'),
      ]);
      expect(
        _attr(_stops(session.bytes).single, 'pos'),
        '${(position * 20).round()}',
      );
    });
  }

  for (final arguments in <Map<String, Object?>>[
    {'position': 1584.05},
    {'position': -1584.05},
    {'position': 12.025},
    {'position': double.nan},
    {'position': double.infinity},
    {'position': '72'},
    {'position': true},
    {'position': 72, 'alignment': 'bar'},
    {'position': 72, 'leader': 'heavy'},
    {'position': 72, 'unknown': 1},
  ]) {
    test('invalid native arguments $arguments do not mutate the document', () {
      final document = _read(_fixture(_direct, styles: _styles));
      final source = document.paragraphs.single.properties.sourcePropertiesXml;
      final tabs = _tabs(document.paragraphs.single);
      expect(
        () => OfficeOperationCatalog.apply(document, 'docx.tabStop', {
          'paragraph': 0,
          ...arguments,
        }),
        throwsArgumentError,
      );
      expect(document.paragraphs.single.properties.sourcePropertiesXml, source);
      expect(_tabs(document.paragraphs.single), tabs);
    });
  }

  for (final (source, reason) in [
    (
      '<w:tabs><mc:AlternateContent><mc:Fallback>'
          '<w:tab w:pos="720" w:val="left"/>'
          '</mc:Fallback></mc:AlternateContent></w:tabs>',
      'markup-compatibility alternatives',
    ),
    (
      '<n:tabs xmlns:n="$_w" xmlns:w="$_x" w:metadata="keep">'
          '<n:tab n:pos="720" n:val="right" w:val="opaque"/></n:tabs>',
      'unambiguous native paragraph-properties namespace',
    ),
    ('<w:tabs/><w:tabs/>', 'one direct native tabs'),
    (
      '<w:tabs><w:tab w:pos="720" w:val="left"/><w:tab w:pos="0720" w:val="right"/></w:tabs>',
      'duplicate native tab positions',
    ),
    (
      '<w:tabs><w:tab w:pos="72pt" w:val="left"/></w:tabs>',
      'integer twip positions',
    ),
    (
      '<w:tabs><w:tab w:pos="2147483648" w:val="left"/></w:tabs>',
      'integer twip positions',
    ),
    (
      '<w:tabs><w:tab w:pos="720" w:val="future"/></w:tabs>',
      'recognized native tab alignment',
    ),
    (
      '<mc:AlternateContent><mc:Fallback><w:tabs><w:tab w:pos="720" w:val="left"/></w:tabs></mc:Fallback></mc:AlternateContent>',
      'markup-compatibility alternatives',
    ),
  ]) {
    test('ambiguous source refuses atomically: $reason', () async {
      final input = _fixture(source);
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      await expectLater(
        session.run(
          _plan([
            OfficeMacroStep(
              tool: 'docx.replaceText',
              arguments: {
                'paragraph': 0,
                'start': 0,
                'end': 0,
                'text': 'Before: ',
              },
            ),
            _add(72),
          ]),
        ),
        throwsA(
          isA<OfficeMacroException>().having(
            (e) => e.toString(),
            'reason',
            contains(reason),
          ),
        ),
      );
      expect(session.bytes, input);
      expect(session.revision, 0);
      final document = _read(input);
      final before = document.paragraphs.single.properties.sourcePropertiesXml;
      expect(
        () => OfficeOperationCatalog.apply(document, 'docx.clearTabStops', {
          'paragraph': 0,
        }),
        throwsA(
          isA<UnsupportedError>().having(
            (e) => e.toString(),
            'reason',
            contains(reason),
          ),
        ),
      );
      expect(document.paragraphs.single.properties.sourcePropertiesXml, before);
    });
  }

  test('pending non-tab edits survive tab ownership publication', () {
    final document = _read(_fixture(_direct, styles: _styles));
    OfficeOperationCatalog.apply(document, 'docx.paragraphFormat', {
      'paragraph': 0,
      'before': 12.5,
      'rtl': true,
    });
    OfficeOperationCatalog.apply(document, 'docx.tabStop', {
      'paragraph': 0,
      'position': 72.15,
    });
    final reopened = _read(WordSerializer().writeBytes(document));
    expect(reopened.paragraphs.single.properties.spacingBefore, 12.5);
    expect(reopened.paragraphs.single.properties.rightToLeft, isTrue);
    expect(reopened.paragraphs.single.properties.tabs.map((t) => t.position), [
      36,
      72.15,
      90,
      108,
    ]);
  });

  test(
    'clear custom definitions preserves hanging-indent formatting',
    () async {
      final session = OfficeMacroSession(
        _fixture(
          '<w:ind w:left="720" w:hanging="360"/>'
          '<w:tabs><w:tab w:pos="1440" w:val="left"/></w:tabs>',
        ),
        format: OfficeMacroFormat.docx,
      );
      await session.run(_plan([_clear()]));
      final document = _read(session.bytes);
      expect(document.paragraphs.single.properties.indent.left, 36);
      expect(document.paragraphs.single.properties.indent.hanging, 18);
      expect(document.paragraphs.single.properties.tabs, isEmpty);
      final again = _read(WordSerializer().writeBytes(document));
      expect(again.paragraphs.single.properties.indent.hanging, 18);
      expect(again.paragraphs.single.properties.tabs, isEmpty);
    },
  );

  test(
    'legacy paragraphFormat tabs replaces the effective set on styled paragraphs',
    () {
      final document = _read(_fixture(_direct, styles: _styles));
      OfficeOperationCatalog.apply(document, 'docx.paragraphFormat', {
        'paragraph': 0,
        'before': 12.5,
        'tabs': [
          {'position': 144, 'alignment': 'right', 'leader': 'dot'},
        ],
      });
      expect(_tabs(document.paragraphs.single), [(144.0, 'right', 'dot')]);
      final reopened = _read(WordSerializer().writeBytes(document));
      expect(_tabs(reopened.paragraphs.single), [(144.0, 'right', 'dot')]);
      expect(reopened.paragraphs.single.properties.spacingBefore, 12.5);
      OfficeOperationCatalog.apply(reopened, 'docx.paragraphFormat', {
        'paragraph': 0,
        'tabs': <Object?>[],
      });
      expect(reopened.paragraphs.single.properties.tabs, isEmpty);
      expect(
        _read(
          WordSerializer().writeBytes(reopened),
        ).paragraphs.single.properties.tabs,
        isEmpty,
      );
    },
  );

  test('legacy tab-array acceptance keeps large and fractional positions', () {
    final document = _read(
      _fixture('<w:pStyle w:val="Derived"/>', styles: _styles),
    );
    OfficeOperationCatalog.apply(document, 'docx.paragraphFormat', {
      'paragraph': 0,
      'tabs': [
        {'position': 2000.025, 'alignment': 'center'},
      ],
    });
    // The legacy serializer rounds to twips; it does not acquire the stricter
    // source-dialect position range or exact-twip requirement.
    expect(_tabs(document.paragraphs.single), [(2000.05, 'center', 'none')]);
    expect(
      _tabs(_read(WordSerializer().writeBytes(document)).paragraphs.single),
      [(2000.05, 'center', 'none')],
    );
  });

  test(
    'legacy replacement refuses unsupported source before any field or inline edit',
    () {
      final document = _read(
        _fixture(
          '<w:tabs><w:tab w:pos="720" w:val="left"/>'
          '<w:tab w:pos="720" w:val="right"/></w:tabs>',
        ),
      );
      final target = document.paragraphs.single;
      target.inlines.insert(0, WmlBreak(WmlBreakType.column));
      final source = target.properties.sourcePropertiesXml;
      final before = target.properties.spacingBefore;
      expect(
        () => OfficeOperationCatalog.apply(document, 'docx.paragraphFormat', {
          'paragraph': 0,
          'before': 18,
          'columnBreakBefore': false,
          'tabs': <Object?>[],
        }),
        throwsA(isA<UnsupportedError>()),
      );
      expect(target.properties.sourcePropertiesXml, source);
      expect(target.properties.spacingBefore, before);
      expect(target.inlines.first, isA<WmlBreak>());
    },
  );

  for (final style in [
    '<w:style w:type="paragraph" w:styleId="Base">'
        '<mc:AlternateContent><mc:Fallback><w:pPr><w:tabs>'
        '<w:tab w:pos="720" w:val="left"/>'
        '</w:tabs></w:pPr></mc:Fallback></mc:AlternateContent></w:style>',
    '<w:docDefaults><mc:AlternateContent><mc:Fallback><w:pPrDefault><w:pPr>'
        '<w:tabs><w:tab w:pos="720" w:val="left"/></w:tabs>'
        '</w:pPr></w:pPrDefault></mc:Fallback></mc:AlternateContent></w:docDefaults>',
  ]) {
    test(
      'MC wrappers around native style/default properties refuse atomically: ${style.substring(0, 25)}',
      () async {
        final bytes = _fixture('<w:pStyle w:val="Base"/>', styles: style);
        final package = OpcPackage.openBytes(bytes);
        final part = package.getPart('/word/styles.xml')!;
        part.writeText(
          part.readText().replaceFirst(
            '<w:styles ',
            '<w:styles xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006" ',
          ),
        );
        final input = package.save();
        final session = OfficeMacroSession(
          input,
          format: OfficeMacroFormat.docx,
        );
        await expectLater(
          session.run(_plan([_clear()])),
          throwsA(
            isA<OfficeMacroException>().having(
              (e) => e.message,
              'reason',
              contains('markup-compatibility alternatives'),
            ),
          ),
        );
        expect(session.bytes, input);
        expect(session.revision, 0);
      },
    );
  }

  test('table style tabs are cumulative and clearing a cell stays local', () {
    final document = _read(
      _fixture(
        '',
        styles:
            '<w:style w:type="table" w:styleId="Grid"><w:pPr><w:tabs>'
            '<w:tab w:pos="720" w:val="center"/><w:tab w:pos="1080" w:val="bar"/>'
            '</w:tabs></w:pPr></w:style>',
        body:
            '<w:tbl><w:tblPr><w:tblStyle w:val="Grid"/></w:tblPr>'
            '<w:tblGrid><w:gridCol w:w="3000"/><w:gridCol w:w="3000"/></w:tblGrid><w:tr>'
            '<w:tc><w:p><w:r><w:t>First</w:t></w:r></w:p></w:tc>'
            '<w:tc><w:p><w:r><w:t>Second</w:t></w:r></w:p></w:tc>'
            '</w:tr></w:tbl>',
      ),
    );
    expect(document.paragraphs.map(_tabs), [
      [(36.0, 'center', 'none')],
      [(36.0, 'center', 'none')],
    ]);
    OfficeOperationCatalog.apply(document, 'docx.tabStop', {
      'paragraph': 0,
      'position': 72,
    });
    expect(_tabs(document.paragraphs.first), [
      (36.0, 'center', 'none'),
      (72.0, 'left', 'none'),
    ]);
    OfficeOperationCatalog.apply(document, 'docx.clearTabStops', {
      'paragraph': 0,
    });
    final reopened = _read(WordSerializer().writeBytes(document));
    expect(reopened.paragraphs.map(_tabs), [
      <(double, String, String)>[],
      [(36.0, 'center', 'none')],
    ]);
  });

  test(
    'inline tab characters inside MC do not trigger the custom-tab guard',
    () async {
      final session = OfficeMacroSession(
        _fixture(
          '',
          body:
              '<w:p><mc:AlternateContent><mc:Fallback>'
              '<w:r><w:t>One</w:t><w:tab/><w:t>Two</w:t></w:r>'
              '</mc:Fallback></mc:AlternateContent></w:p>',
        ),
        format: OfficeMacroFormat.docx,
      );
      await session.run(_plan([_add(72)]));
      final paragraph = _read(session.bytes).paragraphs.single;
      expect(paragraph.text, 'One\tTwo');
      expect(_tabs(paragraph), [(72.0, 'left', 'none')]);
    },
  );
}
