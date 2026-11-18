import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

class _TagCatalog {
  _TagCatalog({this.local = false});

  final bool local;
  final requests = <ZoteroHttpRequest>[];
  Completer<ZoteroHttpResponse>? pending;
  bool failNextItems = false;

  List<ZoteroHttpRequest> get itemRequests => requests
      .where(
        (request) =>
            request.uri.path.endsWith('/items/top') ||
            request.uri.path.endsWith('/items'),
      )
      .toList();

  ZoteroHttpResponse json(Object value, {bool paged = false}) =>
      ZoteroHttpResponse(
        statusCode: 200,
        body: jsonEncode(value),
        headers: {
          if (local) 'Zotero-Server-ID': 'tag-filter-desktop',
          if (paged) 'Total-Results': '101',
        },
      );

  Future<ZoteroHttpResponse> send(ZoteroHttpRequest request) async {
    requests.add(request);
    final path = request.uri.path;
    expect(request.uri.host, local ? 'localhost' : 'api.zotero.org');
    expect(request.headers['Zotero-API-Key'], local ? isNull : 'tag-test-key');
    expect(request.followRedirects, isFalse);
    if (path == '/api/') {
      return ZoteroHttpResponse(
        statusCode: 200,
        body: 'Local API',
        headers: const {
          'Zotero-API-Version': '3',
          'Zotero-Server-ID': 'tag-filter-desktop',
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
      if (failNextItems) {
        failNextItems = false;
        return ZoteroHttpResponse(statusCode: 503, body: 'Unavailable');
      }
      if (pending != null) return pending!.future;
      return results(request);
    }
    throw StateError('Unexpected tag catalog route: $path');
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

Finder _tagInput() => find.byKey(const ValueKey('zotero-tag-input'));

Finder _tag(String tag) => find.byKey(ValueKey('zotero-tag-$tag'));

Finder _query() => find.byWidgetPredicate(
  (widget) =>
      widget is TextField &&
      const {
        'Search title, creator, or year',
        'Search references and full text',
        'Search within saved search',
      }.contains(widget.decoration?.labelText),
);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  // Text entry can schedule a caret reveal in the outer catalog scroll view.
  // Finish it before revealing the next target, including nested chip controls.
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: 'After $finder');
}

Future<void> _addTag(
  WidgetTester tester,
  String tag, {
  bool submit = false,
}) async {
  await tester.ensureVisible(_tagInput());
  await tester.enterText(_tagInput(), tag);
  if (submit) {
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  } else {
    await _tap(tester, find.byKey(const ValueKey('zotero-add-tag')));
  }
}

Future<void> _removeTag(WidgetTester tester, String tag) =>
    _tap(tester, find.byTooltip('Remove tag $tag'));

void _expectTags(_TagCatalog catalog, List<String> tags) {
  expect(catalog.itemRequests.last.uri.queryParametersAll['tag'], tags);
}

Future<WordEditorController> _open(
  WidgetTester tester,
  _TagCatalog catalog, {
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
    ..apiKey = 'tag-test-key';
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
    'adding AND tags restarts the submitted query and keeps selection',
    (tester) async {
      final catalog = _TagCatalog();
      final controller = await _open(tester, catalog);
      await tester.enterText(_query(), 'submitted phrase');
      await _tap(tester, find.byTooltip('Search'));
      await _tap(tester, find.widgetWithText(CheckboxListTile, 'First source'));
      await _tap(tester, find.byTooltip('Next page'));
      await tester.enterText(_query(), 'unsubmitted query');
      await _tap(tester, find.byTooltip('Search options'));
      await _addTag(tester, '  Research & القدس  ');
      await _addTag(tester, 'Müller', submit: true);

      _expectTags(catalog, ['Research & القدس', 'Müller']);
      expect(catalog.itemRequests.last.uri.queryParameters['start'], '0');
      expect(
        catalog.itemRequests.last.uri.queryParameters['q'],
        'submitted phrase',
      );
      expect(_tag('Research & القدس'), findsOneWidget);
      expect(_tag('Müller'), findsOneWidget);
      expect(tester.widget<TextField>(_tagInput()).controller!.text, isEmpty);
      expect(
        tester.widget<TextField>(_query()).controller!.text,
        'unsubmitted query',
      );
      expect(find.text('1 selected'), findsOneWidget);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'First source'),
            )
            .value,
        isTrue,
      );
      expect(controller.document.paragraphs.single.text, 'Unchanged document');
      expect(controller.canUndo, isFalse);
    },
  );

  testWidgets('draft tag and query do not change either pagination direction', (
    tester,
  ) async {
    final catalog = _TagCatalog();
    await _open(tester, catalog);
    await tester.enterText(_query(), 'submitted');
    await _tap(tester, find.byTooltip('Search'));
    await _tap(tester, find.byTooltip('Search options'));
    await _addTag(tester, 'reviewed');
    await _addTag(tester, 'methods');
    await tester.enterText(_tagInput(), 'draft tag');
    await tester.enterText(_query(), 'draft query');
    final before = catalog.itemRequests.length;
    await tester.pumpAndSettle();
    expect(catalog.itemRequests.length, before);
    for (final action in [
      ('Next page', '50'),
      ('Next page', '100'),
      ('Previous page', '50'),
      ('Previous page', '0'),
    ]) {
      await _tap(tester, find.byTooltip(action.$1));
      _expectTags(catalog, ['reviewed', 'methods']);
      expect(catalog.itemRequests.last.uri.queryParameters['start'], action.$2);
      expect(catalog.itemRequests.last.uri.queryParameters['q'], 'submitted');
    }
    expect(tester.widget<TextField>(_tagInput()).controller!.text, 'draft tag');
    expect(tester.widget<TextField>(_query()).controller!.text, 'draft query');
  });

  testWidgets('removing and clearing tags restart the last submitted search', (
    tester,
  ) async {
    final catalog = _TagCatalog();
    await _open(tester, catalog);
    await tester.enterText(_query(), 'submitted');
    await _tap(tester, find.byTooltip('Search'));
    await _tap(tester, find.widgetWithText(CheckboxListTile, 'First source'));
    await _tap(tester, find.byTooltip('Search options'));
    await _addTag(tester, 'first');
    await _addTag(tester, 'second');
    await _tap(tester, find.byTooltip('Next page'));
    await tester.enterText(_query(), 'draft');
    await _removeTag(tester, 'first');
    _expectTags(catalog, ['second']);
    expect(_tag('first'), findsNothing);
    expect(catalog.itemRequests.last.uri.queryParameters['start'], '0');
    expect(catalog.itemRequests.last.uri.queryParameters['q'], 'submitted');
    await _tap(tester, find.byTooltip('Next page'));
    await _tap(tester, find.byKey(const ValueKey('zotero-clear-tags')));
    expect(
      catalog.itemRequests.last.uri.queryParametersAll.containsKey('tag'),
      isFalse,
    );
    expect(catalog.itemRequests.last.uri.queryParameters['start'], '0');
    expect(catalog.itemRequests.last.uri.queryParameters['q'], 'submitted');
    expect(_tag('second'), findsNothing);
    expect(find.text('1 selected'), findsOneWidget);
  });

  testWidgets(
    'new searches preserve tags and collapsing options keeps them active',
    (tester) async {
      final catalog = _TagCatalog();
      await _open(tester, catalog);
      await _tap(tester, find.byTooltip('Search options'));
      await _addTag(tester, 'reviewed');
      await _tap(tester, find.byTooltip('Next page'));
      await _tap(tester, find.byTooltip('Search options'));
      expect(_tagInput(), findsNothing);
      await tester.enterText(_query(), 'new submitted query');
      await _tap(tester, find.byTooltip('Search'));
      _expectTags(catalog, ['reviewed']);
      expect(catalog.itemRequests.last.uri.queryParameters['start'], '0');
      expect(
        catalog.itemRequests.last.uri.queryParameters['q'],
        'new submitted query',
      );
      await _tap(tester, find.byTooltip('Next page'));
      _expectTags(catalog, ['reviewed']);
      await _tap(tester, find.byTooltip('Search options'));
      expect(_tag('reviewed'), findsOneWidget);
    },
  );

  testWidgets('collection and group scopes retain repeated tag parameters', (
    tester,
  ) async {
    final catalog = _TagCatalog();
    await _open(tester, catalog);
    await _tap(tester, find.byTooltip('Search options'));
    await _addTag(tester, 'literature');
    await _addTag(tester, 'reviewed');
    await _tap(tester, find.byTooltip('Next page'));
    await _tap(
      tester,
      find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            widget.decoration.labelText == 'Collection',
      ),
    );
    await _tap(tester, find.text('Research collection').last);
    expect(
      catalog.itemRequests.last.uri.path,
      '/users/42/collections/COLL0001/items/top',
    );
    expect(catalog.itemRequests.last.uri.queryParameters['start'], '0');
    _expectTags(catalog, ['literature', 'reviewed']);
    await _tap(
      tester,
      find.byWidgetPredicate(
        (widget) => widget is DropdownButtonFormField<ZoteroLibrary>,
      ),
    );
    await _tap(tester, find.text('Research group').last);
    expect(catalog.itemRequests.last.uri.path, '/groups/84/items/top');
    expect(catalog.itemRequests.last.uri.queryParameters['start'], '0');
    _expectTags(catalog, ['literature', 'reviewed']);
    await _tap(tester, find.byTooltip('Next page'));
    expect(catalog.itemRequests.last.uri.queryParameters['start'], '50');
    _expectTags(catalog, ['literature', 'reviewed']);
  });

  testWidgets(
    'desktop saved searches apply tags before pagination without API keys',
    (tester) async {
      final catalog = _TagCatalog(local: true);
      await _open(tester, catalog);
      await _tap(tester, find.byTooltip('Search options'));
      await _addTag(tester, 'local research');
      await _addTag(tester, '-archived');
      await _tap(tester, find.widgetWithText(ChoiceChip, 'Saved searches'));
      await _tap(
        tester,
        find.byWidgetPredicate(
          (widget) =>
              widget is DropdownButtonFormField<String> &&
              widget.decoration.labelText == 'Saved search',
        ),
      );
      await _tap(tester, find.text('Saved research').last);
      expect(
        catalog.itemRequests.last.uri.path,
        '/api/users/0/searches/SEARCH01/items',
      );
      _expectTags(catalog, ['local research', r'\-archived']);
      expect(catalog.itemRequests.last.uri.queryParameters['start'], '0');
      await _tap(tester, find.byTooltip('Next page'));
      expect(catalog.itemRequests.last.uri.queryParameters['start'], '50');
      _expectTags(catalog, ['local research', r'\-archived']);
      expect(_tag('-archived'), findsOneWidget);
    },
  );

  testWidgets(
    'duplicate tags are trimmed, not resent, and preserve capitalization',
    (tester) async {
      final catalog = _TagCatalog();
      await _open(tester, catalog);
      await _tap(tester, find.byTooltip('Search options'));
      await _addTag(tester, 'reviewed');
      final before = catalog.itemRequests.length;
      await _addTag(tester, '  reviewed  ', submit: true);
      expect(catalog.itemRequests.length, before);
      expect(_tag('reviewed'), findsOneWidget);
      expect(tester.widget<TextField>(_tagInput()).controller!.text, isEmpty);
      await _addTag(tester, 'Reviewed');
      _expectTags(catalog, ['reviewed', 'Reviewed']);
      expect(_tag('Reviewed'), findsOneWidget);
    },
  );

  for (final invalid in [
    '',
    '   ',
    'one || two',
    r'\-literal',
    'two\tparts',
    'x' * 257,
  ]) {
    final label = invalid.length > 40
        ? '257-character tag'
        : jsonEncode(invalid);
    testWidgets('invalid $label keeps the catalog and selection intact', (
      tester,
    ) async {
      final catalog = _TagCatalog();
      final controller = await _open(tester, catalog);
      await _tap(tester, find.widgetWithText(CheckboxListTile, 'First source'));
      await _tap(tester, find.byTooltip('Search options'));
      await _addTag(tester, 'valid');
      final before = catalog.requests.length;
      await _addTag(tester, invalid);
      expect(catalog.requests.length, before);
      expect(
        tester.widget<TextField>(_tagInput()).decoration!.errorText,
        isNotEmpty,
      );
      expect(_tag('valid'), findsOneWidget);
      expect(find.text('1 selected'), findsOneWidget);
      expect(
        find.widgetWithText(CheckboxListTile, 'First source'),
        findsOneWidget,
      );
      expect(controller.canUndo, isFalse);
      await _addTag(tester, 'recovered');
      expect(
        tester.widget<TextField>(_tagInput()).decoration!.errorText,
        isNull,
      );
      _expectTags(catalog, ['valid', 'recovered']);
    });
  }

  testWidgets('the twenty-tag limit rejects extra input without a request', (
    tester,
  ) async {
    final catalog = _TagCatalog();
    await _open(tester, catalog);
    await _tap(tester, find.byTooltip('Search options'));
    final tags = [for (var i = 1; i <= 20; i++) 'Tag $i'];
    for (final tag in tags) {
      await _addTag(tester, tag);
    }
    _expectTags(catalog, tags);
    final before = catalog.requests.length;
    await _addTag(tester, 'One too many');
    expect(catalog.requests.length, before);
    expect(
      tester.widget<TextField>(_tagInput()).decoration!.errorText,
      isNotEmpty,
    );
    _expectTags(catalog, tags);
    await _removeTag(tester, 'Tag 1');
    await _addTag(tester, 'Replacement');
    _expectTags(catalog, [...tags.skip(1), 'Replacement']);
  });

  testWidgets('desktop reconnect retains applied tags and expanded controls', (
    tester,
  ) async {
    final catalog = _TagCatalog(local: true);
    await _open(tester, catalog);
    await _tap(tester, find.byTooltip('Search options'));
    await _addTag(tester, 'local research');
    await _addTag(tester, 'reviewed');
    await _tap(tester, find.text('Disconnect desktop'));
    expect(_tagInput(), findsNothing);
    await _tap(tester, find.text('Connect desktop'));
    _expectTags(catalog, ['local research', 'reviewed']);
    expect(_tag('local research'), findsOneWidget);
    expect(_tag('reviewed'), findsOneWidget);
    expect(_tagInput(), findsOneWidget);
  });

  testWidgets(
    'failed tag requests retain editable filters for a successful retry',
    (tester) async {
      final catalog = _TagCatalog();
      final controller = await _open(tester, catalog);
      await _tap(tester, find.widgetWithText(CheckboxListTile, 'First source'));
      await _tap(tester, find.byTooltip('Search options'));
      catalog.failNextItems = true;
      await _addTag(tester, 'reviewed');
      expect(
        find.text('Zotero is temporarily unavailable. Try again later.'),
        findsOneWidget,
      );
      expect(_tag('reviewed'), findsOneWidget);
      expect(find.text('1 selected'), findsOneWidget);
      _expectTags(catalog, ['reviewed']);
      await _tap(tester, find.byTooltip('Search'));
      expect(
        find.text('Zotero is temporarily unavailable. Try again later.'),
        findsNothing,
      );
      _expectTags(catalog, ['reviewed']);
      expect(
        find.widgetWithText(CheckboxListTile, 'First source'),
        findsOneWidget,
      );
      expect(controller.document.paragraphs.single.text, 'Unchanged document');
      expect(controller.canUndo, isFalse);
    },
  );

  for (final width in [320.0, 360.0, 420.0]) {
    testWidgets('twenty applied tags and paging fit a $width-pixel window', (
      tester,
    ) async {
      final catalog = _TagCatalog(local: true);
      await _open(tester, catalog, size: Size(width, 760));
      await _tap(tester, find.byTooltip('Search options'));
      final longTag = 'Long reference tag ${'x' * 180}';
      final tags = [longTag, for (var i = 2; i <= 20; i++) 'Research tag $i'];
      for (final tag in tags) {
        await _addTag(tester, tag);
      }
      _expectTags(catalog, tags);
      await _tap(tester, find.byTooltip('Next page'));
      expect(catalog.itemRequests.last.uri.queryParameters['start'], '50');
      _expectTags(catalog, tags);
      await _removeTag(tester, longTag);
      _expectTags(catalog, tags.skip(1).toList());
      await _tap(tester, find.byKey(const ValueKey('zotero-clear-tags')));
      expect(
        catalog.itemRequests.last.uri.queryParametersAll.containsKey('tag'),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'closing while a tag request is pending discards the late response',
    (tester) async {
      final catalog = _TagCatalog();
      final controller = await _open(tester, catalog);
      await _tap(tester, find.byTooltip('Search options'));
      await tester.enterText(_tagInput(), 'reviewed');
      catalog.pending = Completer<ZoteroHttpResponse>();
      await tester.tap(find.byKey(const ValueKey('zotero-add-tag')));
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
    },
  );
}
