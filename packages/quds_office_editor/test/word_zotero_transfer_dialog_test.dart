import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _exportKey = ValueKey<String>('zotero-export-document');
const _importKey = ValueKey<String>('zotero-refresh-or-import');
const _instructions =
    'Open this document in the destination word processor and use Zotero Refresh.';
const _preferences =
    '<data data-version="3"><session id="transfer-dialog"/>'
    '<style id="http://www.zotero.org/styles/apa" '
    'locale="de-DE" hasBibliography="1"/>'
    '<prefs><pref name="fieldType" value="Field"/>'
    '<pref name="noteType" value="0"/></prefs></data>';

WmlDocument _activeDocument() {
  final document = WmlDocument.empty(text: 'Before ')
    ..zoteroDocumentData = _preferences;
  final paragraph = document.paragraphs.single;
  for (final id in ['first', 'second']) {
    WordZotero.insertCitation(
      paragraph,
      ZoteroCitation(
        citationId: id,
        plainCitation: '($id)',
        items: [
          ZoteroCitationItem.fromCsl(
            itemData: {
              'id': id,
              'type': 'book',
              'title': 'Research source $id',
            },
            uris: ['http://zotero.org/users/42/items/ABCD1234'],
          ),
        ],
      ),
    );
    paragraph.inlines.add(WmlRun(text: ' after '));
  }
  return document;
}

WmlDocument _transferDocument() {
  final document = _activeDocument();
  WordZoteroTransfer.prepareExport(
    document,
    instructions: _instructions,
    documentData: _preferences,
  ).apply();
  return document;
}

String _state(WmlDocument document) => jsonEncode({
  'data': document.zoteroDocumentData,
  'paragraphs': [
    for (final paragraph in document.paragraphs)
      [
        paragraph.text,
        for (final run in paragraph.inlines.whereType<WmlRun>())
          [run.text, run.hyperlink?.url, run.fieldInstruction],
      ],
  ],
});

typedef _Step = Map<String, Object?> Function(_Desktop desktop);

final class _Desktop {
  _Desktop(this.steps, {this.holdAt});

  final List<_Step> steps;
  final int? holdAt;
  final release = Completer<void>();
  final requests = <ZoteroHttpRequest>[];
  final replies = <Object?>[];
  final fieldIds = <String>[];
  String documentId = '';
  String command = '';
  int index = 0;

  Map<String, Object?> message(String name, List<Object?> arguments) => {
    'command': name,
    'arguments': arguments,
  };

  Future<ZoteroHttpResponse> send(ZoteroHttpRequest request) async {
    requests.add(request);
    expect(request.method, 'POST');
    expect(request.uri.host, 'localhost');
    expect(request.uri.port, 23119);
    expect(request.headers.containsKey('Zotero-API-Key'), isFalse);
    final Object? decoded = jsonDecode(request.body!);
    if (index == 0) {
      final start = decoded! as Map<String, Object?>;
      documentId = start['docId']! as String;
      command = start['command']! as String;
    } else {
      replies.add(decoded);
      if (decoded is List<Object?>) {
        for (final item in decoded) {
          if (item is Map<String, Object?> && item['id'] is String) {
            fieldIds.add(item['id']! as String);
          }
        }
      }
    }
    if (holdAt == index) await release.future;
    expect(index, lessThan(steps.length));
    return ZoteroHttpResponse(
      statusCode: 200,
      headers: const {},
      body: jsonEncode(steps[index++](this)),
    );
  }
}

List<_Step> _exportScript() => [
  (d) => d.message('Application.getActiveDocument', []),
  (d) => d.message('Document.getDocumentData', [d.documentId]),
  (d) => d.message('Document.exportDocument', [
    d.documentId,
    'Http',
    _instructions,
  ]),
  (d) => d.message('Document.setDocumentData', [
    d.documentId,
    WordZoteroDocumentData.toHttp(_preferences),
  ]),
  (d) => d.message('Document.activate', [d.documentId]),
  (d) => d.message('Document.complete', [d.documentId]),
];

List<_Step> _importScript() => [
  (d) => d.message('Application.getActiveDocument', []),
  (d) => d.message('Document.getDocumentData', [d.documentId]),
  (d) => d.message('Document.importDocument', [d.documentId, 'Http']),
  (d) => d.message('Document.getDocumentData', [d.documentId]),
  (d) => d.message('Document.getFields', [d.documentId, 'Http']),
  (d) => d.message('Field.setText', [
    d.documentId,
    d.fieldIds[0],
    '<i>(Restored first)</i>',
    true,
  ]),
  (d) => d.message('Field.setText', [
    d.documentId,
    d.fieldIds[1],
    '<i>(Restored second)</i>',
    true,
  ]),
  (d) => d.message('Document.complete', [d.documentId]),
];

Future<WordEditorController> _open(
  WidgetTester tester, {
  required WmlDocument document,
  required _Desktop desktop,
  Size size = const Size(1300, 1000),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = WordEditorController(document: document);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    if (!controller.isDisposed) controller.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showWordZoteroDialog(
              context,
              controller: controller,
              localTransport: desktop.send,
              initialTab: WordZoteroTab.document,
            ),
            child: const Text('Open Zotero transfer'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open Zotero transfer'));
  await tester.pumpAndSettle();
  return controller;
}

Future<void> _tap(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pump();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'export button sends the native command and explains saving a copy',
    (tester) async {
      final document = _activeDocument();
      final before = _state(document);
      final desktop = _Desktop(_exportScript());
      final controller = await _open(
        tester,
        document: document,
        desktop: desktop,
      );
      await _tap(tester, _exportKey);
      expect(desktop.command, 'exportDocument');
      expect(desktop.requests, hasLength(6));
      expect(WordZoteroTransfer.isTransferDocument(document), isTrue);
      expect(controller.zoteroFields, isEmpty);
      expect(find.textContaining('Save a copy as DOCX'), findsOneWidget);
      expect(find.textContaining('use Zotero Refresh'), findsOneWidget);
      expect(find.text('Import transferred references…'), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(find.byKey(_exportKey)).onPressed,
        isNull,
      );
      controller.undo();
      expect(_state(document), before);
      expect(controller.canUndo, isFalse);
    },
  );

  testWidgets(
    'transfer detection offers import and disables other desktop edits',
    (tester) async {
      final desktop = _Desktop(_importScript());
      await _open(tester, document: _transferDocument(), desktop: desktop);
      expect(find.text('Import transferred references…'), findsOneWidget);
      expect(
        find.textContaining('original document stays intact'),
        findsOneWidget,
      );
      expect(
        tester.widget<OutlinedButton>(find.byKey(_importKey)).onPressed,
        isNotNull,
      );
      expect(
        tester.widget<OutlinedButton>(find.byKey(_exportKey)).onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Citation in Zotero…'),
            )
            .onPressed,
        isNull,
      );
      for (final label in [
        'Add note from Zotero…',
        'Add annotation from Zotero…',
        'Document style…',
        'Bibliography in Zotero…',
      ]) {
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, label),
              )
              .onPressed,
          isNull,
        );
      }
      expect(desktop.requests, isEmpty);
    },
  );

  testWidgets(
    'import action uses Refresh and restores every formatted reference',
    (tester) async {
      final document = _transferDocument();
      final before = _state(document);
      final desktop = _Desktop(_importScript());
      final controller = await _open(
        tester,
        document: document,
        desktop: desktop,
      );
      await _tap(tester, _importKey);
      expect(desktop.command, 'refresh');
      expect(desktop.requests, hasLength(8));
      expect(desktop.replies[1], 'ZOTERO_TRANSFER_DOCUMENT');
      expect(desktop.replies[2], isTrue);
      expect(WordZoteroTransfer.isTransferDocument(document), isFalse);
      expect(controller.zoteroFields.map((field) => field.cachedText), [
        '(Restored first)',
        '(Restored second)',
      ]);
      expect(find.textContaining('restored and formatted'), findsOneWidget);
      expect(find.text('Refresh all with Zotero'), findsOneWidget);
      controller.undo();
      expect(_state(document), before);
      expect(controller.canUndo, isFalse);
    },
  );

  testWidgets(
    'cancelling after export staging keeps active fields and no history',
    (tester) async {
      final document = _activeDocument();
      final before = _state(document);
      final desktop = _Desktop(_exportScript(), holdAt: 5);
      final controller = await _open(
        tester,
        document: document,
        desktop: desktop,
      );
      await tester.ensureVisible(find.byKey(_exportKey));
      await tester.tap(find.byKey(_exportKey));
      for (var index = 0; index < 8; index++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(desktop.requests, hasLength(6));
      expect(_state(document), before);
      await tester.tap(find.text('Cancel operation'));
      await tester.pump();
      desktop.release.complete();
      await tester.pumpAndSettle();
      expect(_state(document), before);
      expect(controller.zoteroFields, hasLength(2));
      expect(controller.canUndo, isFalse);
      expect(controller.isDirty, isFalse);
      expect(find.textContaining('cancelled'), findsOneWidget);
      expect(find.textContaining('Save a copy as DOCX'), findsNothing);
    },
  );

  testWidgets('malformed transfer data remains intact after a refused import', (
    tester,
  ) async {
    final document = _transferDocument();
    final payload = document.paragraphs
        .expand((p) => p.inlines)
        .whereType<WmlRun>()
        .firstWhere((run) => run.text.contains('ITEM CSL_CITATION'));
    payload.text = 'ITEM CSL_CITATION {';
    final before = _state(document);
    final desktop = _Desktop([
      (d) => d.message('Application.getActiveDocument', []),
      (d) => d.message('Document.importDocument', [d.documentId, 'Http']),
      (d) => d.message('Document.complete', [d.documentId]),
    ]);
    final controller = await _open(
      tester,
      document: document,
      desktop: desktop,
    );
    await _tap(tester, _importKey);
    expect(desktop.command, 'refresh');
    expect(desktop.requests, hasLength(3));
    expect(desktop.replies.last, isA<Map<String, Object?>>());
    expect(
      (desktop.replies.last! as Map<String, Object?>).containsKey('error'),
      isTrue,
    );
    expect(_state(document), before);
    expect(controller.canUndo, isFalse);
    expect(find.textContaining('could not be applied safely'), findsOneWidget);
    expect(find.text('Import transferred references…'), findsOneWidget);
  });

  testWidgets('transfer controls remain reachable in a narrow dialog', (
    tester,
  ) async {
    final desktop = _Desktop(_importScript());
    await _open(
      tester,
      document: _transferDocument(),
      desktop: desktop,
      size: const Size(360, 800),
    );
    await tester.ensureVisible(find.byKey(_importKey));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(_importKey).hitTestable(), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(find.byKey(_importKey)).onPressed,
      isNotNull,
    );
    expect(desktop.requests, isEmpty);
  });
}
