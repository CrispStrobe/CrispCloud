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
  LegacyWordOfficeArtLine? line,
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
              type: 202,
              text: layout,
              wrapDistances: distances,
              line: line,
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
    'textbox default stroke remains unforced while frame semantics are unresolved',
    () {
      for (final line in [null, const LegacyWordOfficeArtLine(enabled: true)]) {
        final box = _convert(
          null,
          line: line,
        ).findAllElements('rect', namespace: _v).single;
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
      officeArtShapeWordFixture(values: {0x01cb: 0xffffffff}),
      officeArtShapeWordFixture(values: {0x01cb: 0x0132f541}),
      officeArtShapeWordFixture(
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
