import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('deleting an inline picture removes its run and undo restores it', () {
    final picture = WmlVisual(
      visual: OfficeVisual(
        kind: OfficeVisualKind.picture,
        title: 'Inline',
        width: 20,
        height: 20,
      ),
    );
    final paragraph = WmlParagraph(
      inlines: <WmlInline>[
        WmlRun(text: 'before '),
        WmlRun(text: '\uFFFC', inlineVisual: picture),
        WmlRun(text: ' after'),
      ],
    );
    final controller = WordEditorController(
      document: WmlDocument(
        sections: <WmlSection>[
          WmlSection(blocks: <WmlBlock>[paragraph]),
        ],
      ),
    );
    addTearDown(controller.dispose);

    expect(controller.visuals, contains(same(picture)));
    controller.selectVisual(picture);
    controller.deleteSelectedVisual();

    expect(paragraph.text, 'before  after');
    expect(
      paragraph.inlines.whereType<WmlRun>().any((r) => r.inlineVisual != null),
      isFalse,
    );
    expect(controller.selectedVisual, isNull);

    controller.undo();
    expect(paragraph.text, 'before ￼ after');
    expect(
      paragraph.inlines
          .whereType<WmlRun>()
          .singleWhere((run) => run.inlineVisual != null)
          .inlineVisual,
      same(picture),
    );
    expect(controller.selectedVisual, same(picture));

    controller.redo();
    expect(paragraph.text, 'before  after');
  });

  test(
    'vertical navigation finds pictures after a table through delete and undo',
    () {
      WmlVisual picture(String title) => WmlVisual(
        visual: OfficeVisual(
          kind: OfficeVisualKind.picture,
          title: title,
          width: 20,
          height: 20,
        ),
      );
      final inline = picture('Inline');
      final first = picture('First block');
      final second = picture('Second block');
      final table = WmlTable(
        grid: [120],
        rows: [
          WmlTableRow(
            cells: [
              WmlTableCell(
                blocks: [
                  WmlParagraph(
                    inlines: [WmlRun(text: '￼', inlineVisual: inline)],
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      final controller = WordEditorController(
        document: WmlDocument(
          sections: [
            WmlSection(
              blocks: [
                table,
                first,
                second,
                WmlParagraph(inlines: [WmlRun(text: 'After')]),
              ],
            ),
          ],
        ),
      );
      addTearDown(controller.dispose);

      controller.moveCaretLine(1);
      expect(controller.selectedVisual, same(first));
      controller.deleteSelectedVisual();
      controller.moveCaretLine(1);
      expect(controller.selectedVisual, same(second));
      controller.undo();
      controller.selectedVisual = null;
      controller.moveCaretLine(1);
      expect(controller.selectedVisual, same(first));
    },
  );
}
