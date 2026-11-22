import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

WmlDocument _document({bool locked = false}) {
  final document = WmlDocument.empty(text: 'Before ');
  WordZotero.insertCitation(
    document.paragraphs.single,
    ZoteroCitation(
      citationId: 'citation',
      plainCitation: '(Hassan, 2024)',
      items: [
        ZoteroCitationItem.fromCsl(
          uris: const ['http://zotero.org/users/42/items/ABCD1234'],
          itemData: {
            'id': 'source',
            'type': 'book',
            'title': 'Stored research',
            'author': [
              {'family': 'Hassan'},
            ],
            'issued': {
              'date-parts': [
                [2024],
              ],
            },
          },
        ),
      ],
    ),
  );
  final citation = WordZotero.fields(document).single;
  citation.run!.properties.italic = true;
  if (locked) citation.run!.fieldLocked = true;
  document.sections.single.blocks.add(
    WordZotero.bibliography(text: 'Hassan. Stored research. 2024.'),
  );
  return document;
}

WmlDocument _damagedDocument({bool locked = false}) {
  final document = _document(locked: locked);
  final fields = WordZotero.fields(document);
  fields.first.run!.fieldInstruction =
      ' ADDIN ZOTERO_ITEM CSL_CITATION {broken} ';
  fields.last.run!.fieldInstruction =
      ' ADDIN ZOTERO_BIBL {broken} CSL_BIBLIOGRAPHY ';
  return document;
}

Finder _key(String value) => find.byKey(ValueKey(value));

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<WordEditorController> _open(
  WidgetTester tester, {
  WmlDocument? document,
  int offset = 8,
  WordZoteroTab? initialTab,
  bool readOnly = false,
  Size size = const Size(1200, 1000),
  double scale = 1,
  TextDirection direction = TextDirection.ltr,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final controller = WordEditorController(
    document: document ?? _document(),
    config: OfficeSurfaceConfig(
      mode: readOnly
          ? OfficeInteractionMode.selecting
          : OfficeInteractionMode.editing,
    ),
  );
  controller.caret.logicalIndex = offset;
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
              initialTab: initialTab,
            ),
            child: const Text('Open references'),
          ),
        ),
      ),
    ),
  );
  await _tap(tester, find.text('Open references'));
  return controller;
}

void main() {
  testWidgets('a citation at the caret opens its document editing tools', (
    tester,
  ) async {
    final controller = await _open(tester);
    expect(find.text('Citation at the caret'), findsOneWidget);
    expect(_key('zotero-edit-current').hitTestable(), findsOneWidget);
    await tester.tap(_key('zotero-edit-current'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Edit Zotero citation'), findsOneWidget);
    expect(find.text('Stored research'), findsWidgets);
    await _tap(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Cancel'),
      ),
    );
    expect(controller.canUndo, isFalse);
    expect(controller.zoteroFields, hasLength(2));
  });

  testWidgets('hosts can explicitly open Library from an existing citation', (
    tester,
  ) async {
    await _open(tester, initialTab: WordZoteroTab.library);
    expect(_key('zotero-edit-current').hitTestable(), findsNothing);
    expect(find.text('Import CSL JSON'), findsOneWidget);
    await _tap(tester, find.text('Document'));
    expect(_key('zotero-edit-current').hitTestable(), findsOneWidget);
  });

  testWidgets('a plain-text caret keeps the Library as the default page', (
    tester,
  ) async {
    await _open(tester, offset: 2);
    expect(_key('zotero-unlink-all').hitTestable(), findsNothing);
    await _tap(tester, find.text('Document'));
    expect(_key('zotero-unlink-all').hitTestable(), findsOneWidget);
    expect(find.text('Citation at the caret'), findsNothing);
  });

  testWidgets('unlink all reviews counts, cancels, then converts as one undo', (
    tester,
  ) async {
    final controller = await _open(tester);
    final text = controller.document.paragraphs.map((p) => p.text).toList();
    final revision = controller.contentRevision;
    await _tap(tester, _key('zotero-unlink-all'));
    expect(
      find.textContaining('1 citation field(s) and 1 bibliography'),
      findsOneWidget,
    );
    expect(controller.zoteroFields, hasLength(2));
    await _tap(tester, find.text('Cancel'));
    expect(controller.contentRevision, revision);
    expect(controller.canUndo, isFalse);
    await _tap(tester, _key('zotero-unlink-all'));
    await _tap(tester, _key('zotero-confirm-unlink-all'));
    expect(controller.zoteroFields, isEmpty);
    expect(controller.document.paragraphs.map((p) => p.text), text);
    expect(find.textContaining('2 Zotero field(s) converted'), findsOneWidget);
    expect(controller.contentRevision, greaterThan(revision));
    controller.undo();
    expect(controller.zoteroFields, hasLength(2));
    expect(controller.zoteroFields.first.run!.properties.italic, isTrue);
    expect(controller.canUndo, isFalse);
    controller.redo();
    expect(controller.zoteroFields, isEmpty);
    expect(controller.document.paragraphs.map((p) => p.text), text);
  });

  testWidgets('a locked field rejects the complete conversion', (tester) async {
    final controller = await _open(tester, document: _document(locked: true));
    final revision = controller.contentRevision;
    await _tap(tester, _key('zotero-unlink-all'));
    await _tap(tester, _key('zotero-confirm-unlink-all'));
    expect(controller.zoteroFields, hasLength(2));
    expect(controller.contentRevision, revision);
    expect(controller.canUndo, isFalse);
    expect(find.textContaining('locked'), findsWidgets);
  });

  testWidgets(
    'unlink all discloses damaged counts and preserves text on cancel',
    (tester) async {
      final controller = await _open(tester, document: _damagedDocument());
      final original = controller.zoteroFields
          .map((field) => field.instruction)
          .toList();
      final text = controller.document.paragraphs.map((p) => p.text).toList();
      final revision = controller.contentRevision;
      await _tap(tester, _key('zotero-unlink-all'));
      expect(
        find.textContaining('2 field(s) have damaged reference data'),
        findsOneWidget,
      );
      expect(
        find.textContaining('1 citation field(s) and 1 bibliography'),
        findsOneWidget,
      );
      await _tap(tester, find.text('Cancel'));
      expect(
        controller.zoteroFields.map((field) => field.instruction),
        original,
      );
      expect(controller.contentRevision, revision);
      expect(controller.canUndo, isFalse);

      await _tap(tester, _key('zotero-unlink-all'));
      await _tap(tester, _key('zotero-confirm-unlink-all'));
      expect(controller.zoteroFields, isEmpty);
      expect(controller.document.paragraphs.map((p) => p.text), text);
      expect(
        find.textContaining('2 Zotero field(s) converted'),
        findsOneWidget,
      );
      final reopened = WordDeserializer().readBytes(controller.saveBytes());
      expect(WordZotero.fields(reopened), isEmpty);
      expect(reopened.paragraphs.map((p) => p.text), text);
      controller.undo();
      expect(
        controller.zoteroFields.map((field) => field.instruction),
        original,
      );
      expect(controller.zoteroFields.every((field) => !field.isValid), isTrue);
      expect(controller.zoteroFields.first.run!.properties.italic, isTrue);
      expect(controller.canUndo, isFalse);
      controller.redo();
      expect(controller.zoteroFields, isEmpty);
    },
  );

  testWidgets('damaged-field confirmation cannot remove a locked result', (
    tester,
  ) async {
    final controller = await _open(
      tester,
      document: _damagedDocument(locked: true),
    );
    final original = controller.zoteroFields
        .map((field) => field.instruction)
        .toList();
    final revision = controller.contentRevision;
    await _tap(tester, _key('zotero-unlink-all'));
    expect(
      find.textContaining('2 field(s) have damaged reference data'),
      findsOneWidget,
    );
    await _tap(tester, _key('zotero-confirm-unlink-all'));
    expect(controller.zoteroFields.map((field) => field.instruction), original);
    expect(controller.contentRevision, revision);
    expect(controller.canUndo, isFalse);
    expect(find.textContaining('locked'), findsWidgets);
  });

  testWidgets('a stale damaged-field confirmation keeps the whole document', (
    tester,
  ) async {
    final document = _damagedDocument();
    document.sections.single.blocks.insert(
      0,
      WmlParagraph(inlines: [WmlRun(text: 'Introduction ')]),
    );
    final controller = await _open(
      tester,
      document: document,
      offset: 0,
      initialTab: WordZoteroTab.document,
    );
    final original = controller.zoteroFields
        .map((field) => field.instruction)
        .toList();
    await _tap(tester, _key('zotero-unlink-all'));
    controller.insertText('New ');
    final revision = controller.contentRevision;
    await _tap(tester, _key('zotero-confirm-unlink-all'));
    expect(controller.zoteroFields.map((field) => field.instruction), original);
    expect(controller.contentRevision, revision);
    expect(find.textContaining('insertion point changed'), findsOneWidget);
    controller.undo();
    expect(controller.canUndo, isFalse);
  });

  testWidgets('a changed document cannot accept an old unlink confirmation', (
    tester,
  ) async {
    final controller = await _open(tester);
    await _tap(tester, _key('zotero-unlink-all'));
    controller.caret.logicalIndex = 0;
    controller.caret.collapseSelection();
    controller.insertText('New ');
    final revision = controller.contentRevision;
    await _tap(tester, _key('zotero-confirm-unlink-all'));
    expect(controller.zoteroFields, hasLength(2));
    expect(controller.contentRevision, revision);
    expect(controller.document.paragraphs.first.text, startsWith('New Before'));
    expect(find.textContaining('insertion point changed'), findsOneWidget);
    controller.undo();
    expect(controller.canUndo, isFalse);
    expect(controller.zoteroFields, hasLength(2));
  });

  for (final readOnly in [true, false]) {
    testWidgets(
      'unlink is disabled for ${readOnly ? 'read-only' : 'tracked'} documents',
      (tester) async {
        final document = _document()..trackRevisions = !readOnly;
        final controller = await _open(
          tester,
          document: document,
          readOnly: readOnly,
        );
        expect(
          tester.widget<OutlinedButton>(_key('zotero-unlink-all')).onPressed,
          isNull,
        );
        expect(controller.canUndo, isFalse);
      },
    );
  }

  testWidgets(
    'damaged unlink review remains usable at narrow RTL with doubled text',
    (tester) async {
      final controller = await _open(
        tester,
        document: _damagedDocument(),
        size: const Size(320, 480),
        scale: 2,
        direction: TextDirection.rtl,
      );
      await _tap(tester, _key('zotero-unlink-all'));
      await _tap(tester, find.text('Cancel'));
      expect(controller.zoteroFields, hasLength(2));
      expect(controller.canUndo, isFalse);
    },
  );
}
