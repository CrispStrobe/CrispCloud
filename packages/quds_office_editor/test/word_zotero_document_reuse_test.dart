import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

ZoteroCitationItem _source(String id, String title, {bool linked = false}) =>
    ZoteroCitationItem.fromJson({
      'id': id,
      'uris': linked
          ? ['http://zotero.org/users/42/items/ABCD1234']
          : <String>[],
      'itemData': {
        'id': id,
        'type': 'book',
        'title': title,
        'author': [
          {'family': 'Hassan', 'given': 'Amal'},
        ],
        'issued': {
          'date-parts': [
            [2024],
          ],
        },
        'DOI': '10.1234/$id',
        'customData': {'keep': true},
      },
      'locator': '98',
      'label': 'chapter',
      'prefix': 'see old',
      'suffix': 'old suffix',
      'suppress-author': true,
      'extraItemSetting': {'keep': true},
    });

WmlDocument _document(List<ZoteroCitationItem> sources) {
  final document = WmlDocument.empty(text: 'Before after ');
  final paragraph = document.paragraphs.single;
  for (var index = 0; index < sources.length; index++) {
    WordZotero.insertCitation(
      paragraph,
      ZoteroCitation.fromJson({
        'citationID': 'original-$index',
        'citationItems': [sources[index].toJson()],
        'properties': {
          'plainCitation': '(Original $index)',
          'formattedCitation': '(Original $index)',
          'qudsFormat': 'basic-author-year',
          'extraCitationSetting': 'keep',
        },
      }),
    );
    paragraph.inlines.add(WmlRun(text: ' '));
  }
  return document;
}

Finder _key(String key) => find.byKey(ValueKey(key));

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget, reason: '$finder');
  await tester.tap(finder);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: 'After $finder');
}

Future<WordEditorController> _open(
  WidgetTester tester, {
  List<ZoteroCitationItem>? sources,
  bool readOnly = false,
  bool trackChanges = false,
  Size size = const Size(1200, 1000),
  double scale = 1,
  TextDirection direction = TextDirection.ltr,
  List<ZoteroHttpRequest>? requests,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final document = _document(
    sources ?? [_source('offline', 'Stored research')],
  );
  document.trackRevisions = trackChanges;
  final controller = WordEditorController(
    document: document,
    config: OfficeSurfaceConfig(
      mode: readOnly
          ? OfficeInteractionMode.selecting
          : OfficeInteractionMode.editing,
    ),
  );
  controller.caret.logicalIndex = 7;
  controller.caret.collapseSelection();
  addTearDown(controller.dispose);
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
            onPressed: () => showWordZoteroDialog(
              context,
              controller: controller,
              transport: requests == null
                  ? null
                  : (request) async {
                      requests.add(request);
                      throw StateError(
                        'Stored-source workflows must not fetch.',
                      );
                    },
            ),
            child: const Text('Open references'),
          ),
        ),
      ),
    ),
  );
  await _tap(tester, find.text('Open references'));
  await _tap(tester, find.text('Document'));
  return controller;
}

Future<void> _chooseCited(WidgetTester tester, {int index = 0}) async {
  await _tap(tester, _key('zotero-cited-references'));
  final list = _key('zotero-document-source-list');
  final row = _key('zotero-document-source-$index');
  await tester.ensureVisible(list);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    row,
    140,
    scrollable: find.descendant(
      of: list,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    ),
  );
  await _tap(tester, find.descendant(of: row, matching: find.byType(Checkbox)));
  await _tap(tester, _key('zotero-document-sources-apply'));
}

Future<void> _loadImport(WidgetTester tester, String id, String title) async {
  await _tap(tester, find.text('Import CSL JSON'));
  await tester.enterText(
    _key('zotero-csl-import'),
    jsonEncode([_source(id, title).itemData]),
  );
  await _tap(tester, find.widgetWithText(OutlinedButton, 'Load references'));
}

void main() {
  testWidgets(
    'reuses stored source offline with fresh options and one undo step',
    (tester) async {
      final requests = <ZoteroHttpRequest>[];
      final original = _source('offline', 'Stored research');
      final controller = await _open(
        tester,
        sources: [original],
        requests: requests,
      );
      final initialInstruction = controller.zoteroFields.single.instruction;
      final revision = controller.contentRevision;

      await _chooseCited(tester);
      expect(controller.contentRevision, revision);
      expect(controller.canUndo, isFalse);
      await _tap(tester, _key('zotero-cite-document-selection'));
      await _tap(tester, _key('zotero-composer-apply'));

      expect(controller.zoteroFields, hasLength(2));
      final added = controller.zoteroFields.first.citation!;
      expect(added.citationId, isNot('original-0'));
      final item = added.items.single;
      expect(item.itemData, original.itemData);
      expect(item.toJson()['extraItemSetting'], {'keep': true});
      expect([
        item.locator,
        item.label,
        item.prefix,
        item.suffix,
      ], everyElement(isEmpty));
      expect(item.suppressAuthor, isFalse);
      expect(item.authorOnly, isFalse);
      expect(controller.zoteroFields.last.instruction, initialInstruction);
      expect(controller.contentRevision, greaterThan(revision));
      expect(requests, isEmpty);
      final reopened = WordZotero.fields(
        WordDeserializer().readBytes(controller.saveBytes()),
      );
      expect(reopened.first.citation!.items.single.toJson(), item.toJson());
      await _tap(tester, find.byTooltip('Close Zotero'));
      controller.undo();
      expect(controller.zoteroFields.single.instruction, initialInstruction);
      expect(controller.canUndo, isFalse);
      controller.redo();
      expect(controller.zoteroFields.first.citation!.toJson(), added.toJson());
    },
  );

  testWidgets(
    'document and imported selections retain chosen order across tabs',
    (tester) async {
      final controller = await _open(tester);
      await _loadImport(tester, 'imported', 'Imported research');
      await _tap(
        tester,
        find.widgetWithText(CheckboxListTile, 'Imported research'),
      );
      await _tap(tester, find.text('Document'));
      await _chooseCited(tester);
      expect(find.text('2 selected across all tabs'), findsOneWidget);
      await _tap(tester, _key('zotero-review-document-selection'));
      expect(find.text('1. Imported research'), findsOneWidget);
      expect(find.text('2. Stored research'), findsOneWidget);
      await _tap(tester, _key('zotero-selection-cancel'));
      await _tap(tester, _key('zotero-cite-document-selection'));
      await _tap(tester, _key('zotero-composer-apply'));
      expect(
        controller.zoteroFields.first.citation!.items.map(
          (item) => item.itemData!['title'],
        ),
        ['Imported research', 'Stored research'],
      );
    },
  );

  testWidgets(
    'selection and citation cancellation leave document and undo untouched',
    (tester) async {
      final controller = await _open(tester);
      final before = controller.zoteroFields.single.instruction;
      final revision = controller.contentRevision;
      await _tap(tester, _key('zotero-cited-references'));
      await _tap(tester, _key('zotero-document-source-0'));
      await _tap(tester, _key('zotero-document-sources-cancel'));
      expect(_key('zotero-cite-document-selection'), findsNothing);
      await _chooseCited(tester);
      await _tap(tester, _key('zotero-cite-document-selection'));
      await _tap(tester, _key('zotero-composer-remove-0'));
      await _tap(tester, _key('zotero-composer-cancel'));
      expect(controller.zoteroFields.single.instruction, before);
      expect(controller.contentRevision, revision);
      expect(controller.canUndo, isFalse);
      expect(find.text('1 selected across all tabs'), findsOneWidget);
    },
  );

  for (final stage in ['source picker', 'composer']) {
    testWidgets('changed caret rejects the staged $stage without mutation', (
      tester,
    ) async {
      final controller = await _open(tester);
      final before = controller.zoteroFields.single.instruction;
      final revision = controller.contentRevision;
      if (stage == 'source picker') {
        await _tap(tester, _key('zotero-cited-references'));
        await _tap(tester, _key('zotero-document-source-0'));
      } else {
        await _chooseCited(tester);
        await _tap(tester, _key('zotero-cite-document-selection'));
      }
      controller.caret.logicalIndex = 2;
      controller.caret.collapseSelection();
      await _tap(
        tester,
        _key(
          stage == 'source picker'
              ? 'zotero-document-sources-apply'
              : 'zotero-composer-apply',
        ),
      );
      expect(
        find.textContaining(
          stage == 'source picker'
              ? 'source selection changed'
              : 'insertion point changed',
        ),
        findsOneWidget,
      );
      expect(controller.zoteroFields.single.instruction, before);
      expect(controller.contentRevision, revision);
      expect(controller.canUndo, isFalse);
    });
  }

  for (final mode in ['read-only', 'tracking']) {
    testWidgets(
      '$mode allows stored inspection and copying but disables insertion',
      (tester) async {
        final copies = <String>[];
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          if (call.method == 'Clipboard.setData') {
            copies.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
        addTearDown(
          () =>
              messenger.setMockMethodCallHandler(SystemChannels.platform, null),
        );
        final requests = <ZoteroHttpRequest>[];
        final controller = await _open(
          tester,
          readOnly: mode == 'read-only',
          trackChanges: mode == 'tracking',
          requests: requests,
        );
        final revision = controller.contentRevision;
        await _tap(tester, _key('zotero-cited-references'));
        await _tap(tester, _key('zotero-document-source-details-0'));
        expect(find.byType(SelectableText), findsWidgets);
        await _tap(tester, _key('zotero-copy-stored-reference-details'));
        expect(copies.single, contains('Stored research'));
        await _tap(tester, find.widgetWithText(TextButton, 'Close'));
        await _tap(tester, _key('zotero-document-source-0'));
        await _tap(tester, _key('zotero-document-sources-apply'));
        expect(
          tester
              .widget<OutlinedButton>(_key('zotero-cite-document-selection'))
              .onPressed,
          isNull,
        );
        await _tap(tester, _key('zotero-copy-document-selection'));
        expect(
          (jsonDecode(copies.last) as List).single['title'],
          'Stored research',
        );
        expect(controller.contentRevision, revision);
        expect(controller.canUndo, isFalse);
        expect(requests, isEmpty);
      },
    );
  }

  testWidgets(
    'editing a citation adds loaded sources in a single undoable update',
    (tester) async {
      final controller = await _open(tester);
      final original = controller.zoteroFields.single.citation!;
      await _loadImport(tester, 'addition', 'Additional study');
      await _tap(tester, find.text('Document'));
      await _tap(tester, find.byTooltip('Reference actions'));
      await _tap(tester, find.text('Edit citation'));
      await _tap(tester, _key('zotero-composer-add-sources'));
      await tester.enterText(
        _key('zotero-composer-source-search'),
        'Additional',
      );
      await tester.pumpAndSettle();
      await _tap(
        tester,
        find.widgetWithText(CheckboxListTile, 'Additional study'),
      );
      await _tap(tester, _key('zotero-composer-source-add'));
      await _tap(tester, _key('zotero-composer-up-1'));
      await _tap(tester, _key('zotero-composer-apply'));
      final updated = controller.zoteroFields.single.citation!;
      expect(updated.citationId, original.citationId);
      expect(updated.properties['extraCitationSetting'], 'keep');
      expect(updated.items.map((item) => item.itemData!['title']), [
        'Additional study',
        'Stored research',
      ]);
      expect(updated.items.last.toJson(), original.items.single.toJson());
      expect(updated.items.first.locator, isEmpty);
      await _tap(tester, find.byTooltip('Close Zotero'));
      controller.undo();
      expect(
        controller.zoteroFields.single.citation!.toJson(),
        original.toJson(),
      );
      expect(controller.canUndo, isFalse);
      controller.redo();
      expect(
        controller.zoteroFields.single.citation!.toJson(),
        updated.toJson(),
      );
    },
  );

  testWidgets(
    'oversized alias catalog reports an error before opening the composer',
    (tester) async {
      final source = ZoteroCitationItem.fromJson({
        ..._source('linked', 'Large alias history').toJson(),
        'uris': [
          for (var index = 0; index < 10001; index++)
            'http://zotero.org/users/42/items/S${index.toString().padLeft(7, '0')}',
        ],
      });
      final controller = await _open(tester, sources: [source]);
      final before = controller.zoteroFields.single.instruction;
      final revision = controller.contentRevision;
      await _tap(tester, find.byTooltip('Reference actions'));
      await _tap(tester, find.text('Edit citation'));
      expect(_key('zotero-citation-composer'), findsNothing);
      expect(
        find.textContaining('10,000 Zotero source aliases'),
        findsOneWidget,
      );
      expect(controller.zoteroFields.single.instruction, before);
      expect(controller.contentRevision, revision);
      expect(controller.canUndo, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  for (final direction in TextDirection.values) {
    testWidgets(
      'cited-source insertion works at 320x480 doubled text ${direction.name}',
      (tester) async {
        final controller = await _open(
          tester,
          size: const Size(320, 480),
          scale: 2,
          direction: direction,
        );
        await _chooseCited(tester);
        await _tap(tester, _key('zotero-cite-document-selection'));
        await _tap(tester, _key('zotero-composer-apply'));
        expect(controller.zoteroFields, hasLength(2));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
