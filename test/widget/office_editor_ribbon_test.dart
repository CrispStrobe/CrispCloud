// test/widget/office_editor_ribbon_test.dart
//
// Smoke tests for the host ribbon: Word font/paragraph commands, sheet cell
// formatting, slide creation and the find bar.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/services/office_editor_menu.dart';
import 'package:crisp_cloud/widgets/office_editor_find_bar.dart';
import 'package:crisp_cloud/widgets/office_editor_ribbon.dart';

OfficeSurfaceConfig _config() => const OfficeSurfaceConfig(
      mode: OfficeInteractionMode.editing,
      autofocus: false,
      adaptiveChrome: false,
    );

Widget _host(
  OfficeController controller,
  OfficeEditorKind kind, {
  Locale? locale,
}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Column(
        children: <Widget>[
          OfficeEditorRibbon(
            controller: controller,
            kind: kind,
            config: controller.config,
            onSave: () {},
            onClose: () {},
            onConfigChanged: (_) {},
            onFind: controller.requestFind,
          ),
          Expanded(
            child: switch (kind) {
              OfficeEditorKind.word => QudsWordEditor(
                  controller: controller as WordEditorController,
                  config: controller.config,
                ),
              OfficeEditorKind.sheet => QudsSheetEditor(
                  controller: controller as SheetEditorController,
                  config: controller.config,
                ),
              OfficeEditorKind.slides => QudsSlideEditor(
                  controller: controller as SlideEditorController,
                  config: controller.config,
                ),
              OfficeEditorKind.unsupported => const SizedBox.shrink(),
            },
          ),
        ],
      ),
    ),
  );
}

void _widen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1700, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('Word ribbon applies bold and paragraph alignment',
      (WidgetTester tester) async {
    _widen(tester);
    final WordEditorController controller = WordEditorController(
      document: WmlDocument.empty(text: 'Hello ribbon'),
      config: _config(),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _host(controller, OfficeEditorKind.word),
    );
    await tester.pump();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Insert'), findsWidgets);
    expect(find.byIcon(Icons.format_bold), findsOneWidget);

    await tester.tap(find.byIcon(Icons.format_bold));
    await tester.pump();
    expect(controller.activeRunProps.bold, isTrue);

    await tester.tap(find.byIcon(Icons.format_align_center));
    await tester.pump();
    expect(
      controller.document.paragraphs.first.properties.justification,
      WmlJustification.center,
    );

    // The ribbon tab switch exposes the Insert group.
    await tester.tap(find.text('Insert').last);
    await tester.pump();
    expect(find.text('Table'), findsWidgets);
    expect(find.text('Hyperlink'), findsOneWidget);

    await tester.tap(find.text('Table').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Insert table'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The Format menu opens the font dialog.
    await tester.tap(find.text('Format'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Font…'), findsOneWidget);
    await tester.tap(find.text('Font…'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Font'), findsWidgets);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Sheet ribbon applies bold to the active cell',
      (WidgetTester tester) async {
    _widen(tester);
    final SheetEditorController controller = SheetEditorController(
      config: _config(),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _host(controller, OfficeEditorKind.sheet),
    );
    await tester.pump();

    expect(controller.sheet.cell(controller.activeCell).fontBold, isFalse);
    await tester.tap(find.byIcon(Icons.format_bold));
    await tester.pump();
    expect(controller.sheet.cell(controller.activeCell).fontBold, isTrue);

    // Undo is wired through the shared command pipeline.
    controller.undo();
    controller.refresh();
    await tester.pump();
    expect(controller.sheet.cell(controller.activeCell).fontBold, isFalse);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Slide ribbon adds a slide', (WidgetTester tester) async {
    _widen(tester);
    final SlideEditorController controller = SlideEditorController(
      config: _config(),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _host(controller, OfficeEditorKind.slides),
    );
    await tester.pump();

    expect(controller.presentation.slides.length, 1);
    await tester.tap(find.byIcon(Icons.add_box_outlined).first);
    await tester.pump();
    expect(controller.presentation.slides.length, 2);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('German locale localizes ribbon and menus',
      (WidgetTester tester) async {
    _widen(tester);
    final WordEditorController controller = WordEditorController(
      document: WmlDocument.empty(text: 'Hallo'),
      config: _config(),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _host(controller, OfficeEditorKind.word, locale: const Locale('de')),
    );
    await tester.pump();

    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Datei'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('macOS uses the native menu bar and a compact ribbon',
      (WidgetTester tester) async {
    _widen(tester);
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final WordEditorController controller = WordEditorController(
      document: WmlDocument.empty(text: 'Hello'),
      config: _config(),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _host(controller, OfficeEditorKind.word),
    );
    await tester.pump();

    // The in-window File menu row is gone on macOS.
    expect(find.text('File'), findsNothing);
    expect(
      tester.getSize(find.byType(OfficeEditorRibbon)).height,
      lessThan(100),
    );

    debugDefaultTargetPlatformOverride = null;
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Find bar collects Word matches', (WidgetTester tester) async {
    final WordEditorController controller = WordEditorController(
      document: WmlDocument.empty(text: 'alpha beta alpha'),
      config: _config(),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OfficeFindBar(controller: controller),
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'alpha');
    await tester.pump();
    expect(controller.findSession.hits.length, 2);

    await tester.pumpWidget(const SizedBox());
  });
}
