import 'dart:async';
import 'dart:ui' show Locale;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_editor/src/proofing/platform_spelling_provider.dart';

class _Service extends SpellCheckService {
  _Service(this.respond);
  final Future<List<SuggestionSpan>?> Function(Locale locale, String text)
  respond;
  final calls = <({Locale locale, String text})>[];
  @override
  Future<List<SuggestionSpan>?> fetchSpellCheckSuggestions(
    Locale locale,
    String text,
  ) {
    calls.add((locale: locale, text: text));
    return respond(locale, text);
  }
}

OfficeProofingRequest _request({
  String text = 'Fehler',
  String language = 'de-DE',
  int startOffset = 0,
  Set<String> ignored = const {},
}) => OfficeProofingRequest(
  documentId: 'platform-test',
  blockId: 'paragraph',
  revision: 4,
  text: text,
  language: language,
  startOffset: startOffset,
  ignoredRuleIds: ignored,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'unavailable and undeclared dictionaries never claim a clean check',
    () async {
      final service = _Service((_, _) async => []);
      final unavailable = OfficePlatformSpellingProvider(
        supportedLanguages: ['de-DE'],
        service: service,
        isAvailable: () => false,
      );
      final unsupported = OfficePlatformSpellingProvider(
        supportedLanguages: ['de-DE'],
        service: service,
        isAvailable: () => true,
      );
      addTearDown(unavailable.dispose);
      addTearDown(unsupported.dispose);
      final missing = await unavailable.check(_request());
      final locale = await unsupported.check(_request(language: 'fr-FR'));
      expect(missing.status, OfficeProofingStatus.unavailable);
      expect(locale.status, OfficeProofingStatus.unsupported);
      expect(service.calls, isEmpty);
      for (final result in [missing, locale]) {
        expect(
          OfficeProofingReport(
            request: result.request,
            results: [result],
          ).isClean,
          isFalse,
        );
      }
    },
  );

  test(
    'an empty successful response remains distinct from an incomplete response',
    () async {
      for (final response in [<SuggestionSpan>[], null]) {
        final provider = OfficePlatformSpellingProvider(
          supportedLanguages: ['de-DE'],
          service: _Service((_, _) async => response),
          isAvailable: () => true,
        );
        addTearDown(provider.dispose);
        final request = _request();
        final result = await provider.check(request);
        expect(
          result.status,
          response == null
              ? OfficeProofingStatus.failed
              : OfficeProofingStatus.success,
        );
        expect(
          OfficeProofingReport(request: request, results: [result]).isClean,
          response != null,
        );
      }
    },
  );

  test('platform exceptions and malformed ranges fail the request', () async {
    final responses = <Future<List<SuggestionSpan>?> Function(Locale, String)>[
      (_, _) async => throw PlatformException(code: 'spellcheck-unavailable'),
      (_, _) async => [
        const SuggestionSpan(TextRange(start: 0, end: 30), ['Text']),
      ],
      (_, _) async => [
        const SuggestionSpan(TextRange(start: 2, end: 2), ['Text']),
      ],
    ];
    for (final response in responses) {
      final provider = OfficePlatformSpellingProvider(
        supportedLanguages: ['de-DE'],
        service: _Service(response),
        isAvailable: () => true,
      );
      addTearDown(provider.dispose);
      final result = await provider.check(_request());
      expect(result.status, OfficeProofingStatus.failed);
      expect(result.findings, isEmpty);
    }
  });

  test(
    'UTF-16 offsets, locale and bounded suggestions survive adapter mapping',
    () async {
      final service = _Service(
        (_, _) async => [
          SuggestionSpan(
            const TextRange(start: 3, end: 8),
            List.generate(12, (i) => 'word$i'),
          ),
        ],
      );
      final provider = OfficePlatformSpellingProvider(
        supportedLanguages: ['de_ch'],
        service: service,
        isAvailable: () => true,
      );
      addTearDown(provider.dispose);
      final result = await provider.check(
        _request(text: '😀 Feler', language: 'de-CH', startOffset: 20),
      );
      expect(result.status, OfficeProofingStatus.success);
      expect(service.calls.single.locale.toLanguageTag(), 'de-CH');
      final finding = result.findings.single;
      expect(
        (finding.start, finding.end, finding.originalText),
        (23, 28, 'Feler'),
      );
      expect(finding.replacements, hasLength(8));
      expect(finding.revision, 4);
      final ignored = await provider.check(
        _request(
          text: '😀 Feler',
          language: 'de-CH',
          ignored: {'platform.spelling'},
        ),
      );
      expect(ignored.status, OfficeProofingStatus.success);
      expect(ignored.findings, isEmpty);
    },
  );

  test(
    'concurrent paragraphs serialize requests on the platform channel',
    () async {
      final pending = <Completer<List<SuggestionSpan>?>>[];
      final service = _Service((_, _) {
        final completer = Completer<List<SuggestionSpan>?>();
        pending.add(completer);
        return completer.future;
      });
      final provider = OfficePlatformSpellingProvider(
        supportedLanguages: ['de-DE'],
        service: service,
        isAvailable: () => true,
      );
      addTearDown(provider.dispose);
      final first = provider.check(_request(text: 'First'));
      final second = provider.check(_request(text: 'Second'));
      await Future<void>.delayed(Duration.zero);
      expect(service.calls.map((call) => call.text), ['First']);
      pending.first.complete([]);
      expect((await first).status, OfficeProofingStatus.success);
      await Future<void>.delayed(Duration.zero);
      expect(service.calls.map((call) => call.text), ['First', 'Second']);
      pending.last.complete([]);
      expect((await second).status, OfficeProofingStatus.success);
    },
  );

  test('distinct providers serialize the shared Flutter channel', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final pending = <Completer<List<Map<String, Object>>>>[];
    final calls = <String>[];
    messenger.setMockMethodCallHandler(SystemChannels.spellCheck, (call) {
      calls.add((call.arguments as List)[1] as String);
      final completer = Completer<List<Map<String, Object>>>();
      pending.add(completer);
      return completer.future;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.spellCheck, null),
    );
    final firstProvider = OfficePlatformSpellingProvider(
      supportedLanguages: ['de-DE'],
      isAvailable: () => true,
    );
    final secondProvider = OfficePlatformSpellingProvider(
      supportedLanguages: ['de-DE'],
      isAvailable: () => true,
    );
    addTearDown(firstProvider.dispose);
    addTearDown(secondProvider.dispose);
    final first = firstProvider.check(_request(text: 'First'));
    final second = secondProvider.check(_request(text: 'Second'));
    await Future<void>.delayed(Duration.zero);
    final callsBeforeCompletion = calls.toList();
    // Release both calls even on the old adapter, avoiding a hung mock channel.
    pending.first.complete([]);
    expect((await first).status, OfficeProofingStatus.success);
    await Future<void>.delayed(Duration.zero);
    if (pending.length > 1) pending.last.complete([]);
    expect((await second).status, OfficeProofingStatus.success);
    expect(callsBeforeCompletion, ['First']);
    expect(calls, ['First', 'Second']);
  });

  test('a shared injected service serializes providers too', () async {
    final pending = <Completer<List<SuggestionSpan>?>>[];
    final service = _Service((_, _) {
      final completer = Completer<List<SuggestionSpan>?>();
      pending.add(completer);
      return completer.future;
    });
    final providers = List.generate(
      2,
      (_) => OfficePlatformSpellingProvider(
        supportedLanguages: ['de-DE'],
        service: service,
        isAvailable: () => true,
      ),
    );
    for (final provider in providers) {
      addTearDown(provider.dispose);
    }
    final first = providers.first.check(_request(text: 'First'));
    final second = providers.last.check(_request(text: 'Second'));
    await Future<void>.delayed(Duration.zero);
    final started = service.calls.length;
    pending.first.complete([]);
    expect((await first).status, OfficeProofingStatus.success);
    await Future<void>.delayed(Duration.zero);
    pending.last.complete([]);
    expect((await second).status, OfficeProofingStatus.success);
    expect(started, 1);
  });

  test('independent injected services do not block each other', () async {
    final pending = Completer<List<SuggestionSpan>?>();
    final first = OfficePlatformSpellingProvider(
      supportedLanguages: ['de-DE'],
      service: _Service((_, _) => pending.future),
      isAvailable: () => true,
    );
    final second = OfficePlatformSpellingProvider(
      supportedLanguages: ['de-DE'],
      service: _Service((_, _) async => []),
      isAvailable: () => true,
    );
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final waiting = first.check(_request());
    expect(
      (await second.check(_request())).status,
      OfficeProofingStatus.success,
    );
    pending.complete([]);
    expect((await waiting).status, OfficeProofingStatus.success);
  });

  test(
    'disposal settles callers without releasing the active channel',
    () async {
      final pending = Completer<List<SuggestionSpan>?>();
      final service = _Service((_, text) async {
        if (text == 'First') return pending.future;
        return [];
      });
      final firstProvider = OfficePlatformSpellingProvider(
        supportedLanguages: ['de-DE'],
        service: service,
        isAvailable: () => true,
      );
      final secondProvider = OfficePlatformSpellingProvider(
        supportedLanguages: ['de-DE'],
        service: service,
        isAvailable: () => true,
      );
      addTearDown(firstProvider.dispose);
      addTearDown(secondProvider.dispose);
      final first = firstProvider.check(_request(text: 'First'));
      final queued = firstProvider.check(_request(text: 'Queued'));
      await Future<void>.delayed(Duration.zero);
      await firstProvider.dispose();
      final replacement = secondProvider.check(_request(text: 'Replacement'));
      await Future<void>.delayed(Duration.zero);
      final callsBeforeCompletion = service.calls
          .map((call) => call.text)
          .toList();
      OfficeProofingResult? firstWhilePending;
      OfficeProofingResult? queuedWhilePending;
      first.then((result) => firstWhilePending = result);
      queued.then((result) => queuedWhilePending = result);
      await Future<void>.delayed(Duration.zero);
      final settledBeforeCompletion = (
        firstWhilePending?.status,
        queuedWhilePending?.status,
      );
      pending.complete([]);
      await first;
      await queued;
      expect((await replacement).status, OfficeProofingStatus.success);
      expect(callsBeforeCompletion, ['First']);
      expect(settledBeforeCompletion, (
        OfficeProofingStatus.unavailable,
        OfficeProofingStatus.unavailable,
      ));
      expect(service.calls.map((call) => call.text), ['First', 'Replacement']);
    },
  );

  test(
    'a stuck channel bounds later callers without starting native work',
    () async {
      final pending = Completer<List<SuggestionSpan>?>();
      final service = _Service((_, text) async {
        if (text == 'First') return pending.future;
        return [];
      });
      OfficePlatformSpellingProvider provider() =>
          OfficePlatformSpellingProvider(
            supportedLanguages: ['de-DE'],
            service: service,
            isAvailable: () => true,
            timeout: const Duration(milliseconds: 10),
          );
      final first = provider();
      final second = provider();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      expect(
        (await first.check(_request(text: 'First'))).status,
        OfficeProofingStatus.failed,
      );
      final result = await second.check(_request(text: 'Second'));
      final callsBeforeCompletion = service.calls
          .map((call) => call.text)
          .toList();
      pending.complete([]);
      await Future<void>.delayed(Duration.zero);
      expect(result.status, OfficeProofingStatus.failed);
      expect(callsBeforeCompletion, ['First']);
      final recovered = provider();
      addTearDown(recovered.dispose);
      expect(
        (await recovered.check(_request(text: 'Recovered'))).status,
        OfficeProofingStatus.success,
      );
      expect(service.calls.map((call) => call.text), ['First', 'Recovered']);
    },
  );

  test(
    'late native errors release the channel only after actual completion',
    () async {
      for (final retireByDisposal in [false, true]) {
        final pending = Completer<List<SuggestionSpan>?>();
        final service = _Service((_, text) async {
          if (text == 'First') return pending.future;
          return [];
        });
        final firstProvider = OfficePlatformSpellingProvider(
          supportedLanguages: ['de-DE'],
          service: service,
          isAvailable: () => true,
          timeout: retireByDisposal
              ? const Duration(seconds: 2)
              : const Duration(milliseconds: 10),
        );
        final secondProvider = OfficePlatformSpellingProvider(
          supportedLanguages: ['de-DE'],
          service: service,
          isAvailable: () => true,
          timeout: const Duration(seconds: 2),
        );
        addTearDown(firstProvider.dispose);
        addTearDown(secondProvider.dispose);
        final first = firstProvider.check(_request(text: 'First'));
        await Future<void>.delayed(Duration.zero);
        final second = secondProvider.check(_request(text: 'Second'));
        if (retireByDisposal) await firstProvider.dispose();
        final firstResult = await first;
        final callsBeforeCompletion = service.calls
            .map((call) => call.text)
            .toList();
        pending.completeError(StateError('Late native failure'));
        expect((await second).status, OfficeProofingStatus.success);
        expect(
          firstResult.status,
          retireByDisposal
              ? OfficeProofingStatus.unavailable
              : OfficeProofingStatus.failed,
        );
        expect(callsBeforeCompletion, ['First']);
        expect(service.calls.map((call) => call.text), ['First', 'Second']);
      }
    },
  );

  test(
    'a queued request has its own deadline including channel wait',
    () async {
      final pending = Completer<List<SuggestionSpan>?>();
      final service = _Service((_, _) => pending.future);
      final first = OfficePlatformSpellingProvider(
        supportedLanguages: ['de-DE'],
        service: service,
        isAvailable: () => true,
        timeout: const Duration(seconds: 2),
      );
      final second = OfficePlatformSpellingProvider(
        supportedLanguages: ['de-DE'],
        service: service,
        isAvailable: () => true,
        timeout: const Duration(milliseconds: 10),
      );
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      final waiting = first.check(_request(text: 'First'));
      await Future<void>.delayed(Duration.zero);
      final result = await second.check(_request(text: 'Second'));
      pending.complete([]);
      expect((await waiting).status, OfficeProofingStatus.success);
      expect(result.status, OfficeProofingStatus.failed);
      expect(service.calls.map((call) => call.text), ['First']);
    },
  );

  test(
    'platform locales preserve scripts and numeric regions exactly',
    () async {
      final service = _Service((_, _) async => []);
      final provider = OfficePlatformSpellingProvider(
        supportedLanguages: ['zh_Hant_TW', 'es-419', 'sr-Latn'],
        service: service,
        isAvailable: () => true,
      );
      addTearDown(provider.dispose);
      for (final language in ['zh-Hant-TW', 'es-419', 'sr-Latn']) {
        expect(
          (await provider.check(_request(language: language))).status,
          OfficeProofingStatus.success,
        );
      }
      expect(service.calls.map((call) => call.locale.toLanguageTag()), [
        'zh-Hant-TW',
        'es-419',
        'sr-Latn',
      ]);
    },
  );

  test(
    'unrepresentable variants never fall back to a different dictionary',
    () async {
      final service = _Service((_, _) async => []);
      final provider = OfficePlatformSpellingProvider(
        supportedLanguages: [
          'de-1901',
          'sl-rozaj',
          'fr-CA-x-private',
          'en--US',
        ],
        service: service,
        isAvailable: () => true,
      );
      addTearDown(provider.dispose);
      for (final language in [
        'de-1901',
        'sl-rozaj',
        'fr-CA-x-private',
        'en--US',
      ]) {
        expect(provider.supportsLanguage(language), isFalse);
        expect(
          (await provider.check(_request(language: language))).status,
          OfficeProofingStatus.unsupported,
        );
      }
      expect(service.calls, isEmpty);
    },
  );

  test('platform findings leave URLs email and code alone', () async {
    const text =
        'Feler https://example.com/Feler userFeler@example.com `Feler` Feler';
    final service = _Service(
      (_, source) async => [
        for (final match in RegExp('Feler').allMatches(source))
          SuggestionSpan(TextRange(start: match.start, end: match.end), [
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
    final result = await provider.check(_request(text: text, startOffset: 30));
    expect(result.status, OfficeProofingStatus.success);
    expect(result.findings.map((finding) => finding.start), [
      30,
      30 + text.lastIndexOf('Feler'),
    ]);
    expect(result.findings.map((finding) => finding.originalText), [
      'Feler',
      'Feler',
    ]);
  });

  test(
    'native suggestions discard unusable entries before the display cap',
    () async {
      final provider = OfficePlatformSpellingProvider(
        supportedLanguages: ['de-DE'],
        service: _Service(
          (_, _) async => [
            const SuggestionSpan(TextRange(start: 0, end: 5), [
              '',
              ' ',
              '\u00a0\u2003',
              'Feler',
              'Fehler',
              'Fehler',
              'Feh\nler',
              'Feh\rler',
              'Feh\tler',
              'Feh\u0000ler',
              'Feh\u007fler',
              'Feh\u0085ler',
              'Feh\u2028ler',
              'Feh\u2029ler',
              'Feh\ud800ler',
              'Feh\udc00ler',
              'Fehler\ud800',
              'fehlte',
              'Felder',
              'Feier',
              'Feger',
              'Feder',
              'Feile',
              'Falter',
              'Filler',
            ]),
          ],
        ),
        isAvailable: () => true,
      );
      addTearDown(provider.dispose);
      final result = await provider.check(
        _request(text: 'Feler', startOffset: 17),
      );
      expect(result.status, OfficeProofingStatus.success);
      final finding = result.findings.single;
      expect(
        (finding.start, finding.end, finding.originalText),
        (17, 22, 'Feler'),
      );
      expect(finding.replacements, [
        'Fehler',
        'fehlte',
        'Felder',
        'Feier',
        'Feger',
        'Feder',
        'Feile',
        'Falter',
      ]);
    },
  );

  test('native suggestions preserve multiword and Unicode spelling', () async {
    const suggestions = [
      'a lot',
      'café',
      'cafe\u0301',
      'darf’s',
      'Haus‑Tür',
      '𐐀𐐨',
      'क्ष\u200dत्र',
      'می\u200cشود',
    ];
    final provider = OfficePlatformSpellingProvider(
      supportedLanguages: ['en-US'],
      service: _Service(
        (_, _) async => [
          const SuggestionSpan(TextRange(start: 0, end: 4), suggestions),
        ],
      ),
      isAvailable: () => true,
    );
    addTearDown(provider.dispose);
    final result = await provider.check(
      _request(text: 'alot', language: 'en-US'),
    );
    expect(result.status, OfficeProofingStatus.success);
    expect(result.findings.single.replacements, suggestions);
  });

  test(
    'native suggestions reject invisible and bidi-control replacements',
    () async {
      const accepted = [
        'Fehler',
        'مرحبا',
        'שלום',
        'می\u200cشود',
        'क्ष\u200dत्र',
      ];
      final provider = OfficePlatformSpellingProvider(
        supportedLanguages: ['de-DE'],
        service: _Service(
          (_, _) async => [
            SuggestionSpan(const TextRange(start: 0, end: 5), [
              '\u200b',
              '\u200e',
              '\u202e',
              '\u2066',
              '\u0301',
              '\ufe0f',
              ' \u200b\u0301\u00a0',
              for (final control in [
                '\u202a',
                '\u202b',
                '\u202c',
                '\u202d',
                '\u202e',
                '\u2066',
                '\u2067',
                '\u2068',
                '\u2069',
              ])
                'Feh${control}ler',
              ...accepted,
            ]),
          ],
        ),
        isAvailable: () => true,
      );
      addTearDown(provider.dispose);
      final result = await provider.check(_request(text: 'Feler'));
      expect(result.status, OfficeProofingStatus.success);
      expect(result.findings.single.replacements, accepted);
    },
  );

  test(
    'only invisible native suggestions leave an issue without blank actions',
    () async {
      final provider = OfficePlatformSpellingProvider(
        supportedLanguages: ['de-DE'],
        service: _Service(
          (_, _) async => [
            const SuggestionSpan(TextRange(start: 0, end: 5), [
              '\u200b',
              '\u200e',
              '\u202e',
              '\u2066',
              '\u0301',
              '\ufe0f',
            ]),
          ],
        ),
        isAvailable: () => true,
      );
      addTearDown(provider.dispose);
      final result = await provider.check(_request(text: 'Feler'));
      expect(result.status, OfficeProofingStatus.success);
      expect(result.findings.single.originalText, 'Feler');
      expect(result.findings.single.replacements, isEmpty);
    },
  );

  test(
    'native suggestion inspection and replacement sizes are bounded',
    () async {
      final provider = OfficePlatformSpellingProvider(
        supportedLanguages: ['de-DE'],
        service: _Service(
          (_, _) async => [
            SuggestionSpan(const TextRange(start: 0, end: 5), [
              'x' * 257,
              'y' * 256,
              ...List.filled(62, 'Feler'),
              'Fehler',
            ]),
          ],
        ),
        isAvailable: () => true,
      );
      addTearDown(provider.dispose);
      final result = await provider.check(_request(text: 'Feler'));
      expect(result.status, OfficeProofingStatus.success);
      expect(result.findings.single.replacements, ['y' * 256]);
    },
  );

  test(
    'an unknown word stays reviewable when no native suggestion is usable',
    () async {
      final provider = OfficePlatformSpellingProvider(
        supportedLanguages: ['de-DE'],
        service: _Service(
          (_, _) async => [
            const SuggestionSpan(TextRange(start: 0, end: 5), [
              '',
              'Feler',
              '\n',
            ]),
          ],
        ),
        isAvailable: () => true,
      );
      addTearDown(provider.dispose);
      final request = _request(text: 'Feler');
      final result = await provider.check(request);
      expect(result.status, OfficeProofingStatus.success);
      expect(result.findings.single.originalText, 'Feler');
      expect(result.findings.single.replacements, isEmpty);
      expect(
        OfficeProofingReport(request: request, results: [result]).isClean,
        isFalse,
      );
    },
  );

  test(
    'native spelling leaves numeric and connector identifier fragments alone',
    () async {
      const text =
          'Feler42 42Feler Feler_name Feler\u203fname Feler𝟘 𝟘Feler 30 Feler 20';
      final provider = OfficePlatformSpellingProvider(
        supportedLanguages: ['de-DE'],
        service: _Service(
          (_, source) async => [
            for (final match in RegExp('Feler').allMatches(source))
              SuggestionSpan(TextRange(start: match.start, end: match.end), [
                'Fehler',
              ]),
          ],
        ),
        isAvailable: () => true,
      );
      addTearDown(provider.dispose);
      final result = await provider.check(
        _request(text: text, startOffset: 11),
      );
      expect(result.status, OfficeProofingStatus.success);
      final finding = result.findings.single;
      expect(finding.originalText, 'Feler');
      expect(finding.start, 11 + text.lastIndexOf('Feler'));
      expect(finding.replacements, ['Fehler']);
    },
  );

  test('native spelling protects marked identifier grapheme edges', () async {
    final text =
        '42\u0301Feler _\u0301Feler 𝟘\u0301Feler '
        '𝟘${'\u0301' * 128}Feler Feler𝟘\u0301 Feler_\u0301 42\u0301 Feler';
    final provider = OfficePlatformSpellingProvider(
      supportedLanguages: ['de-DE'],
      service: _Service(
        (_, source) async => [
          for (final match in RegExp('Feler').allMatches(source))
            SuggestionSpan(TextRange(start: match.start, end: match.end), [
              'Fehler',
            ]),
        ],
      ),
      isAvailable: () => true,
    );
    addTearDown(provider.dispose);
    final result = await provider.check(_request(text: text, startOffset: 7));
    expect(result.status, OfficeProofingStatus.success);
    final finding = result.findings.single;
    expect(finding.originalText, 'Feler');
    expect(finding.start, 7 + text.lastIndexOf('Feler'));
    expect(finding.replacements, ['Fehler']);
  });

  test(
    'native word boundaries retain hyphen parts and CJK dictionary spans',
    () async {
      for (final sample in [
        (
          text: 'Feler-Tür',
          language: 'de-DE',
          start: 0,
          end: 5,
          replacement: 'Fehler',
        ),
        (
          text: 'Tür‑Feler',
          language: 'de-DE',
          start: 4,
          end: 9,
          replacement: 'Fehler',
        ),
        (
          text: '这是错子测试',
          language: 'zh-CN',
          start: 2,
          end: 4,
          replacement: '错字',
        ),
      ]) {
        final provider = OfficePlatformSpellingProvider(
          supportedLanguages: [sample.language],
          service: _Service(
            (_, _) async => [
              SuggestionSpan(TextRange(start: sample.start, end: sample.end), [
                sample.replacement,
              ]),
            ],
          ),
          isAvailable: () => true,
        );
        addTearDown(provider.dispose);
        final result = await provider.check(
          _request(text: sample.text, language: sample.language),
        );
        expect(result.status, OfficeProofingStatus.success);
        expect(
          result.findings.single.originalText,
          sample.text.substring(sample.start, sample.end),
        );
        expect(result.findings.single.replacements, [sample.replacement]);
      }
    },
  );

  test('malformed grapheme boundaries fail direct provider checks', () async {
    for (final sample in [
      (text: '😀 Feler', start: 1, end: 2),
      (text: 'Fe\u0301ler', start: 0, end: 2),
    ]) {
      final provider = OfficePlatformSpellingProvider(
        supportedLanguages: ['de-DE'],
        service: _Service(
          (_, _) async => [
            SuggestionSpan(TextRange(start: sample.start, end: sample.end), [
              'Fehler',
            ]),
          ],
        ),
        isAvailable: () => true,
      );
      addTearDown(provider.dispose);
      final result = await provider.check(_request(text: sample.text));
      expect(result.status, OfficeProofingStatus.failed);
      expect(result.findings, isEmpty);
    }
  });

  test('non-positive platform deadlines are rejected', () {
    for (final timeout in [Duration.zero, const Duration(milliseconds: -1)]) {
      expect(
        () => OfficePlatformSpellingProvider(
          supportedLanguages: ['de-DE'],
          timeout: timeout,
        ),
        throwsArgumentError,
      );
    }
  });

  test(
    'timeout retires a provider before another channel request starts',
    () async {
      final pending = Completer<List<SuggestionSpan>?>();
      final service = _Service((_, _) => pending.future);
      final provider = OfficePlatformSpellingProvider(
        supportedLanguages: ['de-DE'],
        service: service,
        isAvailable: () => true,
        timeout: const Duration(milliseconds: 5),
      );
      addTearDown(provider.dispose);
      final first = provider.check(_request());
      final queued = provider.check(_request(text: 'Queued'));
      expect((await first).status, OfficeProofingStatus.failed);
      expect((await queued).status, OfficeProofingStatus.unavailable);
      expect(service.calls, hasLength(1));
      pending.complete([]);
    },
  );

  test('a result completing after disposal is unavailable', () async {
    final pending = Completer<List<SuggestionSpan>?>();
    final provider = OfficePlatformSpellingProvider(
      supportedLanguages: ['de-DE'],
      service: _Service((_, _) => pending.future),
      isAvailable: () => true,
    );
    final future = provider.check(_request());
    await Future<void>.delayed(Duration.zero);
    await provider.dispose();
    pending.complete([]);
    expect((await future).status, OfficeProofingStatus.unavailable);
  });

  test(
    'real Flutter channel failures remain failed instead of successful empty responses',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        SystemChannels.spellCheck,
        (_) async => throw PlatformException(code: 'channel-failed'),
      );
      addTearDown(
        () =>
            messenger.setMockMethodCallHandler(SystemChannels.spellCheck, null),
      );
      final provider = OfficePlatformSpellingProvider(
        supportedLanguages: ['de-DE'],
        isAvailable: () => true,
      );
      addTearDown(provider.dispose);
      final result = await provider.check(_request());
      expect(result.status, OfficeProofingStatus.failed);
      expect(result.findings, isEmpty);
    },
  );

  test(
    'real Flutter service checks the same text independently across locales',
    () async {
      final calls = <List<String>>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.spellCheck, (
        call,
      ) async {
        expect(call.method, 'SpellCheck.initiateSpellCheck');
        final args = (call.arguments as List).cast<String>();
        calls.add(args);
        return args.first == 'de-DE'
            ? [
                <String, Object>{
                  'startIndex': 0,
                  'endIndex': 6,
                  'suggestions': ['Besser'],
                },
              ]
            : <Map<String, Object>>[];
      });
      addTearDown(
        () =>
            messenger.setMockMethodCallHandler(SystemChannels.spellCheck, null),
      );
      final provider = OfficePlatformSpellingProvider(
        supportedLanguages: ['de-DE', 'de-CH'],
        isAvailable: () => true,
      );
      addTearDown(provider.dispose);
      expect((await provider.check(_request())).findings, hasLength(1));
      final swiss = await provider.check(_request(language: 'de-CH'));
      expect(swiss.status, OfficeProofingStatus.success);
      expect(swiss.findings, isEmpty);
      expect(calls, [
        ['de-DE', 'Fehler'],
        ['de-CH', 'Fehler'],
      ]);
    },
  );
}
