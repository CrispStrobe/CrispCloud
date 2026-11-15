import 'package:crisp_cloud/widgets/pdf_floating_toolbars.dart';
import 'package:crisp_cloud/services/pdf_selection_note.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart' show PdfRect;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pdf_editor_fixture.dart';

void main() {
  testWidgets(
    'independent bars persist dragging and let empty overlay clicks reach the page',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1000, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = PdfEditingController(buildPdfEditorFixture());
      final viewer = PdfViewerController();
      final commands = PdfEditorCommands(
        controller: controller,
        viewerController: viewer,
      );
      addTearDown(() {
        commands.dispose();
        viewer.dispose();
        controller.dispose();
      });
      PdfSelectionNote.capture(controller, {
        0: [const PdfRect(10, 20, 50, 40)],
      }).attach('Note');
      controller.selectAnnotation(0, 0);
      var taps = 0;
      Widget app(Key key) => MaterialApp(
        home: Scaffold(
          body: PdfFloatingToolbars(
            key: key,
            controller: controller,
            commands: commands,
            barBuilder: (context, primary, vertical, handle) => SizedBox(
              width: primary ? 300 : 200,
              height: 48,
              child: Material(
                child: Row(
                  children: [handle, Text(primary ? 'Tools' : 'Settings')],
                ),
              ),
            ),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => taps++,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app(const ValueKey('first')));
      await tester.pumpAndSettle();
      final primary = find.byKey(const ValueKey('pdf-toolbar-grip-0'));
      final secondary = find.byKey(const ValueKey('pdf-toolbar-grip-1'));
      final before = tester.getCenter(secondary);
      await tester.drag(primary, const Offset(-150, -180));
      await tester.pumpAndSettle();
      expect((tester.getCenter(secondary) - before).distance, lessThan(1));
      final moved = tester.getCenter(primary);
      await tester.tapAt(const Offset(900, 200));
      expect(taps, 1);
      await tester.pumpWidget(app(const ValueKey('reopened')));
      await tester.pumpAndSettle();
      expect((tester.getCenter(primary) - moved).distance, lessThan(1));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('crispcloud.pdf.toolbars.v1.snap'), isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
