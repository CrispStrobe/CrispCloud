// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

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
