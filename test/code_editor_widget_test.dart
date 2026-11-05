// Widget-level smoke tests for the Re-Editor integration.

import 'package:crisp_cloud/services/editor_highlighting.dart';
import 'package:crisp_cloud/widgets/code_editor_find_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

void main() {
  testWidgets('CodeEditor mounts with highlighting and preserves edits', (
    tester,
  ) async {
    final controller = CodeLineEditingController.fromText('void main() {}');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: Scaffold(
          body: CodeEditor(
            controller: controller,
            autofocus: false,
            style: CodeEditorStyle(
              codeTheme: buildEditorHighlightTheme(
                language: 'dart',
                dark: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CodeEditor), findsOneWidget);
    expect(tester.takeException(), isNull);

    controller.selection = const CodeLineSelection.collapsed(
      index: 0,
      offset: 0,
    );
    controller.replaceSelection('// Unicode 🌍\n');
    await tester.pump();

    expect(controller.text, '// Unicode 🌍\nvoid main() {}');
    expect(tester.takeException(), isNull);
  });

  testWidgets('find panel opens, shows controls and closes', (tester) async {
    final controller = CodeLineEditingController.fromText('cat\nCat');
    final findController = CodeFindController(controller);
    addTearDown(() {
      findController.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: CodeEditor(
              controller: controller,
              findController: findController,
              autofocus: false,
              findBuilder: (context, findController, readOnly) =>
                  CodeEditorFindPanel(
                    controller: findController,
                    editingController: controller,
                    readOnly: readOnly,
                  ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    findController.findMode();
    await tester.pump();
    expect(find.text('Find'), findsOneWidget);
    expect(find.text('Aa'), findsOneWidget);
    expect(find.text('.*'), findsOneWidget);

    findController.close();
    await tester.pump();
    // The find field autofocused and started Re-Editor's cursor blink timer.
    // Drop focus so the timer is cancelled before the tree is torn down.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Find'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
