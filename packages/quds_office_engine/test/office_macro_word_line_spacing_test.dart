import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/automation/operations/word_steps.dart'
    as native;
import 'package:test/test.dart';

const _w = OfficeNamespaces.w;
const _x = 'urn:line-spacing-test';

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
        'xmlns:mc="${OfficeNamespaces.mc}">'
        '<$prefix:body>${body ?? '<$prefix:p><$prefix:pPr>$properties</$prefix:pPr>'
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
String? _val(XmlElement node, String name) =>
    node.getAttribute(name, namespaceUri: _w);

Map<String, Object?> _step({String rule = 'exact', num points = 18}) => {
  'op': 'lineSpacing',
  'paragraph': 0,
  'rule': rule,
  'points': points,
};

Map<String, Uint8List> _parts(WmlDocument document) => {
  for (final part in document.package!.parts) part.uri: part.readBytes(),
};

void _refuses(
  WmlDocument document,
  Map<String, Object?> operation, {
  Matcher? matcher,
}) {
  final paragraph = document.paragraphs.first;
  final properties = paragraph.properties;
  final source = properties.sourcePropertiesXml;
  final imported = Map<String, String>.from(properties.importedValues ?? {});
  final parts = _parts(document);
  expect(
    () => native.applyStep(document, operation),
    matcher ?? throwsUnsupportedError,
  );
  expect(identical(paragraph.properties, properties), isTrue);
  expect(properties.sourcePropertiesXml, source);
  expect(properties.importedValues ?? {}, imported);
  expect(_parts(document), parts);
}

void main() {
  for (final (rule, nativeRule) in [
    ('exact', WmlLineSpacingRule.exact),
    ('atLeast', WmlLineSpacingRule.atLeast),
    ('multiple', WmlLineSpacingRule.auto),
  ]) {
    for (final points in [0.05, 0.15, 7.15, 12.0, 18.5, 36.0, 107374182.35]) {
      test(
        '$rule $points points serializes exact native units through reopens',
        () {
          final document = _read(
            _fixture(
              properties: '<w:spacing w:line="400" w:lineRule="atLeast"/>',
            ),
          );
          native.applyStep(document, _step(rule: rule, points: points));
          var saved = WordSerializer().writeBytes(document);
          for (var cycle = 0; cycle < 3; cycle++) {
            final spacing = _spacing(saved);
            expect(_val(spacing, 'line'), '${(points * 20).round()}');
            expect(_val(spacing, 'lineRule'), nativeRule.name);
            final reopened = _read(saved);
            final properties = reopened.paragraphs.single.properties;
            final expected = rule == 'multiple' ? points / 12 : points;
            expect(properties.lineSpacing, closeTo(expected, 0.00000001));
            expect(properties.lineSpacingRule, nativeRule);
            expect(properties.explicitLineSpacing, isTrue);
            saved = WordSerializer().writeBytes(reopened);
          }
        },
      );
    }

    test('$rule works on an empty paragraph without creating text', () {
      final document = _read(_fixture(body: '<w:p/>'));
      native.applyStep(document, _step(rule: rule));
      final saved = WordSerializer().writeBytes(document);
      expect(_val(_spacing(saved), 'line'), '360');
      expect(_read(saved).paragraphs.single.text, isEmpty);
      expect(_read(saved).paragraphs, hasLength(1));
    });

    test(
      '$rule owns line attributes while preserving sparse native metadata',
      () {
        final document = _read(
          _fixture(
            properties:
                '<w:spacing w:before="120" w:after="180" '
                'w:beforeLines="10" w:afterLines="20" w:beforeAutospacing="1" '
                'w:afterAutospacing="0" w:line="480" w:lineRule="auto" '
                'x:line="opaque-line" x:lineRule="opaque-rule" x:token="keep">'
                '<x:child x:val="keep-child"/></w:spacing>'
                '<x:spacing w:line="960" x:token="foreign-spacing"/>'
                '<x:metadata><w:spacing w:line="1200" w:lineRule="auto"/></x:metadata>'
                '<w:jc w:val="right"/><w:keepNext/>',
          ),
        );
        native.applyStep(document, _step(rule: rule, points: 21.25));
        var saved = WordSerializer().writeBytes(document);
        for (var cycle = 0; cycle < 3; cycle++) {
          final properties = _properties(saved);
          final spacing = _spacing(saved);
          expect(_val(spacing, 'line'), '425');
          expect(_val(spacing, 'lineRule'), nativeRule.name);
          for (final entry in {
            'before': '120',
            'after': '180',
            'beforeLines': '10',
            'afterLines': '20',
            'beforeAutospacing': '1',
            'afterAutospacing': '0',
          }.entries) {
            expect(_val(spacing, entry.key), entry.value);
          }
          expect(spacing.getAttribute('line', namespaceUri: _x), 'opaque-line');
          expect(
            spacing.getAttribute('lineRule', namespaceUri: _x),
            'opaque-rule',
          );
          expect(spacing.getAttribute('token', namespaceUri: _x), 'keep');
          expect(
            spacing
                .firstChild('child', namespaceUri: _x)!
                .getAttribute('val', namespaceUri: _x),
            'keep-child',
          );
          expect(
            properties
                .firstChild('spacing', namespaceUri: _x)!
                .getAttribute('token', namespaceUri: _x),
            'foreign-spacing',
          );
          expect(
            _val(
              properties
                  .firstChild('metadata', namespaceUri: _x)!
                  .firstChild('spacing', namespaceUri: _w)!,
              'line',
            ),
            '1200',
          );
          expect(
            properties.firstChild('keepNext', namespaceUri: _w),
            isNotNull,
          );
          final reopened = _read(saved);
          expect(reopened.paragraphs.single.text, 'Original');
          expect(
            reopened.paragraphs.single.properties.justification,
            WmlJustification.right,
          );
          expect(
            reopened.paragraphs.single.inlines
                .whereType<WmlRun>()
                .single
                .properties
                .italic,
            isTrue,
          );
          saved = WordSerializer().writeBytes(reopened);
        }
      },
    );

    test(
      '$rule same inherited value becomes direct without freezing before/after',
      () {
        final document = _read(
          _fixture(
            properties: '<w:pStyle w:val="Layout"/>',
            styles:
                '<w:style w:type="paragraph" w:styleId="Layout"><w:pPr>'
                '<w:spacing w:before="180" w:after="240" '
                'w:line="360" w:lineRule="${nativeRule.name}"/>'
                '</w:pPr></w:style>',
          ),
        );
        native.applyStep(document, _step(rule: rule));
        final saved = WordSerializer().writeBytes(document);
        final spacing = _spacing(saved);
        expect(_val(spacing, 'before'), isNull);
        expect(_val(spacing, 'after'), isNull);
        expect(_val(spacing, 'line'), '360');
        final package = OpcPackage.openBytes(saved);
        final styles = package.getPart('/word/styles.xml')!;
        styles.writeText(
          styles
              .readText()
              .replaceAll('w:before="180"', 'w:before="400"')
              .replaceAll('w:after="240"', 'w:after="600"')
              .replaceAll('w:line="360"', 'w:line="480"'),
        );
        final reopened = WordDeserializer().read(package);
        final properties = reopened.paragraphs.single.properties;
        expect(properties.lineSpacing, rule == 'multiple' ? 1.5 : 18);
        expect(properties.lineSpacingRule, nativeRule);
        expect(properties.spacingBefore, 20);
        expect(properties.spacingAfter, 30);
        final again = _spacing(WordSerializer().writeBytes(reopened));
        expect(_val(again, 'before'), isNull);
        expect(_val(again, 'after'), isNull);
      },
    );
  }

  test(
    'a prior direct before/after assignment remains direct across line edit',
    () {
      final document = _read(
        _fixture(
          properties: '<w:pStyle w:val="Layout"/>',
          styles:
              '<w:style w:type="paragraph" w:styleId="Layout"><w:pPr>'
              '<w:spacing w:before="180" w:after="240"/>'
              '</w:pPr></w:style>',
        ),
      );
      native.applyStep(document, {
        'op': 'paragraphFormat',
        'paragraph': 0,
        'before': 9,
        'after': 12,
      });
      native.applyStep(document, _step());
      final spacing = _spacing(WordSerializer().writeBytes(document));
      expect(_val(spacing, 'before'), '180');
      expect(_val(spacing, 'after'), '240');
      expect(_val(spacing, 'line'), '360');
    },
  );

  test(
    'alternate native prefixes retain effective and opaque spacing values',
    () {
      final document = _read(
        _fixture(
          prefix: 'q',
          properties:
              '<q:spacing q:before="180" q:after="240" '
              'q:line="480" q:lineRule="auto" x:token="keep"/>'
              '<x:spacing q:line="960" x:token="opaque"/>',
        ),
      );
      native.applyStep(document, _step(points: 19.25));
      var saved = WordSerializer().writeBytes(document);
      for (var cycle = 0; cycle < 3; cycle++) {
        final spacing = _spacing(saved);
        expect(_val(spacing, 'line'), '385');
        expect(_val(spacing, 'before'), '180');
        expect(_val(spacing, 'after'), '240');
        expect(spacing.getAttribute('token', namespaceUri: _x), 'keep');
        final reopened = _read(saved);
        expect(reopened.paragraphs.single.properties.spacingBefore, 9);
        expect(reopened.paragraphs.single.properties.spacingAfter, 12);
        expect(reopened.paragraphs.single.properties.lineSpacing, 19.25);
        saved = WordSerializer().writeBytes(reopened);
      }
    },
  );

  test(
    'alternate style prefixes retain inherited before and after ownership',
    () {
      final document = _read(
        _fixture(
          properties: '<w:pStyle w:val="Layout"/>',
          styles:
              '<q:style xmlns:q="$_w" w:type="paragraph" w:styleId="Layout">'
              '<q:pPr><q:spacing q:before="180" q:after="240" '
              'q:line="360" q:lineRule="exact" x:before="opaque"/>'
              '</q:pPr></q:style>',
        ),
      );
      expect(document.paragraphs.single.properties.spacingBefore, 9);
      expect(document.paragraphs.single.properties.spacingAfter, 12);
      native.applyStep(document, _step());
      final saved = WordSerializer().writeBytes(document);
      expect(_val(_spacing(saved), 'before'), isNull);
      expect(_val(_spacing(saved), 'after'), isNull);
      final package = OpcPackage.openBytes(saved);
      final styles = package.getPart('/word/styles.xml')!;
      final source = styles.readText();
      expect(source, contains('x:before="opaque"'));
      styles.writeText(
        source
            .replaceAll('q:before="180"', 'q:before="400"')
            .replaceAll('q:after="240"', 'q:after="600"')
            .replaceAll('q:line="360"', 'q:line="480"'),
      );
      final restored = WordDeserializer().read(package);
      expect(restored.paragraphs.single.properties.spacingBefore, 20);
      expect(restored.paragraphs.single.properties.spacingAfter, 30);
      expect(restored.paragraphs.single.properties.lineSpacing, 18);
    },
  );

  for (final (rule, points, expectedPitch) in [
    ('exact', 18.0, 18.0),
    ('atLeast', 8.0, 13.798828125),
    ('atLeast', 20.0, 20.0),
    ('multiple', 18.0, 20.6982421875),
  ]) {
    test('$rule $points points reaches saved native line-box layout', () {
      final font = SfntFont.parse(
        File(
          '../quds_office_editor/fonts/LiberationSans-Regular.ttf',
        ).readAsBytesSync(),
      );
      final document = _read(
        _fixture(
          body:
              '<w:p><w:r><w:rPr><w:rFonts w:ascii="Arial"/>'
              '<w:sz w:val="24"/></w:rPr><w:t>First line</w:t>'
              '<w:br/><w:t>Second line</w:t><w:br/><w:t>Third line</w:t>'
              '</w:r></w:p>',
        ),
      );
      native.applyStep(document, _step(rule: rule, points: points));
      final restored = _read(WordSerializer().writeBytes(document));
      final laidOut = WordLayoutEngine(
        font: null,
        measureFont: (_, size, _) =>
            FontMetrics(font: font, fontSizePoints: size),
      ).layout(restored);
      expect(laidOut.pages, hasLength(1));
      final lines = laidOut.pages.single.lines;
      expect(lines, hasLength(3));
      expect(lines[1].y - lines[0].y, closeTo(expectedPitch, 0.0001));
      expect(lines[2].y - lines[1].y, closeTo(expectedPitch, 0.0001));
    });
  }

  test('native explicit header selection changes only that story', () {
    final document = _read(_fixture());
    final bodyProperties = document.paragraphs.single.properties;
    document.sections.single.header.add(
      WmlParagraph(inlines: [WmlRun(text: 'Header')]),
    );
    native.applyStep(document, {
      ..._step(rule: 'multiple', points: 30),
      'story': 'header',
      'section': 0,
    });
    expect(
      identical(document.paragraphs.single.properties, bodyProperties),
      isTrue,
    );
    expect(document.sections.single.header.single.properties.lineSpacing, 2.5);
    expect(
      document.sections.single.header.single.properties.lineSpacingRule,
      WmlLineSpacingRule.auto,
    );
  });

  for (final multiple in [1.0, 1.5, 2.0]) {
    final preset = <String, Object?>{
      'op': 'paragraphFormat',
      'paragraph': 0,
      'lineSpacing': multiple,
      'lineSpacingRule': 'auto',
    };
    for (final (name, source) in [
      (
        'duplicate spacing',
        '<w:spacing w:line="240"/><w:spacing w:line="480"/>',
      ),
      (
        'native alternative',
        '<mc:AlternateContent><mc:Choice Requires="x">'
            '<w:spacing w:line="480"/></mc:Choice>'
            '<mc:Fallback><w:spacing w:line="240"/></mc:Fallback></mc:AlternateContent>',
      ),
      (
        'foreign alternative',
        '<mc:AlternateContent><mc:Choice Requires="x">'
            '<x:spacing x:token="opaque"/></mc:Choice><mc:Fallback/></mc:AlternateContent>',
      ),
    ]) {
      test(
        'preset $multiple refuses $name before changing source ownership',
        () {
          _refuses(_read(_fixture(properties: source)), {
            ...preset,
            'before': 17,
          });
        },
      );
    }
    test('preset $multiple refuses unbalanced fields in another story', () {
      final document = _read(_fixture());
      document.sections.single.header.add(
        WmlParagraph(
          inlines: [WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin)],
        ),
      );
      _refuses(document, preset);
    });
    test(
      'preset $multiple preserves native metadata and reopens at its actual value',
      () {
        final document = _read(
          _fixture(
            properties:
                '<w:spacing w:before="120" w:after="180" w:line="300" '
                'w:lineRule="exact" w:beforeLines="10" w:afterAutospacing="1" '
                'x:line="opaque-line" x:token="keep"/>'
                '<x:spacing w:line="960" x:token="foreign"/>',
          ),
        );
        native.applyStep(document, preset);
        var saved = WordSerializer().writeBytes(document);
        for (var cycle = 0; cycle < 3; cycle++) {
          final spacing = _spacing(saved);
          expect(_val(spacing, 'line'), '${(multiple * 240).round()}');
          expect(_val(spacing, 'lineRule'), 'auto');
          expect(_val(spacing, 'before'), '120');
          expect(_val(spacing, 'after'), '180');
          expect(_val(spacing, 'beforeLines'), '10');
          expect(_val(spacing, 'afterAutospacing'), '1');
          expect(spacing.getAttribute('line', namespaceUri: _x), 'opaque-line');
          expect(spacing.getAttribute('token', namespaceUri: _x), 'keep');
          expect(
            _properties(saved)
                .firstChild('spacing', namespaceUri: _x)!
                .getAttribute('token', namespaceUri: _x),
            'foreign',
          );
          final restored = _read(saved);
          expect(restored.paragraphs.single.properties.lineSpacing, multiple);
          expect(
            restored.paragraphs.single.properties.lineSpacingRule,
            WmlLineSpacingRule.auto,
          );
          saved = WordSerializer().writeBytes(restored);
        }
      },
    );
  }

  for (final entry in <String, Object>{
    'lineSpacing': 1.5,
    'lineSpacingRule': 'exact',
  }.entries) {
    test('a lone ${entry.key} native write also refuses duplicate spacing', () {
      _refuses(
        _read(
          _fixture(
            properties: '<w:spacing w:line="240"/><w:spacing w:line="480"/>',
          ),
        ),
        {'op': 'paragraphFormat', 'paragraph': 0, entry.key: entry.value},
      );
    });
  }

  for (final operation in [
    _step(),
    <String, Object?>{
      'op': 'paragraphFormat',
      'paragraph': 0,
      'lineSpacing': 1.5,
      'lineSpacingRule': 'auto',
    },
  ]) {
    for (final (name, input) in <(String, Uint8List)>[
      (
        'within direct properties',
        _fixture(
          properties:
              '<mc:AlternateContent><mc:Choice Requires="x">'
              '<x:metadata x:val="retain-choice"/></mc:Choice>'
              '<mc:Fallback><x:metadata x:val="retain-fallback"/></mc:Fallback>'
              '</mc:AlternateContent>',
        ),
      ),
      (
        'within a property extension',
        _fixture(
          properties:
              '<x:extension><mc:AlternateContent><mc:Choice Requires="x">'
              '<x:metadata x:val="retain-choice"/></mc:Choice>'
              '<mc:Fallback/></mc:AlternateContent></x:extension>',
        ),
      ),
      (
        'around direct properties',
        _fixture(
          body:
              '<w:p><mc:AlternateContent><mc:Choice Requires="x">'
              '<w:pPr><x:metadata x:val="retain-choice"/></w:pPr></mc:Choice>'
              '<mc:Fallback><w:pPr><x:metadata x:val="retain-fallback"/></w:pPr>'
              '</mc:Fallback></mc:AlternateContent><w:r><w:t>Original</w:t></w:r></w:p>',
        ),
      ),
      (
        'around a style property packet',
        _fixture(
          styles:
              '<mc:AlternateContent><mc:Choice Requires="x">'
              '<w:style w:type="paragraph" w:styleId="Choice"><w:pPr>'
              '<x:metadata x:val="retain-choice"/></w:pPr></w:style></mc:Choice>'
              '<mc:Fallback/></mc:AlternateContent>',
        ),
      ),
    ]) {
      test('${operation['op']} refuses nonspacing alternatives $name', () {
        _refuses(_read(input), operation);
      });
    }
  }

  for (final value in <Object?>[
    null,
    true,
    '18',
    -1,
    0,
    0.01,
    0.049,
    1.001,
    107374182.4,
    double.nan,
    double.infinity,
    double.negativeInfinity,
  ]) {
    test('invalid native point value $value refuses before mutation', () {
      _refuses(_read(_fixture()), {
        ..._step(),
        'points': value,
      }, matcher: throwsArgumentError);
    });
  }
  for (final value in <Object?>[
    null,
    true,
    4,
    '',
    'auto',
    'Exactly',
    'single',
  ]) {
    test('invalid native rule $value refuses before mutation', () {
      _refuses(_read(_fixture()), {
        ..._step(),
        'rule': value,
      }, matcher: throwsArgumentError);
    });
  }
  for (final entry in <String, Object?>{
    'unknown': 1,
    'paragraph': 4,
    'story': 'missing',
  }.entries) {
    test(
      'invalid native selector or field ${entry.key} refuses before mutation',
      () {
        _refuses(_read(_fixture()), {
          ..._step(),
          entry.key: entry.value,
        }, matcher: throwsArgumentError);
      },
    );
  }

  for (final (name, input) in <(String, Uint8List)>[
    (
      'duplicate direct spacing',
      _fixture(
        properties: '<w:spacing w:line="240"/><w:spacing w:line="480"/>',
      ),
    ),
    (
      'duplicate style spacing',
      _fixture(
        styles:
            '<w:style w:type="paragraph" w:styleId="Bad"><w:pPr><w:spacing/><w:spacing/></w:pPr></w:style>',
      ),
    ),
    (
      'duplicate paragraph properties',
      _fixture(
        body:
            '<w:p><w:pPr/><w:pPr><w:spacing w:line="240"/></w:pPr><w:r><w:t>Original</w:t></w:r></w:p>',
      ),
    ),
    (
      'duplicate native line attributes',
      _fixture(
        properties: '<w:spacing xmlns:q="$_w" w:line="240" q:line="480"/>',
      ),
    ),
    (
      'duplicate native rule attributes',
      _fixture(
        properties:
            '<w:spacing xmlns:q="$_w" w:lineRule="auto" q:lineRule="exact"/>',
      ),
    ),
    (
      'alternative direct spacing',
      _fixture(
        properties:
            '<mc:AlternateContent><mc:Choice Requires="x"><w:spacing w:line="480"/></mc:Choice><mc:Fallback><w:spacing w:line="240"/></mc:Fallback></mc:AlternateContent>',
      ),
    ),
    (
      'alternative whole style',
      _fixture(
        styles:
            '<mc:AlternateContent><mc:Choice Requires="x"><w:style w:type="paragraph" w:styleId="Alternative"><w:pPr><w:spacing w:line="480"/></w:pPr></w:style></mc:Choice><mc:Fallback/></mc:AlternateContent>',
      ),
    ),
  ]) {
    test('$name refuses without any native mutation', () {
      _refuses(_read(input), _step());
    });
  }

  test('spacing in a stored non-body alternative causes conservative refusal', () {
    final document = _read(_fixture());
    document.package!.createPart(
      '/word/comments.xml',
      OfficeContentTypes.wordComments,
      utf8.encode(
        '<w:comments xmlns:w="$_w" xmlns:x="$_x" xmlns:mc="${OfficeNamespaces.mc}">'
        '<mc:AlternateContent><mc:Choice Requires="x"><w:comment w:id="7">'
        '<w:p><w:pPr><w:spacing w:line="240"/></w:pPr></w:p>'
        '</w:comment></mc:Choice><mc:Fallback/></mc:AlternateContent></w:comments>',
      ),
    );
    _refuses(document, _step());
  });

  test('foreign spacing in an alternative refuses before opaque branch loss', () {
    final document = _read(
      _fixture(
        properties:
            '<mc:AlternateContent><mc:Choice Requires="x">'
            '<x:spacing x:token="opaque"/></mc:Choice><mc:Fallback/></mc:AlternateContent>',
      ),
    );
    _refuses(document, _step());
  });

  test(
    'balanced native fields survive line edits and unrelated unbalanced fields refuse',
    () {
      final input = _fixture(
        body:
            '<w:p><w:r><w:fldChar w:fldCharType="begin"/></w:r>'
            '<w:r><w:instrText xml:space="preserve"> PAGE </w:instrText></w:r>'
            '<w:r><w:fldChar w:fldCharType="separate"/></w:r>'
            '<w:r><w:t>1</w:t></w:r><w:r><w:fldChar w:fldCharType="end"/></w:r></w:p>',
      );
      final document = _read(input);
      native.applyStep(document, _step());
      final saved = WordSerializer().writeBytes(document);
      final xml = OpcPackage.openBytes(
        saved,
      ).getPart('/word/document.xml')!.readText();
      for (final token in [
        'fldCharType="begin"',
        ' PAGE ',
        'fldCharType="separate"',
        'fldCharType="end"',
      ]) {
        expect(xml, contains(token));
      }
      document.sections.single.header.add(
        WmlParagraph(
          inlines: [WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin)],
        ),
      );
      _refuses(document, _step());
    },
  );

  test(
    'late invalid native line spacing rolls back the complete plan',
    () async {
      final input = _fixture();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      session.startRecording('Rejected spacing');
      final plan = OfficeMacro(
        name: 'Rejected spacing',
        format: OfficeMacroFormat.docx,
        steps: [
          OfficeMacroStep(
            tool: 'docx.lineSpacing',
            arguments: {'paragraph': 0, 'rule': 'exact', 'points': 18},
          ),
          OfficeMacroStep(
            tool: 'docx.lineSpacing',
            arguments: {'paragraph': 0, 'rule': 'multiple', 'points': 0.01},
          ),
        ],
      );
      for (final action in [session.validate, session.run]) {
        await expectLater(
          action(plan),
          throwsA(
            isA<OfficeMacroException>().having(
              (e) => e.stepIndex,
              'stepIndex',
              1,
            ),
          ),
        );
        expect(session.bytes, input);
        expect(session.revision, 0);
      }
      expect(session.stopRecording().steps, isEmpty);
    },
  );
}
