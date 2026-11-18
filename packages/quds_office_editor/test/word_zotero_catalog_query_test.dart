import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

class _Catalog {
  _Catalog({this.local = false});

  final bool local;
  final requests = <ZoteroHttpRequest>[];
  Completer<ZoteroHttpResponse>? pending;

  List<ZoteroHttpRequest> get itemRequests => requests
      .where(
        (r) =>
            r.uri.path.endsWith('/items/top') || r.uri.path.endsWith('/items'),
      )
      .toList();

  ZoteroHttpResponse json(Object value, {bool paged = false}) =>
      ZoteroHttpResponse(
        statusCode: 200,
        body: jsonEncode(value),
        headers: {
          if (local) 'Zotero-Server-ID': 'catalog-query-desktop',
          if (paged) 'Total-Results': '101',
        },
      );

  Future<ZoteroHttpResponse> send(ZoteroHttpRequest request) async {
    requests.add(request);
    final path = request.uri.path;
    expect(request.uri.host, local ? 'localhost' : 'api.zotero.org');
    expect(
      request.headers['Zotero-API-Key'],
      local ? isNull : 'query-test-key',
    );
    expect(request.followRedirects, isFalse);
    if (path == '/api/') {
      return ZoteroHttpResponse(
        statusCode: 200,
        body: 'Local API',
        headers: const {
          'Zotero-API-Version': '3',
          'Zotero-Server-ID': 'catalog-query-desktop',
        },
      );
    }
    if (path == '/keys/current') {
      return json({
        'userID': 42,
        'username': 'Reader',
        'access': {
          'user': {'library': true},
          'groups': {
            'all': {'library': true},
          },
        },
      });
    }
    if (path.endsWith('/groups')) {
      return json([
        {
          'id': 84,
          'data': {'name': 'Research group'},
        },
      ]);
    }
    if (path.endsWith('/collections')) {
      return json([
        {
          'key': 'COLL0001',
          'data': {'name': 'Research collection'},
        },
      ]);
    }
    if (path.endsWith('/searches')) {
      return json([
        {
          'key': 'SEARCH01',
          'data': {'name': 'Saved research'},
        },
      ]);
    }
    if (path.endsWith('/items/top') || path.endsWith('/items')) {
      if (pending != null) return pending!.future;
      return results(request);
    }
    throw StateError('Unexpected catalog route: $path');
  }

  ZoteroHttpResponse results(ZoteroHttpRequest request) {
    final group = request.uri.path.contains('/groups/84/');
    final start = int.parse(request.uri.queryParameters['start']!);
    final key = start == 0 ? 'SOURCE01' : 'SOURCE02';
    final title = start == 0 ? 'First source' : 'Later source';
    return json([
      {
        'key': key,
        'library': {
          'type': group ? 'group' : 'user',
          'id': group
              ? 84
              : local
              ? 0
              : 42,
        },
        'data': {'key': key, 'itemType': 'book', 'title': title},
        'csljson': {
          'id': group
              ? 'http://zotero.org/groups/84/items/$key'
              : local
              ? 'http://zotero.org/users/local/LOCALKEY/items/$key'
              : 'http://zotero.org/users/42/items/$key',
          'type': 'book',
          'title': title,
        },
      },
    ], paged: true);
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: 'After $finder');
}

Finder _query() => find.byWidgetPredicate(
  (widget) =>
      widget is TextField &&
      const {
        'Search title, creator, or year',
        'Search references and full text',
        'Search within saved search',
      }.contains(widget.decoration?.labelText),
);

Future<void> _choose(WidgetTester tester, String key, String label) async {
  await _tap(tester, find.byKey(ValueKey(key)));
  await _tap(tester, find.text(label).last);
}

Future<void> _openOptions(WidgetTester tester) =>
    _tap(tester, find.byTooltip('Search options'));

Future<WordEditorController> _open(
  WidgetTester tester,
  _Catalog catalog, {
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
  final session = ZoteroSession()
    ..useLocal = catalog.local
    ..apiKey = 'query-test-key';
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
            ),
            child: const Text('Open references'),
          ),
        ),
      ),
    ),
  );
  await _tap(tester, find.text('Open references'));
  await _tap(tester, find.text(catalog.local ? 'Connect desktop' : 'Connect'));
  return controller;
}

void main() {
  testWidgets(
    'online query controls apply to every page and retain selection',
    (tester) async {
      final catalog = _Catalog();
      final controller = await _open(tester, catalog);
      await _tap(tester, find.widgetWithText(CheckboxListTile, 'First source'));
      await tester.enterText(_query(), 'Müller & القدس');
      await _openOptions(tester);
      await _choose(tester, 'zotero-search-mode', 'Include full text');
      await _choose(tester, 'zotero-item-type', 'Book');
      await _choose(tester, 'zotero-item-sort', 'Title');
      await _choose(tester, 'zotero-sort-direction', 'Ascending');
      await _tap(tester, find.byTooltip('Next page'));
      expect(catalog.itemRequests.last.uri.queryParameters, {
        'start': '50',
        'limit': '50',
        'format': 'json',
        'include': 'data,csljson',
        'sort': 'title',
        'direction': 'asc',
        'itemType': 'book',
        'q': 'Müller & القدس',
        'qmode': 'everything',
      });
      expect(find.text('1 selected'), findsOneWidget);
      await _tap(tester, find.widgetWithText(CheckboxListTile, 'Later source'));
      await _tap(tester, find.byTooltip('Previous page'));
      expect(catalog.itemRequests.last.uri.queryParameters['start'], '0');
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'First source'),
            )
            .value,
        isTrue,
      );
      expect(find.text('2 selected'), findsOneWidget);
      expect(controller.document.paragraphs.single.text, 'Unchanged document');
      expect(controller.canUndo, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('both page directions retain submitted text until a new search', (
    tester,
  ) async {
    final catalog = _Catalog();
    await _open(tester, catalog);
    await tester.enterText(_query(), 'submitted phrase');
    await _tap(tester, find.byTooltip('Search'));
    await _tap(tester, find.byTooltip('Next page'));
    await tester.enterText(_query(), 'unsubmitted draft');
    await _tap(tester, find.byTooltip('Next page'));
    expect(catalog.itemRequests.last.uri.queryParameters['start'], '100');
    expect(
      catalog.itemRequests.last.uri.queryParameters['q'],
      'submitted phrase',
    );
    await _tap(tester, find.byTooltip('Previous page'));
    await _tap(tester, find.byTooltip('Previous page'));
    expect(catalog.itemRequests.last.uri.queryParameters['start'], '0');
    expect(
      catalog.itemRequests.last.uri.queryParameters['q'],
      'submitted phrase',
    );
    expect(
      tester.widget<TextField>(_query()).controller!.text,
      'unsubmitted draft',
    );
    await _tap(tester, find.byTooltip('Search'));
    expect(catalog.itemRequests.last.uri.queryParameters['start'], '0');
    expect(
      catalog.itemRequests.last.uri.queryParameters['q'],
      'unsubmitted draft',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'paging an unfiltered catalog does not submit draft search text',
    (tester) async {
      final catalog = _Catalog();
      await _open(tester, catalog);
      await tester.enterText(_query(), 'new draft');
      await _tap(tester, find.byTooltip('Next page'));
      expect(
        catalog.itemRequests.last.uri.queryParameters.containsKey('q'),
        isFalse,
      );
      await _tap(tester, find.byTooltip('Previous page'));
      expect(
        catalog.itemRequests.last.uri.queryParameters.containsKey('q'),
        isFalse,
      );
    },
  );

  testWidgets(
    'changing query options restarts at zero and all-types removes the filter',
    (tester) async {
      final catalog = _Catalog();
      await _open(tester, catalog);
      await _tap(tester, find.byTooltip('Next page'));
      await _openOptions(tester);
      await _choose(tester, 'zotero-item-type', 'Journal article');
      expect(catalog.itemRequests.last.uri.queryParameters['start'], '0');
      expect(
        catalog.itemRequests.last.uri.queryParameters['itemType'],
        'journalArticle',
      );
      await _tap(tester, find.byTooltip('Next page'));
      await _choose(tester, 'zotero-item-sort', 'Publication date');
      expect(catalog.itemRequests.last.uri.queryParameters['start'], '0');
      expect(catalog.itemRequests.last.uri.queryParameters['sort'], 'date');
      await _choose(tester, 'zotero-item-type', 'All types');
      expect(
        catalog.itemRequests.last.uri.queryParameters.containsKey('itemType'),
        isFalse,
      );
    },
  );

  testWidgets(
    'collection and group changes retain filters and restart pagination',
    (tester) async {
      final catalog = _Catalog();
      await _open(tester, catalog);
      await _openOptions(tester);
      await _choose(tester, 'zotero-item-type', 'Book');
      await _tap(tester, find.byTooltip('Next page'));
      final collection = find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            widget.decoration.labelText == 'Collection',
      );
      await _tap(tester, collection);
      await _tap(tester, find.text('Research collection').last);
      expect(
        catalog.itemRequests.last.uri.path,
        '/users/42/collections/COLL0001/items/top',
      );
      expect(catalog.itemRequests.last.uri.queryParameters['start'], '0');
      expect(catalog.itemRequests.last.uri.queryParameters['itemType'], 'book');
      final library = find.byWidgetPredicate(
        (widget) => widget is DropdownButtonFormField<ZoteroLibrary>,
      );
      await _tap(tester, library);
      await _tap(tester, find.text('Research group').last);
      expect(catalog.itemRequests.last.uri.path, '/groups/84/items/top');
      expect(catalog.itemRequests.last.uri.queryParameters['itemType'], 'book');
      expect(catalog.itemRequests.last.uri.queryParameters['start'], '0');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'desktop saved-search query controls keep their endpoint and credentials',
    (tester) async {
      final catalog = _Catalog(local: true);
      final controller = await _open(tester, catalog);
      await _tap(tester, find.widgetWithText(ChoiceChip, 'Saved searches'));
      final menu = find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            widget.decoration.labelText == 'Saved search',
      );
      await _tap(tester, menu);
      await _tap(tester, find.text('Saved research').last);
      await tester.enterText(_query(), 'local indexed text');
      await _openOptions(tester);
      await _choose(tester, 'zotero-search-mode', 'Include full text');
      await _choose(tester, 'zotero-item-type', 'Report');
      await _choose(tester, 'zotero-item-sort', 'Creator');
      await _tap(tester, find.byTooltip('Next page'));
      final request = catalog.itemRequests.last;
      expect(request.uri.path, '/api/users/0/searches/SEARCH01/items');
      expect(request.uri.queryParameters['qmode'], 'everything');
      expect(request.uri.queryParameters['q'], 'local indexed text');
      expect(request.uri.queryParameters['itemType'], 'report');
      expect(request.uri.queryParameters['sort'], 'creator');
      expect(request.uri.queryParameters['start'], '50');
      expect(controller.canUndo, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 360.0, 420.0]) {
    testWidgets('expanded catalog options fit a $width-pixel window', (
      tester,
    ) async {
      final catalog = _Catalog(local: true);
      await _open(tester, catalog, size: Size(width, 760));
      await _openOptions(tester);
      await _choose(tester, 'zotero-search-mode', 'Include full text');
      await _choose(tester, 'zotero-item-type', 'Book');
      await _choose(tester, 'zotero-item-sort', 'Title');
      await _choose(tester, 'zotero-sort-direction', 'Ascending');
      await _tap(tester, find.byTooltip('Next page'));
      expect(catalog.itemRequests.last.uri.queryParameters['start'], '50');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('desktop reconnect keeps expanded options and chosen filters', (
    tester,
  ) async {
    final catalog = _Catalog(local: true);
    await _open(tester, catalog);
    await _openOptions(tester);
    await _choose(tester, 'zotero-item-type', 'Book');
    await _tap(tester, find.text('Disconnect desktop'));
    expect(find.byKey(const ValueKey('zotero-search-options')), findsNothing);
    await _tap(tester, find.text('Connect desktop'));
    expect(catalog.itemRequests.last.uri.queryParameters['itemType'], 'book');
    // A recreated tile must show the controls, without a second expansion tap.
    await _choose(tester, 'zotero-search-mode', 'Include full text');
    expect(
      tester.widget<TextField>(_query()).decoration!.labelText,
      'Search references and full text',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing during an option request discards the late result', (
    tester,
  ) async {
    final catalog = _Catalog();
    final controller = await _open(tester, catalog);
    await _openOptions(tester);
    await _tap(tester, find.byKey(const ValueKey('zotero-item-sort')));
    catalog.pending = Completer<ZoteroHttpResponse>();
    await tester.tap(find.text('Title').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    final count = catalog.requests.length;
    await tester.tap(find.byTooltip('Close Zotero'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    catalog.pending!.complete(catalog.results(catalog.itemRequests.last));
    await tester.pumpAndSettle();
    expect(find.text('Zotero references'), findsNothing);
    expect(catalog.requests.length, count);
    expect(controller.document.paragraphs.single.text, 'Unchanged document');
    expect(controller.canUndo, isFalse);
    expect(tester.takeException(), isNull);
  });
}
