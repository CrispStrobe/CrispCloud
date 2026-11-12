import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _a = 'http://schemas.openxmlformats.org/drawingml/2006/main';
const _strictA = 'http://purl.oclc.org/ooxml/drawingml/main';
const _originalLine =
    '<a:ln><a:solidFill><a:srgbClr val="355C7D"/></a:solidFill></a:ln>';

String _line({
  String attributes = '',
  String children = '',
  String namespace = _a,
}) => '<a:ln xmlns:a="$namespace" $attributes>$children</a:ln>';

void _expectFallback(DrawingLineStyle style, {double width = 0.8}) {
  expect(style.widthPoints, width);
  expect(style.dashLengths, isEmpty);
  expect(style.cap, DrawingLineCap.square);
  expect(style.join, DrawingLineJoin.miter);
  expect(style.miterLimit, 4);
  expect(style.inset, isFalse);
}

// Compare native semantics, including unsupported attributes and extension
// payloads, while ignoring redundant namespace declarations/indentation that
// the engine adds when it retains an independently usable XML fragment.
Object _xmlIdentity(XmlElement element) {
  final attributes = <String, String>{};
  for (final attribute in element.attributes) {
    if (attribute.qualifiedName == 'xmlns' || attribute.prefix == 'xmlns') {
      continue;
    }
    attributes['{${attribute.namespaceUri}}${attribute.localName}'] =
        attribute.value;
  }
  return {
    'name': '{${element.namespaceUri}}${element.localName}',
    'attributes': attributes,
    'children': [
      for (final child in element.children)
        if (child is XmlElement)
          _xmlIdentity(child)
        else if (child is XmlText && child.text.trim().isNotEmpty)
          child.text,
    ],
  };
}

Iterable<XmlElement> _elements(XmlElement root) sync* {
  yield root;
  for (final child in root.childElements) {
    yield* _elements(child);
  }
}

WmlFrame _frame(WmlDocument document) =>
    document.sections.single.blocks.whereType<WmlFrame>().single;

void main() {
  test('explicit native widths retain exact point values, including zero', () {
    for (final (native, points) in [
      ('0', 0.0),
      ('6350', 0.5),
      ('12700', 1.0),
      ('38100', 3.0),
      ('50800', 4.0),
    ]) {
      final style = DrawingLineStyle.fromXml(_line(attributes: 'w="$native"'));
      expect(style.widthPoints, points, reason: 'EMU width $native');
    }
  });

  test(
    'omitted/imported and newly authored widths keep their documented fallbacks',
    () {
      _expectFallback(DrawingLineStyle.fromXml(null, fallbackWidth: 0.8));
      _expectFallback(DrawingLineStyle.fromXml('', fallbackWidth: 0.8));
      _expectFallback(DrawingLineStyle.fromXml(_line(), fallbackWidth: 0.8));
      expect(WmlFrame().lineStyle.widthPoints, 1);
      expect(WmlFrame(sourceLinePropertiesXml: '').lineStyle.widthPoints, 0.8);
      expect(
        WmlFrame(sourceLinePropertiesXml: _line()).lineStyle.widthPoints,
        0.8,
      );
    },
  );

  // Fixed native expectations, not values read from the implementation map.
  // ECMA-376 DrawingML dash names; proportions agree with the native importer:
  // https://github.com/LibreOffice/core/blob/master/oox/source/drawingml/lineproperties.cxx
  const presetExpectations = <String, List<double>>{
    'solid': [],
    'dot': [1, 3],
    'dash': [4, 3],
    'dashDot': [4, 3, 1, 3],
    'lgDash': [8, 3],
    'lgDashDot': [8, 3, 1, 3],
    'lgDashDotDot': [8, 3, 1, 3, 1, 3],
    'sysDot': [1, 1],
    'sysDash': [3, 1],
    'sysDashDot': [3, 1, 1, 1],
    'sysDashDotDot': [3, 1, 1, 1, 1, 1],
  };
  for (final preset in presetExpectations.entries) {
    test(
      'native preset ${preset.key} exposes proportions independent of width',
      () {
        for (final width in ['12700', '50800']) {
          final style = DrawingLineStyle.fromXml(
            _line(
              attributes: 'w="$width" cap="rnd"',
              children: '<a:prstDash val="${preset.key}"/>',
            ),
          );
          expect(style.dashLengths, preset.value);
          expect(style.capsIncludedInDash, isTrue);
        }
      },
    );
  }

  test('custom integer and percentage dash lengths are equivalent', () {
    for (final namespace in [_a, _strictA]) {
      final integer = DrawingLineStyle.fromXml(
        _line(
          attributes: 'w="25400" cap="rnd"',
          namespace: namespace,
          children:
              '<a:custDash><a:ds d="250000" sp="50000"/><a:ds d="0" sp="125000"/></a:custDash>',
        ),
      );
      final percentages = DrawingLineStyle.fromXml(
        _line(
          attributes: 'w="25400" cap="rnd"',
          namespace: namespace,
          children:
              '<a:custDash><a:ds d="250%" sp="50%"/><a:ds d="0%" sp="125%"/></a:custDash>',
        ),
      );
      expect(integer.widthPoints, 2);
      expect(integer.dashLengths, [2.5, 0.5, 0, 1.25]);
      expect(percentages.dashLengths, integer.dashLengths);
      expect(integer.capsIncludedInDash, isTrue);
    }
  });

  test('cap semantics distinguish custom square and round caps', () {
    for (final (native, expected, included) in [
      ('flat', DrawingLineCap.flat, false),
      ('rnd', DrawingLineCap.round, true),
      ('sq', DrawingLineCap.square, false),
    ]) {
      final custom = DrawingLineStyle.fromXml(
        _line(
          attributes: 'cap="$native"',
          children: '<a:custDash><a:ds d="200000" sp="100000"/></a:custDash>',
        ),
      );
      expect(custom.cap, expected);
      expect(custom.capsIncludedInDash, included);
      final preset = DrawingLineStyle.fromXml(
        _line(
          attributes: 'cap="$native"',
          children: '<a:prstDash val="dash"/>',
        ),
      );
      expect(preset.cap, expected);
      expect(preset.capsIncludedInDash, isTrue);
    }
  });

  test('native joins, miter ratios and inset alignment stay independent', () {
    final round = DrawingLineStyle.fromXml(
      _line(attributes: 'algn="in"', children: '<a:round/>'),
    );
    expect(round.join, DrawingLineJoin.round);
    expect(round.inset, isTrue);
    final bevel = DrawingLineStyle.fromXml(
      _line(attributes: 'algn="ctr"', children: '<a:bevel/>'),
    );
    expect(bevel.join, DrawingLineJoin.bevel);
    expect(bevel.inset, isFalse);
    for (final native in ['350000', '350%']) {
      final miter = DrawingLineStyle.fromXml(
        _line(children: '<a:miter lim="$native"/>'),
      );
      expect(miter.join, DrawingLineJoin.miter);
      expect(miter.miterLimit, 3.5);
    }
  });

  test(
    'foreign root namespaces and unqualified roots cannot inject styles',
    () {
      for (final source in [
        _line(
          namespace: 'urn:decoy',
          attributes: 'w="50800" cap="rnd"',
          children: '<a:round/>',
        ),
        '<ln w="50800"><round/></ln>',
        '<a:other xmlns:a="$_a" w="50800"/>',
      ]) {
        _expectFallback(DrawingLineStyle.fromXml(source, fallbackWidth: 0.8));
      }
    },
  );

  test(
    'native namespace identity works with alternate prefixes and default namespaces',
    () {
      for (final source in [
        '<drawing:ln xmlns:drawing="$_a" w="38100"><drawing:bevel/></drawing:ln>',
        '<ln xmlns="$_a" w="38100"><bevel/></ln>',
        '<strict:ln xmlns:strict="$_strictA" w="38100"><strict:bevel/></strict:ln>',
      ]) {
        final style = DrawingLineStyle.fromXml(source);
        expect(style.widthPoints, 3);
        expect(style.join, DrawingLineJoin.bevel);
      }
    },
  );

  test(
    'foreign attributes, child decoys and nested styles do not override native properties',
    () {
      final source =
          '''<a:ln xmlns:a="$_a" xmlns:e="urn:decoy" e:w="50800" e:cap="rnd" e:algn="in">
<a:prstDash val="dash"/><a:miter lim="250000"/>
<e:prstDash val="lgDash"/><e:round/><e:custDash><e:ds d="100000" sp="100000"/></e:custDash>
<a:extLst><a:ext uri="urn:decoy"><a:round/><a:prstDash val="dot"/></a:ext></a:extLst>
</a:ln>''';
      final style = DrawingLineStyle.fromXml(source, fallbackWidth: 0.8);
      expect(style.widthPoints, 0.8);
      expect(style.cap, DrawingLineCap.square);
      expect(style.inset, isFalse);
      expect(style.join, DrawingLineJoin.miter);
      expect(style.miterLimit, 2.5);
      expect(style.dashLengths, [4, 3]);
    },
  );

  test('foreign dash-stop attributes cannot supply missing native values', () {
    final style = DrawingLineStyle.fromXml(
      '''<a:ln xmlns:a="$_a" xmlns:e="urn:decoy">
<a:custDash><a:ds e:d="100000" sp="100000"/></a:custDash></a:ln>''',
    );
    expect(style.dashLengths, isEmpty);
  });

  for (final (label, source) in [
    ('unterminated element', '<a:ln xmlns:a="$_a" w="50800">'),
    ('unterminated attribute', '<a:ln xmlns:a="$_a" w="50800'),
    ('attribute without a value', '<a:ln xmlns:a="$_a" w='),
    ('mismatched closing tag', '<a:ln xmlns:a="$_a" w="50800"></a:other>'),
    ('multiple roots', '<other/>${_line(attributes: 'w="50800"')}'),
    ('text outside root', 'not XML${_line(attributes: 'w="50800"')}'),
  ]) {
    test('malformed $label uses the visual fallback without throwing', () {
      _expectFallback(DrawingLineStyle.fromXml(source, fallbackWidth: 0.8));
    });
  }

  test(
    'invalid numeric properties cannot create nonfinite or negative styles',
    () {
      for (final value in ['-1', 'NaN', 'Infinity', '-Infinity', 'invalid']) {
        final style = DrawingLineStyle.fromXml(
          _line(
            attributes: 'w="$value"',
            children:
                '<a:custDash><a:ds d="$value" sp="100000"/></a:custDash><a:miter lim="$value"/>',
          ),
          fallbackWidth: 0.8,
        );
        _expectFallback(style);
      }
      expect(
        DrawingLineStyle.fromXml(
          _line(attributes: 'w="12.5"'),
          fallbackWidth: 0.8,
        ).widthPoints,
        0.8,
      );
    },
  );

  test('empty or degenerate custom patterns use solid fallback as one unit', () {
    for (final children in [
      '<a:custDash/>',
      '<a:custDash><a:ds d="0" sp="0"/></a:custDash>',
      '<a:custDash><a:ds d="100000" sp="100000"/><a:ds d="0" sp="0"/></a:custDash>',
      '<a:custDash><a:ds d="100000"/></a:custDash>',
      '<a:prstDash val="unsupported"/>',
    ]) {
      expect(
        DrawingLineStyle.fromXml(_line(children: children)).dashLengths,
        isEmpty,
      );
    }
    final touching = DrawingLineStyle.fromXml(
      _line(children: '<a:custDash><a:ds d="100000" sp="0"/></a:custDash>'),
    );
    expect(touching.dashLengths, [1, 0]);
  });

  test('native dash views cannot mutate preserved line properties', () {
    for (final children in [
      '<a:prstDash val="dash"/>',
      '<a:custDash><a:ds d="250000" sp="50000"/></a:custDash>',
    ]) {
      final source = _line(children: children);
      final frame = WmlFrame(sourceLinePropertiesXml: source);
      expect(() => frame.lineStyle.dashLengths.add(3), throwsUnsupportedError);
      expect(frame.sourceLinePropertiesXml, source);
    }
  });

  test(
    'source reassignment and cloning cannot reuse a stale parsed outline',
    () {
      final first = _line(
        attributes: 'w="38100" cap="rnd"',
        children: '<a:prstDash val="dash"/><a:round/>',
      );
      final second = _line(
        attributes: 'w="6350" cap="flat" algn="in"',
        children:
            '<a:custDash><a:ds d="200000" sp="50000"/></a:custDash><a:bevel/>',
      );
      final frame = WmlFrame(sourceLinePropertiesXml: first);
      final initial = frame.lineStyle;
      expect(identical(frame.lineStyle, initial), isTrue);
      final clone = WmlClone.frame(frame);
      expect(clone.sourceLinePropertiesXml, first);
      frame.sourceLinePropertiesXml = second;
      expect(frame.lineStyle.widthPoints, 0.5);
      expect(frame.lineStyle.dashLengths, [2, 0.5]);
      expect(frame.lineStyle.join, DrawingLineJoin.bevel);
      expect(frame.lineStyle.inset, isTrue);
      expect(initial.widthPoints, 3);
      expect(initial.dashLengths, [4, 3]);
      expect(clone.lineStyle.widthPoints, 3);
      expect(clone.lineStyle.join, DrawingLineJoin.round);
      frame.sourceLinePropertiesXml = null;
      expect(frame.lineStyle.widthPoints, 1);
      frame.sourceLinePropertiesXml = '';
      expect(frame.lineStyle.widthPoints, 0.8);
      expect(frame.lineStyle.dashLengths, isEmpty);
    },
  );

  const sources = <String, String>{
    'preset':
        '<a:ln xmlns:a="$_a" xmlns:e="urn:line-test" w="38100" cap="rnd" cmpd="dbl" algn="in" e:keep="native"><a:solidFill><a:srgbClr val="355C7D"/></a:solidFill><a:prstDash val="lgDashDot"/><a:miter lim="350000"/><a:headEnd type="triangle"/><a:extLst><a:ext uri="urn:line-test"><e:payload>Preserve this</e:payload></a:ext></a:extLst></a:ln>',
    'custom':
        '<a:ln xmlns:a="$_a" xmlns:e="urn:line-test" w="6350" cap="sq" cmpd="sng" algn="ctr" e:keep="native"><a:solidFill><a:srgbClr val="355C7D"/></a:solidFill><a:custDash><a:ds d="250000" sp="50000"/><a:ds d="0" sp="125000"/></a:custDash><a:bevel/><a:tailEnd type="oval"/><a:extLst><a:ext uri="urn:line-test"><e:payload>Preserve this</e:payload></a:ext></a:extLst></a:ln>',
  };
  for (final asynchronous in [false, true]) {
    for (final sourceLine in sources.entries) {
      test(
        '${asynchronous ? 'isolate' : 'direct'} saves preserve raw ${sourceLine.key} properties through three real edits',
        () async {
          final authored = File(
            'test/fixtures/fidelity/frame_wrap_source.xml',
          ).readAsStringSync();
          expect(_originalLine.allMatches(authored), hasLength(1));
          final package = OpcPackage.create(OpcPackageKind.word);
          package
              .getPart('/word/document.xml')!
              .writeText(
                authored.replaceFirst(_originalLine, sourceLine.value),
              );
          var document = WordDeserializer().read(package);
          final expected = _xmlIdentity(
            XmlDocument.parse(sourceLine.value).root!,
          );
          for (var cycle = 1; cycle <= 3; cycle++) {
            final frame = _frame(document);
            final retained = frame.sourceLinePropertiesXml;
            final style = frame.lineStyle;
            expect(style.widthPoints, sourceLine.key == 'preset' ? 3 : 0.5);
            expect(
              style.dashLengths,
              sourceLine.key == 'preset' ? [8, 3, 1, 3] : [2.5, 0.5, 0, 1.25],
            );
            expect(
              frame.sourceLinePropertiesXml,
              retained,
              reason: 'Reading the preview view must not normalize source XML',
            );
            frame.blocks
                    .whereType<WmlParagraph>()
                    .first
                    .inlines
                    .whereType<WmlRun>()
                    .first
                    .text =
                'Edited frame $cycle';
            document.sections.single.blocks
                    .whereType<WmlParagraph>()
                    .last
                    .inlines
                    .whereType<WmlRun>()
                    .first
                    .text =
                'Edited body $cycle';
            final frameIndex = document.sections.single.blocks.indexOf(frame);
            document.sections.single.blocks[frameIndex] = WmlClone.frame(frame);
            final saved = asynchronous
                ? await OfficeIsolateSave.word(document)
                : WordSerializer().writeBytes(document);
            final reopened = OpcPackage.openBytes(saved);
            final savedXml = reopened.getPart('/word/document.xml')!.readText();
            // These literal payload expectations do not ask the engine's XML
            // parser to decide which original metadata should have survived.
            expect(savedXml, contains('e:keep="native"'));
            expect(savedXml, contains('<e:payload>Preserve this</e:payload>'));
            final body = XmlDocument.parse(savedXml).root!;
            final nativeLine = _elements(body)
                .where(
                  (element) =>
                      element.localName == 'ln' && element.namespaceUri == _a,
                )
                .single;
            expect(
              _xmlIdentity(nativeLine),
              expected,
              reason:
                  'Unedited native line properties, including unsupported payloads, must survive cycle $cycle',
            );
            expect(body.text, contains('Edited frame $cycle'));
            expect(body.text, contains('Edited body $cycle'));
            document = WordDeserializer().read(reopened);
            expect(
              _xmlIdentity(
                XmlDocument.parse(
                  _frame(document).sourceLinePropertiesXml!,
                ).root!,
              ),
              expected,
            );
          }
        },
      );
    }
  }
}
