import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/test_pdf.dart';

void main() {
  PdfEditingController session() {
    final preferences =
        PdfEditingPreferences(store: PdfMemoryPreferencesStore());
    addTearDown(preferences.dispose);
    final editing = PdfEditingController(
      buildTestPdf(),
      preferences: preferences,
      formSecretStore: InMemoryFormSecretStore(),
    );
    addTearDown(editing.dispose);
    return editing;
  }

  // Opening a group arms its default tool, so the first tap on that tool in
  // the strip must keep it armed (it used to toggle it off and collapse the
  // strip, so a rectangle or text box could not be drawn).
  for (final (group, tool, label) in [
    ('Shapes', PdfEditTool.rectangle, 'Rectangle'),
    ('Insert', PdfEditTool.freeText, 'Text box'),
  ]) {
    testWidgets('tapping the default $label in the open $group strip keeps it',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final editing = session();
      final viewer = PdfViewerController();
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: PdfEditingToolbar(
              controller: editing,
              viewerController: viewer,
            ),
          ),
        ),
      ));
      await tester.pump();

      await tester.tap(find.text(group).first);
      await tester.pumpAndSettle();
      expect(editing.tool, tool);

      await tester.tap(find.byTooltip(RegExp('^$label', caseSensitive: false))
          .first);
      await tester.pumpAndSettle();
      expect(editing.tool, tool, reason: 'the tool must stay armed');
      expect(find.byTooltip(RegExp('^$label', caseSensitive: false)),
          findsWidgets,
          reason: 'the strip must stay open');
      await tester.pumpWidget(const SizedBox());
    });
  }
}
