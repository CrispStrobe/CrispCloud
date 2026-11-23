import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

final class _CaptureProvider extends OfficeProofingProvider {
  final List<OfficeProofingRequest> requests = [];

  @override
  String get id => 'capture-cache-test';

  @override
  bool supportsLanguage(String language) => true;

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async {
    requests.add(request);
    return OfficeProofingResult(
      request: request,
      providerId: id,
      status: OfficeProofingStatus.success,
      findings: [
        for (final match in RegExp('Feler').allMatches(request.text))
          OfficeProofingFinding.forRequest(
            request,
            providerId: id,
            ruleId: 'capture.spelling',
            start: match.start,
            end: match.end,
            message: 'Check spelling.',
            category: OfficeProofingCategory.spelling,
            replacements: const ['Fehler'],
          ),
      ],
    );
  }
}

final class _Harness {
  _Harness(this.document) {
    session = WordProofingSession(
      document: () => document,
      // These host edits deliberately bypass revision notifications. Capture
      // metadata must remain authoritative even when text and revision match.
      revision: () => 0,
      service: OfficeProofingService(providers: [provider]),
    );
    addTearDown(session.dispose);
  }

  final WmlDocument document;
  final provider = _CaptureProvider();
  late final WordProofingSession session;

  WordProofingIssue issueFor(WmlParagraph paragraph) => session.summary.issues
      .singleWhere((issue) => identical(issue.paragraph, paragraph));
}

WmlParagraph _paragraph(String text) =>
    WmlParagraph(inlines: [WmlRun(text: text)]);

WmlDocument _document(List<WmlParagraph> paragraphs) => WmlDocument(
  proofingLanguage: 'de-DE',
  sections: [
    WmlSection(blocks: <WmlBlock>[...paragraphs]),
  ],
);

WmlContentControlData _lock() => WmlContentControlData(
  xml:
      '<w:sdt xmlns:w="${OfficeNamespaces.w}"><w:sdtPr>'
      '<w:id w:val="42"/><w:lock w:val="contentLocked"/>'
      '</w:sdtPr><w:sdtContent/></w:sdt>',
  sourcePartUri: '/word/document.xml',
  relationships: [],
);

void main() {
  test(
    'settled recheck publishes once and reuses the validated report',
    () async {
      final paragraph = _paragraph('Feler');
      final h = _Harness(_document([paragraph]));
      final first = await h.session.checkNow();
      final checking = <bool>[];
      h.session.addListener(() => checking.add(h.session.checking));
      final second = await h.session.checkNow();

      expect(checking, [false]);
      expect(h.provider.requests, hasLength(1));
      expect(second.reports.single, same(first.reports.single));
      expect(second.issues.single, same(first.issues.single));
    },
  );

  test(
    'warm capture notices noProof and language changes without text edits',
    () async {
      final changed = _paragraph('Feler');
      final stable = _paragraph('Feler stable');
      final h = _Harness(_document([changed, stable]));
      await h.session.checkNow();
      final old = h.issueFor(changed);
      final retained = h.issueFor(stable);
      expect(h.provider.requests, hasLength(2));

      h.session.refresh();
      expect(h.issueFor(changed), same(old));
      expect(h.issueFor(stable), same(retained));

      final run = changed.inlines.single as WmlRun;
      run.properties.noProof = true;
      h.session.refresh();
      expect(h.session.summary.issues, [retained]);
      expect(h.session.isCurrent(old), isFalse);
      final excluded = await h.session.checkNow();
      expect(h.provider.requests, hasLength(2));
      expect(excluded.skippedContentCount, 1);
      expect(excluded.checkedParagraphCount, 1);
      expect(excluded.complete, isFalse);

      run.properties
        ..noProof = false
        ..proofingLanguage = 'en-US';
      h.session.refresh();
      expect(h.session.summary.issues, [retained]);
      final checked = await h.session.checkNow();
      expect(h.provider.requests, hasLength(3));
      expect(h.provider.requests.last.text, 'Feler');
      expect(h.provider.requests.last.language, 'en-US');
      expect(h.issueFor(changed).language, 'en-US');
      expect(h.issueFor(stable), same(retained));
      expect(h.session.isCurrent(retained), isTrue);
      expect(checked.complete, isTrue);
      expect(changed.text, 'Feler');
    },
  );

  test(
    'warm empty and generated paragraphs keep current language and coverage',
    () async {
      final empty = _paragraph('');
      final generated = _paragraph('Feler page');
      final stable = _paragraph('Feler stable');
      final h = _Harness(_document([empty, generated, stable]));
      await h.session.checkNow();
      final retained = h.issueFor(stable);
      expect(h.provider.requests, hasLength(3));

      empty.properties.proofingLanguage = 'en_US';
      generated.properties.pageNumberField = true;
      h.session.refresh();
      expect(h.session.summary.issues, [retained]);
      final pageNumber = await h.session.checkNow();
      expect(h.provider.requests, hasLength(4));
      expect(h.provider.requests.last.text, '');
      expect(h.provider.requests.last.language, 'en-US');
      expect(pageNumber.checkedParagraphCount, 2);
      expect(pageNumber.skippedContentCount, 1);
      expect(pageNumber.complete, isFalse);

      generated.properties
        ..pageNumberField = false
        ..fieldInstruction = ' PAGE ';
      h.session.refresh();
      final genericField = await h.session.checkNow();
      expect(h.provider.requests, hasLength(4));
      expect(genericField.skippedContentCount, 1);
      expect(genericField.issues, [retained]);

      generated.properties.fieldInstruction = null;
      h.session.refresh();
      final restored = await h.session.checkNow();
      expect(h.provider.requests, hasLength(5));
      expect(h.provider.requests.last.text, 'Feler page');
      expect(h.issueFor(stable), same(retained));
      expect(restored.checkedParagraphCount, 3);
      expect(restored.skippedContentCount, 0);
      expect(restored.complete, isTrue);
      expect(generated.text, 'Feler page');
    },
  );

  test(
    'reused field-opening snapshots still propagate field depth across sections',
    () async {
      final beginning = WmlParagraph(
        inlines: [
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
          WmlFieldBoundary(
            kind: WmlFieldBoundaryKind.instruction,
            text: ' REF bookmark ',
          ),
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
          WmlRun(text: 'Cached field heading'),
        ],
      );
      final middle = _paragraph('Feler inside');
      final ending = WmlParagraph(
        inlines: [
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
          WmlRun(text: 'Feler after'),
        ],
      );
      final stable = _paragraph('Feler stable');
      final h = _Harness(
        WmlDocument(
          proofingLanguage: 'de-DE',
          sections: [
            WmlSection(blocks: [beginning]),
            WmlSection(blocks: [middle, ending, stable]),
          ],
        ),
      );
      await h.session.checkNow();
      final afterField = h.issueFor(ending);
      final retained = h.issueFor(stable);
      expect(h.provider.requests.map((request) => request.text), [
        'Feler after',
        'Feler stable',
      ]);
      for (var index = 0; index < 2; index++) {
        h.session.refresh();
        final repeated = await h.session.checkNow();
        expect(repeated.issues, [afterField, retained]);
        expect(repeated.skippedContentCount, 2);
        expect(h.provider.requests, hasLength(2));
      }

      beginning.inlines.removeWhere((inline) => inline is WmlFieldBoundary);
      h.session.refresh();
      expect(h.session.summary.issues, [afterField, retained]);
      final authored = await h.session.checkNow();
      expect(h.provider.requests, hasLength(4));
      expect(h.provider.requests.skip(2).map((request) => request.text), [
        'Cached field heading',
        'Feler inside',
      ]);
      expect(authored.skippedContentCount, 0);
      final inside = h.issueFor(middle);
      expect(h.session.canCorrect(inside), isTrue);
      expect(h.issueFor(ending), same(afterField));
      expect(h.issueFor(stable), same(retained));

      beginning.inlines.insertAll(0, [
        WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
        WmlFieldBoundary(
          kind: WmlFieldBoundaryKind.instruction,
          text: ' REF bookmark ',
        ),
        WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
      ]);
      h.session.refresh();
      expect(h.session.isCurrent(inside), isFalse);
      expect(h.session.summary.issues, [afterField, retained]);
      final excluded = await h.session.checkNow();
      expect(h.provider.requests, hasLength(4));
      expect(excluded.checkedParagraphCount, 2);
      expect(excluded.skippedContentCount, 2);
      expect(excluded.complete, isFalse);
      expect(beginning.text, 'Cached field heading');
      expect(middle.text, 'Feler inside');
    },
  );

  test(
    'warm capture rechecks parent locks and revision guards on unchanged text',
    () async {
      final guarded = _paragraph('Feler');
      final stable = _paragraph('Feler stable');
      final h = _Harness(_document([guarded, stable]));
      await h.session.checkNow();
      final old = h.issueFor(guarded);
      final retained = h.issueFor(stable);
      expect(h.session.canCorrect(old), isTrue);

      h.document.sections.single.blocks[0] = WmlContentControlBlock(
        control: _lock(),
        blocks: [guarded],
      );
      h.session.refresh();
      expect(h.session.isCurrent(old), isFalse);
      expect(h.session.summary.issues, [retained]);
      await h.session.checkNow();
      final locked = h.issueFor(guarded);
      expect(h.session.canCorrect(locked), isFalse);
      expect(h.provider.requests, hasLength(3));
      expect(h.issueFor(stable), same(retained));

      h.document.sections.single.blocks[0] = guarded;
      WordRevisions.record(
        h.document,
        kind: WmlRevisionKind.insert,
        paragraphIndex: 0,
        paragraph: guarded,
        start: 0,
        end: 5,
        text: 'Feler',
        author: 'Mira',
      );
      h.session.refresh();
      expect(h.session.isCurrent(locked), isFalse);
      expect(h.session.summary.issues, [retained]);
      await h.session.checkNow();
      final pending = h.issueFor(guarded);
      expect(h.session.canCorrect(pending), isFalse);
      expect(h.provider.requests, hasLength(4));
      expect(h.issueFor(stable), same(retained));

      h.document.revisions.clear();
      h.session.refresh();
      expect(h.session.isCurrent(pending), isFalse);
      await h.session.checkNow();
      expect(h.session.canCorrect(h.issueFor(guarded)), isTrue);
      expect(h.provider.requests, hasLength(5));
      expect(h.issueFor(stable), same(retained));
      expect(guarded.text, 'Feler');
    },
  );
}
