import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _editorKey = ValueKey<String>('guarded-word-editor');
const _dialogFieldKey = ValueKey<String>('modal-text-field');

WordEditorController _controller(String text) {
  final controller = WordEditorController(
    document: WmlDocument.empty(text: text),
  );
  controller.caret
    ..logicalIndex = text.length
    ..collapseSelection();
  return controller;
}

Widget _app(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox.expand(child: child)),
);

Widget _editor(WordEditorController controller, FocusNode focus) =>
    QudsWordEditor(key: _editorKey, controller: controller, focusNode: focus);

Future<void> _focusEditor(
  WidgetTester tester,
  WordEditorController controller,
  FocusNode focus,
) async {
  focus.requestFocus();
  await tester.pump();
  expect(focus.hasPrimaryFocus, isTrue);
  expect(controller.input.isAttached, isTrue);
}

void _expectStaleInputRejected(WordEditorController controller) {
  final paragraphs = controller.document.paragraphs
      .map((paragraph) => paragraph.text)
      .toList();
  final revision = controller.contentRevision;
  final value = controller.input.value;
  final caret = controller.caret.logicalIndex;

  controller.input.updateEditingValue(
    const TextEditingValue(
      text: 'stale replacement',
      selection: TextSelection.collapsed(offset: 17),
      composing: TextRange(start: 0, end: 5),
    ),
  );
  controller.input.performAction(TextInputAction.newline);
  // Native desktop IMEs can deliver editing selectors separately from values
  // and actions. They must obey the same ownership policy.
  controller.input.performSelector('deleteBackward:');

  expect(
    controller.document.paragraphs.map((paragraph) => paragraph.text),
    paragraphs,
  );
  expect(controller.contentRevision, revision);
  expect(controller.caret.logicalIndex, caret);
  expect(controller.input.value, value);
  controller.attachInput();
  expect(controller.input.isAttached, isFalse);
}

Future<void> _finishDialog(WidgetTester tester, Future<void> closed) async {
  Navigator.of(tester.element(find.byKey(_editorKey))).pop();
  // The editor runs a caret ticker, so an unbounded pumpAndSettle is unsuitable.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await closed;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);

  testWidgets(
    'modal text input retains ownership over stale Word IME traffic',
    (tester) async {
      final controller = _controller('Document text');
      final editorFocus = FocusNode(debugLabel: 'word');
      final dialogFocus = FocusNode(debugLabel: 'dialog');
      final dialogText = TextEditingController();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        editorFocus.dispose();
        dialogFocus.dispose();
        dialogText.dispose();
      });

      await tester.pumpWidget(_app(_editor(controller, editorFocus)));
      await _focusEditor(tester, controller, editorFocus);
      final closed = showDialog<void>(
        context: tester.element(find.byKey(_editorKey)),
        builder: (context) => AlertDialog(
          content: TextField(
            key: _dialogFieldKey,
            controller: dialogText,
            focusNode: dialogFocus,
            autofocus: true,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(dialogFocus.hasPrimaryFocus, isTrue);
      expect(controller.input.isAttached, isFalse);

      controller.onRequestFocus?.call();
      await tester.pump();
      expect(dialogFocus.hasPrimaryFocus, isTrue);
      _expectStaleInputRejected(controller);
      // Send to the existing platform client without refocusing the TextField:
      // attaching the Word bridge above must not steal the dialog's connection.
      tester.testTextInput.enterText('Only in the dialog');
      await tester.pump();
      expect(dialogText.text, 'Only in the dialog');
      expect(controller.document.paragraphs.single.text, 'Document text');

      await _finishDialog(tester, closed);
      await _focusEditor(tester, controller, editorFocus);
      tester.testTextInput.enterText('Document text resumed');
      await tester.pump();
      expect(
        controller.document.paragraphs.single.text,
        'Document text resumed',
      );
    },
  );

  testWidgets('covered route rejects stale input even when Word keeps focus', (
    tester,
  ) async {
    final controller = _controller('Preserve this');
    final editorFocus = FocusNode(debugLabel: 'word');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      editorFocus.dispose();
    });

    await tester.pumpWidget(_app(_editor(controller, editorFocus)));
    await _focusEditor(tester, controller, editorFocus);
    final closed = showDialog<void>(
      context: tester.element(find.byKey(_editorKey)),
      requestFocus: false,
      builder: (context) => const AlertDialog(content: Text('Covered route')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(editorFocus.hasPrimaryFocus, isTrue);
    _expectStaleInputRejected(controller);
    final revision = controller.contentRevision;
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX, character: 'x');
    await tester.pump();
    expect(controller.document.paragraphs.map((paragraph) => paragraph.text), [
      'Preserve this',
    ]);
    expect(controller.contentRevision, revision);

    await _finishDialog(tester, closed);
    expect(editorFocus.hasPrimaryFocus, isTrue);
    expect(controller.input.isAttached, isTrue);
    // Restored route ownership must revive the platform client without a
    // click, a focus change, or an explicit controller attachment.
    tester.testTextInput.enterText('Preserve this resumed');
    await tester.pump();
    expect(controller.document.paragraphs.single.text, 'Preserve this resumed');
  });

  testWidgets('controller replacement transfers the focused input guard', (
    tester,
  ) async {
    final first = _controller('First document');
    final second = _controller('Second document');
    final current = ValueNotifier<WordEditorController>(first);
    final editorFocus = FocusNode(debugLabel: 'shared word focus');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      current.dispose();
      first.dispose();
      second.dispose();
      editorFocus.dispose();
    });

    await tester.pumpWidget(
      _app(
        ValueListenableBuilder<WordEditorController>(
          valueListenable: current,
          builder: (context, controller, child) =>
              _editor(controller, editorFocus),
        ),
      ),
    );
    await _focusEditor(tester, first, editorFocus);
    final state = tester.state(find.byKey(_editorKey));

    current.value = second;
    await tester.pump();
    expect(tester.state(find.byKey(_editorKey)), same(state));
    expect(editorFocus.hasPrimaryFocus, isTrue);
    expect(first.input.isAttached, isFalse);
    expect(first.onRequestFocus, isNull);
    expect(second.input.isAttached, isTrue);

    _expectStaleInputRejected(first);
    // The rejected old bridge must leave the new controller's client attached.
    expect(second.input.isAttached, isTrue);
    tester.testTextInput.enterText('Second document edited');
    await tester.pump();
    expect(first.document.paragraphs.single.text, 'First document');
    expect(second.document.paragraphs.single.text, 'Second document edited');
    expect(second.canUndo, isTrue);
    second.undo();
    expect(second.document.paragraphs.single.text, 'Second document');
  });

  testWidgets(
    'unmounted editor rejects stale traffic and can be mounted again',
    (tester) async {
      final controller = _controller('Reopen this');
      final editorFocus = FocusNode(debugLabel: 'reusable word focus');
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        editorFocus.dispose();
      });

      await tester.pumpWidget(_app(_editor(controller, editorFocus)));
      await _focusEditor(tester, controller, editorFocus);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(controller.input.isAttached, isFalse);
      expect(controller.onRequestFocus, isNull);
      _expectStaleInputRejected(controller);
      expect(controller.document.paragraphs.single.text, 'Reopen this');

      await tester.pumpWidget(_app(_editor(controller, editorFocus)));
      await _focusEditor(tester, controller, editorFocus);
      tester.testTextInput.enterText('Reopen this safely');
      await tester.pump();
      expect(controller.document.paragraphs.single.text, 'Reopen this safely');
    },
  );

  testWidgets('focused selecting mode preserves navigation and rejects edits', (
    tester,
  ) async {
    final controller = _controller('Read only');
    final editorFocus = FocusNode(debugLabel: 'selecting word focus');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      editorFocus.dispose();
    });

    await tester.pumpWidget(_app(_editor(controller, editorFocus)));
    await _focusEditor(tester, controller, editorFocus);
    // Selecting mode permits caret navigation while keeping mutation disabled.
    controller.setMode(OfficeInteractionMode.selecting);
    await tester.pump();
    expect(editorFocus.hasPrimaryFocus, isTrue);
    expect(controller.input.isAttached, isFalse);
    expect(controller.config.allowsMutation, isFalse);
    expect(controller.config.allowsSelection, isTrue);

    final end = controller.document.paragraphs.single.text.length;
    controller.caret
      ..logicalIndex = end
      ..collapseSelection();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(controller.caret.logicalIndex, end - 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX, character: 'x');
    await tester.pump();
    expect(controller.document.paragraphs.single.text, 'Read only');
    expect(controller.canUndo, isFalse);
  });
}
