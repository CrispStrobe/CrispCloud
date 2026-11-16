import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

Map<String, Object?> _collection(String key, String name) => {
  'key': key,
  'data': {'key': key, 'name': name},
};

ZoteroHttpResponse _json(
  Object data, {
  Map<String, String> headers = const {},
}) => ZoteroHttpResponse(
  statusCode: 200,
  body: jsonEncode(data),
  headers: {'Zotero-Server-ID': 'collection-desktop', ...headers},
);

class _Catalog {
  final requests = <ZoteroHttpRequest>[];
  bool duplicateInitial = false;
  Completer<ZoteroHttpResponse>? pendingPage;

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
          'Zotero-Server-ID': 'collection-desktop',
        },
      );
    }
    if (path.endsWith('/groups')) {
      return _json([
        {
          'id': 42,
          'data': {'name': 'Research group'},
        },
      ]);
    }
    if (path.endsWith('/collections')) {
      if (request.uri.queryParameters['start'] == '100') {
        if (pendingPage != null) return pendingPage!.future;
        return _json([
          _collection('COLL0001', 'Intermediate name'),
          _collection('COLL0003', 'Later collection'),
          _collection('COLL0001', 'Updated research'),
        ]);
      }
      return _json(
        [
          _collection('COLL0001', 'Original research'),
          _collection('COLL0002', 'Other research'),
          if (duplicateInitial)
            _collection('COLL0001', 'Renamed initial research'),
        ],
        headers: {'Total-Results': '101'},
      );
    }
    if (path.endsWith('/items/top')) {
      final title = path.contains('/collections/')
          ? 'Collection source'
          : 'Library source';
      return _json([
        {
          'key': 'SOURCE01',
          'library': {'type': 'user', 'id': 0},
          'data': {'key': 'SOURCE01', 'itemType': 'book', 'title': title},
          'csljson': {
            'id': 'http://zotero.org/users/local/LOCALKEY/items/SOURCE01',
            'type': 'book',
            'title': title,
          },
        },
      ]);
    }
    throw StateError('Unexpected catalog route: $path');
  }
}

Future<WordEditorController> _open(
  WidgetTester tester,
  _Catalog catalog, {
  ZoteroSession? session,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 1100);
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
          builder: (context) => FilledButton(
            onPressed: () => showWordZoteroDialog(
              context,
              controller: controller,
              session: session ?? (ZoteroSession()..useLocal = true),
              localTransport: catalog.send,
            ),
            child: const Text('Open references'),
          ),
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

Finder _collectionMenu() => find.byWidgetPredicate(
  (widget) =>
      widget is DropdownButtonFormField<String> &&
      widget.decoration.labelText == 'Collection',
);

DropdownButton<String> _collectionButton(WidgetTester tester) =>
    tester.widget<DropdownButton<String>>(
      find.descendant(
        of: _collectionMenu(),
        matching: find.byType(DropdownButton<String>),
      ),
    );

Future<void> _chooseCollection(WidgetTester tester, String name) async {
  await _tap(tester, _collectionMenu());
  await _tap(tester, find.text(name).last);
}

Future<void> _startMoreCollections(WidgetTester tester) async {
  final more = find.text('More collections');
  await tester.ensureVisible(more);
  await tester.pump();
  await tester.tap(more);
  await tester.pump();
}

void main() {
  testWidgets(
    'initial collection duplicates keep one selectable latest entry',
    (tester) async {
      final catalog = _Catalog()..duplicateInitial = true;
      final controller = await _open(tester, catalog);
      expect(_collectionButton(tester).items!.map((item) => item.value), [
        '',
        'COLL0001',
        'COLL0002',
      ]);
      await _chooseCollection(tester, 'Renamed initial research');
      expect(_collectionButton(tester).value, 'COLL0001');
      expect(
        catalog.requests.last.uri.path,
        '/api/users/0/collections/COLL0001/items/top',
      );
      expect(find.text('Collection source'), findsOneWidget);
      expect(controller.document.paragraphs.single.text, 'Unchanged document');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'later collection pages replace duplicate metadata and retain selected keys',
    (tester) async {
      final catalog = _Catalog();
      final controller = await _open(tester, catalog);
      await _tap(
        tester,
        find.widgetWithText(CheckboxListTile, 'Library source'),
      );
      await _chooseCollection(tester, 'Original research');
      await _tap(tester, find.text('More collections'));
      expect(catalog.requests.last.uri.queryParameters['start'], '100');
      expect(_collectionButton(tester).items!.map((item) => item.value), [
        '',
        'COLL0001',
        'COLL0002',
        'COLL0003',
      ]);
      expect(_collectionButton(tester).value, 'COLL0001');
      expect(find.text('Updated research'), findsOneWidget);
      expect(find.text('Collection source'), findsOneWidget);
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.text('More collections'), findsNothing);
      await _chooseCollection(tester, 'Later collection');
      expect(
        catalog.requests.last.uri.path,
        '/api/users/0/collections/COLL0003/items/top',
      );
      expect(find.text('1 selected'), findsOneWidget);
      expect(controller.document.paragraphs.single.text, 'Unchanged document');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a changed library discards its pending collection page', (
    tester,
  ) async {
    final catalog = _Catalog();
    final session = ZoteroSession()..useLocal = true;
    await _open(tester, catalog, session: session);
    catalog.pendingPage = Completer<ZoteroHttpResponse>();
    await _startMoreCollections(tester);
    session.library = ZoteroLibrary.group(42);
    catalog.pendingPage!.complete(
      _json([_collection('COLL0003', 'Wrong library collection')]),
    );
    await tester.pumpAndSettle();
    expect(_collectionButton(tester).items!.map((item) => item.value), [
      '',
      'COLL0001',
      'COLL0002',
    ]);
    expect(find.text('Wrong library collection'), findsNothing);
    expect(find.text('More collections'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing during collection pagination discards the response', (
    tester,
  ) async {
    final catalog = _Catalog();
    final controller = await _open(tester, catalog);
    catalog.pendingPage = Completer<ZoteroHttpResponse>();
    await _startMoreCollections(tester);
    await tester.tap(find.byTooltip('Close Zotero'));
    await tester.pumpAndSettle();
    catalog.pendingPage!.complete(
      _json([_collection('COLL0003', 'Late collection')]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Zotero references'), findsNothing);
    expect(find.text('Late collection'), findsNothing);
    expect(controller.document.paragraphs.single.text, 'Unchanged document');
    expect(tester.takeException(), isNull);
  });
}
