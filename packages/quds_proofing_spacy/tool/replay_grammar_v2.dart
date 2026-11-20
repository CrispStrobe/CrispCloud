// Cross-binary replay of the consumed grammar v2 panel and clean corpus on
// one exact desktop library (the row loop is grammar_replay_core.dart, the
// same code the on-device mobile replay runs). Not a new qualification.
//
// Every annotation digest must equal the recorded qualification. Planner
// outcomes must equal it too, except the `id/field` pairs passed with
// --expected-source-differences (a JSON list): rows that differ because the
// planner source changed after the sealed run, measured on a qualified
// library first so the same list then binds every other build.
//
//   dart run packages/quds_proofing_spacy/tool/replay_grammar_v2.dart \
//     --protocol docs/validation/native-spacy-grammar-v2-20261120/protocol.json \
//     --panel <qualification-panel.json> --corpus <clean-corpus-gsd-test.json> \
//     --recorded <uncompressed qualification-macos.json> \
//     --library <lib> --library-sha256 <hex> --bundle <German bundle dir> \
//     --report <new report.json> [--expected-source-differences <list.json>]
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
    '--protocol',
    '--panel',
    '--corpus',
    '--recorded',
    '--library',
    '--library-sha256',
    '--bundle',
    '--report',
  };
  scoring.require(
    required.every(options.containsKey) &&
        options.keys.every(
          (k) => required.contains(k) || k == '--expected-source-differences',
        ),
    'Required: ${required.join(', ')}; optional '
    '--expected-source-differences.',
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
  final expected = options.containsKey('--expected-source-differences')
      ? {
          ...(jsonDecode(
                    File(
                      options['--expected-source-differences']!,
                    ).readAsStringSync(),
                  )
                  as List)
              .cast<String>(),
        }
      : <String>{};
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
    await replayGrammarV2(
      report,
      protocolBytes: File(options['--protocol']!).readAsBytesSync(),
      panelBytes: File(options['--panel']!).readAsBytesSync(),
      corpusBytes: File(options['--corpus']!).readAsBytesSync(),
      recordedBytes: File(options['--recorded']!).readAsBytesSync(),
      transport: transport,
      librarySha256: librarySha,
      libraryBytes: libraryBytes.length,
      host: '${Platform.operatingSystem} ${Abi.current()}',
      dartVersion: Platform.version.split(' ').first,
      expectedSourceDifferences: expected,
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
      const JsonEncoder.withIndent('  ').convert({
        'completed': report['completed'],
        'passed': report['passed'],
        'annotation_differences':
            (report['annotation_differences'] as List?)?.length,
        'case_differences': [
          for (final d in (report['case_differences'] as List?) ?? const [])
            '${(d as Map)['id']}/${d['field']}',
        ],
        'unexpected_differences':
            (report['unexpected_differences'] as List?)?.length,
        'missing_expected_differences': report['missing_expected_differences'],
        'clean_native_findings':
            ((report['clean_corpus'] as Map?)?['native_findings'] as List?)
                ?.length,
      }),
    );
    if (report['passed'] != true) exitCode = 1;
  }
}
