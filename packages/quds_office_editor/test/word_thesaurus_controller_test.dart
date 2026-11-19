import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

import 'support/thesaurus_fixture.dart';

WordEditorController _controller({
  String text = 'bank',
  WmlDocument? document,
  String language = 'en-US',
}) {
  final controller = WordEditorController(
    document: document ?? WmlDocument.empty(text: text),
  );
  controller.document.proofingLanguage = language;
  addTearDown(controller.dispose);
  return controller;
}

WmlParagraph _paragraph(String text) =>
    WmlParagraph(inlines: [WmlRun(text: text)]);

WmlDocument _document(WmlParagraph paragraph) => WmlDocument(
  sections: [
    WmlSection(blocks: [paragraph]),
  ],
);

void _select(
  WordEditorController controller,
  int start,
  int end, {
  int paragraph = 0,
}) {
  controller.caret
    ..paragraphIndex = paragraph
    ..logicalIndex = end
    ..selectionAnchorParagraph = paragraph
    ..selectionAnchor = start;
}

Future<WordThesaurusLookup> _lookup(
  WordEditorController controller, {
  OfficeThesaurusService? service,
}) {
  final capture = controller.captureThesaurusTarget();
  expect(
    capture.status,
    WordThesaurusTargetStatus.ready,
    reason: capture.message,
  );
  return controller.lookupThesaurus(
    capture.target!,
    service ?? testThesaurusService(),
  );
}

OfficeThesaurusTerm _term(WordThesaurusLookup lookup, String text) => lookup
    .result
    .senses
    .expand((sense) => sense.terms)
    .firstWhere((term) => term.text == text);

WmlContentControlData _control({
  String lock = 'contentLocked',
  bool bound = false,
}) => WmlContentControlData(
  xml:
      '<w:sdt xmlns:w="${OfficeNamespaces.w}"><w:sdtPr>'
      '<w:id w:val="42"/><w:lock w:val="$lock"/>'
      '${bound ? '<w:dataBinding w:storeItemID="{OWNER}" w:xpath="/value"/>' : ''}'
      '</w:sdtPr><w:sdtContent/></w:sdt>',
  sourcePartUri: '/word/document.xml',
  relationships: [],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'lookup at the caret changes neither selection nor document history',
    () async {
      final controller = _controller(text: 'A bank here.');
      _select(controller, 4, 4);
      final revision = controller.contentRevision;
      final lookup = await _lookup(controller);
      expect(lookup.target.text, 'bank');
      expect(lookup.target.start, 2);
      expect(lookup.target.end, 6);
      expect(lookup.target.language, 'en-US');
      expect(lookup.target.story, 'Body');
      expect(lookup.result.status, OfficeThesaurusStatus.ready);
      expect(controller.caret.logicalIndex, 4);
      expect(controller.caret.selectionAnchor, 4);
      expect(controller.document.paragraphs.single.text, 'A bank here.');
      expect(controller.contentRevision, revision);
      expect(controller.canUndo, isFalse);
      expect(controller.proofing.summary.hasResults, isFalse);
    },
  );

  for (final sample in [
    (text: 'bank', start: 0, end: 4, replacement: 'financial institution'),
    (text: 'financial institution', start: 0, end: 21, replacement: 'bank'),
    (text: '😀 cafe\u0301 עברית', start: 3, end: 8, replacement: 'coffeehouse'),
    (text: 'fast\u00ad', start: 0, end: 4, replacement: 'quick'),
    (text: 'ba\u00adnk', start: 0, end: 5, replacement: 'depository'),
  ]) {
    for (final tracked in [false, true]) {
      test(
        'literal ${sample.text} replacement and history (tracked $tracked)',
        () async {
          final controller = _controller(text: sample.text);
          controller.document.trackRevisions = tracked;
          _select(controller, sample.start, sample.end);
          final lookup = await _lookup(controller);
          final term = _term(lookup, sample.replacement);
          expect(controller.applyThesaurusTerm(lookup, term), isTrue);
          final before = sample.text;
          final after = tracked
              ? before.substring(0, sample.end) +
                    sample.replacement +
                    before.substring(sample.end)
              : before.substring(0, sample.start) +
                    sample.replacement +
                    before.substring(sample.end);
          expect(controller.document.paragraphs.single.text, after);
          expect(
            controller.caret.logicalIndex,
            (tracked ? sample.end : sample.start) + sample.replacement.length,
          );
          expect(controller.caret.isCollapsed, isTrue);
          expect(controller.document.revisions.length, tracked ? 2 : 0);
          expect(controller.isThesaurusLookupCurrent(lookup), isFalse);
          controller.undo();
          expect(controller.document.paragraphs.single.text, before);
          expect(controller.document.revisions, isEmpty);
          expect(controller.caret.logicalIndex, sample.end);
          expect(controller.caret.selectionAnchor, sample.start);
          expect(controller.canUndo, isFalse);
          expect(controller.canRedo, isTrue);
          controller.redo();
          expect(controller.document.paragraphs.single.text, after);
          expect(controller.document.revisions.length, tracked ? 2 : 0);
        },
      );
    }
  }

  for (final tracked in [false, true]) {
    test(
      'formatting, links, bookmarks and comments survive one undo unit (tracked $tracked)',
      () async {
        const link = WmlHyperlink(url: 'https://example.test/bank');
        final paragraph = WmlParagraph(
          inlines: [
            WmlRun(text: 'Before ', properties: WmlRunProps(italic: true)),
            WmlBookmarkBoundary(id: '7', isStart: true, name: 'selected-word'),
            WmlRun(
              text: 'ba',
              properties: WmlRunProps(bold: true),
              hyperlink: link,
              commentIds: [3],
            ),
            WmlRun(
              text: 'nk',
              properties: WmlRunProps(underline: WmlUnderline.single),
              hyperlink: link,
              commentIds: [3],
            ),
            WmlBookmarkBoundary(id: '7', isStart: false),
            WmlRun(text: ' after', properties: WmlRunProps(italic: true)),
          ],
        );
        final controller = _controller(document: _document(paragraph));
        controller.document.trackRevisions = tracked;
        _select(controller, 7, 11);
        final lookup = await _lookup(controller);
        expect(
          controller.applyThesaurusTerm(lookup, _term(lookup, 'depository')),
          isTrue,
        );
        final inserted = paragraph.inlines.whereType<WmlRun>().firstWhere(
          (run) => run.text.contains('depository'),
        );
        expect(inserted.properties.bold, isTrue);
        expect(inserted.hyperlink?.url, link.url);
        expect(inserted.commentIds, [3]);
        expect(
          paragraph.inlines.whereType<WmlBookmarkBoundary>().map(
            (b) => (b.id, b.isStart),
          ),
          [('7', true), ('7', false)],
        );
        expect(
          paragraph.inlines.whereType<WmlRun>().first.properties.italic,
          isTrue,
        );
        expect(
          paragraph.inlines.whereType<WmlRun>().last.properties.italic,
          isTrue,
        );
        controller.undo();
        final original = paragraph.inlines.whereType<WmlRun>().toList();
        expect(original.map((run) => run.text), [
          'Before ',
          'ba',
          'nk',
          ' after',
        ]);
        expect(original[1].properties.bold, isTrue);
        expect(original[2].properties.underline, WmlUnderline.single);
        expect(original[1].hyperlink?.url, link.url);
        controller.redo();
        expect(
          paragraph.inlines
              .whereType<WmlRun>()
              .firstWhere((run) => run.text.contains('depository'))
              .hyperlink
              ?.url,
          link.url,
        );
      },
    );
  }

  test('mixed linked and unlinked source does not invent a link', () async {
    final paragraph = WmlParagraph(
      inlines: [
        WmlRun(
          text: 'ba',
          hyperlink: const WmlHyperlink(url: 'https://example.test/'),
        ),
        WmlRun(text: 'nk'),
      ],
    );
    final controller = _controller(document: _document(paragraph));
    _select(controller, 0, 4);
    final lookup = await _lookup(controller);
    expect(
      controller.applyThesaurusTerm(lookup, _term(lookup, 'depository')),
      isTrue,
    );
    expect(paragraph.inlines.whereType<WmlRun>().single.hyperlink, isNull);
    controller.undo();
    expect(paragraph.inlines.whereType<WmlRun>().first.hyperlink, isNotNull);
  });

  test('run then paragraph then document language is authoritative', () async {
    final paragraph = _paragraph('Bank');
    paragraph.properties.proofingLanguage = 'de-AT';
    paragraph.inlines.whereType<WmlRun>().single.properties.proofingLanguage =
        'de_CH';
    final controller = _controller(document: _document(paragraph));
    final first = controller.captureThesaurusTarget().target!;
    expect(first.language, 'de-CH');
    final german = await controller.lookupThesaurus(
      first,
      testThesaurusService(locale: 'de'),
    );
    expect(german.result.status, OfficeThesaurusStatus.ready);
    paragraph.inlines.whereType<WmlRun>().single.properties.proofingLanguage =
        null;
    expect(controller.isThesaurusLookupCurrent(german), isFalse);
    expect(controller.captureThesaurusTarget().target!.language, 'de-AT');
    paragraph.properties.proofingLanguage = null;
    expect(controller.captureThesaurusTarget().target!.language, 'en-US');
  });

  test(
    'text language controls and undo retire an earlier thesaurus lookup',
    () async {
      final controller = _controller();
      _select(controller, 0, 4);
      final lookup = await _lookup(controller);
      final term = _term(lookup, 'depository');
      final textTarget = controller.textProofingTarget!;
      final revision = controller.contentRevision;
      expect(controller.canApplyThesaurusTerm(lookup, term), isTrue);
      expect(
        controller.setTextProofingLanguage('de-DE', target: textTarget),
        isTrue,
      );
      expect(controller.document.paragraphs.single.text, 'bank');
      expect(controller.contentRevision, greaterThan(revision));
      expect(controller.canApplyThesaurusTerm(lookup, term), isFalse);
      expect(controller.applyThesaurusTerm(lookup, term), isFalse);
      final german = await _lookup(
        controller,
        service: testThesaurusService(locale: 'de'),
      );
      expect(german.target.language, 'de-DE');
      final germanTerm = _term(german, 'Geldinstitut');
      expect(controller.canApplyThesaurusTerm(german, germanTerm), isTrue);
      controller.undo();
      expect(controller.canUndo, isFalse);
      expect(controller.document.paragraphs.single.text, 'bank');
      expect(controller.applyThesaurusTerm(lookup, term), isFalse);
      expect(controller.applyThesaurusTerm(german, germanTerm), isFalse);
      final fresh = await _lookup(controller);
      expect(fresh.target.language, 'en-US');
      expect(
        controller.applyThesaurusTerm(fresh, _term(fresh, 'depository')),
        isTrue,
      );
      expect(controller.document.paragraphs.single.text, 'depository');
      controller.undo();
      expect(controller.document.paragraphs.single.text, 'bank');
      expect(controller.canUndo, isFalse);
    },
  );

  for (final splitGrapheme in [false, true]) {
    test(
      'mixed source language is explicit (split grapheme $splitGrapheme)',
      () {
        final paragraph = WmlParagraph(
          inlines: [
            WmlRun(
              text: splitGrapheme ? 'e' : 'bank ',
              properties: WmlRunProps(proofingLanguage: 'en-US'),
            ),
            WmlRun(
              text: splitGrapheme ? '\u0301' : 'Haus',
              properties: WmlRunProps(proofingLanguage: 'de-DE'),
            ),
          ],
        );
        final controller = _controller(document: _document(paragraph));
        _select(controller, 0, paragraph.text.length);
        expect(
          controller.captureThesaurusTarget().status,
          WordThesaurusTargetStatus.mixedLanguage,
        );
        expect(controller.canUndo, isFalse);
      },
    );
  }

  for (final mutation in <String, void Function(WordEditorController)>{
    'selection': (c) => _select(c, 1, 1),
    'source text': (c) =>
        c.document.paragraphs.single.inlines.whereType<WmlRun>().single.text =
            'sand',
    'document identity': (c) =>
        c.document = WmlDocument.empty(text: 'bank')
          ..proofingLanguage = 'en-US',
    'document language': (c) => c.document.proofingLanguage = 'de-DE',
    'run language': (c) =>
        c.document.paragraphs.single.inlines
                .whereType<WmlRun>()
                .single
                .properties
                .proofingLanguage =
            'de-DE',
    'generated source': (c) =>
        c.document.paragraphs.single.properties.fieldInstruction = ' REF bank ',
    'formatting': (c) =>
        c.document.paragraphs.single.inlines
                .whereType<WmlRun>()
                .single
                .properties
                .bold =
            true,
    'hyperlink': (c) =>
        c.document.paragraphs.single.inlines
            .whereType<WmlRun>()
            .single
            .hyperlink = const WmlHyperlink(
          url: 'https://example.test/',
        ),
    'tracking mode': (c) => c.document.trackRevisions = true,
    'IME': (c) => c.input.composing = const TextRange(start: 0, end: 2),
    'host viewing mode': (c) => c.setMode(OfficeInteractionMode.viewing),
    'selected picture': (c) => c.selectedVisual = WmlVisual(
      visual: OfficeVisual(kind: OfficeVisualKind.picture),
    ),
    'selected frame': (c) => c.selectedFrame = WmlFrame(),
    'selected equation': (c) =>
        c.selectedEquation = WmlEquation(math: OmmlEquation.empty()),
    'document protection': (c) {
      c.document.restrictEditing = true;
      c.document.restrictMode = WmlRestrictMode.readOnly;
    },
  }.entries) {
    test(
      '${mutation.key} after lookup rejects without editing history',
      () async {
        final controller = _controller();
        final lookup = await _lookup(controller);
        final term = _term(lookup, 'depository');
        mutation.value(controller);
        final text = controller.document.paragraphs.single.text;
        expect(controller.canApplyThesaurusTerm(lookup, term), isFalse);
        expect(controller.applyThesaurusTerm(lookup, term), isFalse);
        expect(controller.document.paragraphs.single.text, text);
        expect(controller.canUndo, isFalse);
      },
    );
  }

  test(
    'candidate identity, controller owner and pack revision cannot be substituted',
    () async {
      final controller = _controller();
      final service = testThesaurusService();
      final lookup = await _lookup(controller, service: service);
      final term = _term(lookup, 'depository');
      final forged = OfficeThesaurusTerm(id: term.id, text: term.text);
      expect(controller.applyThesaurusTerm(lookup, forged), isFalse);
      expect(_controller().applyThesaurusTerm(lookup, term), isFalse);
      expect(
        controller.applyThesaurusTerm(lookup, _term(lookup, 'bank')),
        isFalse,
      );
      service.clear();
      expect(controller.applyThesaurusTerm(lookup, term), isFalse);
      expect(controller.canUndo, isFalse);
    },
  );

  test(
    'observed selection changes and text edit then undo cannot revive old choices',
    () async {
      final controller = _controller();
      final first = await _lookup(controller);
      _select(controller, 1, 1);
      controller.refreshView();
      _select(controller, 0, 0);
      controller.refreshView();
      expect(controller.isThesaurusLookupCurrent(first), isFalse);
      final second = await _lookup(controller);
      controller.insertText('x');
      controller.undo();
      _select(controller, 0, 0);
      expect(controller.document.paragraphs.single.text, 'bank');
      expect(
        controller.applyThesaurusTerm(second, _term(second, 'depository')),
        isFalse,
      );
    },
  );

  test(
    'word-at-caret preserves full Unicode and internal punctuation ranges',
    () {
      for (final word in [
        'cafe\u0301',
        '😀',
        'ba\u00adnk',
        "bank’s",
        'co-operative',
        '𐐀word',
      ]) {
        final controller = _controller(text: ' $word ');
        _select(controller, 1, 1);
        final capture = controller.captureThesaurusTarget();
        if (word == '😀') {
          expect(capture.status, WordThesaurusTargetStatus.noText);
        } else {
          expect(capture.target?.text, word);
          expect(capture.target?.start, 1);
          expect(capture.target?.end, 1 + word.length);
        }
      }
    },
  );

  test(
    'new language override retires old choices without changing source tags',
    () async {
      final controller = _controller();
      final files = {
        ...thesaurusFixtureAssets(),
        ...thesaurusFixtureAssets(locale: 'de'),
      };
      final service = testThesaurusService(assets: files);
      final first = await _lookup(controller, service: service);
      final second = await controller.lookupThesaurus(
        first.target,
        service,
        languageOverride: 'de-DE',
      );
      expect(
        controller.applyThesaurusTerm(first, _term(first, 'depository')),
        isFalse,
      );
      expect(second.language, 'de-DE');
      expect(second.target.language, 'en-US');
      expect(controller.document.proofingLanguage, 'en-US');
      expect(
        controller.applyThesaurusTerm(second, _term(second, 'Geldinstitut')),
        isTrue,
      );
    },
  );

  test(
    'late old request cannot replace newer lookup or revived source',
    () async {
      final controller = _controller();
      final gate = Completer<void>();
      final target = controller.captureThesaurusTarget().target!;
      final pending = controller.lookupThesaurus(
        target,
        testThesaurusService(gate: gate.future),
      );
      final fresh = await controller.lookupThesaurus(
        target,
        testThesaurusService(),
      );
      gate.complete();
      final late = await pending;
      expect(controller.isThesaurusLookupCurrent(late), isFalse);
      expect(controller.isThesaurusLookupCurrent(fresh), isTrue);
      expect(
        controller.applyThesaurusTerm(late, _term(late, 'depository')),
        isFalse,
      );
      expect(
        controller.applyThesaurusTerm(fresh, _term(fresh, 'depository')),
        isTrue,
      );
    },
  );

  test(
    'source changes while pack loads keep returned result noneditable',
    () async {
      final controller = _controller();
      final gate = Completer<void>();
      final target = controller.captureThesaurusTarget().target!;
      final pending = controller.lookupThesaurus(
        target,
        testThesaurusService(gate: gate.future),
      );
      _select(controller, 1, 1);
      gate.complete();
      final lookup = await pending;
      expect(controller.isThesaurusLookupCurrent(lookup), isFalse);
      expect(
        controller.applyThesaurusTerm(lookup, _term(lookup, 'depository')),
        isFalse,
      );
    },
  );

  for (final protectedKind in [
    'field',
    'page number',
    'no proof',
    'locked block',
    'bound block',
    'pending revision',
    'empty field in range',
  ]) {
    test('$protectedKind gives a clear noneditable capture', () {
      final paragraph = _paragraph('bank');
      final document = _document(paragraph);
      switch (protectedKind) {
        case 'field':
          paragraph.inlines.whereType<WmlRun>().single.fieldInstruction =
              ' REF bank ';
        case 'page number':
          paragraph.properties.pageNumberField = true;
        case 'no proof':
          paragraph.inlines.whereType<WmlRun>().single.properties.noProof =
              true;
        case 'locked block':
        case 'bound block':
          document.sections.single.blocks
            ..clear()
            ..add(
              WmlContentControlBlock(
                control: _control(
                  lock: protectedKind == 'bound block'
                      ? 'unlocked'
                      : 'contentLocked',
                  bound: protectedKind == 'bound block',
                ),
                blocks: [paragraph],
              ),
            );
        case 'pending revision':
          WordRevisions.record(
            document,
            kind: WmlRevisionKind.insert,
            paragraph: paragraph,
            paragraphIndex: 0,
            start: 0,
            end: 4,
            text: 'bank',
            author: 'Tester',
          );
        case 'empty field in range':
          paragraph.inlines
            ..clear()
            ..addAll([
              WmlRun(text: 'ba'),
              WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
              WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
              WmlRun(text: 'nk'),
            ]);
      }
      final controller = _controller(document: document);
      _select(controller, 0, paragraph.text.length);
      final capture = controller.captureThesaurusTarget();
      expect(capture.status, WordThesaurusTargetStatus.protectedContent);
      expect(capture.target, isNull);
      expect(capture.message, isNotEmpty);
      expect(controller.canUndo, isFalse);
    });
  }

  test(
    'partial surrogate and combining mark selections never become targets',
    () {
      for (final sample in [
        (text: '😀bank', start: 1, end: 6),
        (text: 'cafe\u0301', start: 0, end: 4),
      ]) {
        final controller = _controller(text: sample.text);
        _select(controller, sample.start, sample.end);
        expect(
          controller.captureThesaurusTarget().status,
          WordThesaurusTargetStatus.invalidRange,
        );
      }
    },
  );

  test('active IME is neither committed nor cleared by capture', () {
    final controller = _controller();
    controller.input.composing = const TextRange(start: 0, end: 4);
    expect(
      controller.captureThesaurusTarget().status,
      WordThesaurusTargetStatus.composing,
    );
    expect(controller.input.composing, const TextRange(start: 0, end: 4));
    expect(controller.canUndo, isFalse);
  });

  test(
    'selection spanning paragraphs is explicit and leaves source untouched',
    () {
      final controller = _controller(
        document: WmlDocument(
          sections: [
            WmlSection(blocks: [_paragraph('bank'), _paragraph('fast')]),
          ],
        ),
      );
      controller.caret
        ..paragraphIndex = 1
        ..logicalIndex = 4
        ..selectionAnchorParagraph = 0
        ..selectionAnchor = 0;
      expect(
        controller.captureThesaurusTarget().status,
        WordThesaurusTargetStatus.multipleParagraphs,
      );
      expect(controller.canUndo, isFalse);
    },
  );

  test('read-only selection can look up but cannot apply', () async {
    final controller = _controller();
    controller.setMode(OfficeInteractionMode.selecting);
    final lookup = await _lookup(controller);
    expect(lookup.result.status, OfficeThesaurusStatus.ready);
    expect(
      controller.applyThesaurusTerm(lookup, _term(lookup, 'depository')),
      isFalse,
    );
  });

  for (final comment in [false, true]) {
    test(
      'active ${comment ? 'comment' : 'header'} has independent source and history',
      () async {
        final targetParagraph = _paragraph('bank');
        final other = _paragraph('Other');
        final document = WmlDocument(
          sections: [
            WmlSection(
              blocks: [_paragraph('Body')],
              header: comment ? [] : [targetParagraph],
              footer: comment ? [] : [other],
            ),
          ],
          comments: comment
              ? [
                  WmlComment(id: 1, paragraphs: [targetParagraph]),
                  WmlComment(id: 2, paragraphs: [other]),
                ]
              : [],
        );
        final controller = _controller(document: document);
        void selectStory(bool first) {
          if (comment) {
            controller.beginCommentEdit(first ? 1 : 2);
          } else {
            controller.beginHeaderFooterEdit(0, footer: !first);
          }
        }

        selectStory(true);
        _select(controller, 0, 4);
        final lookup = await _lookup(controller);
        expect(
          controller.applyThesaurusTerm(lookup, _term(lookup, 'depository')),
          isTrue,
        );
        selectStory(false);
        _select(controller, 1, 2);
        controller.undo();
        expect(targetParagraph.text, 'bank');
        expect(controller.caret.logicalIndex, 2);
        expect(controller.caret.selectionAnchor, 1);
        controller.redo();
        expect(targetParagraph.text, 'depository');
        expect(controller.caret.logicalIndex, 2);
        expect(controller.caret.selectionAnchor, 1);
        selectStory(true);
        controller.undo();
        expect(controller.caret.logicalIndex, 4);
        expect(controller.caret.selectionAnchor, 0);
      },
    );
  }
}
