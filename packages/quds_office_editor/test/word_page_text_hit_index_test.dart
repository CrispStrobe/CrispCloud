import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/src/editor_word/page_text_hit_index.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

LaidOutLine _line(double y, WmlHyperlink link, {int? comment}) => LaidOutLine(
  glyphs: comment == null
      ? []
      : [
          LaidOutGlyph(
            glyph: const ShapedGlyph(
              codePoint: 65,
              glyphId: 1,
              advance: 8,
              logicalIndex: 0,
              level: 0,
            ),
            x: 10,
            y: y,
            color: '000000',
            fontSize: 12,
            bold: false,
            underline: WmlUnderline.none,
            hyperlink: link,
            commentIds: [1, comment],
          ),
        ],
  x: 10,
  y: y,
  width: 8,
  height: 12,
  pageIndex: 0,
  justification: WmlJustification.left,
  hyperlink: comment == null ? link : null,
);

void main() {
  test('overlapping lines retain story and document order', () {
    const headerLink = WmlHyperlink(anchor: 'header');
    const bodyLink = WmlHyperlink(anchor: 'body');
    const nextLink = WmlHyperlink(anchor: 'next');
    const footerLink = WmlHyperlink(anchor: 'footer');
    final body = _line(20, bodyLink, comment: 7);
    final index = WordPageTextHitIndex(
      LaidOutPage(
        index: 0,
        width: 300,
        height: 400,
        header: [_line(14, headerLink)],
        lines: [body, _line(18, nextLink, comment: 8)],
        footer: [_line(25, footerLink)],
      ),
    );
    expect(index.linkAt(const Offset(10, 28)), same(headerLink));
    expect(index.commentIdAt(const Offset(8, 28)), 7);
    expect(index.linkAt(const Offset(10, 28.1)), same(bodyLink));
    expect(index.linkAt(const Offset(10, 34.1)), same(footerLink));
    expect(index.linkAt(const Offset(10, 39.1)), isNull);

    // Font fitting may change glyph x and advance after building the index.
    body.glyphs.single
      ..x = 30
      ..advance = 12;
    expect(index.linkAt(const Offset(10, 29)), same(nextLink));
    expect(index.linkAt(const Offset(42, 34)), same(bodyLink));
    expect(index.commentIdAt(const Offset(44, 34)), 7);
    expect(index.commentIdAt(const Offset(44.1, 34)), isNull);
  });
}
