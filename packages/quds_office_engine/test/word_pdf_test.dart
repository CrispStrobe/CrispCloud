import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  test('round-trips a Word document and emits a PDF 1.7 file', () {
    final WmlDocument doc = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          blocks: <WmlBlock>[
            WmlParagraph(
              properties: WmlParagraphProps(
                justification: WmlJustification.center,
              ),
              inlines: <WmlInline>[
                WmlRun(
                  text: 'Quds Office مرحبا',
                  properties: WmlRunProps(bold: true, fontSizeHalfPoints: 28),
                ),
              ],
            ),
            WmlParagraph(
              inlines: <WmlInline>[
                WmlRun(text: 'Line two with more words for wrapping. ' * 8),
              ],
            ),
            WmlTable(
              grid: <double>[200, 200],
              rows: <WmlTableRow>[
                WmlTableRow(
                  cells: <WmlTableCell>[
                    WmlTableCell(
                      blocks: <WmlBlock>[
                        WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'A')]),
                      ],
                    ),
                    WmlTableCell(
                      blocks: <WmlBlock>[
                        WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'B')]),
                      ],
                      gridSpan: 1,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );

    final Uint8List docx = WordSerializer().writeBytes(doc);
    expect(docx[0], 0x50);
    final WmlDocument opened = WordDeserializer().readBytes(docx);
    expect(opened.paragraphs.first.text, contains('Quds Office'));
    expect(
      opened.paragraphs.first.properties.justification,
      WmlJustification.center,
    );
    expect(opened.sections.first.blocks.whereType<WmlTable>(), isNotEmpty);

    SfntFont? font;
    const String fontPath = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf';
    if (File(fontPath).existsSync()) {
      font = SfntFont.parse(File(fontPath).readAsBytesSync());
    }
    final LaidOutDocument laid = WordLayoutEngine(font: font).layout(opened);
    expect(laid.pages, isNotEmpty);
    expect(laid.pages.first.lines, isNotEmpty);

    final Uint8List pdf = PdfDocument.fromWord(opened, font: font);
    expect(String.fromCharCodes(pdf.take(8)), '%PDF-1.7');
    expect(utf8Contains(pdf, '%%EOF'), isTrue);
    expect(utf8Contains(pdf, 'xref'), isTrue);
  });
}

bool utf8Contains(Uint8List bytes, String token) {
  return String.fromCharCodes(bytes).contains(token);
}
