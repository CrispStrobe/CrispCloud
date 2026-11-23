import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:crisp_cloud/services/office_page_preview.dart';
import 'package:crisp_cloud/services/office_document_service.dart';
import 'package:crisp_cloud/services/internal_viewer_service.dart';

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
  test('PowerPoint slide shows reach the read-only Office viewer', () async {
    final deck = PmlPresentation(slideWidth: 6858000, slideHeight: 9906000);
    final source = SlideSerializer().writeBytes(deck);
    for (final extension in ['ppsm', 'ppsx', 'potm']) {
      final name = 'example.$extension';
      expect(
        const InternalViewerService().detectMode(name, header: source),
        ViewerMode.office,
      );
      final controller = await loadOfficePagePreview(
        source,
        filename: name,
      ) as SlideEditorController;
      expect(controller.config.allowsMutation, isFalse);
      expect(controller.presentation.slideWidth, 6858000);
      expect(controller.presentation.slideHeight, 9906000);
      expect(
        (await parseOfficeDocument(source, name)).deck?.slides,
        hasLength(1),
      );
      controller.dispose();
    }
  });

  test('Slides fallback recovers a missing ZIP end record', () async {
    final source = SlideSerializer().writeBytes(PmlPresentation());
    final truncated = Uint8List.sublistView(source, 0, source.length - 22);
    final preview = await parseOfficeDocument(truncated, 'recovered.pptx');
    expect(preview.deck?.slides, hasLength(1));
  });

  test('other formats keep existing fallbacks', () async {
    expect(
      await loadOfficePagePreview(Uint8List(0), filename: 'legacy.ppt'),
      isNull,
    );
  });
}
