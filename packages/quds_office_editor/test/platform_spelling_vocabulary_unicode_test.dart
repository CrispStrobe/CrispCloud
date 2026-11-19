import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

typedef _NativeRequest = ({String language, String text});

List<_NativeRequest> _nativeUnknownWords() {
  final requests = <_NativeRequest>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.spellCheck, (call) async {
    expect(call.method, 'SpellCheck.initiateSpellCheck');
    final arguments = call.arguments as List<Object?>;
    final language = arguments[0]! as String;
    final text = arguments[1]! as String;
    expect(text.startsWith('🙂 '), isTrue);
    expect(text.endsWith('.'), isTrue);
    requests.add((language: language, text: text));
    return <Map<String, Object>>[
      <String, Object>{
        'startIndex': 3,
        'endIndex': text.length - 1,
        'suggestions': <String>[],
      },
    ];
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.spellCheck, null),
  );
  return requests;
}

final class _NativeSession {
  _NativeSession(String word, {required OfficeProofingVocabulary vocabulary})
    : document = WmlDocument.empty(text: '🙂 $word.')
        ..proofingLanguage = 'de-DE' {
    session = WordProofingSession(
      document: () => document,
      revision: () => revision,
      vocabulary: vocabulary,
      service: OfficeProofingService(
        providers: <OfficeProofingProvider>[
          // Omit service so Flutter's actual DefaultSpellCheckService owns the
          // channel response and its text-only cache.
          OfficePlatformSpellingProvider(
            supportedLanguages: <String>['de-DE', 'de-CH'],
            isAvailable: () => true,
          ),
        ],
      ),
    );
    addTearDown(session.dispose);
  }

  WmlDocument document;
  int revision = 0;
  late final WordProofingSession session;

  void reopen(String word) {
    document = WmlDocument.empty(text: '🙂 $word.')..proofingLanguage = 'de-DE';
    revision++;
    session.observeDocument();
  }

  void setLanguage(String language) {
    document.proofingLanguage = language;
    revision++;
    session.observeDocument();
  }
}

Map<String, Object?> _persist(Map<String, Object?> snapshot) =>
    jsonDecode(jsonEncode(snapshot)) as Map<String, Object?>;

void _expectNativeWord(WordProofingSummary summary, String word) {
  expect(summary.complete, isTrue);
  final finding = summary.issues.single.finding;
  expect(finding.providerId, 'platform-spelling');
  expect(finding.category, OfficeProofingCategory.spelling);
  expect(
    (finding.start, finding.end, finding.originalText),
    (3, 3 + word.length, word),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'native personal spelling survives a decomposed reopen with exact owner and locale scope',
    () async {
      final requests = _nativeUnknownWords();
      final vocabulary = OfficeProofingVocabulary(ownerId: 'owner-a');
      final h = _NativeSession('Joël', vocabulary: vocabulary);
      final snapshots = <Map<String, Object?>>[];
      h.session.onVocabularyChanged = snapshots.add;

      final initial = await h.session.checkNow();
      _expectNativeWord(initial, 'Joël');
      h.session.addWord(initial.issues.single);
      expect(vocabulary.wordsFor('de-DE'), <String>{'Joël'});
      expect(snapshots.single['ownerId'], 'owner-a');
      expect((await h.session.checkNow()).issues, isEmpty);
      final afterAdd = requests.length;
      expect((await h.session.checkNow()).issues, isEmpty);
      expect(requests, hasLength(afterAdd));

      h.reopen('Joe\u0308l');
      final reopened = await h.session.checkNow();
      expect(reopened.complete, isTrue);
      expect(reopened.issues, isEmpty);
      // The native checker still reports the authored decomposed word. The
      // owner's canonical vocabulary suppresses it at the Word session layer.
      expect(
        reopened.reports.single.findings.single.originalText,
        'Joe\u0308l',
      );
      expect(requests.last, (language: 'de-DE', text: '🙂 Joe\u0308l.'));
      expect(h.document.paragraphs.single.text, '🙂 Joe\u0308l.');

      h.setLanguage('de-CH');
      _expectNativeWord(await h.session.checkNow(), 'Joe\u0308l');
      expect(requests.last, (language: 'de-CH', text: '🙂 Joe\u0308l.'));
      expect(vocabulary.wordsFor('de-CH'), isEmpty);

      final other = _NativeSession(
        'Joe\u0308l',
        vocabulary: OfficeProofingVocabulary(ownerId: 'owner-b'),
      );
      _expectNativeWord(await other.session.checkNow(), 'Joe\u0308l');
      expect(other.session.vocabulary.wordsFor('de-DE'), isEmpty);
      expect(vocabulary.wordsFor('de-DE'), <String>{'Joël'});
      expect(h.document.paragraphs.single.text, '🙂 Joe\u0308l.');
    },
  );

  test(
    'native ignored caron spelling restores from JSON and reappears after alias removal',
    () async {
      final requests = _nativeUnknownWords();
      final original = _NativeSession(
        'Š',
        vocabulary: OfficeProofingVocabulary(ownerId: 'owner-a'),
      );
      final snapshots = <Map<String, Object?>>[];
      original.session.onVocabularyChanged = snapshots.add;
      final initial = await original.session.checkNow();
      _expectNativeWord(initial, 'Š');
      original.session.ignoreWord(initial.issues.single);
      expect((await original.session.checkNow()).issues, isEmpty);
      expect(original.session.vocabulary.ignoredWordsFor('de-DE'), <String>{
        'Š',
      });
      final saved = _persist(snapshots.single);

      final reopened = _NativeSession(
        'S\u030c',
        vocabulary: OfficeProofingVocabulary(ownerId: 'owner-a'),
      );
      reopened.session.restoreVocabulary(saved);
      final restored = await reopened.session.checkNow();
      expect(restored.complete, isTrue);
      expect(restored.issues, isEmpty);
      expect(restored.reports.single.findings.single.originalText, 'S\u030c');
      final cached = requests.length;
      expect((await reopened.session.checkNow()).issues, isEmpty);
      expect(requests, hasLength(cached));

      final changed = <Map<String, Object?>>[];
      reopened.session.onVocabularyChanged = changed.add;
      reopened.session.unignoreWord('S\u030c', language: 'de-DE');
      expect(reopened.session.vocabulary.ignoredWordsFor('de-DE'), isEmpty);
      expect(changed, hasLength(1));
      _expectNativeWord(await reopened.session.checkNow(), 'S\u030c');
      expect(requests, hasLength(cached + 1));
      expect(requests.last, (language: 'de-DE', text: '🙂 S\u030c.'));
      expect(reopened.document.paragraphs.single.text, '🙂 S\u030c.');
      expect(original.document.paragraphs.single.text, '🙂 Š.');

      expect(
        () => reopened.session.restoreVocabulary(<String, Object?>{
          ...saved,
          'ownerId': 'owner-b',
        }),
        throwsArgumentError,
      );
      expect(reopened.session.vocabulary.ignoredWordsFor('de-DE'), isEmpty);
    },
  );

  test(
    'native soft hyphen before an accent saves a canonical personal word without rewriting source',
    () async {
      final requests = _nativeUnknownWords();
      const authored = 'Joe\u00ad\u0308l';
      final original = _NativeSession(
        authored,
        vocabulary: OfficeProofingVocabulary(ownerId: 'owner-a'),
      );
      final snapshots = <Map<String, Object?>>[];
      original.session.onVocabularyChanged = snapshots.add;
      final initial = await original.session.checkNow();
      _expectNativeWord(initial, authored);
      expect(requests.single, (language: 'de-DE', text: '🙂 Joe\u0308l.'));
      original.session.addWord(initial.issues.single);
      expect(original.session.vocabulary.wordsFor('de-DE'), <String>{'Joël'});
      expect((await original.session.checkNow()).issues, isEmpty);
      expect(original.document.paragraphs.single.text, '🙂 $authored.');

      final vocabulary = OfficeProofingVocabulary.fromJson(
        _persist(snapshots.single),
      );
      final reopened = _NativeSession('Joël', vocabulary: vocabulary);
      final restored = await reopened.session.checkNow();
      expect(restored.complete, isTrue);
      expect(restored.issues, isEmpty);
      expect(restored.reports.single.findings.single.originalText, 'Joël');
      final cached = requests.length;
      expect((await reopened.session.checkNow()).issues, isEmpty);
      expect(requests, hasLength(cached));

      vocabulary.removeWord('Joe\u0308l', language: 'de-DE');
      expect(vocabulary.wordsFor('de-DE'), isEmpty);
      _expectNativeWord(await reopened.session.checkNow(), 'Joël');
      expect(requests, hasLength(cached + 1));
      expect(reopened.document.paragraphs.single.text, '🙂 Joël.');
      expect(original.document.paragraphs.single.text, '🙂 $authored.');
    },
  );
}
