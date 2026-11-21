// Typing edits notify listeners once per keystroke: the undo command's
// notification is folded into the edit's own (coalesceEditNotifications).
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

WordEditorController _controller() {
  final c = WordEditorController(
    document: WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          blocks: <WmlBlock>[
            for (var i = 0; i < 5; i++)
              WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'Absatz $i')]),
          ],
        ),
      ],
    ),
  );
  addTearDown(c.dispose);
  c.caret
    ..paragraphIndex = 2
    ..logicalIndex = 3
    ..collapseSelection();
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final on in <bool>[true, false]) {
    test('typing edits notify ${on ? 'once' : 'twice (switch off)'}', () {
      OfficeController.coalesceEditNotifications = on;
      addTearDown(() => OfficeController.coalesceEditNotifications = true);
      final c = _controller();
      var notified = 0;
      var pagesAtNotify = <int>[];
      c.addListener(() {
        notified++;
        pagesAtNotify.add(c.documentLaidOut.pages.length);
      });
      final expected = on ? 1 : 2;
      c.insertText('x');
      expect(notified, expected, reason: 'insertText');
      notified = 0;
      c.deleteSelectionOr(backward: true);
      expect(notified, expected, reason: 'backspace');
      notified = 0;
      c.input.updateEditingValue(
        TextEditingValue(
          text: 'Abs!atz 2',
          selection: const TextSelection.collapsed(offset: 4),
        ),
      );
      expect(notified, expected, reason: 'IME');
      notified = 0;
      c.insertParagraphBreak();
      expect(notified, greaterThanOrEqualTo(1), reason: 'Enter');
      expect(c.isDirty, isTrue);
      expect(c.canUndo, isTrue);
      c.undo();
      expect(c.document.paragraphs.length, 5);
    });
  }
}
