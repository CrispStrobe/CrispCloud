import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

WmlParagraph _paragraph(String text, {String? language}) => WmlParagraph(
  properties: WmlParagraphProps(proofingLanguage: language),
  inlines: [WmlRun(text: text)],
);

class _Provider extends OfficeProofingProvider {
  _Provider({
    this.languages,
    this.status = OfficeProofingStatus.success,
    this.gate,
    this.replacements = const ['Fehler'],
    this.emptyInsertion = false,
  });
  final Set<String>? languages;
  final OfficeProofingStatus status;
  final Completer<void>? gate;
  final List<String> replacements;
  final bool emptyInsertion;
  final started = Completer<void>();
  final requests = <OfficeProofingRequest>[];
  bool disposed = false;
  int revision = 0;
  @override
  String get id => 'test';
  @override
  int get configurationRevision => revision;
  @override
  bool supportsLanguage(String language) =>
      languages?.contains(language) ?? true;
  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async {
    requests.add(request);
    if (!started.isCompleted) started.complete();
    await gate?.future;
    return OfficeProofingResult(
      request: request,
      providerId: id,
      status: status,
      findings:
          status != OfficeProofingStatus.success ||
              request.ignoredRuleIds.contains('test.spelling')
          ? []
          : [
              if (emptyInsertion && request.text.isEmpty)
                OfficeProofingFinding.forRequest(
                  request,
                  providerId: id,
                  start: 0,
                  end: 0,
                  ruleId: 'test.spelling',
                  message: 'Insert punctuation',
                  category: OfficeProofingCategory.grammar,
                  replacements: const ['.'],
                ),
              for (final match in RegExp('Feler').allMatches(request.text))
                OfficeProofingFinding.forRequest(
                  request,
                  providerId: id,
                  start: match.start,
                  end: match.end,
                  ruleId: 'test.spelling',
                  message: 'Use Fehler',
                  category: OfficeProofingCategory.spelling,
                  replacements: replacements,
                ),
            ],
    );
  }

  @override
  Future<void> dispose() async => disposed = true;
}

WordEditorController _controller(
  WmlDocument doc, {
  _Provider? provider,
  OfficeProofingService? service,
  OfficeProofingVocabulary? vocabulary,
}) {
  final c = WordEditorController(
    document: doc,
    proofingService:
        service ?? OfficeProofingService(providers: [provider ?? _Provider()]),
    proofingVocabulary: vocabulary,
  );
  addTearDown(c.dispose);
  return c;
}

WmlDocument _document(List<WmlBlock> blocks) =>
    WmlDocument(sections: [WmlSection(blocks: blocks)]);

WmlContentControlData _control(String lock) => WmlContentControlData(
  xml:
      '<w:sdt xmlns:w="${OfficeNamespaces.w}"><w:sdtPr>'
      '<w:lock w:val="$lock"/></w:sdtPr><w:sdtContent/></w:sdt>',
  sourcePartUri: '/word/document.xml',
  relationships: const [],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('caret issue lookup keeps an empty read-only story unchanged', () {
    final doc = _document([]);
    final c = _controller(doc);
    c.setMode(OfficeInteractionMode.viewing);
    expect(doc.paragraphs, isEmpty);
    expect(doc.sections.single.blocks, isEmpty);
    expect(c.proofingIssuesAtCaret, isEmpty);
    expect(doc.paragraphs, isEmpty);
    expect(doc.sections.single.blocks, isEmpty);
    expect(c.canUndo, isFalse);
  });

  test(
    'standard header and footer findings navigate to the exact rendered story',
    () async {
      final doc = _document([_paragraph('Body')]);
      final header = _paragraph('Feler header');
      final footer = _paragraph('Feler footer');
      final firstHeader = _paragraph('Feler alternate');
      doc.sections.single.header.addAll([_paragraph('Header context'), header]);
      doc.sections.single.footer.addAll([_paragraph('Footer context'), footer]);
      doc.sections.single.firstHeader.add(firstHeader);
      final c = _controller(doc);
      await c.checkDocumentProofing();
      for (final (paragraph, isFooter) in [(header, false), (footer, true)]) {
        final issue = c.proofing.issuesForParagraph(paragraph).single;
        expect(c.proofing.canSelectIssue(issue), isTrue);
        expect(c.revealProofingIssue(issue), isTrue);
        expect(c.isEditingHeaderFooter, isTrue);
        expect(c.isEditingFooter, isFooter);
        expect(c.headerFooterParagraphs[1], same(paragraph));
        expect(c.headerFooterCaret.paragraphIndex, 1);
        expect(c.headerFooterCaret.selectionAnchor, 0);
        expect(c.headerFooterCaret.logicalIndex, 5);
        expect(c.input.value.text, paragraph.text);
        expect(
          c.input.value.selection,
          const TextSelection(baseOffset: 0, extentOffset: 5),
        );
      }
      final alternate = c.proofing.issuesForParagraph(firstHeader).single;
      expect(c.proofing.canSelectIssue(alternate), isFalse);
      expect(c.revealProofingIssue(alternate), isFalse);
      expect(c.headerFooterParagraphs[1], same(footer));
    },
  );

  test(
    'imported body and comment style languages/noProof have effective inherited semantics',
    () async {
      final package = OpcPackage.create(OpcPackageKind.word);
      const body = '''<w:document xmlns:w="${OfficeNamespaces.w}"><w:body>
<w:p><w:pPr><w:pStyle w:val="Derived"/></w:pPr>
<w:r><w:t>Feler </w:t></w:r>
<w:r><w:rPr><w:rStyle w:val="Check"/></w:rPr><w:t>Feler</w:t></w:r></w:p>
</w:body></w:document>''';
      package.getPart('/word/document.xml')!.writeText(body);
      package.createPart(
        '/word/styles.xml',
        OfficeContentTypes.wordStyles,
        utf8.encode('''<w:styles xmlns:w="${OfficeNamespaces.w}">
<w:docDefaults><w:rPrDefault><w:rPr><w:lang w:val="de-DE"/></w:rPr></w:rPrDefault></w:docDefaults>
<w:style w:type="paragraph" w:styleId="Base"><w:name w:val="Base"/>
<w:rPr><w:lang w:val="de-CH"/><w:noProof/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Derived"><w:name w:val="Derived"/><w:basedOn w:val="Base"/></w:style>
<w:style w:type="character" w:styleId="Check"><w:name w:val="Check"/>
<w:rPr><w:noProof w:val="0"/></w:rPr></w:style></w:styles>'''),
      );
      package.createPart(
        '/word/comments.xml',
        OfficeContentTypes.wordComments,
        utf8.encode('''<w:comments xmlns:w="${OfficeNamespaces.w}">
<w:comment w:id="0" w:author="Author"><w:p><w:pPr><w:pStyle w:val="Derived"/></w:pPr>
<w:r><w:t>Feler </w:t></w:r>
<w:r><w:rPr><w:rStyle w:val="Check"/><w:lang w:val="de-AT"/></w:rPr><w:t>Feler</w:t></w:r>
</w:p></w:comment></w:comments>'''),
      );
      package.relationshipsFor('/word/document.xml')
        ..add(type: RelationshipTypes.styles, target: 'styles.xml')
        ..add(type: RelationshipTypes.comments, target: 'comments.xml');
      var document = WordDeserializer().read(package);
      for (var cycle = 0; cycle < 2; cycle++) {
        final paragraph = document.comments.single.paragraphs.single;
        final runs = paragraph.inlines.whereType<WmlRun>().toList();
        expect(runs[0].properties.proofingLanguage, 'de-CH');
        expect(runs[0].properties.noProof, isTrue);
        expect(runs[1].properties.proofingLanguage, 'de-AT');
        expect(runs[1].properties.noProof, isFalse);
        final provider = _Provider();
        final controller = _controller(document, provider: provider);
        final report = await controller.proofing.checkDocument();
        expect(report.issues, hasLength(2));
        expect(provider.requests.map((r) => r.language), ['de-CH', 'de-AT']);
        expect(report.issues.map((i) => i.finding.start), [6, 6]);
        expect(report.excludedSpanCount, 2);
        document = WordDeserializer().readBytes(
          WordSerializer().writeBytes(document),
        );
      }
    },
  );

  testWidgets(
    'last detached view cancels debounce while leaving its controller usable',
    (tester) async {
      final provider = _Provider();
      final c = _controller(
        _document([_paragraph('Feler')]),
        provider: provider,
      );
      c.proofing.attachView();
      c.proofing.attachView();
      c.proofing.detachView();
      c.proofing.detachView();
      await tester.pump(const Duration(milliseconds: 400));
      expect(provider.requests, isEmpty);
      expect(c.isDisposed, isFalse);
      await tester.runAsync(() => c.proofing.checkDocument());
      expect(c.proofing.issues, hasLength(1));
    },
  );

  testWidgets(
    'a remaining view and explicit host start keep independent ownership',
    (tester) async {
      final provider = _Provider();
      final c = _controller(
        _document([_paragraph('Gut.')]),
        provider: provider,
      );
      c.proofing.attachView();
      c.proofing.attachView();
      c.proofing.detachView();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(provider.requests, hasLength(1));
      c.proofing.start();
      c.proofing.detachView();
      c.insertText('x');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(provider.requests, hasLength(2));
      c.proofing.stop();
      c.insertText('y');
      await tester.pump(const Duration(milliseconds: 400));
      expect(provider.requests, hasLength(2));
    },
  );

  test(
    'checks all modeled stories and nested tables/frames, not only caret paragraph',
    () async {
      final body = _paragraph('Feler body');
      final cell = _paragraph('Feler table');
      final frame = _paragraph('Feler frame');
      final doc = _document([
        body,
        WmlTable(
          rows: [
            WmlTableRow(
              cells: [
                WmlTableCell(blocks: [cell]),
              ],
            ),
          ],
        ),
        WmlFrame(blocks: [frame]),
      ]);
      final section = doc.sections.single;
      section.header.add(_paragraph('Feler header'));
      section.footer.add(_paragraph('Feler footer'));
      section.firstHeader.add(_paragraph('Feler first header'));
      section.firstFooter.add(_paragraph('Feler first footer'));
      section.evenHeader.add(_paragraph('Feler even header'));
      section.evenFooter.add(_paragraph('Feler even footer'));
      doc.footnotes.add(
        WmlNote(
          id: 1,
          endnote: false,
          paragraphs: [_paragraph('Feler footnote')],
        ),
      );
      doc.endnotes.add(
        WmlNote(
          id: 2,
          endnote: true,
          paragraphs: [_paragraph('Feler endnote')],
        ),
      );
      doc.comments.add(WmlComment(id: 3, text: 'Feler comment'));
      final c = _controller(doc);
      final report = await c.proofing.checkDocument();
      expect(report.paragraphCount, 12);
      expect(report.issues, hasLength(12));
      expect(report.complete, isTrue);
      expect(c.proofing.issuesForParagraph(cell).single.paragraph, same(cell));
      expect(c.proofing.findingsByParagraph[frame], hasLength(1));
      expect(c.proofing.issuesAt(body, 2), hasLength(1));
      expect(c.proofing.issuesAt(body, 5), isEmpty);
      expect(report.issues.map((i) => i.story), contains('Comment 3'));
    },
  );

  test(
    'joins formatting runs and uses UTF-16 source offsets after emoji',
    () async {
      final p = WmlParagraph(
        inlines: [
          WmlRun(text: '😀 Fe', properties: WmlRunProps(bold: true)),
          WmlRun(text: 'ler.'),
        ],
      );
      final provider = _Provider();
      final c = _controller(_document([p]), provider: provider);
      await c.proofing.checkDocument();
      expect(provider.requests.single.text, '😀 Feler.');
      final issue = c.proofing.issues.single;
      expect(issue.finding.start, 3);
      expect(c.proofing.applySuggestion(issue, 'Fehler'), isTrue);
      expect(p.text, '😀 Fehler.');
      c.undo();
      expect(p.text, '😀 Feler.');
      expect(p.inlines.whereType<WmlRun>().first.properties.bold, isTrue);
      c.redo();
      expect(p.text, '😀 Fehler.');
    },
  );

  test(
    'run languages and noProof boundaries produce exact source segments',
    () async {
      final p = WmlParagraph(
        inlines: [
          WmlRun(
            text: 'Feler ',
            properties: WmlRunProps(proofingLanguage: 'de_CH'),
          ),
          WmlRun(text: 'ignored', properties: WmlRunProps(noProof: true)),
          WmlRun(
            text: ' Feler',
            properties: WmlRunProps(proofingLanguage: 'en-GB'),
          ),
        ],
      );
      final provider = _Provider();
      final c = _controller(_document([p]), provider: provider);
      final report = await c.proofing.checkDocument();
      expect(provider.requests.map((r) => r.language), ['de-CH', 'en-GB']);
      expect(provider.requests.map((r) => r.startOffset), [0, 13]);
      expect(report.issues.map((i) => i.finding.start), [0, 14]);
      expect(report.excludedSpanCount, 1);
    },
  );

  test(
    'a shortening correction rebases selection before typing and restores it on undo',
    () async {
      final paragraph = _paragraph('A Feler Z');
      final c = _controller(
        _document([paragraph]),
        provider: _Provider(replacements: const ['']),
      );
      c.caret
        ..selectionAnchor = 2
        ..logicalIndex = 7;
      await c.proofing.checkDocument();
      expect(c.proofing.applySuggestion(c.proofing.issues.single, ''), isTrue);
      expect(paragraph.text, 'A  Z');
      expect(c.caret.logicalIndex, 2);
      expect(c.caret.isCollapsed, isTrue);
      c.insertText('gut');
      expect(paragraph.text, 'A gut Z');
      c.undo();
      expect(paragraph.text, 'A  Z');
      c.undo();
      expect(paragraph.text, 'A Feler Z');
      expect(c.caret.selectionAnchor, 2);
      expect(c.caret.logicalIndex, 7);
    },
  );

  test(
    'unsupported paragraph prevents a partial check from claiming clean',
    () async {
      final provider = _Provider(languages: {'de-DE'});
      final c = _controller(
        _document([_paragraph('Gut.'), _paragraph('Good.', language: 'en-US')]),
        provider: provider,
      );
      final report = await c.proofing.checkDocument();
      expect(report.issues, isEmpty);
      expect(report.complete, isFalse);
      expect(report.isClean, isFalse);
      expect(
        report.results.map((r) => r.status),
        contains(OfficeProofingStatus.unsupported),
      );
    },
  );

  test('unavailable, failed, clean and disabled are distinct', () async {
    final c = _controller(
      _document([_paragraph('Gut.')]),
      service: OfficeProofingService(providers: []),
    );
    expect(
      (await c.proofing.checkDocument()).results.single.status,
      OfficeProofingStatus.unavailable,
    );
    expect(c.proofing.summary.isClean, isFalse);
    c.proofing.configureService(
      OfficeProofingService(
        providers: [_Provider(status: OfficeProofingStatus.failed)],
      ),
    );
    expect(
      (await c.proofing.checkDocument()).results.single.status,
      OfficeProofingStatus.failed,
    );
    c.proofing.configureService(
      OfficeProofingService(providers: [_Provider()]),
    );
    expect((await c.proofing.checkDocument()).isClean, isTrue);
    c.proofing.setEnabled(false);
    expect(c.proofing.summary.enabled, isFalse);
    expect(c.proofing.summary.isClean, isFalse);
  });

  test('opaque content is reported as unchecked', () async {
    final doc = _document([
      _paragraph('Gut.'),
      WmlOpaqueBlock(
        xml: '<w:altChunk/>',
        sourcePartUri: '/word/document.xml',
        relationships: const [],
      ),
    ]);
    final c = _controller(doc);
    final report = await c.proofing.checkDocument();
    expect(report.skippedContentCount, 1);
    expect(report.complete, isFalse);
  });

  test(
    'reuses unchanged paragraphs but rechecks edited source and provider configuration',
    () async {
      final first = _paragraph('Feler one');
      final second = _paragraph('Feler two');
      final provider = _Provider();
      final c = _controller(_document([first, second]), provider: provider);
      await c.proofing.checkDocument();
      expect(provider.requests, hasLength(2));
      await c.proofing.checkDocument();
      expect(provider.requests, hasLength(2));
      first.inlines.whereType<WmlRun>().first.text = 'Feler changed';
      await c.proofing.checkDocument();
      expect(provider.requests, hasLength(3));
      provider.revision++;
      await c.proofing.checkDocument();
      expect(provider.requests, hasLength(5));
    },
  );

  test('asynchronous result is rejected after controller edit', () async {
    final gate = Completer<void>();
    final provider = _Provider(gate: gate);
    final p = _paragraph('Feler');
    final c = _controller(_document([p]), provider: provider);
    final pending = c.proofing.checkDocument();
    await provider.started.future;
    c.insertText('x');
    gate.complete();
    await pending;
    expect(c.proofing.issues, isEmpty);
    expect(c.proofing.summary.hasChecked, isFalse);
  });

  test(
    'direct text and language mutations reject asynchronous result without revision notification',
    () async {
      final gate = Completer<void>();
      final provider = _Provider(gate: gate);
      final p = _paragraph('Feler');
      final c = _controller(_document([p]), provider: provider);
      final pending = c.proofing.checkDocument();
      await provider.started.future;
      p.inlines.whereType<WmlRun>().first.properties.proofingLanguage = 'de-CH';
      gate.complete();
      await pending;
      expect(c.proofing.issues, isEmpty);
      expect(c.proofing.summary.hasChecked, isFalse);
    },
  );

  test('replacing document with identical text rejects old findings', () async {
    final c = _controller(_document([_paragraph('Feler')]));
    await c.proofing.checkDocument();
    final issue = c.proofing.issues.single;
    c.document = _document([_paragraph('Feler')]);
    expect(c.proofing.applySuggestion(issue, 'Fehler'), isFalse);
    expect(c.document.paragraphs.single.text, 'Feler');
  });

  for (final invalidateFirst in [false, true]) {
    test(
      'direct document replacement resets cached reports and ignore-once ${invalidateFirst ? 'after invalidate' : 'on check'}',
      () async {
        final paragraph = _paragraph('Feler');
        final provider = _Provider();
        final c = _controller(_document([paragraph]), provider: provider);
        final original = (await c.proofing.checkDocument()).issues.single;
        c.proofing.ignoreOnce(original);
        expect((await c.proofing.checkDocument()).issues, isEmpty);
        expect(provider.requests, hasLength(1));

        // Hosts can replace the public document directly and reuse a model
        // paragraph; neither operation necessarily notifies the controller.
        c.document = _document([paragraph]);
        if (invalidateFirst) c.proofing.invalidate();
        final report = await c.proofing.checkDocument();
        expect(provider.requests, hasLength(2));
        final issue = report.issues.single;
        expect(issue.paragraph, same(paragraph));
        expect(issue.finding.documentId, isNot(original.finding.documentId));
        expect(issue.finding.documentId, provider.requests.last.documentId);
        expect(c.proofing.isCurrent(original), isFalse);
        expect(c.proofing.isCurrent(issue), isTrue);
        expect(c.canUndo, isFalse);
      },
    );
  }

  for (final kind in [
    'simple field',
    'empty complex field',
    'locked control',
  ]) {
    test('tracked correction cannot insert into an adjacent $kind', () async {
      final control = _control('contentLocked');
      final paragraph = WmlParagraph(
        inlines: [
          WmlRun(text: 'Feler'),
          if (kind == 'simple field')
            WmlRun(text: 'Cached')..fieldInstruction = ' REF target ',
          if (kind == 'empty complex field') ...[
            WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
            WmlFieldBoundary(
              kind: WmlFieldBoundaryKind.instruction,
              text: ' REF target ',
            ),
            WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
            WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
          ],
          if (kind == 'locked control') ...[
            WmlContentControlBoundary(control: control, start: true),
            WmlRun(text: 'Locked'),
            WmlContentControlBoundary(control: control, start: false),
          ],
        ],
      );
      final document = _document([paragraph])..trackRevisions = true;
      final c = _controller(document);
      final original = paragraph.text;
      final issue = (await c.proofing.checkDocument()).issues.single;
      expect(c.proofing.canApply(issue), isFalse);
      expect(c.proofing.applySuggestion(issue, 'Fehler'), isFalse);
      expect(paragraph.text, original);
      expect(document.revisions, isEmpty);
      expect(c.canUndo, isFalse);
    });
  }

  test('correction cannot split a grapheme across language runs', () async {
    final paragraph = WmlParagraph(
      inlines: [
        WmlRun(
          text: 'Feler',
          properties: WmlRunProps(proofingLanguage: 'de-DE'),
        ),
        WmlRun(
          text: '\u0301',
          properties: WmlRunProps(proofingLanguage: 'en-US'),
        ),
      ],
    );
    final c = _controller(_document([paragraph]));
    final issue = (await c.proofing.checkDocument()).issues.single;
    expect(issue.finding.end, 5);
    expect(c.proofing.canApply(issue), isFalse);
    expect(c.proofing.applySuggestion(issue, 'Fehler'), isFalse);
    expect(paragraph.text, 'Feler\u0301');
    expect(c.canUndo, isFalse);
  });

  test('empty complex fields cannot produce an applicable insertion', () async {
    for (final spanning in [false, true]) {
      final first = WmlParagraph(
        inlines: [
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
          WmlFieldBoundary(
            kind: WmlFieldBoundaryKind.instruction,
            text: ' REF target ',
          ),
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
          if (!spanning) WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
        ],
      );
      final last = WmlParagraph(
        inlines: [WmlFieldBoundary(kind: WmlFieldBoundaryKind.end)],
      );
      final provider = _Provider(emptyInsertion: true);
      final c = _controller(
        _document([first, if (spanning) last]),
        provider: provider,
      );
      final report = await c.proofing.checkDocument();
      for (final issue in report.issues) {
        expect(c.proofing.applySuggestion(issue, '.'), isFalse);
      }
      expect(report.issues, isEmpty);
      expect(provider.requests, isEmpty);
      expect(report.excludedSpanCount, greaterThan(0));
      expect(report.complete, isFalse);
      expect(c.document.paragraphs.map((p) => p.text), everyElement(isEmpty));
      expect(c.canUndo, isFalse);
    }
    // An ordinary blank paragraph still supports a real insertion finding.
    final plain = _paragraph('');
    final c = _controller(
      _document([plain]),
      provider: _Provider(emptyInsertion: true),
    );
    final issue = (await c.proofing.checkDocument()).issues.single;
    expect(c.proofing.applySuggestion(issue, '.'), isTrue);
    expect(plain.text, '.');
    c.undo();
    expect(plain.text, '');
  });

  for (final comment in [true, false]) {
    test(
      'correction history preserves selection after switching ${comment ? 'comments' : 'header and footer'}',
      () async {
        final corrected = _paragraph('Prefix Feler suffix');
        final other = _paragraph('OK');
        final document = _document([_paragraph('Body')]);
        if (comment) {
          document.comments.addAll([
            WmlComment(id: 1, paragraphs: [corrected]),
            WmlComment(id: 2, paragraphs: [other]),
          ]);
        } else {
          document.sections.single.header.add(corrected);
          document.sections.single.footer.add(other);
        }
        final c = _controller(document);
        void selectStory(bool first) {
          if (comment) {
            c.beginCommentEdit(first ? 1 : 2);
          } else {
            c.beginHeaderFooterEdit(0, footer: !first);
          }
        }

        selectStory(true);
        c.caret
          ..logicalIndex = 12
          ..selectionAnchor = 7;
        final issue = (await c.proofing.checkDocument()).issues.single;
        expect(c.proofing.applySuggestion(issue, 'Fehler'), isTrue);
        selectStory(false);
        c.caret
          ..logicalIndex = 2
          ..selectionAnchor = 1;
        void expectOtherSelection() {
          expect(c.caret.paragraphIndex, 0);
          expect(c.caret.logicalIndex, 2);
          expect(c.caret.selectionAnchorParagraph, 0);
          expect(c.caret.selectionAnchor, 1);
          expect(other.text, 'OK');
          if (comment) {
            expect(c.selectedCommentId, 2);
          } else {
            expect(c.isEditingFooter, isTrue);
          }
        }

        c.undo();
        expect(corrected.text, 'Prefix Feler suffix');
        expectOtherSelection();
        c.redo();
        expect(corrected.text, 'Prefix Fehler suffix');
        expectOtherSelection();
        selectStory(true);
        c.undo();
        expect(c.caret.logicalIndex, 12);
        expect(c.caret.selectionAnchor, 7);
      },
    );
  }

  test(
    'stale same-text language and generated-field changes block corrections',
    () async {
      final p = _paragraph('Feler');
      final c = _controller(_document([p]));
      await c.proofing.checkDocument();
      final issue = c.proofing.issues.single;
      p.inlines.whereType<WmlRun>().first.fieldInstruction = ' REF target ';
      expect(c.proofing.canApply(issue), isFalse);
      expect(c.proofing.applySuggestion(issue, 'Fehler'), isFalse);
      expect(c.canUndo, isFalse);
    },
  );

  test(
    'page-number field metadata invalidates stale suggestions and excludes its cache',
    () async {
      final header = _paragraph('Feler');
      final doc = _document([_paragraph('Gut.')]);
      doc.sections.single.header.add(header);
      final c = _controller(doc);
      await c.proofing.checkDocument();
      final issue = c.proofing.issues.single;
      header.properties.pageNumberField = true;
      expect(c.proofing.canApply(issue), isFalse);
      expect(c.proofing.applySuggestion(issue, 'Fehler'), isFalse);
      final report = await c.proofing.checkDocument();
      expect(report.issues, isEmpty);
      expect(report.excludedSpanCount, 1);
      expect(header.text, 'Feler');
    },
  );

  test(
    'complex field results spanning paragraphs are excluded while surrounding text is checked',
    () async {
      final first = WmlParagraph(
        inlines: [
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
          WmlFieldBoundary(
            kind: WmlFieldBoundaryKind.instruction,
            text: ' REF target ',
          ),
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
          WmlRun(text: 'Feler'),
        ],
      );
      final second = WmlParagraph(
        inlines: [
          WmlRun(text: 'Feler'),
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
          WmlRun(text: ' Feler'),
        ],
      );
      final c = _controller(_document([first, second]));
      final report = await c.proofing.checkDocument();
      expect(report.issues, hasLength(1));
      expect(report.issues.single.paragraph, same(second));
      expect(report.issues.single.finding.start, 6);
    },
  );

  test(
    'read-only host and active IME block correction without adding history',
    () async {
      final p = _paragraph('Feler');
      final c = _controller(_document([p]));
      await c.proofing.checkDocument();
      final issue = c.proofing.issues.single;
      c.input.composing = const TextRange(start: 0, end: 2);
      expect(c.proofing.applySuggestion(issue, 'Fehler'), isFalse);
      c.input.composing = TextRange.empty;
      c.setMode(OfficeInteractionMode.viewing);
      expect(c.proofing.applySuggestion(issue, 'Fehler'), isFalse);
      expect(p.text, 'Feler');
      expect(c.canUndo, isFalse);
    },
  );

  for (final kind in ['inline', 'block', 'paragraph']) {
    test('native content lock blocks $kind correction', () async {
      final p = _paragraph('Feler');
      final control = _control('contentLocked');
      WmlBlock block = p;
      if (kind == 'inline') {
        p.inlines = [
          WmlContentControlBoundary(control: control, start: true),
          ...p.inlines,
          WmlContentControlBoundary(control: control, start: false),
        ];
      }
      if (kind == 'paragraph') p.contentControlWrappers.add(control);
      if (kind == 'block') {
        block = WmlContentControlBlock(control: control, blocks: [p]);
      }
      final c = _controller(_document([block]));
      await c.proofing.checkDocument();
      final issue = c.proofing.issues.single;
      expect(c.proofing.canApply(issue), isFalse);
      expect(c.proofing.applySuggestion(issue, 'Fehler'), isFalse);
      expect(p.text, 'Feler');
      expect(c.canUndo, isFalse);
    });
  }

  test(
    'a control-only lock permits text correction while preserving its shell',
    () async {
      final control = _control('sdtLocked');
      final p = WmlParagraph(
        inlines: [
          WmlContentControlBoundary(control: control, start: true),
          WmlRun(text: 'Feler'),
          WmlContentControlBoundary(control: control, start: false),
        ],
      );
      final c = _controller(_document([p]));
      await c.proofing.checkDocument();
      expect(
        c.proofing.applySuggestion(c.proofing.issues.single, 'Fehler'),
        isTrue,
      );
      expect(p.inlines.whereType<WmlContentControlBoundary>(), hasLength(2));
      c.undo();
      expect(p.text, 'Feler');
    },
  );

  test(
    'correction in a footnote changes its actual paragraph and undoes independently of focus',
    () async {
      final body = _paragraph('body');
      final note = _paragraph('Feler');
      final doc = _document([body])
        ..footnotes.add(WmlNote(id: 2, endnote: false, paragraphs: [note]));
      final c = _controller(doc);
      await c.proofing.checkDocument();
      expect(
        c.proofing.applySuggestion(c.proofing.issues.single, 'Fehler'),
        isTrue,
      );
      expect(note.text, 'Fehler');
      expect(body.text, 'body');
      c.undo();
      expect(note.text, 'Feler');
      expect(body.text, 'body');
      c.redo();
      expect(note.text, 'Fehler');
    },
  );

  test(
    'tracked correction preserves deletion and insertion with valid nonoverlapping ranges',
    () async {
      final p = _paragraph('Feler');
      final doc = _document([p])..trackRevisions = true;
      final c = _controller(doc);
      await c.proofing.checkDocument();
      expect(
        c.proofing.applySuggestion(c.proofing.issues.single, 'Fehler'),
        isTrue,
      );
      expect(p.text, 'FelerFehler');
      expect(doc.revisions.map((r) => r.kind), [
        WmlRevisionKind.delete,
        WmlRevisionKind.insert,
      ]);
      expect(doc.revisions.map((r) => (r.start, r.end)), [(0, 5), (5, 11)]);
      WordRevisions.validate(doc);
      await c.proofing.checkDocument();
      expect(c.proofing.issues, isEmpty);
      c.undo();
      expect(p.text, 'Feler');
      expect(doc.revisions, isEmpty);
      c.redo();
      WordRevisions.validate(doc);
      expect(p.text, 'FelerFehler');
    },
  );

  test(
    'existing tracked changes are not overwritten by a proofreading correction',
    () async {
      final p = _paragraph('Feler');
      final doc = _document([p]);
      WordRevisions.record(
        doc,
        kind: WmlRevisionKind.insert,
        paragraphIndex: 0,
        paragraph: p,
        start: 0,
        end: 5,
        text: 'Feler',
      );
      final c = _controller(doc);
      await c.proofing.checkDocument();
      expect(
        c.proofing.applySuggestion(c.proofing.issues.single, 'Fehler'),
        isFalse,
      );
      WordRevisions.validate(doc);
      expect(p.text, 'Feler');
    },
  );

  test(
    'document language and hyphenation toggle save fallback in one undo step',
    () {
      final doc = _document([_paragraph('Rechtschreibung')]);
      final c = _controller(doc);
      expect(c.proofingLanguage, 'de-DE');
      expect(doc.proofingLanguage, isNull);
      c.setAutomaticHyphenation(true);
      expect(doc.proofingLanguage, 'de-DE');
      expect(doc.autoHyphenation, isTrue);
      c.undo();
      expect(doc.proofingLanguage, isNull);
      expect(doc.autoHyphenation, isFalse);
      expect(c.canUndo, isFalse);
      c.redo();
      c.setProofingLanguage('de_ch');
      expect(doc.proofingLanguage, 'de-CH');
      c.undo();
      expect(doc.proofingLanguage, 'de-DE');
    },
  );

  test(
    'default German checker supports personal vocabulary persistence and owner isolation',
    () async {
      final vocabulary = OfficeProofingVocabulary(ownerId: 'alice');
      final c = WordEditorController(
        document: _document([_paragraph('Qudsbegrif')]),
        proofingVocabulary: vocabulary,
      );
      addTearDown(c.dispose);
      await c.proofing.checkDocument();
      final issue = c.proofing.issues
          .where((i) => i.finding.category == OfficeProofingCategory.spelling)
          .single;
      Map<String, Object?>? saved;
      c.proofing.onVocabularyChanged = (snapshot) => saved = snapshot;
      c.proofing.addWord(issue);
      await c.proofing.checkDocument();
      expect(c.proofing.issues, isEmpty);
      expect(saved!['ownerId'], 'alice');
      expect(
        OfficeProofingVocabulary.fromJson(saved!).contains('Qudsbegrif'),
        isTrue,
      );
      expect(
        () => c.proofing.restoreVocabulary(
          OfficeProofingVocabulary(ownerId: 'bob').toJson(),
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'disposing a running session prevents late publications and disposes providers',
    () async {
      final gate = Completer<void>();
      final provider = _Provider(gate: gate);
      final c = WordEditorController(
        document: _document([_paragraph('Feler')]),
        proofingService: OfficeProofingService(providers: [provider]),
      );
      final session = c.proofing;
      var notifications = 0;
      session.addListener(() => notifications++);
      final pending = session.checkDocument();
      await provider.started.future;
      c.dispose();
      final before = notifications;
      gate.complete();
      await pending;
      expect(notifications, before);
      expect(provider.disposed, isTrue);
    },
  );
}
