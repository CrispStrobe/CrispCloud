import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _runKey = ValueKey<String>('run-field-context-command');
const _contextKey = ValueKey<String>('zotero-selected-field-context');
const _textKey = ValueKey<String>('zotero-selected-field-text');
const _locationKey = ValueKey<String>('zotero-selected-field-location');
const _pendingKey = ValueKey<String>('zotero-selected-field-pending');
const _directKey = ValueKey<String>('zotero-direct-command');

ZoteroCitation _citation(String id, String text, {int noteIndex = 0}) =>
    ZoteroCitation(
      citationId: id,
      plainCitation: text,
      noteIndex: noteIndex,
      items: [
        ZoteroCitationItem.fromCsl(
          itemData: {'id': id, 'type': 'book', 'title': 'Source $id'},
          uris: ['http://zotero.org/users/42/items/ABCD1234'],
        ),
      ],
    );

String _code(String id, String text) =>
    'ITEM CSL_CITATION ${jsonEncode(_citation(id, text).toJson())}';

WmlDocument _document({String citationText = '(Alpha)'}) {
  final document = WmlDocument.empty(text: 'Before ');
  final paragraph = document.paragraphs.single;
  WordZotero.insertCitation(paragraph, _citation('alpha', citationText));
  paragraph.inlines.add(WmlRun(text: ' after'));
  return document;
}

WmlDocument _twoFields() {
  final document = _document();
  final second = WmlParagraph(inlines: [WmlRun(text: 'Other source ')]);
  WordZotero.insertCitation(second, _citation('beta', '(Beta)'));
  second.inlines.add(WmlRun(text: ' end'));
  document.sections.single.blocks.add(second);
  return document;
}

WmlDocument _bibliographyDocument({String? html}) {
  final document = WmlDocument.empty(text: 'Introduction');
  document.sections.single.blocks.add(
    WmlParagraph(inlines: [WmlRun(text: 'Continue writing')]),
  );
  const id = 'bibliography-fixture';
  final session = WordZoteroCitingSession(
    document: document,
    documentId: id,
    insertionParagraph: document.paragraphs.first,
    insertionOffset: document.paragraphs.first.text.length,
  );
  final field =
      session.handle('Document.insertField', [id, 'Http', 0])!
          as Map<String, Object?>;
  session.handle('Field.setCode', [
    id,
    field['id'],
    'BIBL {"uncited":[],"omitted":[],"custom":[]} CSL_BIBLIOGRAPHY',
  ]);
  session.handle('Field.setText', [
    id,
    field['id'],
    html ??
        '<div class="csl-entry">Alpha Book.</div>'
            '<div class="csl-entry">Beta Book.</div>',
    true,
  ]);
  session.handle('Document.complete', [id]);
  session.prepareReview();
  session.apply();
  return document;
}

typedef _Step = Map<String, Object?> Function(_Desktop desktop);

final class _Desktop {
  _Desktop(this.steps);

  final List<_Step> steps;
  final pauses = <int, Completer<void>>{};
  final replies = <Object?>[];
  final fieldIds = <String>[];
  String documentId = '';
  String insertedFieldId = '';
  int index = 0;

  Map<String, Object?> message(String name, List<Object?> arguments) => {
    'command': name,
    'arguments': arguments,
  };

  Future<ZoteroHttpResponse> send(ZoteroHttpRequest request) async {
    expect(request.method, 'POST');
    expect(request.uri.host, 'localhost');
    expect(request.uri.port, 23119);
    final Object? decoded = jsonDecode(request.body!);
    if (index == 0) {
      final start = decoded! as Map<String, Object?>;
      documentId = start['docId']! as String;
    } else {
      replies.add(decoded);
      if (decoded case {'id': final String id}) insertedFieldId = id;
      if (decoded case final List<Object?> fields) {
        fieldIds
          ..clear()
          ..addAll(
            fields.map(
              (field) => (field! as Map<String, Object?>)['id']! as String,
            ),
          );
      }
    }
    expect(index, lessThan(steps.length));
    await pauses[index]?.future;
    return ZoteroHttpResponse(
      statusCode: 200,
      headers: const {},
      body: jsonEncode(steps[index++](this)),
    );
  }
}

List<_Step> _selectionScript({
  String prompt = 'Review the selected reference.',
  int buttons = 3,
  String? stagedText,
}) => [
  (d) => d.message('Application.getActiveDocument', []),
  (d) => d.message('Document.getFields', [d.documentId, 'Http']),
  if (stagedText != null) ...[
    (d) => d.message('Field.setCode', [
      d.documentId,
      d.fieldIds.first,
      _code('alpha', stagedText),
    ]),
    (d) => d.message('Field.setText', [
      d.documentId,
      d.fieldIds.first,
      stagedText,
      false,
    ]),
  ],
  (d) => d.message('Field.select', [d.documentId, d.fieldIds.first]),
  (d) => d.message('Document.displayAlert', [d.documentId, prompt, 1, buttons]),
  (d) => d.message('Document.complete', [d.documentId]),
];

List<_Step> _selectionThenComplete() => [
  (d) => d.message('Application.getActiveDocument', []),
  (d) => d.message('Document.getFields', [d.documentId, 'Http']),
  (d) => d.message('Field.select', [d.documentId, d.fieldIds.first]),
  (d) => d.message('Document.complete', [d.documentId]),
];

List<int> _selection(WordEditorController controller) => [
  controller.caret.paragraphIndex,
  controller.caret.logicalIndex,
  controller.caret.selectionAnchorParagraph,
  controller.caret.selectionAnchor,
];

Future<void> _pump(WidgetTester tester) async {
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<WordEditorController> _mount(
  WidgetTester tester,
  _Desktop desktop, {
  WmlDocument? document,
  ZoteroCitingCommand command = ZoteroCitingCommand.refresh,
  bool closeAfterCommand = true,
  bool Function()? isCurrent,
  Size size = const Size(1100, 900),
  double textScale = 1,
  ({int start, int end}) selection = (start: 5, end: 2),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final controller = WordEditorController(document: document ?? _document());
  controller.proofing.enabled = false;
  controller.caret
    ..logicalIndex = selection.end
    ..selectionAnchor = selection.start
    ..selectionAnchorParagraph = 0;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    if (!controller.isDisposed) controller.dispose();
    await tester.pump();
  });
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            key: _runKey,
            onPressed: () => showWordZoteroDialog(
              context,
              controller: controller,
              localTransport: desktop.send,
              initialCommand: command,
              closeAfterCommand: closeAfterCommand,
              isCurrent: isCurrent,
            ),
            child: const Text('Run Zotero'),
          ),
        ),
      ),
    ),
  );
  return controller;
}

Future<void> _run(WidgetTester tester) async {
  await tester.tap(find.byKey(_runKey));
  await _pump(tester);
}

Finder get _prompt => find.byWidgetPredicate(
  (widget) =>
      widget is AlertDialog &&
      widget.title is Text &&
      (widget.title! as Text).data == 'Zotero',
);

Finder _inPrompt(Key key) =>
    find.descendant(of: _prompt, matching: find.byKey(key));

String _excerpt(WidgetTester tester) =>
    tester.widget<SelectableText>(_inPrompt(_textKey)).textSpan!.toPlainText();

Future<void> _answer(WidgetTester tester, String label) async {
  final button = find.descendant(of: _prompt, matching: find.text(label));
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
  await _pump(tester);
}

void _expectUnchanged(
  WordEditorController controller,
  List<int> selection,
  String text,
) {
  expect(_selection(controller), selection);
  expect(controller.document.paragraphs.map((p) => p.text).join('\n'), text);
  expect(controller.canUndo, isFalse);
  expect(controller.canRedo, isFalse);
  expect(controller.isDirty, isFalse);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);

  testWidgets(
    'selected alert shows original source until the staged update completes',
    (tester) async {
      final desktop = _Desktop(
        _selectionScript(stagedText: '(Unpublished replacement)'),
      );
      final controller = await _mount(tester, desktop);
      final selection = _selection(controller);
      await _run(tester);

      expect(_prompt, findsOneWidget);
      expect(_inPrompt(_contextKey), findsOneWidget);
      expect(find.text('Citation selected by Zotero'), findsOneWidget);
      expect(
        tester.widget<Text>(_inPrompt(_locationKey)).data,
        'Document body · paragraph 1',
      );
      expect(_excerpt(tester), 'Before (Alpha) after');
      expect(_excerpt(tester), isNot(contains('Unpublished')));
      expect(controller.zoteroFieldContext!.sourceText, '(Alpha)');
      _expectUnchanged(controller, selection, 'Before (Alpha) after');

      await _answer(tester, 'Yes');
      expect(desktop.replies.last, 2);
      expect(
        controller.document.paragraphs.single.text,
        'Before (Unpublished replacement) after',
      );
      expect(controller.zoteroFieldContext, isNull);
      expect(find.byKey(_contextKey), findsNothing);
      expect(find.byKey(_directKey), findsNothing);
      expect(_selection(controller), selection);
      expect(controller.canUndo, isTrue);
      controller.undo();
      expect(
        controller.document.paragraphs.single.text,
        'Before (Alpha) after',
      );
      expect(_selection(controller), selection);
      expect(controller.canUndo, isFalse);
    },
  );

  for (final (buttons, label, code) in [
    (0, 'OK', 1),
    (1, 'Cancel', 0),
    (1, 'OK', 1),
    (2, 'No', 0),
    (2, 'Yes', 1),
    (3, 'Cancel', 0),
    (3, 'No', 1),
    (3, 'Yes', 2),
  ]) {
    testWidgets(
      'selected context preserves alert set $buttons $label response $code',
      (tester) async {
        final desktop = _Desktop(_selectionScript(buttons: buttons));
        final controller = await _mount(tester, desktop);
        final selection = _selection(controller);
        await _run(tester);
        expect(_excerpt(tester), 'Before (Alpha) after');
        _expectUnchanged(controller, selection, 'Before (Alpha) after');
        await _answer(tester, label);
        expect(desktop.replies.last, code);
        expect(controller.zoteroFieldContext, isNull);
        expect(find.byKey(_contextKey), findsNothing);
        _expectUnchanged(controller, selection, 'Before (Alpha) after');
      },
    );
  }

  testWidgets(
    'successive native prompts replace context with the newly selected field',
    (tester) async {
      final desktop = _Desktop([
        (d) => d.message('Application.getActiveDocument', []),
        (d) => d.message('Document.getFields', [d.documentId, 'Http']),
        (d) => d.message('Field.select', [d.documentId, d.fieldIds[0]]),
        (d) => d.message('Document.displayAlert', [
          d.documentId,
          'First source?',
          1,
          0,
        ]),
        (d) => d.message('Field.select', [d.documentId, d.fieldIds[1]]),
        (d) => d.message('Document.displayAlert', [
          d.documentId,
          'Second source?',
          1,
          0,
        ]),
        (d) => d.message('Document.complete', [d.documentId]),
      ]);
      final controller = await _mount(tester, desktop, document: _twoFields());
      final selection = _selection(controller);
      await _run(tester);
      expect(_excerpt(tester), 'Before (Alpha) after');
      await _answer(tester, 'OK');
      expect(find.text('Second source?'), findsOneWidget);
      expect(_excerpt(tester), 'Other source (Beta) end');
      expect(
        tester.widget<Text>(_inPrompt(_locationKey)).data,
        'Document body · paragraph 2',
      );
      expect(controller.zoteroFieldContext!.fieldId, desktop.fieldIds[1]);
      await _answer(tester, 'OK');
      expect(controller.zoteroFieldContext, isNull);
      _expectUnchanged(
        controller,
        selection,
        'Before (Alpha) after\nOther source (Beta) end',
      );
    },
  );

  testWidgets(
    'cancelling a selected operation preserves writing selection and history',
    (tester) async {
      final gate = Completer<void>();
      final desktop = _Desktop(_selectionThenComplete())..pauses[3] = gate;
      final controller = await _mount(tester, desktop);
      final selection = _selection(controller);
      await _run(tester);
      expect(find.byKey(_contextKey), findsOneWidget);
      expect(controller.zoteroFieldContext!.sourceText, '(Alpha)');
      await tester.tap(find.text('Cancel operation'));
      await _pump(tester);
      expect(find.text('Cancelling…'), findsOneWidget);
      _expectUnchanged(controller, selection, 'Before (Alpha) after');
      gate.complete();
      await _pump(tester);
      expect(controller.zoteroFieldContext, isNull);
      expect(find.byKey(_directKey), findsNothing);
      _expectUnchanged(controller, selection, 'Before (Alpha) after');
    },
  );

  testWidgets(
    'a stale writing target hides context and rejects the detached result',
    (tester) async {
      final gate = Completer<void>();
      final desktop = _Desktop(
        _selectionScript(stagedText: '(Stale replacement)'),
      )..pauses[5] = gate;
      final controller = await _mount(tester, desktop);
      await _run(tester);
      expect(find.byKey(_contextKey), findsOneWidget);
      controller.caret
        ..logicalIndex = 1
        ..collapseSelection();
      controller.refreshView();
      await _pump(tester);
      expect(controller.zoteroFieldContext, isNull);
      expect(find.byKey(_contextKey), findsNothing);
      gate.complete();
      await _pump(tester);
      expect(
        find.textContaining('could not be applied safely'),
        findsOneWidget,
      );
      expect(controller.zoteroFieldContext, isNull);
      expect(controller.caret.logicalIndex, 1);
      expect(
        controller.document.paragraphs.single.text,
        'Before (Alpha) after',
      );
      expect(controller.canUndo, isFalse);
    },
  );

  testWidgets(
    'invalidated host hides selected context before the pending reply returns',
    (tester) async {
      var current = true;
      final gate = Completer<void>();
      final desktop = _Desktop(_selectionThenComplete())..pauses[3] = gate;
      final controller = await _mount(
        tester,
        desktop,
        isCurrent: () => current,
      );
      final selection = _selection(controller);
      await _run(tester);
      expect(find.byKey(_contextKey), findsOneWidget);
      current = false;
      controller.refreshView();
      await _pump(tester);
      expect(find.byKey(_contextKey), findsNothing);
      gate.complete();
      await _pump(tester);
      expect(controller.zoteroFieldContext, isNull);
      _expectUnchanged(controller, selection, 'Before (Alpha) after');
    },
  );

  testWidgets('disposing the host clears context before native completion', (
    tester,
  ) async {
    final gate = Completer<void>();
    final desktop = _Desktop(_selectionThenComplete())..pauses[3] = gate;
    final controller = await _mount(tester, desktop);
    final selection = _selection(controller);
    await _run(tester);
    expect(controller.zoteroFieldContext, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(controller.zoteroFieldContext, isNull);
    _expectUnchanged(controller, selection, 'Before (Alpha) after');
    controller.dispose();
    gate.complete();
    await _pump(tester);
    expect(controller.zoteroFieldContext, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'selected staged insertion explains its pending position without exposing staged text',
    (tester) async {
      final desktop = _Desktop([
        (d) => d.message('Application.getActiveDocument', []),
        (d) => d.message('Document.insertField', [d.documentId, 'Http', 0]),
        (d) => d.message('Field.setCode', [
          d.documentId,
          d.insertedFieldId,
          _code('new', '(Private draft)'),
        ]),
        (d) => d.message('Field.setText', [
          d.documentId,
          d.insertedFieldId,
          '(Private draft)',
          false,
        ]),
        (d) => d.message('Field.select', [d.documentId, d.insertedFieldId]),
        (d) => d.message('Document.displayAlert', [
          d.documentId,
          'Keep this insertion?',
          1,
          1,
        ]),
        (d) => d.message('Field.delete', [d.documentId, d.insertedFieldId]),
        (d) => d.message('Document.complete', [d.documentId]),
      ]);
      final controller = await _mount(
        tester,
        desktop,
        document: WmlDocument.empty(text: 'Write here'),
        command: ZoteroCitingCommand.addEditCitation,
        selection: (start: 5, end: 5),
      );
      final selection = _selection(controller);
      await _run(tester);
      expect(_inPrompt(_contextKey), findsOneWidget);
      expect(_inPrompt(_pendingKey), findsOneWidget);
      expect(_inPrompt(_textKey), findsNothing);
      expect(find.textContaining('Private draft'), findsNothing);
      expect(
        tester.widget<Text>(_inPrompt(_pendingKey)).data,
        contains('preparing a new reference'),
      );
      final context = controller.zoteroFieldContext!;
      expect(context.source, WordZoteroFieldSelectionSource.stagedInsertion);
      expect(context.sourceField, isNull);
      expect(context.sourceText, isNull);
      expect(context.sourceRanges, isEmpty);
      expect(controller.zoteroFields, isEmpty);
      _expectUnchanged(controller, selection, 'Write here');
      await _answer(tester, 'Cancel');
      expect(desktop.replies, contains(0));
      expect(controller.zoteroFieldContext, isNull);
      expect(controller.zoteroFields, isEmpty);
      _expectUnchanged(controller, selection, 'Write here');
    },
  );

  for (final endnote in [false, true]) {
    testWidgets(
      'selected ${endnote ? 'endnote' : 'footnote'} context preserves the active Notes selection',
      (tester) async {
        final document = WmlDocument.empty(text: 'Body continues');
        final note = WordNotes.insert(
          document,
          document.paragraphs.single,
          text: 'Note before ',
          endnote: endnote,
        );
        WordZotero.insertCitation(
          note.paragraphs.single,
          _citation('note', '(Note source)', noteIndex: 1),
        );
        note.paragraphs.single.inlines.add(WmlRun(text: ' after'));
        final desktop = _Desktop(_selectionScript(buttons: 1));
        final controller = await _mount(tester, desktop, document: document);
        controller.setNoteEditingTarget(
          note,
          const TextSelection(baseOffset: 5, extentOffset: 1),
        );
        final noteTarget = controller.noteEditingTarget;
        final bodySelection = _selection(controller);
        await _run(tester);
        expect(
          tester.widget<Text>(_inPrompt(_locationKey)).data,
          '${endnote ? 'Endnote' : 'Footnote'} · paragraph 1',
        );
        expect(_excerpt(tester), contains('Note before (Note source) after'));
        expect(controller.zoteroFieldContext!.sourceNote, same(note));
        expect(controller.noteEditingTarget, noteTarget);
        expect(_selection(controller), bodySelection);
        expect(controller.canUndo, isFalse);
        await _answer(tester, 'Cancel');
        expect(controller.zoteroFieldContext, isNull);
        expect(controller.noteEditingTarget, noteTarget);
        expect(_selection(controller), bodySelection);
        expect(controller.canUndo, isFalse);
      },
    );
  }

  testWidgets(
    'multipart bibliography prompt shows complete original entries and location',
    (tester) async {
      final document = _bibliographyDocument();
      final desktop = _Desktop(_selectionScript(buttons: 0));
      final controller = await _mount(tester, desktop, document: document);
      final text = document.paragraphs.map((p) => p.text).join('\n');
      final selection = _selection(controller);
      await _run(tester);
      expect(find.text('Bibliography selected by Zotero'), findsOneWidget);
      expect(
        tester.widget<Text>(_inPrompt(_locationKey)).data,
        'Document body · paragraph 2 · 2 paragraphs',
      );
      expect(_excerpt(tester), 'Alpha Book.\nBeta Book.');
      expect(controller.zoteroFieldContext!.sourceRanges, hasLength(2));
      _expectUnchanged(controller, selection, text);
      await _answer(tester, 'OK');
      expect(controller.zoteroFieldContext, isNull);
      _expectUnchanged(controller, selection, text);
    },
  );

  testWidgets(
    'compact progress and selected alert remain usable on a narrow scaled display',
    (tester) async {
      final longText = '(${List.filled(120, 'Long source context').join(' ')})';
      final gate = Completer<void>();
      final desktop = _Desktop(_selectionScript(buttons: 1))..pauses[3] = gate;
      final controller = await _mount(
        tester,
        desktop,
        document: _document(citationText: longText),
        size: const Size(360, 640),
        textScale: 2,
      );
      final selection = _selection(controller);
      await _run(tester);
      expect(find.byKey(_directKey), findsOneWidget);
      expect(find.byKey(_contextKey), findsOneWidget);
      expect(tester.takeException(), isNull);
      final compactBounds = tester.getRect(find.byKey(_contextKey));
      expect(compactBounds.left, greaterThanOrEqualTo(0));
      expect(compactBounds.right, lessThanOrEqualTo(360));
      gate.complete();
      await _pump(tester);
      expect(_prompt, findsOneWidget);
      expect(_inPrompt(_contextKey), findsOneWidget);
      expect(_excerpt(tester), contains('Long source context'));
      expect(
        find.text('Excerpt of the current document reference.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await _answer(tester, 'Cancel');
      expect(controller.zoteroFieldContext, isNull);
      _expectUnchanged(controller, selection, 'Before $longText after');
      expect(tester.takeException(), isNull);
    },
  );

  for (final cancelPending in [false, true]) {
    testWidgets(
      'regular references workspace supports ${cancelPending ? 'operation' : 'native alert'} cancellation in a short scaled window',
      (tester) async {
        final layoutErrors = <FlutterErrorDetails>[];
        final reportError = FlutterError.onError;
        FlutterError.onError = (details) {
          layoutErrors.add(details);
          reportError?.call(details);
        };
        addTearDown(() => FlutterError.onError = reportError);
        final html = List.generate(
          12,
          (index) =>
              '<div class="csl-entry">Reference ${index + 1}. '
              '${List.filled(16, 'Long bibliography entry with source details.').join(' ')}'
              '</div>',
        ).join();
        final document = _bibliographyDocument(html: html);
        final gate = Completer<void>();
        addTearDown(() async {
          if (!gate.isCompleted) gate.complete();
          await _pump(tester);
        });
        final desktop = _Desktop(_selectionScript(buttons: 1))
          ..pauses[3] = gate;
        final controller = await _mount(
          tester,
          desktop,
          document: document,
          closeAfterCommand: false,
          size: const Size(700, 440),
          textScale: 2,
        );
        final selection = _selection(controller);
        final originalText = document.paragraphs.map((p) => p.text).join('\n');
        await _run(tester);

        expect(find.byKey(_directKey), findsNothing);
        expect(find.text('Zotero references'), findsOneWidget);
        expect(find.byKey(_contextKey), findsOneWidget);
        expect(controller.zoteroFieldContext!.sourceRanges, hasLength(12));
        expect(
          tester.takeException(),
          isNull,
          reason: [
            ...layoutErrors.map((error) => error.toString()),
            if (layoutErrors.isNotEmpty)
              ...tester
                  .renderObject<RenderFlex>(
                    find
                        .ancestor(
                          of: find.text('Zotero references'),
                          matching: find.byType(Column),
                        )
                        .first,
                  )
                  .debugDescribeChildren()
                  .map((node) {
                    final child = node.value! as RenderBox;
                    return '${child.runtimeType}: ${child.size}; ${child.debugCreator}';
                  }),
          ].join('\n'),
        );

        // Both the whole context and its long excerpt must remain reachable in
        // the fixed-height workspace, independently of the direct-mode dialog.
        await tester.ensureVisible(find.byKey(_textKey));
        await _pump(tester);
        final excerptScroll = find
            .ancestor(
              of: find.byKey(_textKey),
              matching: find.byType(Scrollable),
            )
            .first;
        final position = tester.state<ScrollableState>(excerptScroll).position;
        expect(position.maxScrollExtent, greaterThan(0));
        final offsetBefore = position.pixels;
        await tester.drag(excerptScroll, const Offset(0, -80));
        await _pump(tester);
        expect(position.pixels, greaterThan(offsetBefore));
        expect(
          tester
              .widget<SelectableText>(find.byKey(_textKey))
              .textSpan!
              .toPlainText(),
          contains('Reference 1.'),
        );
        expect(tester.takeException(), isNull);

        final cancel = find.widgetWithText(TextButton, 'Cancel operation');
        expect(tester.widget<TextButton>(cancel).onPressed, isNotNull);
        await tester.ensureVisible(cancel);
        await _pump(tester);
        expect(cancel.hitTestable(), findsOneWidget);
        _expectUnchanged(controller, selection, originalText);

        if (cancelPending) {
          await tester.tap(cancel);
          await _pump(tester);
          gate.complete();
          await _pump(tester);
          expect(_prompt, findsNothing);
        } else {
          gate.complete();
          await _pump(tester);
          expect(_prompt, findsOneWidget);
          expect(_inPrompt(_contextKey), findsOneWidget);
          expect(_excerpt(tester), contains('Reference 1.'));
          expect(tester.takeException(), isNull);
          await _answer(tester, 'Cancel');
          expect(desktop.replies.last, 0);
        }

        expect(controller.zoteroFieldContext, isNull);
        expect(find.byKey(_contextKey), findsNothing);
        expect(find.text('Zotero references'), findsOneWidget);
        expect(find.text('Cancel operation'), findsNothing);
        expect(
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is IconButton && widget.tooltip == 'Close Zotero',
                ),
              )
              .onPressed,
          isNotNull,
        );
        _expectUnchanged(controller, selection, originalText);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
