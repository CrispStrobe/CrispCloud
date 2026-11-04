import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf_document/pdf_document.dart';

import 'support/test_pdf.dart';

void main() {
  PdfEditingController session({bool withText = false}) {
    final preferences =
        PdfEditingPreferences(store: PdfMemoryPreferencesStore());
    addTearDown(preferences.dispose);
    final editing = PdfEditingController(
      buildTestPdf(withText: withText),
      preferences: preferences,
      formSecretStore: InMemoryFormSecretStore(),
    );
    addTearDown(editing.dispose);
    return editing;
  }

  PdfViewerController viewer() {
    final result = PdfViewerController();
    addTearDown(result.dispose);
    return result;
  }

  Future<void> pumpHost(WidgetTester tester, Widget body) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: body)));
    await tester.pump();
  }

  testWidgets(
      'excluded redaction cannot be armed by commands or group defaults',
      (tester) async {
    final editing = session();
    final commands = PdfEditorCommands(
      controller: editing,
      viewerController: viewer(),
      tools: {PdfEditTool.select, PdfEditTool.rectangle},
    );
    addTearDown(commands.dispose);
    await pumpHost(tester, const SizedBox());
    final context = tester.element(find.byType(Scaffold));

    expect(await commands.armTool(context, PdfEditTool.redact), isFalse);
    expect(await commands.toggleTool(context, PdfEditTool.redact), isFalse);
    commands.toggleToolNow(PdfEditTool.redact);
    commands.redactSelection();
    commands.openGroup(const PdfToolGroup(
      'restricted-default',
      Icons.gradient,
      [PdfToolEntry.tool(PdfEditTool.redact, Icons.gradient)],
      defaultTool: PdfEditTool.redact,
    ));
    expect(editing.tool, isNot(PdfEditTool.redact));
    expect(editing.hasRedactionMarks, isFalse);
    expect(commands.catalog(context).map((command) => command.id),
        isNot(contains('tool-redact')));

    // The filter must not disable supported editing commands.
    expect(await commands.armTool(context, PdfEditTool.rectangle), isTrue);
    expect(editing.tool, PdfEditTool.rectangle);
  });

  testWidgets('pre-expanded search preference cannot reveal disabled redaction',
      (tester) async {
    final editing = session();
    final controller = viewer();
    final preferences = editing.preferences..searchRedactExpanded = true;
    Widget panel(bool allowed) => Row(children: [
          PdfSearchResultsPanel(
            controller: controller,
            editing: editing,
            preferences: preferences,
            showRedaction: allowed,
          ),
          const Expanded(child: SizedBox()),
        ]);

    await pumpHost(tester, panel(false));
    expect(preferences.searchRedactExpanded, isTrue);
    expect(
        find.byKey(const ValueKey('pdf-search-redact-toggle')), findsNothing);
    expect(find.byKey(const ValueKey('pdf-search-redact-one')), findsNothing);
    expect(find.byKey(const ValueKey('pdf-search-redact-all')), findsNothing);
    expect(find.byKey(const ValueKey('pdf-search-replace-toggle')),
        findsOneWidget);

    // Prove that the persisted expansion is present and only the gate hides it.
    await pumpHost(tester, panel(true));
    expect(
        find.byKey(const ValueKey('pdf-search-redact-toggle')), findsOneWidget);
    expect(find.byKey(const ValueKey('pdf-search-redact-all')), findsOneWidget);
    await pumpHost(tester, panel(false));
    expect(find.byKey(const ValueKey('pdf-search-redact-all')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('restricted shell clears a pre-armed tool and blocks K and X',
      (tester) async {
    final editing = session()..tool = PdfEditTool.redact;
    final controller = viewer();
    await pumpHost(
      tester,
      PdfEditorView(
        controller: editing,
        viewerController: controller,
        autoRenderWorker: false,
        features: const PdfEditorFeatures(
          headerBar: false,
          thumbnails: false,
          tools: {PdfEditTool.select, PdfEditTool.rectangle},
        ),
      ),
    );
    expect(editing.tool, PdfEditTool.select);
    final pdfViewer = tester.widget<PdfViewer>(find.byType(PdfViewer));
    expect(pdfViewer.textSelectionRedaction, isFalse);
    expect(find.byKey(const ValueKey('pdf-apply-redactions')), findsNothing);
    expect(find.byKey(const ValueKey('pdf-find-to-redact')), findsNothing);

    controller.requestKeyboardFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pump();
    expect(editing.tool, PdfEditTool.select);
    expect(editing.lastUsedTool, PdfEditTool.redact);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.pump();
    expect(editing.tool, PdfEditTool.select);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(editing.tool, PdfEditTool.rectangle);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a toolbar hides Apply even for existing marks and an armed tool',
      (tester) async {
    final editing = session()
      ..addRedaction(0, const PdfRect(20, 30, 80, 100))
      ..tool = PdfEditTool.redact;
    await pumpHost(
      tester,
      Align(
        alignment: Alignment.bottomCenter,
        child: PdfEditingToolbar(
          controller: editing,
          viewerController: viewer(),
          tools: const {PdfEditTool.select, PdfEditTool.rectangle},
          onFindToRedact: () => fail('Restricted find-to-redact was invoked'),
        ),
      ),
    );
    expect(editing.hasRedactionMarks, isTrue);
    expect(find.byKey(const ValueKey('pdf-apply-redactions')), findsNothing);
    expect(find.byKey(const ValueKey('pdf-find-to-redact')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  // A width-fitted 612pt page in the default 800px-wide test viewport.
  Offset textPosition() => const Offset(100 * 800 / 612, 72 * 800 / 612);

  Future<({PdfEditingController editing, PdfViewerController viewer})>
      pumpRestrictedViewer(WidgetTester tester) async {
    final editing = session(withText: true);
    final controller = viewer();
    await pumpHost(
      tester,
      PdfViewer(
        editing: editing,
        controller: controller,
        initialFit: PdfViewerFit.width,
        textSelectionRedaction: false,
      ),
    );
    return (editing: editing, viewer: controller);
  }

  testWidgets('desktop text menu omits redaction while retaining markup',
      (tester) async {
    final state = await pumpRestrictedViewer(tester);
    await tester.tapAt(textPosition(),
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(state.viewer.hasSelection, isTrue);
    expect(find.byKey(const ValueKey('pdf-text-menu-redact')), findsNothing);
    expect(find.byKey(const ValueKey('pdf-text-menu-copy')), findsOneWidget);
    expect(state.editing.hasRedactionMarks, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('touch selection chip omits redaction while retaining markup',
      (tester) async {
    final state = await pumpRestrictedViewer(tester);
    final gesture = await tester.startGesture(textPosition());
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pump();
    expect(state.viewer.hasSelection, isTrue);
    expect(
        find.byKey(const ValueKey('pdf-text-selection-chip')), findsOneWidget);
    expect(find.byKey(const ValueKey('pdf-text-selection-chip-redact')),
        findsNothing);
    expect(find.byKey(const ValueKey('pdf-text-selection-chip-markup')),
        findsOneWidget);
    expect(state.editing.hasRedactionMarks, isFalse);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(const SizedBox());
  });
}
