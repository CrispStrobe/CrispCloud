import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_editor/src/embed/word_zotero_library.dart';

const _abstract =
    'For A < B and C > D, keep both comparisons.\n'
    '<script>alert("inert")</script> remains literal reference data.\n'
    'القدس & 東京 — second paragraph.';
const _url = 'javascript:alert("reference data only")';

class _DetailsCatalog {
  _DetailsCatalog({this.local = false, this.tags = const ['Research & القدس']});

  final bool local;
  final List<String> tags;
  final requests = <ZoteroHttpRequest>[];

  List<ZoteroHttpRequest> get itemRequests => requests
      .where(
        (request) =>
            request.uri.path.endsWith('/items/top') ||
            request.uri.path.endsWith('/items'),
      )
      .toList();

  String sourceId(int page) => local
      ? 'http://zotero.org/users/local/LOCALKEY/items/SOURCE0${page + 1}'
      : 'http://zotero.org/users/42/items/SOURCE0${page + 1}';

  ZoteroHttpResponse json(Object value, {bool paged = false}) =>
      ZoteroHttpResponse(
        statusCode: 200,
        body: jsonEncode(value),
        headers: {
          if (local) 'Zotero-Server-ID': 'details-desktop',
          if (paged) 'Total-Results': '101',
        },
      );

  Future<ZoteroHttpResponse> send(ZoteroHttpRequest request) async {
    requests.add(request);
    final path = request.uri.path;
    expect(request.method, 'GET');
    expect(request.body, isNull);
    expect(request.uri.host, local ? 'localhost' : 'api.zotero.org');
    expect(
      request.headers['Zotero-API-Key'],
      local ? isNull : 'details-test-key',
    );
    expect(request.followRedirects, isFalse);
    if (path == '/api/') {
      return ZoteroHttpResponse(
        statusCode: 200,
        body: 'Local API',
        headers: const {
          'Zotero-API-Version': '3',
          'Zotero-Server-ID': 'details-desktop',
        },
      );
    }
    if (path == '/keys/current') {
      return json({
        'userID': 42,
        'username': 'Reader',
        'access': {
          'user': {'library': true},
        },
      });
    }
    if (path.endsWith('/groups')) return json(<Object>[]);
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
      final page = int.parse(request.uri.queryParameters['start']!) ~/ 50;
      final key = 'SOURCE0${page + 1}';
      final title = ['First source', 'Later source', 'Final source'][page];
      return json([
        {
          'key': key,
          'library': {'type': 'user', 'id': local ? 0 : 42},
          'data': {
            'key': key,
            'itemType': 'journalArticle',
            'title': title,
            'abstractNote': _abstract,
            'publicationTitle': 'Journal of <i>Studies</i>',
            'publisher': 'Research Press',
            'date': '2026-11-18',
            'DOI': '10.1234/δοκιμή',
            'url': _url,
            'creators': [
              {
                'firstName': 'Amal',
                'lastName': 'Hassan',
                'creatorType': 'author',
              },
              {'name': 'Research Council', 'creatorType': 'editor'},
            ],
            'tags': [
              for (final tag in tags) {'tag': tag},
            ],
          },
          'csljson': {
            'id': sourceId(page),
            'type': 'article-journal',
            'title': title,
            'author': [
              {'family': 'Author ${page + 1}'},
            ],
            'issued': {
              'date-parts': [
                [2026],
              ],
            },
            'custom': {'preserve': page + 1},
          },
        },
      ], paged: true);
    }
    throw StateError('Unexpected details catalog request: $path');
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

void _size(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<WordEditorController> _open(
  WidgetTester tester, {
  _DetailsCatalog? catalog,
  ZoteroSession? session,
  Size size = const Size(1280, 1100),
}) async {
  _size(tester, size);
  final controller = WordEditorController(
    document: WmlDocument.empty(text: 'Before after'),
  );
  controller.caret.logicalIndex = 7;
  controller.caret.collapseSelection();
  addTearDown(controller.dispose);
  final connection = (session ?? ZoteroSession())
    ..useLocal = catalog?.local ?? false
    ..apiKey = 'details-test-key';
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showWordZoteroDialog(
              context,
              controller: controller,
              session: connection,
              transport: catalog == null || catalog.local ? null : catalog.send,
              localTransport: catalog?.local == true ? catalog!.send : null,
            ),
            child: const Text('Open references'),
          ),
        ),
      ),
    ),
  );
  await _tap(tester, find.text('Open references'));
  if (catalog != null) {
    await _tap(
      tester,
      find.text(catalog.local ? 'Connect desktop' : 'Connect'),
    );
  }
  return controller;
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
Finder _tagDraft() => find.byKey(const ValueKey('zotero-tag-input'));
Finder _details() => find.byKey(const ValueKey('zotero-item-details-dialog'));
Finder _review() =>
    find.byKey(const ValueKey('zotero-selected-references-dialog'));
Finder _selectable(String text) => find.byWidgetPredicate(
  (widget) => widget is SelectableText && widget.data == text,
);

Future<void> _openDetails(
  WidgetTester tester,
  _DetailsCatalog catalog,
  int page,
) => _tap(
  tester,
  find.byKey(ValueKey('zotero-details-${catalog.sourceId(page)}')),
);

Future<void> _openReview(WidgetTester tester, {bool imported = false}) => _tap(
  tester,
  find.byKey(
    ValueKey(
      imported
          ? 'zotero-review-import-selection'
          : 'zotero-review-library-selection',
    ),
  ),
);

Future<void> _listTap(
  WidgetTester tester,
  Finder finder,
  String listKey,
) async {
  final list = find.byKey(ValueKey(listKey));
  await tester.ensureVisible(list);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    finder,
    120,
    scrollable: find.descendant(of: list, matching: find.byType(Scrollable)),
  );
  await _tap(tester, finder);
}

Future<void> _reviewAction(WidgetTester tester, String action, String key) =>
    _listTap(
      tester,
      find.byKey(ValueKey('zotero-selection-$action-$key')),
      'zotero-selected-reference-list',
    );

List<String> _captureClipboard({bool fail = false}) {
  final copied = <String>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      if (fail) throw PlatformException(code: 'unavailable');
      final arguments = call.arguments as Map<Object?, Object?>;
      copied.add(arguments['text']! as String);
    }
    if (call.method == 'Clipboard.hasStrings') {
      return {'value': copied.isNotEmpty};
    }
    if (call.method == 'Clipboard.getData') return {'text': copied.lastOrNull};
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return copied;
}

Future<void> _insert(
  WidgetTester tester, {
  bool imported = false,
  int count = 2,
}) async {
  await _tap(
    tester,
    find.text(
      imported ? 'Insert $count selected source(s)' : 'Insert citation',
    ),
  );
  expect(find.text('Insert Zotero citation'), findsOneWidget);
  await _tap(
    tester,
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, 'Insert citation'),
    ),
  );
}

void _unchanged(WordEditorController controller, int revision) {
  expect(controller.document.paragraphs.single.text, 'Before after');
  expect(controller.zoteroFields, isEmpty);
  expect(controller.contentRevision, revision);
  expect(controller.canUndo, isFalse);
}

void main() {
  testWidgets(
    'reference details inspect loaded metadata without selecting or fetching',
    (tester) async {
      final catalog = _DetailsCatalog();
      final copied = _captureClipboard();
      final controller = await _open(tester, catalog: catalog);
      final revision = controller.contentRevision;
      final requests = catalog.requests.length;
      await _openDetails(tester, catalog, 0);
      expect(_details(), findsOneWidget);
      for (final value in [
        'First source',
        'Amal Hassan\nResearch Council (editor)',
        'journalArticle',
        'Journal of Studies',
        '2026-11-18',
        'Research Press',
        '10.1234/δοκιμή',
        _url,
        catalog.sourceId(0),
        _abstract,
      ]) {
        expect(_selectable(value), findsOneWidget);
      }
      await _tap(tester, _selectable(_url));
      await _tap(
        tester,
        find.byKey(const ValueKey('zotero-copy-item-details')),
      );
      expect(copied, hasLength(1));
      expect(copied.single, contains('Abstract:\n$_abstract'));
      expect(copied.single, contains('URL: $_url'));
      expect(copied.single, contains('Tags:\n• Research & القدس'));
      expect(copied.single, contains('Publication: Journal of Studies'));
      expect(find.text('Reference details copied.'), findsOneWidget);
      expect(catalog.requests.length, requests);
      _unchanged(controller, revision);
      await _tap(tester, find.widgetWithText(TextButton, 'Close'));
      expect(find.text('0 selected'), findsOneWidget);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'First source'),
            )
            .value,
        isFalse,
      );
    },
  );

  testWidgets(
    'clipboard failure stays in the details dialog without changing a source',
    (tester) async {
      final catalog = _DetailsCatalog();
      _captureClipboard(fail: true);
      final controller = await _open(tester, catalog: catalog);
      final revision = controller.contentRevision;
      final requests = catalog.requests.length;
      await _openDetails(tester, catalog, 0);
      await _tap(
        tester,
        find.byKey(const ValueKey('zotero-copy-item-details')),
      );
      expect(
        find.text('Could not copy. Select the text to copy it manually.'),
        findsOneWidget,
      );
      expect(_details(), findsOneWidget);
      expect(catalog.requests.length, requests);
      _unchanged(controller, revision);
    },
  );

  for (final scope in ['library', 'collection', 'saved search']) {
    testWidgets(
      'details tag filters the submitted $scope query and preserves drafts',
      (tester) async {
        final catalog = _DetailsCatalog(
          local: scope == 'saved search',
          tags: const ['-Research & القدس'],
        );
        final controller = await _open(tester, catalog: catalog);
        final revision = controller.contentRevision;
        if (scope == 'collection') {
          await _tap(
            tester,
            find.byWidgetPredicate(
              (widget) =>
                  widget is DropdownButtonFormField<String> &&
                  widget.decoration.labelText == 'Collection',
            ),
          );
          await _tap(tester, find.text('Research collection').last);
        }
        if (scope == 'saved search') {
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
        }
        await tester.enterText(_query(), 'submitted phrase');
        await _tap(tester, find.byTooltip('Search'));
        await _tap(
          tester,
          find.widgetWithText(CheckboxListTile, 'First source'),
        );
        await _tap(tester, find.byTooltip('Next page'));
        await _tap(tester, find.byTooltip('Search options'));
        await tester.enterText(_query(), 'unfinished query');
        await tester.enterText(_tagDraft(), 'unfinished tag');
        final requests = catalog.requests.length;
        await _openDetails(tester, catalog, 1);
        await _listTap(
          tester,
          find.byKey(const ValueKey('zotero-item-tag-0')),
          'zotero-item-tags',
        );
        expect(_details(), findsNothing);
        expect(catalog.requests.length, requests + 1);
        final request = catalog.itemRequests.last;
        expect(request.uri.queryParameters['q'], 'submitted phrase');
        expect(request.uri.queryParameters['start'], '0');
        expect(request.uri.queryParametersAll['tag'], [r'\-Research & القدس']);
        expect(request.uri.path, switch (scope) {
          'collection' => '/users/42/collections/COLL0001/items/top',
          'saved search' => '/api/users/0/searches/SEARCH01/items',
          _ => '/users/42/items/top',
        });
        expect(
          tester.widget<TextField>(_query()).controller!.text,
          'unfinished query',
        );
        expect(
          tester.widget<TextField>(_tagDraft()).controller!.text,
          'unfinished tag',
        );
        expect(
          find.byKey(const ValueKey('zotero-tag--Research & القدس')),
          findsOneWidget,
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
        _unchanged(controller, revision);
      },
    );
  }

  testWidgets(
    'unrepresentable and surrounding-space tags stay visible but cannot filter',
    (tester) async {
      final tags = [
        'one || two',
        r'\-literal',
        ' padded ',
        'x' * 257,
        'two\tparts',
      ];
      final catalog = _DetailsCatalog(tags: tags);
      final controller = await _open(tester, catalog: catalog);
      final revision = controller.contentRevision;
      final requests = catalog.requests.length;
      await _openDetails(tester, catalog, 0);
      for (var index = 0; index < tags.length; index++) {
        final finder = find.byKey(ValueKey('zotero-item-tag-$index'));
        await _listTap(tester, finder, 'zotero-item-tags');
        expect(tester.widget<TextButton>(finder).onPressed, isNull);
        expect(_details(), findsOneWidget);
      }
      expect(catalog.requests.length, requests);
      _unchanged(controller, revision);
    },
  );

  testWidgets(
    'an already active details tag is disabled without another request',
    (tester) async {
      final catalog = _DetailsCatalog();
      await _open(tester, catalog: catalog);
      await _openDetails(tester, catalog, 0);
      await _listTap(
        tester,
        find.byKey(const ValueKey('zotero-item-tag-0')),
        'zotero-item-tags',
      );
      final requests = catalog.requests.length;
      await _openDetails(tester, catalog, 0);
      final tag = find.byKey(const ValueKey('zotero-item-tag-0'));
      await _listTap(tester, tag, 'zotero-item-tags');
      expect(tester.widget<TextButton>(tag).onPressed, isNull);
      expect(catalog.requests.length, requests);
      expect(_details(), findsOneWidget);
    },
  );

  testWidgets(
    'a details tag cannot filter a library changed while the dialog was open',
    (tester) async {
      final catalog = _DetailsCatalog();
      final session = ZoteroSession();
      final controller = await _open(
        tester,
        catalog: catalog,
        session: session,
      );
      final revision = controller.contentRevision;
      final requests = catalog.requests.length;
      await _tap(tester, find.byTooltip('Search options'));
      await _openDetails(tester, catalog, 0);
      session.library = ZoteroLibrary.user(77);
      await _listTap(
        tester,
        find.byKey(const ValueKey('zotero-item-tag-0')),
        'zotero-item-tags',
      );
      expect(_details(), findsNothing);
      expect(catalog.requests.length, requests);
      expect(
        find.byKey(const ValueKey('zotero-tag-Research & القدس')),
        findsNothing,
      );
      _unchanged(controller, revision);
    },
  );

  testWidgets(
    'selection review stages cross-page changes and inserts the applied order in one undo',
    (tester) async {
      final catalog = _DetailsCatalog();
      final controller = await _open(tester, catalog: catalog);
      final revision = controller.contentRevision;
      for (final title in ['First source', 'Later source', 'Final source']) {
        await _tap(tester, find.widgetWithText(CheckboxListTile, title));
        if (title != 'Final source') {
          await _tap(tester, find.byTooltip('Next page'));
        }
      }
      final requests = catalog.requests.length;
      await _openReview(tester);
      await _reviewAction(tester, 'down', catalog.sourceId(0));
      await _reviewAction(tester, 'remove', catalog.sourceId(2));
      expect(find.text('2 selected').hitTestable(), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('zotero-selection-cancel')));
      expect(find.text('3 selected'), findsOneWidget);
      await _openReview(tester);
      expect(find.text('1. First source'), findsOneWidget);
      await _reviewAction(tester, 'up', catalog.sourceId(2));
      await _reviewAction(tester, 'up', catalog.sourceId(2));
      await _reviewAction(tester, 'remove', catalog.sourceId(1));
      await _tap(tester, find.byKey(const ValueKey('zotero-selection-apply')));
      expect(find.text('2 selected'), findsOneWidget);
      expect(catalog.requests.length, requests);
      _unchanged(controller, revision);
      await _tap(tester, find.byTooltip('Previous page'));
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'Later source'),
            )
            .value,
        isFalse,
      );
      await _insert(tester);
      final items = controller.zoteroFields.single.citation!.items;
      expect(items.map((item) => item.itemData!['title']), [
        'Final source',
        'First source',
      ]);
      expect(items.map((item) => item.uris.single), [
        catalog.sourceId(2),
        catalog.sourceId(0),
      ]);
      expect(items.first.itemData!['custom'], {'preserve': 3});
      expect(controller.contentRevision, greaterThan(revision));
      expect(controller.canUndo, isTrue);
      controller.undo();
      expect(controller.zoteroFields, isEmpty);
      expect(controller.document.paragraphs.single.text, 'Before after');
      expect(controller.canUndo, isFalse);
      expect(controller.canRedo, isTrue);
      controller.redo();
      expect(
        controller.zoteroFields.single.citation!.items.map(
          (item) => item.uris.single,
        ),
        [catalog.sourceId(2), catalog.sourceId(0)],
      );
    },
  );

  testWidgets('barrier dismissal discards staged removal and reordering', (
    tester,
  ) async {
    final catalog = _DetailsCatalog();
    final controller = await _open(tester, catalog: catalog);
    final revision = controller.contentRevision;
    await _tap(tester, find.widgetWithText(CheckboxListTile, 'First source'));
    await _tap(tester, find.byTooltip('Next page'));
    await _tap(tester, find.widgetWithText(CheckboxListTile, 'Later source'));
    final requests = catalog.requests.length;
    await _openReview(tester);
    await _reviewAction(tester, 'up', catalog.sourceId(1));
    await _reviewAction(tester, 'remove', catalog.sourceId(0));
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(_review(), findsNothing);
    expect(find.text('2 selected'), findsOneWidget);
    await _openReview(tester);
    expect(find.text('1. First source'), findsOneWidget);
    expect(find.text('2. Later source'), findsOneWidget);
    expect(catalog.requests.length, requests);
    _unchanged(controller, revision);
  });

  testWidgets('applying an empty review disables selection actions', (
    tester,
  ) async {
    final catalog = _DetailsCatalog();
    final controller = await _open(tester, catalog: catalog);
    final revision = controller.contentRevision;
    await _tap(tester, find.widgetWithText(CheckboxListTile, 'First source'));
    await _openReview(tester);
    await _reviewAction(tester, 'remove', catalog.sourceId(0));
    expect(find.text('No references selected.'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('zotero-selection-apply')));
    expect(find.text('0 selected'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('zotero-review-library-selection')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<CheckboxListTile>(
            find.widgetWithText(CheckboxListTile, 'First source'),
          )
          .value,
      isFalse,
    );
    _unchanged(controller, revision);
  });

  testWidgets(
    'offline import review preserves original checkbox keys after reorder',
    (tester) async {
      final controller = await _open(tester);
      final revision = controller.contentRevision;
      await _tap(tester, find.text('Import CSL JSON'));
      await tester.enterText(
        find.byKey(const ValueKey('zotero-csl-import')),
        jsonEncode([
          for (var index = 1; index <= 2; index++)
            {
              'id': 'offline-$index',
              'type': 'book',
              'title': 'Offline source $index',
              'author': [
                {'family': 'Offline $index'},
              ],
              'custom': {'source': index},
            },
        ]),
      );
      await _tap(tester, find.text('Load references'));
      for (final index in [1, 2]) {
        await _tap(
          tester,
          find.widgetWithText(CheckboxListTile, 'Offline source $index'),
        );
      }
      await _openReview(tester, imported: true);
      await _reviewAction(tester, 'up', 'import:1:offline-2');
      await _tap(tester, find.byKey(const ValueKey('zotero-selection-apply')));
      for (final index in [1, 2]) {
        expect(
          tester
              .widget<CheckboxListTile>(
                find.widgetWithText(CheckboxListTile, 'Offline source $index'),
              )
              .value,
          isTrue,
        );
      }
      _unchanged(controller, revision);
      await _tap(
        tester,
        find.widgetWithText(CheckboxListTile, 'Offline source 1'),
      );
      expect(find.text('Insert 1 selected source(s)'), findsOneWidget);
      await _insert(tester, imported: true, count: 1);
      final item = controller.zoteroFields.single.citation!.items.single;
      expect(item.id, 'offline-2');
      expect(item.uris, isEmpty);
      expect(item.itemData!['custom'], {'source': 2});
    },
  );

  testWidgets(
    'mixed catalog and imported selections keep both key schemes after apply',
    (tester) async {
      final catalog = _DetailsCatalog();
      final controller = await _open(tester, catalog: catalog);
      final revision = controller.contentRevision;
      await _tap(tester, find.widgetWithText(CheckboxListTile, 'First source'));
      await _tap(tester, find.text('Import CSL JSON'));
      await tester.enterText(
        find.byKey(const ValueKey('zotero-csl-import')),
        jsonEncode([
          for (var index = 1; index <= 2; index++)
            {
              'id': 'mixed-offline-$index',
              'type': 'book',
              'title': 'Mixed offline source $index',
              'custom': {'source': index},
            },
        ]),
      );
      await _tap(tester, find.text('Load references'));
      for (final index in [1, 2]) {
        await _tap(
          tester,
          find.widgetWithText(CheckboxListTile, 'Mixed offline source $index'),
        );
      }
      final requests = catalog.requests.length;
      await _openReview(tester, imported: true);
      await _reviewAction(tester, 'up', 'import:1:mixed-offline-2');
      await _reviewAction(tester, 'up', 'import:1:mixed-offline-2');
      await _reviewAction(tester, 'remove', 'import:0:mixed-offline-1');
      await _tap(tester, find.byKey(const ValueKey('zotero-selection-apply')));
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'Mixed offline source 1'),
            )
            .value,
        isFalse,
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'Mixed offline source 2'),
            )
            .value,
        isTrue,
      );
      await _tap(tester, find.text('Library'));
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'First source'),
            )
            .value,
        isTrue,
      );
      expect(catalog.requests.length, requests);
      _unchanged(controller, revision);
      await _insert(tester);
      final items = controller.zoteroFields.single.citation!.items;
      expect(items.map((item) => item.itemData!['title']), [
        'Mixed offline source 2',
        'First source',
      ]);
      expect(items.first.uris, isEmpty);
      expect(items.first.itemData!['custom'], {'source': 2});
      expect(items.last.uris, [catalog.sourceId(0)]);
    },
  );

  for (final width in [320.0, 360.0, 420.0]) {
    testWidgets(
      'many detail tags and copy feedback fit a $width-pixel window',
      (tester) async {
        final tags = [
          'Long label ${'x' * 200}',
          for (var index = 1; index < 25; index++) 'Topic $index',
        ];
        final catalog = _DetailsCatalog(tags: tags);
        final copied = _captureClipboard();
        final controller = await _open(
          tester,
          catalog: catalog,
          size: Size(width, 760),
        );
        final revision = controller.contentRevision;
        await _openDetails(tester, catalog, 0);
        final last = find.byKey(const ValueKey('zotero-item-tag-24'));
        final list = find.byKey(const ValueKey('zotero-item-tags'));
        await tester.ensureVisible(list);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          last,
          120,
          scrollable: find.descendant(
            of: list,
            matching: find.byType(Scrollable),
          ),
        );
        expect(tester.widget<TextButton>(last).onPressed, isNotNull);
        await _tap(
          tester,
          find.byKey(const ValueKey('zotero-copy-item-details')),
        );
        expect(copied.single, contains('• ${tags.first}'));
        expect(copied.single, contains('• Topic 24'));
        expect(find.text('Reference details copied.'), findsOneWidget);
        expect(tester.takeException(), isNull);
        _unchanged(controller, revision);
      },
    );
  }

  for (final layout in [
    (width: 320.0, height: 760.0, scale: 1.0),
    (width: 360.0, height: 760.0, scale: 1.0),
    (width: 420.0, height: 760.0, scale: 1.0),
    (width: 320.0, height: 480.0, scale: 2.0),
    (width: 320.0, height: 360.0, scale: 1.0),
  ]) {
    testWidgets(
      'twenty-source review scrolls at ${layout.width}x${layout.height} scale ${layout.scale}',
      (tester) async {
        _size(tester, Size(layout.width, layout.height));
        final selection = <String, ZoteroCitationItem>{
          for (var index = 0; index < 20; index++)
            'source-$index': ZoteroCitationItem.fromJson({
              'id': 'offline-$index',
              'uris': <String>[],
              'itemData': {
                'id': 'offline-$index',
                'type': 'book',
                'title': 'Source $index ${'long title ' * 15}',
                'author': [
                  {'family': 'Researcher $index'},
                ],
              },
              'locator': '$index',
              'prefix': 'see',
              'custom': {'preserve': index},
            }),
        };
        List<String>? result;
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(layout.scale)),
              child: child!,
            ),
            home: Scaffold(
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
          ),
        );
        await _tap(tester, find.text('Review'));
        final firstUp = find.byKey(
          const ValueKey('zotero-selection-up-source-0'),
        );
        await _listTap(tester, firstUp, 'zotero-selected-reference-list');
        expect(tester.widget<IconButton>(firstUp).onPressed, isNull);
        await _reviewAction(tester, 'down', 'source-0');
        final lastDown = find.byKey(
          const ValueKey('zotero-selection-down-source-19'),
        );
        await _listTap(tester, lastDown, 'zotero-selected-reference-list');
        expect(tester.widget<IconButton>(lastDown).onPressed, isNull);
        await _reviewAction(tester, 'remove', 'source-19');
        await _tap(
          tester,
          find.byKey(const ValueKey('zotero-selection-apply')),
        );
        expect(result, [
          'source-1',
          'source-0',
          for (var index = 2; index < 19; index++) 'source-$index',
        ]);
        expect(selection, hasLength(20));
        expect(selection['source-0']!.locator, '0');
        expect(selection['source-0']!.toJson()['custom'], {'preserve': 0});
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('details copy feedback fits a short window with doubled text', (
    tester,
  ) async {
    _size(tester, const Size(320, 480));
    final copied = _captureClipboard();
    final item = ZoteroItem(
      library: ZoteroLibrary.user(42),
      key: 'SOURCE01',
      title: 'A long reference title ${'continued ' * 12}',
      itemType: 'journalArticle',
      abstractNote: _abstract,
      publicationTitle: 'Journal of Studies',
      tags: [
        'Literal <tag> & research',
        for (var index = 1; index < 25; index++) 'Topic $index',
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) =>
                    ZoteroItemDetailsDialog(item: item, activeTags: const []),
              ),
              child: const Text('Inspect'),
            ),
          ),
        ),
      ),
    );
    await _tap(tester, find.text('Inspect'));
    await _tap(tester, find.byKey(const ValueKey('zotero-copy-item-details')));
    expect(copied, hasLength(1));
    expect(copied.single, contains('Abstract:\n$_abstract'));
    expect(copied.single, contains('• Literal <tag> & research'));
    expect(copied.single, contains('• Topic 24'));
    expect(find.text('Reference details copied.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _tap(tester, find.widgetWithText(TextButton, 'Close'));
    expect(_details(), findsNothing);
  });
}
