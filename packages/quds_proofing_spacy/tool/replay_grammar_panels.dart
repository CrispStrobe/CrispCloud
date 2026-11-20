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
// only if the replay matches. Missing assets fail; nothing is skipped. The
// case loop and comparison are in grammar_replay_core.dart, shared with the
// on-device mobile replay (Studio integration_test/
// mobile_spacy_grammar_replay_test.dart).
//
//   dart run packages/quds_proofing_spacy/tool/replay_grammar_panels.dart \
//     --panel <panel.json> --recorded <original result.json> \
//     --document-id w6-grammar --configuration-id w6-frozen-grammar-evaluation \
//     --library <libcrispembed-spacy.dylib> --library-sha256 <hex> \
//     --bundle <German bundle dir> --report <new report.json>
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:quds_proofing_spacy/quds_proofing_spacy_grammar.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy_native.dart';

import 'evaluate_grammar.dart' as scoring;
import 'grammar_replay_core.dart';

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
    spacyGrammarNativeSha256s.contains(librarySha) ||
        spacyGrammarCodeSha256s.contains(machOCodeSha256(libraryBytes)),
    'The planner refuses this build; list it before replaying.',
  );
  final panelBytes = File(options['--panel']!).readAsBytesSync();
  final recordedBytes = File(options['--recorded']!).readAsBytesSync();
  final report = <String, Object?>{'completed': false, 'passed': false};
  SpacyTransport? transport;
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
    await replayConsumedPanel(
      report,
      panelBytes: panelBytes,
      recordedBytes: recordedBytes,
      documentId: options['--document-id']!,
      configurationId: options['--configuration-id']!,
      transport: transport,
      librarySha256: librarySha,
      libraryBytes: libraryBytes.length,
      host: '${Platform.operatingSystem} ${Abi.current()}',
      dartVersion: Platform.version.split(' ').first,
    );
  } on Object catch (error) {
    report['failure'] = error
        .toString()
        .replaceAll(File(libraryPath).absolute.path, '<NATIVE_LIBRARY>')
        .replaceAll(Directory(options['--bundle']!).absolute.path, '<BUNDLE>');
    rethrow;
  } finally {
    await transport?.dispose();
    report['rows'] = report.remove('rows') ?? const [];
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
        'case_differences': (report['case_differences'] as List?)?.length,
        'summary_differences': report['summary_differences'],
      }),
    );
    if (report['passed'] != true) exitCode = 1;
  }
}
