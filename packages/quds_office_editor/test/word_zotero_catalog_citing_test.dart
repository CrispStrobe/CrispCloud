import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _uri = 'http://zotero.org/users/local/LOCALKEY/items/ABCD1234';
const _style =
    'http://www.zotero.org/styles/chicago-notes-bibliography-subsequent-ibid';
const _item = <String, dynamic>{
  'id': _uri,
  'type': 'book',
  'title': 'Local catalog source',
  'author': [
    {'family': 'Müller'},
  ],
};

String _preferences(int note) => jsonEncode({
  'dataVersion': 4,
  'sessionID': 'catalog-session',
  'style': {'styleID': _style, 'locale': 'de-DE'},
  'prefs': {'fieldType': 'Http', 'noteType': note},
});

class _CatalogDesktop {
  _CatalogDesktop({this.noteType = 1, this.savedSearch = false});

  final int noteType;
  final bool savedSearch;
  bool cancelStyle = false;
  bool cancelCitation = false;
  bool failCitation = false;
  Completer<void>? citationGate;
  final commands = <String>[];
  final ids = <String>[];
  final requests = <ZoteroHttpRequest>[];
  Map<String, dynamic>? seed;
  String documentId = '';
  int step = 0;
  List<Map<String, Object?> Function()> script = [];

  List<Map<String, Object?>> get catalogRecords => [
    {
      'key': 'ABCD1234',
      'version': 1,
      'library': {'type': 'user', 'id': 0},
      'data': {
        'key': 'ABCD1234',
        'itemType': 'book',
        'title': 'Local catalog source',
      },
      'csljson': [_item],
    },
  ];

  Map<String, Object?> _message(String name, [List<Object?> args = const []]) =>
      {'command': name, 'arguments': args};

  String _code() =>
      'ITEM CSL_CITATION ${jsonEncode(ZoteroCitation(
        citationId: 'native-catalog-citation',
        plainCitation: 'Ebd., 34.',
        items: [
          ZoteroCitationItem.fromCsl(itemData: _item, uris: [_uri], locator: '34', label: 'page'),
        ],
      ).toJson())}';

  Future<ZoteroHttpResponse> send(ZoteroHttpRequest request) async {
    requests.add(request);
    expect(request.headers.containsKey('Zotero-API-Key'), isFalse);
    expect(request.uri.host, 'localhost');
    expect(request.uri.port, 23119);
    if (request.method == 'GET') {
      if (request.uri.path == '/api/') {
        return ZoteroHttpResponse(
          statusCode: 200,
          body: 'Nothing to see here.',
          headers: const {
            'Zotero-API-Version': '3',
            'Zotero-Server-ID': 'catalog-test-profile',
          },
        );
      }
      final Object body = switch (request.uri.path) {
        '/api/users/0/groups' || '/api/users/0/collections' => <Object>[],
        '/api/users/0/items/top' => savedSearch ? <Object>[] : catalogRecords,
        '/api/users/0/searches' => [
          {
            'key': 'SEARCH01',
            'data': {'key': 'SEARCH01', 'name': 'Sources for this paper'},
          },
        ],
        '/api/users/0/searches/SEARCH01/items' => catalogRecords,
        _ => throw StateError('Unexpected catalog path: ${request.uri.path}'),
      };
      return ZoteroHttpResponse(
        statusCode: 200,
        body: jsonEncode(body),
        headers: const {'Zotero-Server-ID': 'catalog-test-profile'},
      );
    }
    final decoded = jsonDecode(request.body!);
    if (request.uri.path.endsWith('/execCommand')) {
      documentId = decoded['docId'] as String;
      ids.add(documentId);
      commands.add(decoded['command'] as String);
      step = 0;
      if (commands.last == 'setDocPrefs') {
        script = [
          () => _message('Application.getActiveDocument'),
          () => _message('Document.getDocumentData', [documentId]),
          if (!cancelStyle)
            () => _message('Document.setDocumentData', [
              documentId,
              _preferences(noteType),
            ]),
          () => _message('Document.complete', [documentId]),
        ];
      } else {
        expect(commands.last, 'addEditCitation');
        await citationGate?.future;
        if (failCitation) {
          return ZoteroHttpResponse(statusCode: 503, body: 'unavailable');
        }
        script = [
          () => _message('Application.getActiveDocument'),
          () => _message('Document.getDocumentData', [documentId]),
          () => _message('Document.cursorInField', [documentId, 'Http']),
          if (!cancelCitation) ...[
            () => _message('Field.setCode', [documentId, seed!['id'], _code()]),
            () => _message('Field.setText', [
              documentId,
              seed!['id'],
              'Ebd., 34.',
              true,
            ]),
          ],
          () => _message('Document.complete', [documentId]),
        ];
      }
    } else if (decoded is Map<String, dynamic> &&
        decoded['id'] is String &&
        decoded['code'] is String) {
      seed = decoded;
    }
    return ZoteroHttpResponse(
      statusCode: 200,
      body: jsonEncode(script[step++]()),
    );
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<WordEditorController> _open(
  WidgetTester tester,
  _CatalogDesktop desktop, {
  String? preferences,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1300, 1000);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final document = WmlDocument.empty(text: 'Before after');
  document.zoteroDocumentData = preferences;
  final controller = WordEditorController(document: document);
  controller.caret.logicalIndex = 7;
  controller.caret.collapseSelection();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showWordZoteroDialog(
              context,
              controller: controller,
              localTransport: desktop.send,
              session: ZoteroSession()
                ..useLocal = true
                ..apiKey = 'cloud-key-must-never-be-sent',
            ),
            child: const Text('Open catalog'),
          ),
        ),
      ),
    ),
  );
  await _tap(tester, find.text('Open catalog'));
  await _tap(tester, find.byKey(const ValueKey('zotero-connect-desktop')));
  if (desktop.savedSearch) {
    expect(find.text('Local catalog source'), findsNothing);
    await _tap(tester, find.widgetWithText(ChoiceChip, 'Saved searches'));
    await _tap(
      tester,
      find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            widget.decoration.labelText == 'Saved search',
      ),
    );
    await _tap(tester, find.text('Sources for this paper').last);
  }
  await _tap(
    tester,
    find.widgetWithText(CheckboxListTile, 'Local catalog source'),
  );
  expect(find.text('1 selected'), findsOneWidget);
  expect(
    find.widgetWithText(FilledButton, 'Insert with Zotero…'),
    findsOneWidget,
  );
  expect(
    find.widgetWithText(OutlinedButton, 'Insert basic citation'),
    findsOneWidget,
  );
  return controller;
}

void _expectUntouched(WordEditorController controller) {
  expect(controller.document.paragraphs.single.text, 'Before after');
  expect(controller.zoteroFields, isEmpty);
  expect(controller.document.footnotes, isEmpty);
  expect(controller.document.endnotes, isEmpty);
  expect(WordZoteroDocumentData.read(controller.document), isEmpty);
  expect(controller.canUndo, isFalse);
}

void main() {
  testWidgets(
    'a saved-search source seeds native first insertion and survives DOCX and undo',
    (tester) async {
      final desktop = _CatalogDesktop(savedSearch: true);
      final controller = await _open(tester, desktop);
      expect(
        desktop.requests.last.uri.path,
        '/api/users/0/searches/SEARCH01/items',
      );
      await _tap(tester, find.text('Insert with Zotero…'));
      expect(desktop.commands, ['setDocPrefs', 'addEditCitation']);
      expect(desktop.ids.toSet(), hasLength(1));
      expect(desktop.seed!['code'], contains(_uri));
      expect(controller.document.footnotes, hasLength(1));
      expect(controller.zoteroFields.single.cachedText, 'Ebd., 34.');
      expect(find.text('0 selected'), findsOneWidget);
      final reopened = WordDeserializer().readBytes(controller.saveBytes());
      final citation = WordZotero.fields(reopened).single.citation!;
      expect(citation.items.single.uris, [_uri]);
      expect(citation.items.single.locator, '34');
      expect(citation.items.single.label, 'page');
      controller.undo();
      _expectUntouched(controller);
      expect(controller.caret.logicalIndex, 7);
      expect(tester.takeException(), isNull);
    },
  );

  for (final noteType in [0, 1, 2]) {
    testWidgets(
      'first catalog insertion chooses placement $noteType in one undo',
      (tester) async {
        final desktop = _CatalogDesktop(noteType: noteType);
        final controller = await _open(tester, desktop);
        await _tap(tester, find.text('Insert with Zotero…'));
        expect(desktop.commands, ['setDocPrefs', 'addEditCitation']);
        expect(desktop.ids.toSet(), hasLength(1));
        expect(desktop.seed!['code'], contains(_uri));
        expect(desktop.seed!['noteIndex'], noteType == 0 ? 0 : 1);
        expect(controller.zoteroFields.single.cachedText, 'Ebd., 34.');
        expect(
          controller.zoteroFields.single.citation!.items.single.locator,
          '34',
        );
        expect(controller.document.footnotes, hasLength(noteType == 1 ? 1 : 0));
        expect(controller.document.endnotes, hasLength(noteType == 2 ? 1 : 0));
        expect(find.text('0 selected'), findsOneWidget);
        final reopened = WordDeserializer().readBytes(controller.saveBytes());
        expect(WordZotero.fields(reopened).single.cachedText, 'Ebd., 34.');
        await _tap(tester, find.text('Document'));
        expect(
          find.textContaining(
            'Document style: chicago-notes-bibliography-subsequent-ibid',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('Language: de-DE'), findsOneWidget);
        controller.undo();
        _expectUntouched(controller);
        expect(controller.caret.logicalIndex, 7);
        controller.redo();
        expect(controller.zoteroFields.single.cachedText, 'Ebd., 34.');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'saved document style goes directly to the seeded native picker',
    (tester) async {
      final desktop = _CatalogDesktop(noteType: 2);
      final controller = await _open(
        tester,
        desktop,
        preferences: _preferences(2),
      );
      await _tap(tester, find.text('Insert with Zotero…'));
      expect(desktop.commands, ['addEditCitation']);
      expect(controller.document.endnotes, hasLength(1));
      controller.undo();
      expect(controller.zoteroFields, isEmpty);
      expect(
        WordZoteroDocumentData.citationNoteType(
          WordZoteroDocumentData.read(controller.document),
        ),
        2,
      );
      expect(controller.canUndo, isFalse);
    },
  );

  testWidgets('cancelling the first style chooser retains catalog selection', (
    tester,
  ) async {
    final desktop = _CatalogDesktop()..cancelStyle = true;
    final controller = await _open(tester, desktop);
    await _tap(tester, find.text('Insert with Zotero…'));
    expect(desktop.commands, ['setDocPrefs']);
    _expectUntouched(controller);
    expect(find.text('1 selected'), findsOneWidget);
    expect(
      find.textContaining('No document style was selected'),
      findsOneWidget,
    );
  });

  testWidgets('cancelling the following picker also discards staged style', (
    tester,
  ) async {
    final desktop = _CatalogDesktop()..cancelCitation = true;
    final controller = await _open(tester, desktop);
    await _tap(tester, find.text('Insert with Zotero…'));
    expect(desktop.commands, ['setDocPrefs', 'addEditCitation']);
    _expectUntouched(controller);
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.textContaining('No citation was inserted'), findsOneWidget);
  });

  testWidgets('a failed picker never commits the preceding style choice', (
    tester,
  ) async {
    final desktop = _CatalogDesktop()..failCitation = true;
    final controller = await _open(tester, desktop);
    await _tap(tester, find.text('Insert with Zotero…'));
    expect(desktop.commands, ['setDocPrefs', 'addEditCitation']);
    _expectUntouched(controller);
    expect(find.text('1 selected'), findsOneWidget);
  });

  testWidgets('preferences stay detached while the next native dialog waits', (
    tester,
  ) async {
    final gate = Completer<void>();
    final desktop = _CatalogDesktop()..citationGate = gate;
    final controller = await _open(tester, desktop);
    final insert = find.text('Insert with Zotero…');
    await tester.ensureVisible(insert);
    await tester.tap(insert);
    for (var i = 0; i < 20 && desktop.commands.length < 2; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(desktop.commands, ['setDocPrefs', 'addEditCitation']);
    _expectUntouched(controller);
    expect(find.text('Cancel operation'), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(controller.zoteroFields.single.cachedText, 'Ebd., 34.');
  });

  for (final cancel in [true, false]) {
    testWidgets(
      cancel
          ? 'Cancel operation discards both native stages'
          : 'a changed insertion point discards both native stages',
      (tester) async {
        final gate = Completer<void>();
        final desktop = _CatalogDesktop()
          ..citationGate = gate
          ..cancelCitation = true;
        final controller = await _open(tester, desktop);
        final insert = find.text('Insert with Zotero…');
        await tester.ensureVisible(insert);
        await tester.tap(insert);
        for (var i = 0; i < 20 && desktop.commands.length < 2; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(desktop.commands, ['setDocPrefs', 'addEditCitation']);
        _expectUntouched(controller);
        if (cancel) {
          await tester.tap(find.text('Cancel operation'));
          await tester.pump();
        } else {
          controller.caret.logicalIndex = 8;
        }
        gate.complete();
        await tester.pumpAndSettle();
        _expectUntouched(controller);
        expect(find.text('1 selected'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
