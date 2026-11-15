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
  ZoteroTransport? localTransport,
  ZoteroSession? session,
  Future<void> Function(String? apiKey)? persistApiKey,
  WmlDocument? document,
  Size size = const Size(1200, 900),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = WordEditorController(
    document: document ?? WmlDocument.empty(text: 'Before after'),
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
              localTransport: localTransport,
              session: session,
              persistApiKey: persistApiKey,
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
  final tab = find.text('Import CSL JSON');
  await tester.ensureVisible(tab);
  await tester.pump();
  await tester.tap(tab);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('zotero-csl-import')),
    jsonEncode({
      'items': [_offlineSource],
    }),
  );
  final load = find.widgetWithText(OutlinedButton, 'Load references');
  await tester.ensureVisible(load);
  await tester.pump();
  await tester.tap(load);
  await tester.pumpAndSettle();
  final source = find.widgetWithText(CheckboxListTile, 'A research source');
  await tester.ensureVisible(source);
  await tester.pump();
  await tester.tap(source);
  await tester.pumpAndSettle();
  final insert = find.widgetWithText(
    FilledButton,
    'Insert 1 selected source(s)',
  );
  await tester.ensureVisible(insert);
  await tester.pump();
  await tester.tap(insert);
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

void _expectNoSavedSecret(WordEditorController controller, String secret) {
  final zip = ZipReader.open(MemoryByteSource(controller.saveBytes()));
  for (final entry in zip.entries.where((entry) => !entry.isDirectory)) {
    expect(
      utf8.decode(zip.read(entry.fileName), allowMalformed: true),
      isNot(contains(secret)),
      reason: entry.fileName,
    );
  }
}

void main() {
  for (final identity in ['account', 'unsynced', 'citation-key']) {
    testWidgets(
      'desktop $identity source inserts without using the saved cloud key',
      (tester) async {
        const secret = 'cloud-key-never-sent-to-local-zotero';
        const key = 'ABCD1234';
        const localUri =
            'http://zotero.org/users/local/LOCALKEY/items/ABCD1234';
        final session = ZoteroSession()
          ..apiKey = secret
          ..rememberKey = true
          ..useLocal = true;
        final requests = <ZoteroHttpRequest>[];
        final writes = <String?>[];
        final controller = await _openDialog(
          tester,
          session: session,
          transport: (_) async =>
              throw StateError('Cloud transport must stay unused'),
          persistApiKey: (key) async => writes.add(key),
          localTransport: (request) async {
            requests.add(request);
            expect(request.uri.scheme, 'http');
            expect(request.uri.host, 'localhost');
            expect(request.uri.port, 23119);
            expect(request.headers.containsKey('Zotero-API-Key'), isFalse);
            expect(request.headers['Zotero-Allowed-Request'], '1');
            expect(request.followRedirects, isFalse);
            if (request.uri.path == '/api/') {
              return ZoteroHttpResponse(
                statusCode: 200,
                body: 'Nothing to see here.',
                headers: const {
                  'Zotero-API-Version': '3',
                  'Zotero-Server-ID': 'desktop-library',
                },
              );
            }
            expect(request.headers['Zotero-Server-ID'], 'desktop-library');
            final Object body;
            switch (request.uri.path) {
              case '/api/users/0/groups':
              case '/api/users/0/collections':
                body = <Object>[];
              case '/api/users/0/items/top':
                body = [
                  {
                    ..._apiItem(key, 'Desktop source'),
                    'library': {
                      'type': 'user',
                      'id': identity == 'account' ? 42 : 0,
                    },
                    'csljson': jsonEncode([
                      {
                        ..._offlineSource,
                        'title': 'Desktop source',
                        'id': identity == 'unsynced' ? localUri : 'Hassan2024',
                      },
                    ]),
                  },
                ];
              default:
                throw StateError('Unexpected desktop path');
            }
            return _json(
              body,
              headers: const {'Zotero-Server-ID': 'desktop-library'},
            );
          },
        );
        expect(find.byKey(const ValueKey('zotero-api-key')), findsNothing);
        expect(
          requests,
          isEmpty,
          reason: 'Desktop access requires an explicit connection',
        );
        await tester.tap(find.byKey(const ValueKey('zotero-connect-desktop')));
        await tester.pumpAndSettle();
        expect(requests, hasLength(4));
        expect(find.text('Desktop source'), findsOneWidget);
        final source = find.widgetWithText(CheckboxListTile, 'Desktop source');
        await tester.ensureVisible(source);
        await tester.tap(source);
        await tester.pumpAndSettle();
        if (identity == 'citation-key') {
          expect(
            find.textContaining('embedded without a Zotero link'),
            findsOneWidget,
          );
        }
        final insert = find.widgetWithText(FilledButton, 'Insert citation');
        await tester.ensureVisible(insert);
        await tester.tap(insert);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.tap(_composerButton('Insert citation'));
        await tester.pumpAndSettle();
        final item = controller.zoteroFields.single.citation!.items.single;
        expect(item.itemData!['title'], 'Desktop source');
        expect(item.uris, switch (identity) {
          'account' => ['http://zotero.org/users/42/items/ABCD1234'],
          'unsynced' => [localUri],
          _ => <String>[],
        });
        if (identity == 'citation-key') {
          expect(item.id, startsWith('quds-offline-'));
        }
        expect(writes, isEmpty);
        expect(session.apiKey, secret);
        expect(session.rememberKey, isTrue);
        _expectNoSavedSecret(controller, secret);
        _expectNoSavedSecret(controller, '/users/0');
        final disconnect = find.text('Disconnect desktop');
        await tester.ensureVisible(disconnect);
        await tester.tap(disconnect);
        await tester.pumpAndSettle();
        expect(session.apiKey, secret);
        expect(writes, isEmpty);
        expect(find.text('Desktop source'), findsNothing);
        expect(controller.zoteroFields, hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'switching sources makes no requests and preserves the cloud credential',
    (tester) async {
      final session = ZoteroSession()..apiKey = 'retained-cloud-key';
      var calls = 0;
      Future<ZoteroHttpResponse> transport(ZoteroHttpRequest _) async {
        calls++;
        throw StateError('Do not connect while changing a preference');
      }

      await _openDialog(
        tester,
        session: session,
        transport: transport,
        localTransport: transport,
      );
      final source = find.byKey(const ValueKey('zotero-library-source'));
      await tester.tap(source);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zotero desktop (this computer)').last);
      await tester.pumpAndSettle();
      expect(session.useLocal, isTrue);
      expect(find.byKey(const ValueKey('zotero-api-key')), findsNothing);
      await tester.tap(source);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Online Zotero library').last);
      await tester.pumpAndSettle();
      expect(session.useLocal, isFalse);
      expect(session.apiKey, 'retained-cloud-key');
      expect(calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a host without desktop transport offers only the supported source',
    (tester) async {
      final session = ZoteroSession()..useLocal = true;
      await _openDialog(tester, session: session);
      expect(session.useLocal, isFalse);
      expect(find.byKey(const ValueKey('zotero-library-source')), findsNothing);
      expect(
        find.byKey(const ValueKey('zotero-connect-desktop')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('desktop connection and errors fit a 320 by 640 viewport', (
    tester,
  ) async {
    final session = ZoteroSession()..useLocal = true;
    final controller = await _openDialog(
      tester,
      size: const Size(320, 640),
      session: session,
      localTransport: (_) async =>
          ZoteroHttpResponse(statusCode: 403, body: 'private diagnostic'),
    );
    final revision = controller.contentRevision;
    expect(tester.takeException(), isNull);
    final connect = find.byKey(const ValueKey('zotero-connect-desktop'));
    await tester.ensureVisible(connect);
    await tester.tap(connect);
    await tester.pumpAndSettle();
    expect(find.textContaining('Settings'), findsWidgets);
    expect(find.textContaining('private diagnostic'), findsNothing);
    expect(controller.contentRevision, revision);
    expect(controller.zoteroFields, isEmpty);
    expect(tester.takeException(), isNull);
  });

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
      _expectNoSavedSecret(controller, secret);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unchecking Remember removes the saved key immediately without connecting',
    (tester) async {
      const secret = 'persisted-test-key-not-document-content';
      final writes = <String?>[];
      final session = ZoteroSession()
        ..apiKey = secret
        ..rememberKey = true;
      final controller = await _openDialog(
        tester,
        session: session,
        persistApiKey: (key) async {
          writes.add(key);
        },
      );
      final revision = controller.contentRevision;
      expect(writes, isEmpty);
      final checkbox = find.byType(Checkbox);
      expect(tester.widget<Checkbox>(checkbox).value, isTrue);
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      expect(writes, <String?>[null]);
      expect(session.rememberKey, isFalse);
      expect(
        session.apiKey,
        secret,
        reason: 'The existing session may stay connected.',
      );
      expect(find.textContaining('connection is session-only'), findsOneWidget);
      expect(controller.contentRevision, revision);
      expect(controller.canUndo, isFalse);
      _expectNoSavedSecret(controller, secret);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'imported bibliography customizations cannot be overwritten by basic update',
    (tester) async {
      const uri = 'http://zotero.org/users/42/items/ABCD1234';
      for (final customization in ['uncited', 'omitted', 'custom']) {
        final document = WmlDocument.empty(text: 'Before after');
        WordZotero.insertCitation(
          document.paragraphs.single,
          ZoteroCitation(
            citationId: 'imported-citation',
            plainCitation: '(Hassan, 2024)',
            items: [
              ZoteroCitationItem.fromJson({
                'id': 'offline-paper',
                'itemData': _offlineSource,
              }),
            ],
          ),
        );
        document.sections.single.blocks.add(
          WordZotero.bibliography(
            text: 'Preserved bibliography',
            metadata: {
              'uncited': <dynamic>[],
              'omitted': <dynamic>[],
              'custom': <dynamic>[],
              customization: customization == 'custom'
                  ? [
                      [uri, 'Custom reference'],
                    ]
                  : [
                      [uri],
                    ],
            },
          ),
        );
        final controller = await _openDialog(tester, document: document);
        final before = controller.zoteroFields.last;
        final metadata = jsonEncode(before.metadata);
        final revision = controller.contentRevision;
        final texts = document.paragraphs
            .map((paragraph) => paragraph.text)
            .toList();
        await tester.tap(find.text('Document'));
        await tester.pumpAndSettle();
        final row = find.ancestor(
          of: find.text('Preserved bibliography'),
          matching: find.byType(ListTile),
        );
        await tester.ensureVisible(row);
        await tester.pump();
        await tester.tap(
          find.descendant(
            of: row,
            matching: find.byTooltip('Reference actions'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Update basic bibliography'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('additions, exclusions, or custom entries'),
          findsOneWidget,
          reason: customization,
        );
        expect(find.byType(AlertDialog), findsNothing);
        expect(
          controller.zoteroFields.last.cachedText,
          'Preserved bibliography',
        );
        expect(jsonEncode(controller.zoteroFields.last.metadata), metadata);
        expect(document.paragraphs.map((paragraph) => paragraph.text), texts);
        expect(controller.contentRevision, revision);
        expect(controller.canUndo, isFalse);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Close Zotero'));
        await tester.pumpAndSettle();
      }
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
