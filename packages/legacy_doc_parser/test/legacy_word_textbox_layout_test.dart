// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/officeart_shape_fixture.dart';

const _v = 'urn:schemas-microsoft-com:vml';
const _w10 = 'urn:schemas-microsoft-com:office:word';

LegacyWordParagraph _paragraph(int start, String text) => LegacyWordParagraph(
  startCp: start,
  endCp: start + text.length + 1,
  runs: [LegacyWordRun(startCp: start, endCp: start + text.length, text: text)],
);

XmlDocument _convert(
  LegacyWordOfficeArtText? layout, {
  int wrap = 3,
  int? groupProperties,
  LegacyWordOfficeArtWrapDistances? distances,
  LegacyWordOfficeArtFill? fill,
  LegacyWordOfficeArtLine? line,
  LegacyWordOfficeArtShadow? shadow,
  LegacyWordOfficeArtPosition? position,
  int shapeType = 202,
  int sourceFlags = 0,
  int rotation = 0,
  bool flip = false,
  List<int> unsupported = const [],
}) {
  final paragraph = _paragraph(10, 'One editable story');
  final result = convertLegacyWordDocument(
    LegacyWordDocument(
      blocks: [_paragraph(0, 'Body')],
      sections: const [],
      plainText: 'Body',
      safeHtml: '',
      stories: [
        LegacyWordStory(
          id: 'box',
          kind: LegacyWordStoryKind.textbox,
          startCp: 10,
          endCp: paragraph.endCp,
          blocks: [paragraph],
          plainText: 'One editable story',
          safeHtml: '',
        ),
      ],
      textboxReferences: const [
        LegacyWordTextboxReference(
          id: 1,
          storyId: 'box',
          inHeaderFooter: false,
          shapeId: 42,
          anchorCp: 1,
        ),
      ],
      media: LegacyWordMediaCatalog.from(
        drawings: [
          LegacyWordDrawing(
            shapeId: 42,
            anchorCp: 1,
            headerStory: false,
            leftTwips: 1440,
            topTwips: 1440,
            rightTwips: 4320,
            bottomTwips: 2880,
            horizontalOrigin: 1,
            verticalOrigin: 1,
            wrapMode: wrap,
            wrapSide: 2,
            behindText: false,
            anchorLocked: false,
            textboxId: 0x10000,
            shape: LegacyWordOfficeArtShape(
              type: shapeType,
              sourceFlags: sourceFlags,
              rotationFixed16: rotation,
              flipHorizontal: flip,
              text: layout,
              wrapDistances: distances,
              fill: fill,
              line: line,
              shadow: shadow,
              position: position,
              unsupportedProperties: unsupported,
              groupShapeBooleanProperties: groupProperties,
            ),
            source: const LegacyWordSourceReference(
              streamPath: '0Table',
              offset: 0,
              length: 26,
              structure: 'FSPA',
            ),
          ),
        ],
      ),
    ),
  );
  final archive = ZipDecoder().decodeBytes(result.bytes);
  return XmlDocument.parse(
    utf8.decode(archive.findFile('word/document.xml')!.content),
  );
}

void main() {
  test(
    'textbox scaled gradient retains both colors, alpha and signed focus',
    () {
      final xml = _convert(
        null,
        fill: const LegacyWordOfficeArtFill(
          type: 7,
          color: '112233',
          backColor: '445566',
          opacityFixed16: 0,
          backOpacityFixed16: 32768,
          angleFixed16: -45 * 65536,
          focusPercent: -50,
          rotateWithShape: false,
        ),
      );
      final rect = xml.findAllElements('rect', namespace: _v).single;
      final fill = rect.findElements('fill', namespace: _v).single;
      expect(rect.getAttribute('fillcolor'), '#112233');
      expect(fill.getAttribute('type'), 'gradient');
      expect(fill.getAttribute('color2'), '#445566');
      expect(fill.getAttribute('opacity'), '0.0');
      expect(
        fill.getAttribute(
          'opacity2',
          namespace: 'urn:schemas-microsoft-com:office:office',
        ),
        '0.5',
      );
      expect(fill.getAttribute('angle'), '-45.0');
      expect(fill.getAttribute('focus'), '-50%');
      expect(fill.getAttribute('rotate'), 'f');
      final unresolved = _convert(
        null,
        fill: const LegacyWordOfficeArtFill(type: 7, backColor: '445566'),
        unsupported: [0x0197],
      );
      expect(unresolved.findAllElements('fill', namespace: _v), isEmpty);
    },
  );

  test(
    'textbox paint retains independently resolved opacity, line and shadow',
    () {
      final xml = _convert(
        null,
        fill: const LegacyWordOfficeArtFill(
          color: '336699',
          opacityFixed16: 32768,
        ),
        line: const LegacyWordOfficeArtLine(
          color: '993366',
          widthEmu: 25400,
          opacityFixed16: 16384,
          dash: 4,
          join: 1,
          cap: 0,
        ),
        shadow: const LegacyWordOfficeArtShadow(
          enabled: true,
          color: '112233',
          opacityFixed16: 49152,
          offsetXEmu: -38100,
          offsetYEmu: 63500,
          obscured: false,
        ),
      );
      final box = xml.findAllElements('rect', namespace: _v).single;
      expect(box.getAttribute('fillcolor'), '#336699');
      expect(box.getAttribute('strokecolor'), '#993366');
      expect(box.getAttribute('strokeweight'), '2.0pt');
      expect(
        box.findElements('fill', namespace: _v).single.getAttribute('opacity'),
        '0.5',
      );
      final stroke = box.findElements('stroke', namespace: _v).single;
      expect(stroke.getAttribute('opacity'), '0.25');
      expect(stroke.getAttribute('dashstyle'), 'shortdashdotdot');
      expect(stroke.getAttribute('joinstyle'), 'miter');
      expect(stroke.getAttribute('endcap'), 'round');
      final shadow = box.findElements('shadow', namespace: _v).single;
      expect(shadow.getAttribute('on'), 't');
      expect(shadow.getAttribute('type'), 'single');
      expect(shadow.getAttribute('color'), '#112233');
      expect(shadow.getAttribute('opacity'), '0.75');
      expect(shadow.getAttribute('offset'), '-3.0pt,5.0pt');
      expect(shadow.getAttribute('obscured'), 'f');
      expect(xml.toXmlString(), contains('One editable story'));
    },
  );

  test('textbox zero opacity and disabled shadow remain explicit', () {
    final xml = _convert(
      null,
      fill: const LegacyWordOfficeArtFill(opacityFixed16: 0),
      line: const LegacyWordOfficeArtLine(enabled: false, opacityFixed16: 0),
      shadow: const LegacyWordOfficeArtShadow(
        enabled: false,
        offsetXEmu: 0,
        offsetYEmu: 0,
        opacityFixed16: 0,
      ),
    );
    final box = xml.findAllElements('rect', namespace: _v).single;
    expect(box.getAttribute('stroked'), 'f');
    for (final element in ['fill', 'stroke', 'shadow']) {
      expect(
        box.findElements(element, namespace: _v).single.getAttribute('opacity'),
        '0.0',
      );
    }
    final shadow = box.findElements('shadow', namespace: _v).single;
    expect(shadow.getAttribute('on'), 'f');
    expect(shadow.getAttribute('offset'), '0.0pt,0.0pt');
    final absent = _convert(null);
    expect(absent.findAllElements('fill', namespace: _v), isEmpty);
    expect(absent.findAllElements('stroke', namespace: _v), isEmpty);
    expect(absent.findAllElements('shadow', namespace: _v), isEmpty);
  });

  test(
    'unresolved textbox paint does not suppress another resolved component',
    () {
      for (final unsupported in [0x0186, 0x01d5, 0x0207]) {
        final xml = _convert(
          null,
          fill: const LegacyWordOfficeArtFill(opacityFixed16: 32768),
          line: const LegacyWordOfficeArtLine(dash: 1),
          shadow: const LegacyWordOfficeArtShadow(enabled: true),
          unsupported: [unsupported],
        );
        final box = xml.findAllElements('rect', namespace: _v).single;
        for (final (name, first, last) in [
          ('fill', 0x0180, 0x01bf),
          ('stroke', 0x01c0, 0x01ff),
          ('shadow', 0x0200, 0x023f),
        ]) {
          expect(
            box.findElements(name, namespace: _v),
            hasLength(unsupported >= first && unsupported <= last ? 0 : 1),
          );
        }
        expect(xml.toXmlString(), contains('One editable story'));
      }
      final unknownTypes = _convert(
        null,
        fill: const LegacyWordOfficeArtFill(type: 2, opacityFixed16: 32768),
        line: const LegacyWordOfficeArtLine(compoundStyle: 1),
        shadow: const LegacyWordOfficeArtShadow(enabled: true, type: 2),
      );
      expect(unknownTypes.findAllElements('fill', namespace: _v), isEmpty);
      expect(unknownTypes.findAllElements('stroke', namespace: _v), isEmpty);
      expect(unknownTypes.findAllElements('shadow', namespace: _v), isEmpty);
    },
  );

  test('simple explicit borders convert the inner anchor to outer frame', () {
    // Literal source widths and expected outer coordinates, in twips. These
    // include even/odd widths, zero, hairline, and a fractional-twip boundary.
    for (final (width, outside) in [
      (0, 0),
      (635, 0),
      (1270, 1),
      (6350, 5),
      (9525, 7),
      (12700, 10),
      (29845, 23),
      (38100, 30),
      (10000, 0),
    ]) {
      final box = _convert(
        const LegacyWordOfficeArtText(insetLeftEmu: 25400),
        line: LegacyWordOfficeArtLine(widthEmu: width, compoundStyle: 0),
      ).findAllElements('rect', namespace: _v).single;
      expect(
        box.getAttribute('style'),
        contains(
          'margin-left:${(1440 - outside) / 20}pt;'
          'margin-top:${(1440 - outside) / 20}pt;'
          'width:${(2880 + 2 * outside) / 20}pt;'
          'height:${(1440 + 2 * outside) / 20}pt;',
        ),
      );
      expect(
        box.findElements('textbox', namespace: _v).single.getAttribute('inset'),
        '2.0pt,3.6pt,7.2pt,3.6pt',
      );
    }
  });

  test('frame conversion is restricted to resolved simple textbox borders', () {
    final outputs = [
      _convert(
        null,
        line: const LegacyWordOfficeArtLine(widthEmu: 9525, enabled: false),
      ),
      _convert(
        null,
        line: const LegacyWordOfficeArtLine(widthEmu: 9525, compoundStyle: 1),
      ),
      _convert(
        null,
        line: const LegacyWordOfficeArtLine(widthEmu: 9525),
        shadow: const LegacyWordOfficeArtShadow(enabled: true, type: 2),
      ),
      _convert(
        null,
        line: const LegacyWordOfficeArtLine(widthEmu: 9525),
        shapeType: 1,
      ),
      _convert(
        null,
        line: const LegacyWordOfficeArtLine(widthEmu: 9525),
        sourceFlags: 2,
      ),
      _convert(
        null,
        line: const LegacyWordOfficeArtLine(widthEmu: 9525),
        rotation: 65536,
      ),
      _convert(
        null,
        line: const LegacyWordOfficeArtLine(widthEmu: 9525),
        flip: true,
      ),
      _convert(
        null,
        line: const LegacyWordOfficeArtLine(widthEmu: 9525),
        unsupported: const [0x01ff],
      ),
      _convert(
        null,
        line: const LegacyWordOfficeArtLine(widthEmu: 9525),
        position: const LegacyWordOfficeArtPosition(horizontalMode: 2),
      ),
      _convert(
        null,
        line: const LegacyWordOfficeArtLine(widthEmu: 9525),
        position: const LegacyWordOfficeArtPosition(verticalMode: 1),
      ),
      _convert(
        const LegacyWordOfficeArtText(autoTextMargin: true),
        line: const LegacyWordOfficeArtLine(widthEmu: 9525),
      ),
      _convert(
        const LegacyWordOfficeArtText(insetLeftEmu: -635),
        line: const LegacyWordOfficeArtLine(widthEmu: 9525),
      ),
    ];
    for (final xml in outputs) {
      expect(
        xml.findAllElements('rect', namespace: _v).single.getAttribute('style'),
        contains(
          'margin-left:72.0pt;margin-top:72.0pt;width:144.0pt;height:72.0pt;',
        ),
      );
    }
  });

  test('simple dashed borders and offset shadows share the outside frame', () {
    for (final dash in [0, 1, 2, 6, 10]) {
      for (final enabled in [null, false, true]) {
        final box = _convert(
          null,
          line: LegacyWordOfficeArtLine(widthEmu: 25400, dash: dash),
          shadow: LegacyWordOfficeArtShadow(
            enabled: enabled,
            type: 0,
            offsetXEmu: -25400,
            offsetYEmu: 50800,
          ),
        ).findAllElements('rect', namespace: _v).single;
        expect(
          box.getAttribute('style'),
          contains(
            'margin-left:71.0pt;margin-top:71.0pt;width:146.0pt;height:74.0pt;',
          ),
        );
        expect(box.getAttribute('strokeweight'), '2.0pt');
      }
    }
  });

  test(
    'explicit frame borders retain each source origin without margin guesses',
    () {
      for (var origin = 0; origin < 4; origin++) {
        final box = _convert(
          null,
          line: const LegacyWordOfficeArtLine(widthEmu: 9525),
          position: LegacyWordOfficeArtPosition(
            horizontalRelativeTo: origin,
            verticalRelativeTo: origin,
          ),
        ).findAllElements('rect', namespace: _v).single;
        final style = box.getAttribute('style')!;
        expect(style, contains('margin-left:71.65pt;margin-top:71.65pt;'));
        expect(
          style,
          contains(
            'mso-position-horizontal-relative:${['margin', 'page', 'text', 'char'][origin]};',
          ),
        );
        expect(
          style,
          contains(
            'mso-position-vertical-relative:${['margin', 'page', 'text', 'line'][origin]};',
          ),
        );
      }
    },
  );

  test(
    'simple line style resolves inheritance; compound and malformed values stay unsupported',
    () {
      for (var value = 0; value <= 4; value++) {
        final shape = parseLegacyWordDocument(
          officeArtShapeWordFixture(values: {0x01cd: value}),
        ).media.drawings.single.shape!;
        expect(shape.line!.compoundStyle, value);
        expect(shape.unsupportedProperties.contains(0x01cd), value != 0);
      }
      final inherited = parseLegacyWordDocument(
        officeArtShapeWordFixture(defaults: {0x01cd: 1}, values: {0x01cd: 0}),
      ).media.drawings.single.shape!;
      expect(inherited.line!.compoundStyle, 0);
      expect(inherited.unsupportedProperties, isNot(contains(0x01cd)));
      for (final input in [
        officeArtShapeWordFixture(values: {0x01cd: 5}),
        officeArtShapeWordFixture(values: {0x01cd: 0xffffffff}),
        officeArtShapeWordFixture(complex: {0x01cd: Uint8List(4)}),
      ]) {
        expect(
          parseLegacyWordDocument(
            input,
          ).media.drawings.single.shape!.unsupportedProperties,
          contains(0x01cd),
        );
      }
      expect(
        () => parseLegacyWordDocument(
          officeArtShapeWordFixture(values: {0x41cd: 0}),
        ),
        throwsFormatException,
      );
      final complexLine = parseLegacyWordDocument(
        officeArtShapeWordFixture(
          values: {0x01cb: 9525},
          complex: {0x01ff: Uint8List(4)},
        ),
      ).media.drawings.single.shape!;
      expect(complexLine.unsupportedProperties, contains(0x01ff));
    },
  );

  test(
    'retained header frames keep their literal source anchors and insets',
    () {
      for (final (fixture, right, bottom, targetExtent) in [
        (
          'header-textbox-duplicate-chain',
          4312,
          1872,
          'width:143.95pt;height:21.95pt;',
        ),
        (
          'shared-header-textbox-table',
          5752,
          3592,
          'width:215.95pt;height:107.95pt;',
        ),
      ]) {
        final document = parseLegacyWordDocument(
          File('test/fixtures/word_native/$fixture.doc').readAsBytesSync(),
        );
        for (final drawing in document.media.drawings) {
          expect(
            [
              drawing.leftTwips,
              drawing.topTwips,
              drawing.rightTwips,
              drawing.bottomTwips,
            ],
            [1447, 1447, right, bottom],
          );
          expect(drawing.shape!.line!.widthEmu, 9525);
          expect(drawing.shape!.line!.compoundStyle, 0);
        }
        final package = ZipDecoder().decodeBytes(
          convertLegacyWordDocument(document).bytes,
        );
        var boxes = 0;
        for (final part in package.where(
          (file) => RegExp(r'^word/header\d+\.xml$').hasMatch(file.name),
        )) {
          for (final box in XmlDocument.parse(
            utf8.decode(part.content),
          ).findAllElements('rect', namespace: _v)) {
            boxes++;
            expect(
              box.getAttribute('style'),
              contains('margin-left:72.0pt;margin-top:72.0pt;$targetExtent'),
            );
            expect(box.getAttribute('strokeweight'), '0.75pt');
            expect(
              box
                  .findElements('textbox', namespace: _v)
                  .single
                  .getAttribute('inset'),
              '0.0pt,0.0pt,0.0pt,0.0pt',
            );
          }
        }
        expect(boxes, 2);
      }
    },
  );

  test(
    'qualified enabled absent width couples source default to outer frame',
    () {
      final parsed = parseLegacyWordDocument(
        officeArtShapeWordFixture(type: 202, values: {0x01ff: 0x00080008}),
      ).media.drawings.single.shape!;
      expect(parsed.line!.enabled, isTrue);
      expect(parsed.line!.widthEmu, isNull);
      for (final line in [
        parsed.line,
        const LegacyWordOfficeArtLine(enabled: true, widthEmu: 9525),
        const LegacyWordOfficeArtLine(enabled: true, dash: 1),
      ]) {
        final box = _convert(
          null,
          line: line,
        ).findAllElements('rect', namespace: _v).single;
        expect(box.getAttribute('strokeweight'), '0.75pt');
        expect(
          box.getAttribute('style'),
          contains(
            'margin-left:71.65pt;margin-top:71.65pt;width:144.7pt;height:72.7pt;',
          ),
        );
      }
      expect(parsed.line!.widthEmu, isNull);
    },
  );

  test(
    'textbox default stroke remains unforced while frame semantics are unresolved',
    () {
      for (final xml in [
        _convert(null),
        _convert(null, line: const LegacyWordOfficeArtLine()),
        _convert(
          null,
          line: const LegacyWordOfficeArtLine(enabled: true),
          unsupported: [0x0307],
        ),
        _convert(
          null,
          line: const LegacyWordOfficeArtLine(enabled: true),
          rotation: 65536,
        ),
        _convert(
          null,
          line: const LegacyWordOfficeArtLine(enabled: true),
          position: const LegacyWordOfficeArtPosition(horizontalMode: 1),
        ),
      ]) {
        final box = xml.findAllElements('rect', namespace: _v).single;
        expect(box.getAttribute('strokeweight'), isNull);
        expect(
          box.getAttribute('style'),
          contains(
            'margin-left:72.0pt;margin-top:72.0pt;width:144.0pt;height:72.0pt;',
          ),
        );
      }
    },
  );

  test(
    'explicit zero, hairline and disabled textbox strokes stay distinct',
    () {
      for (final (line, expected, disabled) in [
        (const LegacyWordOfficeArtLine(widthEmu: 0), '0.0pt', false),
        (const LegacyWordOfficeArtLine(widthEmu: 635), '0.05pt', false),
        (const LegacyWordOfficeArtLine(widthEmu: 12700), '1.0pt', false),
        (const LegacyWordOfficeArtLine(enabled: false), null, true),
        (
          const LegacyWordOfficeArtLine(enabled: false, widthEmu: 12700),
          '1.0pt',
          true,
        ),
      ]) {
        final box = _convert(
          null,
          line: line,
        ).findAllElements('rect', namespace: _v).single;
        expect(box.getAttribute('strokeweight'), expected);
        expect(box.getAttribute('stroked') == 'f', disabled);
      }
    },
  );

  test('unsupported line width cannot be relabeled as source default', () {
    for (final bytes in [
      officeArtShapeWordFixture(
        values: {0x01cb: 0xffffffff, 0x01ff: 0x00080008},
      ),
      officeArtShapeWordFixture(
        values: {0x01cb: 0x0132f541, 0x01ff: 0x00080008},
      ),
      officeArtShapeWordFixture(
        values: {0x01ff: 0x00080008},
        complex: {
          0x01cb: Uint8List.fromList([0, 0, 0, 0]),
        },
      ),
    ]) {
      final shape = parseLegacyWordDocument(bytes).media.drawings.single.shape!;
      expect(shape.unsupportedProperties, contains(0x01cb));
      final box = _convert(
        null,
        line: shape.line,
        unsupported: shape.unsupportedProperties,
      ).findAllElements('rect', namespace: _v).single;
      expect(box.getAttribute('strokeweight'), isNull);
    }
  });

  test('caller-built textbox widths respect the documented source range', () {
    for (final width in [-1, 0x0132f541]) {
      expect(
        () => _convert(null, line: LegacyWordOfficeArtLine(widthEmu: width)),
        throwsA(isA<LegacyWordConversionException>()),
      );
    }
    final box = _convert(
      null,
      line: const LegacyWordOfficeArtLine(widthEmu: 0x0132f540),
    ).findAllElements('rect', namespace: _v).single;
    expect(box.getAttribute('strokeweight'), '1584.0pt');
  });

  test('Word14 unspecified strokes stay distinct from explicit widths', () {
    final document = parseLegacyWordDocument(
      File(
        'test/fixtures/word_native/word14-margin-origin.doc',
      ).readAsBytesSync(),
    );
    final drawings = document.media.drawings
        .where((drawing) => drawing.textboxId != null)
        .toList();
    expect(drawings, hasLength(6));
    for (final drawing in drawings) {
      expect(drawing.shape!.line!.enabled, isTrue);
      expect(drawing.shape!.line!.widthEmu, isNull);
      expect(drawing.shape!.unsupportedProperties, isNot(contains(0x01cb)));
    }
    final archive = ZipDecoder().decodeBytes(
      convertLegacyWordDocument(document).bytes,
    );
    final xml = XmlDocument.parse(
      utf8.decode(archive.findFile('word/document.xml')!.content),
    );
    final boxes = xml.findAllElements('rect', namespace: _v).toList();
    expect(boxes, hasLength(6));
    for (var i = 0; i < boxes.length; i++) {
      expect(boxes[i].getAttribute('strokeweight'), isNull);
      expect(
        boxes[i].getAttribute('style'),
        contains('margin-left:${drawings[i].leftTwips / 20}pt;'),
      );
      expect(
        boxes[i].getAttribute('style'),
        contains('margin-top:${drawings[i].topTwips / 20}pt;'),
      );
    }
  });

  test(
    'outer clearance is independent of inner margins and wrapping modes',
    () {
      final xml = _convert(
        const LegacyWordOfficeArtText(insetTopEmu: 12700, wrapMode: 2),
        wrap: 1,
        distances: const LegacyWordOfficeArtWrapDistances(
          leftEmu: 0,
          topEmu: 45720,
          bottomEmu: 25400,
        ),
      );
      final style = xml
          .findAllElements('rect', namespace: _v)
          .single
          .getAttribute('style')!;
      expect(style, contains('mso-wrap-distance-left:0.0pt;'));
      expect(style, contains('mso-wrap-distance-top:3.6pt;'));
      expect(style, contains('mso-wrap-distance-bottom:2.0pt;'));
      expect(style, isNot(contains('mso-wrap-distance-right:')));
      expect(style, contains('mso-wrap-style:none'));
      expect(
        xml
            .findAllElements('textbox', namespace: _v)
            .single
            .getAttribute('inset'),
        '7.2pt,1.0pt,7.2pt,3.6pt',
      );
      expect(
        xml
            .findAllElements('wrap', namespace: _w10)
            .single
            .getAttribute('type'),
        'topAndBottom',
      );
    },
  );

  test('public wrap distance values outside the supported range reject', () {
    for (final value in [-1, 0x80000000]) {
      for (final distance in [
        LegacyWordOfficeArtWrapDistances(leftEmu: value),
        LegacyWordOfficeArtWrapDistances(topEmu: value),
        LegacyWordOfficeArtWrapDistances(rightEmu: value),
        LegacyWordOfficeArtWrapDistances(bottomEmu: value),
      ]) {
        expect(
          () => _convert(null, distances: distance),
          throwsA(isA<LegacyWordConversionException>()),
        );
      }
    }
  });

  test(
    'explicit textbox cell layout is independent of unspecified defaults',
    () {
      for (final (properties, expected) in [
        (null, null),
        (0x00008000, null),
        (0x80000000, 'f'),
        (0x80008000, 't'),
      ]) {
        final box = _convert(
          null,
          groupProperties: properties,
        ).findAllElements('rect', namespace: _v).single;
        expect(
          box.getAttribute(
            'allowincell',
            namespace: 'urn:schemas-microsoft-com:office:office',
          ),
          expected,
        );
      }
    },
  );

  test('absence retains native margins while explicit zero remains zero', () {
    final unspecified = _convert(
      null,
    ).findAllElements('textbox', namespace: _v).single;
    expect(unspecified.getAttribute('inset'), isNull);
    final partial = _convert(
      const LegacyWordOfficeArtText(insetLeftEmu: 0),
    ).findAllElements('textbox', namespace: _v).single;
    expect(partial.getAttribute('inset'), '0.0pt,3.6pt,7.2pt,3.6pt');
    final explicit = _convert(
      const LegacyWordOfficeArtText(
        insetLeftEmu: 12700,
        insetTopEmu: 25400,
        insetRightEmu: 38100,
        insetBottomEmu: 50800,
      ),
    ).findAllElements('textbox', namespace: _v).single;
    expect(explicit.getAttribute('inset'), '1.0pt,2.0pt,3.0pt,4.0pt');
  });

  test('internal wrapping is independent of surrounding document wrapping', () {
    final xml = _convert(
      const LegacyWordOfficeArtText(
        wrapMode: 2,
        anchor: 5,
        fitShapeToText: false,
      ),
      wrap: 1,
    );
    expect(
      xml.findAllElements('rect', namespace: _v).single.getAttribute('style'),
      contains('mso-wrap-style:none'),
    );
    final textbox = xml.findAllElements('textbox', namespace: _v).single;
    expect(
      textbox.getAttribute('style'),
      contains('v-text-anchor:bottom-center'),
    );
    expect(textbox.getAttribute('style'), contains('mso-fit-shape-to-text:f'));
    final wrap = xml.findAllElements('wrap', namespace: _w10).single;
    expect(wrap.getAttribute('type'), 'topAndBottom');
    expect(wrap.getAttribute('side'), 'right');
    expect(wrap.getAttribute('anchorx'), 'page');
    expect(wrap.getAttribute('anchory'), 'page');
  });

  test('vertical flow uses supported Office direction properties', () {
    for (final (flow, expected) in [
      (1, 'layout-flow:vertical;mso-layout-flow-alt:top-to-bottom'),
      (2, 'layout-flow:vertical;mso-layout-flow-alt:bottom-to-top'),
      (3, 'layout-flow:vertical'),
      (4, 'layout-flow:horizontal'),
      (5, 'layout-flow:vertical'),
    ]) {
      final style = _convert(
        LegacyWordOfficeArtText(flow: flow),
      ).findAllElements('textbox', namespace: _v).single.getAttribute('style');
      expect(style, expected);
      expect(style, isNot(contains('mso-rotate')));
    }
  });

  test('all documented anchor positions are retained', () {
    const anchors = [
      'top',
      'middle',
      'bottom',
      'top-center',
      'middle-center',
      'bottom-center',
      'top-baseline',
      'bottom-baseline',
      'top-center-baseline',
      'bottom-center-baseline',
    ];
    for (var i = 0; i < anchors.length; i++) {
      final box = _convert(
        LegacyWordOfficeArtText(anchor: i),
      ).findAllElements('textbox', namespace: _v).single;
      expect(box.getAttribute('style'), 'v-text-anchor:${anchors[i]}');
    }
  });
}
