import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/automation/operations/word_steps.dart'
    as native;
import 'package:test/test.dart';

import '../tool/macros/web_vba_word_headers_footers_smoke.dart' as stories;

const _w = OfficeNamespaces.w;
const _x = 'urn:font-color-tests';
const _text = 'Aé😀 العربية';

Uint8List _fixture({
  String run = '',
  String? body,
  String? styles,
  String prefix = 'w',
}) {
  final package = OpcPackage.openBytes(
    (DocxDocumentBuilder()..paragraph('Template')).build(),
  );
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<$prefix:document xmlns:$prefix="$_w" xmlns:x="$_x" '
        'xmlns:mc="${OfficeNamespaces.mc}"'
        '${prefix == 'q' ? ' xmlns:w="urn:foreign-word-prefix"' : ''}>'
        '<$prefix:body>'
        '${body ?? '<$prefix:p><$prefix:r><$prefix:rPr>$run</$prefix:rPr>'
                '<$prefix:t>$_text</$prefix:t></$prefix:r></$prefix:p>'}'
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

WmlRunProps _props(WmlDocument document) =>
    document.paragraphs.single.inlines.whereType<WmlRun>().single.properties;

XmlElement _rPr(Uint8List bytes) =>
    XmlDocument.parse(
          OpcPackage.openBytes(bytes).getPart('/word/document.xml')!.readText(),
        ).root!
        .firstChild('body', namespaceUri: _w)!
        .firstChild('p', namespaceUri: _w)!
        .firstChild('r', namespaceUri: _w)!
        .firstChild('rPr', namespaceUri: _w)!;

XmlElement _color(Uint8List bytes) =>
    _rPr(bytes).firstChild('color', namespaceUri: _w)!;

void _run(WmlDocument document, Map<String, Object?> fields) =>
    native.applyStep(document, {'op': 'runFormat', 'paragraph': 0, ...fields});

void _refuses(
  WmlDocument document,
  Map<String, Object?> fields, {
  Matcher matcher = throwsUnsupportedError,
}) {
  final paragraph = document.paragraphs.single;
  final inlines = paragraph.inlines;
  final runs = inlines.whereType<WmlRun>().toList();
  final before = runs
      .map((run) => WordSerializer().runPropertiesXml(run.properties))
      .toList();
  final text = paragraph.text;
  final package = document.package!;
  final parts = <String, Uint8List>{
    for (final part in package.parts)
      part.uri: package.getPart(part.uri)!.readBytes(),
  };
  expect(() => _run(document, fields), matcher);
  expect(paragraph.inlines, same(inlines));
  expect(paragraph.inlines.whereType<WmlRun>(), orderedEquals(runs));
  expect(paragraph.text, text);
  expect(
    runs.map((run) => WordSerializer().runPropertiesXml(run.properties)),
    before,
  );
  expect(<String, Uint8List>{
    for (final part in package.parts)
      part.uri: package.getPart(part.uri)!.readBytes(),
  }, parts);
}

void main() {
  for (final input in ['auto', '000000', 'FFFFFF', '1a2b3c']) {
    final expected = input == 'auto' ? 'auto' : input.toUpperCase();
    test(
      'native color $input preserves its identity through three reopens',
      () {
        var document = _read(_fixture(run: '<w:i/><w:sz w:val="29"/>'));
        _run(document, {'color': input});
        for (var cycle = 0; cycle < 3; cycle++) {
          final props = _props(document);
          expect(props.color, expected);
          expect(props.copy().color, expected);
          expect(props.italic, isTrue);
          expect(props.fontSizeHalfPoints, 29);
          final bytes = WordSerializer().writeBytes(document);
          expect(_color(bytes).getAttribute('val', namespaceUri: _w), expected);
          document = _read(bytes);
          expect(document.paragraphs.single.text, _text);
        }
      },
    );
  }

  test('authored automatic color emits auto explicitly instead of black', () {
    final document = WmlDocument.empty(text: _text);
    _run(document, {'color': 'auto'});
    var bytes = WordSerializer().writeBytes(document);
    for (var cycle = 0; cycle < 3; cycle++) {
      expect(_color(bytes).getAttribute('val', namespaceUri: _w), 'auto');
      final reopened = _read(bytes);
      expect(_props(reopened).color, 'auto');
      bytes = WordSerializer().writeBytes(reopened);
    }
  });

  test('an imported automatic color survives unrelated formatting', () {
    final document = _read(
      _fixture(run: '<w:color w:val="auto" x:keep="source"/>'),
    );
    expect(_props(document).color, 'auto');
    _run(document, {'bold': true});
    var bytes = WordSerializer().writeBytes(document);
    for (var cycle = 0; cycle < 3; cycle++) {
      expect(_color(bytes).getAttribute('val', namespaceUri: _w), 'auto');
      expect(_color(bytes).getAttribute('keep', namespaceUri: _x), 'source');
      final reopened = _read(bytes);
      expect(_props(reopened).color, 'auto');
      expect(_props(reopened).bold, isTrue);
      bytes = WordSerializer().writeBytes(reopened);
    }
  });

  for (final color in ['123456', 'auto']) {
    test(
      'same inherited $color becomes direct without pinning other properties',
      () {
        final document = _read(
          _fixture(
            run: '<w:rStyle w:val="Character"/>',
            styles:
                '<w:style w:type="character" w:styleId="Character"><w:rPr>'
                '<w:color w:val="$color"/><w:sz w:val="24"/>'
                '</w:rPr></w:style>',
          ),
        );
        expect(_props(document).color, color);
        _run(document, {'color': color});
        final bytes = WordSerializer().writeBytes(document);
        expect(_color(bytes).getAttribute('val', namespaceUri: _w), color);
        expect(_rPr(bytes).firstChild('sz', namespaceUri: _w), isNull);
        final package = OpcPackage.openBytes(bytes);
        final styles = package.getPart('/word/styles.xml')!;
        styles.writeText(
          styles
              .readText()
              .replaceAll('w:val="$color"', 'w:val="AA5500"')
              .replaceAll('w:val="24"', 'w:val="36"'),
        );
        final changed = WordDeserializer().read(package);
        expect(_props(changed).color, color);
        expect(_props(changed).fontSizeHalfPoints, 36);
        expect(
          _color(
            WordSerializer().writeBytes(changed),
          ).getAttribute('val', namespaceUri: _w),
          color,
        );
      },
    );
  }

  for (final color in ['123456', 'auto']) {
    test(
      'explicit $color owns native color and removes all inherited theme selectors',
      () {
        final document = _read(
          _fixture(
            run:
                '<w:color w:val="123456" w:themeColor="accent1" '
                'w:themeTint="80" w:themeShade="40" x:keep="source"/>',
          ),
        );
        _run(document, {'color': color});
        var bytes = WordSerializer().writeBytes(document);
        for (var cycle = 0; cycle < 3; cycle++) {
          final nativeColor = _color(bytes);
          expect(nativeColor.getAttribute('val', namespaceUri: _w), color);
          for (final attribute in ['themeColor', 'themeTint', 'themeShade']) {
            expect(
              nativeColor.getAttribute(attribute, namespaceUri: _w),
              isNull,
            );
          }
          expect(nativeColor.getAttribute('keep', namespaceUri: _x), 'source');
          bytes = WordSerializer().writeBytes(_read(bytes));
        }
      },
    );
  }

  test('unrelated run edits preserve color theme ownership', () {
    final document = _read(
      _fixture(
        run:
            '<w:color w:val="112233" w:themeColor="accent2" '
            'w:themeTint="99" w:themeShade="55"/>',
      ),
    );
    _run(document, {'italic': true});
    final color = _color(WordSerializer().writeBytes(document));
    expect(color.getAttribute('val', namespaceUri: _w), '112233');
    expect(color.getAttribute('themeColor', namespaceUri: _w), 'accent2');
    expect(color.getAttribute('themeTint', namespaceUri: _w), '99');
    expect(color.getAttribute('themeShade', namespaceUri: _w), '55');
  });

  for (final prefix in ['w', 'q']) {
    for (final requested in ['auto', 'A1B2C3']) {
      test(
        '$requested preserves native aliases and foreign color metadata ($prefix)',
        () {
          final document = _read(
            _fixture(
              prefix: prefix,
              run:
                  '<$prefix:color x:val="foreign-value" $prefix:val="123456" '
                  '$prefix:themeColor="accent1" $prefix:themeTint="80" $prefix:themeShade="40" '
                  'x:themeColor="foreign-theme" x:themeTint="foreign-tint" '
                  'x:themeShade="foreign-shade" x:keep="source">'
                  '<x:child><$prefix:color $prefix:val="445566"/></x:child>'
                  '</$prefix:color><x:color $prefix:val="778899"/>'
                  '<x:container><$prefix:color $prefix:val="ABCDEF"/></x:container>'
                  '<$prefix:i/>',
            ),
          );
          _run(document, {'color': requested, 'bold': true});
          var bytes = WordSerializer().writeBytes(document);
          for (var cycle = 0; cycle < 3; cycle++) {
            final direct = _rPr(bytes);
            final color = _color(bytes);
            expect(
              direct.childrenNamed('color', namespaceUri: _w),
              hasLength(1),
            );
            expect(color.getAttribute('val', namespaceUri: _w), requested);
            expect(
              color.getAttribute('val', namespaceUri: _x),
              'foreign-value',
            );
            expect(
              color.getAttribute('themeColor', namespaceUri: _x),
              'foreign-theme',
            );
            expect(
              color.getAttribute('themeTint', namespaceUri: _x),
              'foreign-tint',
            );
            expect(
              color.getAttribute('themeShade', namespaceUri: _x),
              'foreign-shade',
            );
            expect(color.getAttribute('keep', namespaceUri: _x), 'source');
            for (final attribute in ['themeColor', 'themeTint', 'themeShade']) {
              expect(color.getAttribute(attribute, namespaceUri: _w), isNull);
            }
            expect(
              color
                  .firstChild('child', namespaceUri: _x)!
                  .firstChild('color', namespaceUri: _w)!
                  .getAttribute('val', namespaceUri: _w),
              '445566',
            );
            expect(
              direct
                  .firstChild('color', namespaceUri: _x)!
                  .getAttribute('val', namespaceUri: _w),
              '778899',
            );
            expect(
              direct
                  .firstChild('container', namespaceUri: _x)!
                  .firstChild('color', namespaceUri: _w)!
                  .getAttribute('val', namespaceUri: _w),
              'ABCDEF',
            );
            final reopened = _read(bytes);
            expect(_props(reopened).color, requested);
            expect(_props(reopened).bold, isTrue);
            expect(_props(reopened).italic, isTrue);
            bytes = WordSerializer().writeBytes(reopened);
          }
        },
      );
    }
  }

  test(
    'foreign same-name values do not determine imported direct or style color',
    () {
      for (final direct in [false, true]) {
        final property =
            '<w:color x:val="ABCDEF" w:val="123456"/>'
            '<x:color w:val="556677"/><x:container><w:color w:val="8899AA"/></x:container>';
        final document = _read(
          _fixture(
            run: direct ? property : '<w:rStyle w:val="Character"/>',
            styles: direct
                ? null
                : '<w:style w:type="character" w:styleId="Character">'
                      '<w:rPr>$property</w:rPr></w:style>',
          ),
        );
        expect(_props(document).color, '123456');
        _run(document, {'color': 'auto'});
        expect(
          _props(_read(WordSerializer().writeBytes(document))).color,
          'auto',
        );
      }
    },
  );

  test(
    'partial color edits retain UTF-16 boundaries and untouched neighboring colors',
    () {
      final document = _read(_fixture(run: '<w:color w:val="123456"/><w:i/>'));
      _run(document, {'start': 1, 'end': 4, 'color': 'auto'});
      final reopened = _read(WordSerializer().writeBytes(document));
      final runs = reopened.paragraphs.single.inlines
          .whereType<WmlRun>()
          .toList();
      expect(runs.map((run) => run.text), ['A', 'é😀', ' العربية']);
      expect(runs.map((run) => run.properties.color), [
        '123456',
        'auto',
        '123456',
      ]);
      expect(runs.map((run) => run.properties.italic), everyElement(isTrue));
      expect(reopened.paragraphs.single.text, _text);
    },
  );

  test(
    'automatic color targets one independent header without changing the body',
    () {
      final input = stories.wordHeadersFootersInput();
      final document = _read(input);
      final bodyBefore = document.paragraphs
          .map((paragraph) => paragraph.text)
          .toList();
      final target = stories
          .wordHeaderFooterParagraphs(document.sections[0], 'header')
          .first;
      final headerText = target.text;
      native.applyStep(document, {
        'op': 'runFormat',
        'paragraph': 0,
        'story': 'header',
        'section': 0,
        'color': 'auto',
      });
      final reopened = _read(WordSerializer().writeBytes(document));
      final header = stories
          .wordHeaderFooterParagraphs(reopened.sections[0], 'header')
          .first;
      expect(header.text, headerText);
      expect(
        header.inlines.whereType<WmlRun>().map((run) => run.properties.color),
        everyElement('auto'),
      );
      expect(
        reopened.paragraphs.map((paragraph) => paragraph.text),
        bodyBefore,
      );
      expect(
        reopened.paragraphs
            .expand((paragraph) => paragraph.inlines.whereType<WmlRun>())
            .map((run) => run.properties.color),
        isNot(contains('auto')),
      );
    },
  );

  for (final value in <Object?>[
    null,
    true,
    0,
    -16777216,
    '',
    'AUTO',
    'Auto',
    'auto ',
    ' auto',
    '#FFFFFF',
    'FFFFFFF',
    'ZZZZZZ',
    <Object?>[],
  ]) {
    test(
      'invalid native color $value refuses before run splitting or formatting',
      () {
        _refuses(_read(_fixture()), {
          'start': 1,
          'end': 4,
          'bold': true,
          'color': value,
        }, matcher: throwsArgumentError);
      },
    );
  }

  for (final source in [
    '<w:color w:val="123456"/><w:color w:val="654321"/>',
    '<w:color xmlns:q="$_w" w:val="123456" q:val="654321"/>',
    '<w:color xmlns:q="$_w" w:val="123456" w:themeColor="accent1" q:themeColor="accent2"/>',
    '<w:color xmlns:q="$_w" w:val="123456" w:themeTint="80" q:themeTint="40"/>',
    '<w:color xmlns:q="$_w" w:val="123456" w:themeShade="80" q:themeShade="40"/>',
  ]) {
    test(
      'late duplicate native color ownership refuses all affected runs: $source',
      () {
        final document = _read(
          _fixture(
            body:
                '<w:p><w:r><w:t>First</w:t></w:r>'
                '<w:r><w:rPr>$source</w:rPr><w:t>Last</w:t></w:r></w:p>',
          ),
        );
        _refuses(document, {
          'start': 1,
          'end': 8,
          'bold': true,
          'color': 'auto',
        });
      },
    );
  }

  test('duplicate run-property containers cannot hide color ownership', () {
    final document = _read(
      _fixture(
        body:
            '<w:p><w:r><w:t>First</w:t></w:r><w:r>'
            '<w:rPr><w:color w:val="123456"/></w:rPr>'
            '<w:rPr><w:color w:val="654321"/></w:rPr>'
            '<w:t>Last</w:t></w:r></w:p>',
      ),
    );
    _refuses(document, {'color': 'auto', 'bold': true});
  });

  for (final source in [
    '<w:rPr><mc:AlternateContent><mc:Choice Requires="x">'
        '<w:color w:val="123456"/></mc:Choice>'
        '<mc:Fallback><w:color w:val="654321"/></mc:Fallback>'
        '</mc:AlternateContent></w:rPr>',
    '<w:rPr mc:Ignorable="x" mc:ProcessContent="x:container">'
        '<x:container><w:color w:val="123456"/></x:container></w:rPr>',
  ]) {
    test(
      'markup-compatibility color alternatives refuse before mutation: $source',
      () {
        final document = _read(
          _fixture(body: '<w:p><w:r>$source<w:t>Original</w:t></w:r></w:p>'),
        );
        _refuses(document, {
          'start': 1,
          'end': 4,
          'bold': true,
          'color': 'auto',
        });
      },
    );
  }

  for (final validate in [true, false]) {
    for (final lateFailure in ['invalid color', 'missing paragraph']) {
      test(
        'late $lateFailure rolls back color, bytes and recording (validate $validate)',
        () async {
          final input = _fixture(run: '<w:color w:val="123456"/>');
          final session = OfficeMacroSession(
            input,
            format: OfficeMacroFormat.docx,
          );
          session.startRecording('Font color rollback');
          final plan = OfficeMacro(
            name: 'Font color rollback',
            format: OfficeMacroFormat.docx,
            steps: [
              OfficeMacroStep(
                tool: 'docx.runFormat',
                arguments: {'paragraph': 0, 'color': 'auto', 'bold': true},
              ),
              OfficeMacroStep(
                tool: 'docx.runFormat',
                arguments: {
                  'paragraph': lateFailure == 'missing paragraph' ? 99 : 0,
                  'color': lateFailure == 'invalid color' ? 'AUTO' : 'FF0000',
                },
              ),
            ],
          );
          await expectLater(
            validate ? session.validate(plan) : session.run(plan),
            throwsA(
              isA<OfficeMacroException>().having(
                (error) => error.stepIndex,
                'failed step',
                1,
              ),
            ),
          );
          expect(session.bytes, input);
          expect(session.revision, 0);
          expect(session.stopRecording().steps, isEmpty);
        },
      );
    }
  }
}
