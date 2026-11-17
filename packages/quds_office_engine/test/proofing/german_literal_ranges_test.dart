import 'package:quds_office_engine/src/proofing/german_literal_ranges.dart';
import 'package:quds_office_engine/src/proofing/german_spelling.dart';
import 'package:quds_office_engine/src/proofing/german_writing_rules.dart';
import 'package:quds_office_engine/src/proofing/office_proofing.dart';
import 'package:test/test.dart';

void main() {
  for (final source in [
    'Er hat das Wort gelest genannt.',
    'Das Wort gelest wird hier erklärt.',
    'Er hat den Titel »gelest« erklärt.',
    '„Er hat das Buch gelest“ steht im Text.',
    'Er hat das Wort gelest.',
    'Das Wort Wort ist hier ein Beispiel.',
  ]) {
    test('literal mention stays literal: $source', () async {
      final service = OfficeProofingService(
        providers: [GermanWritingRulesProvider(), GermanSpellingProvider()],
      );
      addTearDown(service.dispose);
      final report = await service.check(
        OfficeProofingRequest(
          documentId: 'literal',
          blockId: 'p',
          revision: 1,
          text: source,
          language: 'de-DE',
        ),
      );
      expect(report.complete, isTrue);
      expect(report.findings, isEmpty);
    });
  }
  for (final source in [
    'Er hat das Buch gelest.',
    'Er sagte: „Er hat das Buch gelest.“',
  ]) {
    test('ordinary prose and quoted speech remain checked: $source', () async {
      final service = OfficeProofingService(
        providers: [GermanSpellingProvider()],
      );
      addTearDown(service.dispose);
      final report = await service.check(
        OfficeProofingRequest(
          documentId: 'literal',
          blockId: 'p',
          revision: 1,
          text: source,
          language: 'de-DE',
        ),
      );
      expect(report.findings.any((f) => f.originalText == 'gelest'), isTrue);
    });
  }
  for (final source in [
    '👩🏽‍💻 Das Wort Wort bleibt.',
    '„Das Wort abc und das Wort def und gelest“ steht im Text.',
  ]) {
    test(
      'UTF-16 interval queries match independently selected literal: $source',
      () {
        final ranges = GermanLiteralTextRanges(source);
        final start = source.startsWith('„') ? 1 : source.lastIndexOf('Wort');
        final end = source.startsWith('„') ? source.indexOf('“') : start + 4;
        for (var a = 0; a <= source.length; a++) {
          for (var b = a; b <= source.length; b++) {
            final expected = a == b
                ? a >= start && a <= end
                : a < end && b > start;
            expect(
              ranges.overlaps(a, b),
              expected,
              reason: '[$a,$b) expected [$start,$end)',
            );
          }
        }
      },
    );
  }
  test('ordinary or mismatched quotations are not whole literal examples', () {
    for (final source in ['„gelest“ sagte er.', '„gelest» steht im Text.']) {
      final start = source.indexOf('gelest');
      expect(
        GermanLiteralTextRanges(source).overlaps(start, start + 6),
        isFalse,
      );
    }
  });
  test('an ordinary verb following Wort remains eligible for spelling', () {
    const source = 'Das Wort fehlht hier.';
    final start = source.indexOf('fehlht');
    expect(GermanLiteralTextRanges(source).overlaps(start, start + 6), isFalse);
  });
}
