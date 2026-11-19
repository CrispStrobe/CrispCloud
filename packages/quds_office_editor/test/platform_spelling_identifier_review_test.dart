import 'dart:ui' show Locale;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

final class _ReportedSpelling extends SpellCheckService {
  _ReportedSpelling(this.spans);

  final List<SuggestionSpan> Function(String) spans;

  @override
  Future<List<SuggestionSpan>?> fetchSpellCheckSuggestions(
    Locale locale,
    String text,
  ) async => spans(text);
}

Future<OfficeProofingResult> _check(
  String text,
  List<SuggestionSpan> Function(String) spans,
) async {
  final provider = OfficePlatformSpellingProvider(
    supportedLanguages: ['de-DE'],
    service: _ReportedSpelling(spans),
    isAvailable: () => true,
  );
  try {
    return await provider.check(
      OfficeProofingRequest(
        documentId: 'identifier-review',
        blockId: 'body',
        revision: 3,
        text: text,
        language: 'de-DE',
        startOffset: 17,
      ),
    );
  } finally {
    await provider.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('whole identifiers retain markers inside prepended graphemes', () async {
    for (final marker in ['4', '_', '𝟘', '\u203f']) {
      for (final prefix in ['\u0600', '\u{110bd}', '\u0600\u0600']) {
        final word = 'Fe$prefix$marker\u0301ler';
        final result = await _check(
          word,
          (text) => [
            SuggestionSpan(TextRange(start: 0, end: text.length), ['Fehler']),
          ],
        );
        expect(result.status, OfficeProofingStatus.success, reason: word);
        expect(result.findings, isEmpty, reason: word);
      }
    }
  });

  test('prepended markers protect adjacent native letter fragments', () async {
    for (final word in [
      '\u06004\u0301Feler',
      '\u0600_\u0301Feler',
      '\u{110bd}𝟘\u0301Feler',
      'Feler\u06004\u0301',
      'Feler\u{110bd}_\u0301',
    ]) {
      final result = await _check(word, (text) {
        final start = text.indexOf('Feler');
        return [
          SuggestionSpan(TextRange(start: start, end: start + 5), ['Fehler']),
        ];
      });
      expect(result.status, OfficeProofingStatus.success, reason: word);
      expect(result.findings, isEmpty, reason: word);
    }
  });

  test('prepended marker protection survives soft-hyphen projection', () async {
    for (final word in [
      'Fe\u00ad\u06004\u0301ler',
      '\u0600\u00ad4\u0301Feler',
      'Fe\u00adler\u{110bd}_\u0301',
    ]) {
      final result = await _check(
        word,
        (text) => [
          SuggestionSpan(TextRange(start: 0, end: text.length), ['Fehler']),
        ],
      );
      expect(result.status, OfficeProofingStatus.success, reason: word);
      expect(result.findings, isEmpty, reason: word);
    }
  });

  test('numeric symbols and connector punctuation stay intact', () async {
    for (final word in [
      'ⅧFeler',
      'Feler²',
      'Fe½ler',
      'Fe＿ler',
      'Fe‿ler',
      'Fe⁀ler',
      'Fe﹏ler',
    ]) {
      final result = await _check(
        word,
        (text) => [
          SuggestionSpan(TextRange(start: 0, end: text.length), ['Fehler']),
        ],
      );
      expect(result.status, OfficeProofingStatus.success, reason: word);
      expect(result.findings, isEmpty, reason: word);
    }
  });

  test('marked separators and numeral words retain prose findings', () async {
    for (final word in [
      'Ⅷ \u0600Feler',
      '_\u0301 Feler',
      '4\u0301-Feler',
      'Feler—4',
      '一错子二',
      'Feler\u00ad‑42',
    ]) {
      final expected = word.contains('错子')
          ? '错子'
          : word.contains('\u0600Feler')
          ? '\u0600Feler'
          : 'Feler';
      final result = await _check(word, (text) {
        final start = text.indexOf(expected);
        return [
          SuggestionSpan(
            TextRange(start: start, end: start + expected.length),
            ['correct'],
          ),
        ];
      });
      expect(result.status, OfficeProofingStatus.success, reason: word);
      expect(result.findings.single.originalText, expected, reason: word);
      expect(
        result.findings.single.start,
        17 + word.indexOf(expected),
        reason: word,
      );
    }
  });
}
