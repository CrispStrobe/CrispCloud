import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_editor/src/embed/word_zotero_library.dart';

const _catalogUri = 'http://zotero.org/users/42/items/CATALOG1';

Map<String, Object?> _source({
  String id = 'offline',
  String title = 'Offline research',
  String doi = '10.1234/offline',
  Map<String, Object?> extra = const {},
}) => {
  'id': id,
  'type': 'article-journal',
  'title': title,
  'author': [
    {'family': 'Hassan', 'given': 'Amal'},
  ],
  'issued': {
    'date-parts': [
      [2024, 3, 6],
    ],
  },
  'DOI': doi,
  ...extra,
};

class _Clipboard {
  final texts = <String>[];
  bool fails = false;
  Completer<void>? pending;

  void install() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method != 'Clipboard.setData') return null;
      if (fails) throw PlatformException(code: 'clipboard-unavailable');
      final arguments = call.arguments as Map<Object?, Object?>;
      texts.add(arguments['text']! as String);
      await pending?.future;
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
  }

  List<Map<String, Object?>> get lastRecords =>
      (jsonDecode(texts.last) as List<Object?>).cast<Map<String, Object?>>();
}

class _Catalog {
  final requests = <ZoteroHttpRequest>[];

  Future<ZoteroHttpResponse> send(ZoteroHttpRequest request) async {
    requests.add(request);
    final Object response;
    switch (request.uri.path) {
      case '/keys/current':
        response = {
          'userID': 42,
          'username': 'Reader',
          'access': {
            'user': {'library': true},
          },
        };
      case '/users/42/groups':
      case '/users/42/collections':
        response = <Object>[];
      case '/users/42/items/top':
        response = [
          {
            'key': 'CATALOG1',
            'library': {'type': 'user', 'id': 42},
            'data': {
              'key': 'CATALOG1',
              'itemType': 'journalArticle',
              'title': 'Connected catalog source',
            },
            'csljson': _source(
              id: _catalogUri,
              title: 'Connected catalog source',
              doi: '10.1234/catalog',
            ),
          },
        ];
      default:
        throw StateError('Unexpected request: ${request.uri}');
    }
    return ZoteroHttpResponse(
      statusCode: 200,
      body: jsonEncode(response),
      headers: const {'Total-Results': '1'},
    );
  }
}

Finder _key(String value) => find.byKey(ValueKey(value));
Finder _details() => _key('zotero-stored-reference-details-dialog');
Finder _row(int index, String id) => _key('import:$index:$id');
Finder _importDetails(int index, String id) =>
    _key('zotero-import-details-import:$index:$id');
Finder _copyDetails() => _key('zotero-copy-stored-reference-details');
Finder _selectable(String text) => find.byWidgetPredicate(
  (widget) => widget is SelectableText && widget.data == text,
);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: 'After $finder');
}

void _size(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Widget _app(
  Widget home,
  double scale, {
  TextDirection direction = TextDirection.ltr,
}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: Directionality(textDirection: direction, child: child!),
  ),
  home: home,
);

Future<WordEditorController> _open(
  WidgetTester tester, {
  required _Catalog catalog,
  bool connect = false,
  bool readOnly = false,
  Size size = const Size(1200, 1000),
  double scale = 1,
  TextDirection direction = TextDirection.ltr,
}) async {
  _size(tester, size);
  final controller = WordEditorController(
    document: WmlDocument.empty(text: 'Before after'),
    config: OfficeSurfaceConfig(
      mode: readOnly
          ? OfficeInteractionMode.selecting
          : OfficeInteractionMode.editing,
    ),
  );
  controller.caret.logicalIndex = 7;
  controller.caret.collapseSelection();
  addTearDown(controller.dispose);
  final session = ZoteroSession()..apiKey = 'stored-details-test-key';
  await tester.pumpWidget(
    _app(
      Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
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
      scale,
      direction: direction,
    ),
  );
  await _tap(tester, find.text('Open references'));
  if (connect) await _tap(tester, find.text('Connect'));
  return controller;
}

Future<void> _load(
  WidgetTester tester,
  List<Map<String, Object?>> records,
) async {
  await _tap(tester, find.text('Import CSL JSON'));
  final input = _key('zotero-csl-import');
  await tester.ensureVisible(input);
  await tester.enterText(input, jsonEncode(records));
  await _tap(tester, find.text('Load references'));
}

Future<void> _search(WidgetTester tester, String text) async {
  final search = _key('zotero-import-search');
  await tester.ensureVisible(search);
  await tester.enterText(search, text);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _closeDetails(WidgetTester tester) =>
    _tap(tester, _key('zotero-stored-details-close'));

Future<void> _review(WidgetTester tester) =>
    _tap(tester, _key('zotero-review-import-selection'));

Future<void> _reviewAction(
  WidgetTester tester,
  String action,
  String selectionKey,
) async {
  final list = _key('zotero-selected-reference-list');
  await tester.ensureVisible(list);
  await tester.pumpAndSettle();
  await tester.drag(list, const Offset(0, 6000));
  await tester.pumpAndSettle();
  final target = _key('zotero-selection-$action-$selectionKey');
  await tester.scrollUntilVisible(
    target,
    120,
    maxScrolls: 100,
    scrollable: find.descendant(of: list, matching: find.byType(Scrollable)),
  );
  await _tap(tester, target);
}

String _count(WidgetTester tester) =>
    tester.widget<Text>(_key('zotero-import-result-count')).data!;

void _unchanged(WordEditorController controller, int revision) {
  expect(controller.document.paragraphs.single.text, 'Before after');
  expect(controller.zoteroFields, isEmpty);
  expect(controller.contentRevision, revision);
  expect(controller.canUndo, isFalse);
  expect(controller.caret.logicalIndex, 7);
}

void main() {
  setUp(() {
    final previous = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = previous);
  });

  testWidgets(
    'import details distinguish duplicate IDs without selecting them',
    (tester) async {
      final clipboard = _Clipboard()..install();
      final catalog = _Catalog();
      final controller = await _open(tester, catalog: catalog);
      final revision = controller.contentRevision;
      await _load(tester, [
        _source(id: 'same', title: 'First record', doi: '10.1234/first'),
        _source(id: 'same', title: 'Second record', doi: '10.1234/second'),
      ]);
      for (final (index, title, doi) in const [
        (0, 'First record', '10.1234/first'),
        (1, 'Second record', '10.1234/second'),
      ]) {
        await _search(tester, title);
        await _tap(tester, _importDetails(index, 'same'));
        expect(_details(), findsOneWidget);
        expect(_selectable(title), findsOneWidget);
        expect(_selectable(doi), findsOneWidget);
        await _tap(tester, _copyDetails());
        expect(clipboard.texts.last, contains(title));
        expect(clipboard.texts.last, contains(doi));
        await _closeDetails(tester);
        expect(
          tester.widget<CheckboxListTile>(_row(index, 'same')).value,
          isFalse,
        );
        expect(_count(tester), '1 of 2 shown · 0 selected');
      }
      expect(catalog.requests, isEmpty);
      _unchanged(controller, revision);
    },
  );

  testWidgets(
    'read-only offline details retain linked identities and metadata',
    (tester) async {
      final clipboard = _Clipboard()..install();
      final catalog = _Catalog();
      final controller = await _open(tester, catalog: catalog, readOnly: true);
      final revision = controller.contentRevision;
      const uri = 'https://zotero.org/groups/9/items/GROUP001';
      await _load(tester, [
        _source(
          extra: {
            'uri': uri,
            'URL': 'javascript:alert("inert reference data")',
            'abstract': 'A < B and C > D. القدس & 東京.',
            'custom': {
              'preserve': ['unknown', 17],
            },
          },
        ),
      ]);
      await _tap(tester, _row(0, uri));
      await _tap(tester, _key('zotero-copy-import-selection'));
      final before = clipboard.lastRecords.single;
      await _tap(tester, _importDetails(0, uri));
      await _tap(tester, _copyDetails());
      expect(clipboard.texts.last, contains(uri));
      expect(clipboard.texts.last, contains('10.1234/offline'));
      expect(
        clipboard.texts.last,
        contains('javascript:alert("inert reference data")'),
      );
      await _closeDetails(tester);
      await _tap(tester, _key('zotero-copy-import-selection'));
      expect(clipboard.lastRecords.single, before);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Insert 1 selected source(s)'),
            )
            .onPressed,
        isNull,
      );
      expect(catalog.requests, isEmpty);
      _unchanged(controller, revision);
    },
  );

  testWidgets('copy failure leaves selectable metadata and allows retry', (
    tester,
  ) async {
    final clipboard = _Clipboard()
      ..fails = true
      ..install();
    final catalog = _Catalog();
    final controller = await _open(tester, catalog: catalog);
    final revision = controller.contentRevision;
    await _load(tester, [_source()]);
    await _tap(tester, _row(0, 'offline'));
    await _tap(tester, _importDetails(0, 'offline'));
    await _tap(tester, _copyDetails());
    expect(
      tester.widget<Text>(_key('zotero-stored-details-copy-status')).data,
      'Could not copy. Select the text to copy it manually.',
    );
    expect(_selectable('Offline research'), findsOneWidget);
    expect(_selectable('10.1234/offline'), findsOneWidget);
    expect(clipboard.texts, isEmpty);
    clipboard.fails = false;
    await _tap(tester, _copyDetails());
    expect(clipboard.texts.single, contains('Offline research'));
    expect(
      tester.widget<Text>(_key('zotero-stored-details-copy-status')).data,
      contains('copied'),
    );
    await _closeDetails(tester);
    expect(tester.widget<CheckboxListTile>(_row(0, 'offline')).value, isTrue);
    expect(catalog.requests, isEmpty);
    _unchanged(controller, revision);
  });

  testWidgets('closing pending details copy leaves parent selection intact', (
    tester,
  ) async {
    final clipboard = _Clipboard()..install();
    final catalog = _Catalog();
    final controller = await _open(tester, catalog: catalog);
    final revision = controller.contentRevision;
    await _load(tester, [_source()]);
    await _tap(tester, _row(0, 'offline'));
    await _tap(tester, _importDetails(0, 'offline'));
    clipboard.pending = Completer<void>();
    await tester.ensureVisible(_copyDetails());
    await tester.tap(_copyDetails());
    await tester.pump();
    expect(tester.widget<TextButton>(_copyDetails()).onPressed, isNull);
    await _closeDetails(tester);
    clipboard.pending!.complete();
    await tester.pumpAndSettle();
    expect(_details(), findsNothing);
    expect(tester.widget<CheckboxListTile>(_row(0, 'offline')).value, isTrue);
    expect(tester.takeException(), isNull);
    expect(catalog.requests, isEmpty);
    _unchanged(controller, revision);
  });

  testWidgets(
    'nested details preserve staged order and removals on cancel and apply',
    (tester) async {
      final clipboard = _Clipboard()..install();
      final catalog = _Catalog();
      final controller = await _open(tester, catalog: catalog);
      final revision = controller.contentRevision;
      await _load(tester, [
        _source(id: 'a', title: 'Alpha source'),
        _source(id: 'b', title: 'Beta source'),
        _source(id: 'c', title: 'Gamma source'),
      ]);
      for (final (index, id, query) in const [
        (0, 'a', 'Alpha'),
        (1, 'b', 'Beta'),
        (2, 'c', 'Gamma'),
      ]) {
        await _search(tester, query);
        await _tap(tester, _row(index, id));
      }
      for (final apply in [false, true]) {
        await _review(tester);
        await _reviewAction(tester, 'up', 'import:1:b');
        await _reviewAction(tester, 'remove', 'import:2:c');
        await _reviewAction(tester, 'details', 'import:1:b');
        expect(_selectable('Beta source'), findsOneWidget);
        await _closeDetails(tester);
        expect(find.text('1. Beta source'), findsOneWidget);
        expect(find.text('2. Alpha source'), findsOneWidget);
        expect(_key('zotero-selected-import:2:c'), findsNothing);
        expect(
          tester.widget<Text>(_key('zotero-review-selected-count')).data,
          '2 selected',
        );
        await _tap(
          tester,
          _key(apply ? 'zotero-selection-apply' : 'zotero-selection-cancel'),
        );
        await _tap(tester, _key('zotero-copy-import-selection'));
        expect(
          clipboard.lastRecords.map((record) => record['id']),
          apply ? ['b', 'a'] : ['a', 'b', 'c'],
        );
      }
      expect(catalog.requests, isEmpty);
      _unchanged(controller, revision);
    },
  );

  testWidgets(
    'hidden mixed-library selections expose their stored details without fetches',
    (tester) async {
      final clipboard = _Clipboard()..install();
      final catalog = _Catalog();
      final controller = await _open(tester, catalog: catalog, connect: true);
      final revision = controller.contentRevision;
      await _tap(
        tester,
        find.widgetWithText(CheckboxListTile, 'Connected catalog source'),
      );
      final requests = catalog.requests.length;
      const groupUri = 'https://zotero.org/groups/9/items/GROUP001';
      await _load(tester, [
        _source(id: 'local', title: 'Local paper'),
        _source(id: 'group', title: 'Group paper', extra: {'uri': groupUri}),
      ]);
      for (final (index, id, query) in const [
        (0, 'local', 'Local'),
        (1, groupUri, 'Group'),
      ]) {
        await _search(tester, query);
        await _tap(tester, _row(index, id));
      }
      await _search(tester, 'no matching paper');
      expect(
        _count(tester),
        '0 of 2 shown · 3 selected (3 outside these results)',
      );
      await _review(tester);
      for (final (selectionKey, title, identity) in const [
        (_catalogUri, 'Connected catalog source', _catalogUri),
        ('import:0:local', 'Local paper', 'local'),
        ('import:1:$groupUri', 'Group paper', groupUri),
      ]) {
        await _reviewAction(tester, 'details', selectionKey);
        expect(_selectable(title), findsOneWidget);
        await _tap(tester, _copyDetails());
        expect(clipboard.texts.last, contains(identity));
        await _closeDetails(tester);
      }
      await _tap(tester, _key('zotero-selection-apply'));
      await _tap(tester, _key('zotero-copy-import-selection'));
      expect(clipboard.lastRecords.map((record) => record['title']), [
        'Connected catalog source',
        'Local paper',
        'Group paper',
      ]);
      expect(catalog.requests.length, requests);
      _unchanged(controller, revision);
    },
  );

  testWidgets(
    'selection limit counts hidden catalog sources and still permits deselection',
    (tester) async {
      final clipboard = _Clipboard()..install();
      final catalog = _Catalog();
      final controller = await _open(tester, catalog: catalog, connect: true);
      final revision = controller.contentRevision;
      await _tap(
        tester,
        find.widgetWithText(CheckboxListTile, 'Connected catalog source'),
      );
      final requests = catalog.requests.length;
      await _load(tester, [
        for (var index = 0; index < 20; index++)
          _source(id: 'record-$index', title: 'Import token$index.'),
      ]);
      for (var index = 0; index < 19; index++) {
        await _search(tester, 'token$index.');
        await _tap(tester, _row(index, 'record-$index'));
      }
      await _search(tester, 'token19.');
      expect(
        _count(tester),
        '1 of 20 shown · 20 selected (20 outside these results)',
      );
      await _tap(tester, _row(19, 'record-19'));
      expect(
        find.text('Select at most 20 sources per citation.'),
        findsOneWidget,
      );
      expect(
        tester.widget<CheckboxListTile>(_row(19, 'record-19')).value,
        isFalse,
      );
      await _tap(tester, _importDetails(19, 'record-19'));
      expect(_selectable('Import token19.'), findsOneWidget);
      await _closeDetails(tester);
      await _tap(tester, _key('zotero-copy-import-selection'));
      expect(clipboard.lastRecords, hasLength(20));
      expect(clipboard.lastRecords.first['id'], _catalogUri);
      expect(
        clipboard.lastRecords.map((record) => record['id']),
        isNot(contains('record-19')),
      );
      await _search(tester, 'token0.');
      await _tap(tester, _row(0, 'record-0'));
      expect(
        tester.widget<CheckboxListTile>(_row(0, 'record-0')).value,
        isFalse,
      );
      await _search(tester, 'token19.');
      await _tap(tester, _row(19, 'record-19'));
      expect(
        tester.widget<CheckboxListTile>(_row(19, 'record-19')).value,
        isTrue,
      );
      await _tap(tester, _key('zotero-copy-import-selection'));
      expect(clipboard.lastRecords, hasLength(20));
      expect(clipboard.lastRecords.last['id'], 'record-19');
      expect(
        clipboard.lastRecords.map((record) => record['id']),
        isNot(contains('record-0')),
      );
      expect(catalog.requests.length, requests);
      _unchanged(controller, revision);
    },
  );

  for (final direction in TextDirection.values) {
    testWidgets(
      'import details and failure feedback fit 320x480 with doubled text in $direction',
      (tester) async {
        final clipboard = _Clipboard()
          ..fails = true
          ..install();
        final catalog = _Catalog();
        final controller = await _open(
          tester,
          catalog: catalog,
          size: const Size(320, 480),
          scale: 2,
          direction: direction,
        );
        final revision = controller.contentRevision;
        final title = 'Research القدس ${'long title ' * 16}';
        const uri = 'https://zotero.org/users/42/items/SOURCE01';
        await _load(tester, [
          _source(
            title: title,
            extra: {
              'abstract': 'A < B & 東京. ${'Detailed text. ' * 100}',
              'uri': uri,
            },
          ),
        ]);
        await _search(tester, 'القدس');
        await _tap(tester, _importDetails(0, uri));
        await _tap(tester, _copyDetails());
        expect(_key('zotero-stored-details-copy-status'), findsOneWidget);
        clipboard.fails = false;
        await _tap(tester, _copyDetails());
        expect(clipboard.texts.single, contains('Research القدس'));
        expect(clipboard.texts.single, contains('10.1234/offline'));
        await _closeDetails(tester);
        await _tap(tester, _row(0, uri));
        await _review(tester);
        await _reviewAction(tester, 'details', 'import:0:$uri');
        await _tap(tester, _copyDetails());
        await _closeDetails(tester);
        await _tap(tester, _key('zotero-selection-apply'));
        expect(_count(tester), '1 of 1 shown · 1 selected');
        expect(catalog.requests, isEmpty);
        _unchanged(controller, revision);
      },
    );
  }

  testWidgets(
    'twenty-source narrow review keeps nested details and actions reachable',
    (tester) async {
      _size(tester, const Size(320, 480));
      final clipboard = _Clipboard()..install();
      final selection = {
        for (var index = 0; index < 20; index++)
          'source-$index': ZoteroCitationItem.fromJson({
            'id': 'record-$index',
            'uris': <String>[],
            'locator': '$index',
            'prefix': 'see',
            'custom': {'preserve': index},
            'itemData': _source(
              id: 'record-$index',
              title: 'Source $index ${'long title ' * 12}',
              doi: '10.1234/source-$index',
            ),
          }),
      };
      final original = jsonEncode({
        for (final entry in selection.entries) entry.key: entry.value.toJson(),
      });
      List<String>? result;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () async {
                  result = await showDialog<List<String>>(
                    context: context,
                    builder: (_) =>
                        ZoteroSelectedReferencesDialog(selection: selection),
                  );
                },
                child: const Text('Review'),
              ),
            ),
          ),
          2,
        ),
      );
      await _tap(tester, find.text('Review'));
      await _reviewAction(tester, 'down', 'source-0');
      await _reviewAction(tester, 'details', 'source-19');
      await _tap(tester, _copyDetails());
      expect(clipboard.texts.single, contains('10.1234/source-19'));
      await _closeDetails(tester);
      await _reviewAction(tester, 'remove', 'source-19');
      await _tap(tester, _key('zotero-selection-apply'));
      expect(result, [
        'source-1',
        'source-0',
        for (var index = 2; index < 19; index++) 'source-$index',
      ]);
      expect(
        jsonEncode({
          for (final entry in selection.entries)
            entry.key: entry.value.toJson(),
        }),
        original,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reference without stored CSL metadata remains inspectable', (
    tester,
  ) async {
    final clipboard = _Clipboard()..install();
    final item = ZoteroCitationItem.fromJson({
      'id': 'unresolved-source',
      'uris': ['https://zotero.org/users/42/items/MISSING1'],
      'locator': '17',
      'label': 'page',
      'prefix': 'see',
      'custom': {'retain': true},
    });
    final original = jsonEncode(item.toJson());
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => ZoteroStoredReferenceDetailsDialog(item: item),
              ),
              child: const Text('Inspect'),
            ),
          ),
        ),
        1,
      ),
    );
    await _tap(tester, find.text('Inspect'));
    expect(find.text('Stored reference details'), findsOneWidget);
    await _tap(tester, _copyDetails());
    expect(clipboard.texts.single, contains('unresolved-source'));
    expect(
      clipboard.texts.single,
      contains('https://zotero.org/users/42/items/MISSING1'),
    );
    await _closeDetails(tester);
    expect(jsonEncode(item.toJson()), original);
    expect(tester.takeException(), isNull);
  });
}
