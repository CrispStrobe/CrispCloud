import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

class _CorrectionProvider extends OfficeProofingProvider {
  _CorrectionProvider({
    this.replacements = const <String>['Fehler'],
    this.insertAtEnd = false,
  });
  final List<String> replacements;
  final bool insertAtEnd;
  @override
  String get id => 'correction-test';
  @override
  bool supportsLanguage(String language) => true;
  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async =>
      OfficeProofingResult(
        request: request,
        providerId: id,
        status: OfficeProofingStatus.success,
        findings: <OfficeProofingFinding>[
          if (insertAtEnd)
            OfficeProofingFinding.forRequest(
              request,
              providerId: id,
              start: request.text.length,
              end: request.text.length,
              ruleId: 'punctuation',
              message: 'Add punctuation.',
              category: OfficeProofingCategory.grammar,
              replacements: replacements,
            )
          else
            for (final match in RegExp('Feler').allMatches(request.text))
              OfficeProofingFinding.forRequest(
                request,
                providerId: id,
                start: match.start,
                end: match.end,
                ruleId: 'spelling',
                message: 'Check spelling.',
                category: OfficeProofingCategory.spelling,
                replacements: replacements,
              ),
        ],
      );
}

WordEditorController _controller({
  WmlDocument? document,
  String text = 'Feler',
  List<String> replacements = const <String>['Fehler'],
  bool insertAtEnd = false,
}) {
  final controller = WordEditorController(
    document: document ?? WmlDocument.empty(text: text),
  );
  controller.proofing.configure(
    OfficeProofingService(
      providers: <OfficeProofingProvider>[
        _CorrectionProvider(
          replacements: replacements,
          insertAtEnd: insertAtEnd,
        ),
      ],
    ),
  );
  addTearDown(controller.dispose);
  return controller;
}

WmlParagraph _paragraph(String text) =>
    WmlParagraph(inlines: <WmlInline>[WmlRun(text: text)]);
WmlDocument _document(WmlParagraph paragraph) => WmlDocument(
  sections: <WmlSection>[
    WmlSection(blocks: <WmlBlock>[paragraph]),
  ],
);

Future<WordProofingIssue> _issue(WordEditorController controller) async =>
    (await controller.checkDocumentProofing()).issues.single;

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
  relationships: <WmlOpaqueRelationship>[],
);

String _t(String text) => '<w:r><w:t xml:space="preserve">$text</w:t></w:r>';
String _field(String kind, String text) => kind == 'simple'
    ? '<w:fldSimple w:instr=" QUDS_TEST_FIELD ">${_t(text)}</w:fldSimple>'
    : '<w:r><w:fldChar w:fldCharType="begin"/></w:r>'
          '<w:r><w:instrText> QUDS_TEST_FIELD </w:instrText></w:r>'
          '<w:r><w:fldChar w:fldCharType="separate"/></w:r>'
          '${text.isEmpty ? '' : _t(text)}'
          '<w:r><w:fldChar w:fldCharType="end"/></w:r>';

WmlDocument _read(String body) {
  final package = OpcPackage.create(OpcPackageKind.word);
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="${OfficeNamespaces.w}"><w:body>$body<w:sectPr/></w:body></w:document>',
      );
  return WordDeserializer().read(package);
}

Iterable<XmlElement> _elements(XmlElement element, String name) sync* {
  for (final child in element.childElements) {
    if (child.namespaceUri == OfficeNamespaces.w && child.localName == name) {
      yield child;
    }
    yield* _elements(child, name);
  }
}

void _reject(WordEditorController controller, WordProofingIssue issue) {
  final text = issue.paragraph.text;
  expect(controller.canApplyProofingIssue(issue), isFalse);
  expect(controller.applyProofingSuggestion(issue, 'Fehler'), isFalse);
  expect(issue.paragraph.text, text);
  expect(controller.canUndo, isFalse);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final comment in <bool>[true, false]) {
    test(
      'correction history preserves the selection after switching ${comment ? 'comments' : 'header/footer stories'}',
      () async {
        final corrected = _paragraph('Prefix Feler suffix');
        final other = _paragraph('OK');
        final document = WmlDocument(
          sections: <WmlSection>[
            WmlSection(
              blocks: <WmlBlock>[_paragraph('Body')],
              header: comment ? <WmlParagraph>[] : <WmlParagraph>[corrected],
              footer: comment ? <WmlParagraph>[] : <WmlParagraph>[other],
            ),
          ],
          comments: comment
              ? <WmlComment>[
                  WmlComment(id: 1, paragraphs: <WmlParagraph>[corrected]),
                  WmlComment(id: 2, paragraphs: <WmlParagraph>[other]),
                ]
              : <WmlComment>[],
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
        controller.caret
          ..logicalIndex = 12
          ..selectionAnchor = 7;
        final issue = await _issue(controller);
        expect(controller.applyProofingSuggestion(issue, 'Fehler'), isTrue);
        expect(corrected.text, 'Prefix Fehler suffix');
        selectStory(false);
        controller.caret
          ..logicalIndex = 2
          ..selectionAnchor = 1;
        void expectOtherSelection() {
          expect(controller.caret.paragraphIndex, 0);
          expect(controller.caret.logicalIndex, 2);
          expect(controller.caret.selectionAnchorParagraph, 0);
          expect(controller.caret.selectionAnchor, 1);
          if (comment) {
            expect(controller.selectedCommentId, 2);
          } else {
            expect(controller.isEditingFooter, isTrue);
          }
        }

        controller.undo();
        expect(corrected.text, 'Prefix Feler suffix');
        expectOtherSelection();
        controller.redo();
        expect(corrected.text, 'Prefix Fehler suffix');
        expectOtherSelection();
        selectStory(true);
        controller.undo();
        expect(corrected.text, 'Prefix Feler suffix');
        expect(controller.caret.logicalIndex, 12);
        expect(controller.caret.selectionAnchor, 7);
      },
    );
  }

  for (final tracked in <bool>[false, true]) {
    test(
      'correction restores caret and selection through undo/redo (tracking: $tracked)',
      () async {
        final paragraph = _paragraph('😀 Feler Ende');
        final controller = _controller(
          document: WmlDocument(
            sections: <WmlSection>[
              WmlSection(blocks: <WmlBlock>[_paragraph('Intro'), paragraph]),
            ],
          ),
        );
        controller.document.trackRevisions = tracked;
        controller.caret
          ..paragraphIndex = 1
          ..logicalIndex = 8
          ..selectionAnchorParagraph = 0
          ..selectionAnchor = 2;
        final issue = await _issue(controller);
        expect(controller.applyProofingSuggestion(issue, 'Fehler'), isTrue);
        expect(controller.caret.paragraphIndex, 1);
        expect(controller.caret.logicalIndex, tracked ? 14 : 9);
        expect(controller.caret.isCollapsed, isTrue);
        controller.undo();
        expect(paragraph.text, '😀 Feler Ende');
        expect(controller.caret.paragraphIndex, 1);
        expect(controller.caret.logicalIndex, 8);
        expect(controller.caret.selectionAnchorParagraph, 0);
        expect(controller.caret.selectionAnchor, 2);
        controller.caret
          ..paragraphIndex = 0
          ..logicalIndex = 0
          ..collapseSelection();
        controller.redo();
        expect(
          paragraph.text,
          tracked ? '😀 FelerFehler Ende' : '😀 Fehler Ende',
        );
        expect(controller.caret.paragraphIndex, 1);
        expect(controller.caret.logicalIndex, tracked ? 14 : 9);
        expect(controller.caret.isCollapsed, isTrue);
      },
    );
  }

  test('zero-width findings are hit only at their insertion point', () async {
    final controller = _controller(
      text: 'Text',
      insertAtEnd: true,
      replacements: <String>['.'],
    );
    final issue = await _issue(controller);
    expect(controller.proofing.issuesAt(issue.paragraph, 3), isEmpty);
    expect(
      controller.proofing.issuesAt(issue.paragraph, 4),
      <WordProofingIssue>[issue],
    );
    expect(controller.proofing.issuesAt(issue.paragraph, 5), isEmpty);
  });

  test(
    'already-enabled hyphenation on an untagged document saves the default language with reversible history',
    () {
      final controller = _controller(text: 'Silbentrennung');
      controller.document.autoHyphenation = true;
      expect(controller.document.proofingLanguage, isNull);
      controller.setAutomaticHyphenation(true);
      expect(controller.document.autoHyphenation, isTrue);
      expect(controller.document.proofingLanguage, 'de-DE');
      expect(controller.canUndo, isTrue);
      controller.undo();
      expect(controller.document.autoHyphenation, isTrue);
      expect(controller.document.proofingLanguage, isNull);
      expect(controller.canUndo, isFalse);
      controller.redo();
      expect(controller.document.autoHyphenation, isTrue);
      expect(controller.document.proofingLanguage, 'de-DE');
      expect(controller.document.paragraphs.single.text, 'Silbentrennung');
    },
  );

  test(
    'a correction across styled runs after emoji preserves source styles and one undo/redo step',
    () async {
      final paragraph = WmlParagraph(
        inlines: <WmlInline>[
          WmlRun(
            text: '😀 ',
            properties: WmlRunProps(color: '224466'),
          ),
          WmlRun(text: 'Fe', properties: WmlRunProps(bold: true)),
          WmlRun(text: 'ler', properties: WmlRunProps(italic: true)),
          WmlRun(
            text: ' Ende',
            properties: WmlRunProps(fontSizeHalfPoints: 28),
          ),
        ],
      );
      final controller = _controller(document: _document(paragraph));
      final issue = await _issue(controller);
      expect((issue.finding.start, issue.finding.end), (3, 8));
      expect(controller.applyProofingSuggestion(issue, 'Fehler'), isTrue);
      expect(paragraph.text, '😀 Fehler Ende');
      final runs = paragraph.inlines.whereType<WmlRun>().toList();
      expect(runs.first.properties.color, '224466');
      expect(
        runs.where((run) => run.text.contains('Fehler')).single.properties.bold,
        isTrue,
      );
      expect(runs.last.properties.fontSizeHalfPoints, 28);
      controller.undo();
      expect(paragraph.text, '😀 Feler Ende');
      expect(
        paragraph.inlines.whereType<WmlRun>().map((run) => run.text),
        <String>['😀 ', 'Fe', 'ler', ' Ende'],
      );
      expect(
        paragraph.inlines.whereType<WmlRun>().elementAt(2).properties.italic,
        isTrue,
      );
      expect(controller.canUndo, isFalse);
      controller.redo();
      expect(paragraph.text, '😀 Fehler Ende');
      final copy = WordDeserializer().readBytes(controller.saveBytes());
      expect(copy.paragraphs.single.text, '😀 Fehler Ende');
      expect(
        copy.paragraphs.single.inlines
            .whereType<WmlRun>()
            .last
            .properties
            .fontSizeHalfPoints,
        28,
      );
    },
  );

  test(
    'empty replacement suggestions delete text and remain undoable',
    () async {
      final controller = _controller(
        text: 'Feler tail',
        replacements: <String>[''],
      );
      final issue = await _issue(controller);
      expect(controller.applyProofingSuggestion(issue, ''), isTrue);
      expect(controller.document.paragraphs.single.text, ' tail');
      controller.undo();
      expect(controller.document.paragraphs.single.text, 'Feler tail');
      controller.redo();
      expect(controller.document.paragraphs.single.text, ' tail');
    },
  );

  test(
    'zero-width punctuation suggestions use a UTF-16 boundary after emoji',
    () async {
      final controller = _controller(
        text: '😀 Gut',
        replacements: <String>['.'],
        insertAtEnd: true,
      );
      final issue = await _issue(controller);
      expect((issue.finding.start, issue.finding.end), (6, 6));
      expect(controller.applyProofingSuggestion(issue, '.'), isTrue);
      expect(controller.document.paragraphs.single.text, '😀 Gut.');
      controller.undo();
      expect(controller.document.paragraphs.single.text, '😀 Gut');
    },
  );

  test(
    'unoffered and multiline replacements do not open an undo transaction',
    () async {
      final controller = _controller(
        replacements: <String>['Fehler', 'line\nbreak'],
      );
      final issue = await _issue(controller);
      expect(controller.applyProofingSuggestion(issue, 'Not offered'), isFalse);
      expect(controller.applyProofingSuggestion(issue, 'line\nbreak'), isFalse);
      expect(controller.document.paragraphs.single.text, 'Feler');
      expect(controller.canUndo, isFalse);
    },
  );

  test(
    'a host switching to read-only prevents applying an existing result',
    () async {
      final controller = _controller();
      final issue = await _issue(controller);
      controller.setMode(OfficeInteractionMode.viewing);
      _reject(controller, issue);
    },
  );

  test(
    'live document protection prevents a result even before host mode synchronization',
    () async {
      final controller = _controller();
      final issue = await _issue(controller);
      controller.document
        ..restrictEditing = true
        ..restrictMode = WmlRestrictMode.readOnly;
      _reject(controller, issue);
    },
  );

  test(
    'active IME composition blocks correction without invalidating the unchanged result',
    () async {
      final controller = _controller();
      final issue = await _issue(controller);
      controller.input.setValue(
        const TextEditingValue(
          text: 'Feler',
          selection: TextSelection.collapsed(offset: 5),
          composing: TextRange(start: 0, end: 5),
        ),
      );
      expect(controller.proofing.isCurrent(issue), isTrue);
      _reject(controller, issue);
      controller.input.setValue(
        const TextEditingValue(
          text: 'Feler',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );
      expect(controller.applyProofingSuggestion(issue, 'Fehler'), isTrue);
    },
  );

  test(
    'same-length source edits reject stale suggestions without a revision callback',
    () async {
      final controller = _controller();
      final issue = await _issue(controller);
      issue.paragraph.inlines.whereType<WmlRun>().single.text = 'Felar';
      _reject(controller, issue);
    },
  );

  test(
    'a replaced document with the same text does not accept findings from the prior document',
    () async {
      final controller = _controller();
      final issue = await _issue(controller);
      controller.document = WmlDocument.empty(text: 'Feler');
      _reject(controller, issue);
      expect(controller.document.paragraphs.single.text, 'Feler');
    },
  );

  test(
    'changing only noProof semantics invalidates an old finding and excludes a fresh check',
    () async {
      final controller = _controller();
      final issue = await _issue(controller);
      issue.paragraph.inlines.whereType<WmlRun>().single.properties.noProof =
          true;
      _reject(controller, issue);
      final fresh = await controller.checkDocumentProofing();
      expect(fresh.issues, isEmpty);
      expect(fresh.complete, isFalse);
      expect(fresh.skippedContentCount, greaterThan(0));
    },
  );

  for (final location in <String>['inline', 'container', 'wrapper']) {
    test(
      'live $location content-control locks reject old and freshly checked corrections',
      () async {
        final controller = _controller();
        final issue = await _issue(controller);
        final paragraph = issue.paragraph;
        final lock = _control();
        switch (location) {
          case 'inline':
            paragraph.inlines
              ..insert(0, WmlContentControlBoundary(control: lock, start: true))
              ..add(WmlContentControlBoundary(control: lock, start: false));
          case 'container':
            controller.document.sections.single.blocks[0] =
                WmlContentControlBlock(
                  control: lock,
                  blocks: <WmlBlock>[paragraph],
                );
          case 'wrapper':
            paragraph.contentControlWrappers.add(lock);
        }
        _reject(controller, issue);
        _reject(controller, await _issue(controller));
      },
    );
  }

  test(
    'data-bound content is reviewable but cannot be rewritten even without a content lock',
    () async {
      final paragraph = _paragraph('Feler');
      paragraph.contentControlWrappers.add(
        _control(lock: 'unlocked', bound: true),
      );
      final controller = _controller(document: _document(paragraph));
      _reject(controller, await _issue(controller));
    },
  );

  test(
    'an sdtLocked container still permits edits to its unlocked text content',
    () async {
      final paragraph = _paragraph('Feler');
      final controller = _controller(
        document: WmlDocument(
          sections: <WmlSection>[
            WmlSection(
              blocks: <WmlBlock>[
                WmlContentControlBlock(
                  control: _control(lock: 'sdtLocked'),
                  blocks: <WmlBlock>[paragraph],
                ),
              ],
            ),
          ],
        ),
      );
      expect(
        controller.applyProofingSuggestion(await _issue(controller), 'Fehler'),
        isTrue,
      );
      expect(paragraph.text, 'Fehler');
    },
  );

  test(
    'simple generic field results are excluded while adjacent ordinary text remains correctable',
    () async {
      final controller = _controller(
        document: _read(
          '<w:p>${_t('Feler ')}${_field('simple', 'Feler')}${_t(' tail')}</w:p>',
        ),
      );
      final issue = await _issue(controller);
      expect(issue.finding.start, 0);
      expect(controller.applyProofingSuggestion(issue, 'Fehler'), isTrue);
      expect(controller.document.paragraphs.single.text, 'Fehler Feler tail');
      final package = OpcPackage.openBytes(controller.saveBytes());
      final root = XmlDocument.parse(
        package.getPart('/word/document.xml')!.readText(),
      ).root!;
      expect(_elements(root, 'fldSimple').single.text, 'Feler');
    },
  );

  test(
    'complex fields spanning paragraphs and sections exclude cached results but permit text after the end',
    () async {
      final first = WmlParagraph(
        inlines: <WmlInline>[
          WmlRun(text: 'Outside '),
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
          WmlFieldBoundary(
            kind: WmlFieldBoundaryKind.instruction,
            text: ' REF bookmark ',
          ),
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
          WmlRun(text: 'Feler'),
        ],
      );
      final second = WmlParagraph(
        inlines: <WmlInline>[
          WmlRun(text: 'Feler'),
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
          WmlRun(text: ' Feler'),
        ],
      );
      final controller = _controller(
        document: WmlDocument(
          sections: <WmlSection>[
            WmlSection(blocks: <WmlBlock>[first]),
            WmlSection(blocks: <WmlBlock>[second]),
          ],
        ),
      );
      final issue = await _issue(controller);
      expect(issue.paragraph, same(second));
      expect(issue.finding.start, 6);
      expect(controller.applyProofingSuggestion(issue, 'Fehler'), isTrue);
      expect(first.text, 'Outside Feler');
      expect(second.text, 'Feler Fehler');
    },
  );

  test(
    'paragraph-level generic fields never produce editable cached-text findings',
    () async {
      final paragraph = _paragraph('Feler');
      paragraph.properties.fieldInstruction = ' REF bookmark ';
      final controller = _controller(document: _document(paragraph));
      final summary = await controller.checkDocumentProofing();
      expect(summary.issues, isEmpty);
      expect(summary.complete, isFalse);
    },
  );

  for (final kind in <String>['simple', 'complex', 'empty complex']) {
    test(
      'tracked correction immediately before $kind field cannot insert into that field',
      () async {
        final controller = _controller(
          document: _read(
            '<w:p>${_t('Feler')}${_field(kind, kind == 'empty complex' ? '' : 'Cached')}${_t(' tail')}</w:p>',
          ),
        );
        controller.document.trackRevisions = true;
        final issue = await _issue(controller);
        _reject(controller, issue);
        expect(controller.document.revisions, isEmpty);
      },
    );
  }

  test(
    'tracked correction ending at a locked inline control boundary cannot inherit its insertion affinity',
    () async {
      final lock = _control();
      final paragraph = WmlParagraph(
        inlines: <WmlInline>[
          WmlRun(text: 'Feler'),
          WmlContentControlBoundary(control: lock, start: true),
          WmlRun(text: 'Locked'),
          WmlContentControlBoundary(control: lock, start: false),
        ],
      );
      final controller = _controller(document: _document(paragraph));
      controller.document.trackRevisions = true;
      _reject(controller, await _issue(controller));
      expect(paragraph.text, 'FelerLocked');
      expect(controller.document.revisions, isEmpty);
    },
  );

  test(
    'tracked correction creates separate valid deletion and insertion with undo and DOCX accept/reject',
    () async {
      final controller = _controller(text: '😀 Feler.');
      controller.document.trackRevisions = true;
      expect(
        controller.applyProofingSuggestion(await _issue(controller), 'Fehler'),
        isTrue,
      );
      final paragraph = controller.document.paragraphs.single;
      expect(paragraph.text, '😀 FelerFehler.');
      expect(
        controller.document.revisions.map(
          (revision) =>
              (revision.kind, revision.start, revision.end, revision.text),
        ),
        <(WmlRevisionKind, int, int, String)>[
          (WmlRevisionKind.delete, 3, 8, 'Feler'),
          (WmlRevisionKind.insert, 8, 14, 'Fehler'),
        ],
      );
      WordRevisions.validate(controller.document);
      controller.undo();
      expect(paragraph.text, '😀 Feler.');
      expect(controller.document.revisions, isEmpty);
      expect(controller.canUndo, isFalse);
      controller.redo();
      WordRevisions.validate(controller.document);
      final bytes = controller.saveBytes();
      final native = XmlDocument.parse(
        OpcPackage.openBytes(bytes).getPart('/word/document.xml')!.readText(),
      ).root!;
      expect(_elements(native, 'del').single.text, 'Feler');
      expect(_elements(native, 'ins').single.text, 'Fehler');
      final accepted = WordDeserializer().readBytes(bytes);
      WordRevisions.validate(accepted);
      WordRevisions.acceptAll(accepted);
      expect(accepted.paragraphs.single.text, '😀 Fehler.');
      final rejected = WordDeserializer().readBytes(bytes);
      WordRevisions.validate(rejected);
      WordRevisions.rejectAll(rejected);
      expect(rejected.paragraphs.single.text, '😀 Feler.');
    },
  );

  test(
    'tracked deletion suggestions create only a deletion and preserve accept/reject semantics',
    () async {
      final controller = _controller(
        text: 'Feler tail',
        replacements: <String>[''],
      );
      controller.document.trackRevisions = true;
      expect(
        controller.applyProofingSuggestion(await _issue(controller), ''),
        isTrue,
      );
      expect(controller.document.revisions.single.kind, WmlRevisionKind.delete);
      WordRevisions.validate(controller.document);
      final bytes = controller.saveBytes();
      final accepted = WordDeserializer().readBytes(bytes);
      WordRevisions.acceptAll(accepted);
      expect(accepted.paragraphs.single.text, ' tail');
      final rejected = WordDeserializer().readBytes(bytes);
      WordRevisions.rejectAll(rejected);
      expect(rejected.paragraphs.single.text, 'Feler tail');
    },
  );

  test(
    'legacy pending insert revisions without targetParagraph block overlapping proofing edits',
    () async {
      final controller = _controller();
      final revision = WmlRevision(
        id: 99,
        kind: WmlRevisionKind.insert,
        paragraphIndex: 0,
        start: 0,
        end: 5,
        text: 'Feler',
      );
      controller.document.revisions.add(revision);
      expect(revision.targetParagraph, isNull);
      _reject(controller, await _issue(controller));
      expect(controller.document.revisions.single, same(revision));
      WordRevisions.validate(controller.document);
    },
  );

  test(
    'hyphenation on an untagged document saves its displayed language in the same undo step',
    () {
      final controller = _controller(text: 'Silbentrennung');
      expect(controller.document.proofingLanguage, isNull);
      expect(controller.proofing.language, 'de-DE');
      controller.setAutomaticHyphenation(true);
      expect(controller.document.autoHyphenation, isTrue);
      expect(controller.document.proofingLanguage, 'de-DE');
      controller.undo();
      expect(controller.document.autoHyphenation, isFalse);
      expect(controller.document.proofingLanguage, isNull);
      expect(controller.canUndo, isFalse);
      controller.redo();
      expect(controller.document.autoHyphenation, isTrue);
      expect(controller.document.proofingLanguage, 'de-DE');
      expect(controller.document.paragraphs.single.text, 'Silbentrennung');
    },
  );

  test(
    'adding a zero-width field with identical paragraph text invalidates prior structure-bound findings',
    () async {
      final controller = _controller();
      final issue = await _issue(controller);
      issue.paragraph.inlines.insertAll(0, <WmlInline>[
        WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
        WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
        WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
      ]);
      expect(issue.paragraph.text, 'Feler');
      _reject(controller, issue);
      expect((await controller.checkDocumentProofing()).issues, hasLength(1));
    },
  );
}
