import 'dart:async';

import 'package:crisperbooks/crisperbooks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

EpubDocument _book({String? content}) {
  final book = EpubDocument.create(title: 'Formatted text');
  book.updateText(
    book.chapters.first.path,
    '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Text</title></head>'
    '<body><p id="paragraph">${content ?? 'Before <em id="emphasis">tyop</em><a href="#paragraph" id="link">lable</a>'}</p></body></html>',
  );
  return EpubDocument.open(book.toBytes());
}

EpubStructuredProseBlock _block(EpubDocument book) =>
    book.readStructuredProse(book.chapters.first.path).single;

Future<void> _open(
  WidgetTester tester,
  EpubStructuredProseBlock block,
  FutureOr<void> Function(Map<int, String>) onApply, {
  String Function(Object)? errorMessage,
  String Function(String)? translate,
  FutureOr<void> Function(String)? onPlainTextApply,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<bool>(
              context: context,
              builder: (_) => EbookProseEditorDialog(
                block: block,
                onApply: onApply,
                onPlainTextApply: onPlainTextApply,
                errorMessage: errorMessage,
                translate: translate ?? (value) => value,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Finder _field(int index) => find.byKey(ValueKey('ebook-prose-segment-$index'));

Future<void> _apply(WidgetTester tester) async {
  // enterText notifies the controller immediately, while the enabled button
  // appears on the next frame. Assert that the tested action is really active.
  await tester.pump();
  final button = find.widgetWithText(FilledButton, 'Apply');
  expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
  await tester.tap(button);
}

void main() {
  testWidgets(
    'plain mode uses one multiline field and preserves newline authoring',
    (tester) async {
      final session = EbookEditSession(_book(content: 'Before<br/>After'));
      final block = _block(session.document);
      var structuredCalls = 0;
      await _open(
        tester,
        block,
        (_) => structuredCalls++,
        onPlainTextApply: (text) {
          session.mutate((doc) => doc.updateStructuredProseText(block, text));
        },
      );
      final field = find.byKey(const ValueKey('ebook-prose-plain-text'));
      await tester.ensureVisible(field);
      expect(tester.widget<TextField>(field).controller!.text, 'Before\nAfter');
      expect(find.text('Edit text'), findsOneWidget);
      await tester.enterText(field, 'First\nSecond\nThird');
      await _apply(tester);
      await tester.pumpAndSettle();
      expect(structuredCalls, 0);
      expect(
        session.document.readText(block.resourcePath),
        contains('First<br/>Second<br/>Third'),
      );
      session.undo();
      expect(_block(session.document).text, 'Before\nAfter');
      session.dispose();
    },
  );

  testWidgets(
    'formatted text apply preserves markup and is one undoable batch',
    (tester) async {
      final session = EbookEditSession(_book());
      final block = _block(session.document);
      final path = block.resourcePath;
      final original = session.document.readText(path);
      await _open(
        tester,
        block,
        (edits) => session.mutate(
          (doc) => doc.updateStructuredProseBlock(block, edits),
        ),
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Apply'))
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(_field(1));
      await tester.enterText(_field(1), 'typo');
      await tester.ensureVisible(_field(2));
      await tester.enterText(_field(2), 'label');
      await _apply(tester);
      await tester.pumpAndSettle();
      expect(find.byType(EbookProseEditorDialog), findsNothing);
      expect(
        session.document.readText(path),
        contains('<em id="emphasis">typo</em>'),
      );
      expect(
        session.document.readText(path),
        contains('<a href="#paragraph" id="link">label</a>'),
      );
      expect(session.isDirty, isTrue);
      session.undo();
      expect(session.document.readText(path), original);
      expect(session.canUndo, isFalse);
      expect(session.isDirty, isFalse);
      session.redo();
      expect(_block(session.document).text, 'Before typolabel');
      session.dispose();
    },
  );

  testWidgets('cancel retains the original and never invokes apply', (
    tester,
  ) async {
    final book = _book();
    final original = book.toBytes();
    var applications = 0;
    await _open(tester, _block(book), (_) => applications++);
    await tester.ensureVisible(_field(1));
    await tester.enterText(_field(1), 'unsaved correction');
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(applications, 0);
    expect(book.toBytes(), orderedEquals(original));
  });

  testWidgets('protected objects and breaks have no editable text fields', (
    tester,
  ) async {
    final book = _book(
      content: 'Before <img alt="drawing"/><br id="line"/><em>after</em>',
    );
    final block = _block(book);
    await _open(tester, block, (_) {});
    await tester.ensureVisible(
      find.byKey(const ValueKey('ebook-prose-protected-1')),
    );
    expect(
      find.byKey(const ValueKey('ebook-prose-protected-1')),
      findsOneWidget,
    );
    expect(_field(1), findsNothing);
    await tester.ensureVisible(
      find.byKey(const ValueKey('ebook-prose-protected-2')),
    );
    expect(find.text('Line break'), findsOneWidget);
    expect(_field(2), findsNothing);
    await tester.scrollUntilVisible(
      _field(3),
      100,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(_field(3), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stale application keeps entered text and the dialog open', (
    tester,
  ) async {
    final book = _book();
    final block = _block(book);
    await _open(
      tester,
      block,
      (edits) => book.updateStructuredProseBlock(block, edits),
      errorMessage: (_) => 'The chapter changed. Keep your correction.',
    );
    book.updateText(
      block.resourcePath,
      book
          .readText(block.resourcePath)
          .replaceFirst('id="emphasis"', 'id="emphasis" class="changed"'),
    );
    await tester.ensureVisible(_field(1));
    await tester.enterText(_field(1), 'valuable correction');
    await _apply(tester);
    await tester.pumpAndSettle();
    expect(find.byType(EbookProseEditorDialog), findsOneWidget);
    expect(
      find.text('The chapter changed. Keep your correction.'),
      findsOneWidget,
    );
    await tester.ensureVisible(_field(1));
    expect(
      tester.widget<TextField>(_field(1)).controller!.text,
      'valuable correction',
    );
    expect(book.readText(block.resourcePath), contains('class="changed">tyop'));
    expect(
      book.readText(block.resourcePath),
      isNot(contains('valuable correction')),
    );
  });

  testWidgets(
    'async failure unlocks fields and retry keeps a stable submitted map',
    (tester) async {
      final book = _book();
      final completion = Completer<void>();
      Map<int, String>? submitted;
      var calls = 0;
      await _open(tester, _block(book), (edits) {
        submitted = edits;
        calls++;
        if (calls == 1) return completion.future;
      }, errorMessage: (_) => 'Try again');
      await tester.ensureVisible(_field(1));
      await tester.enterText(_field(1), 'correction');
      await _apply(tester);
      await tester.pump();
      expect(tester.widget<TextField>(_field(1)).enabled, isFalse);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
            .onPressed,
        isNull,
      );
      expect(submitted, {1: 'correction'});
      expect(() => submitted![1] = 'retarget', throwsUnsupportedError);
      completion.completeError(StateError('temporary'));
      await tester.pumpAndSettle();
      expect(find.text('Try again'), findsOneWidget);
      await tester.ensureVisible(_field(1));
      expect(tester.widget<TextField>(_field(1)).enabled, isTrue);
      expect(
        tester.widget<TextField>(_field(1)).controller!.text,
        'correction',
      );
      await _apply(tester);
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.byType(EbookProseEditorDialog), findsNothing);
    },
  );

  testWidgets(
    'labels use the host translator and small layouts stay scrollable',
    (tester) async {
      tester.view.resetPhysicalSize();
      tester.view.physicalSize = const Size(480, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final book = _book();
      await _open(
        tester,
        _block(book),
        (_) {},
        translate: (value) => 'T:$value',
      );
      expect(find.text('T:Edit formatted text'), findsOneWidget);
      expect(find.text('T:Apply'), findsOneWidget);
      expect(find.text('T:Cancel'), findsOneWidget);
      await tester.ensureVisible(_field(2));
      expect(_field(2), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
