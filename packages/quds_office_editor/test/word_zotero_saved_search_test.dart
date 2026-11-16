import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

Map<String, Object?> _source(String key, String title, {bool group = false}) =>
    {
      'key': key,
      'library': {'type': group ? 'group' : 'user', 'id': group ? 42 : 0},
      'data': {'key': key, 'itemType': 'book', 'title': title},
      'csljson': {
        'id': group
            ? 'http://zotero.org/groups/42/items/$key'
            : 'http://zotero.org/users/local/LOCALKEY/items/$key',
        'type': 'book',
        'title': title,
        'author': [
          {'family': 'Hassan'},
        ],
      },
    };

Map<String, Object?> _search(String key, String name) => {
  'key': key,
  'data': {'key': key, 'name': name},
};

ZoteroHttpResponse _json(
  Object data, {
  Map<String, String> headers = const {},
}) => ZoteroHttpResponse(
  statusCode: 200,
  body: jsonEncode(data),
  headers: {'Zotero-Server-ID': 'desktop-1', ...headers},
);

class _Catalog {
  final requests = <ZoteroHttpRequest>[];
  bool deleted = false;
  bool emptySearches = false;
  Completer<ZoteroHttpResponse>? pending;

  Future<ZoteroHttpResponse> send(ZoteroHttpRequest request) async {
    requests.add(request);
    final path = request.uri.path;
    expect(request.uri.host, 'localhost');
    expect(request.headers['Zotero-API-Key'], isNull);
    if (path == '/api/') {
      return ZoteroHttpResponse(
        statusCode: 200,
        body: 'Local API',
        headers: const {
          'Zotero-API-Version': '3',
          'Zotero-Server-ID': 'desktop-1',
        },
      );
    }
    expect(request.headers['Zotero-Server-ID'], 'desktop-1');
    if (path.endsWith('/groups')) {
      return _json([
        {
          'id': 42,
          'data': {'name': 'Research group'},
        },
      ]);
    }
    if (path.endsWith('/collections')) return _json([]);
    final group = path.startsWith('/api/groups/42/');
    if (path.endsWith('/items/top')) {
      return _json([
        _source(
          'SOURCE01',
          group ? 'Group source' : 'Library source',
          group: group,
        ),
      ]);
    }
    if (path.endsWith('/searches')) {
      if (emptySearches) return _json([]);
      if (request.uri.queryParameters['start'] == '100') {
        return _json([
          _search('SEARCH01', 'Updated research'),
          _search('SEARCH03', 'Later search'),
        ]);
      }
      return _json(
        [
          _search('SEARCH01', group ? 'Group research' : 'Recent research'),
          _search('SEARCH02', 'Empty research'),
        ],
        headers: {'Total-Results': '101'},
      );
    }
    if (path.contains('/searches/') && path.endsWith('/items')) {
      if (pending != null) return pending!.future;
      if (deleted) {
        return ZoteroHttpResponse(statusCode: 404, body: 'private conditions');
      }
      if (path.contains('/SEARCH02/')) return _json([]);
      if (request.uri.queryParameters['start'] == '50') {
        return _json(
          [_source('SOURCE02', 'Next-page source')],
          headers: {'Total-Results': '51'},
        );
      }
      return _json(
        [
          _source(
            'SOURCE01',
            group ? 'Group result' : 'Search result',
            group: group,
          ),
        ],
        headers: {'Total-Results': '51'},
      );
    }
    throw StateError('Unexpected catalog route: $path');
  }
}

Future<WordEditorController> _open(
  WidgetTester tester,
  _Catalog catalog, {
  ZoteroSession? session,
  Size size = const Size(1280, 1100),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final controller = WordEditorController(
    document: WmlDocument.empty(text: 'Unchanged document'),
  );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return FilledButton(
              onPressed: () => showWordZoteroDialog(
                context,
                controller: controller,
                session: session ?? (ZoteroSession()..useLocal = true),
                localTransport: catalog.send,
                transport: (_) async => throw StateError(
                  'Saved searches must not contact the online library.',
                ),
              ),
              child: const Text('Open references'),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open references'));
  await tester.pumpAndSettle();
  await _tap(tester, find.byKey(const ValueKey('zotero-connect-desktop')));
  return controller;
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Finder _savedSearchMenu() => find.byWidgetPredicate(
  (widget) =>
      widget is DropdownButtonFormField<String> &&
      widget.decoration.labelText == 'Saved search',
);

Future<void> _chooseSearch(WidgetTester tester, String name) async {
  await _tap(tester, _savedSearchMenu());
  await _tap(tester, find.text(name).last);
}

Finder _sourceTile(String name) => find.widgetWithText(CheckboxListTile, name);

void main() {
  testWidgets(
    'saved-search browsing keeps selected identities through filters and pages',
    (tester) async {
      final catalog = _Catalog();
      final controller = await _open(tester, catalog);
      expect(
        catalog.requests.any((r) => r.uri.path.endsWith('/searches')),
        isFalse,
      );
      await _tap(tester, _sourceTile('Library source'));
      await _tap(tester, find.widgetWithText(ChoiceChip, 'Saved searches'));
      expect(
        find.text('Choose a saved search to browse its references.'),
        findsOneWidget,
      );
      expect(find.text('1 selected'), findsOneWidget);
      await _chooseSearch(tester, 'Recent research');
      expect(
        tester.widget<CheckboxListTile>(_sourceTile('Search result')).value,
        isTrue,
      );
      final query = find.widgetWithText(
        TextField,
        'Search within saved search',
      );
      await tester.enterText(query, 'Müller & 年');
      await _tap(tester, find.byTooltip('Search'));
      expect(catalog.requests.last.uri.queryParameters['q'], 'Müller & 年');
      await _tap(tester, find.byTooltip('Next page'));
      expect(catalog.requests.last.uri.queryParameters['start'], '50');
      expect(catalog.requests.last.uri.queryParameters['q'], 'Müller & 年');
      await _tap(tester, _sourceTile('Next-page source'));
      expect(find.text('2 selected'), findsOneWidget);
      await _tap(tester, find.byTooltip('Previous page'));
      expect(
        tester.widget<CheckboxListTile>(_sourceTile('Search result')).value,
        isTrue,
      );
      await _tap(tester, find.widgetWithText(ChoiceChip, 'Collections'));
      expect(catalog.requests.last.uri.path, '/api/users/0/items/top');
      expect(
        tester.widget<CheckboxListTile>(_sourceTile('Library source')).value,
        isTrue,
      );
      expect(find.text('2 selected'), findsOneWidget);
      expect(controller.document.paragraphs.single.text, 'Unchanged document');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'saved-search list pagination deduplicates menu keys and refresh keeps source selection',
    (tester) async {
      final catalog = _Catalog();
      await _open(tester, catalog);
      await _tap(tester, _sourceTile('Library source'));
      await _tap(tester, find.widgetWithText(ChoiceChip, 'Saved searches'));
      await _chooseSearch(tester, 'Recent research');
      await _tap(tester, find.text('More searches'));
      expect(catalog.requests.last.uri.queryParameters['start'], '100');
      expect(find.text('Updated research'), findsOneWidget);
      expect(find.text('Search result'), findsOneWidget);
      await _chooseSearch(tester, 'Later search');
      expect(
        catalog.requests.last.uri.path,
        '/api/users/0/searches/SEARCH03/items',
      );
      await _tap(tester, find.byTooltip('Refresh saved searches'));
      expect(
        find.text('Choose a saved search to browse its references.'),
        findsOneWidget,
      );
      expect(find.text('1 selected'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'group library resets the saved-search view without losing other selected sources',
    (tester) async {
      final catalog = _Catalog();
      await _open(tester, catalog);
      await _tap(tester, _sourceTile('Library source'));
      await _tap(tester, find.widgetWithText(ChoiceChip, 'Saved searches'));
      await _chooseSearch(tester, 'Recent research');
      await _tap(tester, find.byType(DropdownButtonFormField<ZoteroLibrary>));
      await _tap(tester, find.text('Research group').last);
      expect(catalog.requests.last.uri.path, '/api/groups/42/items/top');
      expect(_savedSearchMenu(), findsNothing);
      expect(
        tester.widget<CheckboxListTile>(_sourceTile('Group source')).value,
        isFalse,
      );
      await _tap(tester, _sourceTile('Group source'));
      expect(find.text('2 selected'), findsOneWidget);
      await _tap(tester, find.widgetWithText(ChoiceChip, 'Saved searches'));
      await _chooseSearch(tester, 'Group research');
      expect(
        catalog.requests.last.uri.path,
        '/api/groups/42/searches/SEARCH01/items',
      );
      expect(
        tester.widget<CheckboxListTile>(_sourceTile('Group result')).value,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a deleted saved search removes stale results and retains source selection',
    (tester) async {
      final catalog = _Catalog();
      final controller = await _open(tester, catalog);
      await _tap(tester, find.widgetWithText(ChoiceChip, 'Saved searches'));
      await _chooseSearch(tester, 'Recent research');
      await _tap(tester, _sourceTile('Search result'));
      catalog.deleted = true;
      await _tap(tester, find.byTooltip('Search'));
      expect(
        find.textContaining('Refresh saved searches and choose again'),
        findsOneWidget,
      );
      expect(_sourceTile('Search result'), findsNothing);
      expect(find.text('1 selected'), findsOneWidget);
      expect(controller.document.paragraphs.single.text, 'Unchanged document');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('closing during saved-search execution discards the response', (
    tester,
  ) async {
    final catalog = _Catalog();
    final controller = await _open(tester, catalog);
    await _tap(tester, find.widgetWithText(ChoiceChip, 'Saved searches'));
    await _tap(tester, _savedSearchMenu());
    catalog.pending = Completer<ZoteroHttpResponse>();
    await tester.tap(find.text('Recent research').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.byTooltip('Close Zotero'));
    await tester.pumpAndSettle();
    catalog.pending!.complete(_json([_source('SOURCE01', 'Late result')]));
    await tester.pumpAndSettle();
    expect(find.text('Zotero references'), findsNothing);
    expect(find.text('Late result'), findsNothing);
    expect(controller.document.paragraphs.single.text, 'Unchanged document');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'an externally changed library cannot display a pending saved-search result',
    (tester) async {
      final catalog = _Catalog();
      final session = ZoteroSession()..useLocal = true;
      await _open(tester, catalog, session: session);
      await _tap(tester, find.widgetWithText(ChoiceChip, 'Saved searches'));
      await _tap(tester, _savedSearchMenu());
      catalog.pending = Completer<ZoteroHttpResponse>();
      await tester.tap(find.text('Recent research').last);
      await tester.pump();
      session.library = ZoteroLibrary.group(42);
      catalog.pending!.complete(
        _json([_source('SOURCE01', 'Wrong library result')]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Wrong library result'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty saved searches remain usable in a narrow viewport', (
    tester,
  ) async {
    final catalog = _Catalog()..emptySearches = true;
    await _open(tester, catalog, size: const Size(320, 640));
    await _tap(tester, find.widgetWithText(ChoiceChip, 'Saved searches'));
    expect(find.text('No saved searches in this library'), findsWidgets);
    expect(
      find.text('Choose a saved search to browse its references.'),
      findsOneWidget,
    );
    await _tap(tester, find.byTooltip('Refresh saved searches'));
    expect(catalog.requests.last.uri.path, '/api/users/0/searches');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'switching to the online source removes saved-search navigation',
    (tester) async {
      final catalog = _Catalog();
      await _open(tester, catalog);
      await _tap(tester, find.widgetWithText(ChoiceChip, 'Saved searches'));
      await _tap(tester, find.byKey(const ValueKey('zotero-library-source')));
      await _tap(tester, find.text('Online Zotero library').last);
      expect(find.widgetWithText(ChoiceChip, 'Saved searches'), findsNothing);
      expect(_savedSearchMenu(), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
