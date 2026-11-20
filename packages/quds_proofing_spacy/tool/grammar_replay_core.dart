// Shared core of the cross-binary grammar replays, independent of where the
// library is loaded from. The desktop tools (`replay_grammar_panels.dart`,
// `replay_grammar_v2.dart`) open a worker from a library path; the mobile
// integration test (Studio example `integration_test/
// mobile_spacy_grammar_replay_test.dart`) passes the worker the Studio host
// opens for grammar inside the app. Both run exactly this code.
//
// Neither replay is a new qualification of the planner. They answer one
// question: does another exact native build produce the same annotations,
// and therefore the same manual grammar outcome, as the build that consumed
// the panel? Inputs are passed as bytes; nothing here reads the repository.
//
// * [replayConsumedPanel]: the W6/W7 panels (schema
//   `quds.spacy.grammar.evaluation.v1`), the default planner (noun-verb), the
//   complete annotation JSON compared case by case.
// * [replayGrammarV2]: the sealed grammar v2 panel plus the 977-sentence clean
//   corpus (schema `quds.spacy.grammar.v2.evaluation.v1`), the five evaluated
//   families, annotation digests compared case by case. The row loop and the
//   per-family summary are those of `evaluate_grammar_v2.dart` (kept
//   unchanged there because it is part of the consumed v2 seal).
//
// The scorer functions (arm/summarize/finding) are the unchanged W6 ones.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy_grammar.dart';

import 'evaluate_grammar.dart' as scoring;

/// Replays a consumed W6/W7 panel on [transport] and fills [report]
/// (schema `quds.spacy.grammar.cross-binary-replay.v1`). Rows are added to
/// `report['rows']` as they complete, so a failure keeps them.
Future<void> replayConsumedPanel(
  Map<String, Object?> report, {
  required List<int> panelBytes,
  required List<int> recordedBytes,
  required String documentId,
  required String configurationId,
  required SpacyTransport transport,
  required String librarySha256,
  required int libraryBytes,
  required String host,
  required String dartVersion,
}) async {
  final panel = jsonDecode(utf8.decode(panelBytes)) as Map<String, dynamic>;
  final recorded =
      jsonDecode(utf8.decode(recordedBytes)) as Map<String, dynamic>;
  scoring.require(
    panel['schema'] == 'quds.spacy.grammar.panel.v1' &&
        recorded['schema'] == 'quds.spacy.grammar.evaluation.v1' &&
        recorded['panel_sha256'] == scoring.digest(panelBytes) &&
        recorded['completed'] == true,
    'The retained result does not belong to this panel.',
  );
  final cases = (panel['cases'] as List).cast<Map<String, dynamic>>();
  final originalRows = (recorded['cases'] as List).cast<Map<String, dynamic>>();
  scoring.require(
    cases.length == originalRows.length &&
        [
          for (var i = 0; i < cases.length; i++)
            cases[i]['id'] == originalRows[i]['id'] &&
                cases[i]['text'] == originalRows[i]['text'],
        ].every((ok) => ok),
    'Panel and retained rows differ in order or text.',
  );
  final rows = <Map<String, Object?>>[];
  final differences = <Map<String, Object?>>[];
  report.addAll({
    'schema': 'quds.spacy.grammar.cross-binary-replay.v1',
    'scope':
        'Replay of an already consumed authored panel on another exact '
        'build; compares annotations and outcomes with the retained result. '
        'Not a new planner qualification and not population-level quality.',
    'started_at': DateTime.now().toUtc().toIso8601String(),
    'panel_sha256': scoring.digest(panelBytes),
    'recorded_result_sha256': scoring.digest(recordedBytes),
    'recorded_library_sha256': recorded['native_library_sha256'],
    'library_sha256': librarySha256,
    'library_bytes': libraryBytes,
    'document_id': documentId,
    'configuration_id': configurationId,
    'dart_version': dartVersion,
    'host': host,
    'completed': false,
    'passed': false,
    'identity': transport.identity.toJson(),
    'rows': rows,
  });
  final ordinary = OfficeProofingService(
    providers: [GermanWritingRulesProvider()],
  );
  final planner = SpacyGermanGrammarPlanner();
  try {
    for (var index = 0; index < cases.length; index++) {
      final item = cases[index];
      final original = originalRows[index];
      final request = _request(item, documentId);
      final baseline = await ordinary.check(request);
      final analysis = await transport.analyze(
        _analysis(request, configurationId),
      );
      final plan = await planner.plan(
        request,
        analysis,
        personalWords: (item['personal_words'] as List? ?? const [])
            .cast<String>()
            .toSet(),
      );
      final secondary = await OfficeProofingService(
        providers: [_Completed(plan.result)],
      ).check(request);
      final combined = mergeOfficeProofingReports(
        primary: baseline,
        secondary: secondary,
      );
      final expected = item['expected'] as String;
      final row = <String, Object?>{
        'id': item['id'],
        'kind': item['kind'],
        'analysis': analysis.toJson(),
        'decisions': plan.decisions.map((d) => d.toJson()).toList(),
        'baseline': scoring.arm(baseline, expected),
        'model': scoring.arm(secondary, expected),
        'combined': scoring.arm(combined, expected),
        'model_proposals_suppressed_by_merge':
            secondary.findings.length -
            combined.findings
                .where((f) => f.providerId == plan.result.providerId)
                .length,
      };
      final unsupported = item['kind'] == 'unsupported';
      row['operational_ok'] =
          !baseline.results.any(
            (r) =>
                r.status == OfficeProofingStatus.failed ||
                r.status == OfficeProofingStatus.unavailable,
          ) &&
          (unsupported
              ? analysis.status == LinguisticAnalysisStatus.unsupported &&
                    secondary.results.single.status ==
                        OfficeProofingStatus.unsupported
              : analysis.isSuccess && secondary.complete);
      final combinedArm = row['combined']! as Map<String, Object?>;
      if (item['kind'] == 'error' && combinedArm['exact'] == true) {
        final corrected = _request({
          ...item,
          'text': combinedArm['output'],
        }, documentId);
        final reanalysis = await transport.analyze(
          _analysis(corrected, configurationId),
        );
        final replan = await planner.plan(corrected, reanalysis);
        row['corrected_recheck'] = {
          'analysis_status': reanalysis.status.name,
          'status': replan.result.status.name,
          'findings': replan.result.findings.map(scoring.finding).toList(),
          'decisions': replan.decisions.map((d) => d.toJson()).toList(),
          'annotations': reanalysis.toJson(),
        };
      }
      rows.add(row);
      differences.addAll(_compareConsumed(original, row, librarySha256));
    }
  } finally {
    await ordinary.dispose();
  }
  final summary = scoring.summarize(rows);
  final recordedSummary = recorded['summary'] as Map<String, dynamic>;
  final summaryDifferences = {
    for (final key in {...summary.keys, ...recordedSummary.keys})
      if (summary[key] != recordedSummary[key])
        key: {'recorded': recordedSummary[key], 'replay': summary[key]},
  };
  report['completed'] = rows.length == cases.length;
  report['summary'] = summary;
  report['recorded_summary'] = recordedSummary;
  report['summary_differences'] = summaryDifferences;
  report['case_differences'] = differences;
  report['cases_compared'] = rows.length;
  report['annotations_compared'] =
      rows.length +
      rows.where((r) => r.containsKey('corrected_recheck')).length;
  report['passed'] =
      report['completed'] == true &&
      differences.isEmpty &&
      summaryDifferences.isEmpty;
  // Keep `rows` last in the serialized report, as before.
  report['rows'] = report.remove('rows');
}

OfficeProofingRequest _request(Map<String, dynamic> item, String documentId) =>
    OfficeProofingRequest(
      documentId: documentId,
      blockId: item['id'] as String,
      revision: 1,
      text: item['text'] as String,
      language: item['locale'] as String,
      startOffset: item['start_offset'] as int,
      ignoredRuleIds: (item['ignored_rule_ids'] as List? ?? const [])
          .cast<String>()
          .toSet(),
    );

LinguisticAnalysisRequest _analysis(
  OfficeProofingRequest request,
  String configurationId,
) => LinguisticAnalysisRequest(
  text: request.text,
  documentId: request.documentId,
  blockId: request.blockId,
  revision: request.revision,
  locale: request.language,
  startOffset: request.startOffset,
  configurationId: configurationId,
);

final class _Completed extends OfficeProofingProvider {
  _Completed(this.result);
  final OfficeProofingResult result;
  @override
  String get id => result.providerId;
  @override
  bool supportsLanguage(String language) => true;
  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async =>
      result;
}

/// Replaces the one field that names the build (and drops the host-bundled
/// code digest, which recorded results predate); everything else must match.
Object? _normalize(Object? value, String recordedLibrary, String library) {
  if (value is Map) {
    return {
      for (final entry in value.entries)
        if (entry.key != 'code_sha256')
          entry.key: entry.key == 'library_sha256' && entry.value == library
              ? recordedLibrary
              : _normalize(entry.value, recordedLibrary, library),
    };
  }
  if (value is List) {
    return [for (final v in value) _normalize(v, recordedLibrary, library)];
  }
  return value;
}

List<Map<String, Object?>> _compareConsumed(
  Map<String, dynamic> original,
  Map<String, Object?> replay,
  String library,
) {
  final recordedLibrary = (original['analysis'] as Map)['identity'] == null
      ? library
      : ((original['analysis'] as Map)['identity'] as Map)['library_sha256']
            as String;
  final normalized =
      jsonDecode(jsonEncode(_normalize(replay, recordedLibrary, library)))
          as Map<String, dynamic>;
  final result = <Map<String, Object?>>[];
  for (final field in [
    'analysis',
    'decisions',
    'baseline',
    'model',
    'combined',
    'model_proposals_suppressed_by_merge',
    'operational_ok',
    'corrected_recheck',
  ]) {
    final a = jsonEncode(original[field]);
    final b = jsonEncode(normalized[field]);
    if (a != b) {
      result.add({
        'id': original['id'],
        'field': field,
        'recorded_sha256': sha256.convert(utf8.encode(a)).toString(),
        'replay_sha256': sha256.convert(utf8.encode(b)).toString(),
      });
    }
  }
  return result;
}

// ---------------------------------------------------------------------------
// Grammar v2 (sealed per-family panel plus clean corpus).

const v2DocumentId = 'grammar-v2';
const v2ConfigurationId = 'grammar-v2-evaluation';
const v2EvaluatedFamilies = {
  SpacyGrammarFamily.nounVerb,
  SpacyGrammarFamily.nounPhraseAgreement,
  SpacyGrammarFamily.prepositionCase,
  SpacyGrammarFamily.subjectPerson,
  SpacyGrammarFamily.verbPosition,
};
const v2NewFamilies = [
  SpacyGrammarFamily.nounPhraseAgreement,
  SpacyGrammarFamily.prepositionCase,
  SpacyGrammarFamily.subjectPerson,
  SpacyGrammarFamily.verbPosition,
];

/// Replays the frozen grammar v2 panel and clean corpus on [transport] and
/// compares every row with the recorded qualification report
/// ([recordedBytes], the uncompressed `qualification-macos.json`). Fills
/// [report] (schema `quds.spacy.grammar.v2.cross-binary-replay.v1`).
///
/// [expectedSourceDifferences] lists `id/field` pairs that are known to
/// differ because the planner source changed after the sealed run (not the
/// library); they are reported separately and must match exactly. Every
/// annotation digest must equal the recorded one regardless.
Future<void> replayGrammarV2(
  Map<String, Object?> report, {
  required List<int> protocolBytes,
  required List<int> panelBytes,
  required List<int> corpusBytes,
  required List<int> recordedBytes,
  required SpacyTransport transport,
  required String librarySha256,
  required int libraryBytes,
  required String host,
  required String dartVersion,
  Set<String> expectedSourceDifferences = const {},
}) async {
  final protocol =
      jsonDecode(utf8.decode(protocolBytes)) as Map<String, dynamic>;
  final panel = jsonDecode(utf8.decode(panelBytes)) as Map<String, dynamic>;
  final corpus = jsonDecode(utf8.decode(corpusBytes)) as Map<String, dynamic>;
  final recorded =
      jsonDecode(utf8.decode(recordedBytes)) as Map<String, dynamic>;
  final panelSha = scoring.digest(panelBytes);
  final frozenPanel = protocol['qualification_panel'] as Map<String, dynamic>;
  final frozenCorpus = protocol['clean_corpus'] as Map<String, dynamic>;
  scoring.require(
    panel['split'] == 'qualification' &&
        frozenPanel['sha256'] == panelSha &&
        frozenCorpus['sha256'] == scoring.digest(corpusBytes),
    'Panel or clean corpus differ from the frozen protocol.',
  );
  scoring.require(
    recorded['schema'] == 'quds.spacy.grammar.v2.evaluation.v1' &&
        recorded['phase'] == 'qualification' &&
        recorded['panel_sha256'] == panelSha &&
        recorded['corpus_sha256'] == scoring.digest(corpusBytes) &&
        recorded['completed'] == true,
    'The recorded report does not belong to this frozen qualification.',
  );
  final cases = <Map<String, dynamic>>[
    ...(panel['cases'] as List).cast<Map<String, dynamic>>(),
    for (final sentence
        in (corpus['sentences'] as List).cast<Map<String, dynamic>>())
      {
        'id': 'corpus:${sentence['id']}',
        'kind': 'clean',
        'family': 'corpus',
        'locale': 'de-DE',
        'text': sentence['text'],
        'expected': sentence['text'],
        'start_offset': 23,
      },
  ];
  final ids = <String>{};
  for (final item in cases) {
    scoring.require(
      ids.add(item['id'] as String) &&
          const {
            'error',
            'valid',
            'guard',
            'unsupported',
            'clean',
          }.contains(item['kind']) &&
          item['text'] is String &&
          item['expected'] is String,
      'Duplicate or invalid case ${item['id']}.',
    );
  }
  final rows = <Map<String, Object?>>[];
  report.addAll({
    'schema': 'quds.spacy.grammar.v2.cross-binary-replay.v1',
    'scope':
        'Replay of the consumed grammar v2 panel and clean corpus on another '
        'exact build; compares annotations, decisions, arms and rechecks with '
        'the recorded qualification. Not a new qualification and not '
        'population-level German grammar quality.',
    'started_at': DateTime.now().toUtc().toIso8601String(),
    'protocol_sha256': scoring.digest(protocolBytes),
    'panel_sha256': panelSha,
    'corpus_sha256': scoring.digest(corpusBytes),
    'recorded_report_sha256': scoring.digest(recordedBytes),
    'recorded_library_sha256': recorded['native_library_sha256'],
    'native_library_sha256': librarySha256,
    'native_library_bytes': libraryBytes,
    'families': [for (final f in v2EvaluatedFamilies) f.id],
    'dart_version': dartVersion,
    'host': host,
    'completed': false,
    'passed': false,
    'identity': transport.identity.toJson(),
    'rows': rows,
  });
  final ordinary = OfficeProofingService(
    providers: [GermanWritingRulesProvider()],
  );
  const planner = SpacyGermanGrammarPlanner(families: v2EvaluatedFamilies);
  try {
    for (final item in cases) {
      final row = <String, Object?>{
        'id': item['id'],
        'kind': item['kind'],
        'family': item['family'],
        'text': item['text'],
        'expected': item['expected'],
      };
      rows.add(row);
      final request = _v2Request(item);
      final baseline = await ordinary.check(request);
      final analysis = await transport.analyze(_v2Analysis(request));
      final plan = await planner.plan(
        request,
        analysis,
        personalWords: (item['personal_words'] as List? ?? const [])
            .cast<String>()
            .toSet(),
      );
      final secondary = await OfficeProofingService(
        providers: [_Completed(plan.result)],
      ).check(request);
      final combined = mergeOfficeProofingReports(
        primary: baseline,
        secondary: secondary,
      );
      final expected = item['expected'] as String;
      final analysisJson = jsonEncode(
        _normalizeLibrary(analysis.toJson(), librarySha256),
      );
      row.addAll({
        if (item['kind'] != 'clean') 'analysis': analysis.toJson(),
        'analysis_sha256': scoring.digest(utf8.encode(analysisJson)),
        'decisions': plan.decisions.map((d) => d.toJson()).toList(),
        'baseline': scoring.arm(baseline, expected),
        'model': scoring.arm(secondary, expected),
        'combined': scoring.arm(combined, expected),
        'model_proposals_suppressed_by_merge':
            secondary.findings.length -
            combined.findings
                .where((f) => f.providerId == plan.result.providerId)
                .length,
      });
      final unsupported = item['kind'] == 'unsupported';
      row['operational_ok'] =
          !baseline.results.any(
            (r) =>
                r.status == OfficeProofingStatus.failed ||
                r.status == OfficeProofingStatus.unavailable,
          ) &&
          (unsupported
              ? analysis.status == LinguisticAnalysisStatus.unsupported &&
                    secondary.results.single.status ==
                        OfficeProofingStatus.unsupported
              : analysis.isSuccess && secondary.complete);
      final combinedArm = row['combined']! as Map<String, Object?>;
      if (item['kind'] == 'error' && combinedArm['exact'] == true) {
        final corrected = _v2Request({...item, 'text': combinedArm['output']});
        final reanalysis = await transport.analyze(_v2Analysis(corrected));
        final replan = await planner.plan(corrected, reanalysis);
        row['corrected_recheck'] = {
          'analysis_status': reanalysis.status.name,
          'status': replan.result.status.name,
          'findings': replan.result.findings.map(scoring.finding).toList(),
          'decisions': replan.decisions.map((d) => d.toJson()).toList(),
          'analysis_sha256': scoring.digest(
            utf8.encode(
              jsonEncode(_normalizeLibrary(reanalysis.toJson(), librarySha256)),
            ),
          ),
        };
        if (!reanalysis.isSuccess ||
            replan.result.status != OfficeProofingStatus.success) {
          row['operational_ok'] = false;
        }
      }
    }
  } finally {
    await ordinary.dispose();
  }
  report['completed'] = rows.length == cases.length;
  final perFamily = <String, Object?>{};
  final gates = <String, Map<String, bool>>{};
  for (final family in v2NewFamilies) {
    final familyRows = rows.where((r) => r['family'] == family.id).toList();
    final summary = <String, Object?>{...scoring.summarize(familyRows)};
    int ruleFindings(Map<String, Object?> row, String arm) =>
        ((row[arm] as Map<String, Object?>?)?['findings'] as List? ?? const [])
            .where((f) => (f as Map)['rule_id'] == family.ruleId)
            .length;
    final validFindings = rows
        .where((r) => r['kind'] == 'valid' && ruleFindings(r, 'model') > 0)
        .map((r) => r['id'])
        .toList();
    final guardFindings = rows
        .where((r) => r['kind'] == 'guard' && ruleFindings(r, 'model') > 0)
        .map((r) => r['id'])
        .toList();
    final cleanFindings = rows
        .where((r) => r['kind'] == 'clean' && ruleFindings(r, 'model') > 0)
        .map((r) => r['id'])
        .toList();
    final nonExact = rows
        .where(
          (r) =>
              r['kind'] == 'error' &&
              ruleFindings(r, 'model') > 0 &&
              (r['model'] as Map)['output'] != r['expected'],
        )
        .map((r) => r['id'])
        .toList();
    final ruleExact = familyRows
        .where(
          (r) =>
              r['kind'] == 'error' &&
              (r['model'] as Map)['exact'] == true &&
              ruleFindings(r, 'model') > 0,
        )
        .length;
    final errors = summary['error_cases']! as int;
    summary.addAll({
      'rule_id': family.ruleId,
      'native_exact_by_this_rule': ruleExact,
      'rule_findings_on_valid_rows': validFindings,
      'rule_findings_on_guard_rows': guardFindings,
      'rule_findings_on_clean_corpus': cleanFindings,
      'non_exact_rule_proposals_on_error_rows': nonExact,
      'recheck_rule_findings': familyRows.fold<int>(
        0,
        (n, r) =>
            n +
            (((r['corrected_recheck'] as Map?)?['findings'] as List?) ?? [])
                .where((f) => (f as Map)['rule_id'] == family.ruleId)
                .length,
      ),
    });
    perFamily[family.id] = summary;
    gates[family.id] = {
      'no_valid_findings': validFindings.isEmpty,
      'no_guard_findings': guardFindings.isEmpty,
      'clean_corpus_findings_zero_or_judged': cleanFindings.isEmpty,
      'native_exact_fraction': errors > 0 && ruleExact / errors >= 0.25,
      'additional_combined_exact':
          (summary['additional_exact_errors']! as int) >= 3,
      'no_baseline_loss': summary['baseline_exact_lost'] == 0,
      'non_exact_proposals': nonExact.length <= 2,
      'no_operational_failures': summary['operational_failures'] == 0,
      'clean_recheck': summary['recheck_rule_findings'] == 0,
    };
  }
  report['per_family'] = perFamily;
  report['gates'] = gates;
  report['overall_summary'] = scoring.summarize(
    rows.where((r) => r['kind'] != 'clean').toList(),
  );
  report['clean_corpus'] = {
    'sentences': rows.where((r) => r['kind'] == 'clean').length,
    'native_findings': [
      for (final r in rows.where((r) => r['kind'] == 'clean'))
        for (final f in ((r['model'] as Map)['findings'] as List))
          {'id': r['id'], 'text': r['text'], ...(f as Map<String, Object?>)},
    ],
    'baseline_flagged_sentences': rows
        .where(
          (r) =>
              r['kind'] == 'clean' &&
              ((r['baseline'] as Map)['findings'] as List).isNotEmpty,
        )
        .length,
    'operational_failures': rows
        .where((r) => r['kind'] == 'clean' && r['operational_ok'] != true)
        .length,
  };
  report['unsupported_ok'] = rows
      .where((r) => r['kind'] == 'unsupported')
      .every((r) => r['operational_ok'] == true);
  final differences = _compareV2(recorded, rows, librarySha256);
  final annotationDifferences = differences
      .where(
        (d) =>
            d['field'] == 'analysis_sha256' ||
            d['field'] == 'row_count' ||
            d['field'] == 'id' ||
            d['field'] == 'corrected_recheck.analysis_sha256',
      )
      .toList();
  final keys = {for (final d in differences) '${d['id']}/${d['field']}'};
  final unexpected = differences
      .where(
        (d) => !expectedSourceDifferences.contains('${d['id']}/${d['field']}'),
      )
      .toList();
  final missing = expectedSourceDifferences.difference(keys).toList()..sort();
  report['case_differences'] = differences;
  report['annotation_differences'] = annotationDifferences;
  report['expected_source_differences'] = expectedSourceDifferences.toList()
    ..sort();
  report['unexpected_differences'] = unexpected;
  report['missing_expected_differences'] = missing;
  report['cases_compared'] = rows.length;
  report['annotations_compared'] =
      rows.length +
      rows.where((r) => r.containsKey('corrected_recheck')).length;
  report['passed'] =
      report['completed'] == true &&
      annotationDifferences.isEmpty &&
      unexpected.isEmpty &&
      missing.isEmpty;
  report['rows'] = report.remove('rows');
}

OfficeProofingRequest _v2Request(Map<String, dynamic> item) =>
    OfficeProofingRequest(
      documentId: v2DocumentId,
      blockId: item['id'] as String,
      revision: 1,
      text: item['text'] as String,
      language: (item['locale'] as String?) ?? 'de-DE',
      startOffset: (item['start_offset'] as int?) ?? 23,
      ignoredRuleIds: (item['ignored_rule_ids'] as List? ?? const [])
          .cast<String>()
          .toSet(),
    );

LinguisticAnalysisRequest _v2Analysis(OfficeProofingRequest request) =>
    LinguisticAnalysisRequest(
      text: request.text,
      documentId: request.documentId,
      blockId: request.blockId,
      revision: request.revision,
      locale: request.language,
      startOffset: request.startOffset,
      configurationId: v2ConfigurationId,
    );

/// Replaces the build digest so annotations of two exact builds compare, and
/// drops the host-bundled Mach-O code digest (absent on ELF and in the
/// recorded v2 report, which predates it), as [_normalize] does for W6/W7.
Object? _normalizeLibrary(Object? value, String library) {
  if (value is Map) {
    return {
      for (final entry in value.entries)
        if (entry.key != 'code_sha256')
          entry.key: entry.key == 'library_sha256' && entry.value == library
              ? '<LIBRARY>'
              : _normalizeLibrary(entry.value, library),
    };
  }
  if (value is List) {
    return [for (final v in value) _normalizeLibrary(v, library)];
  }
  return value;
}

List<Map<String, Object?>> _compareV2(
  Map<String, dynamic> recorded,
  List<Map<String, Object?>> rows,
  String library,
) {
  final originals = (recorded['rows'] as List).cast<Map<String, dynamic>>();
  final recordedLibrary = recorded['native_library_sha256'] as String;
  final result = <Map<String, Object?>>[];
  if (originals.length != rows.length) {
    result.add({
      'field': 'row_count',
      'recorded': originals.length,
      'replay': rows.length,
    });
    return result;
  }
  for (var i = 0; i < rows.length; i++) {
    final a = originals[i];
    final b = jsonDecode(jsonEncode(rows[i])) as Map<String, dynamic>;
    if (a['id'] != b['id']) {
      result.add({'index': i, 'field': 'id'});
      continue;
    }
    for (final field in [
      'analysis_sha256',
      'decisions',
      'baseline',
      'model',
      'combined',
      'model_proposals_suppressed_by_merge',
      'operational_ok',
      'corrected_recheck',
    ]) {
      final left = jsonEncode(_normalizeLibrary(a[field], recordedLibrary));
      final right = jsonEncode(_normalizeLibrary(b[field], library));
      if (left != right) {
        result.add({
          'id': a['id'],
          'field': field,
          'recorded_sha256': scoring.digest(utf8.encode(left)),
          'replay_sha256': scoring.digest(utf8.encode(right)),
        });
      }
    }
    // The recheck annotation digest is library-dependent: report it on its
    // own so a planner-only change can never hide an annotation difference.
    final ra = (a['corrected_recheck'] as Map?)?['analysis_sha256'];
    final rb = (b['corrected_recheck'] as Map?)?['analysis_sha256'];
    if (ra != null && rb != null && ra != rb) {
      result.add({
        'id': a['id'],
        'field': 'corrected_recheck.analysis_sha256',
        'recorded_sha256': ra,
        'replay_sha256': rb,
      });
    }
  }
  return result;
}
