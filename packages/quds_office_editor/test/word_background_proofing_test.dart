// Parity checks cold-start both dictionary implementations.
@Timeout(Duration(minutes: 2))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/src/proofing/background_proofing.dart';
import 'package:quds_office_editor/src/proofing/word_proofing.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

OfficeProofingRequest _request(String language, String text) =>
    OfficeProofingRequest(
      documentId: 'document',
      blockId: 'paragraph',
      revision: 7,
      text: text,
      language: language,
      startOffset: 11,
    );

OfficeProofingService _background(OfficeProofingVocabulary vocabulary) {
  final service = defaultWordProofingService(vocabulary);
  addTearDown(service.dispose);
  return service;
}

Object _signature(OfficeProofingReport report) => [
  for (final result in report.results)
    [
      result.providerId,
      result.status,
      result.message,
      for (final finding in result.findings)
        [
          finding.start,
          finding.end,
          finding.originalText,
          finding.ruleId,
          finding.replacements,
        ],
    ],
];

void main() {
  test(
    'background findings preserve provider results and UTF-16 offsets',
    () async {
      final background = _background(OfficeProofingVocabulary());
      final direct = OfficeProofingService(
        providers: [
          GermanWritingRulesProvider(),
          GermanSpellingProvider(),
          ArabicWritingRulesProvider(),
        ],
      );
      addTearDown(direct.dispose);
      for (final request in [
        _request('de-DE', '📖 Er hat das Buch gelest. Das ist ein Beispeil.'),
        _request('ar', 'هذا  نص ، تجريبي .'),
        _request('en-GB', 'This is a sample.'),
      ]) {
        final report = await background.check(request);
        expect(report.request, same(request));
        for (final result in report.results) {
          expect(result.request, same(request));
        }
        expect(_signature(report), _signature(await direct.check(request)));
        if (request.language != 'en-GB') {
          expect(report.complete, isTrue);
          expect(report.findings, isNotEmpty);
        }
      }
    },
  );

  test(
    'shared worker keeps personal vocabularies and revisions separate',
    () async {
      final firstVocabulary = OfficeProofingVocabulary()..addWord('Qudsmarke');
      final secondVocabulary = OfficeProofingVocabulary();
      final first = _background(firstVocabulary);
      final second = _background(secondVocabulary);
      final request = _request('de-DE', 'Die Qudsmarke.');
      Future<bool> flagged(OfficeProofingService service) async {
        final report = await service.check(request);
        expect(report.complete, isTrue);
        return report.findings.any(
          (finding) => finding.originalText == 'Qudsmarke',
        );
      }

      expect(await Future.wait([flagged(first), flagged(second)]), [
        false,
        true,
      ]);
      final spelling = first.providers.singleWhere(
        (provider) => provider.id == 'german-spelling',
      );
      final otherSpelling = second.providers.singleWhere(
        (provider) => provider.id == 'german-spelling',
      );
      expect((await spelling.check(request)).findings, isEmpty);
      // Enqueue a return to the current owner behind another document.
      final queued = await Future.wait([
        spelling.check(request),
        otherSpelling.check(request),
        spelling.check(request),
      ]);
      expect(queued.map((result) => result.status), [
        OfficeProofingStatus.success,
        OfficeProofingStatus.success,
        OfficeProofingStatus.success,
      ]);
      expect(queued.map((result) => result.findings.length), [0, 1, 0]);

      final stale = List.generate(8, (_) => spelling.check(request));
      final otherDocument = otherSpelling.check(request);
      firstVocabulary.removeWord('Qudsmarke');
      final fresh = spelling.check(request);
      for (final result in await Future.wait(stale)) {
        expect(result.request, same(request));
        expect(result.status, OfficeProofingStatus.failed);
        expect(result.findings, isEmpty);
        expect(result.message, contains('Personal vocabulary changed'));
      }
      final unaffected = await otherDocument;
      expect(unaffected.status, OfficeProofingStatus.success);
      expect(unaffected.findings.single.originalText, 'Qudsmarke');
      final afterEdit = await fresh;
      expect(afterEdit.status, OfficeProofingStatus.success);
      expect(afterEdit.findings.single.originalText, 'Qudsmarke');

      secondVocabulary.addWord('Qudsmarke');
      expect(await flagged(second), isFalse);
      await first.dispose();
      expect(await flagged(second), isFalse);
    },
  );
  test('an edit invalidates results from an in-progress native pass', () async {
    final paragraphs = [
      for (var i = 0; i < 8; i++)
        WmlParagraph(inlines: [WmlRun(text: 'Das ist ein Beispeil.')]),
    ];
    final document = WmlDocument(
      proofingLanguage: 'de-DE',
      sections: [WmlSection(blocks: paragraphs)],
    );
    var revision = 0;
    final session = WordProofingSession(
      document: () => document,
      revision: () => revision,
    );
    addTearDown(session.dispose);

    var edited = false;
    session.addListener(() {
      if (!edited && session.summary.checkedParagraphCount == 1) {
        edited = true;
        // Give the next batch a turn to enqueue before replacing its source.
        Future<void>.delayed(Duration.zero, () {
          paragraphs.last.inlines
            ..clear()
            ..add(WmlRun(text: 'Das ist ein Beispiel.'));
          revision++;
          session.refresh();
        });
      }
    });
    await session.checkNow();
    expect(edited, isTrue);
    expect(revision, 1);
    final fresh = await session.checkNow();
    expect(fresh.complete, isTrue);
    expect(fresh.checkedParagraphCount, 8);
    expect(
      fresh.issues.where((issue) => issue.finding.originalText == 'Beispeil'),
      hasLength(7),
    );
  });
}
