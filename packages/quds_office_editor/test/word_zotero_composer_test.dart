import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/src/embed/word_zotero_composer.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

const _firstUri = 'http://zotero.org/users/42/items/FIRST001';
const _secondUri = 'http://zotero.org/groups/52/items/SECOND02';
const _thirdUri = 'http://zotero.org/users/local/LOCALKEY/items/THIRD003';

ZoteroCitationItem _source(
  String title, {
  Object id = 'same-id',
  String family = 'Hassan',
  String doi = '',
  List<String> uris = const [],
  Map<String, dynamic> options = const {},
}) => ZoteroCitationItem.fromJson({
  'id': id,
  'uris': uris,
  'itemData': {
    'id': id,
    'type': 'book',
    'title': title,
    'author': [
      {'family': family, 'given': 'Amal'},
    ],
    'issued': {
      'date-parts': [
        [2024],
      ],
    },
    'DOI': doi,
    'customData': {'retained': title},
  },
  'unknownSourceProperty': {'keep': title},
  ...options,
});

ZoteroCitation _existing(
  List<ZoteroCitationItem> items, {
  bool basic = false,
}) => ZoteroCitation.fromJson({
  'citationID': 'existing-citation',
  'citationItems': [for (final item in items) item.toJson()],
  'unknownCitationProperty': {'retain': true},
  'properties': {
    'plainCitation': 'Original custom text',
    'formattedCitation': r'{\rtf1 Original custom text}',
    'qudsFormat': basic ? 'basic-author-year' : 'native-zotero',
    'noteIndex': 4,
    'unknownProperty': 'retain',
  },
});

class _Result {
  ZoteroCitation? citation;
  bool returned = false;
}

Finder _key(String value) => find.byKey(ValueKey(value));

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: 'After $finder');
}

Future<void> _enter(WidgetTester tester, String key, String value) async {
  await tester.ensureVisible(_key(key));
  await tester.pumpAndSettle();
  await tester.enterText(_key(key), value);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

String _preview(WidgetTester tester) =>
    tester.widget<TextField>(_key('zotero-citation-preview')).controller!.text;

bool _canApply(WidgetTester tester) =>
    tester.widget<FilledButton>(_key('zotero-composer-apply')).onPressed !=
    null;

Future<_Result> _open(
  WidgetTester tester, {
  required List<ZoteroCitationItem> items,
  List<ZoteroCitationItem> available = const [],
  ZoteroCitation? existing,
  String? existingCache,
  Future<String> Function(ZoteroCitationItem)? preview,
  Future<ZoteroPage<ZoteroCitationItem>> Function(String, int)? searchZotero,
  Size size = const Size(1200, 1000),
  double scale = 1,
  TextDirection direction = TextDirection.ltr,
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
          builder: (context) => TextButton(
            onPressed: () async {
              result.citation = await showDialog<ZoteroCitation>(
                context: context,
                builder: (_) => ZoteroCitationComposer(
                  items: List.unmodifiable(items),
                  availableSources: List.unmodifiable(available),
                  existing: existing,
                  existingCache: existingCache,
                  loadStyleSnapshot: preview,
                  searchZoteroSources: searchZotero,
                ),
              );
              result.returned = true;
            },
            child: const Text('Open composer'),
          ),
        ),
      ),
    ),
  );
  await _tap(tester, find.text('Open composer'));
  return result;
}

Future<void> _add(WidgetTester tester, List<int> indexes) async {
  await _tap(tester, _key('zotero-composer-add-sources'));
  for (final index in indexes) {
    await _tap(tester, _key('zotero-composer-candidate-$index'));
  }
  await _tap(tester, _key('zotero-composer-source-add'));
}

void main() {
  testWidgets(
    'connected chooser supports keyboard search and selection beyond visible results',
    (tester) async {
      final calls = <(String, int)>[];
      final remote = List.generate(
        25,
        (index) => _source('Remote source $index', id: 'remote-$index'),
      );
      final result = await _open(
        tester,
        items: [_source('Current')],
        searchZotero: (query, start) async {
          calls.add((query, start));
          return ZoteroPage<ZoteroCitationItem>(
            items: remote,
            start: start,
            limit: 25,
          );
        },
      );
      await _tap(tester, _key('zotero-composer-search-zotero'));
      final query = tester.widget<TextField>(
        _key('zotero-connected-source-query'),
      );
      expect(query.focusNode!.hasFocus, isTrue);
      await _enter(tester, 'zotero-connected-source-query', 'Remote');
      expect(calls, isEmpty);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(calls, [('Remote', 0)]);
      expect(query.focusNode!.hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(_key('zotero-connected-source-0'))
            .focusNode!
            .hasFocus,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(query.focusNode!.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(_key('zotero-connected-source-0'))
            .value,
        isTrue,
      );

      for (var index = 1; index < remote.length; index++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<CheckboxListTile>(_key('zotero-connected-source-$index'))
              .focusNode!
              .hasFocus,
          isTrue,
          reason: 'Arrow navigation reaches result $index across lazy rows',
        );
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(_key('zotero-connected-source-24'))
            .value,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(_key('zotero-connected-source-24'))
            .focusNode!
            .hasFocus,
        isTrue,
        reason: 'Down at the last result keeps focus inside the result list',
      );
      for (var index = remote.length - 2; index >= 0; index--) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<CheckboxListTile>(_key('zotero-connected-source-$index'))
              .focusNode!
              .hasFocus,
          isTrue,
          reason: 'Up reaches result $index after its lazy row is rebuilt',
        );
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(query.focusNode!.hasFocus, isTrue);
      expect(calls, [('Remote', 0)]);
      await _tap(tester, _key('zotero-connected-source-add'));
      await _tap(tester, _key('zotero-composer-apply'));
      expect(result.citation!.items.map((item) => item.itemData!['title']), [
        'Current',
        'Remote source 0',
        'Remote source 24',
      ]);
    },
  );

  testWidgets(
    'connected Zotero search is explicit, paged and staged with fresh options',
    (tester) async {
      final calls = <(String, int)>[];
      final first = _source(
        'First remote',
        uris: [_firstUri],
        options: {'locator': '77', 'prefix': 'old'},
      );
      final second = _source('Second remote', uris: [_secondUri]);
      final result = await _open(
        tester,
        items: [_source('Current')],
        searchZotero: (query, start) async {
          calls.add((query, start));
          return ZoteroPage<ZoteroCitationItem>(
            items: start == 0 ? [first] : [second],
            start: start,
            limit: 25,
            nextStart: start == 0 ? 25 : null,
          );
        },
      );
      await _tap(tester, _key('zotero-composer-search-zotero'));
      await _enter(tester, 'zotero-connected-source-query', 'Hassan');
      expect(calls, isEmpty, reason: 'Typing must not contact the library');
      await _tap(tester, _key('zotero-connected-source-search'));
      expect(calls, [('Hassan', 0)]);
      await _tap(tester, _key('zotero-connected-source-0'));
      await _tap(tester, _key('zotero-connected-source-more'));
      expect(calls, [('Hassan', 0), ('Hassan', 25)]);
      await _tap(tester, _key('zotero-connected-source-1'));
      await _tap(tester, _key('zotero-connected-source-add'));
      expect(find.text('3 source(s)'), findsOneWidget);
      await _tap(tester, _key('zotero-composer-apply'));

      final items = result.citation!.items;
      expect(items.map((item) => item.itemData!['title']), [
        'Current',
        'First remote',
        'Second remote',
      ]);
      expect(items[1].uris, first.uris);
      expect(items[1].locator, isEmpty);
      expect(items[1].prefix, isEmpty);
      expect(first.locator, '77');
    },
  );

  testWidgets(
    'connected selection review includes hidden sources and stages removal and order',
    (tester) async {
      final calls = <(String, int)>[];
      final first = _source('First remote', uris: [_firstUri]);
      final second = _source('Second remote', uris: [_secondUri]);
      final third = _source('Third remote', uris: [_thirdUri]);
      final result = await _open(
        tester,
        items: [_source('Current')],
        searchZotero: (query, start) async {
          calls.add((query, start));
          return ZoteroPage<ZoteroCitationItem>(
            items: query == 'other'
                ? [third]
                : start == 0
                ? [first]
                : [second],
            start: start,
            limit: 25,
            nextStart: query == 'first' && start == 0 ? 25 : null,
          );
        },
      );
      await _tap(tester, _key('zotero-composer-search-zotero'));
      await _enter(tester, 'zotero-connected-source-query', 'first');
      await _tap(tester, _key('zotero-connected-source-search'));
      await _tap(tester, _key('zotero-connected-source-0'));
      await _tap(tester, _key('zotero-connected-source-more'));
      await _tap(tester, _key('zotero-connected-source-1'));
      await _enter(tester, 'zotero-connected-source-query', 'other');
      await _tap(tester, _key('zotero-connected-source-search'));
      await _tap(tester, _key('zotero-connected-source-0'));
      expect(
        find.text('1 results loaded · 3 selected · 2 hidden'),
        findsOneWidget,
      );

      await _tap(tester, _key('zotero-connected-source-review'));
      await _tap(tester, _key('zotero-selection-up-$_thirdUri'));
      await _tap(tester, _key('zotero-selection-remove-$_firstUri'));
      await _tap(tester, _key('zotero-selection-cancel'));
      expect(
        find.text('1 results loaded · 3 selected · 2 hidden'),
        findsOneWidget,
      );

      await _tap(tester, _key('zotero-connected-source-review'));
      expect(find.text('1. First remote'), findsOneWidget);
      await _tap(tester, _key('zotero-selection-up-$_thirdUri'));
      await _tap(tester, _key('zotero-selection-remove-$_firstUri'));
      await _tap(tester, _key('zotero-selection-details-$_secondUri'));
      expect(find.text('Second remote'), findsOneWidget);
      await _tap(tester, _key('zotero-stored-details-close'));
      await _tap(tester, _key('zotero-selection-apply'));
      expect(
        find.text('1 results loaded · 2 selected · 1 hidden'),
        findsOneWidget,
      );
      expect(calls, [('first', 0), ('first', 25), ('other', 0)]);

      await _tap(tester, _key('zotero-connected-source-add'));
      await _tap(tester, _key('zotero-composer-apply'));
      expect(result.citation!.items.map((item) => item.itemData!['title']), [
        'Current',
        'Third remote',
        'Second remote',
      ]);
      expect(result.citation!.items[1].uris, third.uris);
      expect(result.citation!.items[2].itemData, second.itemData);
    },
  );

  testWidgets(
    'removing hidden connected selections frees capacity and supports an empty selection',
    (tester) async {
      final first = _source('First remote', uris: [_firstUri]);
      final second = _source('Second remote', uris: [_secondUri]);
      final third = _source('Third remote', uris: [_thirdUri]);
      await _open(
        tester,
        items: List.generate(
          18,
          (index) => _source('Current $index', id: index),
        ),
        searchZotero: (query, start) async => ZoteroPage<ZoteroCitationItem>(
          items: query == 'other' ? [third] : [first, second],
          start: start,
          limit: 25,
        ),
      );
      await _tap(tester, _key('zotero-composer-search-zotero'));
      await _enter(tester, 'zotero-connected-source-query', 'first');
      await _tap(tester, _key('zotero-connected-source-search'));
      await _tap(tester, _key('zotero-connected-source-0'));
      await _tap(tester, _key('zotero-connected-source-1'));
      await _enter(tester, 'zotero-connected-source-query', 'other');
      await _tap(tester, _key('zotero-connected-source-search'));
      await _tap(tester, _key('zotero-connected-source-0'));
      expect(
        find.text('Select at most 2 additional source(s).'),
        findsOneWidget,
      );
      await _tap(tester, _key('zotero-connected-source-review'));
      await _tap(tester, _key('zotero-selection-remove-$_firstUri'));
      await _tap(tester, _key('zotero-selection-apply'));
      await _tap(tester, _key('zotero-connected-source-0'));
      expect(
        find.text('1 results loaded · 2 selected · 1 hidden'),
        findsOneWidget,
      );
      expect(_key('zotero-connected-source-error'), findsNothing);

      await _tap(tester, _key('zotero-connected-source-review'));
      await _tap(tester, _key('zotero-selection-remove-$_secondUri'));
      await _tap(tester, _key('zotero-selection-remove-$_thirdUri'));
      await _tap(tester, _key('zotero-selection-apply'));
      expect(
        tester
            .widget<FilledButton>(_key('zotero-connected-source-add'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(_key('zotero-connected-source-review'))
            .onPressed,
        isNull,
      );
      await _tap(tester, _key('zotero-connected-source-cancel'));
      expect(find.text('18 source(s)'), findsOneWidget);
    },
  );

  testWidgets(
    'failed connected search and cancellation leave the citation untouched',
    (tester) async {
      final original = _source('Original');
      final result = await _open(
        tester,
        items: [original],
        searchZotero: (query, start) async {
          throw StateError('Connection unavailable');
        },
      );
      await _tap(tester, _key('zotero-composer-search-zotero'));
      await _enter(tester, 'zotero-connected-source-query', 'title');
      await _tap(tester, _key('zotero-connected-source-search'));
      expect(_key('zotero-connected-source-error'), findsOneWidget);
      await _tap(tester, _key('zotero-connected-source-cancel'));
      expect(find.text('1 source(s)'), findsOneWidget);
      await _tap(tester, _key('zotero-composer-cancel'));
      expect(result.returned, isTrue);
      expect(result.citation, isNull);
      expect(original.itemData!['title'], 'Original');
    },
  );

  testWidgets(
    'connected search remains usable in narrow doubled-text RTL layout',
    (tester) async {
      final result = await _open(
        tester,
        items: [_source('Original')],
        size: const Size(320, 480),
        scale: 2,
        direction: TextDirection.rtl,
        searchZotero: (query, start) async => ZoteroPage<ZoteroCitationItem>(
          items: [
            _source('Arabic and German source', uris: [_firstUri]),
          ],
          start: start,
          limit: 25,
        ),
      );
      await _tap(tester, _key('zotero-composer-search-zotero'));
      await _enter(tester, 'zotero-connected-source-query', 'Arabic');
      await _tap(tester, _key('zotero-connected-source-search'));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(_key('zotero-connected-source-0'))
            .value,
        isTrue,
      );
      await _tap(tester, _key('zotero-connected-source-review'));
      await tester.ensureVisible(_key('zotero-selected-reference-list'));
      await tester.scrollUntilVisible(
        _key('zotero-selection-details-$_firstUri'),
        120,
        scrollable: find.descendant(
          of: _key('zotero-selected-reference-list'),
          matching: find.byType(Scrollable),
        ),
      );
      await _tap(tester, _key('zotero-selection-details-$_firstUri'));
      await _tap(tester, _key('zotero-stored-details-close'));
      await _tap(tester, _key('zotero-selection-apply'));
      await _tap(tester, _key('zotero-connected-source-add'));
      await _tap(tester, _key('zotero-composer-apply'));
      expect(result.citation!.items, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'editing a custom locator requires text review and clears stale RTF',
    (tester) async {
      final first = _source(
        'Citation with a page',
        options: {'locator': '12', 'label': 'page'},
      );
      final existing = _existing([first]);
      final result = await _open(
        tester,
        items: existing.items,
        existing: existing,
      );
      expect(_canApply(tester), isTrue);

      await _tap(tester, _key('zotero-composer-options-0'));
      await _enter(tester, 'zotero-composer-locator-0', '34');
      expect(_preview(tester), 'Original custom text');
      expect(_canApply(tester), isFalse);
      expect(_key('zotero-composer-text-review-message'), findsOneWidget);
      expect(existing.items.single.locator, '12');

      await _tap(tester, _key('zotero-composer-confirm-text'));
      expect(_canApply(tester), isTrue);
      await _tap(tester, _key('zotero-composer-apply'));
      expect(result.citation!.items.single.locator, '34');
      expect(result.citation!.plainCitation, 'Original custom text');
      expect(result.citation!.formattedCitation, 'Original custom text');
      expect(result.citation!.properties['unknownProperty'], 'retain');
      expect(existing.items.single.locator, '12');
      expect(existing.formattedCitation, isNotNull);
    },
  );

  testWidgets(
    'author options and affixes invalidate custom cache, undoing edits restores it',
    (tester) async {
      final first = _source('Citation options', options: {'prefix': 'see'});
      final existing = _existing([first]);
      final result = await _open(
        tester,
        items: existing.items,
        existing: existing,
      );
      await _tap(tester, _key('zotero-composer-options-0'));
      await _enter(tester, 'zotero-composer-prefix-0', 'compare');
      expect(_canApply(tester), isFalse);
      await _enter(tester, 'zotero-composer-prefix-0', 'see');
      expect(_canApply(tester), isTrue);

      await _tap(tester, _key('zotero-composer-author-only-0'));
      expect(_canApply(tester), isFalse);
      await _tap(tester, _key('zotero-composer-confirm-text'));
      await _tap(tester, _key('zotero-composer-apply'));
      expect(result.citation!.items.single.authorOnly, isTrue);
      expect(result.citation!.items.single.suppressAuthor, isFalse);
      expect(result.citation!.formattedCitation, 'Original custom text');
      expect(existing.items.single.authorOnly, isFalse);
    },
  );

  testWidgets(
    'reordering duplicate IDs keeps edited options on the correct occurrence',
    (tester) async {
      final first = _source(
        'First occurrence',
        options: {'locator': '11', 'prefix': 'see', 'label': 'folio'},
      );
      final second = _source(
        'Second occurrence',
        options: {'locator': '22', 'prefix': 'also', 'suffix': 'second'},
      );
      final original = _existing([first, second], basic: true);
      final result = await _open(
        tester,
        items: original.items,
        existing: original,
      );
      await _tap(tester, _key('zotero-composer-options-0'));
      await _enter(tester, 'zotero-composer-locator-0', '101');
      expect(find.text('folio'), findsOneWidget);
      await _tap(tester, _key('zotero-composer-options-1'));
      await _enter(tester, 'zotero-composer-prefix-1', 'compare');
      await _tap(tester, _key('zotero-composer-down-0'));
      final locator = find.descendant(
        of: _key('zotero-composer-locator-0'),
        matching: find.byType(EditableText),
      );
      expect(tester.widget<EditableText>(locator).controller.text, '101');
      expect(_preview(tester), contains('compare Hassan'));
      await _tap(tester, _key('zotero-composer-apply'));
      final citation = result.citation!;
      expect(citation.items[0].itemData!['title'], 'Second occurrence');
      expect(citation.items[0].prefix, 'compare');
      expect(citation.items[0].locator, '22');
      expect(citation.items[0].suffix, 'second');
      expect(citation.items[1].itemData!['title'], 'First occurrence');
      expect(citation.items[1].locator, '101');
      expect(citation.items[1].label, 'folio');
      expect(citation.items[1].prefix, 'see');
      expect(citation.citationId, original.citationId);
      expect(citation.noteIndex, 4);
      expect(citation.toJson()['unknownCitationProperty'], {'retain': true});
      expect(citation.properties['unknownProperty'], 'retain');
      expect(original.items[0].locator, '11');
      expect(original.items[1].prefix, 'also');
    },
  );

  testWidgets('added sources reset occurrence options but keep complete data', (
    tester,
  ) async {
    final added = _source(
      'A linked addition',
      uris: const [
        'http://zotero.org/users/42/items/ADDED001',
        'https://www.zotero.org/users/42/items/ADDED001',
      ],
      options: {
        'locator': '44',
        'label': 'section',
        'prefix': 'previous',
        'suffix': 'old suffix',
        'suppress-author': true,
        'author-only': true,
        'position': 1,
        'near-note': true,
      },
    );
    final result = await _open(
      tester,
      items: [_source('Original')],
      available: [added],
    );
    await _add(tester, [0]);
    await _tap(tester, _key('zotero-composer-apply'));
    final actual = result.citation!.items[1];
    expect(actual.id, added.id);
    expect(actual.itemData, added.itemData);
    expect(actual.uris, added.uris);
    expect(actual.toJson()['unknownSourceProperty'], {
      'keep': 'A linked addition',
    });
    for (final option in [
      'locator',
      'label',
      'prefix',
      'suffix',
      'suppress-author',
      'author-only',
      'position',
      'near-note',
    ]) {
      expect(actual.toJson().containsKey(option), isFalse, reason: option);
    }
    expect(added.locator, '44');
  });

  testWidgets(
    'oversized combined citation keeps its draft and can be repaired',
    (tester) async {
      final first = _source(
        'First large source',
        options: {'largePayload': 'a' * (600 * 1024)},
      );
      final second = _source(
        'Second large source',
        options: {'largePayload': 'b' * (600 * 1024)},
      );
      final result = await _open(tester, items: [first], available: [second]);
      await _add(tester, [0]);
      final before = _preview(tester);
      await _tap(tester, _key('zotero-composer-apply'));
      expect(result.returned, isFalse);
      expect(_key('zotero-citation-composer'), findsOneWidget);
      expect(
        find.text('Zotero metadata exceeds the 1 MiB limit.'),
        findsOneWidget,
      );
      expect(find.text('2 source(s)'), findsOneWidget);
      expect(_preview(tester), before);
      await _tap(tester, _key('zotero-composer-remove-1'));
      expect(_key('zotero-composer-error'), findsNothing);
      await _tap(tester, _key('zotero-composer-apply'));
      expect(result.returned, isTrue);
      expect(result.citation!.items.single.toJson(), first.toJson());
      expect(first.toJson()['largePayload'], 'a' * (600 * 1024));
      expect(second.toJson()['largePayload'], 'b' * (600 * 1024));
    },
  );

  testWidgets(
    'chooser preserves hidden duplicate-ID selections and add order',
    (tester) async {
      final first = _source('First candidate', doi: '10.1000/first');
      final second = _source('Second candidate', family: 'Other');
      final result = await _open(
        tester,
        items: [_source('Original')],
        available: [first, second],
      );
      await _tap(tester, _key('zotero-composer-add-sources'));
      await _enter(tester, 'zotero-composer-source-search', 'Other 2024');
      await _tap(tester, _key('zotero-composer-candidate-1'));
      await _enter(tester, 'zotero-composer-source-search', '10.1000/first');
      expect(find.text('1 selected outside these results'), findsOneWidget);
      await _tap(tester, _key('zotero-composer-candidate-details-0'));
      expect(_key('zotero-stored-reference-details-dialog'), findsOneWidget);
      await _tap(tester, _key('zotero-stored-details-close'));
      expect(find.text('1 selected outside these results'), findsOneWidget);
      await _tap(tester, _key('zotero-composer-candidate-0'));
      await _tap(tester, _key('zotero-composer-source-add'));
      await _tap(tester, _key('zotero-composer-apply'));
      expect(result.citation!.items.map((item) => item.itemData!['title']), [
        'Original',
        'Second candidate',
        'First candidate',
      ]);
    },
  );

  testWidgets(
    'filtering scrolled source candidates starts at the first match',
    (tester) async {
      await _open(
        tester,
        items: [_source('Original')],
        available: [
          for (var index = 0; index < 80; index++)
            _source('${index.isEven ? 'Matching' : 'Other'} candidate $index'),
        ],
      );
      await _tap(tester, _key('zotero-composer-add-sources'));
      final list = _key('zotero-composer-candidate-list');
      await tester.drag(list, const Offset(0, -1300));
      await tester.pumpAndSettle();
      final scrollable = find.descendant(
        of: list,
        matching: find.byType(Scrollable),
      );
      expect(
        tester.state<ScrollableState>(scrollable).position.pixels,
        greaterThan(0),
      );
      await _enter(tester, 'zotero-composer-source-search', 'Matching');
      expect(tester.state<ScrollableState>(scrollable).position.pixels, 0);
      expect(_key('zotero-composer-candidate-0').hitTestable(), findsOneWidget);
      expect(find.text('40 of 80 references · 0 selected'), findsOneWidget);
    },
  );

  testWidgets('cancelled chooser and composer do not modify their inputs', (
    tester,
  ) async {
    final first = _source('First', options: {'locator': '7'});
    final second = _source('Second');
    final original = _existing([first, second]);
    final snapshot = original.toJson();
    final result = await _open(
      tester,
      items: original.items,
      existing: original,
      available: [_source('Available')],
    );
    await _tap(tester, _key('zotero-composer-add-sources'));
    await _tap(tester, _key('zotero-composer-candidate-0'));
    await _tap(tester, _key('zotero-composer-source-cancel'));
    expect(find.text('2 source(s)'), findsOneWidget);
    await _tap(tester, _key('zotero-composer-remove-0'));
    await _add(tester, [0]);
    await _tap(tester, _key('zotero-composer-options-1'));
    await _enter(tester, 'zotero-composer-locator-1', '99');
    await _tap(tester, _key('zotero-composer-cancel'));
    expect(result.returned, isTrue);
    expect(result.citation, isNull);
    expect(original.toJson(), snapshot);
    expect(first.locator, '7');
    expect(second.locator, isEmpty);
  });

  testWidgets(
    'empty citations cannot apply and can recover by adding a source',
    (tester) async {
      final result = await _open(
        tester,
        items: [_source('Original')],
        available: [_source('Replacement')],
      );
      await _tap(tester, _key('zotero-composer-remove-0'));
      expect(_canApply(tester), isFalse);
      expect(_preview(tester), isEmpty);
      expect(find.text('Add at least one source to continue.'), findsOneWidget);
      await _add(tester, [0]);
      expect(_canApply(tester), isTrue);
      await _tap(tester, _key('zotero-composer-apply'));
      expect(result.citation!.items.single.itemData!['title'], 'Replacement');
    },
  );

  testWidgets('addition limit permits deselection and prevents a 21st source', (
    tester,
  ) async {
    final result = await _open(
      tester,
      items: [for (var index = 0; index < 19; index++) _source('Item $index')],
      available: [_source('First extra'), _source('Second extra')],
    );
    await _tap(tester, _key('zotero-composer-add-sources'));
    await _tap(tester, _key('zotero-composer-candidate-0'));
    await _tap(tester, _key('zotero-composer-candidate-1'));
    expect(find.text('Select at most 1 additional source(s).'), findsOneWidget);
    await _tap(tester, _key('zotero-composer-candidate-0'));
    await _tap(tester, _key('zotero-composer-candidate-1'));
    await _tap(tester, _key('zotero-composer-source-add'));
    expect(
      tester
          .widget<OutlinedButton>(_key('zotero-composer-add-sources'))
          .onPressed,
      isNull,
    );
    await _tap(tester, _key('zotero-composer-apply'));
    expect(result.citation!.items, hasLength(20));
    expect(result.citation!.items.last.itemData!['title'], 'Second extra');
  });

  testWidgets(
    'larger imported clusters retain every source and remain editable',
    (tester) async {
      final items = [
        for (var index = 0; index < 21; index++)
          _source('Imported $index', options: {'locator': '$index'}),
      ];
      final existing = _existing(items, basic: true);
      final result = await _open(
        tester,
        items: existing.items,
        existing: existing,
        available: [_source('Available')],
      );
      expect(find.text('21 source(s)'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(_key('zotero-composer-add-sources'))
            .onPressed,
        isNull,
      );
      await _tap(tester, _key('zotero-composer-options-20'));
      await _enter(tester, 'zotero-composer-locator-20', '88');
      await _tap(tester, _key('zotero-composer-up-20'));
      await _tap(tester, _key('zotero-composer-apply'));
      expect(result.citation!.items, hasLength(21));
      expect(result.citation!.items[19].itemData!['title'], 'Imported 20');
      expect(result.citation!.items[19].locator, '88');
      expect(result.citation!.items[20].itemData!['title'], 'Imported 19');
    },
  );

  testWidgets(
    'custom text requires review after changing membership or order',
    (tester) async {
      final original = _existing([_source('First'), _source('Second')]);
      final result = await _open(
        tester,
        items: original.items,
        existing: original,
        existingCache: 'Visible original cache',
      );
      expect(_canApply(tester), isTrue);
      await _tap(tester, _key('zotero-composer-down-0'));
      expect(_canApply(tester), isFalse);
      expect(_preview(tester), 'Visible original cache');
      await _tap(tester, _key('zotero-composer-confirm-text'));
      expect(_canApply(tester), isTrue);
      await _tap(tester, _key('zotero-composer-remove-1'));
      expect(_canApply(tester), isFalse);
      await _enter(tester, 'zotero-citation-preview', 'Reviewed first source');
      expect(_canApply(tester), isTrue);
      await _tap(tester, _key('zotero-composer-apply'));
      expect(result.citation!.items.single.itemData!['title'], 'First');
      expect(result.citation!.plainCitation, 'Reviewed first source');
      expect(result.citation!.formattedCitation, 'Reviewed first source');
      expect(original.formattedCitation, r'{\rtf1 Original custom text}');
    },
  );

  testWidgets('confirming unchanged custom text discards old formatted cache', (
    tester,
  ) async {
    final original = _existing([_source('First'), _source('Second')]);
    final result = await _open(
      tester,
      items: original.items,
      existing: original,
    );
    await _tap(tester, _key('zotero-composer-down-0'));
    await _tap(tester, _key('zotero-composer-confirm-text'));
    await _tap(tester, _key('zotero-composer-apply'));
    expect(result.citation!.plainCitation, original.plainCitation);
    expect(result.citation!.formattedCitation, original.plainCitation);
    expect(
      result.citation!.formattedCitation,
      isNot(original.formattedCitation),
    );
  });

  testWidgets('restoring the original sequence preserves imported formatting', (
    tester,
  ) async {
    final original = _existing([_source('First'), _source('Second')]);
    final result = await _open(
      tester,
      items: original.items,
      existing: original,
    );
    await _tap(tester, _key('zotero-composer-down-0'));
    expect(_canApply(tester), isFalse);
    await _tap(tester, _key('zotero-composer-up-0'));
    expect(_canApply(tester), isTrue);
    expect(_key('zotero-composer-confirm-text'), findsNothing);
    await _tap(tester, _key('zotero-composer-apply'));
    expect(result.citation!.formattedCitation, original.formattedCitation);
    expect(
      result.citation!.items.map((item) => item.toJson()),
      original.items.map((item) => item.toJson()),
    );
  });

  testWidgets(
    'choosing basic format regenerates text for the revised sources',
    (tester) async {
      final original = _existing([
        _source('First', family: 'FirstAuthor'),
        _source('Second', family: 'SecondAuthor'),
      ]);
      final result = await _open(
        tester,
        items: original.items,
        existing: original,
      );
      await _tap(tester, _key('zotero-composer-remove-0'));
      expect(_canApply(tester), isFalse);
      await _tap(tester, find.byType(DropdownButtonFormField<bool>));
      await _tap(tester, find.text('Basic author–year').last);
      expect(_preview(tester), '(SecondAuthor, 2024)');
      expect(_canApply(tester), isTrue);
      await _tap(tester, _key('zotero-composer-apply'));
      expect(result.citation!.properties['qudsFormat'], 'basic-author-year');
      expect(result.citation!.items.single.itemData!['title'], 'Second');
    },
  );

  testWidgets('single-source preview receives the current source after edits', (
    tester,
  ) async {
    final calls = <ZoteroCitationItem>[];
    await _open(
      tester,
      items: [
        _source('First', uris: const [_firstUri]),
        _source('Second', uris: const [_secondUri]),
      ],
      available: [
        _source('Third', uris: const [_thirdUri]),
      ],
      preview: (item) async {
        calls.add(item);
        return 'Preview of ${item.itemData!['title']}';
      },
    );
    expect(_key('zotero-composer-style-preview'), findsNothing);
    await _tap(tester, _key('zotero-composer-remove-0'));
    await _tap(tester, _key('zotero-composer-style-preview'));
    expect(calls.single.itemData!['title'], 'Second');
    expect(_preview(tester), 'Preview of Second');
    expect(_canApply(tester), isFalse);
    await _add(tester, [0]);
    expect(_key('zotero-composer-style-preview'), findsNothing);
    await _tap(tester, _key('zotero-composer-remove-1'));
    await _tap(tester, _key('zotero-composer-style-preview'));
    expect(calls.last.itemData!['title'], 'Third');
    expect(_preview(tester), 'Preview of Third');
  });

  testWidgets('failed preview keeps draft text and allows a successful retry', (
    tester,
  ) async {
    var calls = 0;
    await _open(
      tester,
      items: [
        _source('Source', uris: const [_firstUri]),
      ],
      preview: (_) async {
        calls++;
        if (calls == 1) throw const FormatException('Preview unavailable.');
        return 'Recovered preview';
      },
    );
    final before = _preview(tester);
    await _tap(tester, _key('zotero-composer-style-preview'));
    expect(_preview(tester), before);
    expect(find.text('Preview unavailable.'), findsOneWidget);
    await _tap(tester, _key('zotero-composer-style-preview'));
    expect(_preview(tester), 'Recovered preview');
    expect(_key('zotero-composer-error'), findsNothing);
  });

  testWidgets(
    'pending preview cannot mutate sources or resurrect a closed draft',
    (tester) async {
      final pending = Completer<String>();
      final result = await _open(
        tester,
        items: [
          _source('Source', uris: const [_firstUri]),
        ],
        available: [_source('Another')],
        preview: (_) => pending.future,
      );
      await tester.ensureVisible(_key('zotero-composer-style-preview'));
      await tester.pumpAndSettle();
      await tester.tap(_key('zotero-composer-style-preview'));
      await tester.pump();
      expect(
        tester.widget<IconButton>(_key('zotero-composer-remove-0')).onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(_key('zotero-composer-add-sources'))
            .onPressed,
        isNull,
      );
      expect(_canApply(tester), isFalse);
      await _tap(tester, _key('zotero-composer-cancel'));
      pending.complete('Late preview');
      await tester.pumpAndSettle();
      expect(result.returned, isTrue);
      expect(result.citation, isNull);
      expect(_key('zotero-citation-composer'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'offline and malformed identities do not offer connected previews',
    (tester) async {
      var calls = 0;
      await _open(
        tester,
        items: [
          _source(
            'Offline source',
            uris: const ['http://zotero.org/users/0/items/FIRST001'],
          ),
        ],
        available: [
          _source('Linked source', uris: const [_firstUri]),
        ],
        preview: (_) async {
          calls++;
          return 'Formatted';
        },
      );
      expect(_key('zotero-composer-style-preview'), findsNothing);
      await _tap(tester, _key('zotero-composer-remove-0'));
      await _add(tester, [0]);
      expect(_key('zotero-composer-style-preview'), findsOneWidget);
      expect(calls, 0);
    },
  );

  testWidgets(
    'nested source details retain reordered options and custom review',
    (tester) async {
      final original = _existing([
        _source('First', options: {'locator': '4'}),
        _source('Second', options: {'locator': '5'}),
      ]);
      final result = await _open(
        tester,
        items: original.items,
        existing: original,
      );
      await _tap(tester, _key('zotero-composer-down-0'));
      await _tap(tester, _key('zotero-composer-confirm-text'));
      await _tap(tester, _key('zotero-composer-details-0'));
      expect(
        find.byWidgetPredicate(
          (widget) => widget is SelectableText && widget.data == 'First',
        ),
        findsOneWidget,
      );
      await _tap(tester, _key('zotero-stored-details-close'));
      expect(_canApply(tester), isTrue);
      await _tap(tester, _key('zotero-composer-apply'));
      expect(result.citation!.items.map((item) => item.locator), ['5', '4']);
    },
  );

  for (final direction in TextDirection.values) {
    testWidgets(
      'composer and chooser work at doubled text in narrow $direction',
      (tester) async {
        final result = await _open(
          tester,
          items: [_source('First narrow source')],
          available: [_source('Second narrow source', doi: '10.1234/narrow')],
          size: const Size(320, 480),
          scale: 2,
          direction: direction,
        );
        await _tap(tester, _key('zotero-composer-options-0'));
        await _enter(tester, 'zotero-composer-locator-0', '10–12');
        await _tap(tester, _key('zotero-composer-add-sources'));
        await _enter(tester, 'zotero-composer-source-search', '10.1234/narrow');
        await _tap(tester, _key('zotero-composer-candidate-details-0'));
        await _tap(tester, _key('zotero-stored-details-close'));
        await _tap(tester, _key('zotero-composer-candidate-0'));
        await _tap(tester, _key('zotero-composer-source-add'));
        await _tap(tester, _key('zotero-composer-up-1'));
        await _tap(tester, _key('zotero-composer-details-0'));
        await _tap(tester, _key('zotero-stored-details-close'));
        await _tap(tester, _key('zotero-composer-apply'));
        expect(
          result.citation!.items[0].itemData!['title'],
          'Second narrow source',
        );
        expect(result.citation!.items[1].locator, '10–12');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
