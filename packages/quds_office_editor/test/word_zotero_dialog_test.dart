import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _offlineSource = <String, dynamic>{
  'id': 'offline-paper',
  'type': 'article-journal',
  'title': 'A research source',
  'author': [
    {'family': 'Hassan', 'given': 'Amal'},
  ],
  'issued': {
    'date-parts': [
      [2024],
    ],
  },
};

Future<WordEditorController> _openDialog(
  WidgetTester tester, {
  ZoteroTransport? transport,
  ZoteroTransport? localTransport,
  ZoteroSession? session,
  Future<void> Function(String? apiKey)? persistApiKey,
  WmlDocument? document,
  Size size = const Size(1200, 900),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = WordEditorController(
    document: document ?? WmlDocument.empty(text: 'Before after'),
  );
  controller.caret.logicalIndex = 7;
  controller.caret.collapseSelection();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showWordZoteroDialog(
              context,
              controller: controller,
              transport: transport,
              localTransport: localTransport,
              session: session,
              persistApiKey: persistApiKey,
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

Future<void> _importAndCompose(WidgetTester tester) async {
  final tab = find.text('Import CSL JSON');
  await tester.ensureVisible(tab);
  await tester.pump();
  await tester.tap(tab);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('zotero-csl-import')),
    jsonEncode({
      'items': [_offlineSource],
    }),
  );
  final load = find.widgetWithText(OutlinedButton, 'Load references');
  await tester.ensureVisible(load);
  await tester.pump();
  await tester.tap(load);
  await tester.pumpAndSettle();
  final source = find.widgetWithText(CheckboxListTile, 'A research source');
  await tester.ensureVisible(source);
  await tester.pump();
  await tester.tap(source);
  await tester.pumpAndSettle();
  final insert = find.widgetWithText(
    FilledButton,
    'Insert 1 selected source(s)',
  );
  await tester.ensureVisible(insert);
  await tester.pump();
  await tester.tap(insert);
  // The parent may keep an indeterminate busy indicator under this modal.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  expect(find.text('Insert Zotero citation'), findsOneWidget);
}

Finder _composerButton(String text) => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.widgetWithText(FilledButton, text),
);

Map<String, dynamic> _apiItem(String key, String title) => {
  'key': key,
  'version': 1,
  'library': {'type': 'user', 'id': 42},
  'data': {
    'key': key,
    'itemType': 'journalArticle',
    'title': title,
    'date': '2024',
    'creators': [
      {'creatorType': 'author', 'firstName': 'Amal', 'lastName': 'Hassan'},
    ],
  },
  'csljson': {..._offlineSource, 'id': '999/$key', 'title': title},
};

ZoteroHttpResponse _json(
  Object body, {
  Map<String, String> headers = const {},
}) => ZoteroHttpResponse(
  statusCode: 200,
  body: jsonEncode(body),
  headers: headers,
);

void _expectNoSavedSecret(WordEditorController controller, String secret) {
  final zip = ZipReader.open(MemoryByteSource(controller.saveBytes()));
  for (final entry in zip.entries.where((entry) => !entry.isDirectory)) {
    expect(
      utf8.decode(zip.read(entry.fileName), allowMalformed: true),
      isNot(contains(secret)),
      reason: entry.fileName,
    );
  }
}

const _localItemUri = 'http://zotero.org/users/local/LOCALKEY/items/ABCD1234';

Map<String, Object?> _localRecord({
  String uri = _localItemUri,
  String title = 'Desktop source',
  String family = 'Updated',
}) => {
  ..._apiItem('ABCD1234', title),
  'library': {'type': 'user', 'id': 0},
  'csljson': jsonEncode([
    {
      ..._offlineSource,
      'id': uri,
      'title': title,
      'author': [
        {'family': family},
      ],
      'issued': {
        'date-parts': [
          [2025],
        ],
      },
    },
  ]),
  'citation': '<span>Styled $family citation</span>',
};

WmlDocument _linkedDocument(
  List<List<String>> sourceUris, {
  String cachedText = '(Original)',
}) {
  final document = WmlDocument.empty(text: 'Before after');
  for (var index = 0; index < sourceUris.length; index++) {
    WordZotero.insertCitation(
      document.paragraphs.single,
      ZoteroCitation.fromJson({
        'citationID': 'linked-$index',
        'citationItems': [
          {
            'id': 'source-$index',
            'uris': sourceUris[index],
            'itemData': {..._offlineSource, 'id': 'source-$index'},
            'locator': '12',
            'label': 'page',
            'prefix': 'see',
            'extraItemSetting': {'keep': true},
          },
        ],
        'properties': {
          'plainCitation': cachedText,
          'formattedCitation': cachedText,
          'qudsFormat': 'basic-author-year',
          'extraCitationSetting': 'keep',
        },
      }),
    );
  }
  return document;
}

class _DesktopLibrary {
  _DesktopLibrary({this.serverId = 'desktop-library'})
    : records = [_localRecord()];

  final String? serverId;
  List<Map<String, Object?>> records;
  String bibliographyHtml = '<div>Updated (2025). Desktop source.</div>';
  final requests = <ZoteroHttpRequest>[];

  Future<ZoteroHttpResponse> transport(ZoteroHttpRequest request) async {
    requests.add(request);
    expect(request.uri.host, 'localhost');
    expect(request.headers.containsKey('Zotero-API-Key'), isFalse);
    final headers = <String, String>{
      'Zotero-Server-ID': ?serverId,
      'Last-Modified-Version': '9',
    };
    if (request.uri.path == '/api/') {
      return ZoteroHttpResponse(
        statusCode: 200,
        body: 'Nothing to see here.',
        headers: {...headers, 'Zotero-API-Version': '3'},
      );
    }
    switch (request.uri.path) {
      case '/api/users/0/groups':
      case '/api/users/0/collections':
        return _json(<Object>[], headers: headers);
      case '/api/users/0/items/top':
        return _json(records, headers: headers);
      case '/api/users/0/items/ABCD1234':
        return _json(records.single, headers: headers);
      case '/api/users/0/items':
        final keys = request.uri.queryParameters['itemKey']!.split(',');
        final selected = records
            .where((record) => keys.contains(record['key']))
            .toList();
        if (request.uri.queryParameters['format'] == 'json') {
          return _json(
            selected,
            headers: {...headers, 'Total-Results': '${selected.length}'},
          );
        }
        return ZoteroHttpResponse(
          statusCode: 200,
          headers: headers,
          body: request.uri.queryParameters['format'] == 'bib'
              ? bibliographyHtml
              : 'TY  - JOUR\nTI  - Desktop source\nER  - \n',
        );
      default:
        throw StateError('Unexpected local request: ${request.uri.path}');
    }
  }
}

Future<void> _connectDesktop(WidgetTester tester) async {
  final connect = find.byKey(const ValueKey('zotero-connect-desktop'));
  await tester.ensureVisible(connect);
  await tester.tap(connect);
  await tester.pumpAndSettle();
}

Future<void> _selectDesktopItem(WidgetTester tester) async {
  final source = find.widgetWithText(CheckboxListTile, 'Desktop source');
  await tester.ensureVisible(source);
  await tester.tap(source);
  await tester.pumpAndSettle();
}

Future<void> _documentAction(
  WidgetTester tester,
  String label, {
  bool opensReview = false,
}) async {
  await tester.tap(find.text('Document'));
  await tester.pumpAndSettle();
  final action = find.text(label);
  await tester.ensureVisible(action);
  // A long document-tools header needs a layout frame after scrolling.
  await tester.pump();
  await tester.tap(action);
  if (opensReview) {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  } else {
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('unsynced refresh keeps URI aliases and unknown citation data', (
    tester,
  ) async {
    const original =
        'https://www.zotero.org/users/local/LOCALKEY/items/ABCD1234';
    final desktop = _DesktopLibrary(serverId: null);
    final controller = await _openDialog(
      tester,
      session: ZoteroSession()..useLocal = true,
      localTransport: desktop.transport,
      document: _linkedDocument([
        [original],
      ]),
    );
    await _connectDesktop(tester);
    final revision = controller.contentRevision;
    await _documentAction(tester, 'Refresh basic citations');
    final field = controller.zoteroFields.single;
    final item = field.citation!.items.single;
    expect(field.cachedText, '(see Updated, 2025, p. 12)');
    expect(item.uris, [original]);
    expect(item.id, 'source-0');
    expect(item.itemData!['id'], 'source-0');
    expect(item.itemData!['title'], 'Desktop source');
    expect(item.toJson()['extraItemSetting'], {'keep': true});
    expect(item.locator, '12');
    expect(item.prefix, 'see');
    expect(field.citation!.properties['extraCitationSetting'], 'keep');
    expect(controller.contentRevision, greaterThan(revision));
    expect(desktop.requests.last.uri.path, '/api/users/0/items/ABCD1234');
    expect(
      desktop.requests.last.uri.queryParameters['include'],
      'data,csljson',
    );
    expect(
      desktop.requests.last.uri.queryParameters.containsKey('style'),
      isFalse,
    );
    expect(
      desktop.requests.last.uri.queryParameters.containsKey('locale'),
      isFalse,
    );
    final reopened = WordDeserializer().readBytes(controller.saveBytes());
    expect(WordZotero.fields(reopened).single.citation!.items.single.uris, [
      original,
    ]);
    _expectNoSavedSecret(controller, '/users/0');
    await tester.tap(find.byTooltip('Close Zotero'));
    await tester.pumpAndSettle();
    controller.undo();
    expect(controller.zoteroFields.single.cachedText, '(Original)');
    expect(tester.takeException(), isNull);
  });

  testWidgets('wrong desktop profile with the same item key cannot refresh', (
    tester,
  ) async {
    final desktop = _DesktopLibrary(serverId: null);
    final controller = await _openDialog(
      tester,
      session: ZoteroSession()..useLocal = true,
      localTransport: desktop.transport,
      document: _linkedDocument([
        [_localItemUri],
      ]),
    );
    await _connectDesktop(tester);
    desktop.records = [
      _localRecord(
        uri: 'http://zotero.org/users/local/OTHERKEY/items/ABCD1234',
        family: 'Wrong profile',
      ),
    ];
    final before = controller.zoteroFields.single.instruction;
    final revision = controller.contentRevision;
    await _documentAction(tester, 'Refresh basic citations');
    expect(controller.zoteroFields.single.instruction, before);
    expect(controller.zoteroFields.single.cachedText, '(Original)');
    expect(controller.contentRevision, revision);
    expect(controller.canUndo, isFalse);
    expect(desktop.requests.last.uri.path, '/api/users/0/items/ABCD1234');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'online operations reject local-only references before a request',
    (tester) async {
      final requests = <ZoteroHttpRequest>[];
      final controller = await _openDialog(
        tester,
        transport: (request) async {
          requests.add(request);
          return _json(_apiItem('ABCD1234', 'Must not be used'));
        },
        document: _linkedDocument([
          [_localItemUri],
        ]),
      );
      final revision = controller.contentRevision;
      for (final action in ['Refresh basic citations', 'Zotero bibliography']) {
        await _documentAction(tester, action);
        expect(find.textContaining('unsynced desktop library'), findsOneWidget);
        expect(requests, isEmpty);
        expect(controller.contentRevision, revision);
        expect(controller.zoteroFields.single.cachedText, '(Original)');
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'online refresh can use a numeric alias while retaining old local URI',
    (tester) async {
      const remote = 'https://www.zotero.org/users/42/items/ABCD1234';
      final requests = <ZoteroHttpRequest>[];
      final controller = await _openDialog(
        tester,
        transport: (request) async {
          requests.add(request);
          return _json(_apiItem('ABCD1234', 'Account source'));
        },
        document: _linkedDocument([
          [_localItemUri, remote],
        ]),
      );
      await _documentAction(tester, 'Refresh basic citations');
      expect(requests, hasLength(1));
      expect(requests.single.uri.path, '/users/42/items/ABCD1234');
      expect(controller.zoteroFields.single.citation!.items.single.uris, [
        _localItemUri,
        remote,
      ]);
      expect(
        controller
            .zoteroFields
            .single
            .citation!
            .items
            .single
            .itemData!['title'],
        'Account source',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'different local profiles are not combined through the same route',
    (tester) async {
      final desktop = _DesktopLibrary();
      final controller = await _openDialog(
        tester,
        session: ZoteroSession()..useLocal = true,
        localTransport: desktop.transport,
        document: _linkedDocument([
          [_localItemUri],
          ['http://zotero.org/users/local/OTHERKEY/items/ABCD1234'],
        ]),
      );
      await _connectDesktop(tester);
      final requestCount = desktop.requests.length;
      final revision = controller.contentRevision;
      for (final action in ['Refresh basic citations', 'Zotero bibliography']) {
        await _documentAction(tester, action);
        expect(desktop.requests, hasLength(requestCount));
        expect(controller.contentRevision, revision);
        expect(controller.zoteroFields, hasLength(2));
        expect(controller.canUndo, isFalse);
        expect(find.byType(AlertDialog), findsNothing);
      }
      expect(tester.takeException(), isNull);
    },
  );

  for (final mismatch in [false, true]) {
    testWidgets(
      'unsynced single-source preview verifies identity: mismatch $mismatch',
      (tester) async {
        final desktop = _DesktopLibrary(serverId: null);
        final controller = await _openDialog(
          tester,
          session: ZoteroSession()..useLocal = true,
          localTransport: desktop.transport,
        );
        await _connectDesktop(tester);
        await _selectDesktopItem(tester);
        if (mismatch) {
          desktop.records = [
            _localRecord(
              uri: 'http://zotero.org/users/local/OTHERKEY/items/ABCD1234',
              family: 'Wrong profile',
            ),
          ];
        }
        final insert = find.widgetWithText(
          OutlinedButton,
          'Insert basic citation',
        );
        await tester.ensureVisible(insert);
        await tester.tap(insert);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        final preview = tester.widget<TextField>(
          find.byKey(const ValueKey('zotero-citation-preview')),
        );
        final before = preview.controller!.text;
        final style = find.text('Use apa single-source preview');
        await tester.ensureVisible(style);
        await tester.tap(style);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(
          preview.controller!.text,
          mismatch ? before : 'Styled Updated citation',
        );
        expect(desktop.requests.last.uri.path, '/api/users/0/items/ABCD1234');
        expect(
          desktop.requests.last.uri.queryParameters['include'],
          'data,csljson,citation,bib',
        );
        expect(controller.zoteroFields, isEmpty);
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.widgetWithText(TextButton, 'Cancel'),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'unsynced selected export verifies sources before copying reference data',
    (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add(
              (call.arguments as Map<Object?, Object?>)['text']! as String,
            );
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });
      final desktop = _DesktopLibrary();
      final controller = await _openDialog(
        tester,
        session: ZoteroSession()..useLocal = true,
        localTransport: desktop.transport,
      );
      await _connectDesktop(tester);
      await _selectDesktopItem(tester);
      final revision = controller.contentRevision;
      final export = find.text('Export selected ▾');
      await tester.ensureVisible(export);
      await tester.tap(export);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy ris'));
      await tester.pumpAndSettle();
      expect(copied, ['TY  - JOUR\nTI  - Desktop source\nER  - \n']);
      final operation = desktop.requests.skip(4).toList();
      expect(operation, hasLength(2));
      expect(operation.first.uri.queryParameters['format'], 'json');
      expect(operation.first.uri.queryParameters['include'], 'data,csljson');
      expect(operation.last.uri.queryParameters['format'], 'ris');
      expect(
        operation.every(
          (request) => request.headers['Zotero-Server-ID'] == 'desktop-library',
        ),
        isTrue,
      );
      expect(controller.contentRevision, revision);
      expect(controller.zoteroFields, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'changed profile cannot copy another source under a selected item key',
    (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add(
              (call.arguments as Map<Object?, Object?>)['text']! as String,
            );
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });
      final desktop = _DesktopLibrary();
      final controller = await _openDialog(
        tester,
        session: ZoteroSession()..useLocal = true,
        localTransport: desktop.transport,
      );
      await _connectDesktop(tester);
      await _selectDesktopItem(tester);
      desktop.records = [
        _localRecord(
          uri: 'http://zotero.org/users/local/OTHERKEY/items/ABCD1234',
        ),
      ];
      final export = find.text('Export selected ▾');
      await tester.ensureVisible(export);
      await tester.tap(export);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy ris'));
      await tester.pumpAndSettle();
      expect(copied, isEmpty);
      final operation = desktop.requests.skip(4).toList();
      expect(operation, hasLength(1));
      expect(operation.single.uri.queryParameters['format'], 'json');
      expect(controller.zoteroFields, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unsynced bibliography verifies selection and requires review before insertion',
    (tester) async {
      final desktop = _DesktopLibrary();
      final controller = await _openDialog(
        tester,
        session: ZoteroSession()..useLocal = true,
        localTransport: desktop.transport,
        document: _linkedDocument([
          [_localItemUri],
        ]),
      );
      await _connectDesktop(tester);
      final revision = controller.contentRevision;
      await _documentAction(tester, 'Zotero bibliography', opensReview: true);
      expect(find.text('Review Zotero bibliography'), findsOneWidget);
      expect(controller.zoteroFields, hasLength(1));
      expect(controller.contentRevision, revision);
      final operation = desktop.requests.skip(4).toList();
      expect(operation, hasLength(2));
      expect(operation.first.uri.queryParameters['format'], 'json');
      expect(operation.last.uri.queryParameters['format'], 'bib');
      await tester.tap(find.widgetWithText(FilledButton, 'Use bibliography'));
      await tester.pumpAndSettle();
      expect(controller.zoteroFields, hasLength(2));
      expect(
        controller.zoteroFields
            .singleWhere((field) => field.kind == ZoteroFieldKind.bibliography)
            .cachedText,
        'Updated (2025). Desktop source.',
      );
      expect(controller.contentRevision, greaterThan(revision));
      expect(controller.canUndo, isTrue);
      _expectNoSavedSecret(controller, '/users/0');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reviewed bibliography keeps rich runs through save and undo', (
    tester,
  ) async {
    final desktop = _DesktopLibrary()
      ..bibliographyHtml =
          '<div class="csl-bib-body">'
          '<div class="csl-entry"><div class="csl-left-margin">1.</div>'
          '<div class="csl-right-inline"><i>Book title</i>. '
          '<b>Journal</b> H<sub>2</sub>O<sup>3</sup></div></div></div>';
    final controller = await _openDialog(
      tester,
      session: ZoteroSession()..useLocal = true,
      localTransport: desktop.transport,
      document: _linkedDocument([
        [_localItemUri],
      ]),
    );
    await _connectDesktop(tester);
    final revision = controller.contentRevision;
    await _documentAction(tester, 'Zotero bibliography', opensReview: true);
    expect(
      find.byKey(const ValueKey('zotero-formatted-preview')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('zotero-bibliography-text')),
      findsNothing,
    );
    expect(controller.contentRevision, revision);
    await tester.tap(find.widgetWithText(FilledButton, 'Use bibliography'));
    await tester.pumpAndSettle();
    final field = controller.zoteroFields.last;
    expect(field.cachedText, '1. Book title. Journal H2O3');
    expect(field.canEdit, isTrue);
    void expectStyles(WmlZoteroField field) {
      final runs = field.paragraph.inlines.whereType<WmlRun>().toList();
      expect(
        runs.any(
          (run) => run.text.trim() == 'Book title' && run.properties.italic,
        ),
        isTrue,
      );
      expect(
        runs.any((run) => run.text.trim() == 'Journal' && run.properties.bold),
        isTrue,
      );
      expect(
        runs.any(
          (run) =>
              run.text == '2' &&
              run.properties.vertAlign == WmlVertAlign.subscript,
        ),
        isTrue,
      );
      expect(
        runs.any(
          (run) =>
              run.text == '3' &&
              run.properties.vertAlign == WmlVertAlign.superscript,
        ),
        isTrue,
      );
    }

    expectStyles(field);
    final reopened = WordDeserializer().readBytes(controller.saveBytes());
    expectStyles(WordZotero.fields(reopened).last);
    controller.undo();
    expect(controller.zoteroFields, hasLength(1));
    controller.redo();
    expectStyles(controller.zoteroFields.last);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bibliography review offers an explicit editable plain result', (
    tester,
  ) async {
    final desktop = _DesktopLibrary()
      ..bibliographyHtml = '<div><i>Original title</i>.</div>';
    final controller = await _openDialog(
      tester,
      session: ZoteroSession()..useLocal = true,
      localTransport: desktop.transport,
      document: _linkedDocument([
        [_localItemUri],
      ]),
    );
    await _connectDesktop(tester);
    await _documentAction(tester, 'Zotero bibliography', opensReview: true);
    await tester.tap(find.byKey(const ValueKey('zotero-keep-formatting')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('zotero-bibliography-text')),
      'My reviewed bibliography',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Use bibliography'));
    await tester.pumpAndSettle();
    final field = controller.zoteroFields.last;
    expect(field.cachedText, 'My reviewed bibliography');
    expect(field.run!.properties.italic, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling rich bibliography review keeps history unchanged', (
    tester,
  ) async {
    final desktop = _DesktopLibrary()
      ..bibliographyHtml = '<div><b>Reviewed only</b></div>';
    final controller = await _openDialog(
      tester,
      session: ZoteroSession()..useLocal = true,
      localTransport: desktop.transport,
      document: _linkedDocument([
        [_localItemUri],
      ]),
    );
    await _connectDesktop(tester);
    final revision = controller.contentRevision;
    await _documentAction(tester, 'Zotero bibliography', opensReview: true);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(controller.zoteroFields, hasLength(1));
    expect(controller.contentRevision, revision);
    expect(controller.canUndo, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final change in ['caret', 'revision']) {
    testWidgets('a changed $change rejects a reviewed rich bibliography', (
      tester,
    ) async {
      final desktop = _DesktopLibrary()
        ..bibliographyHtml = '<div><i>Stale result</i></div>';
      final controller = await _openDialog(
        tester,
        session: ZoteroSession()..useLocal = true,
        localTransport: desktop.transport,
        document: _linkedDocument([
          [_localItemUri],
        ]),
      );
      await _connectDesktop(tester);
      await _documentAction(tester, 'Zotero bibliography', opensReview: true);
      if (change == 'caret') {
        controller.caret.logicalIndex = 0;
        controller.caret.collapseSelection();
      } else {
        controller.insertText('Changed ');
        controller.commitPendingEdits();
      }
      final revision = controller.contentRevision;
      await tester.tap(find.widgetWithText(FilledButton, 'Use bibliography'));
      await tester.pumpAndSettle();
      expect(controller.zoteroFields, hasLength(1));
      expect(controller.contentRevision, revision);
      expect(
        find.textContaining('document or insertion point changed'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('rich review and format limitation fit a narrow viewport', (
    tester,
  ) async {
    final desktop = _DesktopLibrary()
      ..bibliographyHtml =
          '<div><span style="font-variant: small-caps">Author</span>. '
          '<i>A title</i>.</div>';
    final controller = await _openDialog(
      tester,
      size: const Size(320, 640),
      session: ZoteroSession()..useLocal = true,
      localTransport: desktop.transport,
      document: _linkedDocument([
        [_localItemUri],
      ]),
    );
    await _connectDesktop(tester);
    await _documentAction(tester, 'Zotero bibliography', opensReview: true);
    expect(find.textContaining('small caps'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final use = find.widgetWithText(FilledButton, 'Use bibliography');
    await tester.ensureVisible(use);
    await tester.tap(use);
    await tester.pumpAndSettle();
    expect(controller.zoteroFields.last.cachedText, 'Author. A title.');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unchanged imported citation keeps its rich cache and native formatting metadata',
    (tester) async {
      const formatted = r'{\i native processor formatting}';
      final citation = ZoteroCitation.fromJson({
        'citationID': 'rich-import',
        'citationItems': [
          {'id': 'offline', 'itemData': _offlineSource},
        ],
        'properties': {
          'plainCitation': 'outdated metadata',
          'formattedCitation': formatted,
          'extension': {'keep': true},
        },
      });
      final document = WmlDocument.empty();
      final paragraph = document.paragraphs.single;
      paragraph.properties.fieldInstruction = citation.fieldInstruction;
      paragraph.inlines
        ..clear()
        ..addAll([
          WmlRun(text: 'A ', properties: WmlRunProps(bold: true)),
          WmlRun(text: 'title', properties: WmlRunProps(italic: true)),
        ]);
      final controller = await _openDialog(tester, document: document);
      await tester.tap(find.text('Document'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Reference actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit citation'));
      await tester.pumpAndSettle();
      final preview = tester.widget<TextField>(
        find.byKey(const ValueKey('zotero-citation-preview')),
      );
      expect(preview.controller!.text, 'A title');
      await tester.tap(_composerButton('Update citation'));
      await tester.pumpAndSettle();
      final updated = controller.zoteroFields.single;
      expect(updated.cachedText, 'A title');
      expect(updated.citation!.plainCitation, 'A title');
      expect(updated.citation!.formattedCitation, formatted);
      expect(updated.citation!.properties['extension'], {'keep': true});
      final runs = updated.paragraph.inlines.whereType<WmlRun>().toList();
      expect(runs, hasLength(2));
      expect(runs.first.properties.bold, isTrue);
      expect(runs.last.properties.italic, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'older desktop cannot render an unverified aggregate bibliography',
    (tester) async {
      final desktop = _DesktopLibrary(serverId: null);
      final controller = await _openDialog(
        tester,
        session: ZoteroSession()..useLocal = true,
        localTransport: desktop.transport,
        document: _linkedDocument([
          [_localItemUri],
        ]),
      );
      await _connectDesktop(tester);
      final revision = controller.contentRevision;
      await _documentAction(tester, 'Zotero bibliography');
      expect(
        desktop.requests.any(
          (request) => request.uri.queryParameters['format'] == 'bib',
        ),
        isFalse,
      );
      expect(find.byType(AlertDialog), findsNothing);
      expect(controller.contentRevision, revision);
      expect(controller.zoteroFields, hasLength(1));
      expect(controller.zoteroFields.single.cachedText, '(Original)');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'local source without CSL or identity is not refetched by a bare key',
    (tester) async {
      final desktop = _DesktopLibrary()
        ..records = [
          {..._localRecord(), 'csljson': null},
        ];
      final controller = await _openDialog(
        tester,
        session: ZoteroSession()..useLocal = true,
        localTransport: desktop.transport,
      );
      await _connectDesktop(tester);
      await _selectDesktopItem(tester);
      expect(
        find.textContaining('did not provide enough source data'),
        findsOneWidget,
      );
      expect(desktop.requests, hasLength(4));
      expect(controller.zoteroFields, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final identity in ['account', 'unsynced', 'citation-key']) {
    testWidgets(
      'desktop $identity source inserts without using the saved cloud key',
      (tester) async {
        const secret = 'cloud-key-never-sent-to-local-zotero';
        const key = 'ABCD1234';
        const localUri =
            'http://zotero.org/users/local/LOCALKEY/items/ABCD1234';
        final session = ZoteroSession()
          ..apiKey = secret
          ..rememberKey = true
          ..useLocal = true;
        final requests = <ZoteroHttpRequest>[];
        final writes = <String?>[];
        final controller = await _openDialog(
          tester,
          session: session,
          transport: (_) async =>
              throw StateError('Cloud transport must stay unused'),
          persistApiKey: (key) async => writes.add(key),
          localTransport: (request) async {
            requests.add(request);
            expect(request.uri.scheme, 'http');
            expect(request.uri.host, 'localhost');
            expect(request.uri.port, 23119);
            expect(request.headers.containsKey('Zotero-API-Key'), isFalse);
            expect(request.headers['Zotero-Allowed-Request'], '1');
            expect(request.followRedirects, isFalse);
            if (request.uri.path == '/api/') {
              return ZoteroHttpResponse(
                statusCode: 200,
                body: 'Nothing to see here.',
                headers: const {
                  'Zotero-API-Version': '3',
                  'Zotero-Server-ID': 'desktop-library',
                },
              );
            }
            expect(request.headers['Zotero-Server-ID'], 'desktop-library');
            final Object body;
            switch (request.uri.path) {
              case '/api/users/0/groups':
              case '/api/users/0/collections':
                body = <Object>[];
              case '/api/users/0/items/top':
                body = [
                  {
                    ..._apiItem(key, 'Desktop source'),
                    'library': {
                      'type': 'user',
                      'id': identity == 'account' ? 42 : 0,
                    },
                    'csljson': jsonEncode([
                      {
                        ..._offlineSource,
                        'title': 'Desktop source',
                        'id': identity == 'unsynced' ? localUri : 'Hassan2024',
                      },
                    ]),
                  },
                ];
              default:
                throw StateError('Unexpected desktop path');
            }
            return _json(
              body,
              headers: const {'Zotero-Server-ID': 'desktop-library'},
            );
          },
        );
        expect(find.byKey(const ValueKey('zotero-api-key')), findsNothing);
        expect(
          requests,
          isEmpty,
          reason: 'Desktop access requires an explicit connection',
        );
        await tester.tap(find.byKey(const ValueKey('zotero-connect-desktop')));
        await tester.pumpAndSettle();
        expect(requests, hasLength(4));
        expect(find.text('Desktop source'), findsOneWidget);
        final source = find.widgetWithText(CheckboxListTile, 'Desktop source');
        await tester.ensureVisible(source);
        await tester.tap(source);
        await tester.pumpAndSettle();
        if (identity == 'citation-key') {
          expect(
            find.textContaining('embedded without a Zotero link'),
            findsOneWidget,
          );
        }
        final insert = find.widgetWithText(
          OutlinedButton,
          'Insert basic citation',
        );
        await tester.ensureVisible(insert);
        await tester.tap(insert);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.tap(_composerButton('Insert citation'));
        await tester.pumpAndSettle();
        final item = controller.zoteroFields.single.citation!.items.single;
        expect(item.itemData!['title'], 'Desktop source');
        expect(item.uris, switch (identity) {
          'account' => ['http://zotero.org/users/42/items/ABCD1234'],
          'unsynced' => [localUri],
          _ => <String>[],
        });
        if (identity == 'citation-key') {
          expect(item.id, startsWith('quds-offline-'));
        }
        expect(writes, isEmpty);
        expect(session.apiKey, secret);
        expect(session.rememberKey, isTrue);
        _expectNoSavedSecret(controller, secret);
        _expectNoSavedSecret(controller, '/users/0');
        final disconnect = find.text('Disconnect desktop');
        await tester.ensureVisible(disconnect);
        await tester.tap(disconnect);
        await tester.pumpAndSettle();
        expect(session.apiKey, secret);
        expect(writes, isEmpty);
        expect(find.text('Desktop source'), findsNothing);
        expect(controller.zoteroFields, hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'switching sources makes no requests and preserves the cloud credential',
    (tester) async {
      final session = ZoteroSession()..apiKey = 'retained-cloud-key';
      var calls = 0;
      Future<ZoteroHttpResponse> transport(ZoteroHttpRequest _) async {
        calls++;
        throw StateError('Do not connect while changing a preference');
      }

      await _openDialog(
        tester,
        session: session,
        transport: transport,
        localTransport: transport,
      );
      final source = find.byKey(const ValueKey('zotero-library-source'));
      await tester.tap(source);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zotero desktop (this computer)').last);
      await tester.pumpAndSettle();
      expect(session.useLocal, isTrue);
      expect(find.byKey(const ValueKey('zotero-api-key')), findsNothing);
      await tester.tap(source);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Online Zotero library').last);
      await tester.pumpAndSettle();
      expect(session.useLocal, isFalse);
      expect(session.apiKey, 'retained-cloud-key');
      expect(calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a host without desktop transport offers only the supported source',
    (tester) async {
      final session = ZoteroSession()..useLocal = true;
      await _openDialog(tester, session: session);
      expect(session.useLocal, isFalse);
      expect(find.byKey(const ValueKey('zotero-library-source')), findsNothing);
      expect(
        find.byKey(const ValueKey('zotero-connect-desktop')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('desktop connection and errors fit a 320 by 640 viewport', (
    tester,
  ) async {
    final session = ZoteroSession()..useLocal = true;
    final controller = await _openDialog(
      tester,
      size: const Size(320, 640),
      session: session,
      localTransport: (_) async =>
          ZoteroHttpResponse(statusCode: 403, body: 'private diagnostic'),
    );
    final revision = controller.contentRevision;
    expect(tester.takeException(), isNull);
    final connect = find.byKey(const ValueKey('zotero-connect-desktop'));
    await tester.ensureVisible(connect);
    await tester.tap(connect);
    await tester.pumpAndSettle();
    expect(find.textContaining('Settings'), findsWidgets);
    expect(find.textContaining('private diagnostic'), findsNothing);
    expect(controller.contentRevision, revision);
    expect(controller.zoteroFields, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offline CSL import inserts source metadata and can be undone', (
    tester,
  ) async {
    final controller = await _openDialog(tester);
    final initialRevision = controller.contentRevision;
    await _importAndCompose(tester);
    final preview = tester.widget<TextField>(
      find.byKey(const ValueKey('zotero-citation-preview')),
    );
    expect(preview.controller!.text, '(Hassan, 2024)');
    expect(find.text('Offline embedded source'), findsOneWidget);
    await tester.tap(_composerButton('Insert citation'));
    await tester.pumpAndSettle();
    expect(
      controller.document.paragraphs.single.text,
      'Before (Hassan, 2024)after',
    );
    final field = controller.zoteroFields.single;
    expect(
      field.citation!.items.single.itemData!['title'],
      'A research source',
    );
    expect(field.citation!.items.single.uris, isEmpty);
    expect(field.citation!.properties['qudsFormat'], 'basic-author-year');
    expect(controller.contentRevision, greaterThan(initialRevision));
    expect(controller.canUndo, isTrue);
    await tester.tap(find.byTooltip('Close Zotero'));
    await tester.pumpAndSettle();
    controller.undo();
    expect(controller.document.paragraphs.single.text, 'Before after');
    expect(controller.zoteroFields, isEmpty);
    controller.redo();
    expect(
      controller.zoteroFields.single.citation!.items.single.id,
      'offline-paper',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'cancelling the citation composer leaves document and history unchanged',
    (tester) async {
      final controller = await _openDialog(tester);
      final revision = controller.contentRevision;
      await _importAndCompose(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(TextButton, 'Cancel'),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.document.paragraphs.single.text, 'Before after');
      expect(controller.zoteroFields, isEmpty);
      expect(controller.contentRevision, revision);
      expect(controller.canUndo, isFalse);
      expect(find.text('Zotero references'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final change in ['caret', 'revision']) {
    testWidgets(
      'a changed $change while the composer is open blocks stale insertion',
      (tester) async {
        final controller = await _openDialog(tester);
        await _importAndCompose(tester);
        if (change == 'caret') {
          controller.caret.logicalIndex = 0;
          controller.caret.collapseSelection();
        } else {
          controller.insertText('Changed ');
          controller.commitPendingEdits();
        }
        final text = controller.document.paragraphs.single.text;
        final revision = controller.contentRevision;
        await tester.tap(_composerButton('Insert citation'));
        await tester.pumpAndSettle();
        expect(controller.zoteroFields, isEmpty);
        expect(controller.document.paragraphs.single.text, text);
        expect(controller.contentRevision, revision);
        expect(
          find.textContaining('document or insertion point changed'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'mock Web API connection, pagination and search keep the key outside the document',
    (tester) async {
      const secret = 'test-only-secret-that-must-never-be-saved';
      final requests = <ZoteroHttpRequest>[];
      final session = ZoteroSession();
      final controller = await _openDialog(
        tester,
        session: session,
        transport: (request) async {
          requests.add(request);
          expect(request.uri.scheme, 'https');
          expect(request.uri.host, 'api.zotero.org');
          expect(request.followRedirects, isFalse);
          expect(request.headers['Zotero-API-Key'], secret);
          expect(request.uri.toString(), isNot(contains(secret)));
          switch (request.uri.path) {
            case '/keys/current':
              return _json({
                'userID': 42,
                'username': 'Researcher',
                'access': {
                  'user': {'library': true},
                },
              });
            case '/users/42/groups':
              return _json([
                {
                  'id': 77,
                  'data': {'name': 'Shared lab'},
                },
              ]);
            case '/users/42/collections':
              return _json([
                {
                  'key': 'COLL0001',
                  'data': {'name': 'Research', 'parentCollection': false},
                },
              ]);
            case '/users/42/items/top':
              if (request.uri.queryParameters['q']?.isNotEmpty == true) {
                return _json(
                  [_apiItem('IJKL9012', 'Search source')],
                  headers: {'Total-Results': '1'},
                );
              }
              if (request.uri.queryParameters['start'] == '50') {
                return _json(
                  [_apiItem('EFGH5678', 'Second source')],
                  headers: {'Total-Results': '51'},
                );
              }
              return _json(
                [_apiItem('ABCD1234', 'First source')],
                headers: {'Total-Results': '51'},
              );
            case '/users/42/items/IJKL9012':
              return _json({
                ..._apiItem('IJKL9012', 'Search source'),
                'citation': '<span>(Hassan, 2024)</span>',
              });
            default:
              fail('Unexpected request path: ${request.uri.path}');
          }
        },
      );
      await tester.enterText(
        find.byKey(const ValueKey('zotero-api-key')),
        secret,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
      await tester.pumpAndSettle();
      expect(find.text('First source'), findsOneWidget);
      expect(session.apiKey, secret);
      expect(session.rememberKey, isFalse);
      expect(find.textContaining('Connected as Researcher'), findsOneWidget);

      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      expect(find.text('Second source'), findsOneWidget);
      expect(requests.last.uri.queryParameters['start'], '50');

      final search = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Search title, creator, or year',
      );
      await tester.enterText(search, 'Hassan & 2024');
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      expect(find.text('Search source'), findsOneWidget);
      expect(requests.last.uri.queryParameters['q'], 'Hassan & 2024');
      expect(requests.last.uri.queryParameters['start'], '0');

      await tester.tap(find.widgetWithText(CheckboxListTile, 'Search source'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Insert citation'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(_composerButton('Insert citation'));
      await tester.pumpAndSettle();
      final source = controller.zoteroFields.single.citation!.items.single;
      expect(source.uris, ['http://zotero.org/users/42/items/IJKL9012']);
      expect(source.itemData!['title'], 'Search source');
      _expectNoSavedSecret(controller, secret);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unchecking Remember removes the saved key immediately without connecting',
    (tester) async {
      const secret = 'persisted-test-key-not-document-content';
      final writes = <String?>[];
      final session = ZoteroSession()
        ..apiKey = secret
        ..rememberKey = true;
      final controller = await _openDialog(
        tester,
        session: session,
        persistApiKey: (key) async {
          writes.add(key);
        },
      );
      final revision = controller.contentRevision;
      expect(writes, isEmpty);
      final checkbox = find.byType(Checkbox);
      expect(tester.widget<Checkbox>(checkbox).value, isTrue);
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      expect(writes, <String?>[null]);
      expect(session.rememberKey, isFalse);
      expect(
        session.apiKey,
        secret,
        reason: 'The existing session may stay connected.',
      );
      expect(find.textContaining('connection is session-only'), findsOneWidget);
      expect(controller.contentRevision, revision);
      expect(controller.canUndo, isFalse);
      _expectNoSavedSecret(controller, secret);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'imported bibliography customizations cannot be overwritten by basic update',
    (tester) async {
      const uri = 'http://zotero.org/users/42/items/ABCD1234';
      for (final customization in ['uncited', 'omitted', 'custom']) {
        final document = WmlDocument.empty(text: 'Before after');
        WordZotero.insertCitation(
          document.paragraphs.single,
          ZoteroCitation(
            citationId: 'imported-citation',
            plainCitation: '(Hassan, 2024)',
            items: [
              ZoteroCitationItem.fromJson({
                'id': 'offline-paper',
                'itemData': _offlineSource,
              }),
            ],
          ),
        );
        document.sections.single.blocks.add(
          WordZotero.bibliography(
            text: 'Preserved bibliography',
            metadata: {
              'uncited': <dynamic>[],
              'omitted': <dynamic>[],
              'custom': <dynamic>[],
              customization: customization == 'custom'
                  ? [
                      [uri, 'Custom reference'],
                    ]
                  : [
                      [uri],
                    ],
            },
          ),
        );
        final controller = await _openDialog(tester, document: document);
        final before = controller.zoteroFields.last;
        final metadata = jsonEncode(before.metadata);
        final revision = controller.contentRevision;
        final texts = document.paragraphs
            .map((paragraph) => paragraph.text)
            .toList();
        await tester.tap(find.text('Document'));
        await tester.pumpAndSettle();
        final row = find.ancestor(
          of: find.text('Preserved bibliography'),
          matching: find.byType(ListTile),
        );
        await tester.ensureVisible(row);
        await tester.pump();
        await tester.tap(
          find.descendant(
            of: row,
            matching: find.byTooltip('Reference actions'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Update basic bibliography'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('additions, exclusions, or custom entries'),
          findsOneWidget,
          reason: customization,
        );
        expect(find.byType(AlertDialog), findsNothing);
        expect(
          controller.zoteroFields.last.cachedText,
          'Preserved bibliography',
        );
        expect(jsonEncode(controller.zoteroFields.last.metadata), metadata);
        expect(document.paragraphs.map((paragraph) => paragraph.text), texts);
        expect(controller.contentRevision, revision);
        expect(controller.canUndo, isFalse);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Close Zotero'));
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets('dialog, offline import and composer fit a 320 by 640 viewport', (
    tester,
  ) async {
    await _openDialog(tester, size: const Size(320, 640));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Document'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await _importAndCompose(tester);
    expect(tester.takeException(), isNull);
    final button = _composerButton('Insert citation');
    await tester.ensureVisible(button);
    expect(tester.getRect(button).bottom, lessThanOrEqualTo(640));
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Cancel'),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
