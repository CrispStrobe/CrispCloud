import 'package:crisp_cloud/services/pdf_selection_note.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart' show PdfRect;
import 'package:pdf_cos/pdf_cos.dart' show CosArray;

import 'support/pdf_editor_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('selection note preserves multiline anchors and pages through save; one undo', () {
    final controller = PdfEditingController(buildPdfEditorFixture());
    addTearDown(controller.dispose);
    final input = <int, List<PdfRect>>{
      0: [const PdfRect(10, 40, 100, 55), const PdfRect(10, 20, 80, 35)],
      1: [const PdfRect(20, 30, 90, 45)],
    };
    final note = PdfSelectionNote.capture(controller, input);
    input[0]!.clear(); // the popup owns its captured selection
    expect(note.attach('  Review this  '), isTrue);
    final reopened = PdfEditingController(controller.bytes);
    addTearDown(reopened.dispose);
    for (var page = 0; page < 2; page++) {
      final annotation = reopened.document.page(page).annotations.single;
      expect(annotation.subtype, 'Highlight');
      expect(annotation.contents, 'Review this');
      expect((reopened.document.cos.resolve(annotation.dict['QuadPoints']) as CosArray).values, hasLength(page == 0 ? 16 : 8));
    }
    controller.undo();
    expect(controller.document.page(0).annotations, isEmpty);
    expect(controller.document.page(1).annotations, isEmpty);
    controller.redo();
    expect(
      controller.document.page(1).annotations.single.contents,
      'Review this',
    );
  });
  test('stale or invalid selection fails before any page is modified', () {
    final controller = PdfEditingController(buildPdfEditorFixture());
    addTearDown(controller.dispose);
    final note = PdfSelectionNote.capture(controller, {
      0: [const PdfRect(10, 20, 40, 30)],
    });
    controller.rotatePages([0], 90);
    expect(() => note.attach('stale'), throwsStateError);
    final invalid = PdfSelectionNote.capture(controller, {
      0: [const PdfRect(10, 20, 40, 30)],
      8: [const PdfRect(10, 20, 40, 30)],
    });
    expect(() => invalid.attach('invalid'), throwsFormatException);
    expect(controller.document.page(0).annotations, isEmpty);
  });
}
