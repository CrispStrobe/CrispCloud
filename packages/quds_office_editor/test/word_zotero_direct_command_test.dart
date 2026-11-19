import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _runKey = ValueKey<String>('run-direct-zotero-command');
const _directKey = ValueKey<String>('zotero-direct-command');
const _editorKey = ValueKey<String>('direct-zotero-editor');

ZoteroCitation _citation(String text, {String id = 'direct-citation'}) =>
    ZoteroCitation(
      citationId: id,
      plainCitation: text,
      items: [
        ZoteroCitationItem.fromCsl(
          itemData: {
            'id': 'source',
            'type': 'book',
            'title': 'Research source',
          },
          uris: ['http://zotero.org/users/42/items/ABCD1234'],
        ),
      ],
    );

String _code(String text, {String id = 'direct-citation'}) =>
    'ITEM CSL_CITATION ${jsonEncode(_citation(text, id: id).toJson())}';

String _data() => jsonEncode({
  'dataVersion': 4,
  'sessionID': 'direct-test',
  'zoteroVersion': '10.0',
  'style': {'styleID': 'http://www.zotero.org/styles/apa', 'locale': 'de-DE'},
  'prefs': {'fieldType': 'Http', 'noteType': 0},
});

typedef _Step = Map<String, Object?> Function(_Desktop desktop);

class _Desktop {
  _Desktop(this.steps, {this.statusCode = 200});

  final List<_Step> steps;
  final int statusCode;
  final requests = <ZoteroHttpRequest>[];
  final replies = <Object?>[];
  Completer<void>? firstResponse;
  String documentId = '';
  String fieldId = '';
  String command = '';
  int index = 0;

  Map<String, Object?> message(String name, List<Object?> args) => {
    'command': name,
    'arguments': args,
  };

  Future<ZoteroHttpResponse> send(ZoteroHttpRequest request) async {
    requests.add(request);
    expect(request.method, 'POST');
    expect(request.uri.host, 'localhost');
    expect(request.uri.port, 23119);
    final Object? decoded = jsonDecode(request.body!);
    if (index == 0) {
      final start = decoded! as Map<String, Object?>;
      documentId = start['docId']! as String;
      command = start['command']! as String;
      await firstResponse?.future;
    } else {
      replies.add(decoded);
      if (decoded case {'id': final String id}) fieldId = id;
      if (decoded case [final Map<String, Object?> first, ...]) {
        if (first case {'id': final String id}) fieldId = id;
      }
    }
    if (statusCode != 200) {
      index++;
      return ZoteroHttpResponse(
        statusCode: statusCode,
        headers: const {},
        body: 'Unavailable',
      );
    }
    expect(index, lessThan(steps.length));
    return ZoteroHttpResponse(
      statusCode: 200,
      headers: const {},
      body: jsonEncode(steps[index++](this)),
    );
  }
}

List<_Step> _noChange() => [
  (d) => d.message('Application.getActiveDocument', []),
  (d) => d.message('Document.complete', [d.documentId]),
];

List<_Step> _insert({String html = '<i>(Source)</i>'}) => [
  (d) => d.message('Application.getActiveDocument', []),
  (d) => d.message('Document.getDocumentData', [d.documentId]),
  (d) => d.message('Document.setDocumentData', [d.documentId, _data()]),
  (d) => d.message('Document.insertField', [d.documentId, 'Http', 0]),
  (d) => d.message('Field.setCode', [
    d.documentId,
    d.fieldId,
    _code(ZoteroFormattedText.fromHtml(html).plainText),
  ]),
  (d) => d.message('Field.setText', [d.documentId, d.fieldId, html, true]),
  (d) => d.message('Document.complete', [d.documentId]),
];

typedef _Fixture = ({
  WordEditorController controller,
  FocusNode bodyFocus,
  GlobalKey<NavigatorState> navigator,
});

Future<void> _pump(WidgetTester tester) async {
  // A live editor keeps its caret ticker active; await bounded route frames.
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<_Fixture> _mount(
  WidgetTester tester, {
  _Desktop? desktop,
  WmlDocument? document,
  ZoteroCitingCommand command = ZoteroCitingCommand.addEditCitation,
  bool closeAfterCommand = true,
  bool showNotes = false,
  ({int start, int end})? selection,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1300, 1000);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final controller = WordEditorController(
    document: document ?? WmlDocument.empty(text: 'Before after'),
    config: OfficeSurfaceConfig(showNotesPane: showNotes),
  );
  controller.proofing.enabled = false;
  controller.caret
    ..logicalIndex = selection?.end ?? 7
    ..collapseSelection();
  if (selection != null) {
    controller.caret
      ..selectionAnchor = selection.start
      ..selectionAnchorParagraph = 0;
  }
  final bodyFocus = FocusNode(debugLabel: 'direct-command-body');
  final navigator = GlobalKey<NavigatorState>();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    if (!controller.isDisposed) controller.dispose();
    bodyFocus.dispose();
    await tester.pump();
  });
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      home: Scaffold(
        body: Builder(
          builder: (context) => Column(
            children: [
              FilledButton(
                key: _runKey,
                onPressed: () => showWordZoteroDialog(
                  context,
                  controller: controller,
                  localTransport: desktop?.send,
                  initialCommand: command,
                  closeAfterCommand: closeAfterCommand,
                ),
                child: const Text('Run Zotero command'),
              ),
              Expanded(
                child: QudsWordEditor(
                  key: _editorKey,
                  controller: controller,
                  focusNode: bodyFocus,
                  enableLiveProofing: false,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  bodyFocus.requestFocus();
  await _pump(tester);
  return (controller: controller, bodyFocus: bodyFocus, navigator: navigator);
}

Future<void> _run(WidgetTester tester) async {
  await tester.tap(find.byKey(_runKey));
  await _pump(tester);
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await _pump(tester);
}

void _expectReturned(_Fixture fixture) {
  expect(find.byKey(_directKey), findsNothing);
  expect(fixture.bodyFocus.hasPrimaryFocus, isTrue);
  expect(fixture.controller.input.isAttached, isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);

  testWidgets('direct mode needs a command before opening a dialog', (
    tester,
  ) async {
    final fixture = await _mount(tester);
    await expectLater(
      showWordZoteroDialog(
        tester.element(find.byKey(_runKey)),
        controller: fixture.controller,
        closeAfterCommand: true,
      ),
      throwsArgumentError,
    );
    expect(find.byType(AlertDialog), findsNothing);
    expect(fixture.controller.canUndo, isFalse);
  });

  testWidgets(
    'body composition prevents modal focus changes and native requests',
    (tester) async {
      final desktop = _Desktop(_noChange());
      final fixture = await _mount(tester, desktop: desktop);
      const composing = TextEditingValue(
        text: 'Before after',
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange(start: 0, end: 6),
      );
      fixture.controller.input.setValue(composing);
      final revision = fixture.controller.contentRevision;
      var focusChanges = 0;
      fixture.bodyFocus.addListener(() => focusChanges++);
      tester.widget<FilledButton>(find.byKey(_runKey)).onPressed!();
      await _pump(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(desktop.requests, isEmpty);
      expect(fixture.bodyFocus.hasPrimaryFocus, isTrue);
      expect(focusChanges, 0);
      expect(fixture.controller.input.composing, composing.composing);
      expect(fixture.controller.contentRevision, revision);
      expect(fixture.controller.canUndo, isFalse);
      expect(
        find.text('Finish the current text composition before using Zotero.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'composition starting during native work remains intact on return',
    (tester) async {
      final desktop = _Desktop(_noChange())..firstResponse = Completer<void>();
      final fixture = await _mount(tester, desktop: desktop);
      await _run(tester);
      fixture.controller.input.setValue(
        const TextEditingValue(
          text: 'Before after',
          selection: TextSelection.collapsed(offset: 3),
          composing: TextRange(start: 0, end: 6),
        ),
      );
      desktop.firstResponse!.complete();
      await _pump(tester);
      expect(find.byKey(_directKey), findsOneWidget);
      expect(
        find.textContaining('could not be applied safely'),
        findsOneWidget,
      );
      expect(fixture.controller.canUndo, isFalse);
      await _tap(tester, 'Return to document');
      expect(
        fixture.controller.input.composing,
        const TextRange(start: 0, end: 6),
      );
      expect(
        fixture.controller.document.paragraphs.single.text,
        'Before after',
      );
      expect(fixture.controller.canUndo, isFalse);
    },
  );

  testWidgets('native citation returns to writing with one undo operation', (
    tester,
  ) async {
    final desktop = _Desktop(_insert());
    final fixture = await _mount(tester, desktop: desktop);
    await _run(tester);
    expect(desktop.command, 'addEditCitation');
    expect(desktop.requests, hasLength(7));
    expect(fixture.controller.zoteroFields.single.cachedText, '(Source)');
    _expectReturned(fixture);
    fixture.controller.undo();
    expect(fixture.controller.document.paragraphs.single.text, 'Before after');
    expect(fixture.controller.zoteroFields, isEmpty);
    expect(fixture.controller.canUndo, isFalse);
  });

  testWidgets('direct edit updates the selected field and returns focus', (
    tester,
  ) async {
    final document = WmlDocument.empty(text: 'Before ');
    WordZotero.insertCitation(
      document.paragraphs.single,
      _citation('(Old)', id: 'existing'),
    );
    final desktop = _Desktop([
      (d) => d.message('Application.getActiveDocument', []),
      (d) => d.message('Document.cursorInField', [d.documentId, 'Http']),
      (d) => d.message('Field.setCode', [
        d.documentId,
        d.fieldId,
        _code('(Updated)', id: 'existing'),
      ]),
      (d) => d.message('Field.setText', [
        d.documentId,
        d.fieldId,
        '<i>(Updated)</i>',
        true,
      ]),
      (d) => d.message('Document.complete', [d.documentId]),
    ]);
    final fixture = await _mount(
      tester,
      desktop: desktop,
      document: document,
      selection: (start: 7, end: 12),
    );
    await _run(tester);
    expect(desktop.requests, hasLength(5));
    expect(fixture.controller.zoteroFields.single.cachedText, '(Updated)');
    expect(
      fixture.controller.zoteroFields.single.citation!.citationId,
      'existing',
    );
    _expectReturned(fixture);
    fixture.controller.undo();
    expect(fixture.controller.zoteroFields.single.cachedText, '(Old)');
    expect(fixture.controller.caret.selectionAnchor, 7);
    expect(fixture.controller.caret.logicalIndex, 12);
  });

  testWidgets('refresh changes existing text and returns to the document', (
    tester,
  ) async {
    final document = WmlDocument.empty(text: 'Before ');
    WordZotero.insertCitation(document.paragraphs.single, _citation('(Old)'));
    final desktop = _Desktop([
      (d) => d.message('Application.getActiveDocument', []),
      (d) => d.message('Document.getFields', [d.documentId, 'Http']),
      (d) => d.message('Field.setText', [
        d.documentId,
        d.fieldId,
        '(Refreshed)',
        false,
      ]),
      (d) => d.message('Document.complete', [d.documentId]),
    ]);
    final fixture = await _mount(
      tester,
      desktop: desktop,
      document: document,
      command: ZoteroCitingCommand.refresh,
    );
    await _run(tester);
    expect(desktop.command, 'refresh');
    expect(fixture.controller.zoteroFields.single.cachedText, '(Refreshed)');
    _expectReturned(fixture);
    fixture.controller.undo();
    expect(fixture.controller.zoteroFields.single.cachedText, '(Old)');
  });

  for (final command in [
    ZoteroCitingCommand.addEditCitation,
    ZoteroCitingCommand.refresh,
    ZoteroCitingCommand.setDocPrefs,
    ZoteroCitingCommand.addEditBibliography,
  ]) {
    testWidgets('unchanged ${command.name} returns without dirtying the file', (
      tester,
    ) async {
      final desktop = _Desktop(_noChange());
      final fixture = await _mount(tester, desktop: desktop, command: command);
      await _run(tester);
      expect(desktop.command, command.name);
      expect(desktop.requests, hasLength(2));
      expect(fixture.controller.isDirty, isFalse);
      expect(fixture.controller.canUndo, isFalse);
      _expectReturned(fixture);
    });
  }

  testWidgets('chosen document preferences persist before returning', (
    tester,
  ) async {
    final desktop = _Desktop([
      (d) => d.message('Application.getActiveDocument', []),
      (d) => d.message('Document.setDocumentData', [d.documentId, _data()]),
      (d) => d.message('Document.complete', [d.documentId]),
    ]);
    final fixture = await _mount(
      tester,
      desktop: desktop,
      command: ZoteroCitingCommand.setDocPrefs,
    );
    await _run(tester);
    expect(desktop.command, 'setDocPrefs');
    expect(
      WordZoteroDocumentData.read(fixture.controller.document),
      contains('de-DE'),
    );
    _expectReturned(fixture);
    fixture.controller.undo();
    expect(WordZoteroDocumentData.read(fixture.controller.document), isEmpty);
  });

  testWidgets('an unavailable host shows a recoverable error', (tester) async {
    final fixture = await _mount(tester);
    await _run(tester);
    expect(find.byKey(_directKey), findsOneWidget);
    expect(find.textContaining('unavailable in this host'), findsOneWidget);
    expect(fixture.controller.isDirty, isFalse);
    expect(fixture.bodyFocus.hasPrimaryFocus, isFalse);
    await _tap(tester, 'Return to document');
    _expectReturned(fixture);
  });

  testWidgets('unavailable annotation command keeps version guidance and data', (
    tester,
  ) async {
    final desktop = _Desktop([], statusCode: 500);
    final fixture = await _mount(
      tester,
      desktop: desktop,
      command: ZoteroCitingCommand.addAnnotation,
    );
    await _run(tester);
    expect(find.byKey(_directKey), findsOneWidget);
    expect(find.text('Add annotation from Zotero'), findsOneWidget);
    expect(
      find.text(
        'Requires Zotero 9 or later. Choose text annotations; image and ink annotations are not yet supported.',
      ),
      findsOneWidget,
    );
    expect(desktop.command, 'addAnnotation');
    expect(desktop.requests, hasLength(1));
    expect(fixture.controller.document.paragraphs.single.text, 'Before after');
    expect(fixture.controller.isDirty, isFalse);
    expect(fixture.controller.canUndo, isFalse);
    await _pump(tester);
    expect(desktop.requests, hasLength(1));
    await _tap(tester, 'Return to document');
    _expectReturned(fixture);
  });

  testWidgets(
    'busy desktop errors stay visible and never restart the request',
    (tester) async {
      final desktop = _Desktop([], statusCode: 503);
      final fixture = await _mount(tester, desktop: desktop);
      await _run(tester);
      expect(find.byKey(_directKey), findsOneWidget);
      expect(
        find.textContaining('already processing a document'),
        findsOneWidget,
      );
      expect(desktop.requests, hasLength(1));
      expect(fixture.controller.canUndo, isFalse);
      await _pump(tester);
      expect(desktop.requests, hasLength(1));
      await _tap(tester, 'Return to document');
      _expectReturned(fixture);
      expect(desktop.requests, hasLength(1));
    },
  );

  for (final accept in [false, true]) {
    testWidgets(
      'formatting review ${accept ? 'applies' : 'discards'} then returns',
      (tester) async {
        final desktop = _Desktop(
          _insert(
            html: '<span style="font-variant: all-small-caps">Title</span>',
          ),
        );
        final fixture = await _mount(tester, desktop: desktop);
        await _run(tester);
        expect(find.text('Review Zotero formatting'), findsOneWidget);
        expect(fixture.controller.zoteroFields, isEmpty);
        expect(fixture.controller.isDirty, isFalse);
        expect(fixture.bodyFocus.hasPrimaryFocus, isFalse);
        await _tap(tester, accept ? 'Apply Zotero result' : 'Cancel');
        expect(fixture.controller.zoteroFields, hasLength(accept ? 1 : 0));
        expect(fixture.controller.canUndo, accept);
        expect(desktop.requests, hasLength(7));
        _expectReturned(fixture);
      },
    );
  }

  testWidgets(
    'a stale formatting target stays open without applying the result',
    (tester) async {
      final desktop = _Desktop(
        _insert(
          html: '<span style="font-variant: all-small-caps">Title</span>',
        ),
      );
      final fixture = await _mount(tester, desktop: desktop);
      await _run(tester);
      fixture.controller.caret
        ..logicalIndex = 1
        ..collapseSelection();
      await _tap(tester, 'Apply Zotero result');
      expect(find.byKey(_directKey), findsOneWidget);
      expect(find.textContaining('insertion point changed'), findsOneWidget);
      expect(
        fixture.controller.document.paragraphs.single.text,
        'Before after',
      );
      expect(fixture.controller.canUndo, isFalse);
      expect(desktop.requests, hasLength(7));
      await _tap(tester, 'Return to document');
      _expectReturned(fixture);
    },
  );

  testWidgets(
    'cooperative cancellation returns only after the response drains',
    (tester) async {
      final desktop = _Desktop(_noChange())..firstResponse = Completer<void>();
      final fixture = await _mount(tester, desktop: desktop);
      await _run(tester);
      expect(find.byKey(_directKey), findsOneWidget);
      expect(desktop.requests, hasLength(1));
      await tester.binding.handlePopRoute();
      await _pump(tester);
      expect(find.byKey(_directKey), findsOneWidget);
      await _tap(tester, 'Cancel operation');
      expect(find.text('Cancelling…'), findsOneWidget);
      expect(desktop.requests, hasLength(1));
      expect(fixture.bodyFocus.hasPrimaryFocus, isFalse);
      desktop.firstResponse!.complete();
      await _pump(tester);
      expect(desktop.requests, hasLength(2));
      expect(desktop.replies.single, contains('error'));
      expect(fixture.controller.canUndo, isFalse);
      _expectReturned(fixture);
    },
  );

  testWidgets('completion never dismisses a newer host dialog', (tester) async {
    final desktop = _Desktop(_noChange())..firstResponse = Completer<void>();
    final fixture = await _mount(tester, desktop: desktop);
    await _run(tester);
    unawaited(
      showDialog<void>(
        context: fixture.navigator.currentContext!,
        builder: (context) => AlertDialog(
          title: const Text('Another document decision'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Keep working'),
            ),
          ],
        ),
      ),
    );
    await _pump(tester);
    desktop.firstResponse!.complete();
    await _pump(tester);
    expect(find.text('Another document decision'), findsOneWidget);
    expect(find.byKey(_directKey, skipOffstage: false), findsOneWidget);
    expect(fixture.bodyFocus.hasPrimaryFocus, isFalse);
    await _tap(tester, 'Keep working');
    expect(find.byKey(_directKey), findsOneWidget);
    await _tap(tester, 'Return to document');
    _expectReturned(fixture);
  });

  testWidgets(
    'the ordinary references workspace remains available after a command',
    (tester) async {
      final desktop = _Desktop(_insert());
      final fixture = await _mount(
        tester,
        desktop: desktop,
        closeAfterCommand: false,
      );
      await _run(tester);
      expect(find.byKey(_directKey), findsNothing);
      expect(find.byTooltip('Close Zotero'), findsOneWidget);
      expect(
        find.textContaining('Zotero updated the document'),
        findsOneWidget,
      );
      expect(fixture.bodyFocus.hasPrimaryFocus, isFalse);
      await _tap(tester, 'Library');
      await _tap(tester, 'Document');
      expect(desktop.requests, hasLength(7));
      expect(fixture.controller.zoteroFields.single.cachedText, '(Source)');
    },
  );

  testWidgets('the returned body accepts keyboard input immediately', (
    tester,
  ) async {
    final fixture = await _mount(tester, desktop: _Desktop(_noChange()));
    await _run(tester);
    _expectReturned(fixture);
    tester.testTextInput.enterText('Before after resumed');
    await _pump(tester);
    expect(
      fixture.controller.document.paragraphs.single.text,
      'Before after resumed',
    );
  });

  for (final endnote in [false, true]) {
    testWidgets(
      'a direct citation returns to its ${endnote ? 'endnote' : 'footnote'} caret',
      (tester) async {
        final document = WmlDocument.empty(text: 'Body stays');
        final note = WordNotes.insert(
          document,
          document.paragraphs.single,
          text: 'Before after',
          endnote: endnote,
        );
        final fixture = await _mount(
          tester,
          desktop: _Desktop(_insert()),
          document: document,
          showNotes: true,
        );
        final field = find.byKey(
          ValueKey<String>('notes-edit-${endnote ? 'E' : ''}${note.id}'),
        );
        await tester.tap(field);
        await _pump(tester);
        tester.widget<TextField>(field).controller!.selection =
            const TextSelection.collapsed(offset: 7);
        await _pump(tester);
        final bodyBefore = document.paragraphs.single.text;
        await _run(tester);
        expect(find.byKey(_directKey), findsNothing);
        expect(
          fixture.controller.zoteroFields.single.paragraph,
          same(note.paragraphs.single),
        );
        expect(fixture.controller.noteEditText(note), 'Before (Source)after');
        expect(fixture.controller.noteEditingTarget?.note, same(note));
        expect(
          tester.widget<TextField>(field).focusNode!.hasPrimaryFocus,
          isTrue,
        );
        expect(fixture.bodyFocus.hasFocus, isFalse);
        expect(fixture.controller.input.isAttached, isFalse);
        expect(document.paragraphs.single.text, bodyBefore);
        expect(endnote ? document.endnotes : document.footnotes, hasLength(1));
      },
    );
  }
}
