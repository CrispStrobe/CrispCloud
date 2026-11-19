import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_editor/src/embed/word_zotero_import.dart';

Map<String, Object?> _source({
  Object id = 'offline-a',
  String title = 'Imported research',
  String family = 'Hassan',
  int year = 2024,
  String doi = '10.1234/research',
  Map<String, Object?> extra = const {},
}) => {
  'id': id,
  'type': 'article-journal',
  'title': title,
  'author': [
    {'family': family, 'given': 'Amal'},
  ],
  'issued': {
    'date-parts': [
      [year, 3, 6],
    ],
  },
  'DOI': doi,
  ...extra,
};

List<ZoteroImportedReference> _references(
  List<Map<String, Object?>> records,
) => [
  for (final (index, item) in zoteroImportCslJson(jsonEncode(records)).indexed)
    ZoteroImportedReference(index: index, item: item),
];

class _Clipboard {
  final texts = <String>[];
  var fails = false;
  Completer<void>? pending;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method != 'Clipboard.setData') return null;
          if (fails) throw PlatformException(code: 'clipboard-unavailable');
          final arguments = call.arguments as Map<Object?, Object?>;
          texts.add(arguments['text']! as String);
          await pending?.future;
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
  }

  List<Map<String, Object?>> get lastRecords {
    final decoded = jsonDecode(texts.last) as List<Object?>;
    return decoded.cast<Map<String, Object?>>();
  }
}

class _Catalog {
  final requests = <ZoteroHttpRequest>[];

  Future<ZoteroHttpResponse> send(ZoteroHttpRequest request) async {
    requests.add(request);
    Object response;
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
              'title': 'Catalog source',
            },
            'csljson': _source(
              id: 'http://zotero.org/users/42/items/CATALOG1',
              title: 'Catalog source',
              extra: {
                'custom': {'origin': 'catalog'},
              },
            ),
          },
        ];
      default:
        throw StateError('Unexpected catalog request: ${request.uri.path}');
    }
    return ZoteroHttpResponse(
      statusCode: 200,
      body: jsonEncode(response),
      headers: const {'Total-Results': '1'},
    );
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: 'After $finder');
}

Future<WordEditorController> _open(
  WidgetTester tester, {
  _Catalog? catalog,
  Size size = const Size(1200, 1000),
  double textScale = 1,
  bool readOnly = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
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
  final session = ZoteroSession()..apiKey = 'import-search-test-key';
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showWordZoteroDialog(
              context,
              controller: controller,
              session: session,
              transport: catalog?.send,
            ),
            child: const Text('Open references'),
          ),
        ),
      ),
    ),
  );
  await _tap(tester, find.text('Open references'));
  if (catalog != null) await _tap(tester, find.text('Connect'));
  return controller;
}

Future<void> _load(
  WidgetTester tester,
  List<Map<String, Object?>> records,
) async {
  await _tap(tester, find.text('Import CSL JSON'));
  final input = find.byKey(const ValueKey('zotero-csl-import'));
  await tester.ensureVisible(input);
  await tester.enterText(input, jsonEncode(records));
  await _tap(tester, find.text('Load references'));
}

Future<void> _search(WidgetTester tester, String query) async {
  final input = find.byKey(const ValueKey('zotero-import-search'));
  await tester.ensureVisible(input);
  await tester.enterText(input, query);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Finder _row(int index, String id) => find.byKey(ValueKey('import:$index:$id'));
Finder _copy() => find.byKey(const ValueKey('zotero-copy-import-selection'));

String _count(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('zotero-import-result-count')))
    .data!;

void _unchanged(WordEditorController controller, int revision) {
  expect(controller.document.paragraphs.single.text, 'Before after');
  expect(controller.zoteroFields, isEmpty);
  expect(controller.contentRevision, revision);
  expect(controller.canUndo, isFalse);
}

void main() {
  test(
    'import search matches every literal term across full creator metadata',
    () {
      final references = _references([
        _source(
          title: 'A <i>literal</i> [study] &amp; القدس',
          doi: '10.1234/ΔΟΚΙΜΉ',
          extra: {
            'author': [
              {'family': 'First'},
              {'family': 'Second'},
              {'given': 'Amal', 'family': 'Hassan'},
            ],
            'editor': [
              {'literal': 'Research Council'},
            ],
            'translator': [
              {'given': 'Léa', 'family': 'Moreau'},
            ],
          },
        ),
        _source(
          id: 'other',
          title: 'Other research',
          family: 'Other',
          year: 2025,
        ),
      ]);
      for (final query in [
        '  AMAL  2024  ',
        '[study] القدس',
        'research council literal',
        'léa δοκιμή',
      ]) {
        expect(filterZoteroImportedReferences(references, query), [
          references.first,
        ], reason: query);
      }
      expect(filterZoteroImportedReferences(references, '.*'), isEmpty);
      expect(
        filterZoteroImportedReferences(references, 'hassan 1900'),
        isEmpty,
      );
      expect(filterZoteroImportedReferences(references, '\n\t '), references);
      expect(references.first.subtitle, 'First, Second, Amal Hassan · 2024');
    },
  );

  test(
    'search preserves original index identities and tolerates optional metadata',
    () {
      final references = _references([
        _source(id: 7, title: 'Same title', family: 'First'),
        _source(
          id: 7,
          title: 'Same title',
          extra: {
            'author': [
              null,
              9,
              {'given': false},
            ],
            'editor': [
              {'literal': 'Editorial Council'},
            ],
            'issued': {'literal': 'Spring 1998'},
            'DOI': {'bad': true},
          },
        ),
      ]);
      final original = jsonEncode(references.last.item.toJson());
      final filtered = filterZoteroImportedReferences(
        references,
        'council 1998',
      );
      expect(filtered.single, same(references.last));
      expect(filtered.single.selectionKey, 'import:1:7');
      expect(references.first.selectionKey, 'import:0:7');
      expect(filtered.single.subtitle, 'Editorial Council · 1998');
      expect(jsonEncode(references.last.item.toJson()), original);
    },
  );

  testWidgets(
    'filtering retains duplicate IDs, hidden selections and review order',
    (tester) async {
      final clipboard = _Clipboard()..install();
      final controller = await _open(tester);
      final revision = controller.contentRevision;
      await _load(tester, [
        _source(id: 'same', title: 'Repeated title', family: 'Alpha'),
        _source(
          id: 'same',
          title: 'Repeated title',
          family: 'Beta',
          extra: {
            'custom': {
              'keep': ['β', 17],
            },
          },
        ),
        _source(id: 'third', title: 'Third source', family: 'Gamma'),
      ]);
      await _search(tester, 'alpha');
      await _tap(tester, _row(0, 'same'));
      await _search(tester, 'beta');
      expect(_row(0, 'same'), findsNothing);
      expect(tester.widget<CheckboxListTile>(_row(1, 'same')).value, isFalse);
      expect(
        _count(tester),
        '1 of 3 shown · 1 selected (1 outside these results)',
      );
      await _tap(tester, _row(1, 'same'));
      await _search(tester, 'nothing matches');
      expect(
        find.byKey(const ValueKey('zotero-import-no-matches')),
        findsOneWidget,
      );
      expect(
        _count(tester),
        '0 of 3 shown · 2 selected (2 outside these results)',
      );
      await _tap(
        tester,
        find.byKey(const ValueKey('zotero-review-import-selection')),
      );
      await _tap(
        tester,
        find.byKey(const ValueKey('zotero-selection-up-import:1:same')),
      );
      await _tap(tester, find.byKey(const ValueKey('zotero-selection-apply')));
      await _tap(tester, _copy());
      expect(clipboard.lastRecords.map((record) => record['author']), [
        [
          {'family': 'Beta', 'given': 'Amal'},
        ],
        [
          {'family': 'Alpha', 'given': 'Amal'},
        ],
      ]);
      expect(clipboard.lastRecords.first['custom'], {
        'keep': ['β', 17],
      });
      await _tap(
        tester,
        find.byKey(const ValueKey('zotero-clear-import-search')),
      );
      expect(_count(tester), '3 of 3 shown · 2 selected');
      for (final index in [0, 1]) {
        expect(
          tester.widget<CheckboxListTile>(_row(index, 'same')).value,
          isTrue,
        );
      }
      await _tap(tester, _row(0, 'same'));
      await _tap(tester, _copy());
      expect(clipboard.lastRecords, hasLength(1));
      expect(clipboard.lastRecords.single['author'], [
        {'family': 'Beta', 'given': 'Amal'},
      ]);
      _unchanged(controller, revision);
    },
  );

  testWidgets(
    'all 500 imported records can be found without losing their keys',
    (tester) async {
      final clipboard = _Clipboard()..install();
      final controller = await _open(tester);
      final revision = controller.contentRevision;
      await _load(tester, [
        for (var index = 0; index < 500; index++)
          _source(
            id: 'record-$index',
            title: 'Source $index',
            family: 'Author $index',
            doi: '10.5678/$index',
          ),
      ]);
      await _search(tester, '10.5678/499 2024');
      expect(_count(tester), '1 of 500 shown · 0 selected');
      await _tap(tester, _row(499, 'record-499'));
      await _search(tester, 'source 0');
      expect(_row(0, 'record-0'), findsOneWidget);
      await _tap(tester, _row(0, 'record-0'));
      await _tap(tester, _copy());
      expect(clipboard.lastRecords.map((record) => record['id']), [
        'record-499',
        'record-0',
      ]);
      _unchanged(controller, revision);
    },
  );

  testWidgets(
    'failed import keeps search and selection, successful reload keeps catalog sources',
    (tester) async {
      final catalog = _Catalog();
      final clipboard = _Clipboard()..install();
      final controller = await _open(tester, catalog: catalog);
      final revision = controller.contentRevision;
      await _tap(
        tester,
        find.widgetWithText(CheckboxListTile, 'Catalog source'),
      );
      final requests = catalog.requests.length;
      await _load(tester, [_source(title: 'First import')]);
      await _search(tester, 'first');
      await _tap(tester, _row(0, 'offline-a'));
      await tester.enterText(
        find.byKey(const ValueKey('zotero-csl-import')),
        '{invalid',
      );
      await _tap(tester, find.text('Load references'));
      expect(
        find.text('Paste a valid CSL JSON object or array.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('zotero-import-search')),
            )
            .controller!
            .text,
        'first',
      );
      expect(
        tester.widget<CheckboxListTile>(_row(0, 'offline-a')).value,
        isTrue,
      );
      await _load(tester, [
        _source(id: 'replacement', title: 'Replacement source'),
      ]);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('zotero-import-search')),
            )
            .controller!
            .text,
        isEmpty,
      );
      expect(
        _count(tester),
        '1 of 1 shown · 1 selected (1 outside these results)',
      );
      expect(
        tester.widget<CheckboxListTile>(_row(0, 'replacement')).value,
        isFalse,
      );
      await _tap(tester, _copy());
      expect(clipboard.lastRecords.map((record) => record['title']), [
        'Catalog source',
      ]);
      expect(catalog.requests.length, requests);
      _unchanged(controller, revision);
    },
  );

  testWidgets(
    'stored copy works in Library for mixed offline and linked sources without transport',
    (tester) async {
      final clipboard = _Clipboard()..install();
      final controller = await _open(tester, readOnly: true);
      final revision = controller.contentRevision;
      await _load(tester, [
        _source(id: 'offline', title: 'Offline paper'),
        _source(
          id: 'user-export',
          title: 'Personal paper',
          extra: {'uri': 'https://zotero.org/users/42/items/USER0001'},
        ),
        _source(
          id: 'group-export',
          title: 'Group paper',
          extra: {'uri': 'http://zotero.org/groups/9/items/GROUP001'},
        ),
      ]);
      for (final title in ['Offline paper', 'Personal paper', 'Group paper']) {
        await _search(tester, title);
        await _tap(tester, find.widgetWithText(CheckboxListTile, title));
      }
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Insert 3 selected source(s)'),
            )
            .onPressed,
        isNull,
      );
      await _tap(tester, find.text('Library'));
      await _tap(tester, find.text('Export selected ▾'));
      await _tap(tester, find.text('Copy stored CSL JSON'));
      expect(clipboard.lastRecords.map((record) => record['title']), [
        'Offline paper',
        'Personal paper',
        'Group paper',
      ]);
      final importedAgain = zoteroImportCslJson(clipboard.texts.single);
      expect(importedAgain.first.uris, isEmpty);
      expect(
        importedAgain[1].uris,
        contains('https://zotero.org/users/42/items/USER0001'),
      );
      expect(
        importedAgain[2].uris,
        contains('http://zotero.org/groups/9/items/GROUP001'),
      );
      expect(
        find.text('Stored reference metadata copied to the clipboard.'),
        findsOneWidget,
      );
      _unchanged(controller, revision);
    },
  );

  testWidgets(
    'clipboard failure preserves selected metadata and permits retry',
    (tester) async {
      final clipboard = _Clipboard()..install();
      final controller = await _open(tester);
      final revision = controller.contentRevision;
      await _load(tester, [_source()]);
      await _tap(tester, _row(0, 'offline-a'));
      clipboard.fails = true;
      await _tap(tester, _copy());
      expect(
        find.text('Could not copy stored reference metadata to the clipboard.'),
        findsOneWidget,
      );
      expect(clipboard.texts, isEmpty);
      expect(
        tester.widget<CheckboxListTile>(_row(0, 'offline-a')).value,
        isTrue,
      );
      clipboard.fails = false;
      await _tap(tester, _copy());
      expect(clipboard.lastRecords.single['title'], 'Imported research');
      _unchanged(controller, revision);
    },
  );

  testWidgets(
    'closing while clipboard is pending does not update a disposed dialog',
    (tester) async {
      final clipboard = _Clipboard()..install();
      final controller = await _open(tester);
      final revision = controller.contentRevision;
      await _load(tester, [_source()]);
      await _tap(tester, _row(0, 'offline-a'));
      clipboard.pending = Completer<void>();
      await tester.ensureVisible(_copy());
      await tester.tap(_copy());
      await tester.pump();
      await tester.tap(find.byTooltip('Close Zotero'));
      await tester.pump(const Duration(milliseconds: 350));
      clipboard.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Zotero references'), findsNothing);
      expect(tester.takeException(), isNull);
      _unchanged(controller, revision);
    },
  );

  for (final (size, scale) in const [
    (Size(320, 640), 1.0),
    (Size(320, 480), 2.0),
  ]) {
    testWidgets(
      'import search and copy controls fit ${size.width}×${size.height} at $scale× text',
      (tester) async {
        final clipboard = _Clipboard()..install();
        final controller = await _open(tester, size: size, textScale: scale);
        final revision = controller.contentRevision;
        await _load(tester, [
          _source(
            title:
                'A long source title with القدس and several identifying words',
          ),
          _source(id: 'second', title: 'Second source'),
        ]);
        await _search(tester, 'القدس 2024');
        await _tap(tester, _row(0, 'offline-a'));
        await _tap(tester, _copy());
        expect(clipboard.lastRecords, hasLength(1));
        await _search(tester, 'not present');
        await tester.ensureVisible(
          find.byKey(const ValueKey('zotero-import-no-matches')),
        );
        await tester.pumpAndSettle();
        await _tap(
          tester,
          find.byKey(const ValueKey('zotero-clear-import-search')),
        );
        await tester.ensureVisible(
          find.widgetWithText(FilledButton, 'Insert 1 selected source(s)'),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        _unchanged(controller, revision);
      },
    );
  }
}
