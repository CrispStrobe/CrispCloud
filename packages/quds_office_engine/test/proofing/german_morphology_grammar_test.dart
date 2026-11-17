import 'package:quds_office_engine/src/proofing/german_writing_rules.dart';
import 'package:quds_office_engine/src/proofing/office_proofing.dart';
import 'package:test/test.dart';

OfficeProofingRequest _request(
  String text, {
  String language = 'de-DE',
  int offset = 0,
  Set<String> ignored = const <String>{},
}) => OfficeProofingRequest(
  documentId: 'licensed-morphology',
  blockId: 'paragraph',
  revision: 1,
  text: text,
  language: language,
  startOffset: offset,
  ignoredRuleIds: ignored,
);

String _apply(String source, List<OfficeProofingFinding> findings, int offset) {
  final List<OfficeProofingFinding> ordered =
      List<OfficeProofingFinding>.of(findings)..sort(
        (OfficeProofingFinding a, OfficeProofingFinding b) =>
            b.start.compareTo(a.start),
      );
  int edge = source.length;
  String result = source;
  for (final OfficeProofingFinding finding in ordered) {
    final int start = finding.start - offset;
    final int end = finding.end - offset;
    expect(end, lessThanOrEqualTo(edge));
    expect(source.substring(start, end), finding.originalText);
    expect(finding.replacements, hasLength(1));
    result = result.replaceRange(start, end, finding.replacements.single);
    edge = start;
  }
  return result;
}

void main() {
  // Authored regression sentences cover different noun paradigms and actual
  // correction/recheck behavior, not the representation of generated tables.
  const List<(String, String)> corrections = <(String, String)>[
    ('Sie arbeitet mit dem Student.', 'Sie arbeitet mit dem Studenten.'),
    ('Das ist für den Kunde.', 'Das ist für den Kunden.'),
    ('Wir sprechen mit dem Junge.', 'Wir sprechen mit dem Jungen.'),
    ('Wir sprechen mit einem Kollege.', 'Wir sprechen mit einem Kollegen.'),
    ('Er kommt ohne diesen Mensch.', 'Er kommt ohne diesen Menschen.'),
    ('Sie spricht mit dem Assistent.', 'Sie spricht mit dem Assistenten.'),
    ('Wir sprechen mit dem Journalist.', 'Wir sprechen mit dem Journalisten.'),
    ('Das ist für den Polizist.', 'Das ist für den Polizisten.'),
    ('Sie kommt mit dem Herr.', 'Sie kommt mit dem Herrn.'),
    ('Wir sprechen mit dem Name.', 'Wir sprechen mit dem Namen.'),
    ('Sie arbeitet mit einem Gedanke.', 'Sie arbeitet mit einem Gedanken.'),
    ('Wir rechnen mit den Ärzte.', 'Wir rechnen mit den Ärzten.'),
    ('Wir rechnen mit den A\u0308rzte.', 'Wir rechnen mit den Ärzten.'),
    ('Sie kommt mit den Gäste.', 'Sie kommt mit den Gästen.'),
    ('Wir arbeiten mit den Anträge.', 'Wir arbeiten mit den Anträgen.'),
    ('Sie kommt mit ihren Brüder.', 'Sie kommt mit ihren Brüdern.'),
    ('Das liegt bei den Schlüssel.', 'Das liegt bei den Schlüsseln.'),
    ('Wir stehen bei die Universität.', 'Wir stehen bei der Universität.'),
    ('Das ist für dem Bildschirm.', 'Das ist für den Bildschirm.'),
    ('Sie steht bei einem Bibliothek.', 'Sie steht bei einer Bibliothek.'),
    ('Das ist für einer Behörde.', 'Das ist für eine Behörde.'),
    ('Ein helle Krankenhaus steht hier.', 'Ein helles Krankenhaus steht hier.'),
    ('Eine modernes Maschine steht hier.', 'Eine moderne Maschine steht hier.'),
    ('Unser neues Drucker funktioniert.', 'Unser neuer Drucker funktioniert.'),
    (
      'Das ist für das neugierigen Publikum.',
      'Das ist für das neugierige Publikum.',
    ),
    (
      'Das ist für unseren neuen Krankenhaus.',
      'Das ist für unser neues Krankenhaus.',
    ),
    (
      'Sie kommt mit einem freundlichem Kunden.',
      'Sie kommt mit einem freundlichen Kunden.',
    ),
    ('Die neue Studenten sind hier.', 'Die neuen Studenten sind hier.'),
  ];

  for (final (String source, String expected) in corrections) {
    test('correct and recheck: $source', () async {
      final GermanWritingRulesProvider provider = GermanWritingRulesProvider();
      final OfficeProofingResult result = await provider.check(
        _request(source),
      );
      expect(result.status, OfficeProofingStatus.success);
      expect(result.findings, isNotEmpty);
      expect(_apply(source, result.findings, 0), expected);
      final OfficeProofingResult recheck = await provider.check(
        _request(expected),
      );
      expect(recheck.status, OfficeProofingStatus.success);
      expect(recheck.findings, isEmpty);
      await provider.dispose();
    });
  }

  const List<String> controls = <String>[
    'Wir sprechen mit dem Studenten und den Studenten.',
    'Das ist für den Kunden und die Kunden.',
    'Der Student kommt mit dem neuen Kollegen.',
    'Wir sprechen mit dem Herrn.',
    'Wir arbeiten mit dem Band und der Band.',
    'Das ist für den Band und das Band.',
    'Sie steht bei dem Leiter und der Leiter.',
    'Wir fahren zu dem See und zu der See.',
    'Sie arbeitet mit dem Steuer und der Steuer.',
    'Das ist für den Kiefer und die Kiefer.',
    'Das ist für dem Leiter.', // Gender cannot be inferred safely here.
    'Sie kommt mit das Band.', // Several genders require different articles.
    'Er kommt mit den Daten und den Eltern.',
    'Sie kommt mit den Teams und den Autos.',
    'Mit dem Herzen ist alles gut.',
    'Das ist für den Nachbarn.',
    'Das ist für den Nachbar.',
    'Sie kommt mit dem Nachbarn.',
    'Sie kommt mit dem Nachbar.',
    'Sie kommt mit den A\u0308rzten.',
    'Sie kommt mit den Bru\u0308dern.',
    'Mit dem Worte beginnt der Satz.',
    'Das geschieht mit dem letzten Atemzuge.',
    'Sie spricht von dem fernen Sterne.',
    'Er steht bei dem hohen Tore.',
    'Aus dem Buche liest sie vor.',
    'Sie spricht mit einem neuen Angestellten.',
    'Ein neuer Angestellter kommt.',
    'Wir sprechen mit einem guten Bekannten.',
    'Sie spricht mit einer Deutschen.',
    'Das ist für die Armen.',
    'Wir sprechen mit der Jungen.',
    'Das ist für die Junge.',
    'Das ist für die Reichen.',
    'Sie kommt mit den Armen.',
    'Das ist für die Bekannten.',
    'Ein Deutscher kommt heute.',
    'Ein technisch versierter Experte kommt.',
    'Eine automatisch gespeicherte Kopie liegt hier.',
    'Ein leicht beschädigter Bildschirm steht hier.',
    'Sie kommt, ohne dem Studenten zu helfen.',
    'Er arbeitet, um dem Kunden einen Gefallen zu tun.',
    'Sie wollte mit den Studenten begleiten.',
    'Wir sprechen mit dem Qudsbrand.',
  ];

  for (final String source in controls) {
    test('valid or ambiguous: $source', () async {
      final GermanWritingRulesProvider provider = GermanWritingRulesProvider();
      final OfficeProofingResult result = await provider.check(
        _request(source),
      );
      expect(result.status, OfficeProofingStatus.success);
      expect(result.findings, isEmpty);
      await provider.dispose();
    });
  }

  test('new noun rule is independently ignorable', () async {
    final GermanWritingRulesProvider provider = GermanWritingRulesProvider();
    const String source = 'Sie spricht mit dem Student.';
    expect(
      GermanWritingRulesProvider.ruleIds,
      contains('de.grammar.noun-case'),
    );
    final OfficeProofingResult initial = await provider.check(_request(source));
    expect(initial.findings.single.ruleId, 'de.grammar.noun-case');
    final OfficeProofingResult ignored = await provider.check(
      _request(source, ignored: <String>{'de.grammar.noun-case'}),
    );
    expect(ignored.status, OfficeProofingStatus.success);
    expect(ignored.findings, isEmpty);
    await provider.dispose();
  });

  test(
    'Swiss aliases and authored soft hyphens retain source ownership',
    () async {
      final GermanWritingRulesProvider provider = GermanWritingRulesProvider();
      for (final String language in <String>[
        'de-CH',
        'de_CH',
        'de-Latn-CH-1996-u-co-phonebk',
      ]) {
        const String source = '👩🏽‍💻 Wir rechnen mit den Fü\u00adsse.';
        final OfficeProofingResult result = await provider.check(
          _request(source, language: language, offset: 37),
        );
        expect(result.status, OfficeProofingStatus.success);
        expect(result.findings, hasLength(1));
        expect(result.findings.single.originalText, 'Fü\u00adsse');
        expect(result.findings.single.replacements, <String>['Füssen']);
        expect(
          _apply(source, result.findings, 37),
          '👩🏽‍💻 Wir rechnen mit den Füssen.',
        );
      }
      await provider.dispose();
    },
  );

  test(
    'new coverage preserves code, URLs and whole grapheme boundaries',
    () async {
      final GermanWritingRulesProvider provider = GermanWritingRulesProvider();
      for (final String source in <String>[
        '`mit dem Student`',
        '``für den Kunde``',
        '```de\nmit den Gäste\n```',
        'https://example.invalid/mit/dem/Student',
        'name@Student.example',
        'mit dem Stu\u0301dent',
        'mit dem Student\u200d',
        'mit dem Student\ufe0f',
        'mit\n dem Student',
        'mit dem\n Student',
      ]) {
        final OfficeProofingResult result = await provider.check(
          _request(source),
        );
        expect(result.status, OfficeProofingStatus.success);
        expect(result.findings, isEmpty, reason: source);
      }
      await provider.dispose();
    },
  );
}
