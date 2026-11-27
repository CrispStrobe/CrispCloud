import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:super_clipboard/super_clipboard.dart';

class _WordClipboard extends Fake implements ClipboardDataReader {
  _WordClipboard(this.native);

  final Uint8List native;

  @override
  bool canProvide(DataFormat format) =>
      format is ValueFormat<Uint8List> || format == Formats.htmlText;

  @override
  Future<T?> readValue<T extends Object>(ValueFormat<T> format) async =>
      (T == Uint8List ? native : '<p>HTML fallback</p>') as T;
}

Uint8List _nativeFragment(WmlDocument document) {
  final bytes = WordSerializer().write(document).save();
  return (CfbfWriter()..addStream('Package', bytes)).build();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'native Word keeps headings, tabs, page breaks, tables and pictures',
    () async {
      final fragment = _nativeFragment(
        WmlDocument(
          sections: [
            WmlSection(
              blocks: [
                WmlParagraph(
                  properties: WmlParagraphProps(
                    headingLevel: 2,
                    pageBreakBefore: true,
                    tabs: const [WmlTabStop(position: 72)],
                    justification: WmlJustification.center,
                    explicitJustification: true,
                  ),
                  inlines: [
                    WmlRun(
                      text: 'Start\tEnd',
                      properties: WmlRunProps(
                        bold: true,
                        color: '2458A0',
                        fontSizeHalfPoints: 32,
                      ),
                    ),
                  ],
                ),
                WmlTable(
                  grid: [160],
                  rows: [
                    WmlTableRow(
                      cells: [
                        WmlTableCell(
                          blocks: [
                            WmlParagraph(
                              inlines: [WmlRun(text: 'Editable table')],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                WmlVisual(
                  visual: OfficeVisual(
                    kind: OfficeVisualKind.picture,
                    imageBytes: PngBytes.studioCard(width: 48, height: 24),
                    width: 100,
                    height: 50,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
      final payload = (await OfficeClipboard.readWordRepresentations(
        _WordClipboard(fragment),
      ))!;
      final clipboard = OfficeClipboard.instance;
      final useSystem = clipboard.useSystem;
      clipboard.useSystem = false;
      clipboard.writeLocal(payload);
      addTearDown(() {
        clipboard.clear();
        clipboard.useSystem = useSystem;
      });
      final controller = WordEditorController(document: WmlDocument.empty());
      addTearDown(controller.dispose);
      await controller.pasteFromClipboard();
      final result = WordDeserializer().read(
        OpcPackage.openBytes(controller.saveBytes()),
      );
      final paragraph = result.paragraphs.first;
      final run = paragraph.inlines.whereType<WmlRun>().first;
      expect(paragraph.text, 'Start\tEnd');
      expect(paragraph.properties.headingLevel, 2);
      expect(paragraph.properties.pageBreakBefore, isTrue);
      expect(paragraph.properties.tabs.single.position, 72);
      expect(paragraph.properties.justification, WmlJustification.center);
      expect(run.properties.bold, isTrue);
      expect(run.properties.color, '2458A0');
      final table = result.sections.single.blocks.whereType<WmlTable>().single;
      expect(
        (table.rows.single.cells.single.blocks.single as WmlParagraph).text,
        'Editable table',
      );
      expect(result.visuals.single.visual.imageBytes, isNotEmpty);
      expect(result.visuals.single.visual.width, 100);
    },
  );

  test(
    'a carried Word page layout applies only to a blank destination',
    () async {
      final native = _nativeFragment(
        WmlDocument(
          sections: [
            WmlSection(
              pageSize: WmlPageSize.letter(),
              margins: const WmlPageMargins(top: 48, bottom: 54),
              header: [
                WmlParagraph(
                  properties: WmlParagraphProps(pageNumberField: true),
                ),
              ],
              blocks: [
                WmlParagraph(inlines: [WmlRun(text: 'Source')]),
              ],
            ),
          ],
        ),
      );
      final payload = (await OfficeClipboard.readWordRepresentations(
        _WordClipboard(native),
      ))!;
      expect(payload.wordSections, hasLength(1));
      final clipboard = OfficeClipboard.instance;
      final oldSystem = clipboard.useSystem;
      clipboard.useSystem = false;
      clipboard.writeLocal(payload);
      addTearDown(() {
        clipboard.clear();
        clipboard.useSystem = oldSystem;
      });
      final blank = WordEditorController(document: WmlDocument.empty());
      final existing = WordEditorController(
        document: WmlDocument.empty(text: 'Existing'),
      );
      addTearDown(blank.dispose);
      addTearDown(existing.dispose);
      await blank.pasteFromClipboard();
      await existing.pasteFromClipboard();
      final reopened = WordDeserializer().read(
        OpcPackage.openBytes(blank.saveBytes()),
      );
      expect(
        reopened.sections.single.pageSize.matches(WmlPageSize.letter()),
        isTrue,
      );
      expect(reopened.sections.single.margins.top, 48);
      expect(
        reopened.sections.single.header.single.properties.pageNumberField,
        isTrue,
      );
      expect(existing.document.sections.single.margins.top, 72);
      expect(existing.document.sections.single.header, isEmpty);
      blank.undo();
      expect(blank.document.sections.single.margins.top, 72);
      expect(blank.document.paragraphs.single.text, isEmpty);
    },
  );

  test('native Word keeps web links and strips file targets', () async {
    final native = _nativeFragment(
      WmlDocument(
        sections: [
          WmlSection(
            blocks: [
              WmlParagraph(
                inlines: [
                  WmlRun(
                    text: 'File',
                    hyperlink: const WmlHyperlink(file: '/tmp/discard'),
                  ),
                  WmlRun(
                    text: 'Web',
                    hyperlink: const WmlHyperlink(url: 'https://example.com/'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    final payload = (await OfficeClipboard.readWordRepresentations(
      _WordClipboard(native),
    ))!;
    final para = payload.wordBlocks.single as WmlParagraph;
    final runs = para.inlines.whereType<WmlRun>().toList();
    expect(runs.first.text, 'File');
    expect(runs.first.hyperlink, isNull);
    expect(runs.last.hyperlink!.url, 'https://example.com/');
  });

  test(
    'an invalid or oversized native Word package falls back to HTML',
    () async {
      final native =
          (ZipWriter()
                ..addFile('word/document.xml', Uint8List(2 * 1024 * 1024 + 1)))
              .close();
      final payload = await OfficeClipboard.readWordRepresentations(
        _WordClipboard(native),
      );
      expect(payload!.plain, 'HTML fallback');
    },
  );
}
