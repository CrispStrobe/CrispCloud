import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

/// The typing pause before a background pass, plus a frame of margin.
final _debounce = WordProofingTiming.idle + const Duration(milliseconds: 50);

/// Answers from a fixed table keyed by the trimmed segment text.
final class _FakeIdentifier implements LanguageIdentifier {
  _FakeIdentifier(this.answers);

  final Map<String, List<LanguageGuess>> answers;
  final calls = <List<String>>[];

  @override
  bool get isAvailable => true;

  @override
  Future<List<List<LanguageGuess>>> identify(List<String> texts) async {
    calls.add(texts);
    return [for (final t in texts) answers[t.trim()] ?? const []];
  }
}

final class _PendingIdentifier implements LanguageIdentifier {
  final started = Completer<void>();
  final _result = Completer<List<List<LanguageGuess>>>();
  List<String> _texts = const [];

  @override
  bool get isAvailable => true;

  @override
  Future<List<List<LanguageGuess>>> identify(List<String> texts) {
    _texts = List.of(texts);
    if (!started.isCompleted) started.complete();
    return _result.future;
  }

  void complete(String language) => _result.complete([
    for (final _ in _texts) [LanguageGuess(language, 1)],
  ]);
}

final class _Provider extends OfficeProofingProvider {
  final requests = <OfficeProofingRequest>[];

  @override
  String get id => 'language-routing';

  @override
  bool supportsLanguage(String language) => true;

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async {
    requests.add(request);
    return OfficeProofingResult(
      request: request,
      providerId: id,
      status: OfficeProofingStatus.success,
    );
  }
}

const _german =
    'Der Bericht wurde gestern veröffentlicht und sorgte für Aufsehen.';
const _german1 =
    'Die Ergebnisse überraschten selbst die erfahrenen Beobachter.';
const _german2 = 'Am Abend trafen sich die Minister zu einer langen Sitzung.';
const _german3 = 'Viele Fragen blieben trotzdem bis zum Schluss unbeantwortet.';
const _english = 'The report was published yesterday and caused quite a stir.';
const _arabic = 'وقد نشر التقرير أمس وأثار ضجة كبيرة في الأوساط السياسية.';

final _answers = <String, List<LanguageGuess>>{
  _german: const [LanguageGuess('de', 0.9999)],
  _german1: const [LanguageGuess('de', 0.9991)],
  _german2: const [LanguageGuess('de', 0.9993)],
  _german3: const [LanguageGuess('de', 0.9992)],
  _english: const [LanguageGuess('en', 0.999), LanguageGuess('de', 0.0004)],
  _arabic: const [LanguageGuess('ar', 0.998)],
};

/// The document default (docDefaults) is en-US: Word writes it onto ordinary
/// text, so it does not say the German text is English.
WmlDocument _document() => WmlDocument(
  proofingLanguage: 'en-US',
  sections: [
    WmlSection(
      pageSize: const WmlPageSize(width: 600, height: 800),
      margins: const WmlPageMargins(top: 50, bottom: 50, left: 48, right: 48),
      blocks: [
        // 0: no language at all.
        WmlParagraph(inlines: [WmlRun(text: _german1)]),
        // 1: an explicit French tag wins over detection.
        WmlParagraph(
          inlines: [
            WmlRun(text: _german2)..properties.proofingLanguage = 'fr-FR',
          ],
        ),
        // 2: the document default written onto the run is still a default.
        WmlParagraph(
          inlines: [
            WmlRun(text: _german3)..properties.proofingLanguage = 'en-US',
          ],
        ),
        // 3: German and Arabic in one unmarked run.
        WmlParagraph(inlines: [WmlRun(text: '$_german $_arabic')]),
        // 4: English text on an English default stays English.
        WmlParagraph(inlines: [WmlRun(text: _english)]),
      ],
    ),
  ],
);

({WordEditorController controller, _Provider provider, _FakeIdentifier fake})
_setUp({bool detection = true}) {
  final provider = _Provider();
  final controller = WordEditorController(
    document: _document(),
    proofingService: OfficeProofingService(providers: [provider]),
  );
  addTearDown(controller.dispose);
  final fake = _FakeIdentifier(_answers);
  if (detection) {
    controller.proofing.configureLanguageDetection(
      ParagraphLanguageDetector(fake),
    );
  }
  return (controller: controller, provider: provider, fake: fake);
}

Map<int, List<String>> _routed(WordEditorController controller, _Provider p) {
  final paragraphs = controller.document.paragraphs.toList();
  final result = <int, List<String>>{};
  for (final request in p.requests) {
    final index = paragraphs.indexWhere(
      (paragraph) => paragraph.text.contains(request.text.trim()),
    );
    result.putIfAbsent(index, () => []).add(request.language);
  }
  return result;
}

void _caretIn(WordEditorController controller, int paragraph) {
  controller.caret
    ..paragraphIndex = paragraph
    ..logicalIndex = 3
    ..collapseSelection();
  controller.refreshView();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('detection routes default-language text and never edits it', () async {
    final s = _setUp();
    List<Object?> languages() => [
      for (final paragraph
          in WordDeserializer().readBytes(s.controller.saveBytes()).paragraphs)
        for (final run in paragraph.inlines.whereType<WmlRun>())
          [
            run.text,
            run.properties.proofingLanguage,
            run.properties.complexScriptLanguage,
          ],
    ];
    final before = languages();
    await s.controller.proofing.checkNow();
    expect(s.fake.calls, hasLength(1), reason: 'one batch for the pass');
    expect(_routed(s.controller, s.provider), {
      0: ['de-DE'],
      1: ['fr-FR'],
      2: ['de-DE'],
      3: ['de-DE', 'ar'],
      4: ['en-US'],
    });
    expect(s.controller.canUndo, isFalse);
    expect(languages(), before);
    expect(s.controller.proofing.summary.complete, isTrue);
  });

  test('turning automatic detection off restores Word routing', () async {
    final s = _setUp();
    await s.controller.proofing.checkNow();
    s.provider.requests.clear();
    s.controller.proofing.automaticLanguageDetection = false;
    await s.controller.proofing.checkNow();
    expect(_routed(s.controller, s.provider), {
      0: ['en-US'],
      1: ['fr-FR'],
      2: ['en-US'],
      3: ['en-US'],
      4: ['en-US'],
    });
    s.provider.requests.clear();
    s.controller.proofing.automaticLanguageDetection = true;
    await s.controller.proofing.checkNow();
    expect(_routed(s.controller, s.provider)[3], ['de-DE', 'ar']);
  });

  test('without a detector nothing changes', () async {
    final s = _setUp(detection: false);
    await s.controller.proofing.checkNow();
    expect(_routed(s.controller, s.provider)[0], ['en-US']);
    _caretIn(s.controller, 3);
    final target = s.controller.textProofingTarget!;
    expect(target.detectedLanguages, isEmpty);
    expect(target.detectionPending, isFalse);
    expect(
      s.controller.applyDetectedTextProofingLanguages(target: target),
      isFalse,
    );
  });

  test('the target shows languages per script and detection', () async {
    final s = _setUp();
    _caretIn(s.controller, 3);
    var target = s.controller.textProofingTarget!;
    expect(target.scriptLanguages, {
      TextScript.latin: 'en-US',
      TextScript.arabic: 'en-US',
    });
    expect(target.detectionPending, isTrue);
    await s.controller.detectTextProofingLanguages(target);
    target = s.controller.textProofingTarget!;
    expect(target.detectionPending, isFalse);
    expect(target.detectedLanguages, {
      TextScript.latin: 'de',
      TextScript.arabic: 'ar',
    });
    expect(target.canApplyDetectedLanguages, isTrue);
  });

  test('apply detected language writes per-script tags and undoes', () async {
    final s = _setUp();
    _caretIn(s.controller, 3);
    await s.controller.detectTextProofingLanguages(
      s.controller.textProofingTarget!,
    );
    final target = s.controller.textProofingTarget!;
    expect(
      s.controller.applyDetectedTextProofingLanguages(target: target),
      isTrue,
    );
    final paragraph = s.controller.document.paragraphs.elementAt(3);
    final runs = paragraph.inlines.whereType<WmlRun>().toList();
    expect(paragraph.text, '$_german $_arabic');
    final german = runs.firstWhere((r) => r.text.contains('Bericht'));
    final arabic = runs.firstWhere((r) => r.text.contains('التقرير'));
    expect(german.properties.proofingLanguage, 'de-DE');
    expect(german.properties.complexScriptLanguage, isNull);
    expect(arabic.properties.complexScriptLanguage, 'ar-SA');
    expect(arabic.properties.proofingLanguage, isNull);
    final after = s.controller.textProofingTarget!;
    expect(after.scriptLanguages, {
      TextScript.latin: 'de-DE',
      TextScript.arabic: 'ar-SA',
    });
    expect(after.canApplyDetectedLanguages, isFalse);
    // The written tags survive DOCX.
    final reloaded = WordDeserializer().readBytes(s.controller.saveBytes());
    final saved = reloaded.paragraphs
        .elementAt(3)
        .inlines
        .whereType<WmlRun>()
        .toList();
    expect(
      saved
          .firstWhere((r) => r.text.contains('Bericht'))
          .properties
          .proofingLanguage,
      'de-DE',
    );
    expect(
      saved
          .firstWhere((r) => r.text.contains('التقرير'))
          .properties
          .complexScriptLanguage,
      'ar-SA',
    );

    s.controller.undo();
    final restored = s.controller.document.paragraphs.elementAt(3);
    expect(restored.inlines.whereType<WmlRun>(), hasLength(1));
    expect(
      restored.inlines.whereType<WmlRun>().single.properties.proofingLanguage,
      isNull,
    );
    expect(s.controller.canUndo, isFalse);
    s.controller.redo();
    expect(
      s.controller.textProofingTarget!.scriptLanguages[TextScript.arabic],
      'ar-SA',
    );
  });

  test('apply keeps an explicit tag of the same language', () async {
    final s = _setUp();
    s.controller.document.paragraphs
            .elementAt(0)
            .inlines
            .whereType<WmlRun>()
            .single
            .properties
            .proofingLanguage =
        'de-CH';
    s.controller.refresh();
    _caretIn(s.controller, 0);
    await s.controller.detectTextProofingLanguages(
      s.controller.textProofingTarget!,
    );
    final target = s.controller.textProofingTarget!;
    expect(target.canApplyDetectedLanguages, isFalse);
    expect(
      s.controller.applyDetectedTextProofingLanguages(target: target),
      isTrue,
    );
    expect(s.controller.canUndo, isFalse, reason: 'nothing to change');
  });

  test(
    'pending language detection cannot publish into a disposed session',
    () async {
      final s = _setUp(detection: false);
      final pending = _PendingIdentifier();
      final session = s.controller.proofing;
      session.configureLanguageDetection(ParagraphLanguageDetector(pending));
      final loading = session.detectLanguages([_german]);
      await pending.started.future;
      session.dispose();
      pending.complete('de');
      expect(await loading, isNull);
      expect(session.detectedLanguages(_german), isNull);
      expect(session.languageDetector, isNull);
      expect(s.provider.requests, isEmpty);
    },
  );

  test(
    'pending language detection cannot replace a newer detector result',
    () async {
      final s = _setUp(detection: false);
      final pending = _PendingIdentifier();
      final session = s.controller.proofing;
      session.configureLanguageDetection(ParagraphLanguageDetector(pending));
      final old = session.detectLanguages([_german]);
      await pending.started.future;
      session.configureLanguageDetection(
        ParagraphLanguageDetector(
          _FakeIdentifier({
            _german: const [LanguageGuess('fr', 1)],
          }),
        ),
      );
      final current = await session.detectLanguages([_german]);
      expect(current!.single.segments.single.language, 'fr');
      pending.complete('de');
      expect(await old, isNull);
      expect(
        session.detectedLanguages(_german)!.segments.single.language,
        'fr',
      );
      expect(s.controller.canUndo, isFalse);
    },
  );

  test(
    'pending language check finishes quietly after session disposal',
    () async {
      final s = _setUp(detection: false);
      final pending = _PendingIdentifier();
      final session = s.controller.proofing;
      session.configureLanguageDetection(ParagraphLanguageDetector(pending));
      final checking = session.checkNow();
      await pending.started.future;
      session.dispose();
      pending.complete('de');
      await expectLater(checking, completes);
      expect(s.provider.requests, isEmpty);
      expect(session.detectedLanguages(_german), isNull);
    },
  );

  test(
    'pending language check cannot publish after detector replacement',
    () async {
      final s = _setUp(detection: false);
      final pending = _PendingIdentifier();
      final session = s.controller.proofing;
      session.configureLanguageDetection(ParagraphLanguageDetector(pending));
      var notifications = 0;
      session.addListener(() => notifications++);
      final checking = session.checkNow();
      await pending.started.future;
      session.configureLanguageDetection(
        ParagraphLanguageDetector(_FakeIdentifier(_answers)),
      );
      final beforeOldCompletion = notifications;
      pending.complete('de');
      await expectLater(checking, completes);
      expect(notifications, beforeOldCompletion);
      expect(s.provider.requests, isEmpty);
    },
  );

  group('review pane', () {
    setUpAll(OfficeHostFonts.ensureRegistered);

    testWidgets('shows languages per script and applies detection', (
      tester,
    ) async {
      final s = _setUp();
      final focus = FocusNode();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 920);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        focus.dispose();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Liberation Sans'),
          home: Scaffold(
            body: QudsWordEditor(controller: s.controller, focusNode: focus),
          ),
        ),
      );
      Future<void> flush() async {
        await tester.pump();
        await tester.pump(_debounce);
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 1));
        }
      }

      await flush();
      _caretIn(s.controller, 3);
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('word-review-language-status')),
      );
      await flush();
      Finder key(String value) => find.byKey(ValueKey<String>(value));
      String text(String value) => tester.widget<Text>(key(value)).data!;
      final scrollable = find
          .descendant(
            of: key('word-review-pane'),
            matching: find.byType(Scrollable),
          )
          .first;
      if (key('live-proofing-apply-detected').evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          key('live-proofing-apply-detected'),
          120,
          scrollable: scrollable,
        );
      }
      expect(
        text('live-proofing-text-scripts'),
        'Latin text: English · Arabic text: English',
      );
      expect(
        text('live-proofing-text-detected'),
        'Detected: Latin text: German · Arabic text: Arabic',
      );
      final revision = s.controller.contentRevision;
      await tester.ensureVisible(key('live-proofing-apply-detected'));
      await tester.pump();
      await tester.tap(key('live-proofing-apply-detected'));
      await flush();
      expect(tester.takeException(), isNull);
      expect(s.controller.contentRevision, isNot(revision));
      expect(
        text('live-proofing-text-scripts'),
        'Latin text: German · Arabic text: Arabic',
      );
      expect(text('live-review-notice'), contains('Undo'));
      expect(
        tester
            .widget<TextButton>(key('live-proofing-apply-detected'))
            .onPressed,
        isNull,
      );
      s.controller.undo();
      await flush();
      expect(
        text('live-proofing-text-scripts'),
        'Latin text: English · Arabic text: English',
      );
    });
  });
}
