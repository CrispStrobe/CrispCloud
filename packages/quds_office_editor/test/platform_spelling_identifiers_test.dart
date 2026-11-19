import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

final class _IdentifierService extends SpellCheckService {
  _IdentifierService(this.respond);

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

OfficeProofingRequest _request(String text, {int startOffset = 0}) =>
    OfficeProofingRequest(
      documentId: 'native-identifiers',
      blockId: 'paragraph',
      revision: 7,
      text: text,
      startOffset: startOffset,
    );

OfficePlatformSpellingProvider _provider(_IdentifierService service) {
  final provider = OfficePlatformSpellingProvider(
    supportedLanguages: ['de-DE'],
    service: service,
    isAvailable: () => true,
  );
  addTearDown(provider.dispose);
  return provider;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final sample in <({String name, List<String> words})>[
    (
      name: 'digits',
      words: ['Feler42', '42Feler', 'Fe42ler', 'Feler𝟘', '𝟘Feler', '٤Feler'],
    ),
    (
      name: 'connectors',
      words: [
        'Feler_name',
        '_Feler',
        'Fe_ler',
        'Feler\u203fname',
        'Fe\u2054ler',
      ],
    ),
    (
      name: 'marked numeric and connector clusters',
      words: [
        'Fe4\u0301ler',
        'Fe_\u0301ler',
        '𝟘\u0301Feler',
        'Feler4\ufe0f\u20e3',
      ],
    ),
  ]) {
    test(
      'whole native identifiers containing ${sample.name} are protected',
      () async {
        for (final word in sample.words) {
          final service = _IdentifierService(
            (text) => [
              SuggestionSpan(TextRange(start: 0, end: text.length), ['Fehler']),
            ],
          );
          final result = await _provider(service).check(_request(word));
          expect(result.status, OfficeProofingStatus.success, reason: word);
          expect(result.findings, isEmpty, reason: word);
          expect(service.requests, [word]);
        }
      },
    );
  }

  test(
    'partial native spans that contain an identifier marker are protected',
    () async {
      for (final sample in [
        (text: 'prefixFe42lersuffix', start: 6, end: 10),
        (text: 'prefixFe_lersuffix', start: 6, end: 10),
        (text: 'prefixFe𝟘lersuffix', start: 6, end: 11),
      ]) {
        final service = _IdentifierService(
          (_) => [
            SuggestionSpan(TextRange(start: sample.start, end: sample.end), [
              'Fehler',
            ]),
          ],
        );
        final result = await _provider(service).check(_request(sample.text));
        expect(result.status, OfficeProofingStatus.success);
        expect(result.findings, isEmpty, reason: sample.text);
      }
    },
  );

  test('soft hyphens cannot expose a whole native identifier', () async {
    for (final source in [
      'Fe\u00adler42',
      'Fe\u00adler_name',
      'Fe\u00ad4\u0301ler',
    ]) {
      final service = _IdentifierService(
        (text) => [
          SuggestionSpan(TextRange(start: 0, end: text.length), ['Fehler']),
        ],
      );
      final result = await _provider(
        service,
      ).check(_request(source, startOffset: 19));
      expect(result.status, OfficeProofingStatus.success);
      expect(result.findings, isEmpty, reason: source);
      expect(service.requests, [source.replaceAll('\u00ad', '')]);
    }
  });

  test(
    'identifier protection retains separate prose, hyphen parts and CJK spans',
    () async {
      for (final sample in [
        (text: '42 Feler 20', word: 'Feler'),
        (text: '_ Feler _', word: 'Feler'),
        (text: '42-Feler', word: 'Feler'),
        (text: 'Feler‑42', word: 'Feler'),
        (text: '这是错子测试', word: '错子'),
        (text: 'これは誤字です', word: '誤字'),
        (text: '٤،Feler', word: 'Feler'),
      ]) {
        final start = sample.text.indexOf(sample.word);
        final service = _IdentifierService(
          (_) => [
            SuggestionSpan(
              TextRange(start: start, end: start + sample.word.length),
              ['correct'],
            ),
          ],
        );
        final result = await _provider(
          service,
        ).check(_request(sample.text, startOffset: 31));
        expect(result.status, OfficeProofingStatus.success);
        final finding = result.findings.single;
        expect(
          (finding.start, finding.end),
          (31 + start, 31 + start + sample.word.length),
        );
        expect(finding.originalText, sample.word);
        expect(finding.replacements, ['correct']);
      }
    },
  );

  test('identifier lookup is independent of native result order', () async {
    final words = [
      'Feler',
      for (var i = 0; i < 128; i++) 'Feler_${i}name',
      'Feler',
    ];
    final text = words.join(' ');
    final service = _IdentifierService(
      (source) => [
        for (final match in RegExp(r'\S+').allMatches(source).toList().reversed)
          SuggestionSpan(TextRange(start: match.start, end: match.end), [
            'Fehler',
          ]),
      ],
    );
    final result = await _provider(service).check(_request(text));
    expect(result.status, OfficeProofingStatus.success);
    expect(result.findings.map((finding) => finding.start), [
      text.lastIndexOf('Feler'),
      0,
    ]);
    expect(result.findings.map((finding) => finding.originalText), [
      'Feler',
      'Feler',
    ]);
  });

  testWidgets(
    'native Word review corrects prose without rewriting whole identifiers',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final requests = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.spellCheck, (
        call,
      ) async {
        expect(call.method, 'SpellCheck.initiateSpellCheck');
        final args = call.arguments as List<Object?>;
        expect(args.first, 'de-DE');
        final source = args[1]! as String;
        requests.add(source);
        return [
          for (final match in RegExp(
            r'Feler42|Feler_name|Feler𝟘|Feler',
          ).allMatches(source))
            <String, Object>{
              'startIndex': match.start,
              'endIndex': match.end,
              'suggestions': ['Fehler'],
            },
        ];
      });
      addTearDown(
        () =>
            messenger.setMockMethodCallHandler(SystemChannels.spellCheck, null),
      );
      const original = 'Feler42 Feler_name Fe\u00adler𝟘. 🙂 Feler.';
      const corrected = 'Feler42 Feler_name Fe\u00adler𝟘. 🙂 Fehler.';
      final controller = WordEditorController(
        document: WmlDocument.empty(text: original)..proofingLanguage = 'de-DE',
        proofingService: OfficeProofingService(
          providers: [
            OfficePlatformSpellingProvider(
              supportedLanguages: ['de-DE'],
              isAvailable: () => true,
            ),
          ],
        ),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: WordProofingDialog(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.proofing.summary.complete, isTrue);
      expect(controller.document.paragraphs.first.text, original);
      expect(controller.canUndo, isFalse);
      final finding = controller.proofing.summary.issues.single.finding;
      expect(
        (finding.start, finding.originalText),
        (original.lastIndexOf('Feler'), 'Feler'),
      );
      final correction = find.widgetWithText(OutlinedButton, 'Fehler');
      expect(correction, findsOneWidget);
      await tester.ensureVisible(correction);
      await tester.pump();
      await tester.tap(correction);
      await tester.pumpAndSettle();
      expect(controller.document.paragraphs.first.text, corrected);
      expect(controller.proofing.summary.complete, isTrue);
      expect(controller.proofing.summary.issues, isEmpty);
      expect(requests.last, corrected.replaceAll('\u00ad', ''));
      controller.undo();
      expect(controller.document.paragraphs.first.text, original);
      controller.redo();
      expect(controller.document.paragraphs.first.text, corrected);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
