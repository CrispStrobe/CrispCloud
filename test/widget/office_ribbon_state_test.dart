import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/services/office_editor_menu.dart';
import 'package:crisp_cloud/widgets/office_editor_ribbon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

WordEditorController _controller({
  bool tracking = false,
  bool viewing = false,
  bool protected = false,
  bool passwordProtected = false,
}) {
  final document = WmlDocument.empty(text: 'Review state');
  document
    ..trackRevisions = tracking
    ..restrictEditing = protected
    ..protectionHasPassword = passwordProtected;
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

SlideEditorController _slides({int count = 2}) {
  final controller = SlideEditorController(
    presentation: PmlPresentation(
      slides: [
        for (var index = 0; index < count; index++) PmlSlide(id: 256 + index),
      ],
    ),
    config: const OfficeSurfaceConfig(
      mode: OfficeInteractionMode.editing,
      autofocus: false,
      adaptiveChrome: false,
    ),
  );
  addTearDown(controller.dispose);
  return controller;
}

Widget _slideRibbon(SlideEditorController controller) => OfficeEditorRibbon(
  controller: controller,
  kind: OfficeEditorKind.slides,
  config: controller.config,
  onSave: () {},
  onClose: () {},
  onConfigChanged: controller.syncConfig,
  onFind: controller.requestFind,
);

Future<void> _slideAction(
  WidgetTester tester,
  OfficeEditorAction action,
) async {
  await tester
      .state<OfficeEditorRibbonState>(find.byType(OfficeEditorRibbon))
      .perform(action);
  await _settle(tester);
}

Future<void> _confirmSlideDelete(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
  await _settle(tester);
}

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
  testWidgets('confirmed slide deletion keeps undo and redo history', (
    tester,
  ) async {
    final controller = _slides();
    final original = controller.presentation.slides.toList();
    await tester.pumpWidget(_host(_slideRibbon(controller)));
    await _slideAction(tester, OfficeEditorAction.deleteSlide);
    expect(find.text('Delete slide 1?'), findsOneWidget);
    expect(controller.presentation.slides, original);
    await _confirmSlideDelete(tester);
    expect(controller.presentation.slides, [original.last]);
    expect(controller.isDirty, isTrue);
    controller.undo();
    expect(controller.presentation.slides, original);
    controller.redo();
    expect(controller.presentation.slides, [original.last]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('slide delete prompts once and cancellation allows a retry', (
    tester,
  ) async {
    final controller = _slides();
    await tester.pumpWidget(_host(_slideRibbon(controller)));
    await _slideAction(tester, OfficeEditorAction.deleteSlide);
    await _slideAction(tester, OfficeEditorAction.deleteSlide);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(_button(tester, 'Delete').onTap, isNull);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await _settle(tester);
    expect(controller.presentation.slides, hasLength(2));
    expect(controller.isDirty, isFalse);
    expect(_button(tester, 'Delete').onTap, isNotNull);
    await _slideAction(tester, OfficeEditorAction.deleteSlide);
    await _confirmSlideDelete(tester);
    expect(controller.presentation.slides, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('slide delete confirmation cannot delete a new selection', (
    tester,
  ) async {
    final controller = _slides();
    final original = controller.presentation.slides.toList();
    await tester.pumpWidget(_host(_slideRibbon(controller)));
    await _slideAction(tester, OfficeEditorAction.deleteSlide);
    controller.setActiveSlide(1);
    await _confirmSlideDelete(tester);
    expect(controller.presentation.slides, original);
    expect(controller.activeSlideIndex, 1);
    expect(controller.isDirty, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('slide delete confirmation rejects a changed deck revision', (
    tester,
  ) async {
    final controller = _slides();
    final first = controller.slide;
    await tester.pumpWidget(_host(_slideRibbon(controller)));
    await _slideAction(tester, OfficeEditorAction.deleteSlide);
    controller.duplicateSlide(0);
    controller.setActiveSlide(0);
    final changed = controller.presentation.slides.toList();
    expect(controller.slide, same(first));
    await _confirmSlideDelete(tester);
    expect(controller.presentation.slides, changed);
    expect(controller.presentation.slides, hasLength(3));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('slide delete confirmation cannot remove the final slide', (
    tester,
  ) async {
    final controller = _slides(count: 1);
    final first = controller.slide;
    controller.duplicateSlide(0);
    controller.setActiveSlide(0);
    await tester.pumpWidget(_host(_slideRibbon(controller)));
    await _slideAction(tester, OfficeEditorAction.deleteSlide);
    controller.undo();
    expect(controller.presentation.slides, [first]);
    await _confirmSlideDelete(tester);
    expect(controller.presentation.slides, [first]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'slide delete respects viewing mode before and after its prompt',
    (tester) async {
      final controller = _slides();
      await tester.pumpWidget(_host(_slideRibbon(controller)));
      controller.setMode(OfficeInteractionMode.viewing);
      await _slideAction(tester, OfficeEditorAction.deleteSlide);
      expect(find.byType(AlertDialog), findsNothing);
      expect(_button(tester, 'Delete').onTap, isNull);
      controller.setMode(OfficeInteractionMode.editing);
      await _slideAction(tester, OfficeEditorAction.deleteSlide);
      controller.setMode(OfficeInteractionMode.viewing);
      await _confirmSlideDelete(tester);
      expect(controller.presentation.slides, hasLength(2));
      expect(controller.isDirty, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final dispose in [false, true]) {
    testWidgets(
      'pending slide deletion handles ${dispose ? 'ribbon disposal' : 'a replacement controller'}',
      (tester) async {
        final first = _slides();
        final second = _slides();
        final selected = ValueNotifier<SlideEditorController?>(first);
        addTearDown(selected.dispose);
        await tester.pumpWidget(
          _host(
            ValueListenableBuilder(
              valueListenable: selected,
              builder: (context, controller, child) => controller == null
                  ? const SizedBox.shrink()
                  : _slideRibbon(controller),
            ),
          ),
        );
        await _slideAction(tester, OfficeEditorAction.deleteSlide);
        selected.value = dispose ? null : second;
        await tester.pump();
        await _confirmSlideDelete(tester);
        expect(first.presentation.slides, hasLength(2));
        expect(second.presentation.slides, hasLength(2));
        expect(first.isDirty, isFalse);
        expect(second.isDirty, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final change in [
    'slide',
    'controller',
    'revision',
    'viewing',
    'dispose',
  ]) {
    testWidgets('speaker notes dialog rejects changed $change', (tester) async {
      final first = _slides();
      final second = _slides();
      final selected = ValueNotifier<SlideEditorController?>(first);
      addTearDown(selected.dispose);
      await tester.pumpWidget(
        _host(
          ValueListenableBuilder(
            valueListenable: selected,
            builder: (context, controller, child) => controller == null
                ? const SizedBox.shrink()
                : _slideRibbon(controller),
          ),
        ),
      );
      await _slideAction(tester, OfficeEditorAction.speakerNotes);
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Notes for the original slide',
      );
      switch (change) {
        case 'slide':
          first.setActiveSlide(1);
        case 'controller':
          selected.value = second;
        case 'revision':
          first.duplicateSlide(0);
          first.setActiveSlide(0);
        case 'viewing':
          first.setMode(OfficeInteractionMode.viewing);
        case 'dispose':
          selected.value = null;
      }
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Apply'));
      await _settle(tester);
      expect(
        first.presentation.slides.every((slide) => slide.notes.isEmpty),
        isTrue,
      );
      expect(
        second.presentation.slides.every((slide) => slide.notes.isEmpty),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

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

  for (final passwordProtected in [false, true]) {
    testWidgets(
      'initial protected state ${passwordProtected ? 'disables password removal' : 'can unprotect and undo'}',
      (tester) async {
        final controller = _controller(
          tracking: true,
          protected: true,
          passwordProtected: passwordProtected,
        );
        await tester.pumpWidget(_host(_ribbon(controller)));
        await _review(tester);
        expect(find.text('Protected'), findsOneWidget);
        expect(_button(tester, 'Tracking on').onTap, isNull);
        expect(controller.config.allowsMutation, isFalse);
        if (passwordProtected) {
          expect(_button(tester, 'Protected').onTap, isNull);
          controller.syncConfig(
            controller.config.copyWith(mode: OfficeInteractionMode.editing),
          );
          await tester.pump();
          expect(_button(tester, 'Protected').onTap, isNull);
          expect(controller.config.allowsMutation, isFalse);
          await tester.tap(find.text('Tools'));
          await tester.pump();
          final remove = tester.widget<MenuItemButton>(
            find.ancestor(
              of: find.text('Unprotect document'),
              matching: find.byType(MenuItemButton),
            ),
          );
          expect(remove.onPressed, isNull);
          expect(controller.isDirty, isFalse);
        } else {
          expect(_button(tester, 'Protected').onTap, isNotNull);
          await tester.tap(find.text('Protected'));
          await tester.pump();
          expect(controller.document.restrictEditing, isFalse);
          expect(controller.config.allowsMutation, isTrue);
          expect(controller.isDirty, isTrue);
          expect(find.text('Protect'), findsOneWidget);
          controller.undo();
          await tester.pump();
          expect(controller.document.restrictEditing, isTrue);
          expect(controller.config.allowsMutation, isFalse);
          expect(find.text('Protected'), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

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
