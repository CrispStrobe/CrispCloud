import 'dart:ui' show Locale;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/src/proofing/platform_spelling_provider.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

final class _Service extends SpellCheckService {
  _Service(this.respond);

  final Future<List<SuggestionSpan>?> Function(String text) respond;
  final calls = <String>[];

  @override
  Future<List<SuggestionSpan>?> fetchSpellCheckSuggestions(
    Locale locale,
    String text,
  ) {
    calls.add(text);
    return respond(text);
  }
}

OfficeProofingRequest _request(String text, {int startOffset = 0}) =>
    OfficeProofingRequest(
      documentId: 'native-projection',
      blockId: 'paragraph',
      revision: 9,
      text: text,
      startOffset: startOffset,
    );

OfficePlatformSpellingProvider _provider(_Service service) {
  final provider = OfficePlatformSpellingProvider(
    supportedLanguages: ['de-DE'],
    service: service,
    isAvailable: () => true,
  );
  addTearDown(provider.dispose);
  return provider;
}

List<SuggestionSpan> _misspellings(String text) => [
  for (final match in RegExp('Feler').allMatches(text))
    SuggestionSpan(TextRange(start: match.start, end: match.end), ['Fehler']),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('only discretionary hyphens are omitted from native input', () async {
    const source = '😀 Fe\u00adler-Tür\u2011Test darf’s\u00a0a\u200db\n';
    const checked = '😀 Feler-Tür\u2011Test darf’s\u00a0a\u200db\n';
    final service = _Service((_) async => []);
    final request = _request(source);
    final result = await _provider(service).check(request);
    expect(result.status, OfficeProofingStatus.success);
    expect(service.calls, [checked]);
    expect(identical(result.request, request), isTrue);
    expect(result.request.text, source);
  });

  test(
    'native ranges map back across repeated and earlier soft hyphens',
    () async {
      const source = '😀 \u00adFe\u00ad\u00adler\u00ad und Tu\u0308\u00adrr.';
      const checked = '😀 Feler und Tu\u0308rr.';
      final service = _Service(
        (text) async => [
          for (final match in RegExp('Feler|Tu\u0308rr').allMatches(text))
            SuggestionSpan(TextRange(start: match.start, end: match.end), [
              match.group(0) == 'Feler' ? 'Fehler' : 'Tür',
            ]),
        ],
      );
      final result = await _provider(
        service,
      ).check(_request(source, startOffset: 19));
      expect(result.status, OfficeProofingStatus.success);
      expect(service.calls, [checked]);
      expect(
        result.findings.map(
          (finding) => (
            finding.start,
            finding.end,
            finding.originalText,
            finding.replacements.single,
          ),
        ),
        [
          (
            19 + source.indexOf('Fe'),
            19 + source.indexOf('ler') + 3,
            'Fe\u00ad\u00adler',
            'Fehler',
          ),
          (
            19 + source.indexOf('Tu'),
            19 + source.length - 1,
            'Tu\u0308\u00adrr',
            'Tür',
          ),
        ],
      );
      expect(result.findings.every((finding) => finding.revision == 9), isTrue);
    },
  );

  test('projection does not own leading or trailing layout controls', () async {
    const source = '\u00ad\u00adFeler\u00ad\u00ad';
    final service = _Service((text) async => _misspellings(text));
    final result = await _provider(service).check(_request(source));
    expect(result.status, OfficeProofingStatus.success);
    expect(service.calls, ['Feler']);
    final finding = result.findings.single;
    expect((finding.start, finding.end, finding.originalText), (2, 7, 'Feler'));
  });

  test('native no-op suggestions do not remove discretionary layout', () async {
    const source = 'Fe\u00adler';
    final service = _Service(
      (text) async => [
        SuggestionSpan(TextRange(start: 0, end: text.length), [
          'Feler',
          source,
          'Fehler',
        ]),
      ],
    );
    final result = await _provider(service).check(_request(source));
    expect(result.status, OfficeProofingStatus.success);
    expect(result.findings.single.originalText, source);
    expect(result.findings.single.replacements, ['Fehler']);
  });

  test('projected links email and code remain protected', () async {
    const source =
        'Fe\u00adler ht\u00adtps://example.com/Fe\u00adler '
        'u\u00adser@example.com `Fe\u00adler` Fe\u00adler';
    final service = _Service(
      (text) async => [
        ..._misspellings(text),
        SuggestionSpan(
          TextRange(start: text.indexOf('user'), end: text.indexOf('user') + 4),
          ['User'],
        ),
      ],
    );
    final result = await _provider(service).check(_request(source));
    expect(result.status, OfficeProofingStatus.success);
    expect(result.findings.map((finding) => finding.start), [
      0,
      source.lastIndexOf('Fe\u00adler'),
    ]);
    expect(result.findings.map((finding) => finding.originalText), [
      'Fe\u00adler',
      'Fe\u00adler',
    ]);
  });

  test(
    'soft hyphens do not expose numeric or marked connector fragments',
    () async {
      const source =
          '42\u00adFeler Feler\u00ad42 _\u0301\u00adFeler '
          'Feler\u00ad_ 𝟘\u0301\u00adFeler 42\u00ad Fe\u00adler';
      final service = _Service((text) async => _misspellings(text));
      final result = await _provider(service).check(_request(source));
      expect(result.status, OfficeProofingStatus.success);
      final finding = result.findings.single;
      expect(finding.start, source.lastIndexOf('Fe\u00adler'));
      expect(finding.originalText, 'Fe\u00adler');
      expect(finding.replacements, ['Fehler']);
    },
  );

  test(
    'empty projected input completes without occupying the native lane',
    () async {
      final service = _Service((_) async => null);
      final provider = _provider(service);
      for (final text in ['', '\u00ad', '\u00ad\u00ad\u00ad']) {
        final request = _request(text);
        final result = await provider.check(request);
        expect(result.status, OfficeProofingStatus.success);
        expect(result.findings, isEmpty);
        expect(
          OfficeProofingReport(request: request, results: [result]).isClean,
          isTrue,
        );
      }
      expect(service.calls, isEmpty);
    },
  );

  test(
    'equal projected texts retain independent original source maps',
    () async {
      final service = _Service((text) async => _misspellings(text));
      final provider = _provider(service);
      for (final source in ['Fe\u00adler', '\u00adFeler', 'Feler\u00ad']) {
        final result = await provider.check(_request(source, startOffset: 7));
        expect(result.status, OfficeProofingStatus.success);
        final finding = result.findings.single;
        final start = source.indexOf('F');
        final end = source.lastIndexOf('r') + 1;
        expect(
          (finding.start, finding.end, finding.originalText),
          (7 + start, 7 + end, source.substring(start, end)),
        );
      }
      expect(service.calls, ['Feler', 'Feler', 'Feler']);
    },
  );

  test('backend bounds are checked against projected text length', () async {
    final provider = _provider(
      _Service(
        (_) async => [
          const SuggestionSpan(TextRange(start: 0, end: 6), ['Fehler']),
        ],
      ),
    );
    final result = await provider.check(_request('Fe\u00ad\u00adler'));
    expect(result.status, OfficeProofingStatus.failed);
    expect(result.findings, isEmpty);
  });

  test(
    'projected ranges cannot split newly joined grapheme clusters',
    () async {
      for (final sample in [
        (source: 'Fe\u00ad\u0301ler', start: 0, end: 2),
        (source: '\u0600\u00adFeler', start: 1, end: 6),
        (source: '\u00ad😀 Feler', start: 1, end: 2),
      ]) {
        final provider = _provider(
          _Service(
            (_) async => [
              SuggestionSpan(TextRange(start: sample.start, end: sample.end), [
                'Text',
              ]),
            ],
          ),
        );
        final result = await provider.check(_request(sample.source));
        expect(result.status, OfficeProofingStatus.failed);
        expect(result.findings, isEmpty);
      }
    },
  );
}
