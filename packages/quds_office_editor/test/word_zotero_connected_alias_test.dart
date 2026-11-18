import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _local = 'http://zotero.org/users/local/LOCALKEY/items/SOURCE01';
const _localAlias = 'http://zotero.org/users/local/LOCALKEY/items/SOURCE02';
const _account = 'http://zotero.org/users/42/items/SOURCE02';
const _group = 'http://zotero.org/groups/42/items/SOURCE02';

ZoteroCitation _citation(
  String id,
  List<String> uris, {
  bool basic = true,
  bool snapshot = true,
}) => ZoteroCitation.fromJson({
  'citationID': id,
  'citationItems': [
    {
      'id': 'original-$id',
      'uris': uris,
      if (snapshot)
        'itemData': {
          'id': 'original-$id',
          'type': 'book',
          'title': 'Original $id',
          'author': [
            {'family': 'Original'},
          ],
          'issued': {
            'date-parts': [
              [2020],
            ],
          },
        },
      'locator': '12–15',
      'label': 'page',
      'prefix': 'see',
      'suffix': 'for details',
      'futureItemSetting': {'keep': id},
    },
  ],
  'properties': {
    'plainCitation': '(Original $id)',
    'formattedCitation': '(Original $id)',
    'qudsFormat': basic ? 'basic-author-year' : 'custom',
    'futureCitationSetting': {'keep': id},
  },
  'futureTopLevelSetting': id,
});

List<ZoteroCitation> _bridgedCitations() => [
  _citation('local', [_local]),
  _citation('account', [_account]),
  _citation('bridge-a', [_local, _localAlias], basic: false, snapshot: false),
  _citation('bridge-b', [_localAlias, _account], basic: false, snapshot: false),
];

List<ZoteroCitation> _manyAliases(int count) {
  final uris = [
    for (var i = 0; i < count; i++)
      'http://zotero.org/users/42/items/K${i.toString().padLeft(7, '0')}',
  ];
  return [
    for (var start = 0; start < count; start += 1000)
      ZoteroCitation.fromJson({
        ..._citation('cluster-$start', [uris[start]]).toJson(),
        'citationItems': [
          for (var i = start; i < count && i < start + 1000; i++)
            _citation('source-$i', [uris[i]]).items.single.toJson(),
        ],
      }),
    _citation('alias-bridge', uris, basic: false, snapshot: false),
  ];
}

WmlDocument _document(List<ZoteroCitation> citations) => WmlDocument(
  sections: [
    WmlSection(
      blocks: [
        for (final citation in citations)
          WmlParagraph(
            inlines: [
              WmlRun(
                text: citation.plainCitation,
                fieldInstruction: citation.fieldInstruction,
              ),
            ],
          ),
      ],
    ),
  ],
);

Map<String, Object?> _apiItem(String key, {bool group = false}) => {
  'key': key,
  'version': 7,
  'library': {'type': group ? 'group' : 'user', 'id': 42},
  'data': {
    'key': key,
    'itemType': 'book',
    'title': group ? 'Updated group source' : 'Updated account source',
  },
  'csljson': {
    'id': 'http://zotero.org/${group ? 'groups' : 'users'}/42/items/$key',
    'type': 'book',
    'title': group ? 'Updated group source' : 'Updated account source',
    'author': [
      {'family': 'Updated'},
    ],
    'issued': {
      'date-parts': [
        [2026],
      ],
    },
  },
};

ZoteroHttpResponse _json(List<Object?> body) => ZoteroHttpResponse(
  statusCode: 200,
  body: jsonEncode(body),
  headers: {'Total-Results': '${body.length}', 'Last-Modified-Version': '7'},
);

Future<WordEditorController> _open(
  WidgetTester tester, {
  required List<ZoteroCitation> citations,
  required ZoteroTransport transport,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 1100);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final controller = WordEditorController(document: _document(citations));
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showWordZoteroDialog(
              context,
              controller: controller,
              session: ZoteroSession()..apiKey = 'test-read-only-key',
              transport: transport,
            ),
            child: const Text('Open references'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open references'));
  await tester.pumpAndSettle();
  return controller;
}

Future<void> _action(
  WidgetTester tester,
  String label, {
  bool pending = false,
}) async {
  await tester.tap(find.text('Document'));
  await tester.pumpAndSettle();
  final action = find.text(label);
  await tester.ensureVisible(action);
  await tester.pump();
  await tester.tap(action);
  if (pending) {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  } else {
    await tester.pumpAndSettle();
  }
}

List<String> _instructions(WordEditorController controller) =>
    controller.zoteroFields.map((field) => field.instruction).toList();

void main() {
  testWidgets('refresh counts 1,001 declared aliases as one linked source', (
    tester,
  ) async {
    final requests = <ZoteroHttpRequest>[];
    final controller = await _open(
      tester,
      citations: _manyAliases(1001),
      transport: (request) async {
        requests.add(request);
        expect(request.uri.queryParameters['itemKey'], 'K0000000');
        return _json([_apiItem('K0000000')]);
      },
    );
    final originalBridge = controller.zoteroFields.last.instruction;
    await _action(tester, 'Refresh basic citations');
    expect(requests, hasLength(1));
    expect(
      controller.zoteroFields
          .take(2)
          .expand((field) => field.citation!.items)
          .map((item) => item.itemData!['title']),
      everyElement('Updated account source'),
    );
    expect(controller.zoteroFields.last.instruction, originalBridge);
    expect(controller.canUndo, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bibliography counts 51 declared aliases as one linked source', (
    tester,
  ) async {
    final requests = <ZoteroHttpRequest>[];
    final controller = await _open(
      tester,
      citations: _manyAliases(51),
      transport: (request) async {
        requests.add(request);
        expect(request.uri.queryParameters['itemKey'], 'K0000000');
        if (request.uri.queryParameters['format'] == 'json') {
          return _json([_apiItem('K0000000')]);
        }
        return ZoteroHttpResponse(
          statusCode: 200,
          headers: {'Total-Results': '1', 'Last-Modified-Version': '7'},
          body: '<div>One complete bibliography entry.</div>',
        );
      },
    );
    final before = _instructions(controller);
    await _action(tester, 'Zotero bibliography', pending: true);
    expect(requests, hasLength(2));
    expect(find.text('Review Zotero bibliography'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(_instructions(controller), before);
    expect(controller.canUndo, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('basic refresh uses late custom alias bridges in one undo', (
    tester,
  ) async {
    final requests = <ZoteroHttpRequest>[];
    final citations = _bridgedCitations();
    final controller = await _open(
      tester,
      citations: citations,
      transport: (request) async {
        requests.add(request);
        expect(request.uri.path, '/users/42/items');
        expect(request.uri.queryParameters['itemKey'], 'SOURCE02');
        return _json([_apiItem('SOURCE02')]);
      },
    );
    final before = _instructions(controller);
    await _action(tester, 'Refresh basic citations');
    expect(requests, hasLength(1));
    final fields = controller.zoteroFields;
    for (var index = 0; index < 2; index++) {
      final updated = fields[index].citation!;
      final old = citations[index];
      final item = updated.items.single;
      final original = old.items.single;
      expect(item.itemData!['title'], 'Updated account source');
      expect(item.itemData!['id'], original.id);
      expect(item.id, original.id);
      expect(item.uris, original.uris);
      expect(item.locator, '12–15');
      expect(item.label, 'page');
      expect(item.prefix, 'see');
      expect(item.suffix, 'for details');
      expect(
        item.toJson()['futureItemSetting'],
        original.toJson()['futureItemSetting'],
      );
      expect(
        updated.toJson()['futureTopLevelSetting'],
        old.toJson()['futureTopLevelSetting'],
      );
      expect(
        updated.properties['futureCitationSetting'],
        old.properties['futureCitationSetting'],
      );
      expect(
        fields[index].cachedText,
        '(see Updated, 2026, p. 12–15 for details)',
      );
    }
    expect(fields.skip(2).map((field) => field.instruction), before.skip(2));
    final after = _instructions(controller);
    await tester.tap(find.byTooltip('Close Zotero'));
    await tester.pumpAndSettle();
    controller.undo();
    expect(_instructions(controller), before);
    expect(controller.canUndo, isFalse);
    controller.redo();
    expect(_instructions(controller), after);
    final reopened = WordDeserializer().readBytes(controller.saveBytes());
    expect(
      WordZotero.fields(reopened).map((field) => field.instruction),
      after,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unrelated group keeps the same item key in another request', (
    tester,
  ) async {
    final requests = <ZoteroHttpRequest>[];
    final controller = await _open(
      tester,
      citations: [
        ..._bridgedCitations(),
        _citation('group', [_group]),
      ],
      transport: (request) async {
        requests.add(request);
        return _json([
          _apiItem('SOURCE02', group: request.uri.path.startsWith('/groups/')),
        ]);
      },
    );
    await _action(tester, 'Refresh basic citations');
    expect(requests.map((request) => request.uri.path), [
      '/users/42/items',
      '/groups/42/items',
    ]);
    expect(
      controller.zoteroFields.first.citation!.items.single.itemData!['title'],
      'Updated account source',
    );
    expect(
      controller.zoteroFields.last.citation!.items.single.itemData!['title'],
      'Updated group source',
    );
    expect(tester.takeException(), isNull);
  });

  for (final failure in ['mismatch', 'missing', 'server', 'stale']) {
    testWidgets('alias refresh $failure discards all staged updates', (
      tester,
    ) async {
      final requests = <ZoteroHttpRequest>[];
      late WordEditorController controller;
      controller = await _open(
        tester,
        citations: [
          ..._bridgedCitations(),
          _citation('group', [_group]),
        ],
        transport: (request) async {
          requests.add(request);
          if (requests.length == 1) return _json([_apiItem('SOURCE02')]);
          expect(controller.zoteroFields.first.cachedText, '(Original local)');
          switch (failure) {
            case 'mismatch':
              return _json([_apiItem('SOURCE02')]);
            case 'missing':
              return _json([]);
            case 'server':
              return ZoteroHttpResponse(statusCode: 500, body: 'Unavailable');
            case 'stale':
              controller.caret.logicalIndex = 1;
              return _json([_apiItem('SOURCE02', group: true)]);
          }
          throw StateError('Unexpected failure case');
        },
      );
      final before = _instructions(controller);
      final revision = controller.contentRevision;
      await _action(tester, 'Refresh basic citations');
      expect(requests, hasLength(2));
      expect(_instructions(controller), before);
      expect(controller.contentRevision, revision);
      expect(controller.canUndo, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'a declared source without an online alias refuses before reads',
    (tester) async {
      final requests = <ZoteroHttpRequest>[];
      final controller = await _open(
        tester,
        citations: [
          ..._bridgedCitations(),
          _citation('other-profile', [
            'http://zotero.org/users/local/OTHERKEY/items/SOURCE01',
          ]),
        ],
        transport: (request) async {
          requests.add(request);
          return _json([_apiItem('SOURCE02')]);
        },
      );
      final before = _instructions(controller);
      await _action(tester, 'Refresh basic citations');
      expect(requests, isEmpty);
      expect(find.textContaining('unsynced desktop library'), findsOneWidget);
      expect(_instructions(controller), before);
      expect(controller.canUndo, isFalse);
    },
  );

  testWidgets(
    'API bibliography verifies and formats one alias representative',
    (tester) async {
      final requests = <ZoteroHttpRequest>[];
      final controller = await _open(
        tester,
        citations: _bridgedCitations(),
        transport: (request) async {
          requests.add(request);
          expect(request.uri.path, '/users/42/items');
          expect(request.uri.queryParameters['itemKey'], 'SOURCE02');
          if (request.uri.queryParameters['format'] == 'json') {
            return _json([_apiItem('SOURCE02')]);
          }
          return ZoteroHttpResponse(
            statusCode: 200,
            headers: {'Total-Results': '1', 'Last-Modified-Version': '7'},
            body: '<div><i>One linked source</i>.</div>',
          );
        },
      );
      final before = _instructions(controller);
      await _action(tester, 'Zotero bibliography', pending: true);
      expect(requests, hasLength(2));
      expect(_instructions(controller), before);
      await tester.tap(find.widgetWithText(FilledButton, 'Use bibliography'));
      await tester.pumpAndSettle();
      final bibliography = controller.zoteroFields.singleWhere(
        (field) => field.kind == ZoteroFieldKind.bibliography,
      );
      expect(bibliography.cachedText, 'One linked source.');
      expect(
        controller.zoteroFields
            .where((field) => field.citation != null)
            .map((field) => field.instruction),
        before,
      );
      await tester.tap(find.byTooltip('Close Zotero'));
      await tester.pumpAndSettle();
      controller.undo();
      expect(_instructions(controller), before);
      expect(controller.canUndo, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'closing during an alias refresh cannot apply its late response',
    (tester) async {
      final pending = Completer<ZoteroHttpResponse>();
      var calls = 0;
      final controller = await _open(
        tester,
        citations: _bridgedCitations(),
        transport: (request) {
          calls++;
          return pending.future;
        },
      );
      final before = _instructions(controller);
      final revision = controller.contentRevision;
      await _action(tester, 'Refresh basic citations', pending: true);
      expect(calls, 1);
      await tester.tap(find.byTooltip('Close Zotero'));
      await tester.pumpAndSettle();
      pending.complete(_json([_apiItem('SOURCE02')]));
      await tester.pumpAndSettle();
      expect(_instructions(controller), before);
      expect(controller.contentRevision, revision);
      expect(controller.canUndo, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
