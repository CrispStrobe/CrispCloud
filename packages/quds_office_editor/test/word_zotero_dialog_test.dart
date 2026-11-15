import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _offlineSource = <String, dynamic>{
  'id': 'offline-paper',
  'type': 'article-journal',
  'title': 'A research source',
  'author': [
    {'family': 'Hassan', 'given': 'Amal'},
  ],
  'issued': {
    'date-parts': [
      [2024],
    ],
  },
};

Future<WordEditorController> _openDialog(
  WidgetTester tester, {
  ZoteroTransport? transport,
  ZoteroSession? session,
  Size size = const Size(1200, 900),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = WordEditorController(
    document: WmlDocument.empty(text: 'Before after'),
  );
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
              transport: transport,
              session: session,
            ),
            child: const Text('Open references'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open references'));
  await tester.pumpAndSettle();
  return controller;
}

Future<void> _importAndCompose(WidgetTester tester) async {
  await tester.tap(find.text('Import CSL JSON'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('zotero-csl-import')),
    jsonEncode({
      'items': [_offlineSource],
    }),
  );
  await tester.tap(find.widgetWithText(OutlinedButton, 'Load references'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(CheckboxListTile, 'A research source'));
  await tester.pumpAndSettle();
  await tester.tap(
    find.widgetWithText(FilledButton, 'Insert 1 selected source(s)'),
  );
  // The parent may keep an indeterminate busy indicator under this modal.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  expect(find.text('Insert Zotero citation'), findsOneWidget);
}

Finder _composerButton(String text) => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.widgetWithText(FilledButton, text),
);

Map<String, dynamic> _apiItem(String key, String title) => {
  'key': key,
  'version': 1,
  'library': {'type': 'user', 'id': 42},
  'data': {
    'key': key,
    'itemType': 'journalArticle',
    'title': title,
    'date': '2024',
    'creators': [
      {'creatorType': 'author', 'firstName': 'Amal', 'lastName': 'Hassan'},
    ],
  },
  'csljson': {..._offlineSource, 'id': '999/$key', 'title': title},
};

ZoteroHttpResponse _json(
  Object body, {
  Map<String, String> headers = const {},
}) => ZoteroHttpResponse(
  statusCode: 200,
  body: jsonEncode(body),
  headers: headers,
);

void main() {
  testWidgets('offline CSL import inserts source metadata and can be undone', (
    tester,
  ) async {
    final controller = await _openDialog(tester);
    final initialRevision = controller.contentRevision;
    await _importAndCompose(tester);
    final preview = tester.widget<TextField>(
      find.byKey(const ValueKey('zotero-citation-preview')),
    );
    expect(preview.controller!.text, '(Hassan, 2024)');
    expect(find.text('Offline embedded source'), findsOneWidget);
    await tester.tap(_composerButton('Insert citation'));
    await tester.pumpAndSettle();
    expect(
      controller.document.paragraphs.single.text,
      'Before (Hassan, 2024)after',
    );
    final field = controller.zoteroFields.single;
    expect(
      field.citation!.items.single.itemData!['title'],
      'A research source',
    );
    expect(field.citation!.items.single.uris, isEmpty);
    expect(field.citation!.properties['qudsFormat'], 'basic-author-year');
    expect(controller.contentRevision, greaterThan(initialRevision));
    expect(controller.canUndo, isTrue);
    await tester.tap(find.byTooltip('Close Zotero'));
    await tester.pumpAndSettle();
    controller.undo();
    expect(controller.document.paragraphs.single.text, 'Before after');
    expect(controller.zoteroFields, isEmpty);
    controller.redo();
    expect(
      controller.zoteroFields.single.citation!.items.single.id,
      'offline-paper',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'cancelling the citation composer leaves document and history unchanged',
    (tester) async {
      final controller = await _openDialog(tester);
      final revision = controller.contentRevision;
      await _importAndCompose(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(TextButton, 'Cancel'),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.document.paragraphs.single.text, 'Before after');
      expect(controller.zoteroFields, isEmpty);
      expect(controller.contentRevision, revision);
      expect(controller.canUndo, isFalse);
      expect(find.text('Zotero references'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final change in ['caret', 'revision']) {
    testWidgets(
      'a changed $change while the composer is open blocks stale insertion',
      (tester) async {
        final controller = await _openDialog(tester);
        await _importAndCompose(tester);
        if (change == 'caret') {
          controller.caret.logicalIndex = 0;
          controller.caret.collapseSelection();
        } else {
          controller.insertText('Changed ');
          controller.commitPendingEdits();
        }
        final text = controller.document.paragraphs.single.text;
        final revision = controller.contentRevision;
        await tester.tap(_composerButton('Insert citation'));
        await tester.pumpAndSettle();
        expect(controller.zoteroFields, isEmpty);
        expect(controller.document.paragraphs.single.text, text);
        expect(controller.contentRevision, revision);
        expect(
          find.textContaining('document or insertion point changed'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'mock Web API connection, pagination and search keep the key outside the document',
    (tester) async {
      const secret = 'test-only-secret-that-must-never-be-saved';
      final requests = <ZoteroHttpRequest>[];
      final session = ZoteroSession();
      final controller = await _openDialog(
        tester,
        session: session,
        transport: (request) async {
          requests.add(request);
          expect(request.uri.scheme, 'https');
          expect(request.uri.host, 'api.zotero.org');
          expect(request.followRedirects, isFalse);
          expect(request.headers['Zotero-API-Key'], secret);
          expect(request.uri.toString(), isNot(contains(secret)));
          switch (request.uri.path) {
            case '/keys/current':
              return _json({
                'userID': 42,
                'username': 'Researcher',
                'access': {
                  'user': {'library': true},
                },
              });
            case '/users/42/groups':
              return _json([
                {
                  'id': 77,
                  'data': {'name': 'Shared lab'},
                },
              ]);
            case '/users/42/collections':
              return _json([
                {
                  'key': 'COLL0001',
                  'data': {'name': 'Research', 'parentCollection': false},
                },
              ]);
            case '/users/42/items/top':
              if (request.uri.queryParameters['q']?.isNotEmpty == true) {
                return _json(
                  [_apiItem('IJKL9012', 'Search source')],
                  headers: {'Total-Results': '1'},
                );
              }
              if (request.uri.queryParameters['start'] == '50') {
                return _json(
                  [_apiItem('EFGH5678', 'Second source')],
                  headers: {'Total-Results': '51'},
                );
              }
              return _json(
                [_apiItem('ABCD1234', 'First source')],
                headers: {'Total-Results': '51'},
              );
            case '/users/42/items/IJKL9012':
              return _json({
                ..._apiItem('IJKL9012', 'Search source'),
                'citation': '<span>(Hassan, 2024)</span>',
              });
            default:
              fail('Unexpected request path: ${request.uri.path}');
          }
        },
      );
      await tester.enterText(
        find.byKey(const ValueKey('zotero-api-key')),
        secret,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
      await tester.pumpAndSettle();
      expect(find.text('First source'), findsOneWidget);
      expect(session.apiKey, secret);
      expect(session.rememberKey, isFalse);
      expect(find.textContaining('Connected as Researcher'), findsOneWidget);

      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      expect(find.text('Second source'), findsOneWidget);
      expect(requests.last.uri.queryParameters['start'], '50');

      final search = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Search title, creator, or year',
      );
      await tester.enterText(search, 'Hassan & 2024');
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      expect(find.text('Search source'), findsOneWidget);
      expect(requests.last.uri.queryParameters['q'], 'Hassan & 2024');
      expect(requests.last.uri.queryParameters['start'], '0');

      await tester.tap(find.widgetWithText(CheckboxListTile, 'Search source'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Insert citation'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(_composerButton('Insert citation'));
      await tester.pumpAndSettle();
      final source = controller.zoteroFields.single.citation!.items.single;
      expect(source.uris, ['http://zotero.org/users/42/items/IJKL9012']);
      expect(source.itemData!['title'], 'Search source');
      final zip = ZipReader.open(MemoryByteSource(controller.saveBytes()));
      for (final entry in zip.entries.where((entry) => !entry.isDirectory)) {
        expect(
          utf8.decode(zip.read(entry.fileName), allowMalformed: true),
          isNot(contains(secret)),
          reason: entry.fileName,
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('dialog, offline import and composer fit a 320 by 640 viewport', (
    tester,
  ) async {
    await _openDialog(tester, size: const Size(320, 640));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Document'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await _importAndCompose(tester);
    expect(tester.takeException(), isNull);
    final button = _composerButton('Insert citation');
    await tester.ensureVisible(button);
    expect(tester.getRect(button).bottom, lessThanOrEqualTo(640));
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Cancel'),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
