import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/widgets/office_editor_ribbon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

WordEditorController _controller({
  bool tracking = false,
  bool viewing = false,
}) {
  final document = WmlDocument.empty(text: 'Review state');
  document.trackRevisions = tracking;
  final controller = WordEditorController(
    document: document,
    config: OfficeSurfaceConfig(
      mode: viewing
          ? OfficeInteractionMode.viewing
          : OfficeInteractionMode.editing,
      autofocus: false,
      adaptiveChrome: false,
    ),
  );
  addTearDown(controller.dispose);
  return controller;
}

Widget _ribbon(WordEditorController controller) => OfficeEditorRibbon(
  controller: controller,
  kind: OfficeEditorKind.word,
  config: controller.config,
  onSave: () {},
  onClose: () {},
  onConfigChanged: controller.syncConfig,
  onFind: controller.requestFind,
);

Widget _host(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

Future<void> _review(WidgetTester tester) async {
  await tester.tap(find.text('Review'));
  await tester.pump();
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

InkWell _button(WidgetTester tester, String label) => tester.widget<InkWell>(
  find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first,
);

void main() {
  testWidgets(
    'Track Changes renders imported state and follows undo and redo',
    (tester) async {
      final controller = _controller(tracking: true);
      await tester.pumpWidget(_host(_ribbon(controller)));
      await _review(tester);
      expect(find.text('Tracking on'), findsOneWidget);
      await tester.tap(find.text('Tracking on'));
      await tester.pump();
      expect(controller.document.trackRevisions, isFalse);
      expect(find.text('Track changes'), findsOneWidget);
      controller.undo();
      await tester.pump();
      expect(controller.document.trackRevisions, isTrue);
      expect(find.text('Tracking on'), findsOneWidget);
      controller.redo();
      await tester.pump();
      expect(controller.document.trackRevisions, isFalse);
      expect(find.text('Track changes'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('reused ribbon reads the replacement controller review state', (
    tester,
  ) async {
    final first = _controller(tracking: true);
    final second = _controller();
    final selected = ValueNotifier(first);
    addTearDown(selected.dispose);
    await tester.pumpWidget(
      _host(
        ValueListenableBuilder(
          valueListenable: selected,
          builder: (context, controller, child) => _ribbon(controller),
        ),
      ),
    );
    await _review(tester);
    expect(find.text('Tracking on'), findsOneWidget);
    selected.value = second;
    await tester.pump();
    expect(find.text('Track changes'), findsOneWidget);
    first.setTrackRevisions(false);
    first.setTrackRevisions(true);
    await tester.pump();
    expect(find.text('Track changes'), findsOneWidget);
    await tester.tap(find.text('Track changes'));
    await tester.pump();
    expect(second.document.trackRevisions, isTrue);
    expect(find.text('Tracking on'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('viewing cannot toggle Track Changes or document protection', (
    tester,
  ) async {
    final controller = _controller(viewing: true);
    await tester.pumpWidget(_host(_ribbon(controller)));
    await _review(tester);
    expect(_button(tester, 'Track changes').onTap, isNull);
    expect(_button(tester, 'Protect').onTap, isNull);
    expect(controller.document.trackRevisions, isFalse);
    expect(controller.document.restrictEditing, isFalse);
    expect(controller.isDirty, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('protection controls reflect the document after undo and redo', (
    tester,
  ) async {
    final controller = _controller();
    await tester.pumpWidget(_host(_ribbon(controller)));
    await _review(tester);
    await tester.tap(find.text('Protect'));
    await _settle(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Protect'));
    await _settle(tester);
    expect(controller.document.restrictEditing, isTrue);
    expect(find.text('Protected'), findsOneWidget);
    controller.undo();
    await tester.pump();
    expect(controller.document.restrictEditing, isFalse);
    expect(find.text('Protect'), findsOneWidget);
    controller.redo();
    await tester.pump();
    expect(controller.document.restrictEditing, isTrue);
    expect(find.text('Protected'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'pending protect confirmation cannot change a replacement document',
    (tester) async {
      final first = _controller();
      final second = _controller();
      final selected = ValueNotifier(first);
      addTearDown(selected.dispose);
      await tester.pumpWidget(
        _host(
          ValueListenableBuilder(
            valueListenable: selected,
            builder: (context, controller, child) => _ribbon(controller),
          ),
        ),
      );
      await _review(tester);
      await tester.tap(find.text('Protect'));
      await _settle(tester);
      selected.value = second;
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Protect'));
      await _settle(tester);
      expect(first.document.restrictEditing, isFalse);
      expect(second.document.restrictEditing, isFalse);
      expect(first.isDirty, isFalse);
      expect(second.isDirty, isFalse);
      expect(_button(tester, 'Protect').onTap, isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'pending protect confirmation rejects a changed document revision',
    (tester) async {
      final controller = _controller();
      await tester.pumpWidget(_host(_ribbon(controller)));
      await _review(tester);
      await tester.tap(find.text('Protect'));
      await _settle(tester);
      controller.insertText('New revision ');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Protect'));
      await _settle(tester);
      expect(controller.document.restrictEditing, isFalse);
      expect(
        controller.document.paragraphs.first.text,
        contains('New revision '),
      );
      expect(_button(tester, 'Protect').onTap, isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('pending protection confirmation handles ribbon disposal', (
    tester,
  ) async {
    final controller = _controller();
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    await tester.pumpWidget(
      _host(
        ValueListenableBuilder(
          valueListenable: visible,
          builder: (context, show, child) =>
              show ? _ribbon(controller) : const SizedBox.shrink(),
        ),
      ),
    );
    await _review(tester);
    await tester.tap(find.text('Protect'));
    await _settle(tester);
    visible.value = false;
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Protect'));
    await _settle(tester);
    expect(controller.document.restrictEditing, isFalse);
    expect(controller.isDirty, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
