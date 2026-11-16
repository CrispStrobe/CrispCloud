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
