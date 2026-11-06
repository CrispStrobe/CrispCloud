import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/office_ribbon_control_strings.dart';
import 'package:crisp_cloud/services/office_editor_menu.dart';
import 'package:crisp_cloud/widgets/office_editor_ribbon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

void main() {
  test('ribbon control translations cover each language and count parameter',
      () {
    final translations = OfficeRibbonControlStrings.translations;
    expect(translations.keys.toSet(),
        {'de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar'});
    final keys = translations['de']!.keys.toSet();
    for (final entry in translations.entries) {
      expect(entry.value.keys.toSet(), keys, reason: entry.key);
      expect(entry.value.values.every((s) => s.isNotEmpty), isTrue,
          reason: entry.key);
      expect(entry.value['{count} lines'], contains('{count}'),
          reason: entry.key);
    }
    expect(
        OfficeRibbonControlStrings.forLanguage('de').lines(1.5), '1.5 Zeilen');
  });

  testWidgets('word ribbon localizes underline control and choices',
      (tester) async {
    tester.view.physicalSize = const Size(1700, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const config = OfficeSurfaceConfig(
      mode: OfficeInteractionMode.editing,
      autofocus: false,
      adaptiveChrome: false,
    );
    final controller = WordEditorController(
      document: WmlDocument.empty(text: 'Text'),
      config: config,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: OfficeEditorRibbon(
          controller: controller,
          kind: OfficeEditorKind.word,
          config: config,
          onSave: () {},
          onClose: () {},
          onConfigChanged: (_) {},
          onFind: controller.requestFind,
        ),
      ),
    ));
    await tester.pump();
    expect(find.byTooltip('Menüband minimieren'), findsOneWidget);
    await tester.tap(find.byTooltip('Unterstreichungsstil'));
    await tester.pumpAndSettle();
    expect(find.text('Gewellt'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
