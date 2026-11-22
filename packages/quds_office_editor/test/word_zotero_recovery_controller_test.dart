import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _id = 'zotero-recovery-controller';
const _damaged = ' ADDIN ZOTERO_ITEM CSL_CITATION {broken} ';
const _damagedBibliography = ' ADDIN ZOTERO_BIBL {broken} CSL_BIBLIOGRAPHY ';
const _reset = 'ITEM CSL_CITATION {"citationItems":[],"properties":{}}';

ZoteroCitation _citation(String text) => ZoteroCitation(
  citationId: 'repaired-reference',
  plainCitation: text,
  items: [
    ZoteroCitationItem.fromCsl(
      itemData: {'id': 'source', 'type': 'book', 'title': 'Recovered source'},
      uris: ['http://zotero.org/users/42/items/ABCD1234'],
    ),
  ],
);

WmlDocument _document({String shape = 'atomic'}) {
  final paragraph = WmlParagraph();
  if (shape == 'paragraph') {
    paragraph.properties
      ..fieldInstruction = _damaged
      ..fieldBegin = true
      ..fieldSeparate = true
      ..fieldEnd = true;
  } else {
    paragraph.inlines.add(WmlRun(text: 'Before '));
  }
  if (shape == 'complex') {
    paragraph.inlines.addAll([
      WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
      WmlFieldBoundary(kind: WmlFieldBoundaryKind.instruction, text: _damaged),
      WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
      WmlRun(text: 'Alpha', properties: WmlRunProps(italic: true)),
      WmlRun(text: ' Beta', properties: WmlRunProps(bold: true)),
      WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
    ]);
  } else {
    paragraph.inlines.add(
      WmlRun(
        text: 'Alpha Beta',
        properties: WmlRunProps(italic: true),
        fieldInstruction: shape == 'atomic' ? _damaged : null,
      ),
    );
  }
  if (shape != 'paragraph') paragraph.inlines.add(WmlRun(text: ' after'));
  return WmlDocument(
    sections: [
      WmlSection(blocks: [paragraph]),
    ],
  );
}

WmlDocument _bibliography() {
  final entries = WordZotero.nativeBibliographyParagraphs(
    instruction: ' ADDIN ZOTERO_BIBL {} CSL_BIBLIOGRAPHY ',
    text: 'First source\nSecond source',
  );
  final index = entries.first.inlines.indexWhere(
    (inline) =>
        inline is WmlFieldBoundary &&
        inline.kind == WmlFieldBoundaryKind.instruction,
  );
  entries.first.inlines[index] = WmlFieldBoundary(
    kind: WmlFieldBoundaryKind.instruction,
    text: _damagedBibliography,
  );
  return WmlDocument(
    sections: [
      WmlSection(
        blocks: [
          WmlParagraph(inlines: [WmlRun(text: 'Introduction')]),
          ...entries,
          WmlParagraph(inlines: [WmlRun(text: 'Continue writing')]),
        ],
      ),
    ],
  );
}

WordEditorController _controller(WmlDocument document) {
  final controller = WordEditorController(document: document);
  controller.proofing.enabled = false;
  addTearDown(() {
    if (!controller.isDisposed) controller.dispose();
  });
  return controller;
}

String _xml(WmlDocument document) =>
    WordSerializer().write(document).getPart('/word/document.xml')!.readText();

WordZoteroTransaction _begin(WordEditorController controller) =>
    controller.beginZoteroTransaction(
      documentId: _id,
      command: ZoteroCitingCommand.refresh,
    );

Object? _call(
  WordZoteroTransaction transaction,
  String command, [
  List<Object?> arguments = const [],
]) => transaction.handle(command, [_id, ...arguments]);

String _field(WordZoteroTransaction transaction) =>
    ((_call(transaction, 'Document.getFields', ['Http']) as List).single
            as Map)['id']
        as String;

void _repair(WordZoteroTransaction transaction, String field, String text) {
  _call(transaction, 'Field.setCode', [
    field,
    'ITEM CSL_CITATION ${jsonEncode(_citation(text).toJson())}',
  ]);
  _call(transaction, 'Field.setText', [field, text, false]);
}

void _complete(WordZoteroTransaction transaction) {
  _call(transaction, 'Document.complete');
  transaction.session.prepareReview();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final shape in ['atomic', 'complex', 'paragraph']) {
    test(
      'explicit $shape recovery unlinks only metadata with undo and DOCX',
      () {
        final controller = _controller(_document(shape: shape));
        final document = controller.document;
        final original = _xml(document);
        final paragraph = document.paragraphs.single;
        final text = paragraph.text;
        final field = controller.zoteroFields.single;
        expect(field.isValid, isFalse);
        expect(field.canEdit, isFalse);
        expect(controller.canEditZoteroFieldNatively(field), isTrue);

        controller.unlinkZoteroField(field);
        expect(controller.zoteroFields, isEmpty);
        expect(document.paragraphs.single, same(paragraph));
        expect(paragraph.text, text);
        expect(controller.canUndo, isTrue);
        final converted = _xml(document);
        final reopened = WordDeserializer().readBytes(controller.saveBytes());
        expect(WordZotero.fields(reopened), isEmpty);
        expect(reopened.paragraphs.single.text, text);
        expect(
          reopened.paragraphs.single.inlines
              .whereType<WmlRun>()
              .where((run) => run.text.startsWith('Alpha'))
              .single
              .properties
              .italic,
          isTrue,
        );
        for (var cycle = 0; cycle < 2; cycle++) {
          controller.undo();
          expect(_xml(document), original);
          expect(controller.zoteroFields.single.instruction, _damaged);
          expect(controller.canUndo, isFalse);
          controller.redo();
          expect(_xml(document), converted);
        }
      },
    );
  }

  test('damaged multipart bibliography unlink keeps its paragraph owners', () {
    final controller = _controller(_bibliography());
    final document = controller.document;
    final original = _xml(document);
    final paragraphs = document.paragraphs.toList();
    final text = paragraphs.map((paragraph) => paragraph.text).toList();
    final field = controller.zoteroFields.single;
    expect(field.paragraphs, hasLength(2));
    expect(controller.canEditZoteroFieldNatively(field), isTrue);
    controller.unlinkZoteroField(field);
    expect(controller.zoteroFields, isEmpty);
    expect(document.paragraphs, orderedEquals(paragraphs));
    expect(document.paragraphs.map((paragraph) => paragraph.text), text);
    final reopened = WordDeserializer().readBytes(controller.saveBytes());
    expect(WordZotero.fields(reopened), isEmpty);
    expect(reopened.paragraphs.map((paragraph) => paragraph.text), text);
    controller.undo();
    expect(_xml(document), original);
    expect(controller.canUndo, isFalse);
  });

  test(
    'native repair stays detached through reset and restores damage on undo',
    () {
      final controller = _controller(_document(shape: 'complex'));
      final document = controller.document;
      final original = _xml(document);
      final originalLength = document.paragraphs.single.text.length;
      controller.caret.logicalIndex = originalLength;
      controller.caret.collapseSelection();
      final transaction = _begin(controller);
      final field = _field(transaction);
      _call(transaction, 'Field.select', [field]);
      expect(transaction.selectedFieldContext!.sourceField!.isValid, isFalse);
      expect(transaction.selectedFieldContext!.sourceText, 'Alpha Beta');
      _call(transaction, 'Field.setCode', [field, _reset]);
      expect(_xml(document), original);
      expect(controller.canUndo, isFalse);
      _repair(transaction, field, '(Recovered source, 2026)');
      expect(_xml(document), original);
      _complete(transaction);
      expect(_xml(document), original);
      transaction.apply();
      expect(controller.zoteroFields.single.isValid, isTrue);
      expect(
        document.paragraphs.single.text,
        'Before (Recovered source, 2026) after',
      );
      expect(
        controller.caret.logicalIndex,
        document.paragraphs.single.text.length,
      );
      expect(controller.zoteroFieldContext, isNull);
      final repaired = _xml(document);
      final reopened = WordDeserializer().readBytes(controller.saveBytes());
      expect(
        WordZotero.fields(reopened).single.citation!.citationId,
        'repaired-reference',
      );
      controller.undo();
      expect(_xml(document), original);
      expect(controller.caret.logicalIndex, originalLength);
      expect(controller.zoteroFields.single.instruction, _damaged);
      controller.redo();
      expect(_xml(document), repaired);
    },
  );

  test('native removeCode preserves damaged cache until completion', () {
    final controller = _controller(_document(shape: 'complex'));
    final original = _xml(controller.document);
    final transaction = _begin(controller);
    final field = _field(transaction);
    _call(transaction, 'Field.select', [field]);
    _call(transaction, 'Field.removeCode', [field]);
    expect(controller.zoteroFieldContext, isNull);
    expect(_xml(controller.document), original);
    _complete(transaction);
    transaction.apply();
    expect(controller.zoteroFields, isEmpty);
    expect(
      controller.document.paragraphs.single.text,
      'Before Alpha Beta after',
    );
    controller.undo();
    expect(_xml(controller.document), original);
  });

  test(
    'cancelled native repair keeps the damaged original and redo history',
    () {
      final controller = _controller(_document());
      controller.caret.logicalIndex = 0;
      controller.caret.collapseSelection();
      controller.insertText('Draft ');
      controller.undo();
      final original = _xml(controller.document);
      final revision = controller.contentRevision;
      final transaction = _begin(controller);
      final field = _field(transaction);
      _call(transaction, 'Field.select', [field]);
      _call(transaction, 'Field.setCode', [field, _reset]);
      transaction.clearFieldContext();
      expect(() => transaction.apply(), throwsStateError);
      expect(_xml(controller.document), original);
      expect(controller.zoteroFieldContext, isNull);
      expect(controller.contentRevision, revision);
      expect(controller.canUndo, isFalse);
      expect(controller.canRedo, isTrue);
    },
  );

  test('native bibliography repair replaces complete entries as one undo', () {
    final controller = _controller(_bibliography());
    final original = _xml(controller.document);
    final transaction = _begin(controller);
    final field = _field(transaction);
    _call(transaction, 'Field.select', [field]);
    expect(transaction.selectedFieldContext!.sourceRanges, hasLength(2));
    _call(transaction, 'Field.setCode', [field, 'BIBL {} CSL_BIBLIOGRAPHY']);
    _call(transaction, 'Field.setText', [
      field,
      '<div class="csl-entry">Recovered one.</div>'
          '<div class="csl-entry">Recovered two.</div>'
          '<div class="csl-entry">Recovered three.</div>',
      true,
    ]);
    _complete(transaction);
    expect(_xml(controller.document), original);
    transaction.apply();
    expect(controller.zoteroFields.single.paragraphs, hasLength(3));
    expect(controller.zoteroFields.single.isValid, isTrue);
    expect(controller.document.paragraphs.last.text, 'Continue writing');
    final reopened = WordDeserializer().readBytes(controller.saveBytes());
    expect(WordZotero.fields(reopened).single.paragraphs, hasLength(3));
    controller.undo();
    expect(_xml(controller.document), original);
    expect(controller.canUndo, isFalse);
  });

  for (final reset in [false, true]) {
    test('unresolved damaged metadata cannot complete after reset=$reset', () {
      final controller = _controller(_document());
      final original = _xml(controller.document);
      final transaction = _begin(controller);
      final field = _field(transaction);
      if (reset) _call(transaction, 'Field.setCode', [field, _reset]);
      _call(transaction, 'Field.setText', [field, 'Uncommitted text', false]);
      expect(() => _complete(transaction), throwsFormatException);
      expect(_xml(controller.document), original);
      expect(controller.canUndo, isFalse);
    });
  }

  for (final stale in ['caret', 'metadata', 'lock', 'protection']) {
    test('$stale changes prevent completed recovery from applying', () {
      final controller = _controller(_document());
      final transaction = _begin(controller);
      final field = _field(transaction);
      _repair(transaction, field, 'Must not apply');
      _complete(transaction);
      switch (stale) {
        case 'caret':
          controller.caret.logicalIndex = 1;
        case 'metadata':
          controller.zoteroFields.single.run!.fieldInstruction =
              ' ADDIN ZOTERO_ITEM CSL_CITATION {changed} ';
        case 'lock':
          controller.zoteroFields.single.run!.fieldLocked = true;
        case 'protection':
          controller.document.restrictEditing = true;
      }
      final changed = _xml(controller.document);
      expect(() => transaction.apply(), throwsStateError);
      expect(_xml(controller.document), changed);
      expect(controller.canUndo, isFalse);
    });
  }

  for (final unsafe in ['locked', 'nested', 'hyperlink', 'opaque']) {
    test(
      '$unsafe metadata damage remains protected from explicit conversion',
      () {
        final document = _document(
          shape: unsafe == 'opaque' ? 'complex' : 'atomic',
        );
        final paragraph = document.paragraphs.single;
        final field = WordZotero.fields(document).single;
        switch (unsafe) {
          case 'locked':
            field.run!.fieldLocked = true;
          case 'nested':
            paragraph.inlines
              ..insert(0, WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin))
              ..insert(
                1,
                WmlFieldBoundary(
                  kind: WmlFieldBoundaryKind.instruction,
                  text: ' IF 1 = 1 ',
                ),
              )
              ..insert(2, WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate))
              ..add(WmlFieldBoundary(kind: WmlFieldBoundaryKind.end));
          case 'hyperlink':
            field.run!.hyperlink = const WmlHyperlink(
              url: 'https://example.org/',
            );
          case 'opaque':
            final index = paragraph.inlines.indexWhere(
              (inline) => inline is WmlFieldBoundary,
            );
            paragraph.inlines[index] = WmlFieldBoundary(
              kind: WmlFieldBoundaryKind.begin,
              runPropertiesXml: '<w:rPr><w:b/></w:rPr>',
            );
        }
        final controller = _controller(document);
        final current = controller.zoteroFields.single;
        final original = _xml(document);
        expect(controller.canEditZoteroFieldNatively(current), isFalse);
        expect(
          () => controller.unlinkZoteroField(current),
          throwsUnsupportedError,
        );
        expect(_xml(document), original);
        expect(controller.canUndo, isFalse);
      },
    );
  }

  test('shared paragraph ownership refuses conversion of damaged metadata', () {
    final document = _document();
    final paragraph = document.paragraphs.single;
    document.sections.single.blocks.add(paragraph);
    final controller = _controller(document);
    final original = _xml(document);
    expect(
      () => controller.unlinkZoteroField(controller.zoteroFields.first),
      throwsStateError,
    );
    expect(_xml(document), original);
    expect(controller.canUndo, isFalse);
  });

  test(
    'shared result runs cannot unlink another paragraph through an alias',
    () {
      final document = _document();
      final shared = WordZotero.fields(document).single.run!;
      document.sections.single.blocks.add(WmlParagraph(inlines: [shared]));
      final controller = _controller(document);
      final original = _xml(document);
      expect(controller.zoteroFields, hasLength(2));
      expect(
        () => controller.unlinkZoteroField(controller.zoteroFields.first),
        throwsUnsupportedError,
      );
      expect(_xml(document), original);
      expect(controller.zoteroFields.map((field) => field.instruction), [
        _damaged,
        _damaged,
      ]);
      expect(controller.canUndo, isFalse);
    },
  );

  for (final story in ['header', 'frame']) {
    test('damaged $story field stays preserved during direct conversion', () {
      final document = _document();
      final paragraph = document.paragraphs.single;
      document.sections.single.blocks
        ..clear()
        ..add(WmlParagraph(inlines: [WmlRun(text: 'Keep body')]));
      if (story == 'header') {
        document.sections.single.header.add(paragraph);
      } else {
        document.sections.single.blocks.add(WmlFrame(blocks: [paragraph]));
      }
      final controller = _controller(document);
      final original = _xml(document);
      final field = controller.zoteroFields.single;
      expect(() => controller.unlinkZoteroField(field), throwsUnsupportedError);
      expect(_xml(document), original);
      expect(controller.zoteroFields.single.instruction, _damaged);
      expect(paragraph.text, 'Before Alpha Beta after');
      expect(controller.canUndo, isFalse);
    });
  }
}
