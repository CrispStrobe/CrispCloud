import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/automation/operations/word_steps.dart'
    as native;
import 'package:test/test.dart';

const _w = OfficeNamespaces.w;
const _x = 'urn:paragraph-control-tests';

Uint8List _fixture({
  String properties = '',
  String? styles,
  String? body,
  String prefix = 'w',
}) {
  final package = OpcPackage.openBytes(
    (DocxDocumentBuilder()..paragraph('Template')).build(),
  );
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<$prefix:document xmlns:$prefix="$_w" xmlns:x="$_x" '
        'xmlns:mc="${OfficeNamespaces.mc}"><$prefix:body>'
        '${body ?? '<$prefix:p><$prefix:pPr>$properties</$prefix:pPr>'
                '<$prefix:r><$prefix:rPr><$prefix:i/></$prefix:rPr>'
                '<$prefix:t>Original</$prefix:t></$prefix:r></$prefix:p>'}'
        '<$prefix:sectPr/></$prefix:body></$prefix:document>',
      );
  if (styles != null) {
    package
        .getPart('/word/styles.xml')!
        .writeText(
          '<w:styles xmlns:w="$_w" xmlns:x="$_x" '
          'xmlns:mc="${OfficeNamespaces.mc}">$styles</w:styles>',
        );
  }
  return package.save();
}

WmlDocument _read(Uint8List bytes) => WordDeserializer().readBytes(bytes);

XmlElement _properties(Uint8List bytes) =>
    XmlDocument.parse(
          OpcPackage.openBytes(bytes).getPart('/word/document.xml')!.readText(),
        ).root!
        .firstChild('body', namespaceUri: _w)!
        .firstChild('p', namespaceUri: _w)!
        .firstChild('pPr', namespaceUri: _w)!;

XmlElement _spacing(Uint8List bytes) =>
    _properties(bytes).firstChild('spacing', namespaceUri: _w)!;

String? _value(XmlElement element, String name) =>
    element.getAttribute(name, namespaceUri: _w);

Map<String, Object?> _step(String action) => {
  'op': 'paragraphSpaceBefore',
  'paragraph': 0,
  'action': action,
};

Map<String, Uint8List> _parts(WmlDocument document) => {
  for (final part in document.package!.parts) part.uri: part.readBytes(),
};

void _refuses(
  WmlDocument document,
  Map<String, Object?> step, {
  Matcher? matcher,
}) {
  final paragraph = document.paragraphs.first;
  final properties = paragraph.properties;
  final source = properties.sourcePropertiesXml;
  final imported = Map<String, String>.from(properties.importedValues ?? {});
  final parts = _parts(document);
  expect(
    () => native.applyStep(document, step),
    matcher ?? throwsUnsupportedError,
  );
  expect(identical(paragraph.properties, properties), isTrue);
  expect(properties.sourcePropertiesXml, source);
  expect(properties.importedValues ?? {}, imported);
  expect(_parts(document), parts);
}

void main() {
  for (final (before, expectedToggle) in [
    ('0', '240'),
    ('1', '0'),
    ('180', '0'),
    ('240', '0'),
    ('2147483647', '0'),
  ]) {
    for (final (action, expected) in [
      ('open', '240'),
      ('close', '0'),
      ('toggle', expectedToggle),
    ]) {
      test('$action from $before twips survives repeated native reopens', () {
        final document = _read(
          _fixture(properties: '<w:spacing w:before="$before"/>'),
        );
        native.applyStep(document, _step(action));
        var bytes = WordSerializer().writeBytes(document);
        for (var cycle = 0; cycle < 3; cycle++) {
          expect(_value(_spacing(bytes), 'before'), expected);
          final reopened = _read(bytes);
          expect(reopened.paragraphs.single.text, 'Original');
          expect(
            reopened.paragraphs.single.properties.spacingBefore,
            int.parse(expected) / 20,
          );
          bytes = WordSerializer().writeBytes(reopened);
        }
      });
    }
  }

  for (final action in ['open', 'close', 'toggle']) {
    test('$action supports empty paragraphs without structural changes', () {
      final document = _read(_fixture(body: '<w:p/>'));
      native.applyStep(document, _step(action));
      final saved = WordSerializer().writeBytes(document);
      expect(
        _value(_spacing(saved), 'before'),
        action == 'close' ? '0' : '240',
      );
      expect(_read(saved).paragraphs.single.text, isEmpty);
    });

    test(
      '$action changes only native before ownership and preserves metadata',
      () {
        final document = _read(
          _fixture(
            properties:
                '<w:keepNext/><w:spacing w:before="180" w:beforeAutospacing="0" '
                'w:after="140" w:afterLines="30" w:afterAutospacing="1" '
                'w:line="360" w:lineRule="exact" x:before="opaque-before" '
                'x:beforeAutospacing="opaque-auto" x:token="keep">'
                '<x:child x:val="child"/></w:spacing>'
                '<x:spacing x:before="foreign-spacing"/>'
                '<w:ind w:left="240" w:right="160"/><w:tabs>'
                '<w:tab w:pos="1440" w:val="right"/></w:tabs>',
          ),
        );
        native.applyStep(document, _step(action));
        var saved = WordSerializer().writeBytes(document);
        for (var cycle = 0; cycle < 3; cycle++) {
          final spacing = _spacing(saved);
          expect(_value(spacing, 'before'), action == 'open' ? '240' : '0');
          expect(_value(spacing, 'beforeAutospacing'), isNull);
          for (final entry in {
            'after': '140',
            'afterLines': '30',
            'afterAutospacing': '1',
            'line': '360',
            'lineRule': 'exact',
          }.entries) {
            expect(_value(spacing, entry.key), entry.value);
          }
          expect(
            spacing.getAttribute('before', namespaceUri: _x),
            'opaque-before',
          );
          expect(
            spacing.getAttribute('beforeAutospacing', namespaceUri: _x),
            'opaque-auto',
          );
          expect(
            spacing
                .firstChild('child', namespaceUri: _x)!
                .getAttribute('val', namespaceUri: _x),
            'child',
          );
          final properties = _properties(saved);
          expect(
            properties
                .firstChild('spacing', namespaceUri: _x)!
                .getAttribute('before', namespaceUri: _x),
            'foreign-spacing',
          );
          expect(
            properties.firstChild('keepNext', namespaceUri: _w),
            isNotNull,
          );
          final reopened = _read(saved);
          final paragraph = reopened.paragraphs.single;
          expect(paragraph.properties.indent.right, 8);
          expect(paragraph.properties.tabs.single.position, 72);
          expect(
            paragraph.inlines.whereType<WmlRun>().single.properties.italic,
            isTrue,
          );
          saved = WordSerializer().writeBytes(reopened);
        }
      },
    );

    test(
      '$action same-value assignment owns before while other attributes inherit',
      () {
        final document = _read(
          _fixture(
            properties: '<w:pStyle w:val="Layout"/>',
            styles:
                '<w:style w:type="paragraph" w:styleId="Layout"><w:pPr>'
                '<w:spacing w:before="${action == 'open' ? '240' : '0'}" '
                'w:after="180" w:line="360" w:lineRule="exact"/>'
                '</w:pPr></w:style>',
          ),
        );
        native.applyStep(document, _step(action));
        final saved = WordSerializer().writeBytes(document);
        final spacing = _spacing(saved);
        expect(_value(spacing, 'before'), action == 'close' ? '0' : '240');
        expect(_value(spacing, 'after'), isNull);
        expect(_value(spacing, 'line'), isNull);
        final package = OpcPackage.openBytes(saved);
        package
            .getPart('/word/styles.xml')!
            .writeText(
              '<w:styles xmlns:w="$_w"><w:style w:type="paragraph" w:styleId="Layout">'
              '<w:pPr><w:spacing w:before="480" w:after="600" w:line="480" '
              'w:lineRule="atLeast"/></w:pPr></w:style></w:styles>',
            );
        final reopened = WordDeserializer().read(package);
        final properties = reopened.paragraphs.single.properties;
        expect(properties.spacingBefore, action == 'close' ? 0 : 12);
        expect(properties.spacingAfter, 30);
        expect(properties.lineSpacing, 24);
        expect(properties.lineSpacingRule, WmlLineSpacingRule.atLeast);
        expect(
          _value(_spacing(WordSerializer().writeBytes(reopened)), 'after'),
          isNull,
        );
      },
    );
  }

  test('toggle resolves document defaults and based-on styles', () {
    for (final styles in [
      '<w:docDefaults><w:pPrDefault><w:pPr><w:spacing w:before="120"/>'
          '</w:pPr></w:pPrDefault></w:docDefaults>'
          '<w:style w:type="paragraph" w:styleId="Layout"/>',
      '<w:style w:type="paragraph" w:styleId="Base"><w:pPr>'
          '<w:spacing w:before="120"/></w:pPr></w:style>'
          '<w:style w:type="paragraph" w:styleId="Layout"><w:basedOn w:val="Base"/></w:style>',
    ]) {
      final document = _read(
        _fixture(properties: '<w:pStyle w:val="Layout"/>', styles: styles),
      );
      expect(document.paragraphs.single.properties.spacingBefore, 6);
      native.applyStep(document, _step('toggle'));
      expect(
        _value(_spacing(WordSerializer().writeBytes(document)), 'before'),
        '0',
      );
    }
  });

  test(
    'toggle sees preceding native writes and preserves their direct ownership',
    () {
      final document = _read(_fixture());
      native.applyStep(document, {
        'op': 'paragraphFormat',
        'paragraph': 0,
        'before': 9,
        'after': 7,
      });
      native.applyStep(document, {
        'op': 'lineSpacing',
        'paragraph': 0,
        'rule': 'exact',
        'points': 18,
      });
      native.applyStep(document, _step('toggle'));
      expect(document.paragraphs.single.properties.spacingBefore, 0);
      native.applyStep(document, _step('toggle'));
      final spacing = _spacing(WordSerializer().writeBytes(document));
      expect(_value(spacing, 'before'), '240');
      expect(_value(spacing, 'after'), '140');
      expect(_value(spacing, 'line'), '360');
      expect(_value(spacing, 'lineRule'), 'exact');
    },
  );

  test('native prefix aliases and foreign collisions remain distinct', () {
    final document = _read(
      _fixture(
        prefix: 'q',
        properties:
            '<q:spacing q:before="120" q:after="180" x:before="foreign" '
            'x:beforeLines="opaque" x:beforeAutospacing="true"/>'
            '<x:spacing q:before="-1" q:beforeLines="10"/>',
      ),
    );
    expect(document.paragraphs.single.properties.spacingBefore, 6);
    native.applyStep(document, _step('toggle'));
    var bytes = WordSerializer().writeBytes(document);
    for (var cycle = 0; cycle < 3; cycle++) {
      expect(_value(_spacing(bytes), 'before'), '0');
      expect(_value(_spacing(bytes), 'after'), '180');
      expect(
        _spacing(bytes).getAttribute('before', namespaceUri: _x),
        'foreign',
      );
      expect(
        _properties(bytes)
            .firstChild('spacing', namespaceUri: _x)!
            .getAttribute('before', namespaceUri: _w),
        '-1',
      );
      bytes = WordSerializer().writeBytes(_read(bytes));
    }
  });

  test(
    'alternate inherited prefixes resolve before without owning after or line',
    () {
      final document = _read(
        _fixture(
          properties: '<w:pStyle w:val="Layout"/><w:spacing x:token="direct"/>',
          styles:
              '<q:style xmlns:q="$_w" w:type="paragraph" w:styleId="Layout">'
              '<q:pPr><q:spacing q:before="180" q:after="240" q:line="400" '
              'q:lineRule="exact" x:before="opaque"/></q:pPr></q:style>',
        ),
      );
      expect(document.paragraphs.single.properties.spacingBefore, 9);
      native.applyStep(document, _step('toggle'));
      final bytes = WordSerializer().writeBytes(document);
      expect(_value(_spacing(bytes), 'before'), '0');
      expect(_value(_spacing(bytes), 'after'), isNull);
      expect(_value(_spacing(bytes), 'line'), isNull);
      expect(_read(bytes).paragraphs.single.properties.spacingAfter, 12);
      expect(_read(bytes).paragraphs.single.properties.lineSpacing, 20);
      expect(
        OpcPackage.openBytes(bytes).getPart('/word/styles.xml')!.readText(),
        contains('x:before="opaque"'),
      );
    },
  );

  for (final raw in ['-1', '1.5', '12pt', 'bad', '2147483648', '1e309']) {
    test('invalid native before=$raw refuses before mutation', () {
      final document = _read(
        _fixture(properties: '<w:spacing w:before="$raw"/>'),
      );
      for (final action in ['open', 'close', 'toggle']) {
        _refuses(document, _step(action));
      }
    });
  }

  for (final (name, styles) in [
    ('missing ID', '<w:style w:type="paragraph"><w:pPr/></w:style>'),
    (
      'duplicate ID',
      '<w:style w:type="paragraph" w:styleId="A"/>'
          '<w:style w:type="paragraph" w:styleId="A"/>',
    ),
    (
      'duplicate expanded ID',
      '<w:style xmlns:q="$_w" w:type="paragraph" '
          'w:styleId="A" q:styleId="B"/>',
    ),
    (
      'multiple defaults',
      '<w:style w:type="paragraph" w:styleId="A" w:default="1"/>'
          '<w:style w:type="paragraph" w:styleId="B" w:default="true"/>',
    ),
    (
      'invalid default flag',
      '<w:style w:type="paragraph" w:styleId="A" w:default="yes"/>',
    ),
    (
      'multiple defaults including omitted type',
      '<w:style w:styleId="A" w:default="1"/>'
          '<w:style w:type="paragraph" w:styleId="B" w:default="on"/>',
    ),
    ('invalid native type', '<w:style w:type="unknown" w:styleId="A"/>'),
    ('empty native type', '<w:style w:type="" w:styleId="A"/>'),
    (
      'paragraph based on character',
      '<w:style w:type="paragraph" w:styleId="A"><w:basedOn w:val="B"/></w:style>'
          '<w:style w:type="character" w:styleId="B"/>',
    ),
    (
      'omitted paragraph type based on table',
      '<w:style w:styleId="A"><w:basedOn w:val="B"/></w:style>'
          '<w:style w:type="table" w:styleId="B"/>',
    ),
    (
      'character based on paragraph',
      '<w:style w:type="character" w:styleId="A"><w:basedOn w:val="B"/></w:style>'
          '<w:style w:type="paragraph" w:styleId="B"/>',
    ),
    (
      'table based on character',
      '<w:style w:type="table" w:styleId="A"><w:basedOn w:val="B"/></w:style>'
          '<w:style w:type="character" w:styleId="B"/>',
    ),
    (
      'numbering based on numbering',
      '<w:style w:type="numbering" w:styleId="A"><w:basedOn w:val="B"/></w:style>'
          '<w:style w:type="numbering" w:styleId="B"/>',
    ),
    (
      'missing parent ID',
      '<w:style w:type="paragraph" w:styleId="A"><w:basedOn/></w:style>',
    ),
    (
      'missing parent style',
      '<w:style w:type="paragraph" w:styleId="A"><w:basedOn w:val="Missing"/></w:style>',
    ),
    (
      'duplicate parent',
      '<w:style w:type="paragraph" w:styleId="A">'
          '<w:basedOn w:val="B"/><w:basedOn w:val="B"/></w:style>'
          '<w:style w:type="paragraph" w:styleId="B"/>',
    ),
    (
      'self cycle',
      '<w:style w:type="paragraph" w:styleId="A"><w:basedOn w:val="A"/></w:style>',
    ),
    (
      'two-style cycle',
      '<w:style w:type="paragraph" w:styleId="A"><w:basedOn w:val="B"/></w:style>'
          '<w:style w:type="paragraph" w:styleId="B"><w:basedOn w:val="A"/></w:style>',
    ),
  ]) {
    test('ambiguous style source $name refuses before any mutation', () {
      final document = _read(_fixture(styles: styles));
      for (final action in ['open', 'close', 'toggle']) {
        _refuses(document, _step(action));
      }
    });
  }

  for (final type in ['character', 'table', 'numbering', 'missing']) {
    test('paragraph selector with $type style refuses before mutation', () {
      final document = _read(
        _fixture(
          properties: '<w:pStyle w:val="Target"/>',
          styles: type == 'missing'
              ? ''
              : '<w:style w:type="$type" w:styleId="Target"><w:pPr>'
                    '<w:spacing w:before="120"/></w:pPr></w:style>',
        ),
      );
      for (final action in ['open', 'close', 'toggle']) {
        _refuses(document, _step(action));
      }
    });
  }

  for (final type in ['paragraph', 'character', 'numbering', 'missing']) {
    test('table selector with $type style refuses before mutation', () {
      final document = _read(
        _fixture(
          body:
              '<w:p/><w:tbl><w:tblPr><w:tblStyle w:val="Target"/></w:tblPr>'
              '<w:tr><w:tc><w:p/></w:tc></w:tr></w:tbl>',
          styles: type == 'missing'
              ? ''
              : '<w:style w:type="$type" w:styleId="Target"><w:pPr>'
                    '<w:spacing w:before="120"/></w:pPr></w:style>',
        ),
      );
      for (final action in ['open', 'close', 'toggle']) {
        _refuses(document, _step(action));
      }
    });
  }

  for (final type in ['paragraph', 'table']) {
    test('unreferenced $type style cannot resolve an active selector', () {
      final package = OpcPackage.openBytes(
        _fixture(
          properties: type == 'paragraph' ? '<w:pStyle w:val="Target"/>' : '',
          body: type == 'table'
              ? '<w:p/><w:tbl><w:tblPr><w:tblStyle w:val="Target"/></w:tblPr>'
                    '<w:tr><w:tc><w:p/></w:tc></w:tr></w:tbl>'
              : null,
          styles: '',
        ),
      );
      package
          .createPart(
            '/word/unused-styles.xml',
            package.getPart('/word/styles.xml')!.contentType,
          )
          .writeText(
            '<w:styles xmlns:w="$_w"><w:style w:type="$type" '
            'w:styleId="Target"><w:pPr><w:spacing w:before="120"/>'
            '</w:pPr></w:style></w:styles>',
          );
      final document = _read(package.save());
      expect(document.package!.getPart('/word/unused-styles.xml'), isNotNull);
      for (final action in ['open', 'close', 'toggle']) {
        _refuses(
          document,
          _step(action),
          matcher: throwsA(
            isA<UnsupportedError>().having(
              (error) => error.message,
              'reason',
              contains(
                type == 'paragraph'
                    ? 'resolved paragraph style'
                    : 'correct type',
              ),
            ),
          ),
        );
      }
    });
  }

  test(
    'paragraph selector resolves the related styles part at a custom path',
    () {
      final package = OpcPackage.openBytes(
        _fixture(
          properties: '<w:pStyle w:val="Target"/>',
          styles:
              '<w:style w:type="paragraph" w:styleId="Target"><w:pPr>'
              '<w:spacing w:before="120"/></w:pPr></w:style>',
        ),
      );
      final conventional = package.getPart('/word/styles.xml')!;
      final source =
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '${conventional.readText()}';
      package
          .createPart('/word/custom-styles.xml', conventional.contentType)
          .writeText(source);
      conventional.writeText('<w:styles xmlns:w="$_w"/>');
      final relationships = package.relationshipsFor('/word/document.xml');
      final previous = relationships.firstByType(RelationshipTypes.styles)!;
      relationships
        ..removeById(previous.id)
        ..add(
          type: RelationshipTypes.styles,
          target: 'custom-styles.xml',
          id: previous.id,
        );
      final document = _read(package.save());
      expect(document.paragraphs.single.properties.spacingBefore, 6);
      native.applyStep(document, _step('toggle'));
      final saved = WordSerializer().writeBytes(document);
      expect(_value(_spacing(saved), 'before'), '0');
      expect(_read(saved).paragraphs.single.properties.spacingBefore, 0);
      expect(
        OpcPackage.openBytes(
          saved,
        ).getPart('/word/custom-styles.xml')!.readText(),
        source,
      );
    },
  );

  for (final (name, properties) in [
    ('foreign element', '<x:pStyle w:val="Target"/>'),
    ('foreign value', '<w:pStyle x:val="Target"/>'),
    ('foreign and native values', '<w:pStyle x:val="Zero" w:val="Target"/>'),
    ('unqualified and native values', '<w:pStyle val="Zero" w:val="Target"/>'),
    ('nested native', '<x:extension><w:pStyle w:val="Target"/></x:extension>'),
    (
      'duplicate native',
      '<w:pStyle w:val="Target"/><w:pStyle w:val="Target"/>',
    ),
    (
      'duplicate expanded value',
      '<w:pStyle xmlns:q="$_w" w:val="Target" q:val="Target"/>',
    ),
  ]) {
    test('$name paragraph style selector refuses before mutation', () {
      final document = _read(
        _fixture(
          properties: properties,
          styles:
              '<w:style w:type="paragraph" w:styleId="Target"><w:pPr>'
              '<w:spacing w:before="120"/></w:pPr></w:style>'
              '<w:style w:type="paragraph" w:styleId="Zero"/>',
        ),
      );
      for (final action in ['open', 'close', 'toggle']) {
        _refuses(document, _step(action));
      }
    });
  }

  for (final attribute in [
    'w:beforeLines="0"',
    'w:beforeLines="100"',
    'w:beforeAutospacing="1"',
    'w:beforeAutospacing="true"',
    'w:beforeAutospacing="on"',
    'w:beforeAutospacing="unknown"',
  ]) {
    for (final location in ['direct', 'style', 'defaults']) {
      test('$location $attribute refuses automatic or line-based inference', () {
        final spacing = '<w:spacing w:before="0" $attribute/>';
        final document = _read(
          _fixture(
            properties: location == 'direct'
                ? spacing
                : '<w:pStyle w:val="Layout"/>',
            styles: switch (location) {
              'style' =>
                '<w:style w:type="paragraph" w:styleId="Layout"><w:pPr>$spacing</w:pPr></w:style>',
              'defaults' =>
                '<w:docDefaults><w:pPrDefault><w:pPr>$spacing</w:pPr></w:pPrDefault></w:docDefaults>',
              _ => null,
            },
          ),
        );
        for (final action in ['open', 'close', 'toggle']) {
          _refuses(document, _step(action));
        }
      });
    }
  }

  for (final value in ['0', 'false', 'off']) {
    test('explicit disabled automatic spacing $value supports toggle', () {
      final document = _read(
        _fixture(
          properties: '<w:spacing w:before="0" w:beforeAutospacing="$value"/>',
        ),
      );
      native.applyStep(document, _step('toggle'));
      expect(
        _value(_spacing(WordSerializer().writeBytes(document)), 'before'),
        '240',
      );
    });
  }

  for (final properties in [
    '<w:spacing w:before="0"/><w:spacing w:before="240"/>',
    '<w:spacing xmlns:q="$_w" w:before="0" q:before="240"/>',
    '<w:spacing xmlns:q="$_w" w:beforeAutospacing="0" q:beforeAutospacing="false"/>',
    '<mc:AlternateContent><mc:Choice Requires="x"><w:spacing w:before="120"/></mc:Choice><mc:Fallback/></mc:AlternateContent>',
    '<mc:AlternateContent><mc:Choice Requires="x"><x:spacing x:before="120"/></mc:Choice><mc:Fallback/></mc:AlternateContent>',
  ]) {
    test(
      'ambiguous before packet ${properties.substring(0, properties.length.clamp(0, 70))} refuses',
      () {
        final document = _read(_fixture(properties: properties));
        _refuses(document, _step('toggle'));
      },
    );
  }

  test('alternative wrappers around paragraph properties refuse', () {
    final document = _read(
      _fixture(
        body:
            '<w:p><mc:AlternateContent><mc:Choice Requires="x">'
            '<w:pPr><w:spacing w:before="120"/></w:pPr>'
            '</mc:Choice><mc:Fallback><w:pPr/></mc:Fallback></mc:AlternateContent>'
            '<w:r><w:t>Original</w:t></w:r></w:p>',
      ),
    );
    _refuses(document, _step('open'));
  });

  test('unbalanced modeled fields refuse before source mutation', () {
    final document = _read(
      _fixture(
        body:
            '<w:p><w:r><w:fldChar w:fldCharType="begin"/></w:r>'
            '<w:r><w:instrText> REF unfinished </w:instrText></w:r>'
            '<w:r><w:t>Original</w:t></w:r></w:p>',
      ),
    );
    _refuses(document, _step('close'));
  });

  for (final region in [
    'lastRow',
    'firstCol',
    'lastCol',
    'band1Vert',
    'nwCell',
  ]) {
    test('unmodeled table region $region with before spacing refuses', () {
      final document = _read(
        _fixture(
          styles:
              '<w:style w:type="table" w:styleId="Table"><w:tblStylePr w:type="$region">'
              '<w:pPr><w:spacing w:before="120"/></w:pPr></w:tblStylePr></w:style>',
        ),
      );
      _refuses(document, _step('toggle'));
    });
  }

  test('numbering-level paragraph spacing cannot be silently inferred', () {
    final document = _read(_fixture());
    document.package!
        .getPart('/word/numbering.xml')!
        .writeText(
          '<w:numbering xmlns:w="$_w"><w:abstractNum w:abstractNumId="8">'
          '<w:lvl w:ilvl="0"><w:pPr><w:spacing w:before="120"/></w:pPr></w:lvl>'
          '</w:abstractNum></w:numbering>',
        );
    _refuses(document, _step('toggle'));
  });

  for (final values in <Map<String, Object?>>[
    {'action': 'invalid'},
    {'action': 'OPEN'},
    {'action': 1},
    {'action': null},
    {'paragraph': -1},
    {'paragraph': 1},
    {'paragraph': 0.5},
    {'extra': 1},
  ]) {
    test('invalid native arguments $values refuse without side effects', () {
      _refuses(_read(_fixture()), {
        ..._step('toggle'),
        ...values,
      }, matcher: throwsArgumentError);
    });
  }

  test('missing action refuses without side effects', () {
    _refuses(_read(_fixture()), {
      'op': 'paragraphSpaceBefore',
      'paragraph': 0,
    }, matcher: throwsArgumentError);
  });

  for (final before in [-1.0, 0.01, double.nan, double.infinity, 107374182.4]) {
    test('invalid authored effective spacing $before refuses', () {
      final document = _read(_fixture());
      document.paragraphs.single.properties.spacingBefore = before;
      _refuses(document, _step('toggle'));
    });
  }
}
