// Cross-binary replay of an already consumed grammar panel.
//
// This is not a new qualification of the planner. It answers one question:
// does another exact native build produce the same annotations, and therefore
// the same manual grammar outcome, as the build that consumed the panel?
// It reads the panel and the retained original result, runs every case (and
// every corrected recheck) through the given library with the unchanged
// scoring code of evaluate_grammar.dart, and compares case by case:
//
//   * the complete annotation JSON (tokens, tags, morphology, lemmas,
//     dependencies, sentences, entities) with only `identity.library_sha256`
//     allowed to differ;
//   * planner decisions and the baseline/native/combined arms;
//   * the corrected-text recheck annotations and findings;
//   * the summary counts.
//
// The planner only accepts builds listed in `spacyGrammarNativeSha256s`, so the
// candidate digest must be listed while this replay runs; it is kept there
// only if the replay matches. Missing assets fail; nothing is skipped.
//
//   dart run packages/quds_proofing_spacy/tool/replay_grammar_panels.dart \
//     --panel <panel.json> --recorded <original result.json> \
//     --document-id w6-grammar --configuration-id w6-frozen-grammar-evaluation \
//     --library <libcrispembed-spacy.dylib> --library-sha256 <hex> \
//     --bundle <German bundle dir> --report <new report.json>
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy_grammar.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy_native.dart';

import 'evaluate_grammar.dart' as scoring;

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
    '--panel',
    '--recorded',
    '--document-id',
    '--configuration-id',
    '--library',
    '--library-sha256',
    '--bundle',
    '--report',
  };
  scoring.require(
    options.keys.toSet().containsAll(required) &&
        options.length == required.length,
    'Required: ${required.join(', ')}.',
  );
  final output = File(options['--report']!);
  scoring.require(!output.existsSync(), 'Report exists; use a fresh path.');
  final libraryPath = options['--library']!;
  final librarySha = options['--library-sha256']!;
  final libraryBytes = File(libraryPath).readAsBytesSync();
  scoring.require(
    scoring.digest(libraryBytes) == librarySha,
    'Library bytes differ from --library-sha256.',
  );
  scoring.require(
    spacyGrammarNativeSha256s.contains(librarySha),
    'The planner refuses this build; list it before replaying.',
  );
  final panelBytes = File(options['--panel']!).readAsBytesSync();
  final recordedBytes = File(options['--recorded']!).readAsBytesSync();
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
  final documentId = options['--document-id']!;
  final configurationId = options['--configuration-id']!;
  final report = <String, Object?>{
    'schema': 'quds.spacy.grammar.cross-binary-replay.v1',
    'scope':
        'Replay of an already consumed authored panel on another exact '
        'build; compares annotations and outcomes with the retained result. '
        'Not a new planner qualification and not population-level quality.',
    'started_at': DateTime.now().toUtc().toIso8601String(),
    'panel_sha256': scoring.digest(panelBytes),
    'recorded_result_sha256': scoring.digest(recordedBytes),
    'recorded_library_sha256': recorded['native_library_sha256'],
    'library_sha256': librarySha,
    'library_bytes': libraryBytes.length,
    'document_id': documentId,
    'configuration_id': configurationId,
    'dart_version': Platform.version.split(' ').first,
    'host': '${Platform.operatingSystem} ${Abi.current()}',
    'completed': false,
    'passed': false,
  };
  final rows = <Map<String, Object?>>[];
  final differences = <Map<String, Object?>>[];
  SpacyTransport? transport;
  final ordinary = OfficeProofingService(
    providers: [GermanWritingRulesProvider()],
  );
  final planner = SpacyGermanGrammarPlanner();
  try {
    transport = await startSpacyWorker(
      bundle: const SpacyBundle.germanF32(),
      backendFactory: SpacyNativeBackendFactory(
        bundleDirectory: options['--bundle']!,
        libraryPath: libraryPath,
        librarySha256: librarySha,
        hostBundled: true,
      ),
    );
    report['identity'] = transport.identity.toJson();
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
      differences.addAll(_compare(original, row, librarySha));
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
  } on Object catch (error) {
    report['failure'] = error
        .toString()
        .replaceAll(File(libraryPath).absolute.path, '<NATIVE_LIBRARY>')
        .replaceAll(Directory(options['--bundle']!).absolute.path, '<BUNDLE>');
    rethrow;
  } finally {
    await transport?.dispose();
    await ordinary.dispose();
    report['rows'] = rows;
    report['finished_at'] = DateTime.now().toUtc().toIso8601String();
    output.parent.createSync(recursive: true);
    output.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      flush: true,
    );
    stdout.writeln(
      jsonEncode({
        'completed': report['completed'],
        'passed': report['passed'],
        'summary': report['summary'],
        'case_differences': differences.length,
        'summary_differences': report['summary_differences'],
      }),
    );
    if (report['passed'] != true) exitCode = 1;
  }
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

/// Replaces the one field that names the build; everything else must match.
Object? _normalize(Object? value, String recordedLibrary, String library) {
  if (value is Map) {
    return {
      for (final entry in value.entries)
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

List<Map<String, Object?>> _compare(
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
