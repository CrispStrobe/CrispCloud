import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';

import 'analysis.dart';
import 'backend.dart';
import 'bundle.dart';
import 'grammar_planner.dart';
import 'transport.dart';

/// Families enabled when a host turns manual native German grammar on and
/// selects nothing else. Only families that passed their sealed
/// qualification belong here (grammar v2 record:
/// docs/validation/native-spacy-grammar-v2-20261120).
///
/// Grammar v2 (20 Nov 2026): np-agreement, preposition-case and
/// verb-position passed every predeclared gate; subject-person failed (one
/// finding on a valid control) and stays an opt-in experimental family.
const spacyGrammarQualifiedFamilies = <SpacyGrammarFamily>{
  SpacyGrammarFamily.nounVerb,
  SpacyGrammarFamily.nounPhraseAgreement,
  SpacyGrammarFamily.prepositionCase,
  SpacyGrammarFamily.verbPosition,
};

/// [spacyGrammarQualifiedFamilies] as stable [SpacyGrammarFamily.id]s, for
/// host settings (a test keeps both sets equal).
const spacyGrammarQualifiedFamilyIds = <String>{
  'noun-verb',
  'np-agreement',
  'preposition-case',
  'verb-position',
};

/// Explicitly enabled, manual-only native grammar provider.
///
/// This provider owns its transport. Do not share that transport with another
/// provider or the analysis view. Register with the editor's configureManual,
/// never its ordinary typing service. The package registers nothing itself.
final class SpacyGrammarProvider extends OfficeProofingProvider {
  SpacyGrammarProvider.withTransport({
    required this._transport,
    this.enabled = false,
    OfficeProofingVocabulary? vocabulary,
    Set<SpacyGrammarFamily> families = spacyGrammarQualifiedFamilies,
    bool englishMessages = false,
  }) : vocabulary = vocabulary ?? OfficeProofingVocabulary(),
       families = Set<SpacyGrammarFamily>.unmodifiable(families),
       _planner = SpacyGermanGrammarPlanner(
         families: Set<SpacyGrammarFamily>.unmodifiable(families),
         englishMessages: englishMessages,
       );

  static Future<SpacyGrammarProvider> load({
    required SpacyBackendFactory backendFactory,
    bool enabled = false,
    OfficeProofingVocabulary? vocabulary,
    Set<SpacyGrammarFamily> families = spacyGrammarQualifiedFamilies,
    bool englishMessages = false,
    Duration startupTimeout = const Duration(seconds: 60),
    Duration requestTimeout = const Duration(seconds: 30),
  }) async {
    if (!enabled) {
      throw const SpacyUnavailableException(
        'Optional manual German grammar is disabled.',
      );
    }
    final transport = await startSpacyWorker(
      bundle: const SpacyBundle.germanF32(),
      backendFactory: backendFactory,
      startupTimeout: startupTimeout,
      requestTimeout: requestTimeout,
    );
    return SpacyGrammarProvider.withTransport(
      transport: transport,
      enabled: true,
      vocabulary: vocabulary,
      families: families,
      englishMessages: englishMessages,
    );
  }

  final bool enabled;
  final OfficeProofingVocabulary vocabulary;
  final SpacyTransport _transport;

  /// Enabled rule families; see [SpacyGrammarFamily].
  final Set<SpacyGrammarFamily> families;
  final SpacyGermanGrammarPlanner _planner;
  final Map<String, ({int generation, OfficeProofingRequest request})> _latest =
      {};
  int _generation = 0;
  bool _disposed = false;
  Future<void>? _closing;

  @override
  String get id => 'spacy-german-grammar';

  @override
  int get configurationRevision => vocabulary.revision;

  @override
  bool supportsLanguage(String language) =>
      normalizeProofingLanguage(language) == 'de-DE';

  String _key(OfficeProofingRequest request) =>
      jsonEncode([request.documentId, request.blockId, request.startOffset]);

  /// Cancels this exact admitted request object, if it is still current.
  /// An obsolete request cannot cancel a newer check for the same unit.
  /// Settles pending callers through the bounded worker. Active native work
  /// keeps its context until it returns; cancellation never kills an isolate.
  void cancel(OfficeProofingRequest request) {
    final key = _key(request);
    if (!identical(_latest[key]?.request, request)) return;
    _latest.remove(key);
    if (!_disposed) _transport.cancel(key);
  }

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async {
    if (_disposed || !enabled) {
      return _result(
        request,
        OfficeProofingStatus.unavailable,
        _disposed
            ? 'Optional German grammar was disposed.'
            : 'Optional manual German grammar is disabled.',
      );
    }
    final key = _key(request);
    final generation = ++_generation;
    _latest[key] = (generation: generation, request: request);
    try {
      if (!supportsLanguage(request.language)) {
        _transport.cancel(key);
        return _result(
          request,
          OfficeProofingStatus.unsupported,
          'The guarded German grammar policy supports de-DE only.',
        );
      }
      if (families.every(
        (family) => family.ignoredBy(request.ignoredRuleIds),
      )) {
        _transport.cancel(key);
        return _result(
          request,
          OfficeProofingStatus.success,
          families.length == 1 && families.single == SpacyGrammarFamily.nounVerb
              ? 'Noun/verb agreement is ignored for this request.'
              : 'Every enabled native grammar rule is ignored for this request.',
        );
      }
      final vocabularyRevision = vocabulary.revision;
      final personal = Set<String>.unmodifiable({
        ...vocabulary.wordsFor(request.language),
        ...vocabulary.ignoredWordsFor(request.language),
      });
      final ignored = request.ignoredRuleIds.toList()..sort();
      final analysisRequest = LinguisticAnalysisRequest(
        text: request.text,
        documentId: request.documentId,
        blockId: request.blockId,
        revision: request.revision,
        locale: request.language,
        startOffset: request.startOffset,
        generation: generation,
        configurationId: jsonEncode([
          families.length == 1 && families.single == SpacyGrammarFamily.nounVerb
              ? 'spacy-grammar-v1'
              : 'spacy-grammar-v2:${[for (final f in families) f.id].join(',')}',
          vocabularyRevision,
          ignored,
        ]),
      );
      final analysis = await _transport.analyze(analysisRequest);
      if (_disposed) {
        return _result(
          request,
          OfficeProofingStatus.unavailable,
          'Optional German grammar was disposed.',
        );
      }
      if (_latest[key]?.generation != generation ||
          vocabulary.revision != vocabularyRevision) {
        return _result(
          request,
          OfficeProofingStatus.failed,
          'The source or personal vocabulary changed; check again.',
        );
      }
      if (!analysis.request.sameSnapshot(analysisRequest) ||
          (analysis.identity != null &&
              analysis.identity != _transport.identity)) {
        return _result(
          request,
          OfficeProofingStatus.failed,
          'The analysis belongs to a different snapshot or native runtime.',
        );
      }
      final plan = await _planner.plan(
        request,
        analysis,
        personalWords: personal,
      );
      // Preparing lexical buckets yields. A vocabulary or source change during
      // that work invalidates the result just as one during inference does.
      if (_disposed ||
          _latest[key]?.generation != generation ||
          vocabulary.revision != vocabularyRevision) {
        return _result(
          request,
          _disposed
              ? OfficeProofingStatus.unavailable
              : OfficeProofingStatus.failed,
          'The grammar snapshot changed before completion; check again.',
        );
      }
      return plan.result;
    } on SpacyUnavailableException catch (error) {
      return _result(request, OfficeProofingStatus.unavailable, error.message);
    } on Object {
      return _result(
        request,
        OfficeProofingStatus.failed,
        'The local grammar request failed; check again.',
      );
    } finally {
      if (_latest[key]?.generation == generation) _latest.remove(key);
    }
  }

  OfficeProofingResult _result(
    OfficeProofingRequest request,
    OfficeProofingStatus status,
    String message,
  ) => OfficeProofingResult(
    request: request,
    providerId: id,
    status: status,
    message: message,
  );

  @override
  Future<void> dispose() {
    _disposed = true;
    _latest.clear();
    return _closing ??= _transport.dispose();
  }
}
