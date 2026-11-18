import 'dart:convert';

import 'package:quds_proofing_spacy/quds_proofing_spacy.dart';
import 'package:quds_proofing_spacy/src/source_text.dart';
import 'package:test/test.dart';

const identity = SpacyBackendIdentity(
  librarySha256:
      'ea89842ebf22c08508aff1cfbf18d78a107118af320523009616ff62b6e42977',
);

LinguisticAnalysisRequest request(String text, {int origin = 0}) =>
    LinguisticAnalysisRequest(
      text: text,
      documentId: 'doc',
      blockId: 'body:2',
      revision: 3,
      startOffset: origin,
    );

LinguisticToken token(
  String text, {
  int index = 0,
  int byteStart = 0,
  int? byteEnd,
  int scalarStart = 0,
  int? scalarEnd,
  int start = 0,
  int? end,
  int head = 0,
  String dependency = 'ROOT',
  bool sentenceStart = true,
  bool sentenceEnd = true,
  bool spaceAfter = false,
}) => LinguisticToken(
  index: index,
  text: text,
  byteStart: byteStart,
  byteEnd: byteEnd ?? byteStart + utf8.encode(text).length,
  scalarStart: scalarStart,
  scalarEnd: scalarEnd ?? scalarStart + text.runes.length,
  start: start,
  end: end ?? start + text.length,
  lemma: text,
  tag: 'NN',
  pos: 'NOUN',
  morphology: 'Number=Sing',
  dependency: dependency,
  head: head,
  sentenceStart: sentenceStart,
  sentenceEnd: sentenceEnd,
  spaceAfter: spaceAfter,
);

LinguisticAnalysisResult success(String text, List<LinguisticToken> tokens) =>
    LinguisticAnalysisResult.success(
      request: request(text),
      identity: identity,
      tokens: tokens,
    );

void main() {
  test(
    'source map keeps UTF8, scalars, UTF16, NUL and decomposed text distinct',
    () {
      final source = SpacySourceText('A😀é e\u0301\u0000');
      const expected = [
        (0, 0, 0),
        (1, 1, 1),
        (5, 3, 2),
        (7, 4, 3),
        (8, 5, 4),
        (9, 6, 5),
        (11, 7, 6),
        (12, 8, 7),
      ];
      for (final (bytes, units, scalars) in expected) {
        expect(source.utf16At(bytes), units);
        expect(source.scalarAt(bytes), scalars);
      }
      for (final offset in [2, 3, 4, 6, 10, -1, 13]) {
        expect(() => source.utf16At(offset), throwsFormatException);
      }
      expect(utf8.decode(source.bytes), 'A😀é e\u0301\u0000');
      expect(() => source.bytes[0] = 0, throwsUnsupportedError);
    },
  );

  test('unpaired UTF16 never silently becomes replacement UTF8', () {
    for (final bad in ['\ud800', '\udc00', 'x\ud800y', '\udfff\udbff']) {
      expect(() => SpacySourceText(bad), throwsFormatException);
    }
    expect(SpacySourceText('�').bytes, [0xef, 0xbf, 0xbd]);
  });

  test('byte admission checks multibyte input without truncation', () {
    expect(
      SpacySourceText('a' * spacyMaximumTextBytes).bytes.length,
      spacyMaximumTextBytes,
    );
    expect(
      () => SpacySourceText('a' * (spacyMaximumTextBytes + 1)),
      throwsFormatException,
    );
    expect(
      () => SpacySourceText('ä' * (spacyMaximumTextBytes ~/ 2 + 1)),
      throwsFormatException,
    );
  });

  test('empty is explicit and nonempty cannot masquerade as empty success', () {
    expect(success('', []).sentences, isEmpty);
    expect(() => success('x', []), throwsFormatException);
    expect(() => success('', [token('x')]), throwsFormatException);
  });

  test(
    'result owns immutable lists and preserves original nonzero offsets',
    () {
      final items = [token('😀')];
      final original = request('😀', origin: 29);
      final result = LinguisticAnalysisResult.success(
        request: original,
        identity: identity,
        tokens: items,
      );
      items.clear();
      expect(result.tokens.single.end, 2);
      expect(original.startOffset + result.tokens.single.start, 29);
      expect(original.startOffset + result.tokens.single.end, 31);
      expect(result.sentences.single.text, '😀');
      expect(() => result.tokens.clear(), throwsUnsupportedError);
      expect(() => result.sentences.clear(), throwsUnsupportedError);
    },
  );

  test('repeated strings must match exact coordinates and source coverage', () {
    final valid = [
      token(
        'ha',
        head: 1,
        dependency: 'mo',
        spaceAfter: true,
        sentenceEnd: false,
      ),
      token(
        'ha',
        index: 1,
        start: 3,
        byteStart: 3,
        scalarStart: 3,
        head: 1,
        sentenceStart: false,
      ),
    ];
    expect(success('ha ha', valid).tokens.length, 2);
    expect(
      () => success('ha ha', [
        valid.first,
        token('ha', index: 1, head: 1, sentenceStart: false),
      ]),
      throwsFormatException,
    );
    expect(() => success('ha  ha', valid), throwsFormatException);
    expect(() => success('ha\tha', valid), throwsFormatException);
    expect(() => success('ha ', [token('ha')]), throwsFormatException);
    expect(success('ha ', [token('ha', spaceAfter: true)]).tokens.length, 1);
  });

  test('coordinate drift and scalar splits fail rather than clamp', () {
    final bad = [
      token('😀', byteEnd: 3),
      token('😀', scalarEnd: 2),
      token('😀', end: 1),
      token('x', byteEnd: 4, scalarEnd: 1, end: 2),
      token('😀', byteStart: 1),
      token('😀', head: 1),
      token('😀', index: 1),
    ];
    for (final value in bad) {
      expect(() => success('😀', [value]), throwsFormatException);
    }
  });

  test('sentence flags, roots and cross-sentence dependencies are checked', () {
    expect(
      () => success('x', [token('x', sentenceStart: false)]),
      throwsFormatException,
    );
    expect(
      () => success('x', [token('x', sentenceEnd: false)]),
      throwsFormatException,
    );
    // spaCy assigns a self-headed `dep` node to a whitespace-only sentence.
    expect(
      success('  ', [token('  ', dependency: 'dep')]).tokens.single.head,
      0,
    );
    expect(
      () => success('a b', [
        token('a', spaceAfter: true, head: 1, dependency: 'sb'),
        token('b', index: 1, start: 2, byteStart: 2, scalarStart: 2, head: 1),
      ]),
      throwsFormatException,
    );
    expect(
      () => success('a b', [
        token('a', spaceAfter: true, sentenceEnd: false),
        token(
          'b',
          index: 1,
          start: 2,
          byteStart: 2,
          scalarStart: 2,
          head: 1,
          sentenceStart: false,
        ),
      ]),
      throwsFormatException,
    );
  });

  test('a cycle disconnected from the one root is rejected', () {
    expect(
      () => success('a b c', [
        token('a', spaceAfter: true, sentenceEnd: false),
        token(
          'b',
          index: 1,
          start: 2,
          byteStart: 2,
          scalarStart: 2,
          head: 2,
          dependency: 'sb',
          sentenceStart: false,
          sentenceEnd: false,
          spaceAfter: true,
        ),
        token(
          'c',
          index: 2,
          start: 4,
          byteStart: 4,
          scalarStart: 4,
          head: 1,
          dependency: 'mo',
          sentenceStart: false,
        ),
      ]),
      throwsFormatException,
    );
  });

  test('coalescing keys are unambiguous and snapshot identity is complete', () {
    final a = LinguisticAnalysisRequest(
      text: 'x',
      documentId: 'a:b',
      blockId: 'c',
      revision: 0,
    );
    final b = LinguisticAnalysisRequest(
      text: 'x',
      documentId: 'a',
      blockId: 'b:c',
      revision: 0,
    );
    expect(a.key, isNot(b.key));
    final edit = LinguisticAnalysisRequest(
      text: 'y',
      documentId: 'a:b',
      blockId: 'c',
      revision: 1,
      generation: 3,
    );
    expect(a.key, edit.key);
    expect(a.sameSnapshot(edit), isFalse);
    final original = request('x');
    expect(original.sameSnapshot(request('x')), isTrue);
    expect(original.sameSnapshot(request('x', origin: 1)), isFalse);
    expect(() => request('x', origin: -1), throwsArgumentError);
  });

  test('failed results cannot carry a successful partial document', () {
    final result = LinguisticAnalysisResult.failure(
      request: request('x'),
      status: LinguisticAnalysisStatus.cancelled,
      message: 'cancelled',
    );
    expect(result.identity, isNull);
    expect(result.tokens, isEmpty);
    expect(result.sentences, isEmpty);
    expect(result.isSuccess, isFalse);
    expect(
      () => LinguisticAnalysisResult.failure(
        request: request('x'),
        status: LinguisticAnalysisStatus.success,
        message: 'invalid',
      ),
      throwsArgumentError,
    );
  });

  test(
    'success is scoped to the exact declared locale and runtime profile',
    () {
      for (final locale in ['de-CH', 'de-AT', 'de', 'en-US', 'DE-de']) {
        expect(
          () => LinguisticAnalysisResult.success(
            request: LinguisticAnalysisRequest(
              text: '',
              documentId: 'doc',
              blockId: 'b',
              revision: 0,
              locale: locale,
            ),
            identity: identity,
            tokens: [],
          ),
          throwsFormatException,
        );
      }
      const invalid = SpacyBackendIdentity(librarySha256: 'unknown');
      expect(invalid.validate, throwsFormatException);
      const numericOnly = SpacyBackendIdentity(
        librarySha256:
            'ea89842ebf22c08508aff1cfbf18d78a107118af320523009616ff62b6e42977',
        capabilityMask: 3,
      );
      expect(numericOnly.validate, throwsFormatException);
      expect(identity.sameIdentity(identity), isTrue);
      expect(identity.sameIdentity(numericOnly), isFalse);
    },
  );
}
