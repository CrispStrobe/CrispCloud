// Non-native controls for receipts, source guards and the comparison scorer.
// The temporary panel below is empty and synthetic; no real qualification
// panel, accepted native library or model bundle is read by these tests.
import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/evaluate_grammar.dart' as harness;

void main() {
  late Directory temporary;
  setUp(() {
    temporary = Directory.current.createTempSync('harness-control-');
  });
  tearDown(() {
    temporary.deleteSync(recursive: true);
  });

  test(
    'existing receipt rejects admission before reading missing assets',
    () async {
      final output = File('${temporary.path}/receipt.json')
        ..writeAsStringSync('{"retained":true}\n');
      final original = output.readAsBytesSync();
      await expectLater(
        harness.main(_arguments(temporary, output)),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Receipt already exists'),
          ),
        ),
      );
      expect(output.readAsBytesSync(), original);
      expect(File('${output.path}.next').existsSync(), isFalse);
    },
  );

  test(
    'checkpoint replacement preserves last complete report on pending collision',
    () {
      final output = File('${temporary.path}/receipt.json')
        ..createSync(exclusive: true);
      harness.writeReport(output, {'completed': false, 'text': 'Ä 😀'});
      expect(jsonDecode(output.readAsStringSync()), {
        'completed': false,
        'text': 'Ä 😀',
      });
      expect(File('${output.path}.next').existsSync(), isFalse);
      final original = output.readAsBytesSync();
      final pending = File('${output.path}.next')
        ..writeAsStringSync('retained interrupted checkpoint');
      expect(
        () => harness.writeReport(output, {'completed': true}),
        throwsA(isA<FileSystemException>()),
      );
      expect(output.readAsBytesSync(), original);
      expect(pending.readAsStringSync(), 'retained interrupted checkpoint');
    },
  );

  test(
    'baseline closure permits additive API but rejects lexical data and ZIP drift',
    () {
      final fixture = _baselineFixture(temporary);
      final provider = File('${temporary.path}/$_provider');
      provider.writeAsStringSync(
        "${provider.readAsStringSync()}part 'german_agreement_facts.dart';\n",
      );
      expect(harness.verifyBaseline(temporary.path, fixture), hasLength(3));

      for (final path in [_data, _zip]) {
        final file = File('${temporary.path}/$path');
        final original = file.readAsBytesSync();
        file.writeAsStringSync('changed source\n');
        expect(
          () => harness.verifyBaseline(temporary.path, fixture),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('Deterministic baseline closure changed: $path'),
            ),
          ),
        );
        file.writeAsBytesSync(original);
      }
      expect(harness.verifyBaseline(temporary.path, fixture), hasLength(3));
      provider.writeAsStringSync('changed ordinary provider\n');
      expect(
        () => harness.verifyBaseline(temporary.path, fixture),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Current deterministic source changed'),
          ),
        ),
      );
    },
  );

  test(
    'consumed synthetic seal blocks a new receipt before native entry',
    () async {
      final protocol = _baselineFixture(temporary);
      final panel = {
        'schema': 'quds.spacy.grammar.panel.v1',
        'split': 'qualification',
        'cases': <Object?>[],
      };
      final panelFile = _write(
        temporary,
        'missing-panel.json',
        jsonEncode(panel),
      );
      final panelHash = harness.digest(panelFile.readAsBytesSync());
      protocol['qualification_panel'] = {
        'sha256': panelHash,
        'total': 0,
        'counts': {'error': 0, 'valid': 0, 'guard': 0, 'unsupported': 0},
      };
      _write(temporary, harness.protocolPath, jsonEncode(protocol));
      for (final path in [
        'pubspec.yaml',
        'pubspec.lock',
        'packages/quds_office_engine/pubspec.yaml',
        'packages/quds_proofing_spacy/pubspec.yaml',
        'packages/quds_proofing_spacy/tool/evaluate_grammar.dart',
      ]) {
        _write(temporary, path, '// Synthetic source closure fixture.\n');
      }
      Directory(
        '${temporary.path}/packages/quds_proofing_spacy/lib',
      ).createSync(recursive: true);
      final seal = _write(
        temporary,
        'synthetic-seal.json',
        jsonEncode({
          'schema': 'quds.spacy.grammar.candidate.v1',
          'qualification_panel_sha256': panelHash,
          'native_library_sha256': harness.nativeSha,
          'source_sha256': harness.sourceHashes(temporary.path),
          'candidate_commit': 'synthetic-control-only',
        }),
      );
      final claim = File('${seal.path}.consumed.json')
        ..writeAsStringSync('{"prior_claim":"retain"}\n');
      final claimBytes = claim.readAsBytesSync();
      final output = File('${temporary.path}/new-receipt.json');
      await expectLater(
        harness.main([
          ..._arguments(temporary, output, phase: 'qualification'),
          '--seal',
          seal.path,
        ]),
        throwsA(isA<FileSystemException>()),
      );
      expect(claim.readAsBytesSync(), claimBytes);
      final pending = jsonDecode(output.readAsStringSync()) as Map;
      expect(pending['completed'], isFalse);
      expect(pending['passed'], isFalse);
      expect(pending.containsKey('identity'), isFalse);
      expect(pending['cases'], isEmpty);
      expect(File('${output.path}.next').existsSync(), isFalse);
    },
  );

  test('exact scorer maps nonzero UTF-16 origin after an emoji', () {
    final request = _request('😀 Die Katzen schläft.');
    final start = request.text.indexOf('schläft');
    final score = harness.arm(
      _report(request, [
        _finding(request, start, start + 7, ['schlafen']),
      ]),
      '😀 Die Katzen schlafen.',
    );
    expect(score['output'], '😀 Die Katzen schlafen.');
    expect(score['exact'], isTrue);
    expect(score['changed'], isTrue);
  });

  test('multiple choices and overlapping proposals cannot score exact', () {
    final request = _request('Die Katzen schläft.');
    final start = request.text.indexOf('schläft');
    final multiple = harness.arm(
      _report(request, [
        _finding(request, start, start + 7, ['schlafen', 'schliefen']),
      ]),
      'Die Katzen schlafen.',
    );
    expect(multiple['all_choices_resolved'], isFalse);
    expect(multiple['exact'], isFalse);
    final overlap = harness.arm(
      _report(request, [
        _finding(request, start, start + 7, ['schlafen']),
        _finding(request, start, start + 7, ['schlafen']),
      ]),
      'Die Katzen schlafen.',
    );
    expect(overlap['applicable_nonoverlapping_edits'], isFalse);
    expect(overlap['output'], request.text);
    expect(overlap['exact'], isFalse);
  });

  test('partial graphemes and wrong original text fail source mapping', () {
    final request = _request('A\u0308pfel sind rot.');
    expect(
      () => harness.arm(
        _report(request, [
          _finding(request, 0, 1, ['O']),
        ]),
        request.text,
      ),
      throwsStateError,
    );
    final wrong = OfficeProofingFinding(
      documentId: request.documentId,
      blockId: request.blockId,
      revision: request.revision,
      providerId: 'synthetic',
      start: request.startOffset,
      end: request.startOffset + 6,
      originalText: 'wrong!',
      ruleId: 'synthetic',
      message: 'Synthetic source guard.',
      category: OfficeProofingCategory.grammar,
      replacements: ['Birnen'],
    );
    expect(
      () => harness.arm(_report(request, [wrong]), request.text),
      throwsStateError,
    );
  });

  test('unsupported and failed arms are never exact clean successes', () {
    final request = _request('Unchanged.');
    for (final status in [
      OfficeProofingStatus.unsupported,
      OfficeProofingStatus.failed,
    ]) {
      final score = harness.arm(
        _report(request, [], status: status),
        request.text,
      );
      expect(score['complete'], isFalse);
      expect(score['exact'], isFalse);
      expect(score['changed'], isFalse);
    }
  });

  test(
    'summary counts raw native false positives despite merge suppression',
    () {
      Map<String, Object?> arm({
        bool exact = false,
        bool flagged = false,
        bool changed = false,
      }) => {
        'exact': exact,
        'changed': changed,
        'findings': flagged ? [<String, Object?>{}] : <Object?>[],
      };
      final summary = harness.summarize([
        {
          'kind': 'error',
          'baseline': arm(),
          'model': arm(exact: true, flagged: true),
          'combined': arm(exact: true, flagged: true),
          'operational_ok': true,
        },
        {
          'kind': 'error',
          'baseline': arm(exact: true),
          'model': arm(),
          'combined': arm(),
          'operational_ok': true,
        },
        {
          'kind': 'valid',
          'baseline': arm(),
          'model': arm(flagged: true, changed: true),
          'combined': arm(),
          'model_proposals_suppressed_by_merge': 1,
          'operational_ok': true,
        },
        {
          'kind': 'guard',
          'baseline': arm(),
          'model': arm(flagged: true),
          'combined': arm(flagged: true),
          'operational_ok': true,
        },
        {
          'kind': 'unsupported',
          'baseline': arm(),
          'model': arm(),
          'combined': arm(),
          'operational_ok': true,
        },
        {'kind': 'error', 'operational_ok': false},
      ]);
      expect(summary['additional_exact_errors'], 1);
      expect(summary['baseline_exact_lost'], 1);
      expect(summary['model_valid_flagged'], 1);
      expect(summary['combined_valid_flagged'], 0);
      expect(summary['model_guard_flagged'], 1);
      expect(summary['merge_suppressed_proposals'], 1);
      expect(summary['unsupported_cases'], 1);
      expect(summary['operational_failures'], 1);
      expect(summary['completed_cases'], 5);
      expect(summary['model_abstentions_or_compatible_cases'], 1);
    },
  );
}

List<String> _arguments(
  Directory root,
  File output, {
  String phase = 'development',
}) => [
  '--root',
  root.path,
  '--phase',
  phase,
  '--panel',
  '${root.path}/missing-panel.json',
  '--library',
  '${root.path}/nonexistent-native-library.so',
  '--bundle',
  '${root.path}/nonexistent-model-bundle',
  '--report',
  output.path,
];

const _provider =
    'packages/quds_office_engine/lib/src/proofing/german_writing_rules.dart';
const _data =
    'packages/quds_office_engine/lib/src/proofing/data/synthetic_data.dart';
const _zip = 'packages/quds_office_engine/lib/src/opc/zip/synthetic_codec.dart';

Map<String, dynamic> _baselineFixture(Directory root) {
  for (final path in [_provider, _data, _zip]) {
    _write(root, path, '// Synthetic baseline fixture for $path\n');
  }
  String git(List<String> args) {
    final result = Process.runSync('git', args, workingDirectory: root.path);
    if (result.exitCode != 0) {
      throw StateError('Fixture git operation failed: ${result.stderr}');
    }
    return (result.stdout as String).trim();
  }

  git(['init', '-q']);
  git(['add', '.']);
  git([
    '-c',
    'core.hooksPath=.git/no-hooks',
    '-c',
    'commit.gpgsign=false',
    '-c',
    'user.name=Harness Control',
    '-c',
    'user.email=harness-control@example.invalid',
    'commit',
    '-qm',
    'Synthetic baseline',
  ]);
  return {
    'baseline': {
      'main_commit': git(['rev-parse', 'HEAD']),
      'ordinary_provider_sources_sha256': {
        _provider: harness.digest(
          File('${root.path}/$_provider').readAsBytesSync(),
        ),
      },
    },
  };
}

File _write(Directory root, String path, String text) {
  final file = File('${root.path}/$path');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(text);
  return file;
}

OfficeProofingRequest _request(String text) => OfficeProofingRequest(
  documentId: 'synthetic-control',
  blockId: 'paragraph',
  revision: 1,
  text: text,
  startOffset: 23,
);

OfficeProofingFinding _finding(
  OfficeProofingRequest request,
  int start,
  int end,
  List<String> replacements,
) => OfficeProofingFinding.forRequest(
  request,
  providerId: 'synthetic',
  start: start,
  end: end,
  ruleId: 'synthetic',
  message: 'Synthetic scoring control.',
  category: OfficeProofingCategory.grammar,
  replacements: replacements,
);

OfficeProofingReport _report(
  OfficeProofingRequest request,
  List<OfficeProofingFinding> findings, {
  OfficeProofingStatus status = OfficeProofingStatus.success,
}) => OfficeProofingReport(
  request: request,
  results: [
    OfficeProofingResult(
      request: request,
      providerId: 'synthetic',
      status: status,
      findings: findings,
    ),
  ],
);
