import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _margins = WmlPageMargins(
  top: 72,
  bottom: 72,
  left: 36,
  right: 36,
  header: 18,
  footer: 18,
);

WmlParagraph _paragraph(String text) =>
    WmlParagraph(inlines: [WmlRun(text: text)]);

WmlVisual _picture(
  String title, {
  int seed = 1,
  double height = 16,
  double x = 0,
  double y = 0,
}) => WmlVisual(
  visual: OfficeVisual(
    kind: OfficeVisualKind.picture,
    title: title,
    width: 48,
    height: height,
    // Geometry tests deliberately use different same-length asset data. No
    // decoder is involved in layout and byte length is not visual identity.
    imageBytes: Uint8List.fromList([seed, seed + 1, seed + 2]),
    offsetX: x,
    offsetY: y,
  ),
);

WmlSection _section({
  List<WmlParagraph>? header,
  List<WmlParagraph>? footer,
  List<WmlVisual>? headerVisuals,
  List<WmlVisual>? footerVisuals,
  List<WmlBlock>? blocks,
  WmlSectionBreakKind breakKind = WmlSectionBreakKind.nextPage,
}) => WmlSection(
  pageSize: const WmlPageSize(width: 400, height: 600),
  margins: _margins,
  header: header,
  footer: footer,
  headerVisuals: headerVisuals,
  footerVisuals: footerVisuals,
  blocks: blocks ?? [_paragraph('Body')],
  breakKind: breakKind,
);

List<LaidOutBox> _pictures(LaidOutDocument layout) => [
  for (final page in layout.pages)
    for (final frame in page.frames)
      if (frame.kind == LaidOutBoxKind.picture) frame,
];

LaidOutDocument _layout(List<WmlSection> sections) => WordLayoutEngine(
  font: null,
).layout(WmlDocument(sections: sections), updateFields: false);

void main() {
  for (final footer in [false, true]) {
    final storyName = footer ? 'footer' : 'header';

    test('$storyName shared inline/list node paints exactly once', () {
      final picture = _picture('Shared node', x: 160);
      final story = [
        WmlParagraph(
          inlines: [
            WmlRun(text: '\uFFFC', inlineVisual: picture),
            WmlRun(text: ' Logo label'),
          ],
        ),
      ];
      final layout = _layout([
        _section(
          header: footer ? null : story,
          footer: footer ? story : null,
          headerVisuals: footer ? null : [picture],
          footerVisuals: footer ? [picture] : null,
        ),
      ]);
      final pictures = _pictures(layout);
      expect(pictures, hasLength(1));
      expect(pictures.single.visual, same(picture.visual));
      expect(pictures.single.x, 160);
      final lines = footer
          ? layout.pages.single.footer
          : layout.pages.single.header;
      expect(lines, isNotEmpty);
      expect(lines.map((line) => line.overlayText).join(), contains('Logo'));
      expect(
        lines.map((line) => line.overlayText).join(),
        isNot(contains('\uFFFC')),
      );
    });

    test('$storyName preserves distinct equal-sized inline/list pictures', () {
      final inline = _picture('Inline asset', seed: 1);
      final floating = _picture('Floating asset', seed: 7, x: 160);
      final story = [
        WmlParagraph(
          inlines: [WmlRun(text: '\uFFFC', inlineVisual: inline)],
        ),
      ];
      final layout = _layout([
        _section(
          header: footer ? null : story,
          footer: footer ? story : null,
          headerVisuals: footer ? null : [floating],
          footerVisuals: footer ? [floating] : null,
        ),
      ]);
      final pictures = _pictures(layout);
      expect(pictures.map((frame) => frame.visual?.title), [
        'Inline asset',
        'Floating asset',
      ]);
      expect(pictures.map((frame) => frame.x), [36, 160]);
    });

    test('$storyName distinct nodes may reuse one visual asset', () {
      final inline = _picture('Reused asset', x: 160);
      final floating = WmlVisual(visual: inline.visual);
      final story = [
        WmlParagraph(
          inlines: [WmlRun(text: '\uFFFC', inlineVisual: inline)],
        ),
      ];
      final layout = _layout([
        _section(
          header: footer ? null : story,
          footer: footer ? story : null,
          headerVisuals: footer ? null : [floating],
          footerVisuals: footer ? [floating] : null,
        ),
      ]);
      expect(_pictures(layout).map((frame) => frame.x), [36, 160]);
    });
  }

  test('equal-size header pictures at different positions both survive', () {
    final layout = _layout([
      _section(
        headerVisuals: [
          _picture('First', seed: 1, x: 36, y: 18),
          _picture('Second', seed: 7, x: 36, y: 44),
        ],
      ),
    ]);
    final pictures = _pictures(layout);
    expect(pictures.map((frame) => frame.visual?.title), ['First', 'Second']);
    expect(pictures.map((frame) => frame.y), [18, 44]);
  });

  test(
    'same-size body pictures near the page top are never chrome duplicates',
    () {
      final layout = _layout([
        _section(
          blocks: [
            _picture('Body first', seed: 1),
            _picture('Body second', seed: 7),
            _paragraph('After pictures'),
          ],
        ),
      ]);
      final pictures = _pictures(layout);
      expect(pictures.map((frame) => frame.visual?.title), [
        'Body first',
        'Body second',
      ]);
      expect(pictures.first.y, lessThan(pictures.last.y));
    },
  );

  test('continuous sections retain body frames and rebuild chrome once', () {
    final header = _picture('Running header');
    final footer = _picture('Running footer');
    final layout = _layout([
      _section(
        headerVisuals: [header],
        footerVisuals: [footer],
        blocks: [_picture('Body picture'), _paragraph('First section')],
      ),
      _section(
        breakKind: WmlSectionBreakKind.continuous,
        headerVisuals: [header],
        footerVisuals: [footer],
        blocks: [_paragraph('Continuous section')],
      ),
    ]);
    expect(layout.pages, hasLength(1));
    expect(_pictures(layout).map((frame) => frame.visual?.title), [
      'Body picture',
      'Running header',
      'Running footer',
    ]);
    expect(layout.pages.single.lines, isNotEmpty);
  });

  test('a tall inline header picture participates in body clearance', () {
    final logo = _picture('Tall inline logo', height: 100);
    final layout = _layout([
      _section(
        header: [
          WmlParagraph(
            inlines: [WmlRun(text: '\uFFFC', inlineVisual: logo)],
          ),
        ],
      ),
    ]);
    final frame = _pictures(layout).single;
    expect(
      layout.pages.single.lines.first.y,
      greaterThanOrEqualTo(frame.y + frame.height),
    );
  });

  test('new body pages clear the inline picture in their own header', () {
    WmlParagraph pictureLine(double height) => WmlParagraph(
      inlines: [
        WmlRun(
          text: '\uFFFC',
          inlineVisual: _picture('Page logo', height: height),
        ),
      ],
    );
    final section =
        _section(
            header: [pictureLine(100)],
            blocks: [
              _paragraph('First page'),
              WmlParagraph(inlines: [WmlBreak(WmlBreakType.page)]),
              _paragraph('Even page'),
              for (var n = 0; n < 32; n++) _paragraph('Line $n'),
            ],
          )
          ..differentOddEven = true
          ..evenHeader = [pictureLine(65)];
    final pages = _layout([section]).pages;
    expect(pages, hasLength(3));
    expect(pages[1].lines.first.y, _margins.header + 65);
    expect(pages[2].lines.first.y, _margins.header + 100);
  });

  test(
    'body pictures and chrome remain equivalent after a local text edit',
    () {
      final changed = _paragraph('Before edit');
      final document = WmlDocument(
        sections: [
          _section(
            headerVisuals: [_picture('Header', x: 160)],
            footerVisuals: [_picture('Footer', x: 160)],
            blocks: [
              _picture('Body first', seed: 1),
              _picture('Body second', seed: 7),
              changed,
              for (var index = 0; index < 12; index++)
                _paragraph('Line $index'),
            ],
          ),
        ],
      );
      final engine = WordLayoutEngine(font: null);
      final before = engine.layout(document, updateFields: false);
      changed.inlines.whereType<WmlRun>().single.text = 'After local edit';
      final incremental = engine.layout(
        document,
        updateFields: false,
        reuse: before,
        dirtyParagraphs: {changed},
      );
      final fresh = WordLayoutEngine(
        font: null,
      ).layout(document, updateFields: false);
      expect(wordLayoutFingerprint(incremental), wordLayoutFingerprint(fresh));
      final titles = _pictures(
        incremental,
      ).map((frame) => frame.visual?.title).toList();
      expect(titles.where((title) => title == 'Body first'), hasLength(1));
      expect(titles.where((title) => title == 'Body second'), hasLength(1));
    },
  );
}
