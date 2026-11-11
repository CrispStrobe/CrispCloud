import 'package:quds_office_engine/quds_office_engine.dart';

Map<String, WmlDocument> layoutCases() {
  WmlParagraph paragraph(
    String text, {
    bool rtl = false,
    bool heading = false,
  }) => WmlParagraph(
    inlines: [
      WmlRun(
        text: text,
        properties: WmlRunProps(
          bold: heading,
          fontSizeHalfPoints: heading ? 28 : 22,
          asciiFont: 'Arial',
          csFont: 'Arial',
        ),
      ),
    ],
    properties: WmlParagraphProps(
      rightToLeft: rtl,
      justification: rtl ? WmlJustification.right : WmlJustification.left,
      spacingAfter: 6,
    ),
  );
  WmlSection section(
    List<WmlBlock> blocks, {
    int columns = 1,
    double width = 360,
    double height = 280,
  }) => WmlSection(
    blocks: blocks,
    pageSize: WmlPageSize(width: width, height: height),
    margins: const WmlPageMargins(
      top: 24,
      bottom: 24,
      left: 24,
      right: 24,
      header: 8,
      footer: 8,
    ),
    columnCount: columns,
    columnSpace: 18,
    columnSep: columns > 1,
  );
  final rtl = WmlDocument(
    sections: [
      section([
        paragraph('العربية والنص المختلط', rtl: true, heading: true),
        paragraph(
          'مرحبا بالعالم. هذا اختبار لاتجاه النص من اليمين إلى اليسار.',
          rtl: true,
        ),
        paragraph('CrispCloud 2026 — العربية 123 — English', rtl: true),
        paragraph('Left aligned English paragraph with punctuation (42).'),
        WmlTable(
          grid: [140, 140],
          properties: WmlTableProps(rightToLeft: true),
          rows: [
            WmlTableRow(
              cells: [
                WmlTableCell(blocks: [paragraph('العمود الأول', rtl: true)]),
                WmlTableCell(blocks: [paragraph('Second column')]),
              ],
            ),
          ],
        ),
      ]),
    ],
  );
  final columns = WmlDocument(
    sections: [
      section([
        for (int i = 0; i < 6; i++)
          paragraph(
            'Column paragraph $i. Text wraps across this narrow column and continues in reading order.',
          ),
      ], columns: 2),
      section(
        [
          paragraph('New landscape section', heading: true),
          paragraph('A section break restores one column.'),
          paragraph('Forced next page')..properties.pageBreakBefore = true,
        ],
        width: 420,
        height: 220,
      ),
    ],
  );
  final notes = WmlDocument(
    sections: [
      section(
        [
          paragraph('Reference paragraph'),
          for (int i = 0; i < 7; i++)
            paragraph(
              'Body $i follows the long note and must remain visible on the following pages.',
            ),
        ],
        width: 300,
        height: 260,
      ),
    ],
  );
  WordNotes.insert(
    notes,
    notes.paragraphs.first,
    endnote: false,
    text: List.generate(
      100,
      (i) => 'N${i.toString().padLeft(3, '0')}',
    ).join(' '),
  );
  notes.footnotes.first.paragraphs.first.inlines
      .whereType<WmlRun>()
      .first
      .properties
    ..color = '225588'
    ..italic = true;
  return {'rtl': rtl, 'columns_sections': columns, 'continued_notes': notes};
}
