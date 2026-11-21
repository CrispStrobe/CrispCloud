import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

WmlParagraph _paragraph(String text) =>
    WmlParagraph(inlines: [WmlRun(text: text)]);

OfficeVisual _picture(int byte, {double x = 80, double y = 20}) => OfficeVisual(
  kind: OfficeVisualKind.picture,
  imageBytes: Uint8List.fromList([byte, 2, 3, 4]),
  width: 32,
  height: 16,
  offsetX: x,
  offsetY: y,
);

WmlParagraph _inline(OfficeVisual visual) =>
    _inlineNode(WmlVisual(visual: visual));

WmlParagraph _inlineNode(WmlVisual visual) => WmlParagraph(
  inlines: [WmlRun(text: '\uFFFC', inlineVisual: visual)],
);

List<LaidOutBox> _pictures(LaidOutPage page) =>
    page.frames.where((frame) => frame.kind == LaidOutBoxKind.picture).toList();

WmlSection _sectionWithPictures({
  required List<WmlBlock> blocks,
  required OfficeVisual header,
  OfficeVisual? footer,
  bool continuous = false,
}) => WmlSection(
  breakKind: continuous
      ? WmlSectionBreakKind.continuous
      : WmlSectionBreakKind.nextPage,
  blocks: blocks,
  headerVisuals: [WmlVisual(visual: header)],
  footerVisuals: [if (footer != null) WmlVisual(visual: footer)],
);

LaidOutPage _page({
  List<WmlParagraph> header = const [],
  List<OfficeVisual> visuals = const [],
  List<WmlVisual>? visualNodes,
  List<OfficeVisual> footerVisuals = const [],
}) => WordLayoutEngine(font: null)
    .layout(
      WmlDocument(
        sections: [
          WmlSection(
            blocks: [_paragraph('Body')],
            header: header,
            headerVisuals:
                visualNodes ??
                [for (final visual in visuals) WmlVisual(visual: visual)],
            footerVisuals: [
              for (final visual in footerVisuals) WmlVisual(visual: visual),
            ],
          ),
        ],
      ),
      updateFields: false,
    )
    .pages
    .single;

void main() {
  test('one visual node represented inline and separately paints once', () {
    final visual = _picture(1, x: 92, y: 22);
    // One occurrence uses the same node in both representations. Merely
    // sharing OfficeVisual content does not make two nodes one occurrence.
    final node = WmlVisual(visual: visual);
    final frames = _pictures(
      _page(header: [_inlineNode(node)], visualNodes: [node]),
    );
    expect(frames, hasLength(1));
    expect(frames.single.visual, same(visual));
    expect((frames.single.x, frames.single.y), (92, 22));
  });

  test('same-size inline and separate pictures retain both identities', () {
    final inline = _picture(1, x: 0, y: 0);
    final separate = _picture(9, x: 130, y: 35);
    final frames = _pictures(
      _page(header: [_inline(inline)], visuals: [separate]),
    );
    expect(frames.map((frame) => frame.visual), [inline, separate]);
  });

  test(
    'equal byte counts and placement do not equate distinct picture content',
    () {
      final first = _picture(1);
      final second = _picture(9);
      final frames = _pictures(_page(visuals: [first, second]));
      expect(frames.map((frame) => frame.visual), [first, second]);
    },
  );

  test(
    'matching image content at distinct vertical placements remains visible',
    () {
      final first = _picture(1);
      final second = first.copy()..offsetY = 50;
      final frames = _pictures(_page(visuals: [first, second]));
      expect(frames.map((frame) => frame.y), [20, 50]);
      expect(frames.map((frame) => frame.visual), [first, second]);
    },
  );

  test('distinct chrome nodes at one placement retain both occurrences', () {
    final first = _picture(1);
    final second = first.copy();
    final frames = _pictures(_page(visuals: [first, second]));
    // The serializer writes both authored nodes. Identical content and
    // placement are not provenance for deleting either occurrence.
    expect(frames, hasLength(2));
    expect(frames.map((frame) => frame.visual), [first, second]);
    expect(frames.map((frame) => (frame.x, frame.y)), [(80, 20), (80, 20)]);
  });

  test('repeated references to one listed node paint one occurrence', () {
    final visual = _picture(1);
    final node = WmlVisual(visual: visual);
    final frames = _pictures(_page(visualNodes: [node, node]));
    expect(frames, hasLength(1));
    expect(frames.single.visual, same(visual));
    expect((frames.single.x, frames.single.y), (80, 20));
  });

  for (final sharedAsset in [false, true]) {
    test('transparent authored nodes stay separate, shared=$sharedAsset', () {
      final first = _picture(1)..picture.transparency = 0.5;
      final second = sharedAsset ? first : first.copy();
      final frames = _pictures(_page(visuals: [first, second]));
      expect(frames, hasLength(2));
      expect(frames.map((frame) => frame.visual), [first, second]);
      expect(frames.map((frame) => (frame.x, frame.y)), [(80, 20), (80, 20)]);
      expect(frames.map((frame) => frame.visual!.picture.transparency), [
        0.5,
        0.5,
      ]);
    });
  }

  test('same content and placement preserve different picture adjustments', () {
    final first = _picture(1);
    final second = first.copy()..picture.rotationDeg = 90;
    final frames = _pictures(_page(visuals: [first, second]));
    expect(frames.map((frame) => frame.visual), [first, second]);
  });

  test(
    'header duplicate suppression never removes body frames or their reuse',
    () {
      final first = _picture(1, x: 80, y: 80)
        ..picture.wrap = PictureWrap.inFront;
      final second = _picture(9, x: 80, y: 100)
        ..picture.wrap = PictureWrap.inFront;
      final paragraphs = [
        for (var index = 0; index < 20; index++) _paragraph('Body $index'),
      ];
      final document = WmlDocument(
        sections: [
          WmlSection(
            blocks: [
              WmlVisual(visual: first),
              WmlVisual(visual: second),
              ...paragraphs,
            ],
          ),
        ],
      );
      final engine = WordLayoutEngine(font: null);
      final initial = engine.layout(document, updateFields: false);
      expect(_pictures(initial.pages.first).map((frame) => frame.visual), [
        first,
        second,
      ]);
      paragraphs[3].inlines.whereType<WmlRun>().single.text += ' edited';
      final incremental = engine.layout(
        document,
        updateFields: false,
        reuse: initial,
        dirtyParagraphs: {paragraphs[3]},
      );
      final full = WordLayoutEngine(
        font: null,
      ).layout(document, updateFields: false);
      expect(wordLayoutFingerprint(incremental), wordLayoutFingerprint(full));
      expect(_pictures(incremental.pages.first).map((frame) => frame.visual), [
        first,
        second,
      ]);
    },
  );

  test('header and footer preserve independent copies of one image', () {
    final first = _picture(1);
    final second = first.copy();
    final frames = _pictures(_page(visuals: [first], footerVisuals: [second]));
    expect(frames.map((frame) => frame.visual), [first, second]);
    expect(frames.last.y, greaterThan(frames.first.y));
  });

  test('inline header pictures render without changing the authored story', () {
    final visual = _picture(1, x: 0, y: 0);
    final paragraph = WmlParagraph(
      inlines: [
        WmlRun(text: 'Before '),
        WmlRun(
          text: '\uFFFC',
          inlineVisual: WmlVisual(visual: visual),
        ),
        WmlRun(text: ' after'),
      ],
    );
    final page = _page(header: [paragraph]);
    expect(_pictures(page).single.visual, same(visual));
    expect(paragraph.text, 'Before \uFFFC after');
    expect(page.header.single.text, 'Before   after');
  });

  test('continuous sections paint a shared header once', () {
    final header = _picture(1);
    final document = WmlDocument(
      sections: [
        _sectionWithPictures(
          blocks: [_paragraph('First section')],
          header: header,
        ),
        _sectionWithPictures(
          blocks: [_paragraph('Second section')],
          header: header,
          continuous: true,
        ),
      ],
    );
    final laid = WordLayoutEngine(
      font: null,
    ).layout(document, updateFields: false);
    expect(laid.pages, hasLength(1));
    final page = laid.pages.single;
    expect(_pictures(page).map((frame) => frame.visual), [header]);
    expect(page.lines.map((line) => line.text), [
      'First section',
      'Second section',
    ]);
  });

  test(
    'continuous sections retain body frames and only current chrome through reuse',
    () {
      final oldHeader = _picture(1);
      final currentHeader = _picture(2);
      final firstBody = _picture(3, y: 100)..picture.wrap = PictureWrap.inFront;
      final secondBody = _picture(4, y: 120)
        ..picture.wrap = PictureWrap.inFront;
      final secondParagraph = _paragraph('Second section');
      final document = WmlDocument(
        sections: [
          _sectionWithPictures(
            blocks: [
              WmlVisual(visual: firstBody),
              WmlVisual(visual: secondBody),
              _paragraph('First section'),
            ],
            header: oldHeader,
          ),
          _sectionWithPictures(
            blocks: [secondParagraph],
            header: currentHeader,
            continuous: true,
          ),
        ],
      );
      final engine = WordLayoutEngine(font: null);
      final initial = engine.layout(document, updateFields: false);
      expect(initial.pages, hasLength(1));
      expect(_pictures(initial.pages.single).map((frame) => frame.visual), [
        firstBody,
        secondBody,
        currentHeader,
      ]);
      secondParagraph.inlines.whereType<WmlRun>().single.text += ' edited';
      final incremental = engine.layout(
        document,
        updateFields: false,
        reuse: initial,
        dirtyParagraphs: {secondParagraph},
      );
      final full = WordLayoutEngine(
        font: null,
      ).layout(document, updateFields: false);
      expect(wordLayoutFingerprint(incremental), wordLayoutFingerprint(full));
      expect(_pictures(incremental.pages.single).map((frame) => frame.visual), [
        firstBody,
        secondBody,
        currentHeader,
      ]);
    },
  );

  test('footer chrome does not move continuous body to page bottom', () {
    final header = _picture(1);
    final footer = _picture(2);
    final document = WmlDocument(
      sections: [
        _sectionWithPictures(
          blocks: [_paragraph('First section')],
          header: header,
          footer: footer,
        ),
        _sectionWithPictures(
          blocks: [_paragraph('Second section')],
          header: header,
          footer: footer,
          continuous: true,
        ),
      ],
    );
    final laid = WordLayoutEngine(
      font: null,
    ).layout(document, updateFields: false);
    expect(laid.pages, hasLength(1));
    final page = laid.pages.single;
    expect(_pictures(page).map((frame) => frame.visual), [header, footer]);
    expect(page.lines.map((line) => line.text), [
      'First section',
      'Second section',
    ]);
    expect(
      page.lines.last.y,
      closeTo(page.lines.first.y + page.lines.first.height, .001),
    );
  });
}
