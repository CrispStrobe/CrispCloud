import 'dart:async';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/src/proofing/platform_spelling_provider.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

final class _Service implements SpellCheckService {
  _Service(this.answer);
  final Future<List<SuggestionSpan>?> Function(Locale, String) answer;
  @override
  Future<List<SuggestionSpan>?> fetchSpellCheckSuggestions(
    Locale locale,
    String text,
  ) => answer(locale, text);
}

OfficeProofingRequest _request([
  String text = '😀 Huas',
  String language = 'de-DE',
]) => OfficeProofingRequest(
  documentId: 'd',
  blockId: 'b',
  revision: 1,
  text: text,
  language: language,
  startOffset: 7,
);

void main() {
  test('platform absence and undeclared language are explicit', () async {
    final absent = OfficePlatformSpellingProvider(
      supportedLanguages: ['de-DE'],
      isAvailable: () => false,
    );
    expect(
      (await absent.check(_request())).status,
      OfficeProofingStatus.unavailable,
    );
    final unknown = OfficePlatformSpellingProvider(
      supportedLanguages: ['de-DE'],
      isAvailable: () => true,
    );
    expect(
      (await unknown.check(_request('', 'fr-FR'))).status,
      OfficeProofingStatus.unsupported,
    );
  });

  test('null is failure, empty successful list is clean', () async {
    final failed = OfficePlatformSpellingProvider(
      supportedLanguages: ['de-DE'],
      isAvailable: () => true,
      service: _Service((_, _) async => null),
    );
    expect(
      (await failed.check(_request())).status,
      OfficeProofingStatus.failed,
    );
    final clean = OfficePlatformSpellingProvider(
      supportedLanguages: ['de-DE'],
      isAvailable: () => true,
      service: _Service((_, _) async => []),
    );
    final result = await clean.check(_request());
    expect(result.status, OfficeProofingStatus.success);
    expect(result.findings, isEmpty);
  });

  test('platform UTF16 offsets preserve emoji and segment origin', () async {
    final provider = OfficePlatformSpellingProvider(
      supportedLanguages: ['de-DE'],
      isAvailable: () => true,
      service: _Service((locale, text) async {
        expect(locale.toLanguageTag(), 'de-DE');
        return [
          const SuggestionSpan(TextRange(start: 3, end: 7), ['Haus']),
        ];
      }),
    );
    final finding = (await provider.check(_request())).findings.single;
    expect(finding.start, 10);
    expect(finding.end, 14);
    expect(finding.originalText, 'Huas');
    expect(finding.replacements, ['Haus']);
  });

  test(
    'requests are serialized and disposal invalidates pending result',
    () async {
      var active = 0;
      var calls = 0;
      final first = Completer<List<SuggestionSpan>?>();
      final provider = OfficePlatformSpellingProvider(
        supportedLanguages: ['de-DE'],
        isAvailable: () => true,
        service: _Service((_, _) async {
          expect(active++, 0);
          calls++;
          final value = await first.future;
          active--;
          return value;
        }),
      );
      final a = provider.check(_request());
      final b = provider.check(_request());
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      await provider.dispose();
      first.complete([]);
      expect((await a).status, OfficeProofingStatus.unavailable);
      expect((await b).status, OfficeProofingStatus.unavailable);
      expect(calls, 1);
    },
  );
}
