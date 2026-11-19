import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

ZoteroCitation _citation(String id, String text) => ZoteroCitation(
  citationId: id,
  plainCitation: text,
  items: [
    ZoteroCitationItem.fromCsl(
      itemData: {
        'id': 'source',
        'type': 'book',
        'title': 'A real source',
        'author': [
          {'family': 'Müller', 'given': 'Anna'},
        ],
        'issued': {
          'date-parts': [
            [2024],
          ],
        },
      },
      uris: ['http://zotero.org/users/42/items/ABCD1234'],
      locator: '34',
      label: 'page',
    ),
  ],
);

String _code(String id, String text) =>
    'ITEM CSL_CITATION ${jsonEncode(_citation(id, text).toJson())}';
String _data(String type) => jsonEncode({
  'dataVersion': 4,
  'sessionID': 'native-test',
  'zoteroVersion': '10.0',
  'style': {
    'styleID':
        'http://www.zotero.org/styles/chicago-notes-bibliography-subsequent-ibid',
    'locale': 'de-DE',
  },
  'prefs': {'fieldType': type, 'noteType': 1},
});

typedef _Step = Map<String, Object?> Function(_Desktop desktop);

class _Desktop {
  _Desktop(this.steps);
  final List<_Step> steps;
  final requests = <ZoteroHttpRequest>[];
  final replies = <Object?>[];
  String documentId = '';
  String fieldId = '';
  String command = '';
  Completer<void>? firstResponse;
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
    expect(
      request.headers.keys.any((key) => key.toLowerCase().contains('key')),
      isFalse,
    );
    final decoded = jsonDecode(request.body!);
    if (index == 0) {
      final start = decoded as Map<String, dynamic>;
      documentId = start['docId'] as String;
      command = start['command'] as String;
      await firstResponse?.future;
    } else {
      replies.add(decoded);
      if (decoded is Map<String, dynamic> && decoded['id'] is String) {
        fieldId = decoded['id'] as String;
      }
    }
    expect(index, lessThan(steps.length));
    return ZoteroHttpResponse(
      statusCode: 200,
      headers: const {},
      body: jsonEncode(steps[index++](this)),
    );
  }
}

List<_Step> _insertScript({String html = 'Ebd., 34.', int noteType = 1}) => [
  (d) => d.message('Application.getActiveDocument', []),
  (d) => d.message('Document.getDocumentData', [d.documentId]),
  (d) => d.message('Document.setDocumentData', [d.documentId, _data('Http')]),
  (d) => d.message('Document.insertField', [d.documentId, 'Http', noteType]),
  (d) => d.message('Field.setCode', [
    d.documentId,
    d.fieldId,
    _code('native-citation', ZoteroFormattedText.fromHtml(html).plainText),
  ]),
  (d) => d.message('Field.setText', [d.documentId, d.fieldId, html, true]),
  (d) => d.message('Document.complete', [d.documentId]),
];

Future<WordEditorController> _open(
  WidgetTester tester, {
  _Desktop? desktop,
  WmlDocument? document,
  ZoteroCitingCommand? initialCommand,
  bool navigateToDocument = true,
  ({int start, int end})? selection,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1300, 1000);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = WordEditorController(
    document: document ?? WmlDocument.empty(text: 'Before after'),
  );
  controller.caret.logicalIndex = 7;
  controller.caret.collapseSelection();
  if (selection != null) {
    controller.caret.logicalIndex = selection.end;
    controller.caret.selectionAnchor = selection.start;
    controller.caret.selectionAnchorParagraph = 0;
  }
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showWordZoteroDialog(
              context,
              controller: controller,
              localTransport: desktop?.send,
              session: ZoteroSession()..apiKey = 'online-secret',
              initialCommand: initialCommand,
            ),
            child: const Text('Open Zotero'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open Zotero'));
  await tester.pumpAndSettle();
  if (navigateToDocument) {
    await tester.tap(find.text('Document'));
    await tester.pumpAndSettle();
  }
  return controller;
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pump();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a direct citation action starts once without navigating tabs', (
    tester,
  ) async {
    final desktop = _Desktop(_insertScript());
    final controller = await _open(
      tester,
      desktop: desktop,
      initialCommand: ZoteroCitingCommand.addEditCitation,
      navigateToDocument: false,
    );
    expect(desktop.command, 'addEditCitation');
    expect(desktop.requests, hasLength(7));
    expect(controller.zoteroFields.single.cachedText, 'Ebd., 34.');
    expect(find.textContaining('Zotero updated the document'), findsOneWidget);
    await _tap(tester, 'Library');
    await _tap(tester, 'Document');
    expect(desktop.requests, hasLength(7));
    controller.undo();
    expect(controller.zoteroFields, isEmpty);
    expect(controller.canUndo, isFalse);
  });

  testWidgets('a direct action edits the citation enclosing the selection', (
    tester,
  ) async {
    final document = WmlDocument.empty(text: 'Before ');
    WordZotero.insertCitation(
      document.paragraphs.single,
      _citation('existing', '(Old)'),
    );
    final desktop = _Desktop([
      (d) => d.message('Application.getActiveDocument', []),
      (d) => d.message('Document.cursorInField', [d.documentId, 'Http']),
      (d) => d.message('Field.setCode', [
        d.documentId,
        d.fieldId,
        _code('existing', '(Updated)'),
      ]),
      (d) => d.message('Field.setText', [
        d.documentId,
        d.fieldId,
        '<i>(Updated)</i>',
        true,
      ]),
      (d) => d.message('Document.complete', [d.documentId]),
    ]);
    final controller = await _open(
      tester,
      document: document,
      desktop: desktop,
      initialCommand: ZoteroCitingCommand.addEditCitation,
      navigateToDocument: false,
      selection: (start: 7, end: 12),
    );
    expect(desktop.command, 'addEditCitation');
    expect(desktop.fieldId, isNotEmpty);
    expect(controller.zoteroFields, hasLength(1));
    expect(controller.zoteroFields.single.citation!.citationId, 'existing');
    expect(controller.zoteroFields.single.cachedText, '(Updated)');
    controller.undo();
    expect(controller.zoteroFields.single.cachedText, '(Old)');
    expect(controller.canUndo, isFalse);
    expect(controller.caret.selectionAnchor, 7);
    expect(controller.caret.logicalIndex, 12);
  });

  for (final command in [
    ZoteroCitingCommand.refresh,
    ZoteroCitingCommand.setDocPrefs,
    ZoteroCitingCommand.addEditBibliography,
  ]) {
    testWidgets('a direct ${command.name} action uses its native command', (
      tester,
    ) async {
      final desktop = _Desktop([
        (d) => d.message('Application.getActiveDocument', []),
        (d) => d.message('Document.complete', [d.documentId]),
      ]);
      final controller = await _open(
        tester,
        desktop: desktop,
        initialCommand: command,
        navigateToDocument: false,
      );
      expect(desktop.command, command.name);
      expect(desktop.requests, hasLength(2));
      expect(controller.canUndo, isFalse);
      expect(
        find.textContaining('without changing the document'),
        findsOneWidget,
      );
    });
  }

  testWidgets(
    'a direct desktop action without a transport keeps the document',
    (tester) async {
      final controller = await _open(
        tester,
        initialCommand: ZoteroCitingCommand.addEditCitation,
        navigateToDocument: false,
      );
      expect(find.textContaining('unavailable in this host'), findsOneWidget);
      expect(controller.zoteroFields, isEmpty);
      expect(controller.canUndo, isFalse);
    },
  );

  testWidgets('desktop tools are absent when the host has no local transport', (
    tester,
  ) async {
    await _open(tester);
    expect(find.text('Citation in Zotero…'), findsNothing);
    expect(find.text('Add annotation from Zotero…'), findsNothing);
    expect(find.text('Document style…'), findsNothing);
    expect(find.text('Refresh all with Zotero'), findsNothing);
  });

  testWidgets('annotation workspace command discards cancelled staged edits', (
    tester,
  ) async {
    final desktop = _Desktop([
      (d) => d.message('Application.getActiveDocument', []),
      (d) =>
          d.message('Document.setDocumentData', [d.documentId, _data('Http')]),
      (d) => d.message('Document.insertField', [d.documentId, 'Http', 0]),
      (d) => d.message('Field.delete', [d.documentId, d.fieldId]),
      (d) => d.message('Document.complete', [d.documentId]),
    ]);
    final controller = await _open(tester, desktop: desktop);
    expect(
      find.byTooltip(
        'Insert text annotations and comments with active citations. Requires Zotero 9 or later.',
      ),
      findsOneWidget,
    );
    await _tap(tester, 'Add annotation from Zotero…');
    expect(desktop.command, 'addAnnotation');
    expect(desktop.requests, hasLength(5));
    expect(controller.document.paragraphs.single.text, 'Before after');
    expect(controller.zoteroFields, isEmpty);
    expect(WordZoteroDocumentData.read(controller.document), isEmpty);
    expect(controller.canUndo, isFalse);
    expect(controller.isDirty, isFalse);
    expect(
      find.text('No Zotero annotation was inserted. The document was kept.'),
      findsOneWidget,
    );
    expect(find.text('Document'), findsOneWidget);
  });

  testWidgets('annotation workspace action is disabled during Track changes', (
    tester,
  ) async {
    final desktop = _Desktop([]);
    final document = WmlDocument.empty(text: 'Before after')
      ..trackRevisions = true;
    final controller = await _open(
      tester,
      desktop: desktop,
      document: document,
    );
    final button = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey<String>('zotero-add-annotation')),
    );
    expect(button.onPressed, isNull);
    expect(desktop.requests, isEmpty);
    expect(controller.document.paragraphs.single.text, 'Before after');
    expect(controller.canUndo, isFalse);
  });

  testWidgets(
    'native picker inserts a linked footnote and preferences as one undo',
    (tester) async {
      final desktop = _Desktop(_insertScript());
      final controller = await _open(tester, desktop: desktop);
      await _tap(tester, 'Citation in Zotero…');
      expect(desktop.command, 'addEditCitation');
      expect(desktop.index, 7);
      expect(desktop.requests, hasLength(7));
      expect(controller.document.footnotes, hasLength(1));
      expect(controller.zoteroFields.single.cachedText, 'Ebd., 34.');
      expect(
        controller.zoteroFields.single.citation!.items.single.locator,
        '34',
      );
      expect(
        WordZoteroDocumentData.read(controller.document),
        contains('"fieldType":"Field"'),
      );
      expect(
        find.textContaining('Zotero updated the document'),
        findsOneWidget,
      );
      controller.undo();
      expect(controller.document.footnotes, isEmpty);
      expect(controller.zoteroFields, isEmpty);
      expect(controller.document.paragraphs.single.text, 'Before after');
      expect(controller.canUndo, isFalse);
      controller.redo();
      expect(controller.zoteroFields.single.cachedText, 'Ebd., 34.');
      expect(controller.document.footnotes, hasLength(1));
    },
  );

  testWidgets(
    'Document style invokes Zotero preferences and persists its chosen locale',
    (tester) async {
      final desktop = _Desktop([
        (d) => d.message('Application.getActiveDocument', []),
        (d) => d.message('Document.getDocumentData', [d.documentId]),
        (d) => d.message('Document.setDocumentData', [
          d.documentId,
          _data('Http'),
        ]),
        (d) => d.message('Document.complete', [d.documentId]),
      ]);
      final controller = await _open(tester, desktop: desktop);
      await _tap(tester, 'Document style…');
      expect(desktop.command, 'setDocPrefs');
      expect(
        WordZoteroDocumentData.read(controller.document),
        contains('de-DE'),
      );
      expect(controller.zoteroFields, isEmpty);
      controller.undo();
      expect(WordZoteroDocumentData.read(controller.document), isEmpty);
    },
  );

  testWidgets('native cancel without changes leaves the undo history clean', (
    tester,
  ) async {
    final desktop = _Desktop([
      (d) => d.message('Application.getActiveDocument', []),
      (d) => d.message('Document.complete', [d.documentId]),
    ]);
    final controller = await _open(tester, desktop: desktop);
    await _tap(tester, 'Citation in Zotero…');
    expect(controller.isDirty, isFalse);
    expect(controller.canUndo, isFalse);
    expect(
      find.text('Zotero finished without changing the document.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'unsupported capital variants are reviewed before mutation and can be discarded',
    (tester) async {
      final desktop = _Desktop(
        _insertScript(
          html: '<span style="font-variant: all-small-caps">Title</span>, 34.',
          noteType: 0,
        ),
      );
      final controller = await _open(tester, desktop: desktop);
      await _tap(tester, 'Citation in Zotero…');
      expect(find.text('Review Zotero formatting'), findsOneWidget);
      expect(find.textContaining('unsupported inline style'), findsOneWidget);
      expect(controller.zoteroFields, isEmpty);
      expect(WordZoteroDocumentData.read(controller.document), isEmpty);
      await _tap(tester, 'Cancel');
      expect(controller.zoteroFields, isEmpty);
      expect(controller.canUndo, isFalse);
      expect(find.textContaining('result discarded'), findsOneWidget);
    },
  );

  testWidgets('native small caps apply without a simplification review', (
    tester,
  ) async {
    final desktop = _Desktop(
      _insertScript(
        html: '<span style="font-variant: small-caps">Title</span>, 34.',
        noteType: 0,
      ),
    );
    final controller = await _open(tester, desktop: desktop);
    await _tap(tester, 'Citation in Zotero…');
    expect(find.text('Review Zotero formatting'), findsNothing);
    final field = controller.zoteroFields.single;
    expect(field.cachedText, 'Title, 34.');
    expect(field.canEdit, isTrue);
    expect(
      field.paragraph.inlines
          .whereType<WmlRun>()
          .singleWhere((run) => run.text == 'Title')
          .properties
          .smallCaps,
      isTrue,
    );
    expect(controller.canUndo, isTrue);
    controller.undo();
    expect(controller.zoteroFields, isEmpty);
  });

  testWidgets(
    'mixed formatting applies styled runs while retaining one protected field',
    (tester) async {
      final desktop = _Desktop(
        _insertScript(html: '<i>Title</i>, 34.', noteType: 0),
      );
      final controller = await _open(tester, desktop: desktop);
      await _tap(tester, 'Citation in Zotero…');
      expect(find.text('Review Zotero formatting'), findsNothing);
      final field = controller.zoteroFields.single;
      expect(field.cachedText, 'Title, 34.');
      expect(field.run, isNull);
      expect(field.canEdit, isTrue);
      expect(
        field.paragraph.inlines
            .whereType<WmlRun>()
            .singleWhere((run) => run.text == 'Title')
            .properties
            .italic,
        isTrue,
      );
      expect(field.citation!.citationId, 'native-citation');
      final reopened = WordDeserializer().read(
        OpcPackage.open(
          MemoryByteSource(WordSerializer().writeBytes(controller.document)),
        ),
      );
      expect(WordZotero.fields(reopened).single.cachedText, 'Title, 34.');
      controller.undo();
      expect(controller.zoteroFields, isEmpty);
    },
  );

  testWidgets('moving the caret during review prevents a stale insertion', (
    tester,
  ) async {
    final desktop = _Desktop(
      _insertScript(
        html: '<span style="font-variant: all-small-caps">Title</span>, 34.',
        noteType: 0,
      ),
    );
    final controller = await _open(tester, desktop: desktop);
    await _tap(tester, 'Citation in Zotero…');
    controller.caret.logicalIndex = 0;
    controller.caret.collapseSelection();
    await _tap(tester, 'Apply Zotero result');
    expect(controller.zoteroFields, isEmpty);
    expect(controller.canUndo, isFalse);
    expect(find.textContaining('insertion point changed'), findsOneWidget);
  });

  for (final specification in [
    (0, 'OK', 1),
    (1, 'Cancel', 0),
    (2, 'No', 0),
    (3, 'Yes', 2),
  ]) {
    final (buttons, label, expected) = specification;
    testWidgets(
      'Zotero alert button set $buttons returns its exact $label code',
      (tester) async {
        final desktop = _Desktop([
          (d) => d.message('Application.getActiveDocument', []),
          (d) => d.message('Document.displayAlert', [
            d.documentId,
            'Review this source decision.',
            0,
            buttons,
          ]),
          (d) => d.message('Document.complete', [d.documentId]),
        ]);
        final controller = await _open(tester, desktop: desktop);
        await _tap(tester, 'Refresh all with Zotero');
        expect(find.text('Review this source decision.'), findsOneWidget);
        expect(desktop.replies, hasLength(1));
        await _tap(tester, label);
        expect(desktop.replies.last, expected);
        expect(controller.canUndo, isFalse);
      },
    );
  }

  for (final buttons in [0, 2]) {
    testWidgets(
      'desktop error alert $buttons discards staged fields even after complete',
      (tester) async {
        final script = _insertScript()..removeLast();
        script.addAll([
          (d) => d.message('Document.displayAlert', [
            d.documentId,
            'Zotero could not finish formatting this document.',
            0,
            buttons,
          ]),
          (d) => d.message('Document.activate', [d.documentId]),
          (d) => d.message('Document.complete', [d.documentId]),
        ]);
        final desktop = _Desktop(script);
        final controller = await _open(tester, desktop: desktop);
        await _tap(tester, 'Citation in Zotero…');
        expect(
          find.text('Zotero could not finish formatting this document.'),
          findsOneWidget,
        );
        expect(controller.zoteroFields, isEmpty);
        await _tap(tester, buttons == 0 ? 'OK' : 'No');
        expect(desktop.index, script.length);
        expect(controller.zoteroFields, isEmpty);
        expect(controller.document.footnotes, isEmpty);
        expect(controller.document.paragraphs.single.text, 'Before after');
        expect(WordZoteroDocumentData.read(controller.document), isEmpty);
        expect(controller.canUndo, isFalse);
        expect(controller.isDirty, isFalse);
        expect(
          find.textContaining('Zotero updated the document'),
          findsNothing,
        );
        expect(
          find.textContaining('No document changes were applied'),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets(
    'cancel waits for a native response then drains without live mutation',
    (tester) async {
      final desktop = _Desktop([
        (d) => d.message('Application.getActiveDocument', []),
        (d) => d.message('Document.complete', [d.documentId]),
      ])..firstResponse = Completer<void>();
      final controller = await _open(tester, desktop: desktop);
      await tester.tap(find.text('Citation in Zotero…'));
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton && widget.tooltip == 'Close Zotero',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Cancel operation'));
      await tester.pump();
      expect(desktop.requests, hasLength(1));
      expect(find.text('Cancelling…'), findsOneWidget);
      desktop.firstResponse!.complete();
      await tester.pumpAndSettle();
      expect(desktop.requests, hasLength(2));
      expect(desktop.replies.single, isA<Map<String, dynamic>>());
      expect(
        (desktop.replies.single as Map<String, dynamic>).containsKey('error'),
        isTrue,
      );
      expect(controller.zoteroFields, isEmpty);
      expect(controller.canUndo, isFalse);
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
    },
  );

  testWidgets(
    'stale editor target reports an error and drains the native transaction',
    (tester) async {
      final desktop = _Desktop([
        (d) => d.message('Application.getActiveDocument', []),
        (d) => d.message('Document.complete', [d.documentId]),
      ])..firstResponse = Completer<void>();
      final controller = await _open(tester, desktop: desktop);
      await tester.tap(find.text('Refresh all with Zotero'));
      await tester.pump();
      controller.caret.logicalIndex = 1;
      controller.caret.collapseSelection();
      desktop.firstResponse!.complete();
      await tester.pumpAndSettle();
      expect(desktop.requests, hasLength(2));
      expect(
        (desktop.replies.single as Map<String, dynamic>).containsKey('error'),
        isTrue,
      );
      expect(controller.canUndo, isFalse);
      expect(controller.document.paragraphs.single.text, 'Before after');
    },
  );
}
