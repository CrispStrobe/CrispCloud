import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _damaged = ' ADDIN ZOTERO_ITEM CSL_CITATION {broken} ';

WmlDocument _document({bool locked = false}) => WmlDocument(
  sections: [
    WmlSection(
      blocks: [
        WmlParagraph(
          inlines: [
            WmlRun(text: 'Before '),
            WmlRun(
              text: '(Original reference)',
              properties: WmlRunProps(italic: true),
              fieldInstruction: _damaged,
              fieldLocked: locked,
            ),
            WmlRun(text: ' after'),
          ],
        ),
      ],
    ),
  ],
);

String _xml(WmlDocument document) =>
    WordSerializer().write(document).getPart('/word/document.xml')!.readText();

final class _Desktop {
  _Desktop({this.unlink = false});

  final bool unlink;
  final replies = <Object?>[];
  String documentId = '';
  String fieldId = '';
  String originalCode = '';
  int index = 0;

  Future<ZoteroHttpResponse> send(ZoteroHttpRequest request) async {
    final decoded = jsonDecode(request.body!);
    if (index == 0) {
      documentId = (decoded as Map)['docId'] as String;
    } else {
      replies.add(decoded);
      if (decoded is List) {
        final field = decoded.single as Map;
        fieldId = field['id'] as String;
        originalCode = field['code'] as String;
      }
    }
    Map<String, Object?> message(String command, List<Object?> arguments) => {
      'command': command,
      'arguments': arguments,
    };
    final citation = ZoteroCitation(
      citationId: 'repaired',
      plainCitation: '(Recovered reference)',
      items: [
        ZoteroCitationItem.fromCsl(
          itemData: {'id': 'source', 'type': 'book', 'title': 'Recovered'},
          uris: ['http://zotero.org/users/42/items/ABCD1234'],
        ),
      ],
    );
    final step = index++;
    final response = switch (step) {
      0 => message('Application.getActiveDocument', []),
      1 => message('Document.getFields', [documentId, 'Http']),
      2 => message('Field.select', [documentId, fieldId]),
      3 => message('Document.displayAlert', [
        documentId,
        'Zotero found damaged reference metadata. Choose how to continue.',
        2,
        3,
      ]),
      4 when decoded == 0 => message('Document.complete', [documentId]),
      4 when unlink => message('Field.removeCode', [documentId, fieldId]),
      4 => message('Field.setCode', [
        documentId,
        fieldId,
        'ITEM CSL_CITATION {"citationItems":[],"properties":{}}',
      ]),
      5 when unlink => message('Document.complete', [documentId]),
      5 => message('Field.setCode', [
        documentId,
        fieldId,
        'ITEM CSL_CITATION ${jsonEncode(citation.toJson())}',
      ]),
      6 => message('Field.setText', [
        documentId,
        fieldId,
        citation.plainCitation,
        false,
      ]),
      7 => message('Document.complete', [documentId]),
      _ => throw StateError('Unexpected native request $step'),
    };
    return ZoteroHttpResponse(
      statusCode: 200,
      headers: const {},
      body: jsonEncode(response),
    );
  }
}

Future<void> _pump(WidgetTester tester) async {
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<WordEditorController> _open(
  WidgetTester tester, {
  _Desktop? desktop,
  bool direct = false,
  bool locked = false,
  Size size = const Size(1100, 900),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final controller = WordEditorController(document: _document(locked: locked));
  controller.proofing.enabled = false;
  controller.caret.logicalIndex = 9;
  controller.caret.collapseSelection();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    if (!controller.isDisposed) controller.dispose();
    await tester.pump();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showWordZoteroDialog(
              context,
              controller: controller,
              localTransport: desktop?.send,
              initialCommand: direct ? ZoteroCitingCommand.refresh : null,
              closeAfterCommand: direct,
            ),
            child: const Text('Open references'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open references'));
  await _pump(tester);
  return controller;
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await _pump(tester);
}

Future<Finder> _referenceMenu(WidgetTester tester) async {
  final menu = find.byKey(const ValueKey('zotero-reference-actions-0'));
  await tester.scrollUntilVisible(
    menu,
    240,
    maxScrolls: 10,
    scrollable: find
        .descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pump();
  return menu;
}

Finder get _prompt => find.byWidgetPredicate(
  (widget) =>
      widget is AlertDialog &&
      widget.title is Text &&
      (widget.title! as Text).data == 'Zotero',
);

Finder _promptText(String text) =>
    find.descendant(of: _prompt, matching: find.text(text));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);

  testWidgets(
    'offline damaged reference conversion is explicit and cancellable',
    (tester) async {
      final controller = await _open(tester);
      final original = _xml(controller.document);
      expect(
        find.byKey(const ValueKey('zotero-current-field-damaged')),
        findsOneWidget,
      );
      final convert = find.byKey(
        const ValueKey('zotero-unlink-current-damaged'),
      );
      await _tap(tester, convert);
      expect(find.text('Convert damaged reference to text?'), findsOneWidget);
      expect(_xml(controller.document), original);
      await _tap(tester, find.widgetWithText(TextButton, 'Cancel'));
      expect(_xml(controller.document), original);
      expect(controller.canUndo, isFalse);
      await _tap(tester, convert);
      await _tap(
        tester,
        find.byKey(const ValueKey('zotero-confirm-unlink-damaged')),
      );
      expect(controller.zoteroFields, isEmpty);
      expect(
        controller.document.paragraphs.single.text,
        'Before (Original reference) after',
      );
      final reopened = WordDeserializer().readBytes(controller.saveBytes());
      expect(WordZotero.fields(reopened), isEmpty);
      controller.undo();
      expect(_xml(controller.document), original);
      expect(controller.canUndo, isFalse);
    },
  );

  testWidgets('locked damaged reference exposes no recovery mutation', (
    tester,
  ) async {
    final controller = await _open(tester, desktop: _Desktop(), locked: true);
    final original = _xml(controller.document);
    expect(
      find.byKey(const ValueKey('zotero-current-field-damaged')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('zotero-unlink-current-damaged')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('zotero-edit-current-native')),
      findsNothing,
    );
    final actions = await _referenceMenu(tester);
    final menu = tester.widget<PopupMenuButton<String>>(actions);
    expect(menu.enabled, isFalse);
    expect(_xml(controller.document), original);
    expect(controller.canUndo, isFalse);
  });

  testWidgets(
    'damaged reference menu offers native repair without basic rewrite',
    (tester) async {
      await _open(tester, desktop: _Desktop());
      expect(find.text('Repair current reference in Zotero…'), findsOneWidget);
      await _tap(tester, await _referenceMenu(tester));
      expect(find.text('Repair in Zotero…'), findsOneWidget);
      expect(find.text('Convert to text (undoable)'), findsOneWidget);
      expect(find.text('Edit citation'), findsNothing);
    },
  );

  testWidgets(
    'native repair shows original damaged text and publishes only completion',
    (tester) async {
      final desktop = _Desktop();
      final controller = await _open(tester, desktop: desktop, direct: true);
      final original = _xml(controller.document);
      expect(_prompt, findsOneWidget);
      expect(desktop.originalCode, contains('{broken}'));
      final damaged = find.descendant(
        of: _prompt,
        matching: find.byKey(const ValueKey('zotero-selected-field-damaged')),
      );
      expect(damaged, findsOneWidget);
      final excerpt = tester.widget<SelectableText>(
        find.descendant(
          of: _prompt,
          matching: find.byKey(const ValueKey('zotero-selected-field-text')),
        ),
      );
      expect(
        excerpt.textSpan!.toPlainText(),
        'Before (Original reference) after',
      );
      expect(controller.zoteroFields.single.isValid, isFalse);
      expect(controller.canUndo, isFalse);
      await _tap(tester, _promptText('Yes'));
      expect(desktop.replies, contains(2));
      expect(controller.zoteroFields.single.isValid, isTrue);
      expect(
        controller.document.paragraphs.single.text,
        'Before (Recovered reference) after',
      );
      expect(controller.zoteroFieldContext, isNull);
      expect(find.byKey(const ValueKey('zotero-direct-command')), findsNothing);
      controller.undo();
      expect(_xml(controller.document), original);
    },
  );

  testWidgets('native Cancel preserves damaged fields without adding undo', (
    tester,
  ) async {
    final desktop = _Desktop();
    final controller = await _open(
      tester,
      desktop: desktop,
      direct: true,
      size: const Size(780, 540),
    );
    final original = _xml(controller.document);
    final revision = controller.contentRevision;
    expect(_prompt, findsOneWidget);
    await _tap(tester, _promptText('Cancel'));
    expect(desktop.replies, contains(0));
    expect(_xml(controller.document), original);
    expect(controller.contentRevision, revision);
    expect(controller.canUndo, isFalse);
    expect(controller.zoteroFieldContext, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'native removeCode keeps the original cache and remains undoable',
    (tester) async {
      // This transcript verifies the callback itself. It does not assume which
      // callback any particular Zotero release chooses for its No button.
      final desktop = _Desktop(unlink: true);
      final controller = await _open(tester, desktop: desktop, direct: true);
      final original = _xml(controller.document);
      await _tap(tester, _promptText('No'));
      expect(desktop.replies, contains(1));
      expect(controller.zoteroFields, isEmpty);
      expect(
        controller.document.paragraphs.single.text,
        'Before (Original reference) after',
      );
      expect(controller.zoteroFieldContext, isNull);
      controller.undo();
      expect(_xml(controller.document), original);
    },
  );
}
