import 'package:quds_office_engine/src/proofing/german_writing_rules.dart';
import 'package:quds_office_engine/src/proofing/office_proofing.dart';
import 'package:test/test.dart';

const rule = 'de.grammar.noun-verb';

OfficeProofingRequest request(
  String text, {
  String locale = 'de-DE',
  int offset = 0,
  Set<String> ignored = const {},
}) => OfficeProofingRequest(
  documentId: 'noun-agreement',
  blockId: 'paragraph',
  revision: 1,
  text: text,
  language: locale,
  startOffset: offset,
  ignoredRuleIds: ignored,
);

void main() {
  const corrections = <(String, String)>[
    ('Die Kinder spielt im Garten.', 'Die Kinder spielen im Garten.'),
    ('Das Kind spielen im Garten.', 'Das Kind spielt im Garten.'),
    ('Die Lehrer arbeitet heute.', 'Die Lehrer arbeiten heute.'),
    ('Der Lehrer arbeiten heute.', 'Der Lehrer arbeitet heute.'),
    ('Meine Freunde kommt morgen.', 'Meine Freunde kommen morgen.'),
    ('Das Buch liegen hier.', 'Das Buch liegt hier.'),
    ('Die Bücher liegt hier.', 'Die Bücher liegen hier.'),
    ('Diese Mädchen ist müde.', 'Diese Mädchen sind müde.'),
    ('Das Mädchen sind müde.', 'Das Mädchen ist müde.'),
    (
      'Die kleinen Kinder spielt im Garten.',
      'Die kleinen Kinder spielen im Garten.',
    ),
    ('Die Frau arbeiten heute.', 'Die Frau arbeitet heute.'),
    ('Der Hund laufen nach Hause.', 'Der Hund läuft nach Hause.'),
    ('Die Hunde läuft nach Hause.', 'Die Hunde laufen nach Hause.'),
    ('Die Gäste wartet draußen.', 'Die Gäste warten draußen.'),
    ('Meine Töchter wohnt hier.', 'Meine Töchter wohnen hier.'),
  ];
  for (final (source, expected) in corrections) {
    test('correct and recheck $source', () async {
      final provider = GermanWritingRulesProvider();
      addTearDown(provider.dispose);
      final result = await provider.check(request(source, offset: 43));
      expect(result.status, OfficeProofingStatus.success);
      final finding = result.findings.single;
      expect(finding.ruleId, rule);
      final start = finding.start - 43;
      final end = finding.end - 43;
      expect(source.substring(start, end), finding.originalText);
      expect(
        source.replaceRange(start, end, finding.replacements.single),
        expected,
      );
      expect((await provider.check(request(expected))).findings, isEmpty);
      expect(
        (await provider.check(request(source, ignored: {rule}))).findings,
        isEmpty,
      );
    });
  }
  const controls = <String>[
    'Die Kinder spielen im Garten.', 'Das Kind spielt im Garten.',
    'Die Leiter steht im Schuppen.', 'Die Leiter arbeiten im Büro.',
    'Die Mutter mit den Kindern kommt morgen.',
    'Die Kinder sieht meine Frau.', 'Die Hunde liebt meine Schwester.',
    'Das Buch lesen meine Freunde.', 'Die Kinder sieht er jeden Tag.',
    'Der Mann und die Frau arbeiten heute.',
    'Das Kind und der Hund spielen draußen.',
    'Die Kinder, die er kennt, spielen draußen.',
    'Die Frau, deren Kinder spielen, arbeitet heute.',
    'Die Eltern des Kindes haben Zeit.',
    'Der Lehrer der Kinder arbeitet heute.',
    'Die Kinder spielt heute Abend.', // Competing unparsed syntax: abstain.
    'Die Kinder spielt!', 'Die Kinder spielt?',
    'Die Kinder spielen gelernt.', 'Die Kinder habe er gesehen.',
    'Die Qudsbrand spielt hier.', 'Die Angestellten arbeitet hier.',
    'Die Kinder Spielt hier.', '„Die Kinder spielt“ ist ein Beispiel.',
    '`Die Kinder spielt im Garten.`', 'https://example.com/Die-Kinder-spielt',
    'Das Mädchen ist müde.', 'Die Mädchen sind müde.',
    'Die große Liebe sind meine Kinder.',
    'Mein größter Schatz sind meine Kinder.',
  ];
  for (final source in controls) {
    test('preserve or abstain $source', () async {
      final provider = GermanWritingRulesProvider();
      addTearDown(provider.dispose);
      final result = await provider.check(request(source));
      expect(result.status, OfficeProofingStatus.success);
      expect(result.findings.where((f) => f.ruleId == rule), isEmpty);
    });
  }
  test('locale aliases and source soft hyphens retain ownership', () async {
    final provider = GermanWritingRulesProvider();
    addTearDown(provider.dispose);
    for (final locale in ['de-DE', 'de-AT', 'de-CH']) {
      final source = locale == 'de-CH'
          ? 'Die Strassen ist sauber.'
          : 'Die Straßen ist sauber.';
      final result = await provider.check(request(source, locale: locale));
      final finding = result.findings.single;
      expect(finding.ruleId, rule);
      expect(finding.originalText, 'ist');
      expect(finding.replacements, ['sind']);
    }
    final result = await provider.check(
      request('Die Kin\u00adder spielt hier.'),
    );
    final finding = result.findings.single;
    expect(finding.originalText, 'spielt');
    expect(finding.start, 'Die Kin\u00adder '.length);
    expect(finding.replacements, ['spielen']);
  });
  test(
    'long rejected predicate stays bounded without partial findings',
    () async {
      final provider = GermanWritingRulesProvider();
      addTearDown(provider.dispose);
      final result = await provider.check(
        request('Die Kinder spielt ${List.filled(4096, 'heute').join(' ')}?'),
      );
      expect(result.status, OfficeProofingStatus.success);
      expect(
        result.findings.where((finding) => finding.ruleId == rule),
        isEmpty,
      );
    },
  );
}
