import 'package:quds_office_engine/src/proofing/german_writing_rules.dart';
import 'package:quds_office_engine/src/proofing/office_proofing.dart';
import 'package:test/test.dart';

OfficeProofingRequest input(
  String text, {
  Set<String> ignored = const <String>{},
  String language = 'de-DE',
}) => OfficeProofingRequest(
  documentId: 'doc',
  blockId: 'p',
  revision: 1,
  text: text,
  language: language,
  ignoredRuleIds: ignored,
);

void main() {
  test(
    'ordinary German, valid repetitions and regional quotes stay clean',
    () async {
      final GermanWritingRulesProvider provider = GermanWritingRulesProvider();
      for (final String text in <String>[
        'Ist das das Haus?',
        'Sie sagte, dass sie sie kennt.',
        'Ich bin hier. Du bist dort. Wir sind froh.',
        '„Guten Tag“, sagte er.',
        '«Grüezi», sagte sie.',
        '»Hallo«, sagte er.',
        'Er sagt “hello”.',
        'Wir sehen d’Artagnan.',
        'Er liest Hans’ Buch.',
        'Es sind 1,25 Euro; z. B. für 3 Stück.',
        '  eingerückt\n  weiterhin eingerückt',
      ]) {
        expect(
          (await provider.check(input(text))).findings,
          isEmpty,
          reason: text,
        );
      }
    },
  );
  test('spacing checks return precise reviewable replacements', () async {
    final OfficeProofingResult result = await GermanWritingRulesProvider()
        .check(input('Hallo  Welt ,weiter'));
    expect(
      result.findings.map((OfficeProofingFinding f) => f.ruleId),
      containsAll(<String>[
        'de.spacing.repeated',
        'de.spacing.before-punctuation',
        'de.spacing.after-punctuation',
      ]),
    );
    expect(result.findings.first.replacements, <String>[' ']);
    final OfficeProofingFinding insertion = result.findings.firstWhere(
      (OfficeProofingFinding f) => f.ruleId == 'de.spacing.after-punctuation',
    );
    expect(insertion.start, insertion.end);
    expect(insertion.originalText, isEmpty);
  });
  test('only conservative repeated conjunctions are flagged', () async {
    final OfficeProofingResult result = await GermanWritingRulesProvider()
        .check(input('🙂 und und weiter'));
    expect(result.findings.single.originalText, 'und und');
    expect(result.findings.single.start, 3);
    expect(result.findings.single.replacements, <String>['und']);
  });
  test(
    'selected pronoun-verb disagreement is grammar, not a broad parser claim',
    () async {
      final OfficeProofingResult result = await GermanWritingRulesProvider()
          .check(input('Ich bist hier. Wir ist dort.'));
      expect(
        result.findings.map((OfficeProofingFinding f) => f.category),
        everyElement(OfficeProofingCategory.grammar),
      );
      expect(
        result.findings.map((OfficeProofingFinding f) => f.replacements.single),
        <String>['bin', 'sind'],
      );
    },
  );
  test(
    'lowercase ich and du receive missing sein agreement corrections',
    () async {
      final OfficeProofingResult result = await GermanWritingRulesProvider()
          .check(input('Heute ich ist hier, und du ist dort.'));
      expect(
        result.findings.map((OfficeProofingFinding f) => f.originalText),
        <String>['ist', 'ist'],
      );
      expect(
        result.findings.map((OfficeProofingFinding f) => f.replacements.single),
        <String>['bin', 'bist'],
      );
    },
  );
  test(
    'nominal Ich and Du remain outside the limited agreement rule',
    () async {
      final OfficeProofingResult
      result = await GermanWritingRulesProvider().check(
        input(
          'Das Ich ist wach. Das Du ist wichtig. Mein wahres Ich ist ruhig. '
          'Ich ist ein Personalpronomen.',
        ),
      );
      expect(result.findings, isEmpty);
    },
  );
  test(
    'comparison pronouns are not mistaken for the following subject',
    () async {
      final OfficeProofingResult result = await GermanWritingRulesProvider()
          .check(
            input(
              'So wie du ist er müde. Anders als ich sind sie wach. '
              'Genau wie wir ist sie hier. Anders als ihr bin ich dort.',
            ),
          );
      expect(result.findings, isEmpty);
    },
  );
  test('agreement suggestions preserve all-capital verb casing', () async {
    final OfficeProofingResult result = await GermanWritingRulesProvider()
        .check(input('ICH BIST HIER. WIR IST DORT. ich IST hier.'));
    expect(
      result.findings.map((OfficeProofingFinding f) => f.replacements.single),
      <String>['BIN', 'SIND', 'BIN'],
    );
  });
  test(
    'finite auxiliary and modal agreement preserves exact source offsets',
    () async {
      final GermanWritingRulesProvider provider = GermanWritingRulesProvider();
      const List<(String, String)> cases = <(String, String)>[
        ('ich hast', 'habe'),
        ('du hat', 'hast'),
        ('wir habe', 'haben'),
        ('ich wirst', 'werde'),
        ('du wird', 'wirst'),
        ('wir werdet', 'werden'),
        ('ich kannst', 'kann'),
        ('du kann', 'kannst'),
        ('wir könnt', 'können'),
        ('ich musst', 'muss'),
        ('du muss', 'musst'),
        ('wir müsst', 'müssen'),
        ('ich darfst', 'darf'),
        ('du darf', 'darfst'),
        ('wir dürft', 'dürfen'),
        ('ich sollst', 'soll'),
        ('du soll', 'sollst'),
        ('wir sollt', 'sollen'),
        ('ich willst', 'will'),
        ('du will', 'willst'),
        ('wir wollt', 'wollen'),
        ('ich magst', 'mag'),
        ('du mag', 'magst'),
        ('wir mögt', 'mögen'),
      ];
      for (final (String, String) entry in cases) {
        final String text = '🙂 ${entry.$1} hier.';
        final String original = entry.$1.split(' ').last;
        final OfficeProofingReport report =
            await OfficeProofingService(
              providers: <OfficeProofingProvider>[provider],
            ).check(
              OfficeProofingRequest(
                documentId: 'doc',
                blockId: 'p',
                revision: 1,
                text: text,
                startOffset: 20,
              ),
            );
        expect(report.complete, isTrue, reason: text);
        expect(report.findings, hasLength(1), reason: text);
        final OfficeProofingFinding finding = report.findings.single;
        expect(finding.ruleId, 'de.grammar.pronoun-verb');
        expect(finding.category, OfficeProofingCategory.grammar);
        expect(finding.start, 20 + text.indexOf(original));
        expect(finding.end, finding.start + original.length);
        expect(finding.originalText, original);
        expect(finding.replacements, <String>[entry.$2]);
      }
      await provider.dispose();
    },
  );
  test(
    'valid German constructions remain outside finite agreement findings',
    () async {
      final GermanWritingRulesProvider provider = GermanWritingRulesProvider();
      for (final String text in <String>[
        'Ich habe Zeit. Du hast Zeit. Wir haben Zeit.',
        'Ich werde warten. Du wirst warten. Wir werden warten.',
        'Ich kann warten. Du kannst warten. Wir können warten.',
        'Ich muss warten. Du musst warten. Wir müssen warten.',
        'Ich darf warten. Du darfst warten. Wir dürfen warten.',
        'Ich soll warten. Du sollst warten. Wir sollen warten.',
        'Ich will warten. Du willst warten. Wir wollen warten.',
        'Ich mag Bücher. Du magst Bücher. Wir mögen Bücher.',
        'Ich sei bereit. Du seiest bereit. Wir seien bereit.',
        'Ich hätte Zeit. Du hättest Zeit. Wir hätten Zeit.',
        'Ich könnte kommen. Du könntest kommen. Wir könnten kommen.',
        'Ich möchte bleiben. Du möchtest bleiben. Wir möchten bleiben.',
        'Sei ruhig! Seid ruhig! Hab Geduld! Werde gesund!',
        'Du, hab Geduld! Ihr, seid ruhig!',
        'Du und ich sind hier. Peter und ich haben Zeit.',
        'Mein Bruder, den du kennst, und ich haben Zeit.',
        'Meine Schwester, die du kennst, sowie ich können helfen.',
        'Weder du noch ich haben Zeit. Du sowie ich können kommen.',
        'Nicht nur du, sondern auch ich haben Zeit.',
        'Wie du haben wir Zeit. Anders als ich hast du Zeit.',
        'Das Ich hat Grenzen. Mein wahres Ich hat Zeit.',
        'Das Wir ist stark. Unser gemeinsames Wir hat Bestand.',
        'Ich ist ein Personalpronomen. Du ist ein Personalpronomen.',
        '„ich“ und „du“ sind Personalpronomen.',
        'Ihr ist kalt. Ihr ist es gelungen.',
        'Ihr bin ich dankbar. Ihr bist du wichtig.',
        'Ihr sind die Bücher wichtig. Ihr sind Menschen wichtig.',
        'Ihr sind heute alle dankbar. Mit ihr sind wir zufrieden.',
        'Von ihr haben wir gehört. Bei nur ihr bin ich ruhig.',
        'Sie haben wir gesehen. Es haben wir erwähnt.',
        'foo_ich haben value_du hat object-wir ist',
        'ich haben2 du hat_teil wir ist-was',
        'ich\nhaben. du\nhat.',
        'ich haſt hier.',
      ]) {
        final OfficeProofingResult result = await provider.check(input(text));
        expect(result.findings, isEmpty, reason: text);
      }
      await provider.dispose();
    },
  );
  test(
    'finite agreement handles horizontal spaces, regions and capitals',
    () async {
      final GermanWritingRulesProvider provider = GermanWritingRulesProvider();
      for (final String language in <String>['de-DE', 'de-AT', 'de-CH']) {
        for (final String space in <String>[' ', '\t', '\u00a0', '\u202f']) {
          final OfficeProofingResult result = await provider.check(
            input(
              'ICH${space}HAST Zeit. WIR${space}KANN warten.',
              language: language,
            ),
          );
          expect(
            result.findings.map(
              (OfficeProofingFinding finding) => finding.replacements.single,
            ),
            <String>['HABE', 'KÖNNEN'],
            reason: '$language / $space',
          );
        }
      }
      await provider.dispose();
    },
  );
  test('finite agreement preserves exclusions and narrow ihr checks', () async {
    final GermanWritingRulesProvider provider = GermanWritingRulesProvider();
    const String text =
        '🙂 `ich hast` ``du hat`` HTTPS://example.invalid/wir kann. '
        'ich hast\u200d. ich hast. ihr bist hier.';
    final OfficeProofingResult result = await provider.check(input(text));
    expect(
      result.findings.map(
        (OfficeProofingFinding finding) => finding.replacements.single,
      ),
      <String>['habe', 'seid'],
    );
    expect(result.findings.first.start, text.lastIndexOf('hast'));
    final OfficeProofingResult ignored = await provider.check(
      input(text, ignored: <String>{'de.grammar.pronoun-verb'}),
    );
    expect(ignored.findings, isEmpty);
    await provider.dispose();
  });
  test(
    'word-internal apostrophes do not close enclosing single quotes',
    () async {
      final OfficeProofingService service = OfficeProofingService(
        providers: <OfficeProofingProvider>[GermanWritingRulesProvider()],
      );
      for (final String text in <String>[
        'Er sagt ‘O’Connor’.',
        'Er fragt ‘Wie geht’s?’.',
        '„Er nennt ihn ‘d’Artagnan’.“',
        'Er sagt ‘Cafe\u0301’s’.',
        'Er sagt ‘𝒪’Connor’.',
        'Er sagt ‘Hallo’\u0308.',
        'Cafe\u0301’ und 𝒪’',
      ]) {
        final OfficeProofingReport report = await service.check(input(text));
        expect(report.results.single.status, OfficeProofingStatus.success);
        expect(report.isClean, isTrue, reason: text);
      }
      final OfficeProofingReport unclosed = await service.check(
        input('🙂 ‘O’Connor'),
      );
      expect(unclosed.complete, isTrue);
      expect(unclosed.findings.single.ruleId, 'de.quote.balance');
      expect(unclosed.findings.single.originalText, '‘');
      expect(unclosed.findings.single.start, 3);
      await service.dispose();
    },
  );
  test('decorated punctuation preserves ordinary paragraph findings', () async {
    final OfficeProofingService service = OfficeProofingService(
      providers: <OfficeProofingProvider>[GermanWritingRulesProvider()],
    );
    for (final String text in <String>[
      '🙂 (\u0308 „\u0308 Hallo  Welt [',
      '🙂 (\u0308) „\u0308Hallo“ Hallo  Welt [',
    ]) {
      final OfficeProofingReport report = await service.check(
        OfficeProofingRequest(
          documentId: 'doc',
          blockId: 'p',
          revision: 1,
          text: text,
          startOffset: 20,
        ),
      );
      expect(report.results.single.status, OfficeProofingStatus.success);
      expect(report.complete, isTrue);
      expect(
        report.findings.map((OfficeProofingFinding f) => f.originalText),
        <String>['  ', '['],
      );
      expect(report.findings.first.start, 20 + text.indexOf('  '));
      expect(report.findings.last.start, 20 + text.lastIndexOf('['));
      expect(report.findings.first.replacements, <String>[' ']);
      expect(report.findings.last.replacements, isEmpty);
    }
    await service.dispose();
  });
  test(
    'unsafe grammar and spacing matches leave ordinary corrections available',
    () async {
      final OfficeProofingService service = OfficeProofingService(
        providers: <OfficeProofingProvider>[GermanWritingRulesProvider()],
      );
      const String grammarText = 'ich bist\u200d. Ich bist hier.';
      final OfficeProofingReport grammar = await service.check(
        input(grammarText),
      );
      expect(grammar.complete, isTrue);
      expect(grammar.findings.single.originalText, 'bist');
      expect(grammar.findings.single.start, grammarText.lastIndexOf('bist'));
      expect(grammar.findings.single.replacements, <String>['bin']);
      const String spacingText = 'Hallo  \u0308Welt,weiter';
      final OfficeProofingReport spacing = await service.check(
        input(spacingText),
      );
      expect(spacing.complete, isTrue);
      expect(spacing.findings.single.ruleId, 'de.spacing.after-punctuation');
      expect(spacing.findings.single.start, spacingText.indexOf(',') + 1);
      expect(spacing.findings.single.start, spacing.findings.single.end);
      expect(spacing.findings.single.replacements, <String>[' ']);
      await service.dispose();
    },
  );
  test(
    'terminology substring rules do not replace partial graphemes',
    () async {
      final OfficeProofingService service = OfficeProofingService(
        providers: <OfficeProofingProvider>[
          OfficeTerminologyProvider(
            rules: <OfficeTerminologyRule>[
              OfficeTerminologyRule(
                id: 'coffee',
                term: 'Cafe',
                message: 'Use the preferred term.',
                replacements: <String>['Kaffee'],
                wholeWord: false,
              ),
            ],
          ),
        ],
      );
      const String text = '🙂 Cafe\u0301 Cafe\u200d Cafe';
      final OfficeProofingReport report = await service.check(
        OfficeProofingRequest(
          documentId: 'doc',
          blockId: 'p',
          revision: 1,
          text: text,
          startOffset: 20,
        ),
      );
      expect(report.results.single.status, OfficeProofingStatus.success);
      expect(report.complete, isTrue);
      final OfficeProofingFinding finding = report.findings.single;
      expect(finding.originalText, 'Cafe');
      expect(finding.start, 20 + text.lastIndexOf('Cafe'));
      expect(finding.end, 20 + text.length);
      expect(finding.replacements, <String>['Kaffee']);
      await service.dispose();
    },
  );
  test(
    'unmatched delimiters and quotes remain advisory with no guessed correction',
    () async {
      final OfficeProofingResult result = await GermanWritingRulesProvider()
          .check(input('Das (offene [Zitat] lautet „Hallo.'));
      expect(
        result.findings.map((OfficeProofingFinding f) => f.ruleId),
        containsAll(<String>['de.delimiter.balance', 'de.quote.balance']),
      );
      expect(
        result.findings.map((OfficeProofingFinding f) => f.replacements),
        everyElement(isEmpty),
      );
    },
  );
  test('URLs, inline code and rule opt-outs remain untouched', () async {
    final OfficeProofingResult result = await GermanWritingRulesProvider()
        .check(
          input(
            'https://example.invalid/a,b `x ,y` Hallo  Welt',
            ignored: <String>{'de.spacing.repeated'},
          ),
        );
    expect(result.findings, isEmpty);
  });
  test(
    'matching multi-backtick spans protect grammar and punctuation',
    () async {
      final GermanWritingRulesProvider provider = GermanWritingRulesProvider();
      for (final String code in <String>[
        '`ich bist [`',
        '``ich bist ` [`x``',
        '```dart\nich bist [\n```',
      ]) {
        final String text = '🙂 $code Ich bist hier.';
        final OfficeProofingResult result = await provider.check(input(text));
        expect(result.findings, hasLength(1), reason: code);
        expect(result.findings.single.originalText, 'bist');
        expect(result.findings.single.start, text.lastIndexOf('bist'));
        expect(result.findings.single.replacements, <String>['bin']);
      }
      await provider.dispose();
    },
  );
  test(
    'protected tokens cannot supply a subject for following prose',
    () async {
      final GermanWritingRulesProvider provider = GermanWritingRulesProvider();
      for (final String prefix in <String>[
        'https://example.invalid/ich',
        'HTTPS://example.invalid/ich',
        'www.example.invalid/ich',
        'name@example.ich',
      ]) {
        final String text = '🙂 $prefix bist. Ich bist hier.';
        final OfficeProofingResult result = await provider.check(input(text));
        expect(result.status, OfficeProofingStatus.success);
        expect(result.findings, hasLength(1), reason: prefix);
        expect(result.findings.single.ruleId, 'de.grammar.pronoun-verb');
        expect(result.findings.single.start, text.lastIndexOf('bist'));
        expect(result.findings.single.replacements, <String>['bin']);
      }
      await provider.dispose();
    },
  );
  test(
    'URL protection preserves enclosing brackets and typographic quotes',
    () async {
      final GermanWritingRulesProvider provider = GermanWritingRulesProvider();
      for (final String text in <String>[
        '(https://example.invalid/path)',
        '[https://example.invalid/path]',
        '{https://example.invalid/path}',
        '(https://example.invalid/a(b))',
        '(https://example.invalid/a(b)).',
        'https://example.invalid/a(b)',
        '(http://[::1]/a(b)).',
        '„https://example.invalid/path“',
        '“https://example.invalid/path”',
        '‘https://example.invalid/path’',
        '«https://example.invalid/path»',
        '»https://example.invalid/path«',
        '(„HTTPS://example.invalid/a(b)“).',
        '`(https://example.invalid/unbalanced`',
      ]) {
        final OfficeProofingResult result = await provider.check(input(text));
        expect(result.status, OfficeProofingStatus.success);
        expect(result.findings, isEmpty, reason: text);
      }
      await provider.dispose();
    },
  );
  test(
    'unmatched punctuation after a URL still has exact source ranges',
    () async {
      final GermanWritingRulesProvider provider = GermanWritingRulesProvider();
      const String text = '🙂 (https://example.invalid/a(b)))';
      final OfficeProofingResult result = await provider.check(
        OfficeProofingRequest(
          documentId: 'doc',
          blockId: 'p',
          revision: 1,
          text: text,
          startOffset: 20,
        ),
      );
      expect(result.status, OfficeProofingStatus.success);
      expect(result.findings.single.ruleId, 'de.delimiter.balance');
      expect(result.findings.single.originalText, ')');
      expect(result.findings.single.start, 20 + text.length - 1);
      expect(result.findings.single.end, 20 + text.length);
      expect(result.findings.single.replacements, isEmpty);
      await provider.dispose();
    },
  );
  test('language and disposed availability are explicit', () async {
    final GermanWritingRulesProvider provider = GermanWritingRulesProvider();
    expect(
      (await provider.check(input('hello', language: 'en-US'))).status,
      OfficeProofingStatus.unsupported,
    );
    await provider.dispose();
    expect(
      (await provider.check(input('Hallo'))).status,
      OfficeProofingStatus.unavailable,
    );
  });
  test(
    'terminology uses literal terms, Unicode word boundaries and correct offsets',
    () async {
      final OfficeTerminologyProvider provider = OfficeTerminologyProvider(
        rules: <OfficeTerminologyRule>[
          OfficeTerminologyRule(
            id: 'brand',
            term: 'Quds+',
            message: 'Use the preferred product name.',
            replacements: <String>['Quds Office'],
            languages: <String>{'de-DE'},
          ),
        ],
      );
      final OfficeProofingResult result = await provider.check(
        input('🙂 Quds+ und XQuds+ und Quds+X'),
      );
      expect(result.findings, hasLength(1));
      expect(result.findings.single.start, 3);
      expect(result.findings.single.originalText, 'Quds+');
      expect(result.findings.single.replacements, <String>['Quds Office']);
      expect(
        (await provider.check(
          input('Quds+', ignored: <String>{'brand'}),
        )).findings,
        isEmpty,
      );
      expect(
        (await provider.check(input('Quds+', language: 'en-US'))).status,
        OfficeProofingStatus.unsupported,
      );
    },
  );
}
