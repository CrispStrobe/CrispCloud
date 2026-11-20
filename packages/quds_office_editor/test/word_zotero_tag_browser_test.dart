import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_editor/src/embed/word_zotero_tags.dart';

class _Catalog {
  final requests = <ZoteroHttpRequest>[];
  Completer<ZoteroHttpResponse>? pending;
  bool fail = false;
  List<Map<String, Object?>>? records;

  List<ZoteroHttpRequest> get tags =>
      requests.where((request) => request.uri.path.endsWith('/tags')).toList();
  List<ZoteroHttpRequest> get items => requests
      .where((request) => request.uri.path.endsWith('/items/top'))
      .toList();

  ZoteroHttpResponse response(Object value, {int? total}) => ZoteroHttpResponse(
    statusCode: 200,
    body: jsonEncode(value),
    headers: {if (total != null) 'Total-Results': '$total'},
  );

  Future<ZoteroHttpResponse> send(ZoteroHttpRequest request) async {
    requests.add(request);
    final path = request.uri.path;
    if (path.endsWith('/tags')) {
      if (fail) throw StateError('Sensitive response must not be displayed');
      if (pending != null) return pending!.future;
      final query = request.uri.queryParameters['q'] ?? '';
      final start = request.uri.queryParameters['start'];
      return response(
        records ??
            [
              {
                'tag': query.isNotEmpty
                    ? 'Found $query'
                    : start == '0'
                    ? 'Research & القدس'
                    : 'Later tag',
                'meta': {'type': 0, 'numItems': 12},
              },
            ],
        total: query.isEmpty ? 101 : 1,
      );
    }
    if (path == '/keys/current') {
      return response({
        'userID': 42,
        'username': 'Reader',
        'access': {
          'user': {'library': true},
          'groups': <String, Object?>{},
        },
      });
    }
    if (path.endsWith('/groups')) return response([]);
    if (path.endsWith('/collections')) {
      return response([
        {
          'key': 'COLL0001',
          'data': {'name': 'Research collection'},
        },
      ]);
    }
    if (path.endsWith('/items/top')) {
      return response([
        {
          'key': 'SOURCE01',
          'library': {'type': 'user', 'id': 42},
          'data': {'key': 'SOURCE01', 'itemType': 'book', 'title': 'Source'},
          'csljson': {
            'id': 'http://zotero.org/users/42/items/SOURCE01',
            'type': 'book',
            'title': 'Source',
          },
        },
      ], total: 101);
    }
    throw StateError('Unexpected catalog route $path');
  }
}

class _Result {
  bool completed = false;
  List<String>? tags;
}

Finder _key(String value) => find.byKey(ValueKey(value));
Finder _choice(String value) => _key('zotero-tag-browser-choice-$value');

Future<void> _tap(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().single.widget is CheckboxListTile) {
    finder = find.descendant(of: finder, matching: find.byType(Checkbox));
  }
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<_Result> _open(
  WidgetTester tester,
  _Catalog catalog, {
  List<String> active = const [],
  Size size = const Size(1100, 1000),
  double scale = 1,
  TextDirection direction = TextDirection.ltr,
  bool settle = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final result = _Result();
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: Directionality(textDirection: direction, child: child!),
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result.tags = await showDialog<List<String>>(
                context: context,
                builder: (_) => ZoteroTagBrowserDialog(
                  client: ZoteroClient(transport: catalog.send),
                  library: ZoteroLibrary.user(42),
                  activeTags: active,
                ),
              );
              result.completed = true;
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
  return result;
}

Future<(WordEditorController, ZoteroSession)> _openWorkspace(
  WidgetTester tester,
  _Catalog catalog,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 1100);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final controller = WordEditorController(
    document: WmlDocument.empty(text: 'Unchanged'),
  );
  addTearDown(controller.dispose);
  final session = ZoteroSession()..apiKey = 'test-key';
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showWordZoteroDialog(
              context,
              controller: controller,
              session: session,
              transport: catalog.send,
            ),
            child: const Text('Open references'),
          ),
        ),
      ),
    ),
  );
  await _tap(tester, find.text('Open references'));
  await _tap(tester, find.text('Connect'));
  return (controller, session);
}

void main() {
  testWidgets('stages exact tag choices across pages and explicit searches', (
    tester,
  ) async {
    final catalog = _Catalog();
    final active = ['reviewed'];
    final result = await _open(tester, catalog, active: active);
    expect(catalog.tags.single.uri.path, '/users/42/tags');
    await _tap(tester, _choice('Research & القدس'));
    final query = _key('zotero-tag-browser-query');
    await tester.enterText(query, 'draft');
    await tester.pumpAndSettle();
    expect(catalog.tags, hasLength(1));
    await _tap(tester, _key('zotero-tag-browser-next'));
    expect(catalog.tags.last.uri.queryParameters['start'], '50');
    expect(catalog.tags.last.uri.queryParameters['q'], isNull);
    await _tap(tester, _choice('Later tag'));
    await _tap(tester, _key('zotero-tag-browser-previous'));
    expect(catalog.tags.last.uri.queryParameters['start'], '0');
    expect(catalog.tags.last.uri.queryParameters['q'], isNull);
    await _tap(tester, _key('zotero-tag-browser-search'));
    expect(catalog.tags.last.uri.queryParameters['q'], 'draft');
    expect(catalog.tags.last.uri.queryParameters['start'], '0');
    await _tap(tester, _choice('Found draft'));
    expect(result.completed, isFalse);
    expect(active, ['reviewed']);
    await _tap(tester, _key('zotero-tag-browser-apply'));
    expect(result.tags, [
      'reviewed',
      'Research & القدس',
      'Later tag',
      'Found draft',
    ]);
    expect(active, ['reviewed']);
  });

  testWidgets('cancel discards staged clearing and additions', (tester) async {
    final active = ['reviewed', 'methods'];
    final result = await _open(tester, _Catalog(), active: active);
    await _tap(tester, _key('zotero-tag-browser-clear'));
    await _tap(tester, _choice('Research & القدس'));
    await _tap(tester, _key('zotero-tag-browser-cancel'));
    expect(result.completed, isTrue);
    expect(result.tags, isNull);
    expect(active, ['reviewed', 'methods']);
  });

  testWidgets('duplicate tag types share a choice without summing counts', (
    tester,
  ) async {
    final catalog = _Catalog()
      ..records = [
        {
          'tag': 'same',
          'meta': {'type': 0, 'numItems': 4},
        },
        {
          'tag': 'same',
          'meta': {'type': 1, 'numItems': 6},
        },
      ];
    await _open(tester, catalog);
    expect(_choice('same'), findsOneWidget);
    expect(find.textContaining('items reported by Zotero'), findsNothing);
    await _tap(tester, _choice('same'));
    expect(find.text('1 tag filters selected'), findsOneWidget);
  });

  testWidgets('unrepresentable literal names remain visible and unavailable', (
    tester,
  ) async {
    final catalog = _Catalog()
      ..records = [
        {'tag': 'A||B'},
        {'tag': r'\-literal'},
        {'tag': ' padded '},
        {'tag': '-supported'},
      ];
    final result = await _open(tester, catalog);
    for (final name in ['A||B', r'\-literal', ' padded ']) {
      await tester.ensureVisible(_choice(name));
      expect(tester.widget<CheckboxListTile>(_choice(name)).onChanged, isNull);
    }
    await _tap(tester, _choice('-supported'));
    await _tap(tester, _key('zotero-tag-browser-apply'));
    expect(result.tags, ['-supported']);
  });

  testWidgets('selection limit can be relieved without losing off-page tags', (
    tester,
  ) async {
    final active = List.generate(20, (index) => 'Selected $index');
    final result = await _open(tester, _Catalog(), active: active);
    expect(
      tester.widget<CheckboxListTile>(_choice('Research & القدس')).onChanged,
      isNull,
    );
    await _tap(tester, find.byTooltip('Remove selected tag Selected 0'));
    await _tap(tester, _choice('Research & القدس'));
    await _tap(tester, _key('zotero-tag-browser-apply'));
    expect(result.tags, [...active.skip(1), 'Research & القدس']);
    expect(active, hasLength(20));
  });

  testWidgets('mode changes retain the submitted query until Search', (
    tester,
  ) async {
    final catalog = _Catalog();
    await _open(tester, catalog);
    await tester.enterText(_key('zotero-tag-browser-query'), 'submitted');
    await _tap(tester, _key('zotero-tag-browser-search'));
    await tester.enterText(_key('zotero-tag-browser-query'), 'draft');
    await _tap(tester, _key('zotero-tag-browser-mode'));
    await _tap(tester, find.text('Starting with the search').last);
    expect(catalog.tags.last.uri.queryParameters['q'], 'submitted');
    expect(catalog.tags.last.uri.queryParameters['qmode'], 'startsWith');
    expect(
      tester
          .widget<TextField>(_key('zotero-tag-browser-query'))
          .controller!
          .text,
      'draft',
    );
  });

  testWidgets('network failure is contained and retry is explicit', (
    tester,
  ) async {
    final catalog = _Catalog()..fail = true;
    await _open(tester, catalog);
    expect(_key('zotero-tag-browser-error'), findsOneWidget);
    expect(find.textContaining('Sensitive response'), findsNothing);
    await tester.pump(const Duration(seconds: 30));
    expect(catalog.tags, hasLength(1));
    catalog.fail = false;
    await _tap(tester, _key('zotero-tag-browser-search'));
    expect(catalog.tags, hasLength(2));
    expect(_choice('Research & القدس'), findsOneWidget);
  });

  testWidgets('closing during a request ignores its eventual response', (
    tester,
  ) async {
    final pending = Completer<ZoteroHttpResponse>();
    final catalog = _Catalog()..pending = pending;
    final result = await _open(tester, catalog, settle: false);
    await tester.tap(_key('zotero-tag-browser-cancel'));
    await tester.pumpAndSettle();
    expect(result.completed, isTrue);
    pending.complete(
      catalog.response([
        {'tag': 'late'},
      ]),
    );
    await tester.pumpAndSettle();
    expect(result.tags, isNull);
    expect(tester.takeException(), isNull);
  });

  for (final direction in TextDirection.values) {
    testWidgets('narrow large-text ${direction.name} keeps filters reachable', (
      tester,
    ) async {
      final result = await _open(
        tester,
        _Catalog(),
        size: const Size(320, 480),
        scale: 2,
        direction: direction,
      );
      await _tap(tester, _choice('Research & القدس'));
      await _tap(tester, _key('zotero-tag-browser-apply'));
      expect(result.tags, ['Research & القدس']);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'workspace applies tags to submitted query and preserves selected sources',
    (tester) async {
      final catalog = _Catalog();
      final (controller, _) = await _openWorkspace(tester, catalog);
      final query = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Search title, creator, or year',
      );
      await tester.enterText(query, 'submitted');
      await _tap(tester, find.byTooltip('Search'));
      await _tap(tester, find.widgetWithText(CheckboxListTile, 'Source'));
      await _tap(tester, find.byTooltip('Next page'));
      await tester.enterText(query, 'unfinished');
      await _tap(tester, find.byTooltip('Search options'));
      await tester.enterText(_key('zotero-tag-input'), 'unfinished tag');
      final before = catalog.items.length;
      await _tap(tester, _key('zotero-browse-tags'));
      await _tap(tester, _choice('Research & القدس'));
      expect(catalog.items.length, before);
      await _tap(tester, _key('zotero-tag-browser-apply'));
      expect(catalog.items.length, before + 1);
      expect(catalog.items.last.uri.queryParameters['q'], 'submitted');
      expect(catalog.items.last.uri.queryParameters['start'], '0');
      expect(catalog.items.last.uri.queryParametersAll['tag'], [
        'Research & القدس',
      ]);
      expect(tester.widget<TextField>(query).controller!.text, 'unfinished');
      expect(
        tester.widget<TextField>(_key('zotero-tag-input')).controller!.text,
        'unfinished tag',
      );
      expect(find.text('1 selected'), findsOneWidget);
      expect(controller.document.paragraphs.single.text, 'Unchanged');
      expect(controller.canUndo, isFalse);
      expect(controller.isDirty, isFalse);
      final applied = catalog.items.length;
      await _tap(tester, _key('zotero-browse-tags'));
      await _tap(tester, _key('zotero-tag-browser-clear'));
      await _tap(tester, _key('zotero-tag-browser-cancel'));
      expect(catalog.items.length, applied);
      expect(_key('zotero-tag-Research & القدس'), findsOneWidget);
    },
  );

  testWidgets('workspace browses tags within the selected collection', (
    tester,
  ) async {
    final catalog = _Catalog();
    await _openWorkspace(tester, catalog);
    final collection = find.byWidgetPredicate(
      (widget) =>
          widget is DropdownButtonFormField<String> &&
          widget.decoration.labelText == 'Collection',
    );
    await _tap(tester, collection);
    await _tap(tester, find.text('Research collection').last);
    await _tap(tester, find.byTooltip('Search options'));
    await _tap(tester, _key('zotero-browse-tags'));
    expect(catalog.tags.single.uri.path, '/users/42/collections/COLL0001/tags');
    expect(find.text('Collection tags: Research collection'), findsOneWidget);
    await _tap(tester, _choice('Research & القدس'));
    await _tap(tester, _key('zotero-tag-browser-apply'));
    expect(
      catalog.items.last.uri.path,
      '/users/42/collections/COLL0001/items/top',
    );
    expect(catalog.items.last.uri.queryParametersAll['tag'], [
      'Research & القدس',
    ]);
  });

  testWidgets('changed host session rejects stale tag choices', (tester) async {
    final catalog = _Catalog();
    final (controller, session) = await _openWorkspace(tester, catalog);
    await _tap(tester, find.byTooltip('Search options'));
    await _tap(tester, _key('zotero-browse-tags'));
    await _tap(tester, _choice('Research & القدس'));
    final before = catalog.items.length;
    session.library = ZoteroLibrary.group(99);
    await _tap(tester, _key('zotero-tag-browser-apply'));
    expect(catalog.items.length, before);
    expect(_key('zotero-tag-Research & القدس'), findsNothing);
    expect(controller.canUndo, isFalse);
    expect(controller.document.paragraphs.single.text, 'Unchanged');
  });
}
