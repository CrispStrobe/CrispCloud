// Explicit actual-library validation. Missing inputs fail; no test skip path.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy_native.dart';

const _developmentManifestSha =
    '9a3bb6bae6114adcf579840834ddcb64dea4e0aaa8361718dc7a551d663c8f7c';

Future<void> main(List<String> args) async {
  final options = <String, String>{};
  for (var i = 0; i < args.length; i += 2) {
    if (i + 1 >= args.length ||
        !args[i].startsWith('--') ||
        options.containsKey(args[i])) {
      throw ArgumentError('Expected unique --name value arguments.');
    }
    options[args[i]] = args[i + 1];
  }
  const names = {
    '--library',
    '--library-sha',
    '--bundle',
    '--quds-root',
    '--report',
  };
  if (!names.every(options.containsKey) ||
      options.keys.any((name) => !names.contains(name) && name != '--mode')) {
    throw ArgumentError(
      'Required: ${names.join(', ')}; optional --mode direct|worker',
    );
  }
  final mode = options['--mode'] ?? 'direct';
  if (mode != 'direct' && mode != 'worker') {
    throw ArgumentError('--mode must be direct or worker.');
  }
  final reportFile = File(options['--report']!);
  if (reportFile.existsSync()) throw StateError('Receipt already exists.');
  final root = Directory(options['--quds-root']!).absolute.path;
  final sourcesBefore = sourceHashes(root);
  final fixtureRoot = '$root/tools/proofing/spacy/fixtures/development';
  final manifestBytes = File('$fixtureRoot/manifest.json').readAsBytesSync();
  require(
    sha256.convert(manifestBytes).toString() == _developmentManifestSha,
    'Frozen development manifest changed.',
  );
  final manifest =
      jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
  require(
    manifest['split'] == 'development' &&
        manifest['case_count'] == 16 &&
        manifest['token_count'] == 113 &&
        manifest['complete'] == true,
    'Incomplete or wrong development fixture panel.',
  );
  final factory = SpacyNativeBackendFactory(
    bundleDirectory: options['--bundle']!,
    libraryPath: options['--library']!,
    librarySha256: options['--library-sha']!,
  );
  final report = <String, Object?>{
    'schema': 'quds.spacy.dart.development.v1',
    'mode': mode,
    'source_sha256_before': sourcesBefore,
    'started_at': DateTime.now().toUtc().toIso8601String(),
    'scope':
        'Dart FFI and complete exposed annotations on the existing 16 '
        'development documents; not a new acceptance or grammar evaluation.',
    'development_manifest_sha256': _developmentManifestSha,
    'native_heldout_acceptance_executions': 0,
    'ci_endpoints_queried': false,
    'platform': 'linux-x86_64',
    'dart_version': Platform.version.split(' ').first,
    'passed': false,
  };
  SpacyBackend? backend;
  try {
    final loadWatch = Stopwatch()..start();
    backend = mode == 'worker'
        ? _WorkerBackend(
            await startSpacyWorker(
              bundle: const SpacyBundle.germanF32(),
              backendFactory: factory,
              maximumTextCodeUnits: 1024 * 1024,
            ),
          )
        : await factory.open(const SpacyBundle.germanF32());
    report['open_microseconds'] = loadWatch.elapsedMicroseconds;
    report['identity'] = backend.identity.toJson();
    final cases = <Map<String, Object?>>[];
    report['cases'] = cases; // Preserve completed cases if a later one fails.
    final ids = <String>{};
    var tokenCount = 0;
    var sentenceCount = 0;
    var comparedFields = 0;
    LinguisticAnalysisResult? retained;
    for (final entry in manifest['cases'] as List) {
      final item = entry as Map<String, dynamic>;
      final id = item['id'] as String;
      require(
        ids.add(id) && RegExp(r'^[a-z-]+$').hasMatch(id),
        'Invalid or duplicate development case ID.',
      );
      final fileEntry = (item['files'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((entry) => entry['path'] == '$id/case.json');
      final bytes = File('$fixtureRoot/$id/case.json').readAsBytesSync();
      require(
        bytes.length == fileEntry['size_bytes'] &&
            sha256.convert(bytes).toString() == fileEntry['sha256'],
        'Development reference changed: $id',
      );
      final reference = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final input = reference['case'] as Map<String, dynamic>;
      require(
        input['id'] == id &&
            input['locale'] == 'de-DE' &&
            sha256.convert(utf8.encode(input['text'] as String)).toString() ==
                item['input_sha256'],
        'Development input identity changed.',
      );
      final request = LinguisticAnalysisRequest(
        text: input['text'] as String,
        documentId: 'development',
        blockId: id,
        revision: 7,
        startOffset: 37,
        generation: 11,
        configurationId: 'development-ffi-v1',
      );
      final watch = Stopwatch()..start();
      final result = await backend.analyze(request);
      final elapsed = watch.elapsedMicroseconds;
      require(
        result.isSuccess,
        '$id: ${result.status.name}: ${result.message}',
      );
      require(
        result.request.sameSnapshot(request) &&
            result.identity == backend.identity,
        'Backend changed snapshot or runtime identity.',
      );
      final expected = reference['annotations'] as Map<String, dynamic>;
      final actual = result.toJson();
      final differences = <String>[];
      for (final category in ['tokens', 'sentences']) {
        final actualRows = actual[category] as List;
        final expectedRows = expected[category] as List;
        require(
          actualRows.length == expectedRows.length,
          '$id: $category count changed.',
        );
        for (var i = 0; i < actualRows.length; i++) {
          final row = actualRows[i] as Map<String, Object>;
          final original = expectedRows[i] as Map<String, dynamic>;
          for (final field in row.keys) {
            comparedFields++;
            if (!original.containsKey(field) || original[field] != row[field]) {
              differences.add('$category[$i].$field');
            }
          }
        }
      }
      require(differences.isEmpty, '$id: ${differences.join(', ')}');
      tokenCount += result.tokens.length;
      sentenceCount += result.sentences.length;
      cases.add({
        'id': id,
        'input_sha256': item['input_sha256'],
        'status': result.status.name,
        'origin_utf16': 37,
        'tokens': actual['tokens'],
        'sentences': actual['sentences'],
        'differences': differences,
        'microseconds': elapsed,
      });
      retained = result;
    }
    require(
      cases.length == 16 && tokenCount == 113 && sentenceCount == 22,
      'Incomplete development denominator.',
    );
    report['cases'] = cases;
    report['counts'] = {
      'cases': cases.length,
      'tokens': tokenCount,
      'sentences': sentenceCount,
      'compared_fields': comparedFields,
      'differences': 0,
    };

    final controls = <Map<String, Object?>>[];
    report['controls'] = controls;
    Future<void> control(
      String id,
      String text,
      LinguisticAnalysisStatus status, {
      String locale = 'de-DE',
    }) async {
      final request = LinguisticAnalysisRequest(
        text: text,
        documentId: 'control',
        blockId: id,
        revision: 1,
        locale: locale,
        startOffset: 19,
      );
      final output = await backend!.analyze(request);
      require(
        output.status == status,
        '$id expected ${status.name}, got '
        '${output.status.name}: ${output.message}',
      );
      require(output.request.sameSnapshot(request), '$id request changed.');
      if (!output.isSuccess) {
        require(
          output.tokens.isEmpty && output.sentences.isEmpty,
          '$id returned successful partial output.',
        );
      }
      controls.add({
        'id': id,
        'status': output.status.name,
        'message': output.message,
        'tokens': output.tokens.length,
        'passed': true,
      });
    }

    for (final locale in ['de-AT', 'de-CH', 'en-US']) {
      await control(
        'unsupported-$locale',
        'Hallo.',
        LinguisticAnalysisStatus.unsupported,
        locale: locale,
      );
    }
    await control('unpaired-high', '\ud800', LinguisticAnalysisStatus.failed);
    await control('unpaired-low', '\udc00', LinguisticAnalysisStatus.failed);
    await control(
      'byte-overflow',
      'ä' * (1024 * 1024 ~/ 2 + 1),
      LinguisticAnalysisStatus.failed,
    );
    await control(
      'token-overflow',
      'x ' * 2049,
      LinguisticAnalysisStatus.failed,
    );
    await control(
      'recovery-with-nul',
      '😀 A\u0000B ä e\u0301.',
      LinguisticAnalysisStatus.success,
    );
    final retainedJson = jsonEncode(retained!.toJson());
    await backend.dispose();
    await backend.dispose();
    require(
      jsonEncode(retained.toJson()) == retainedJson,
      'Owned result changed after context disposal.',
    );
    await control('disposed', 'Hallo.', LinguisticAnalysisStatus.unavailable);
    controls.add({'id': 'owned-result-after-dispose', 'passed': true});
    report['controls'] = controls;
    report['passed'] = true;
  } catch (error) {
    var message = error.toString();
    for (final option in ['--library', '--bundle', '--quds-root', '--report']) {
      final absolute = File(options[option]!).absolute.path;
      message = message.replaceAll(absolute, '<${option.substring(2)}>');
    }
    report['failure'] = message;
    exitCode = 1;
  } finally {
    await backend?.dispose();
    report['completed_at'] = DateTime.now().toUtc().toIso8601String();
    final sourcesAfter = sourceHashes(root);
    report['source_sha256_after'] = sourcesAfter;
    report['source_unchanged'] =
        jsonEncode(sourcesBefore) == jsonEncode(sourcesAfter);
    if (report['source_unchanged'] != true) {
      report['passed'] = false;
      report['failure'] = 'Source files changed during validation.';
      exitCode = 1;
    }
    reportFile.parent.createSync(recursive: true);
    reportFile.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    );
  }
  stdout.writeln(
    jsonEncode({
      'passed': report['passed'],
      'counts': report['counts'],
      'controls': (report['controls'] as List?)?.length,
      'failure': report['failure'],
    }),
  );
}

Map<String, String> sourceHashes(String root) {
  final paths = <String>[
    ...Directory('$root/packages/quds_proofing_spacy/lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.path),
    '$root/packages/quds_proofing_spacy/tool/replay_development.dart',
  ]..sort();
  return {
    for (final path in paths)
      path.substring(root.length + 1): sha256
          .convert(File(path).readAsBytesSync())
          .toString(),
  };
}

/// Same comparison code through the real native worker; no golden output is
/// sent to the worker and no fake backend stands in for its synchronous FFI.
final class _WorkerBackend implements SpacyBackend {
  _WorkerBackend(this.transport);
  final SpacyTransport transport;
  @override
  SpacyBackendIdentity get identity => transport.identity;
  @override
  Future<LinguisticAnalysisResult> analyze(LinguisticAnalysisRequest request) =>
      transport.analyze(request);
  @override
  Future<void> dispose() => transport.dispose();
}

void require(bool value, String message) {
  if (!value) throw StateError(message);
}
