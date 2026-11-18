import 'package:quds_office_engine/src/proofing/german_writing_rules.dart';
import 'package:test/test.dart';

void main() {
  test('reviewed verb API uses the existing closed paradigms', () {
    expect(GermanAgreementFacts.reviewedParadigmCount, 57);
    final reading = GermanAgreementFacts.reviewedPresentReadings(
      'schläft',
    ).single;
    expect(reading.infinitive, 'schlafen');
    expect(reading.thirdSingular, 'schläft');
    expect(reading.thirdPlural, 'schlafen');
    expect(reading.thirdPersonSubjunctive, isFalse);
    expect(GermanAgreementFacts.reviewedPresentReadings('flattert'), isEmpty);
    expect(GermanAgreementFacts.reviewedPresentReadings('schliefe'), isEmpty);
    expect(
      GermanAgreementFacts.reviewedPresentReadings(
        'habe',
      ).single.thirdPersonSubjunctive,
      isTrue,
    );
    expect(
      () => GermanAgreementFacts.reviewedPresentReadings('schläft').clear(),
      throwsUnsupportedError,
    );
  });

  test('all compatible Leiter readings survive the model boundary', () async {
    final ambiguous = await GermanAgreementFacts.nominativePhrase(
      determiner: 'Die',
      noun: 'Leiter',
    );
    expect(ambiguous.ready, isTrue);
    expect(ambiguous.numbers, {false, true});
    expect(ambiguous.readings.length, greaterThanOrEqualTo(2));
    final singular = await GermanAgreementFacts.nominativePhrase(
      determiner: 'Der',
      noun: 'Leiter',
    );
    expect(singular.ready, isTrue);
    expect(singular.numbers, {false});
    expect(() => ambiguous.readings.clear(), throwsUnsupportedError);
    expect(
      () => ambiguous.readings.first.forms.clear(),
      throwsUnsupportedError,
    );
  });

  test('licensed noun facts reject unknown and unresolved readings', () async {
    final unknown = await GermanAgreementFacts.nominativePhrase(
      determiner: 'Die',
      noun: 'Qudsbrand',
    );
    expect(unknown.ready, isFalse);
    final unresolved = await GermanAgreementFacts.nominativePhrase(
      determiner: 'Die',
      noun: 'Angestellten',
    );
    expect(unresolved.ready, isFalse);
    expect(await GermanAgreementFacts.hasKnownNoun('Garten'), isTrue);
    expect(await GermanAgreementFacts.hasKnownNoun('Qudsbrand'), isFalse);
  });

  test(
    'reviewed adjective evidence must agree with every retained reading',
    () async {
      final plural = await GermanAgreementFacts.nominativePhrase(
        determiner: 'Die',
        noun: 'Kinder',
        adjectives: ['kleinen'],
      );
      expect(plural.ready, isTrue);
      expect(plural.numbers, {true});
      final wrong = await GermanAgreementFacts.nominativePhrase(
        determiner: 'Die',
        noun: 'Kinder',
        adjectives: ['kleine'],
      );
      expect(wrong.reason, 'adjective-conflict');
      final unknown = await GermanAgreementFacts.nominativePhrase(
        determiner: 'Die',
        noun: 'Kinder',
        adjectives: ['purpurroten'],
      );
      expect(unknown.reason, 'unreviewed-adjective');
      final wrongCase = await GermanAgreementFacts.nominativePhrase(
        determiner: 'Den',
        noun: 'Kindern',
      );
      expect(wrongCase.ready, isFalse);
    },
  );

  test('grammar edits cannot split a grapheme or surrogate pair', () {
    const source = '😀 schla\u0308ft';
    expect(GermanAgreementFacts.hasSourceBoundaries(source, 0, 2), isTrue);
    expect(GermanAgreementFacts.hasSourceBoundaries(source, 0, 1), isFalse);
    expect(GermanAgreementFacts.hasSourceBoundaries(source, 3, 8), isFalse);
    expect(
      GermanAgreementFacts.hasSourceBoundaries(source, 3, source.length),
      isTrue,
    );
  });
}
