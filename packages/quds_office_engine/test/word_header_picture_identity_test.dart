import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

// Valid red and blue one-pixel PNGs have the same encoded length. Neither
// dimensions nor byte count establishes picture identity.
final _red = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP4z8DwHwAFAAH/VscvDQAAAABJRU5ErkJggg==',
);
final _blue = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNgYPj/HwADAgH/OSkZvgAAAABJRU5ErkJggg==',
);

OfficeVisual _picture(Uint8List bytes, {double x = 0, double y = 0}) =>
    OfficeVisual(
      kind: OfficeVisualKind.picture,
      imageBytes: bytes,
      width: 40,
      height: 24,
      offsetX: x,
      offsetY: y,
    );

WmlParagraph _paragraph(String text) =>
    WmlParagraph(inlines: [WmlRun(text: text)]);

WmlSection _section({
  OfficeVisual? inline,
  List<OfficeVisual> anchored = const [],
  bool footer = false,
  bool continuous = false,
  List<WmlBlock>? blocks,
}) {
  final story = [
    if (inline != null)
      WmlParagraph(
        inlines: [
          WmlRun(
            text: '\uFFFC',
            inlineVisual: WmlVisual(visual: inline),
          ),
        ],
      ),
  ];
  final visuals = [for (final visual in anchored) WmlVisual(visual: visual)];
  return WmlSection(
    blocks: blocks ?? [_paragraph('Body')],
    header: footer ? [] : story,
    footer: footer ? story : [],
    headerVisuals: footer ? [] : visuals,
    footerVisuals: footer ? visuals : [],
    breakKind: continuous
        ? WmlSectionBreakKind.continuous
        : WmlSectionBreakKind.nextPage,
  );
}

List<LaidOutBox> _pictures(WmlDocument document) => WordLayoutEngine(font: null)
    .layout(document)
    .pages
    .expand((page) => page.frames)
    .where((frame) => frame.kind == LaidOutBoxKind.picture)
    .toList();

void main() {
  for (final footer in [false, true]) {
    final story = footer ? 'footer' : 'header';
    test('$story inline picture remains visible after native roundtrip', () {
      var document = WmlDocument(
        sections: [_section(inline: _picture(_red), footer: footer)],
      );
      for (var cycle = 0; cycle < 2; cycle++) {
        final pictures = _pictures(document);
        expect(pictures, hasLength(1));
        expect(pictures.single.visual!.imageBytes, orderedEquals(_red));
        final page = WordLayoutEngine(font: null).layout(document).pages.single;
        final lines = footer ? page.footer : page.header;
        expect(
          lines
              .expand((line) => line.glyphs)
              .any((glyph) => glyph.glyph.codePoint == 0xFFFC),
          isFalse,
        );
        document = WordDeserializer().readBytes(
          WordSerializer().writeBytes(document),
        );
      }
    });

    test('$story shared model node paints exactly once', () {
      final visual = _picture(_red);
      final section = _section(
        inline: visual,
        anchored: [visual],
        footer: footer,
      );
      // Duplicate representations share the WmlVisual node. Two distinct
      // nodes may deliberately reuse the same asset at the same position.
      final storyParagraph = (footer ? section.footer : section.header).single;
      final node = storyParagraph.inlines
          .whereType<WmlRun>()
          .single
          .inlineVisual!;
      (footer ? section.footerVisuals : section.headerVisuals)[0] = node;
      final document = WmlDocument(sections: [section]);
      final pictures = _pictures(document);
      expect(pictures, hasLength(1));
      expect(pictures.single.visual, same(visual));
    });

    test('$story distinct nodes may reuse one asset at the same placement', () {
      final visual = _picture(_red);
      final pictures = _pictures(
        WmlDocument(
          sections: [
            _section(inline: visual, anchored: [visual], footer: footer),
          ],
        ),
      );
      expect(pictures, hasLength(2));
      expect(pictures.map((frame) => frame.visual), [visual, visual]);
      expect(pictures.first.x, pictures.last.x);
      expect(pictures.first.y, pictures.last.y);
    });

    test(
      '$story distinct inline and anchored pictures of one size survive',
      () {
        final inline = _picture(_red);
        final anchored = _picture(_blue, x: 160);
        expect(_red.length, _blue.length);
        final pictures = _pictures(
          WmlDocument(
            sections: [
              _section(inline: inline, anchored: [anchored], footer: footer),
            ],
          ),
        );
        expect(pictures, hasLength(2));
        expect(
          pictures.map((frame) => frame.visual),
          containsAll([inline, anchored]),
        );
        expect(pictures.map((frame) => frame.x), [72.0, 160.0]);
      },
    );
  }

  test('distinct anchored pictures are not identified by payload length', () {
    final first = _picture(_red, x: 72, y: 36);
    final second = _picture(_blue, x: 72, y: 36);
    final pictures = _pictures(
      WmlDocument(
        sections: [
          _section(anchored: [first, second]),
        ],
      ),
    );
    expect(pictures, hasLength(2));
    expect(pictures.map((frame) => frame.visual), [first, second]);
  });

  test('the same image content at distinct vertical positions survives', () {
    final pictures = _pictures(
      WmlDocument(
        sections: [
          _section(
            anchored: [
              _picture(_red, x: 72, y: 36),
              _picture(_red, x: 72, y: 60),
            ],
          ),
        ],
      ),
    );
    expect(pictures, hasLength(2));
    expect(pictures.map((frame) => frame.y), [36.0, 60.0]);
  });

  test('shared inline and anchored identity retains distinct placements', () {
    final visual = _picture(_red, x: 160, y: 60);
    final pictures = _pictures(
      WmlDocument(
        sections: [
          _section(inline: visual, anchored: [visual]),
        ],
      ),
    );
    expect(pictures, hasLength(2));
    expect(pictures.map((frame) => (frame.x, frame.y)), [
      (72.0, 36.0),
      (160.0, 60.0),
    ]);
  });

  test('body pictures near the header are never removed by header dedup', () {
    final body = _picture(_blue, x: 72, y: 36)
      ..picture.wrap = PictureWrap.inFront;
    final header = _picture(_red, x: 72, y: 36);
    final pictures = _pictures(
      WmlDocument(
        sections: [
          _section(
            anchored: [header],
            blocks: [
              WmlVisual(visual: body),
              _paragraph('Body'),
            ],
          ),
        ],
      ),
    );
    expect(pictures, hasLength(2));
    expect(pictures.map((frame) => frame.visual), [body, header]);
  });

  test(
    'continuous sections regenerate page chrome without copying it into body',
    () {
      final first = _picture(_red, x: 72, y: 36);
      final copied = first.copy();
      final document = WmlDocument(
        sections: [
          _section(anchored: [first], blocks: [_paragraph('First section')]),
          _section(
            anchored: [copied],
            continuous: true,
            blocks: [_paragraph('Continuous section')],
          ),
        ],
      );
      final layout = WordLayoutEngine(font: null).layout(document);
      expect(layout.pages, hasLength(1));
      final pictures = layout.pages.single.frames
          .where((frame) => frame.kind == LaidOutBoxKind.picture)
          .toList();
      expect(pictures, hasLength(1));
      expect(pictures.single.visual, same(copied));
      expect(layout.pages.single.lines, hasLength(2));
    },
  );
}
