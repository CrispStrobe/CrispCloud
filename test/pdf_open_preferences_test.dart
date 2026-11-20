import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crisp_cloud/services/pdf_open_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'defaults choose shared PDF viewer/editor and preserve Shift+F4 chooser',
    () async {
      final p = await PdfOpenPreferences.load();
      expect(p.viewer, PdfViewerBackend.pdfEditor);
      expect(p.editor, PdfEditorBackend.pdfEditor);
      expect(p.shiftF4, PdfAlternateEditAction.chooser);
    },
  );
  test('all renderer and shortcut choices survive reload', () async {
    await const PdfOpenPreferences(
      viewer: PdfViewerBackend.crispOffice,
      secondaryViewer: PdfViewerBackend.native,
      editor: PdfEditorBackend.crispOffice,
      secondaryEditor: PdfEditorBackend.pdfEditor,
      shiftF4: PdfAlternateEditAction.secondary,
    ).save();
    final p = await PdfOpenPreferences.load();
    expect(p.viewer, PdfViewerBackend.crispOffice);
    expect(p.editor, PdfEditorBackend.crispOffice);
    expect(p.shiftF4, PdfAlternateEditAction.secondary);
  });
  test('unknown stored choices use supported fallbacks', () async {
    SharedPreferences.setMockInitialValues({
      'pdf.open.viewer': 'removed',
      'pdf.open.editor': 'unknown',
    });
    final p = await PdfOpenPreferences.load();
    expect(p.viewer, PdfViewerBackend.pdfEditor);
    expect(p.editor, PdfEditorBackend.pdfEditor);
  });
  test(
    'overlapping saves finish in order and load awaits the last choice',
    () async {
      final a = const PdfOpenPreferences(viewer: PdfViewerBackend.native)
          .save();
      final b = const PdfOpenPreferences(viewer: PdfViewerBackend.crispOffice)
          .save();
      final p = await PdfOpenPreferences.load();
      await Future.wait([a, b]);
      expect(p.viewer, PdfViewerBackend.crispOffice);
    },
  );
}
