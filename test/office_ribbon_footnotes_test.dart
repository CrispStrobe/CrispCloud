import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/services/office_editor_menu.dart';
import 'package:crisp_cloud/widgets/office_editor_ribbon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

void main() {
  testWidgets('Insert > Footnote… adds a note and opens the notes pane', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1700, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    OfficeSurfaceConfig config = const OfficeSurfaceConfig(
      mode: OfficeInteractionMode.editing,
      autofocus: false,
      adaptiveChrome: false,
    );
    final controller = WordEditorController(
      document: WmlDocument.empty(text: 'Text'),
      config: config,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => OfficeEditorRibbon(
              controller: controller,
              kind: OfficeEditorKind.word,
              config: config,
              onSave: () {},
              onClose: () {},
              onConfigChanged: (next) => setState(() => config = next),
              onFind: controller.requestFind,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Menu bar: Insert > Footnote… asks for the text, then opens the pane.
    await tester.tap(find.text('Insert').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Footnote…').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Source');
    await tester.tap(find.text('Insert').last);
    await tester.pumpAndSettle();
    expect(controller.document.footnotes, hasLength(1));
    expect(controller.noteEditText(controller.document.footnotes.single),
        'Source');
    expect(config.showNotesPane, isTrue);

    // The Insert ribbon tab (the second "Insert"; the first is the menu bar)
    // offers the same commands as buttons.
    await tester.tap(find.text('Insert').at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Endnote').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Later');
    await tester.tap(find.text('Insert').last);
    await tester.pumpAndSettle();
    expect(controller.document.endnotes, hasLength(1));

    // Menu bar: View > Hide footnotes.
    await tester.tap(find.text('View').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide footnotes').first);
    await tester.pumpAndSettle();
    expect(config.showNotesPane, isFalse);
    await tester.pumpWidget(const SizedBox());
  });
}
