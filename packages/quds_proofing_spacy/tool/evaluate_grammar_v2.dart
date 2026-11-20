// Grammar v2 evaluation: sealed per-family panel plus clean-text corpus.
//
// Phases:
//   development    any authored panel (and optional corpus); no seal.
//   qualification  the frozen v2 panel and corpus; requires a source seal and
//                  writes an exclusive consumed claim. Run exactly once.
//   replay         reruns the same frozen inputs on another exact library and
//                  compares annotations, decisions, arms and rechecks case by
//                  case with --recorded (only identity.library_sha256 may
//                  differ). Not a new qualification.
//
//   CRISPEMBED_SPACY=1 dart run packages/quds_proofing_spacy/tool/evaluate_grammar_v2.dart \
//     --root . --phase development --panel <panel.json> [--corpus <corpus.json>] \
//     --library <lib> --library-sha256 <hex> --bundle <dir> --report <new.json>
//
// The scorer functions (arm/summarize/finding) are the unchanged W6 ones.
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy_grammar.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy_native.dart';

import 'evaluate_grammar.dart' as scoring;

const protocolPath =
    'docs/validation/native-spacy-grammar-v2-20261120/protocol.json';
const documentId = 'grammar-v2';
const configurationId = 'grammar-v2-evaluation';
const evaluatedFamilies = {
  SpacyGrammarFamily.nounVerb,
  SpacyGrammarFamily.nounPhraseAgreement,
  SpacyGrammarFamily.prepositionCase,
  SpacyGrammarFamily.subjectPerson,
  SpacyGrammarFamily.verbPosition,
};
const newFamilies = [
  SpacyGrammarFamily.nounPhraseAgreement,
  SpacyGrammarFamily.prepositionCase,
  SpacyGrammarFamily.subjectPerson,
  SpacyGrammarFamily.verbPosition,
];

Future<void> main(List<String> arguments) async {
  final options = <String, String>{};
  for (var i = 0; i < arguments.length; i += 2) {
    if (i + 1 >= arguments.length ||
        !arguments[i].startsWith('--') ||
        options.containsKey(arguments[i])) {
      throw ArgumentError('Expected unique --name value pairs.');
    }
    options[arguments[i]] = arguments[i + 1];
  }
  const required = {
    '--root',
    '--phase',
    '--panel',
    '--library',
    '--library-sha256',
    '--bundle',
    '--report',
  };
  const optional = {'--corpus', '--seal', '--recorded', '--verbose'};
  scoring.require(
    required.every(options.containsKey) &&
        options.keys.every((k) => required.contains(k) || optional.contains(k)),
    'Required: ${required.join(', ')}; optional ${optional.join(', ')}.',
  );
  final phase = options['--phase']!;
  scoring.require(
    const {'development', 'qualification', 'replay'}.contains(phase),
    'Invalid phase.',
  );
  final verbose = options['--verbose'] == 'true';
  final root = Directory(options['--root']!).absolute.path;
  final output = File(options['--report']!);
  scoring.require(!output.existsSync(), 'Report exists; use a fresh path.');
  final librarySha = options['--library-sha256']!;
  final libraryBytes = File(options['--library']!).readAsBytesSync();
  scoring.require(
    scoring.digest(libraryBytes) == librarySha,
    'Library bytes differ from --library-sha256.',
  );
  final panelBytes = File(options['--panel']!).readAsBytesSync();
  final panel = jsonDecode(utf8.decode(panelBytes)) as Map<String, dynamic>;
  final corpusBytes = options.containsKey('--corpus')
      ? File(options['--corpus']!).readAsBytesSync()
      : null;
  final corpus = corpusBytes == null
      ? null
      : jsonDecode(utf8.decode(corpusBytes)) as Map<String, dynamic>;
  final panelSha = scoring.digest(panelBytes);
  final before = sourceHashes(root);
  Map<String, dynamic>? recorded;
  if (phase != 'development') {
    final protocol =
        jsonDecode(File('$root/$protocolPath').readAsStringSync())
            as Map<String, dynamic>;
    final frozenPanel = protocol['qualification_panel'] as Map<String, dynamic>;
    final frozenCorpus = protocol['clean_corpus'] as Map<String, dynamic>;
    scoring.require(
      panel['split'] == 'qualification' &&
          frozenPanel['sha256'] == panelSha &&
          corpusBytes != null &&
          frozenCorpus['sha256'] == scoring.digest(corpusBytes),
      'Panel or clean corpus differ from the frozen protocol.',
    );
  }
  Map<String, dynamic>? seal;
  if (phase == 'qualification') {
    scoring.require(
      options.containsKey('--seal'),
      'Qualification needs a seal.',
    );
    seal =
        jsonDecode(File(options['--seal']!).readAsStringSync())
            as Map<String, dynamic>;
    scoring.require(
      seal['schema'] == 'quds.spacy.grammar.v2.candidate-seal.v1' &&
          seal['qualification_panel_sha256'] == panelSha &&
          seal['native_library_sha256'] == librarySha &&
          scoring.equalMap(
            before,
            seal['source_sha256'] as Map<String, dynamic>,
          ),
      'Candidate, panel, library or source seal changed before qualification.',
    );
  }
  if (phase == 'replay') {
    scoring.require(
      options.containsKey('--recorded'),
      'Replay needs --recorded.',
    );
    recorded =
        jsonDecode(File(options['--recorded']!).readAsStringSync())
            as Map<String, dynamic>;
    scoring.require(
      recorded['schema'] == 'quds.spacy.grammar.v2.evaluation.v1' &&
          recorded['phase'] == 'qualification' &&
          recorded['panel_sha256'] == panelSha &&
          recorded['completed'] == true,
      'The recorded report does not belong to this frozen qualification.',
    );
    final recordedSources =
        recorded['source_sha256_before'] as Map<String, dynamic>;
    final drift = [
      for (final key in {...before.keys, ...recordedSources.keys})
        if (before[key] != recordedSources[key]) key,
    ];
    scoring.require(
      drift.every((path) => !_plannerSource(path)),
      'Planner/engine sources differ from the recorded qualification: $drift',
    );
  }

  final cases = <Map<String, dynamic>>[
    ...(panel['cases'] as List).cast<Map<String, dynamic>>(),
    if (corpus != null)
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
  final report = <String, Object?>{
    'schema': 'quds.spacy.grammar.v2.evaluation.v1',
    'phase': phase,
    'scope':
        'Authored finite per-family comparison plus one clean-text corpus; not '
        'population-level German grammar quality.',
    'started_at': DateTime.now().toUtc().toIso8601String(),
    'panel_sha256': panelSha,
    'corpus_sha256': corpusBytes == null ? null : scoring.digest(corpusBytes),
    'candidate_seal_sha256': options.containsKey('--seal')
        ? scoring.digest(File(options['--seal']!).readAsBytesSync())
        : null,
    'recorded_report_sha256': options.containsKey('--recorded')
        ? scoring.digest(File(options['--recorded']!).readAsBytesSync())
        : null,
    'source_sha256_before': before,
    'native_library_sha256': librarySha,
    'native_library_bytes': libraryBytes.length,
    'families': [for (final f in evaluatedFamilies) f.id],
    'dart_version': Platform.version.split(' ').first,
    'host': '${Platform.operatingSystem} ${Abi.current()}',
    'completed': false,
    'passed': false,
  };
  final rows = <Map<String, Object?>>[];
  output.parent.createSync(recursive: true);
  output.createSync(exclusive: true);
  scoring.writeReport(output, report);
  if (phase == 'qualification') {
    final claim = File('${options['--seal']!}.consumed.json');
    claim.createSync(exclusive: true);
    claim.writeAsStringSync(
      '${jsonEncode({'schema': 'quds.spacy.grammar.v2.qualification.claim.v1', 'candidate_seal_sha256': report['candidate_seal_sha256'], 'panel_sha256': panelSha, 'started_at': report['started_at'], 'policy': 'This sealed qualification has been started; never overwrite or rerun it.'})}\n',
      flush: true,
    );
    report['qualification_claim_sha256'] = scoring.digest(
      claim.readAsBytesSync(),
    );
  }
  SpacyTransport? transport;
  final ordinary = OfficeProofingService(
    providers: [GermanWritingRulesProvider()],
  );
  const planner = SpacyGermanGrammarPlanner(families: evaluatedFamilies);
  try {
    transport = await startSpacyWorker(
      bundle: const SpacyBundle.germanF32(),
      backendFactory: SpacyNativeBackendFactory(
        bundleDirectory: options['--bundle']!,
        libraryPath: options['--library']!,
        librarySha256: librarySha,
        hostBundled: true,
      ),
    );
    report['identity'] = transport.identity.toJson();
    for (final item in cases) {
      final row = <String, Object?>{
        'id': item['id'],
        'kind': item['kind'],
        'family': item['family'],
        'text': item['text'],
        'expected': item['expected'],
      };
      rows.add(row);
      final request = _request(item);
      final baseline = await ordinary.check(request);
      final analysis = await transport.analyze(_analysis(request));
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
        _normalizeLibrary(analysis.toJson(), librarySha),
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
        final corrected = _request({...item, 'text': combinedArm['output']});
        final reanalysis = await transport.analyze(_analysis(corrected));
        final replan = await planner.plan(corrected, reanalysis);
        row['corrected_recheck'] = {
          'analysis_status': reanalysis.status.name,
          'status': replan.result.status.name,
          'findings': replan.result.findings.map(scoring.finding).toList(),
          'decisions': replan.decisions.map((d) => d.toJson()).toList(),
          'analysis_sha256': scoring.digest(
            utf8.encode(
              jsonEncode(_normalizeLibrary(reanalysis.toJson(), librarySha)),
            ),
          ),
        };
        if (!reanalysis.isSuccess ||
            replan.result.status != OfficeProofingStatus.success) {
          row['operational_ok'] = false;
        }
      }
      if (verbose) _print(row);
    }
    report['completed'] = rows.length == cases.length;
    final perFamily = <String, Object?>{};
    final gates = <String, Map<String, bool>>{};
    for (final family in newFamilies) {
      final familyRows = rows.where((r) => r['family'] == family.id).toList();
      final summary = <String, Object?>{...scoring.summarize(familyRows)};
      int ruleFindings(Map<String, Object?> row, String arm) =>
          ((row[arm] as Map<String, Object?>?)?['findings'] as List? ??
                  const [])
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
    if (recorded != null) {
      final differences = _compare(recorded, rows, librarySha);
      report['case_differences'] = differences;
      report['cases_compared'] = rows.length;
      report['passed'] = report['completed'] == true && differences.isEmpty;
    } else {
      report['passed'] =
          report['completed'] == true &&
          report['unsupported_ok'] == true &&
          gates.values.every((g) => g.values.every((v) => v));
    }
  } on Object catch (error) {
    report['failure'] = error
        .toString()
        .replaceAll(root, '<QUDS_ROOT>')
        .replaceAll(Directory(options['--bundle']!).absolute.path, '<BUNDLE>')
        .replaceAll(
          File(options['--library']!).absolute.path,
          '<NATIVE_LIBRARY>',
        );
    rethrow;
  } finally {
    await transport?.dispose();
    await ordinary.dispose();
    final after = sourceHashes(root);
    report['source_unchanged'] = scoring.equalMap(before, after);
    if (report['source_unchanged'] != true) report['passed'] = false;
    report['rows'] = rows;
    report['finished_at'] = DateTime.now().toUtc().toIso8601String();
    scoring.writeReport(output, report);
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'phase': phase,
        'completed': report['completed'],
        'passed': report['passed'],
        'gates': report['gates'],
        'per_family': {
          for (final e in ((report['per_family'] as Map?) ?? {}).entries)
            e.key: {
              for (final k in [
                'baseline_exact_errors',
                'model_exact_errors',
                'native_exact_by_this_rule',
                'combined_exact_errors',
                'additional_exact_errors',
                'rule_findings_on_valid_rows',
                'rule_findings_on_guard_rows',
                'rule_findings_on_clean_corpus',
                'non_exact_rule_proposals_on_error_rows',
              ])
                k: (e.value as Map)[k],
            },
        },
        'clean_native_findings':
            ((report['clean_corpus'] as Map?)?['native_findings'] as List?)
                ?.length,
        'case_differences': (report['case_differences'] as List?)?.length,
      }),
    );
    if (report['passed'] != true) exitCode = 1;
  }
}

bool _plannerSource(String path) =>
    path.startsWith('packages/quds_office_engine/lib/src/proofing/') ||
    path.startsWith('packages/quds_proofing_spacy/lib/src/grammar') ||
    path.endsWith('/evaluate_grammar_v2.dart') ||
    path.endsWith('/evaluate_grammar.dart');

void _print(Map<String, Object?> row) {
  String fs(String arm) => [
    for (final f in ((row[arm] as Map)['findings'] as List))
      '${(f as Map)['rule_id']}:${f['original']}->${f['replacements']}',
  ].join(' ; ');
  final model = fs('model');
  final base = fs('baseline');
  final exact = (row['model'] as Map)['exact'] == true ? 'EXACT' : '';
  stdout.writeln(
    '[${row['kind']}/${row['family']}] ${row['id']}: ${row['text']}\n'
    '    native: $model $exact\n    base: $base',
  );
  if (row['kind'] == 'error' && exact.isEmpty) {
    for (final d in (row['decisions'] as List)) {
      final m = d as Map;
      if (m['action'] != 'abstained' && m['action'] != 'proposed') continue;
      stdout.writeln(
        '    - ${(m['evidence'] as Map)['family'] ?? 'noun-verb'} ${m['action']} ${m['reason']}',
      );
    }
  }
}

OfficeProofingRequest _request(Map<String, dynamic> item) =>
    OfficeProofingRequest(
      documentId: documentId,
      blockId: item['id'] as String,
      revision: 1,
      text: item['text'] as String,
      language: (item['locale'] as String?) ?? 'de-DE',
      startOffset: (item['start_offset'] as int?) ?? 23,
      ignoredRuleIds: (item['ignored_rule_ids'] as List? ?? const [])
          .cast<String>()
          .toSet(),
    );

LinguisticAnalysisRequest _analysis(OfficeProofingRequest request) =>
    LinguisticAnalysisRequest(
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

/// Replaces the build digest so annotations of two exact builds compare.
Object? _normalizeLibrary(Object? value, String library) {
  if (value is Map) {
    return {
      for (final entry in value.entries)
        entry.key: entry.key == 'library_sha256' && entry.value == library
            ? '<LIBRARY>'
            : _normalizeLibrary(entry.value, library),
    };
  }
  if (value is List)
    return [for (final v in value) _normalizeLibrary(v, library)];
  return value;
}

List<Map<String, Object?>> _compare(
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
  }
  return result;
}

Map<String, String> sourceHashes(String root) {
  final paths = <String>{
    'pubspec.yaml',
    'packages/quds_office_engine/pubspec.yaml',
    'packages/quds_proofing_spacy/pubspec.yaml',
    'packages/quds_proofing_spacy/tool/evaluate_grammar.dart',
    'packages/quds_proofing_spacy/tool/evaluate_grammar_v2.dart',
    protocolPath,
  };
  for (final prefix in [
    'packages/quds_office_engine/lib/src/proofing',
    'packages/quds_proofing_spacy/lib',
  ]) {
    for (final entity in Directory(
      '$root/$prefix',
    ).listSync(recursive: true, followLinks: false)) {
      if (entity is File) paths.add(entity.path.substring(root.length + 1));
    }
  }
  return {
    for (final path in paths.toList()..sort())
      path: scoring.digest(File('$root/$path').readAsBytesSync()),
  };
}
