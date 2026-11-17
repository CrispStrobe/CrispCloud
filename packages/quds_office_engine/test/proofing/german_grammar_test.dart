import 'package:quds_office_engine/src/proofing/german_writing_rules.dart';
import 'package:quds_office_engine/src/proofing/office_proofing.dart';
import 'package:test/test.dart';

OfficeProofingRequest request(
  String text, {
  String language = 'de-DE',
  int startOffset = 0,
  Set<String> ignored = const <String>{},
}) => OfficeProofingRequest(
  documentId: 'grammar-document',
  blockId: 'paragraph',
  revision: 4,
  text: text,
  language: language,
  startOffset: startOffset,
  ignoredRuleIds: ignored,
);

void main() {
  const List<(String, String, String, String)>
  corrections = <(String, String, String, String)>[
    ('Ich komme mit mich.', 'preposition-pronoun', 'mich', 'mir'),
    ('Das kommt von dich.', 'preposition-pronoun', 'dich', 'dir'),
    ('Sie wohnt bei ihn.', 'preposition-pronoun', 'ihn', 'ihm'),
    ('Er kommt zu wir.', 'preposition-pronoun', 'wir', 'uns'),
    ('Sie spricht nach ich.', 'preposition-pronoun', 'ich', 'mir'),
    ('Das ist für mir.', 'preposition-pronoun', 'mir', 'mich'),
    ('Das ist für ihm.', 'preposition-pronoun', 'ihm', 'ihn'),
    ('Wir kommen ohne dir.', 'preposition-pronoun', 'dir', 'dich'),
    ('Das spricht gegen er.', 'preposition-pronoun', 'er', 'ihn'),
    ('Es geht um wir.', 'preposition-pronoun', 'wir', 'uns'),
    ('Es geht durch ihnen.', 'preposition-pronoun', 'ihnen', 'sie'),
    ('Ich rede mit den Mann.', 'preposition-case', 'den', 'dem'),
    ('Sie kommt mit der Kind.', 'preposition-case', 'der', 'dem'),
    ('Er kommt mit einem Frau.', 'preposition-case', 'einem', 'einer'),
    ('Wir reden von diese Frage.', 'preposition-case', 'diese', 'dieser'),
    ('Das steht bei das Haus.', 'preposition-case', 'das', 'dem'),
    ('Ich komme aus die Stadt.', 'preposition-case', 'die', 'der'),
    ('Sie fragt nach einen Termin.', 'preposition-case', 'einen', 'einem'),
    ('Er kommt zu seine Schule.', 'preposition-case', 'seine', 'seiner'),
    ('Wir warten seit eine Woche.', 'preposition-case', 'eine', 'einer'),
    ('Sie kommt gegenüber das Büro.', 'preposition-case', 'das', 'dem'),
    ('Das ist für dem Kind.', 'preposition-case', 'dem', 'das'),
    ('Das ist für einem Frau.', 'preposition-case', 'einem', 'eine'),
    ('Sie geht durch der Stadt.', 'preposition-case', 'der', 'die'),
    ('Er kommt ohne dem Buch.', 'preposition-case', 'dem', 'das'),
    ('Das spricht gegen diesem Plan.', 'preposition-case', 'diesem', 'diesen'),
    ('Es geht um einer Frage.', 'preposition-case', 'einer', 'eine'),
    ('Das kommt von euer Kind.', 'preposition-case', 'euer', 'eurem'),
    ('Das ist für unserem Kind.', 'preposition-case', 'unserem', 'unser'),
    ('Er kommt mit den Kinder.', 'dative-plural', 'Kinder', 'Kindern'),
    ('Sie liest aus den Bücher.', 'dative-plural', 'Bücher', 'Büchern'),
    ('Das steht bei den Häuser.', 'dative-plural', 'Häuser', 'Häusern'),
    ('Wir reden von den Fehler.', 'dative-plural', 'Fehler', 'Fehlern'),
    ('Sie kommt zu den Termine.', 'dative-plural', 'Termine', 'Terminen'),
    ('Er wartet seit diesen Tage.', 'dative-plural', 'Tage', 'Tagen'),
    // These nouns deliberately abstained before the licensed morphology layer.
    ('Sie redet mit einem Student.', 'noun-case', 'Student', 'Studenten'),
    ('Er kommt mit den Bänder.', 'dative-plural', 'Bänder', 'Bändern'),
    ('Ein gute Buch liegt hier.', 'adjective-ending', 'gute', 'gutes'),
    ('Eine gutes Frau kommt.', 'adjective-ending', 'gutes', 'gute'),
    ('Das guten Kind kommt.', 'adjective-ending', 'guten', 'gute'),
    ('Der gutes Mann kommt.', 'adjective-ending', 'gutes', 'gute'),
    ('Die guter Frau kommt.', 'adjective-ending', 'guter', 'gute'),
    ('Die gute Kinder kommen.', 'adjective-ending', 'gute', 'guten'),
    ('Ich sehe einen gute Mann.', 'adjective-ending', 'gute', 'guten'),
    ('Ich komme mit einem gutem Buch.', 'adjective-ending', 'gutem', 'guten'),
    ('Sie kommt mit einer gute Frau.', 'adjective-ending', 'gute', 'guten'),
    ('Er kommt aus dem schöne Haus.', 'adjective-ending', 'schöne', 'schönen'),
    ('Das ist für das neuen Büro.', 'adjective-ending', 'neuen', 'neue'),
    ('Ich komme ohne einen guter Plan.', 'adjective-ending', 'guter', 'guten'),
    ('Unser gute Kind kommt.', 'adjective-ending', 'gute', 'gutes'),
    ('Euer gute Kind kommt.', 'adjective-ending', 'gute', 'gutes'),
    ('Diese guter Datei ist hier.', 'adjective-ending', 'guter', 'gute'),
    ('Ich denke, das du kommst.', 'das-dass', 'das', 'dass'),
    ('Wir glauben, das er hier ist.', 'das-dass', 'das', 'dass'),
    ('Er weiß, das wir Zeit haben.', 'das-dass', 'das', 'dass'),
    ('Sie hofft, das ich das Buch lese.', 'das-dass', 'das', 'dass'),
    ('Ich glaube dass du kommst.', 'subordinate-comma', '', ','),
    ('Wir wissen dass sie heute kommen.', 'subordinate-comma', '', ','),
    ('Er meint, sie ist größer wie ich.', 'comparison', 'wie', 'als'),
    ('Das ist besser wie vorher.', 'comparison', 'wie', 'als'),
    ('Sie ist jünger wie er.', 'comparison', 'wie', 'als'),
    ('Er ist so groß als ich.', 'comparison', 'als', 'wie'),
    ('Sie ist genauso gut als er.', 'comparison', 'als', 'wie'),
    (
      'Die Datei ist ebenso wichtig als der Bericht.',
      'comparison',
      'als',
      'wie',
    ),
    ('Die Datei ist wichtiger wie der Bericht.', 'comparison', 'wie', 'als'),
  ];

  group('first-party phrase and clause corrections', () {
    for (final (String, String, String, String) example in corrections) {
      test(example.$1, () async {
        final GermanWritingRulesProvider provider =
            GermanWritingRulesProvider();
        final OfficeProofingResult result = await provider.check(
          request(example.$1),
        );
        expect(result.status, OfficeProofingStatus.success);
        expect(result.findings, hasLength(1));
        final OfficeProofingFinding finding = result.findings.single;
        expect(finding.ruleId, 'de.grammar.${example.$2}');
        expect(finding.category, OfficeProofingCategory.grammar);
        expect(finding.originalText, example.$3);
        expect(finding.replacements, <String>[example.$4]);
        final String corrected = example.$1.replaceRange(
          finding.start,
          finding.end,
          finding.replacements.single,
        );
        expect(
          (await provider.check(request(corrected))).findings,
          isEmpty,
          reason: corrected,
        );
        await provider.dispose();
      });
    }
  });

  const List<String> clean = <String>[
    'Ich komme mit dir. Sie kommt mit ihm. Wir sprechen mit ihnen.',
    'Das ist für mich. Sie kommt ohne ihn. Wir sind gegen euch.',
    'Bei mir ist alles gut. Nach dir bin ich dran.',
    'Für ihr Kind ist das wichtig. Das ist für ihre Kinder.',
    'Sie spricht mit Ihr und Sie in einer Sprachübung.',
    'Das ist für das Ich. Wir sprechen vom Du.',
    'Seit ich hier bin, ist alles gut.',
    'Seit mich der Mann kennt, ist alles gut.',
    'Seit er die Frau kennt, ist alles gut.',
    'Ohne mir zu helfen geht er.',
    'Ohne ihm helfen zu können bleibt er.',
    'Sie kommt, ohne dem Kind zu helfen.',
    'Er kommt, ohne der Frau bekannt zu sein.',
    'Ohne ihm böse zu sein kommt sie.',
    'Ohne mir weh zu tun kommt sie.',
    'Ohne dem Kind weh zu tun kommt sie.',
    'Wir kommen, um ihm zu helfen.',
    'Sie kommt, um dem Kind zu helfen.',
    'Um ihm nahe zu sein kommt sie.',
    'Um mir einen Gefallen zu tun kommt sie.',
    'Er bittet um seiner Kinder willen.',
    'Sie bittet um ihrer kleinen Kinder willen.',
    'Das ist mit ein schönes Buch.',
    'Die Datei ist mit die wichtigste Datei.',
    'Er wollte mit den Mann begleiten.',
    'Sie wollte mit ihn begleiten.',
    'Wegen dem Kind kommt sie. Trotz dem Fehler bleibt sie.',
    'Wegen des Kindes kommt sie. Trotz des Fehlers bleibt sie.',
    'Außer ich kommt niemand. Alle außer mir kommen.',
    'Wir gehen in die Stadt. Wir sind in der Stadt.',
    'Wir gehen auf den Weg. Wir stehen auf dem Weg.',
    'Wir gehen an das Haus. Wir stehen an dem Haus.',
    'Er kommt bis nächsten Dienstag. Wir können bis zu zehn Leute aufnehmen.',
    'Er geht den Weg entlang. Entlang des Weges stehen Häuser.',
    'Das steht bei dem Mann. Sie kommt mit einem Mann.',
    'Das ist für das Kind. Er kommt ohne einen Mann.',
    'Das steht bei den Kindern, den Büchern und den Fehlern.',
    'Er kommt mit den Frauen. Sie kommt mit den Autos.',
    'Sie kommt mit den Büros. Wir reden von den Regeln.',
    'Das ist für den Ordner. Das ist für die Ordner.',
    'Er kommt mit einem Fehler. Er kommt mit den Fehlern.',
    'Von diesem Tage an bleibt sie.',
    'Nach dem Jahre 1990 kommt sie.',
    'Aus dem Texte liest sie.',
    'Mit dem Tage kommt sie.',
    'Das ist für dem Qudsbrand.',
    'Er kommt mit einem Mensch.', // Masculine/neuter lexical ambiguity.
    'Sie redet mit der Leiter.',
    'Ein gutes Buch liegt neben einem guten Buch.',
    'Eine gute Frau kommt mit einer guten Frau.',
    'Ein guter Mann kommt mit einem guten Mann.',
    'Das gute Kind kommt. Die guten Kinder kommen.',
    'Der gute Mann kommt. Die gute Frau kommt.',
    'Diese gute Datei kommt mit diesen guten Dateien.',
    'Er kommt mit einem neuen, guten Buch.',
    'Das ist ein besseres Buch. Wir lesen die besseren Bücher.',
    'Das ist ein größeres Haus. Wir kommen mit dem größeren Auto.',
    'Ein kleiner Mann kommt. Ein kleines Kind kommt.',
    'Das ist ein gut lesbares Buch.',
    'Die automatisch geänderte Datei ist hier.',
    'Der öffentlich geprüfte Bericht ist hier.',
    'Die endgültig geschlossene Tür ist hier.',
    'Eine leicht beschädigte Tür ist hier.',
    'Ein vollständig geänderter Text ist hier.',
    'Ein einfach schönes Haus ist hier.',
    'Ein leise geschlossenes Fenster hilft dem Kind.',
    'Mit dem leise geschlossenen Fenster ist es ruhig.',
    'Ein müde geprüfter Bericht liegt vor.',
    'Eine leiser geschlossene Tür hilft dem Kind.',
    'Ein besonders gutes Buch liegt hier.',
    'Die Kinder spielen schön. Der Mann ist freundlich.',
    'Ich denke, dass du kommst.',
    'Ich denke das. Du kommst.',
    'Ich sage das, was ich denke.',
    'Das Buch, das ich lese, ist gut.',
    'Ich sehe das Buch, das du liest.',
    'Ich hoffe, das reicht.',
    'Ich glaube das gerne.',
    'Ich denke, das ich.',
    'Ich denke, das ich Wort für Wort.',
    'Ich denke, das ich „komme“ sage.',
    'Er ist größer als ich. Sie ist genauso groß wie er.',
    'Er ist kleiner, wie ich gestern bemerkt habe.',
    'Die Lage war früher wie heute schwierig.',
    'Er war früher wie ein Bruder für mich.',
    'Sie sah später wie ihre Mutter aus.',
    'Ich komme später wie vereinbart.',
    'Er ist schneller wie auch zuverlässiger geworden.',
    'Sie ist schneller wie beispielsweise das Auto.',
    'Er arbeitet so schnell als möglich.',
    'Er ist so groß als ob er gewachsen wäre.',
    'Er ist so groß als wenn er gewachsen wäre.',
    'Er war so klein als er geboren wurde.',
    'Er war so klein als er kam.',
    'Die Datei ist ebenso wichtig wie der Bericht.',
    'Die Datei ist wichtiger als der Bericht.',
    'Der Bericht war so wichtig als er hier ankam.',
    'Der Bericht war so wichtig als ob er alles bewiesen hätte.',
    'Er ist so gut als Lehrer.',
    'Er ist so gut als Arzt.',
    'Sie ist so wichtig als Ärztin.',
    'Der Besser ist ein Name. Besser wie früher ist ein Titel.',
  ];
  group('valid and unresolved structures remain untouched', () {
    for (final String text in clean) {
      test(text, () async {
        final GermanWritingRulesProvider provider =
            GermanWritingRulesProvider();
        expect((await provider.check(request(text))).findings, isEmpty);
        await provider.dispose();
      });
    }
  });

  test(
    'every new rule has a stable independently ignorable identity',
    () async {
      final GermanWritingRulesProvider provider = GermanWritingRulesProvider();
      for (final String id in <String>{
        for (final (String, String, String, String) c in corrections) c.$2,
      }) {
        final String text = corrections
            .firstWhere(((String, String, String, String) c) => c.$2 == id)
            .$1;
        final String ruleId = 'de.grammar.$id';
        expect(GermanWritingRulesProvider.ruleIds, contains(ruleId));
        expect(
          (await provider.check(
            request(text, ignored: <String>{ruleId}),
          )).findings,
          isEmpty,
        );
        expect((await provider.check(request(text))).findings, hasLength(1));
      }
      await provider.dispose();
    },
  );

  test(
    'phrase corrections preserve Unicode source and regional aliases',
    () async {
      final GermanWritingRulesProvider provider = GermanWritingRulesProvider();
      for (final String language in <String>[
        'de',
        'de-DE',
        'de-AT',
        'de-CH',
        'de_CH',
      ]) {
        for (final String space in <String>[' ', '\t', '\u00a0', '\u202f']) {
          final String text =
              '🙂 Mit${space}einem${space}gu\u00adtem${space}Buch.';
          final OfficeProofingService service = OfficeProofingService(
            providers: <OfficeProofingProvider>[provider],
          );
          final OfficeProofingReport report = await service.check(
            request(text, language: language, startOffset: 37),
          );
          expect(report.complete, isTrue);
          expect(report.findings, hasLength(1));
          final OfficeProofingFinding finding = report.findings.single;
          expect(finding.ruleId, 'de.grammar.adjective-ending');
          expect(finding.originalText, 'gu\u00adtem');
          expect(finding.start, 37 + text.indexOf('gu\u00adtem'));
          expect(finding.end, finding.start + 'gu\u00adtem'.length);
          expect(finding.replacements, <String>['guten']);
        }
      }
      await provider.dispose();
    },
  );

  test(
    'subordinate correction and insertion retain soft hyphen ownership',
    () async {
      final GermanWritingRulesProvider provider = GermanWritingRulesProvider();
      const String text = '🙂 Ich glau\u00adbe\u00ad da\u00ads du kommst.';
      final OfficeProofingResult result = await provider.check(
        request(text, startOffset: 21),
      );
      expect(result.findings, hasLength(2));
      final OfficeProofingFinding comma = result.findings.singleWhere(
        (OfficeProofingFinding f) => f.ruleId == 'de.grammar.subordinate-comma',
      );
      expect(comma.start, 21 + text.indexOf(' da'));
      expect(comma.end, comma.start);
      expect(comma.originalText, '');
      final OfficeProofingFinding conjunction = result.findings.singleWhere(
        (OfficeProofingFinding f) => f.ruleId == 'de.grammar.das-dass',
      );
      expect(conjunction.originalText, 'da\u00ads');
      expect(conjunction.start, 21 + text.indexOf('da\u00ads'));
      expect(conjunction.replacements, <String>['dass']);
      await provider.dispose();
    },
  );

  test('protected context cannot govern or supply phrase corrections', () async {
    final GermanWritingRulesProvider provider = GermanWritingRulesProvider();
    for (final String text in <String>[
      '`mit mich`',
      '``mit den Mann``',
      '```de\nein gute Buch\n```',
      '`Ich denke, das du kommst.`',
      'https://example.invalid/mit mich',
      'www.example.invalid/ein gute Buch',
      'name@example.mit mich',
      'https://example.invalid/größer wie ich',
      'https://example.invalid/Ich denke, das du kommst.',
      'https://example.invalid/mit den Mann',
      'foo_mit mich',
      'mit mich_id',
      'foo-ein gute Buch',
      'ein gute Buch-name',
      'mit\n den Mann',
      'ein\n gute Buch',
      'ein gute\n Buch',
      'mit den Mann\u0301',
      'mit den Mann\u200d',
      'mit den Mann\ufe0f',
      'mit mi\u0301ch',
    ]) {
      expect(
        (await provider.check(request(text))).findings,
        isEmpty,
        reason: text,
      );
    }
    final OfficeProofingResult result = await provider.check(
      request(
        '`mit mich` https://example.invalid/ein gute Buch. Ich rede mit mich.',
      ),
    );
    expect(result.findings, hasLength(1));
    expect(result.findings.single.ruleId, 'de.grammar.preposition-pronoun');
    await provider.dispose();
  });
}
