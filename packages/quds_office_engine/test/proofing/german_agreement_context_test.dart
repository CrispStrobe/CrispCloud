import 'package:quds_office_engine/src/proofing/german_writing_rules.dart';
import 'package:quds_office_engine/src/proofing/office_proofing.dart';
import 'package:test/test.dart';

OfficeProofingRequest input(String text, {int startOffset = 0}) =>
    OfficeProofingRequest(
      documentId: 'agreement',
      blockId: 'p',
      revision: 2,
      text: text,
      startOffset: startOffset,
    );

void main() {
  test(
    'Swiss conjugation and phrase corrections preserve ss orthography',
    () async {
      final GermanWritingRulesProvider provider = GermanWritingRulesProvider();
      for (final (String, String) example in const <(String, String)>[
        ('Du weiss das.', 'weisst'),
        ('Ich heisst Anna.', 'heisse'),
        ('Ich heißt Anna.', 'heisse'),
        ('Er weisst das.', 'weiss'),
        ('Weisst man das?', 'Weiss'),
        ('Ein grosse Buch liegt hier.', 'grosses'),
      ]) {
        final String text = '🙂 ${example.$1}';
        final OfficeProofingRequest request = OfficeProofingRequest(
          documentId: 'swiss',
          blockId: 'p',
          revision: 1,
          text: text,
          language: 'de-CH',
          startOffset: 18,
        );
        final OfficeProofingResult result = await provider.check(request);
        expect(result.findings, hasLength(1), reason: example.$1);
        final OfficeProofingFinding finding = result.findings.single;
        expect(finding.replacements, <String>[example.$2]);
        expect(finding.start, 18 + text.indexOf(finding.originalText));
        expect(finding.replacements.single, isNot(contains('ß')));
        final String corrected = text.replaceRange(
          finding.start - 18,
          finding.end - 18,
          finding.replacements.single,
        );
        expect(
          (await provider.check(
            OfficeProofingRequest(
              documentId: 'swiss',
              blockId: 'p',
              revision: 2,
              text: corrected,
              language: 'de-CH',
            ),
          )).findings,
          isEmpty,
          reason: corrected,
        );
      }
      for (final String text in <String>[
        'Ich heisse Anna. Du heisst Anna. Wir heissen so.',
        'Ich weiss das. Du weisst das. Er weiss das.',
        'Ein grosses Haus steht an der Strasse.',
        'Das grosse Haus liegt zwischen den Strassen.',
        'Das ist ein grösseres Haus.',
        'Wir reden von den Strassen.',
      ]) {
        expect(
          (await provider.check(
            OfficeProofingRequest(
              documentId: 'swiss',
              blockId: 'p',
              revision: 1,
              text: text,
              language: 'de-CH',
            ),
          )).findings,
          isEmpty,
          reason: text,
        );
      }
      await provider.dispose();
    },
  );

  const List<(String, String, String)> corrections = <(String, String, String)>[
    ('Du bleibt hier.', 'bleibt', 'bleibst'),
    ('Ich stehst hier.', 'stehst', 'stehe'),
    ('Wir sitzt hier.', 'sitzt', 'sitzen'),
    ('Du liegt hier.', 'liegt', 'liegst'),
    ('Ich heißt Anna.', 'heißt', 'heiße'),
    ('Du weiß das.', 'weiß', 'weißt'),
    ('Ich denkst nach.', 'denkst', 'denke'),
    ('Du glaubt das.', 'glaubt', 'glaubst'),
    ('Wir hoffe das.', 'hoffe', 'hoffen'),
    ('Du kennt das.', 'kennt', 'kennst'),
    ('Ich verstehst das.', 'verstehst', 'verstehe'),
    ('Du bringt das Buch.', 'bringt', 'bringst'),
    ('Wir kaufe das Buch.', 'kaufe', 'kaufen'),
    ('Du schreibt das.', 'schreibt', 'schreibst'),
    ('Ich hörst das.', 'hörst', 'höre'),
    ('Du hilft ihr.', 'hilft', 'hilfst'),
    ('Wir fragt nach.', 'fragt', 'fragen'),
    ('Du antwortet ihr.', 'antwortet', 'antwortest'),
    ('Ich wartest hier.', 'wartest', 'warte'),
    ('Du wohnt hier.', 'wohnt', 'wohnst'),
    ('Wir lebt hier.', 'lebt', 'leben'),
    ('Du spielt hier.', 'spielt', 'spielst'),
    ('Ich suchst das.', 'suchst', 'suche'),
    ('Du zeigt das.', 'zeigt', 'zeigst'),
    ('Wir stellt das hierhin.', 'stellt', 'stellen'),
    ('Du legt das hin.', 'legt', 'legst'),
    ('Du hält das.', 'hält', 'hältst'),
    ('Du trägt das.', 'trägt', 'trägst'),
    ('Du trifft ihn.', 'trifft', 'triffst'),
    ('Du schläft hier.', 'schläft', 'schläfst'),
    ('Wir vergisst das.', 'vergisst', 'vergessen'),
    ('Du trinkt das.', 'trinkt', 'trinkst'),
    ('Er bist hier.', 'bist', 'ist'),
    ('Er haben Zeit.', 'haben', 'hat'),
    ('Man kannst hier bleiben.', 'kannst', 'kann'),
    ('Man müssen gehen.', 'müssen', 'muss'),
    ('Er gehst weiter.', 'gehst', 'geht'),
    ('Er kommen heute.', 'kommen', 'kommt'),
    ('Man dürfen hier warten.', 'dürfen', 'darf'),
    ('Er weißt das.', 'weißt', 'weiß'),
    ('Man verstehen das.', 'verstehen', 'versteht'),
    ('Er schreibst das.', 'schreibst', 'schreibt'),
    ('Er tragt das.', 'tragt', 'trägt'),
    ('Bist ich hier richtig?', 'Bist', 'Bin'),
    ('Hat du Zeit?', 'Hat', 'Hast'),
    ('Kann wir kommen?', 'Kann', 'Können'),
    ('Müssen er gehen?', 'Müssen', 'Muss'),
    ('Weißt man das?', 'Weißt', 'Weiß'),
    ('Warum hat du Zeit?', 'hat', 'hast'),
    ('Heute bin wir hier.', 'bin', 'sind'),
    ('Dort kannst man warten.', 'kannst', 'kann'),
    ('Wo hilft du ihr?', 'hilft', 'hilfst'),
    ('Was liest wir heute?', 'liest', 'lesen'),
    ('Wann tragt er das?', 'tragt', 'trägt'),
    ('Wie weißt ich das?', 'weißt', 'weiß'),
    ('Soll du gehen?', 'Soll', 'Sollst'),
    ('Kann wir lesen?', 'Kann', 'Können'),
    ('Ich weiß, dass er gehst.', 'gehst', 'geht'),
    ('Wenn ich hilfst, komme ich.', 'hilfst', 'helfe'),
    ('Ich weiß, dass er gehen.', 'gehen', 'geht'),
  ];
  group('expanded finite forms and clear inverted subjects', () {
    for (final (String, String, String) example in corrections) {
      test(example.$1, () async {
        final GermanWritingRulesProvider provider =
            GermanWritingRulesProvider();
        final OfficeProofingResult result = await provider.check(
          input(example.$1),
        );
        expect(result.findings, hasLength(1));
        final OfficeProofingFinding finding = result.findings.single;
        expect(finding.ruleId, 'de.grammar.pronoun-verb');
        expect(finding.originalText, example.$2);
        expect(finding.replacements, <String>[example.$3]);
        final String corrected = example.$1.replaceRange(
          finding.start,
          finding.end,
          finding.replacements.single,
        );
        expect((await provider.check(input(corrected))).findings, isEmpty);
        await provider.dispose();
      });
    }
  });

  const List<String> preserved = <String>[
    'Er ist hier. Man hat Zeit. Er kommt später.',
    'Du weißt das. Ich weiß das. Wir wissen das.',
    'Du hilfst ihr. Ich helfe ihr. Wir helfen ihr.',
    'Du trägst das. Ich trage das. Wir tragen das.',
    'Er habe Zeit, sagte er.',
    'Er gehe nach Hause, sagte sie.',
    'Man nehme das Buch und lese es.',
    'Er komme heute, sagte sie.',
    'Er werde kommen, sagte sie.',
    'Er denke an uns, sagte sie.',
    'Er bringe das Buch, sagte sie.',
    'Er stehe dort und warte.',
    'Habe er Zeit, frage sie.',
    'Gehe er nach Hause, sagte sie.',
    'Man sei vorsichtig. Er sei vorsichtig.',
    'Habe du Geduld!',
    'Gehe du nach Hause!',
    'Lerne du zuerst!',
    'Warte du hier!',
    'Werde du glücklich!',
    'Sei du ruhig!',
    'Nimm du das Buch!',
    'Gib du das Buch!',
    'Bleib du hier!',
    'Gehen wir! Bleiben wir hier!',
    'Haben du und ich Zeit?',
    'Können er und ich kommen?',
    'Sind du, ich und Peter hier?',
    'Haben du oder ich gewonnen?',
    'Kommen du sowie ich heute?',
    'Ich sagte Du und meinte Ich.',
    'Wir haben du gesagt.',
    'Der Er ist ein Ausdruck. Das Man ist ein Begriff.',
    'Das Er haben wir gelesen. Das Man haben wir besprochen.',
    'Sein wahres Ich hat Grenzen. Ein gutes Du ist wichtig.',
    'Die Macht ich im Text benenne.',
    'Weil er Essen kocht, bleibt er.',
    'Weil er Lesen lernt, bleibt er.',
    'Weil er eine Frage hat, bleibt er.',
    'Weil du Frage und Antwort kennst, bleibst du.',
    'WEIL DU FRAGE UND ANTWORT KENNST, BLEIBST DU.',
    'WEIL DU GLAUBE HAST, BLEIBST DU.',
    'WEIL DU SUCHE UND FRAGE KENNST, BLEIBST DU.',
    'IHR MACHT Freude. Ihr macht Freude.',
    'Ihr schreiben wir. Ihr helfen wir. Ihr tragen wir das nach.',
    'Ihr hilft man. Ihr schreibt man.',
    'Wie er haben wir Zeit. Anders als man haben wir Zeit.',
    'Er und ich haben Zeit. Peter und er haben Zeit.',
    'Nicht nur sie, sondern auch er haben Zeit.',
    'Er hätte Zeit. Er könnte kommen. Man müsste gehen.',
    'Wie geht es dir? Was hat er gesagt? Warum haben wir Zeit?',
    'Kann ich gehen? Will er lesen? Muss man gehen?',
    'Muss er arbeiten? Kann ich helfen?',
    'Könnte ich gehen? Würde ich gehen? Möchte ich helfen?',
    'Sollte ich warten? Dürfte ich kommen? Wollte ich bleiben?',
    'Könnten wir gehen? Würden wir helfen? Möchte er arbeiten?',
    'Auf Man leben viele Menschen.',
    'Für Man haben wir eine Datei.',
    'Ich weiß, dass er gehen kann.',
    'Wenn ich helfen kann, komme ich.',
    'Du sagst, dass du kommen willst.',
    'Ich frage, ob er arbeiten wird.',
    'Wir kommen, weil ich arbeiten muss.',
    'Er sagt, dass wir helfen können.',
    'Ich bleibe, wenn ich lesen darf.',
    'Er weiß, dass er gehen wird.',
    'Sie sagt, dass ich kommen sollte.',
    'Sie sagt, dass du bleiben könntest.',
    'Sie sagt, dass er arbeiten möchte.',
    'Ich komme, weil ich helfen werde.',
    'Ich komme, weil ich arbeiten gehe.',
    'Sie sagt, dass er helfen würde.',
    'Sie sagt, dass ich gehen müsse.',
    'Sie sagt, dass er warten wolle.',
    'Sie sagt, dass er gehen dürfe.',
    'Sie sagt, dass ich bleiben solle.',
    'Er heißt Martin. Man heißt ihn willkommen.',
  ];
  group(
    'mood, coordination, nominal pronouns and objects remain untouched',
    () {
      for (final String text in preserved) {
        test(text, () async {
          final GermanWritingRulesProvider provider =
              GermanWritingRulesProvider();
          expect((await provider.check(input(text))).findings, isEmpty);
          await provider.dispose();
        });
      }
    },
  );

  test(
    'inverted findings retain original ranges through soft hyphens',
    () async {
      final GermanWritingRulesProvider provider = GermanWritingRulesProvider();
      const String text = '🙂 Warum ha\u00adt du Zeit?';
      final OfficeProofingService service = OfficeProofingService(
        providers: <OfficeProofingProvider>[provider],
      );
      final OfficeProofingReport report = await service.check(
        input(text, startOffset: 31),
      );
      expect(report.complete, isTrue);
      final OfficeProofingFinding finding = report.findings.single;
      expect(finding.originalText, 'ha\u00adt');
      expect(finding.replacements, <String>['hast']);
      expect(finding.start, 31 + text.indexOf('ha\u00adt'));
      expect(finding.end, finding.start + 'ha\u00adt'.length);
      await service.dispose();
    },
  );

  test(
    'inverted grammar cannot be inferred from protected or joined tokens',
    () async {
      final GermanWritingRulesProvider provider = GermanWritingRulesProvider();
      for (final String text in <String>[
        '`Hat du Zeit?`',
        'https://example.invalid/hat du Zeit?',
        'name@example.hat du Zeit?',
        'foo_hat du Zeit?',
        'hat du_bar Zeit?',
        'hat-du Zeit?',
        'hat\n du Zeit?',
        'hat\u200d du Zeit?',
        'hat\u0301 du Zeit?',
        'hat du\u0301 Zeit?',
      ]) {
        expect(
          (await provider.check(input(text))).findings,
          isEmpty,
          reason: text,
        );
      }
      await provider.dispose();
    },
  );
}
