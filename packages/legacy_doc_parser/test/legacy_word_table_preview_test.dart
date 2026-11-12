// SPDX-License-Identifier: MPL-2.0
import 'package:legacy_doc_parser/src/legacy_word_structured_model.dart';
import 'package:legacy_doc_parser/src/legacy_word_structured_render.dart';
import 'package:test/test.dart';

String _preview({
  LegacyWordTableCellFormat format = const LegacyWordTableCellFormat(),
  bool rtl = false,
  bool auto = false,
  LegacyWordAlignment alignment = LegacyWordAlignment.left,
  int origin = 0,
  int? height,
  bool? cantSplit,
}) => renderLegacyWordHtml([
  LegacyWordTable(
    startCp: 0,
    endCp: 2,
    rightToLeft: rtl,
    autoFit: auto,
    alignment: alignment,
    rows: [
      LegacyWordTableRow(
        originTwips: origin,
        heightTwips: height,
        cantSplit: cantSplit,
        cells: [
          LegacyWordTableCell(
            paragraphs: const [],
            widthTwips: 1440,
            formatting: format,
          ),
        ],
      ),
    ],
  ),
]);

void main() {
  test('unbordered cells do not acquire a synthetic grid or padding', () {
    final html = _preview();
    expect(html, isNot(contains('#888')));
    expect(html, isNot(contains('padding:4px')));
    expect(html, isNot(contains('border-left')));
  });

  test(
    'resolved cell borders, nil margins and alignment reach the preview',
    () {
      final html = _preview(
        format: const LegacyWordTableCellFormat(
          verticalAlignment: LegacyWordCellAlignment.center,
          noWrap: true,
          margins: {
            LegacyWordBorderSide.left: 240,
            LegacyWordBorderSide.right: null,
          },
          borders: {
            LegacyWordTableBorderSide.top: LegacyWordBorder(
              style: 'double',
              widthEighthPoints: 8,
              colorHex: '123456',
            ),
            LegacyWordTableBorderSide.left: LegacyWordBorder(
              style: 'nil',
              widthEighthPoints: 0,
            ),
          },
        ),
      );
      expect(html, contains('vertical-align:middle'));
      expect(html, contains('white-space:pre;overflow-wrap:normal'));
      expect(html, contains('padding-left:12.0pt'));
      expect(html, contains('padding-right:0.0pt'));
      expect(html, contains('border-top:1.0pt double #123456'));
      expect(html, contains('border-left:0.0pt none currentColor'));
    },
  );

  test(
    'logical cell sides and table positioning respect the table direction',
    () {
      final html = _preview(
        rtl: true,
        origin: 240,
        format: const LegacyWordTableCellFormat(
          margins: {LegacyWordBorderSide.left: 120},
          borders: {
            LegacyWordTableBorderSide.left: LegacyWordBorder(
              style: 'single',
              widthEighthPoints: 4,
            ),
          },
        ),
      );
      expect(html, contains('<table dir="rtl"'));
      expect(html, contains('margin-inline-start:12.0pt'));
      expect(html, contains('padding-right:6.0pt'));
      expect(html, contains('border-right:0.5pt solid currentColor'));
      expect(html, contains('table-layout:fixed'));
      expect(html, contains('width:72.0pt'));
    },
  );

  test(
    'native-only row and cell layout preferences remain visible as limits',
    () {
      final html = _preview(
        auto: true,
        alignment: LegacyWordAlignment.center,
        height: -480,
        cantSplit: true,
        format: const LegacyWordTableCellFormat(
          textDirection: LegacyWordCellTextDirection.btLr,
          fitText: true,
          hideMark: true,
        ),
      );
      expect(html, contains('table-layout:auto'));
      expect(html, contains('margin-inline-start:auto;margin-inline-end:auto'));
      expect(html, contains('data-word-row-height="approximate-exact"'));
      expect(html, contains('height:24.0pt'));
      expect(html, contains('break-inside:avoid'));
      expect(html, contains('data-word-cell-text-direction="btLr"'));
      expect(html, contains('data-word-cell-fit-text="approximate"'));
      expect(html, contains('data-word-cell-hide-mark="approximate"'));
    },
  );

  test('unrepresentable border details are marked rather than invented', () {
    final html = _preview(
      format: const LegacyWordTableCellFormat(
        borders: {
          LegacyWordTableBorderSide.tl2br: LegacyWordBorder(
            style: 'single',
            widthEighthPoints: 4,
          ),
          LegacyWordTableBorderSide.top: LegacyWordBorder(
            style: 'wave',
            widthEighthPoints: 8,
          ),
        },
      ),
    );
    expect(html, contains('data-word-border="approximate"'));
    expect(html, isNot(contains('border-top:')));
  });
}
