import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:crisp_cloud/services/office_page_preview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Word page preview retains native layout and cannot edit the source',
    () async {
      final doc = WmlDocument.empty();
      final source = WordSerializer().writeBytes(doc);
      final c = await loadOfficePagePreview(source, filename: 'sample.docx');
      expect(c, isA<WordEditorController>());
      expect(c!.config.mode, OfficeInteractionMode.viewing);
      expect((c as WordEditorController).documentLaidOut.pages, isNotEmpty);
      expect(c.config.allowsMutation, isFalse);
      c.insertText("must remain read-only");
      expect(c.isDirty, isFalse);
      c.dispose();
    },
  );
  test(
    'PowerPoint pages use full slide controller and disable edit handles',
    () async {
      final deck = PmlPresentation();
      final c = await loadOfficePagePreview(
        SlideSerializer().writeBytes(deck),
        filename: 'sample.pptx',
      );
      expect(c, isA<SlideEditorController>());
      expect(c!.config.mode, OfficeInteractionMode.viewing);
      expect(c.config.showSlideHandles, isFalse);
      c.dispose();
    },
  );
  test('other formats keep existing fallbacks', () async {
    expect(
      await loadOfficePagePreview(Uint8List(0), filename: 'legacy.ppt'),
      isNull,
    );
  });
}
