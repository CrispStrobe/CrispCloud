import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_editor/src/embed/word_zotero_children.dart';

Map<String, Object?> _child({
  String key = 'NOTE0001',
  String kind = 'note',
  String note = '<p>Research &amp; evidence</p><p>A &lt; B; القدس 📚</p>',
  Map<String, Object?> data = const {},
  bool local = false,
}) => {
  'key': key,
  'version': 4,
  'library': {'type': 'user', 'id': local ? 0 : 42},
  'data': {
    'key': key,
    'version': 4,
    'parentItem': 'SOURCE01',
    'itemType': kind,
    'note': note,
    ...data,
  },
};

class _Catalog {
  _Catalog({this.local = false});

  final bool local;
  final requests = <ZoteroHttpRequest>[];
  final pages = <int, List<Object?>>{};
  int total = 2;
  int version = 8;
  bool fail = false;
  Completer<ZoteroHttpResponse>? pending;

  List<Object?> get firstPage => [
    _child(local: local),
    _child(
      key: 'FILE0001',
      kind: 'attachment',
      note: '',
      local: local,
      data: {
        'title': 'Research PDF',
        'filename': 'evidence.pdf',
        'contentType': 'application/pdf',
        'linkMode': 'imported_url',
        'url': 'https://example.invalid/paper.pdf',
      },
    ),
  ];

  ZoteroHttpResponse response(List<Object?> records) => ZoteroHttpResponse(
    statusCode: 200,
    body: jsonEncode(records),
    headers: {
      'Total-Results': '$total',
      'Last-Modified-Version': '$version',
      if (local) 'Zotero-Server-ID': 'children-desktop',
    },
  );

  Future<ZoteroHttpResponse> send(ZoteroHttpRequest request) async {
    requests.add(request);
    expect(request.method, 'GET');
    expect(request.body, isNull);
    expect(request.followRedirects, isFalse);
    if (request.uri.path == '/api/') {
      return ZoteroHttpResponse(
        statusCode: 200,
        body: 'Local API',
        headers: const {
          'Zotero-API-Version': '3',
          'Zotero-Server-ID': 'children-desktop',
        },
      );
    }
    expect(
      request.uri.path,
      local
          ? '/api/users/0/items/SOURCE01/children'
          : '/users/42/items/SOURCE01/children',
    );
    expect(request.uri.queryParameters['include'], 'data');
    expect(request.uri.queryParameters['limit'], '25');
    expect(request.headers['Zotero-API-Key'], local ? isNull : 'test-secret');
    if (local) {
      expect(request.headers['Zotero-Server-ID'], 'children-desktop');
    }
    if (pending != null) return pending!.future;
    if (fail) throw StateError('SECRET connection failure');
    final start = int.parse(request.uri.queryParameters['start']!);
    return response(pages[start] ?? firstPage);
  }

  List<ZoteroHttpRequest> get childRequests => requests
      .where((request) => request.uri.path.endsWith('/children'))
      .toList();
}

Future<void> _open(
  WidgetTester tester,
  _Catalog catalog, {
  bool Function()? isCurrent,
  Size size = const Size(1200, 1000),
  double scale = 1,
  TextDirection direction = TextDirection.ltr,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final client = catalog.local
      ? ZoteroClient.local(transport: catalog.send)
      : ZoteroClient(apiKey: 'test-secret', transport: catalog.send);
  if (catalog.local) await client.probeLocal();
  final parent = ZoteroItem(
    library: catalog.local ? ZoteroLibrary.localUser() : ZoteroLibrary.user(42),
    key: 'SOURCE01',
    title: 'Parent reference',
    itemType: 'book',
    localServerId: catalog.local ? 'children-desktop' : null,
  );
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => Directionality(
        textDirection: direction,
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => ZoteroItemChildrenDialog(
                client: client,
                parent: parent,
                isCurrent: isCurrent ?? () => true,
              ),
            ),
            child: const Text('Browse research materials'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Browse research materials'));
  if (catalog.pending == null) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 300));
  }
  expect(tester.takeException(), isNull);
}

Finder _key(String value) => find.byKey(ValueKey(value));

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = _key(key);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

List<String> _clipboard(WidgetTester tester, {bool fail = false}) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        if (fail) throw PlatformException(code: 'unavailable');
        final arguments = call.arguments as Map<Object?, Object?>;
        copied.add(arguments['text']! as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return copied;
}

void main() {
  for (final local in [false, true]) {
    testWidgets('${local ? 'desktop' : 'online'} notes are inert and copied', (
      tester,
    ) async {
      final catalog = _Catalog(local: local);
      final copied = _clipboard(tester);
      await _open(tester, catalog);
      expect(catalog.childRequests, hasLength(1));
      expect(find.text('1–2 of 2'), findsOneWidget);
      await _tap(tester, 'zotero-child-NOTE0001');
      expect(find.text('Research note'), findsOneWidget);
      final text = tester
          .widget<SelectableText>(_key('zotero-child-note-text'))
          .data!;
      expect(text, contains('Research & evidence'));
      expect(text, contains('A < B; القدس 📚'));
      expect(text, isNot(contains('<p>')));
      await _tap(tester, 'zotero-copy-child-note');
      expect(copied, [text]);
      await _tap(tester, 'zotero-child-details-back');
      expect(_key('zotero-item-children-dialog'), findsOneWidget);
      expect(catalog.childRequests, hasLength(1));
    });
  }

  testWidgets('attachment details remain text and never fetch file contents', (
    tester,
  ) async {
    final catalog = _Catalog();
    final copied = _clipboard(tester);
    catalog.pages[0] = [
      _child(
        key: 'FILE0001',
        kind: 'attachment',
        note: '<p>Attachment note</p>',
        data: {
          'title': 'Linked research',
          'contentType': 'application/pdf',
          'linkMode': 'linked_file',
          'path': '/private/never-display.pdf',
          'url': 'javascript:inert("metadata")',
        },
      ),
    ];
    catalog.total = 1;
    await _open(tester, catalog);
    await _tap(tester, 'zotero-child-FILE0001');
    expect(find.text('Linked file'), findsOneWidget);
    expect(find.text('javascript:inert("metadata")'), findsOneWidget);
    expect(find.textContaining('/private/never-display.pdf'), findsNothing);
    await _tap(tester, 'zotero-copy-child-details');
    expect(copied.single, contains('Type: Attachment'));
    expect(copied.single, contains('URL: javascript:inert("metadata")'));
    expect(copied.single, isNot(contains('/private/')));
    await _tap(tester, 'zotero-copy-child-note');
    expect(copied.last, 'Attachment note');
    expect(catalog.requests, hasLength(1));
  });

  testWidgets(
    'page failure retains the current page and retry uses its target',
    (tester) async {
      final catalog = _Catalog()
        ..total = 26
        ..pages[25] = [
          _child(key: 'NOTE0026', note: '<p>Later research note</p>'),
        ];
      await _open(tester, catalog);
      catalog.fail = true;
      await _tap(tester, 'zotero-children-next');
      expect(_key('zotero-children-error'), findsOneWidget);
      expect(find.textContaining('SECRET'), findsNothing);
      expect(_key('zotero-child-NOTE0001'), findsOneWidget);
      expect(find.text('1–2 of 26'), findsOneWidget);
      catalog.fail = false;
      await _tap(tester, 'zotero-children-retry');
      expect(find.text('26–26 of 26'), findsOneWidget);
      expect(_key('zotero-child-NOTE0026'), findsOneWidget);
      await _tap(tester, 'zotero-children-previous');
      expect(find.text('1–2 of 26'), findsOneWidget);
      expect(
        catalog.childRequests.map(
          (request) => request.uri.queryParameters['start'],
        ),
        ['0', '25', '25', '0'],
      );
    },
  );

  testWidgets('empty and permission-filtered results stay explicit', (
    tester,
  ) async {
    final catalog = _Catalog()
      ..total = 0
      ..pages[0] = [];
    await _open(tester, catalog);
    expect(_key('zotero-children-empty'), findsOneWidget);
    expect(find.textContaining('API-key permissions'), findsOneWidget);
    expect(
      tester.widget<TextButton>(_key('zotero-children-next')).onPressed,
      isNull,
    );
    expect(
      tester.widget<TextButton>(_key('zotero-children-previous')).onPressed,
      isNull,
    );
  });

  testWidgets(
    'a changed library version resets pagination before showing data',
    (tester) async {
      final catalog = _Catalog()
        ..total = 26
        ..pages[25] = [_child(key: 'NOTE0026', note: '<p>Changed page</p>')];
      await _open(tester, catalog);
      catalog.version = 9;
      await _tap(tester, 'zotero-children-next');
      expect(find.textContaining('library may have changed'), findsOneWidget);
      expect(_key('zotero-child-NOTE0001'), findsNothing);
      expect(_key('zotero-child-NOTE0026'), findsNothing);
      expect(find.text('Reload'), findsOneWidget);
      await _tap(tester, 'zotero-children-retry');
      expect(_key('zotero-child-NOTE0001'), findsOneWidget);
      expect(
        catalog.childRequests.map(
          (request) => request.uri.queryParameters['start'],
        ),
        ['0', '25', '0'],
      );
    },
  );

  testWidgets('closing while loading discards late data', (tester) async {
    final pending = Completer<ZoteroHttpResponse>();
    final catalog = _Catalog()..pending = pending;
    await _open(tester, catalog);
    expect(_key('zotero-children-loading'), findsOneWidget);
    await tester.tap(_key('zotero-children-close'));
    await tester.pumpAndSettle();
    pending.complete(catalog.response(catalog.firstPage));
    await tester.pumpAndSettle();
    expect(_key('zotero-item-children-dialog'), findsNothing);
    expect(find.text('Research & evidence'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'changed connection rejects both pending data and future requests',
    (tester) async {
      var current = true;
      final pending = Completer<ZoteroHttpResponse>();
      final catalog = _Catalog()..pending = pending;
      await _open(tester, catalog, isCurrent: () => current);
      current = false;
      pending.complete(catalog.response(catalog.firstPage));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('connection or library changed'),
        findsOneWidget,
      );
      expect(_key('zotero-child-NOTE0001'), findsNothing);
      expect(_key('zotero-children-retry'), findsNothing);
      expect(catalog.childRequests, hasLength(1));
    },
  );

  testWidgets('changed connection prevents copying an open note', (
    tester,
  ) async {
    var current = true;
    final copied = _clipboard(tester);
    final catalog = _Catalog();
    await _open(tester, catalog, isCurrent: () => current);
    await _tap(tester, 'zotero-child-NOTE0001');
    current = false;
    await _tap(tester, 'zotero-copy-child-note');
    expect(copied, isEmpty);
    expect(
      find.textContaining('connection or library changed'),
      findsOneWidget,
    );
    expect(
      tester.widget<TextButton>(_key('zotero-copy-child-note')).onPressed,
      isNull,
    );
    await _tap(tester, 'zotero-child-details-back');
    expect(_key('zotero-child-NOTE0001'), findsNothing);
  });

  testWidgets('failed clipboard leaves selectable note text available', (
    tester,
  ) async {
    final copied = _clipboard(tester, fail: true);
    await _open(tester, _Catalog());
    await _tap(tester, 'zotero-child-NOTE0001');
    await _tap(tester, 'zotero-copy-child-note');
    expect(copied, isEmpty);
    expect(
      find.textContaining('Select the text to copy it manually'),
      findsOneWidget,
    );
    expect(_key('zotero-child-note-text'), findsOneWidget);
  });

  testWidgets('unsupported note markup affects only its preview', (
    tester,
  ) async {
    final catalog = _Catalog();
    catalog.pages[0] = [
      _child(note: '<p title="unterminated>Incomplete note'),
      catalog.firstPage.last,
    ];
    await _open(tester, catalog);
    expect(find.text('Note · Preview unavailable'), findsOneWidget);
    await _tap(tester, 'zotero-child-NOTE0001');
    expect(_key('zotero-child-preview-error'), findsOneWidget);
    expect(_key('zotero-copy-child-note'), findsNothing);
    await _tap(tester, 'zotero-child-details-back');
    await _tap(tester, 'zotero-child-FILE0001');
    expect(find.text('evidence.pdf'), findsOneWidget);
    expect(catalog.childRequests, hasLength(1));
  });

  testWidgets('embedded images are disclosed without resource requests', (
    tester,
  ) async {
    final catalog = _Catalog()
      ..total = 1
      ..pages[0] = [
        _child(
          note:
              '<p>Text before</p><img src="https://example.invalid/image.png">'
              '<p>Text after</p><script>privateScript()</script>',
        ),
      ];
    final copied = _clipboard(tester);
    await _open(tester, catalog);
    await _tap(tester, 'zotero-child-NOTE0001');
    expect(_key('zotero-child-omitted-content'), findsOneWidget);
    await _tap(tester, 'zotero-copy-child-note');
    expect(copied.single, contains('Text before'));
    expect(copied.single, contains('Text after'));
    expect(copied.single, isNot(contains('privateScript')));
    expect(copied.single, isNot(contains('example.invalid')));
    expect(catalog.requests, hasLength(1));
  });

  testWidgets(
    'long note headings are bounded while preview and copy stay full',
    (tester) async {
      final text = List.filled(1000, '📚').join();
      final heading = '${List.filled(200, '📚').join()}…';
      final catalog = _Catalog()
        ..total = 1
        ..pages[0] = [_child(note: '<p>$text</p>')];
      final copied = _clipboard(tester);
      await _open(tester, catalog);
      expect(find.text(heading), findsOneWidget);
      expect(find.text(text), findsNothing);
      await _tap(tester, 'zotero-child-NOTE0001');
      expect(
        tester.widget<SelectableText>(_key('zotero-child-note-text')).data,
        text,
      );
      await _tap(tester, 'zotero-copy-child-note');
      expect(copied, [text]);
    },
  );

  for (final direction in TextDirection.values) {
    testWidgets(
      'small ${direction.name} view supports enlarged text and back',
      (tester) async {
        await _open(
          tester,
          _Catalog(),
          size: const Size(360, 640),
          scale: 2,
          direction: direction,
        );
        await _tap(tester, 'zotero-child-NOTE0001');
        expect(_key('zotero-child-note-text'), findsOneWidget);
        await _tap(tester, 'zotero-copy-child-note');
        await _tap(tester, 'zotero-child-details-back');
        await _tap(tester, 'zotero-children-close');
        expect(_key('zotero-item-children-dialog'), findsNothing);
      },
    );
  }
}
