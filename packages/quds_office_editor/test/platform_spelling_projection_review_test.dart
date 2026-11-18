import 'dart:ui' show Locale;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/src/proofing/platform_spelling_provider.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

final class _ReviewService extends SpellCheckService {
  _ReviewService(this.respond);

  final List<SuggestionSpan> Function(String text) respond;
  final requests = <String>[];

  @override
  Future<List<SuggestionSpan>?> fetchSpellCheckSuggestions(
    Locale locale,
    String text,
  ) async {
    requests.add(text);
    return respond(text);
  }
}

OfficeProofingRequest _request(String text) => OfficeProofingRequest(
  documentId: 'projection-review',
  blockId: 'paragraph',
  revision: 1,
  text: text,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'native correction cannot split a source flag after projection',
    () async {
      const original = '🇦\u00ad🇧🇨';
      const projected = '🇦🇧🇨';
      final service = _ReviewService((text) {
        expect(text, projected);
        // Removing the control changes regional-indicator pairing: C is a whole
        // projected grapheme but only half of the original BC flag cluster.
        return [
          const SuggestionSpan(TextRange(start: 4, end: 6), ['Text']),
        ];
      });
      final provider = OfficePlatformSpellingProvider(
        supportedLanguages: ['de-DE'],
        service: service,
        isAvailable: () => true,
      );
      addTearDown(provider.dispose);
      final result = await provider.check(_request(original));
      expect(result.status, OfficeProofingStatus.failed);
      expect(result.findings, isEmpty);
      expect(service.requests, [projected]);
    },
  );

  test(
    'different soft-hyphen placements are still native no-op choices',
    () async {
      const original = 'Fe\u00adler';
      final service = _ReviewService(
        (text) => [
          SuggestionSpan(TextRange(start: 0, end: text.length), [
            'F\u00adeler',
            '\u00adFeler',
            'Feler\u00ad',
            'F\u00ade\u00adl\u00ade\u00adr',
            'Fehler',
          ]),
        ],
      );
      final provider = OfficePlatformSpellingProvider(
        supportedLanguages: ['de-DE'],
        service: service,
        isAvailable: () => true,
      );
      addTearDown(provider.dispose);
      final result = await provider.check(_request(original));
      expect(result.status, OfficeProofingStatus.success);
      expect(result.findings.single.originalText, original);
      expect(result.findings.single.replacements, ['Fehler']);
    },
  );

  test(
    'empty projection preserves unavailable and exact-locale outcomes',
    () async {
      for (final sample in [
        (
          available: false,
          languages: ['de-DE'],
          expected: OfficeProofingStatus.unavailable,
        ),
        (
          available: true,
          languages: ['en-US'],
          expected: OfficeProofingStatus.unsupported,
        ),
      ]) {
        final service = _ReviewService((_) => []);
        final provider = OfficePlatformSpellingProvider(
          supportedLanguages: sample.languages,
          service: service,
          isAvailable: () => sample.available,
        );
        addTearDown(provider.dispose);
        final request = _request('\u00ad\u00ad');
        final result = await provider.check(request);
        expect(result.status, sample.expected);
        expect(service.requests, isEmpty);
        expect(
          OfficeProofingReport(request: request, results: [result]).isClean,
          isFalse,
        );
      }
    },
  );

  test('empty projection does not revive a disposed native provider', () async {
    final service = _ReviewService((_) => []);
    final provider = OfficePlatformSpellingProvider(
      supportedLanguages: ['de-DE'],
      service: service,
      isAvailable: () => true,
    );
    await provider.dispose();
    final result = await provider.check(_request('\u00ad'));
    expect(result.status, OfficeProofingStatus.unavailable);
    expect(service.requests, isEmpty);
  });
}
