import 'package:quds_office_engine/src/proofing/german_spelling.dart';
import 'package:quds_office_engine/src/proofing/german_writing_rules.dart';
import 'package:quds_office_engine/src/proofing/office_proofing.dart';

/// Executable in VM and compiled JavaScript; exercises the actual shipped data.
/// dart compile js -O2 tool/proofing/german_js_smoke.dart -o /tmp/german-proofing.js
/// node -e 'globalThis.self=globalThis; require(process.argv[1]);' /tmp/german-proofing.js
Future<void> main() async {
  final GermanSpellingProvider spelling = GermanSpellingProvider();
  final OfficeProofingService service = OfficeProofingService(
    providers: <OfficeProofingProvider>[spelling, GermanWritingRulesProvider()],
  );
  OfficeProofingRequest input(String text, {String language = 'de-DE'}) =>
      OfficeProofingRequest(
        documentId: 'js-doc',
        blockId: 'p',
        revision: 1,
        text: text,
        language: language,
      );
  void verify(bool condition, String label) {
    if (!condition) throw StateError(label);
    print('PASS $label');
  }

  final OfficeProofingReport ordinary = await service.check(
    input('Das ist ein schöner Text. Grüße aus dem Haus.'),
  );
  verify(ordinary.isClean, 'real German dictionary + rules clean sentence');
  final OfficeProofingReport typo = await service.check(
    input('🙂 Das Huas ist schön.'),
  );
  verify(
    typo.complete &&
        typo.findings.length == 1 &&
        typo.findings.single.start == 7 &&
        typo.findings.single.replacements.contains('Haus'),
    'UTF16 emoji offset + useful suggestion',
  );
  final OfficeProofingReport composed = await service.check(
    input('Gru\u0308ße aus dem Haus.'),
  );
  verify(composed.isClean, 'decomposed umlaut source lookup');
  final OfficeProofingReport swiss = await service.check(
    input('Grüsse aus der Strasse.', language: 'de-CH'),
  );
  verify(swiss.isClean, 'Swiss modern variants');
  verify(
    (await service.check(input('STRASSE GRÜSSE'))).isClean,
    'cross-runtime German all-capitals sharp-s',
  );
  final OfficeProofingReport old = await service.check(input('daß Fluß muß'));
  verify(old.findings.length == 3, 'obsolete orthography excluded');
  final OfficeProofingReport hyphen = await service.check(
    input('Recht\u00adschreibung'),
  );
  verify(hyphen.isClean, 'source-preserving soft-hyphen lookup');
  final OfficeProofingReport grammar = await service.check(
    input('Ich bist hier.'),
  );
  verify(
    grammar.findings.any(
      (OfficeProofingFinding f) =>
          f.category == OfficeProofingCategory.grammar &&
          f.replacements.contains('bin'),
    ),
    'limited German grammar rule',
  );
  spelling.vocabulary.addWord('Qudsmarke');
  verify(
    (await service.check(input('Qudsmarke'))).isClean,
    'host-owned personal vocabulary',
  );
  await service.dispose();
  verify(
    !(await service.check(input('Hallo'))).isClean,
    'disposed checker is unavailable',
  );
  print('All 10 compiled-JavaScript proofing checks passed.');
}
