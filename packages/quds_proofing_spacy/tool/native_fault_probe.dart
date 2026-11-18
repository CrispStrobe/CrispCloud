// Actual FFI calls to a deliberately malformed developer-only C ABI fixture.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy_native.dart';

typedef _SetNative = Void Function(Int32);
typedef _SetDart = void Function(int);
typedef _CountNative = Int32 Function();
typedef _CountDart = int Function();
typedef _BytesNative = Size Function();
typedef _BytesDart = int Function();

Future<void> main(List<String> args) async {
  if (args.length != 5) {
    throw ArgumentError(
      'Expected fixture-library sha256 bundle quds-root report',
    );
  }
  final [libraryPath, librarySha, bundlePath, root, outputPath] = args;
  final output = File(outputPath);
  if (output.existsSync()) throw StateError('Receipt already exists.');
  final before = _sources(root);
  final report = <String, Object?>{
    'schema': 'quds.spacy.dart.native-faults.v1',
    'scope':
        'Real Dart binding against a model-free malformed C ABI fixture; '
        'no trained model, linguistic, native inference or performance claim.',
    'fixture_library_sha256': librarySha,
    'source_sha256_before': before,
    'passed': false,
  };
  final controls = <Map<String, Object?>>[];
  report['controls'] = controls;
  SpacyBackend? backend;
  try {
    require(
      sha256.convert(File(libraryPath).readAsBytesSync()).toString() ==
          librarySha,
      'Fixture binary differs from explicit trusted hash.',
    );
    final library = DynamicLibrary.open(libraryPath);
    final setMode = library.lookupFunction<_SetNative, _SetDart>(
      'fixture_mode',
    );
    final contexts = library.lookupFunction<_CountNative, _CountDart>(
      'fixture_contexts',
    );
    final documents = library.lookupFunction<_CountNative, _CountDart>(
      'fixture_documents',
    );
    final frees = library.lookupFunction<_CountNative, _CountDart>(
      'fixture_document_frees',
    );
    final inputBytes = library.lookupFunction<_BytesNative, _BytesDart>(
      'fixture_input_bytes',
    );
    final factory = SpacyNativeBackendFactory(
      bundleDirectory: bundlePath,
      libraryPath: libraryPath,
      librarySha256: librarySha,
    );
    const bundle = SpacyBundle.germanF32();
    setMode(0);
    backend = await factory.open(bundle);
    require(contexts() == 1, 'No owned native context.');
    final request = LinguisticAnalysisRequest(
      text: 'A😀\u0000é',
      documentId: 'fixture',
      blockId: 'body',
      revision: 4,
      startOffset: 53,
    );
    final original = await backend.analyze(request);
    require(
      original.isSuccess &&
          original.tokens.single.text == request.text &&
          original.tokens.single.end == 5 &&
          original.tokens.single.byteEnd == 8 &&
          inputBytes() == 8 &&
          documents() == 0,
      'Actual FFI did not honor counted UTF8 or release its document.',
    );
    controls.add({'id': 'counted-nul-unicode-copy', 'passed': true});
    final faultNames = <int, String>{
      1: 'error-with-owned-document',
      2: 'success-null-document',
      3: 'excessive-token-count',
      4: 'unanalyzed-document',
      5: 'token-view-error',
      6: 'excessive-counted-string',
      7: 'null-nonempty-string',
      8: 'malformed-utf8-output',
      9: 'split-byte-span',
      10: 'wrong-utf16-span',
      11: 'invalid-head',
      12: 'unknown-flags',
      13: 'bounded-nonterminated-error',
      14: 'wrong-scalar-span',
      15: 'missing-sentence-end',
    };
    for (final fault in faultNames.entries) {
      final freesBefore = frees();
      setMode(fault.key);
      final result = await backend.analyze(request);
      require(
        result.status == LinguisticAnalysisStatus.failed &&
            result.tokens.isEmpty &&
            result.sentences.isEmpty,
        '${fault.value}: partial or successful malformed result.',
      );
      require(
        documents() == 0 && contexts() == 1,
        '${fault.value}: native resource leak or premature context free.',
      );
      require(
        frees() - freesBefore == (fault.key == 2 ? 0 : 1),
        '${fault.value}: owned document not freed exactly once.',
      );
      if (fault.key == 13) {
        require(
          result.message!.length == 1024,
          'Error diagnostic read beyond its fixed buffer.',
        );
      }
      setMode(0);
      require(
        (await backend.analyze(request)).isSuccess && documents() == 0,
        '${fault.value}: context did not recover.',
      );
      controls.add({
        'id': fault.value,
        'status': result.status.name,
        'native_document_freed': fault.key != 2,
        'recovered': true,
        'passed': true,
      });
    }
    final originalJson = jsonEncode(original.toJson());
    await backend.dispose();
    await backend.dispose();
    require(
      contexts() == 0 &&
          documents() == 0 &&
          jsonEncode(original.toJson()) == originalJson,
      'Idempotent context disposal damaged copied result or leaked resources.',
    );
    controls.add({'id': 'result-after-idempotent-dispose', 'passed': true});
    backend = null;
    for (final mode in [20, 21, 22]) {
      setMode(mode);
      var rejected = false;
      try {
        backend = await factory.open(bundle);
      } catch (_) {
        rejected = true;
      }
      require(
        rejected && contexts() == 0,
        'Startup mode $mode was accepted or leaked a context.',
      );
      controls.add({
        'id': 'startup-$mode',
        'rejected': true,
        'live_contexts': contexts(),
        'passed': true,
      });
    }
    setMode(0);
    report['native_document_frees'] = frees();
    report['live_documents'] = documents();
    report['live_contexts'] = contexts();
    report['passed'] = true;
  } catch (error) {
    report['failure'] = error.toString().replaceAll(
      File(root).absolute.path,
      '<quds-root>',
    );
    exitCode = 1;
  } finally {
    await backend?.dispose();
    final after = _sources(root);
    report['source_sha256_after'] = after;
    report['source_unchanged'] = jsonEncode(before) == jsonEncode(after);
    if (report['source_unchanged'] != true) {
      report['passed'] = false;
      report['failure'] =
          'Source changed while running the native fault probe.';
      exitCode = 1;
    }
    output.parent.createSync(recursive: true);
    output.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    );
  }
  stdout.writeln(
    jsonEncode({
      'passed': report['passed'],
      'controls': controls.length,
      'failure': report['failure'],
    }),
  );
}

Map<String, String> _sources(String root) {
  final absolute = Directory(root).absolute.path;
  final files = <File>[
    ...Directory('$absolute/packages/quds_proofing_spacy/lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart')),
    File('$absolute/packages/quds_proofing_spacy/tool/native_fault_probe.dart'),
    File('$absolute/packages/quds_proofing_spacy/tool/native_fault_fixture.c'),
  ]..sort((a, b) => a.path.compareTo(b.path));
  return {
    for (final file in files)
      file.path.substring(absolute.length + 1): sha256
          .convert(file.readAsBytesSync())
          .toString(),
  };
}

void require(bool value, String message) {
  if (!value) throw StateError(message);
}
