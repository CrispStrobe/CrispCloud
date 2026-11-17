import 'package:quds_office_engine/src/proofing/german_spelling.dart';
import 'package:quds_office_engine/src/proofing/office_proofing.dart';
import 'package:test/test.dart';

void main() {
  late OfficeProofingService service;
  setUp(() {
    service = OfficeProofingService(
      providers: <OfficeProofingProvider>[GermanSpellingProvider()],
    );
  });
  tearDown(() async => service.dispose());

  Future<OfficeProofingReport> check(
    String text, {
    String language = 'de-DE',
    int startOffset = 0,
  }) => service.check(
    OfficeProofingRequest(
      documentId: 'quoted-spelling',
      blockId: 'paragraph',
      revision: 1,
      text: text,
      language: language,
      startOffset: startOffset,
    ),
  );

  test('direct German quotation retains initial determiner', () async {
    final OfficeProofingReport report = await check('Er sagte: „Das stimmt.“');
    expect(report.complete, isTrue);
    expect(report.findings, isEmpty);
  });

  for (final (String, String, String) style in <(String, String, String)>[
    ('German low single', '‚', '‘'),
    ('German guillemets', '»', '«'),
    ('German single guillemets', '›', '‹'),
    ('Swiss guillemets', '«', '»'),
    ('Swiss single guillemets', '‹', '›'),
    ('curly double', '“', '”'),
    ('curly single', '‘', '’'),
    ('ASCII double', '"', '"'),
    ('ASCII single', "'", "'"),
  ]) {
    test('${style.$1} direct quotation keeps its first capital', () async {
      for (final String language in <String>['de-DE', 'de-CH']) {
        final OfficeProofingReport report = await check(
          'Er sagte: ${style.$2}Das stimmt.${style.$3}',
          language: language,
        );
        expect(report.isClean, isTrue, reason: language);
      }
    });
  }

  test('horizontal spacing around an opening quotation is allowed', () async {
    for (final String spacing in <String>['', ' ', '\t', '\u00a0', '\u202f']) {
      final OfficeProofingReport report = await check(
        'Er sagte:$spacing„${spacing}Das stimmt.“',
      );
      expect(report.isClean, isTrue, reason: spacing);
    }
  });

  test(
    'quote context preserves emoji offsets and soft hyphen tokens',
    () async {
      const String text = '🙂 Er sagte: „Da\u00ads stimmt. Huas“';
      final OfficeProofingReport report = await check(text, startOffset: 37);
      expect(report.complete, isTrue);
      final OfficeProofingFinding finding = report.findings.single;
      expect(finding.originalText, 'Huas');
      expect(finding.start, 37 + text.indexOf('Huas'));
      expect(finding.end, 37 + text.indexOf('Huas') + 4);
      expect(finding.replacements, contains('Haus'));
    },
  );

  test('only the first word receives the quotation allowance', () async {
    const String text = 'Er sagte: „Das Das stimmt.“';
    final OfficeProofingReport report = await check(text);
    final OfficeProofingFinding finding = report.findings.single;
    expect(finding.originalText, 'Das');
    expect(finding.start, text.lastIndexOf('Das'));
    expect(finding.replacements, contains('das'));
  });

  test('lowercase nouns still require their lexical capital', () async {
    for (final String text in <String>[
      'Er sagte: „haus“',
      'Er sagte: „Das haus ist schön.“',
    ]) {
      final OfficeProofingReport report = await check(text);
      final OfficeProofingFinding finding = report.findings.single;
      expect(finding.originalText, 'haus');
      expect(finding.replacements, contains('Haus'));
    }
    expect((await check('Er sagte: „Das Haus ist schön.“')).isClean, isTrue);
  });

  test(
    'real first-word errors remain flagged with capitalized suggestions',
    () async {
      final OfficeProofingReport report = await check(
        'Er sagte: „Schönn ist es.“',
      );
      final OfficeProofingFinding finding = report.findings.single;
      expect(finding.originalText, 'Schönn');
      expect(finding.replacements, contains('Schön'));
    },
  );

  test('suggestion caches distinguish ordinary and quoted contexts', () async {
    for (final bool quotedFirst in <bool>[false, true]) {
      final String text = quotedFirst
          ? 'Er sagt: „Schönn.“ und sagt Schönn.'
          : 'Er sagt Schönn und sagt: „Schönn.“';
      final OfficeProofingReport report = await check(text);
      expect(report.findings, hasLength(2));
      final OfficeProofingFinding quoted = report.findings[quotedFirst ? 0 : 1];
      final OfficeProofingFinding ordinary =
          report.findings[quotedFirst ? 1 : 0];
      expect(quoted.replacements, contains('Schön'));
      expect(ordinary.replacements, contains('schön'));
      expect(ordinary.replacements, isNot(contains('Schön')));
    }
  });

  test(
    'ordinary adverb capitals stay contextual within the same check',
    () async {
      const String text = 'Das ist Sehr schön und er sagt: „Sehr schön.“';
      final OfficeProofingReport report = await check(text);
      expect(report.findings.single.start, text.indexOf('Sehr'));
      expect(report.findings.single.originalText, 'Sehr');
      expect(report.findings.single.replacements, contains('sehr'));
    },
  );

  test(
    'existing beginning and sentence-terminal recognition is unchanged',
    () async {
      for (final String text in <String>[
        '„Das stimmt.“',
        '🙂 Das stimmt.',
        'Er sagte. „Das stimmt.“',
        'Er sagte! „Das stimmt.“',
        'Er sagte? „Das stimmt.“',
        'Er sagte:\n„Das stimmt.“',
      ]) {
        expect((await check(text)).isClean, isTrue, reason: text);
      }
    },
  );
}
