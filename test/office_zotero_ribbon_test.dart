import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/services/office_editor_menu.dart';
import 'package:crisp_cloud/widgets/office_editor_ribbon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

Widget _host(WordEditorController controller, VoidCallback? onZotero) =>
    MaterialApp(
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: OfficeEditorRibbon(
          controller: controller,
          kind: OfficeEditorKind.word,
          config: controller.config,
          onSave: () {},
          onClose: () {},
          onConfigChanged: (_) {},
          onFind: controller.requestFind,
          onZotero: onZotero,
        ),
      ),
    );

void main() {
  testWidgets('Zotero is reachable from Word Insert menu and ribbon', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = WordEditorController(
      document: WmlDocument.empty(text: 'Cite here.'),
      config: const OfficeSurfaceConfig(
        mode: OfficeInteractionMode.editing,
        autofocus: false,
        adaptiveChrome: false,
      ),
    );
    addTearDown(controller.dispose);
    var calls = 0;
    await tester.pumpWidget(_host(controller, () => calls++));
    await tester.tap(find.text('Insert').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zotero…'));
    await tester.pumpAndSettle();
    expect(calls, 1);

    await tester.tap(find.text('Insert').last);
    await tester.pumpAndSettle();
    expect(find.text('References'), findsOneWidget);
    await tester.tap(find.text('Zotero'));
    expect(calls, 2);

    controller.config = controller.config.copyWith(
      mode: OfficeInteractionMode.viewing,
    );
    await tester.pump();
    final button = find
        .ancestor(of: find.text('Zotero'), matching: find.byType(InkWell))
        .first;
    expect(tester.widget<InkWell>(button).onTap, isNull);
    expect(controller.isDirty, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('hosts without Zotero integration keep the entry point hidden', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = WordEditorController(
      document: WmlDocument.empty(text: 'Text'),
      config: const OfficeSurfaceConfig(
        mode: OfficeInteractionMode.editing,
        autofocus: false,
        adaptiveChrome: false,
      ),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller, null));
    await tester.tap(find.text('Insert').last);
    await tester.pumpAndSettle();
    expect(find.text('Zotero'), findsNothing);
    await tester.tap(find.text('Insert').first);
    await tester.pumpAndSettle();
    expect(find.text('Zotero…'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
