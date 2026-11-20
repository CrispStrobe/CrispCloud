import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _parentKey = 'SOURCE01';
const _apiKey = 'children-dialog-test-key';
const _serverId = 'children-dialog-database';
const _noteText = 'Research & evidence';
const _staleMessage =
    'The Zotero connection or library changed. Close this view and reopen the reference details.';

Finder _key(String value) => find.byKey(ValueKey(value));
Finder _query() => find.byWidgetPredicate(
  (widget) =>
      widget is TextField &&
      widget.decoration?.labelText == 'Search title, creator, or year',
);

class _Catalog {
  _Catalog({this.local = false, this.identifiesDatabase = true});

  final bool local;
  final bool identifiesDatabase;
  final requests = <ZoteroHttpRequest>[];
  Completer<ZoteroHttpResponse>? pendingChildren;

  String get sourceId => local
      ? 'http://zotero.org/users/local/LOCALKEY/items/$_parentKey'
      : 'http://zotero.org/users/42/items/$_parentKey';

  List<ZoteroHttpRequest> get childrenRequests => requests
      .where((request) => request.uri.path.endsWith('/children'))
      .toList();

  List<ZoteroHttpRequest> get catalogRequests => requests
      .where((request) => request.uri.path.endsWith('/items/top'))
      .toList();

  ZoteroHttpResponse json(
    Object value, {
    Map<String, String> headers = const {},
  }) => ZoteroHttpResponse(
    statusCode: 200,
    body: jsonEncode(value),
    headers: {
      if (local && identifiesDatabase) 'Zotero-Server-ID': _serverId,
      ...headers,
    },
  );

  Map<String, Object?> child(
    String key,
    String type,
    Map<String, Object?> data,
  ) => {
    'key': key,
    'version': 12,
    'library': {'type': 'user', 'id': local ? 0 : 42},
    'data': {
      'key': key,
      'version': 12,
      'parentItem': _parentKey,
      'itemType': type,
      ...data,
    },
  };

  ZoteroHttpResponse childrenResponse() => json(
    [
      child('NOTE0001', 'note', {'note': '<p>Research &amp; evidence</p>'}),
      child('ATTACH01', 'attachment', {
        'title': 'Full text PDF',
        'filename': 'research.pdf',
        'contentType': 'application/pdf',
        'linkMode': 'imported_file',
        'note': '<p>Attachment note</p>',
        'url': 'https://example.org/research.pdf',
      }),
    ],
    headers: {'Total-Results': '2', 'Last-Modified-Version': '12'},
  );

  Future<ZoteroHttpResponse> send(ZoteroHttpRequest request) async {
    requests.add(request);
    expect(request.method, 'GET');
    expect(request.body, isNull);
    expect(request.followRedirects, isFalse);
    expect(request.uri.host, local ? 'localhost' : 'api.zotero.org');
    expect(request.headers['Zotero-API-Key'], local ? isNull : _apiKey);
    final path = request.uri.path;
    if (path == '/api/') {
      return ZoteroHttpResponse(
        statusCode: 200,
        body: 'Local API',
        headers: {
          'Zotero-API-Version': '3',
          if (identifiesDatabase) 'Zotero-Server-ID': _serverId,
        },
      );
    }
    if (path == '/keys/current') {
      return json({
        'userID': 42,
        'username': 'Researcher',
        'access': {
          'user': {'library': true},
        },
      });
    }
    if (path.endsWith('/groups') ||
        path.endsWith('/collections') ||
        path.endsWith('/searches')) {
      return json(<Object>[]);
    }
    if (path.endsWith('/children')) {
      expect(
        path,
        local
            ? '/api/users/0/items/$_parentKey/children'
            : '/users/42/items/$_parentKey/children',
      );
      expect(request.uri.queryParameters['include'], 'data');
      expect(request.uri.queryParameters['limit'], '25');
      expect(request.headers['Zotero-Server-ID'], local ? _serverId : isNull);
      return pendingChildren?.future ?? childrenResponse();
    }
    if (path.endsWith('/items/top')) {
      return json([
        {
          'key': _parentKey,
          'version': 11,
          'library': {'type': 'user', 'id': local ? 0 : 42},
          'data': {
            'key': _parentKey,
            'itemType': 'book',
            'title': 'Source research',
            'date': '2026',
            'tags': [
              {'tag': 'Research'},
            ],
          },
          'csljson': {
            'id': sourceId,
            'type': 'book',
            'title': 'Source research',
          },
        },
      ]);
    }
    throw StateError('Unexpected catalog path: $path');
  }
}

class _Harness {
  _Harness(
    this.controller,
    this.session,
    this.savedParts,
    this.savedModifiedIso,
    this.clipboard,
  );

  final WordEditorController controller;
  final ZoteroSession session;
  final Map<String, String> savedParts;
  final String savedModifiedIso;
  final List<String> clipboard;
}

Map<String, String> _savedParts(WordEditorController controller) {
  final zip = ZipReader.open(MemoryByteSource(controller.saveBytes()));
  return {
    for (final entry in zip.entries)
      if (!entry.isDirectory)
        entry.fileName: entry.fileName == 'docProps/core.xml'
            // A save updates this timestamp even if no UI was opened. Keep
            // every other byte, including the creation date and revision.
            ? utf8
                  .decode(zip.read(entry.fileName))
                  .replaceFirstMapped(
                    RegExp(
                      r'(<dcterms:modified\b[^>]*>)[^<]*(</dcterms:modified>)',
                    ),
                    (match) => '${match[1]}save timestamp${match[2]}',
                  )
            : base64Encode(zip.read(entry.fileName)),
  };
}

Future<void> _tap(
  WidgetTester tester,
  Finder finder, {
  bool settle = true,
}) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
  expect(tester.takeException(), isNull);
}

Future<_Harness> _open(
  WidgetTester tester,
  _Catalog catalog, {
  OfficeInteractionMode mode = OfficeInteractionMode.editing,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 1200);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final controller = WordEditorController(
    document: WmlDocument.empty(text: 'Document stays unchanged'),
    config: OfficeSurfaceConfig(mode: mode),
  );
  controller.caret.logicalIndex = 5;
  controller.caret.collapseSelection();
  controller.proofing.enabled = false;
  addTearDown(controller.dispose);
  // Materialize the new DOCX package before the baseline. Subsequent saves
  // preserve its note separator nodes with their explicit namespaces.
  _savedParts(controller);
  final savedParts = _savedParts(controller);
  final savedModifiedIso = controller.document.properties.modifiedIso;
  final session = ZoteroSession()
    ..apiKey = _apiKey
    ..useLocal = catalog.local;
  final clipboard = <String>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      final args = call.arguments as Map<Object?, Object?>;
      clipboard.add(args['text']! as String);
    }
    if (call.method == 'Clipboard.hasStrings') {
      return {'value': clipboard.isNotEmpty};
    }
    if (call.method == 'Clipboard.getData') {
      return {'text': clipboard.lastOrNull};
    }
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showWordZoteroDialog(
              context,
              controller: controller,
              session: session,
              transport: catalog.local ? null : catalog.send,
              localTransport: catalog.local ? catalog.send : null,
              initialTab: WordZoteroTab.library,
            ),
            child: const Text('Open references'),
          ),
        ),
      ),
    ),
  );
  await _tap(tester, find.text('Open references'));
  await _tap(tester, find.text(catalog.local ? 'Connect desktop' : 'Connect'));
  return _Harness(controller, session, savedParts, savedModifiedIso, clipboard);
}

Future<void> _details(WidgetTester tester, _Catalog catalog) async {
  final finder = _key('zotero-details-${catalog.sourceId}');
  expect(tester.widget<IconButton>(finder).onPressed, isNotNull);
  await _tap(tester, finder);
}

Future<void> _browse(WidgetTester tester, {bool settle = true}) =>
    _tap(tester, _key('zotero-browse-item-children'), settle: settle);

Future<void> _closeDetails(WidgetTester tester) => _tap(
  tester,
  find.descendant(
    of: _key('zotero-item-details-dialog'),
    matching: find.widgetWithText(TextButton, 'Close'),
  ),
);

void _unchanged(_Harness harness) {
  final controller = harness.controller;
  expect(
    controller.document.paragraphs.single.text,
    'Document stays unchanged',
  );
  expect(controller.zoteroFields, isEmpty);
  expect(controller.contentRevision, 0);
  expect(controller.isDirty, isFalse);
  expect(controller.canUndo, isFalse);
  expect(controller.canRedo, isFalse);
  expect(controller.caret.paragraphIndex, 0);
  expect(controller.caret.logicalIndex, 5);
  expect(controller.document.properties.modifiedIso, harness.savedModifiedIso);
  final actual = _savedParts(controller);
  expect(actual.keys, unorderedEquals(harness.savedParts.keys));
  for (final entry in harness.savedParts.entries) {
    expect(actual[entry.key], entry.value, reason: entry.key);
  }
}

void main() {
  for (final local in <bool>[false, true]) {
    testWidgets(
      '${local ? 'desktop' : 'online'} children are explicitly fetched and preserve selection and drafts',
      (tester) async {
        final catalog = _Catalog(local: local);
        final harness = await _open(tester, catalog);
        await tester.enterText(_query(), 'submitted query');
        await _tap(tester, find.byTooltip('Search'));
        await _tap(
          tester,
          find.widgetWithText(CheckboxListTile, 'Source research'),
        );
        await _tap(tester, find.byTooltip('Search options'));
        await tester.enterText(_query(), 'unfinished main query');
        await tester.enterText(_key('zotero-tag-input'), 'unfinished tag');
        await tester.pumpAndSettle();
        final requestsBeforeDetails = catalog.requests.length;
        final catalogRequestsBeforeDetails = catalog.catalogRequests.length;
        await _details(tester, catalog);
        expect(catalog.requests, hasLength(requestsBeforeDetails));
        expect(catalog.childrenRequests, isEmpty);
        await _browse(tester);
        expect(_key('zotero-item-children-dialog'), findsOneWidget);
        expect(catalog.childrenRequests, hasLength(1));
        expect(_key('zotero-child-NOTE0001'), findsOneWidget);
        expect(_key('zotero-child-ATTACH01'), findsOneWidget);
        await _tap(tester, _key('zotero-child-NOTE0001'));
        expect(
          tester.widget<SelectableText>(_key('zotero-child-note-text')).data,
          _noteText,
        );
        await _tap(tester, _key('zotero-copy-child-note'));
        expect(harness.clipboard, <String>[_noteText]);
        await _tap(tester, _key('zotero-child-details-back'));
        await _tap(tester, _key('zotero-child-ATTACH01'));
        expect(find.text('research.pdf'), findsOneWidget);
        expect(find.text('Stored file'), findsOneWidget);
        await _tap(tester, _key('zotero-copy-child-details'));
        expect(harness.clipboard.last, contains('Filename: research.pdf'));
        expect(harness.clipboard.last, isNot(contains(_apiKey)));
        await _tap(tester, _key('zotero-child-details-back'));
        await _tap(tester, _key('zotero-children-close'));
        expect(_key('zotero-item-details-dialog'), findsOneWidget);
        await _closeDetails(tester);
        expect(find.text('1 selected'), findsOneWidget);
        expect(
          tester
              .widget<CheckboxListTile>(
                find.widgetWithText(CheckboxListTile, 'Source research'),
              )
              .value,
          isTrue,
        );
        expect(
          tester.widget<TextField>(_query()).controller!.text,
          'unfinished main query',
        );
        expect(
          tester.widget<TextField>(_key('zotero-tag-input')).controller!.text,
          'unfinished tag',
        );
        expect(
          catalog.catalogRequests,
          hasLength(catalogRequestsBeforeDetails),
        );
        expect(
          catalog.catalogRequests.last.uri.queryParameters['q'],
          'submitted query',
        );
        expect(catalog.childrenRequests, hasLength(1));
        expect(catalog.requests, hasLength(requestsBeforeDetails + 1));
        _unchanged(harness);
      },
    );
  }

  testWidgets('headerless desktop explains why child browsing is disabled', (
    tester,
  ) async {
    final catalog = _Catalog(local: true, identifiesDatabase: false);
    final harness = await _open(tester, catalog);
    final count = catalog.requests.length;
    await _details(tester, catalog);
    expect(
      tester.widget<TextButton>(_key('zotero-browse-item-children')).onPressed,
      isNull,
    );
    expect(
      find.text(
        'Use Zotero 10 or later and reconnect to inspect notes and attachments.',
      ),
      findsOneWidget,
    );
    expect(catalog.requests, hasLength(count));
    expect(catalog.childrenRequests, isEmpty);
    _unchanged(harness);
  });

  for (final mode in <OfficeInteractionMode>[
    OfficeInteractionMode.selecting,
    OfficeInteractionMode.viewing,
  ]) {
    testWidgets(
      'research inspection in ${mode.name} mode leaves history and saved document unchanged',
      (tester) async {
        final catalog = _Catalog();
        final harness = await _open(tester, catalog, mode: mode);
        expect(harness.controller.config.allowsMutation, isFalse);
        await _details(tester, catalog);
        await _browse(tester);
        await _tap(tester, _key('zotero-child-NOTE0001'));
        await _tap(tester, _key('zotero-copy-child-note'));
        expect(harness.clipboard, <String>[_noteText]);
        await _tap(tester, _key('zotero-child-details-back'));
        await _tap(tester, _key('zotero-children-close'));
        await _closeDetails(tester);
        expect(find.text('0 selected'), findsOneWidget);
        _unchanged(harness);
      },
    );
  }

  for (final local in <bool>[false, true]) {
    testWidgets(
      '${local ? 'desktop' : 'online'} late child response cannot cross a session library change',
      (tester) async {
        final catalog = _Catalog(local: local)
          ..pendingChildren = Completer<ZoteroHttpResponse>();
        final harness = await _open(tester, catalog);
        await _details(tester, catalog);
        await _browse(tester, settle: false);
        expect(_key('zotero-children-loading'), findsOneWidget);
        expect(catalog.childrenRequests, hasLength(1));
        harness.session.library = ZoteroLibrary.group(77);
        catalog.pendingChildren!.complete(catalog.childrenResponse());
        await tester.pumpAndSettle();
        expect(find.text(_staleMessage), findsOneWidget);
        expect(_key('zotero-child-NOTE0001'), findsNothing);
        expect(_key('zotero-copy-child-note'), findsNothing);
        expect(harness.clipboard, isEmpty);
        expect(catalog.childrenRequests, hasLength(1));
        _unchanged(harness);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'a library change after preview blocks clipboard copy and clears the old list on return',
    (tester) async {
      final catalog = _Catalog();
      final harness = await _open(tester, catalog);
      await _details(tester, catalog);
      await _browse(tester);
      await _tap(tester, _key('zotero-child-NOTE0001'));
      harness.session.library = ZoteroLibrary.user(77);
      await _tap(tester, _key('zotero-copy-child-note'));
      expect(harness.clipboard, isEmpty);
      expect(find.text(_staleMessage), findsOneWidget);
      expect(
        tester.widget<TextButton>(_key('zotero-copy-child-note')).onPressed,
        isNull,
      );
      await _tap(tester, _key('zotero-child-details-back'));
      expect(find.text(_staleMessage), findsOneWidget);
      expect(_key('zotero-child-NOTE0001'), findsNothing);
      expect(catalog.childrenRequests, hasLength(1));
      _unchanged(harness);
    },
  );

  testWidgets('changing libraries in parent details blocks child dispatch', (
    tester,
  ) async {
    final catalog = _Catalog();
    final harness = await _open(tester, catalog);
    await _details(tester, catalog);
    harness.session.library = ZoteroLibrary.user(77);
    await _browse(tester);
    expect(_key('zotero-item-details-dialog'), findsOneWidget);
    expect(_key('zotero-item-children-dialog'), findsNothing);
    expect(catalog.childrenRequests, isEmpty);
    _unchanged(harness);
  });

  testWidgets(
    'closing a pending child view prevents late results from reopening it',
    (tester) async {
      final catalog = _Catalog()
        ..pendingChildren = Completer<ZoteroHttpResponse>();
      final harness = await _open(tester, catalog);
      await _details(tester, catalog);
      await _browse(tester, settle: false);
      await _tap(tester, _key('zotero-children-close'));
      expect(_key('zotero-item-details-dialog'), findsOneWidget);
      catalog.pendingChildren!.complete(catalog.childrenResponse());
      await tester.pumpAndSettle();
      expect(_key('zotero-item-children-dialog'), findsNothing);
      expect(_key('zotero-child-NOTE0001'), findsNothing);
      expect(harness.clipboard, isEmpty);
      _unchanged(harness);
      expect(tester.takeException(), isNull);
    },
  );
}
