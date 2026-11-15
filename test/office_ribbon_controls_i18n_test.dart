import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/office_ribbon_control_strings.dart';
import 'package:crisp_cloud/services/office_editor_menu.dart';
import 'package:crisp_cloud/widgets/office_editor_ribbon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

void main() {
  test('every modeled underline has a distinct translated choice', () {
    final english = OfficeRibbonControlStrings.forLanguage('en');
    final labels = WmlUnderline.values.map(english.underline).toSet();
    expect(labels.length, WmlUnderline.values.length);
    for (final table in OfficeRibbonControlStrings.translations.values) {
      expect(table.keys.toSet().containsAll(labels), isTrue);
    }
  });
  test(
    'ribbon control translations cover each language and count parameter',
    () {
      final translations = OfficeRibbonControlStrings.translations;
      expect(translations.keys.toSet(), {
        'de',
        'fr',
        'es',
        'pt',
        'zh',
        'ja',
        'ko',
        'ar',
      });
      final keys = translations['de']!.keys.toSet();
      for (final entry in translations.entries) {
        expect(entry.value.keys.toSet(), keys, reason: entry.key);
        expect(
          entry.value.values.every((s) => s.isNotEmpty),
          isTrue,
          reason: entry.key,
        );
        expect(
          entry.value['{count} lines'],
          contains('{count}'),
          reason: entry.key,
        );
      }
      expect(
        OfficeRibbonControlStrings.forLanguage('de').lines(1.5),
        '1.5 Zeilen',
      );
    },
  );

  testWidgets('word ribbon localizes underline control and choices', (
    tester,
  ) async {
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
    await tester.pumpWidget(
      MaterialApp(
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
      ),
    );
    await tester.pump();
    expect(find.byTooltip('Menüband minimieren'), findsOneWidget);
    await tester.tap(find.byTooltip('Unterstreichungsstil'));
    await tester.pumpAndSettle();
    expect(find.text('Gewellt'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('every underline choice survives Font Apply and DOCX reopen', (
    tester,
  ) async {
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
      document: WmlDocument.empty(text: 'Underlined words'),
      config: config,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
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
      ),
    );
    await tester.pump();

    final control = find.byType(PopupMenuButton<WmlUnderline>);
    final popup = tester.widget<PopupMenuButton<WmlUnderline>>(control);
    final choices = popup
        .itemBuilder(tester.element(control))
        .whereType<PopupMenuItem<WmlUnderline>>()
        .toList();
    expect(choices.map((choice) => choice.value), WmlUnderline.values);
    final labels = choices
        .map((choice) => (choice.child! as Text).data!)
        .toList();
    expect(labels.toSet(), hasLength(WmlUnderline.values.length));
    for (final language in OfficeRibbonControlStrings.translations.entries) {
      expect(language.value.keys, containsAll(labels), reason: language.key);
      expect(
        labels.map((label) => language.value[label]).toSet(),
        hasLength(WmlUnderline.values.length),
        reason: language.key,
      );
    }

    for (final style in WmlUnderline.values) {
      controller.selectAll();
      await tester.pump();
      await tester.tap(control);
      await tester.pumpAndSettle();
      final choice = find.byWidgetPredicate(
        (widget) =>
            widget is PopupMenuItem<WmlUnderline> && widget.value == style,
      );
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await tester.pumpAndSettle();
      expect(controller.activeRunProps.underline, style, reason: style.name);

      // The font dialog must admit every imported/current enum value. Applying
      // it without edits must not normalize the selected underline away.
      final revision = controller.contentRevision;
      final fontAction = tester
          .state<OfficeEditorRibbonState>(find.byType(OfficeEditorRibbon))
          .perform(OfficeEditorAction.font);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButtonFormField<WmlUnderline>>(
              find.byType(DropdownButtonFormField<WmlUnderline>),
            )
            .initialValue,
        style,
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Apply'));
      await tester.pumpAndSettle();
      await fontAction;
      expect(controller.contentRevision, revision, reason: style.name);

      final reopened = WordEditorController.fromBytes(controller.saveBytes());
      try {
        expect(reopened.document.paragraphs.single.text, 'Underlined words');
        expect(
          reopened.activeRunProps.underline,
          style,
          reason: style.xmlValue,
        );
      } finally {
        reopened.dispose();
      }
      expect(tester.takeException(), isNull, reason: style.name);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
