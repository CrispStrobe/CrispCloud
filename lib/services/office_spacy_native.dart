import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy_native.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy_grammar.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy_macos.dart';

import 'office_spacy_preferences.dart';

typedef _SetenvNative = Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Int32);
typedef _SetenvDart = int Function(Pointer<Utf8>, Pointer<Utf8>, int);

void _explicitNativeOptIn() {
  if (!(Platform.isLinux || Platform.isMacOS)) {
    throw UnsupportedError('Native spaCy is unavailable on this platform.');
  }
  final setenv = DynamicLibrary.process()
      .lookupFunction<_SetenvNative, _SetenvDart>('setenv');
  using((arena) {
    if (setenv(
          'CRISPEMBED_SPACY'.toNativeUtf8(allocator: arena),
          '1'.toNativeUtf8(allocator: arena),
          1,
        ) !=
        0) {
      throw StateError('Could not opt into the native worker.');
    }
  });
}

/// Creates an owned provider only after the persisted explicit opt-in. The
/// session receives it on configureManual, never the ordinary typing service.
Future<OfficeProofingService?> openOfficeSpacyManualService() async {
  final config = await OfficeSpacyPreferences.read();
  if (!config.enabled) return null;
  if (Abi.current() != Abi.linuxX64) {
    throw UnsupportedError(
      'Manual native grammar is qualified only for Linux x86-64/AVX2.',
    );
  }
  _explicitNativeOptIn();
  final provider = await SpacyGrammarProvider.load(
    enabled: true,
    backendFactory: SpacyNativeBackendFactory(
      bundleDirectory: config.bundle,
      libraryPath: config.library,
      librarySha256: spacyGrammarNativeSha256,
    ),
  );
  return OfficeProofingService(providers: [provider]);
}

/// Invoked only by an explicit diagnostic build of the actual Runner entry
/// point. This is a real owned isolate/native context, not a fake provider.
/// It proves operational app loading, not grammar accuracy or default-on use.
Future<void> runSignedSpacyNativeProbe() async {
  if (Abi.current() != Abi.macosArm64) {
    throw UnsupportedError('The signed W7 native probe requires macOS ARM64.');
  }
  const signedSha = String.fromEnvironment('CRISP_SPACY_SIGNED_LIBRARY_SHA256');
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(signedSha)) {
    throw StateError('No source-bound signed library identity was supplied.');
  }
  final resources = p.join(
    File(Platform.resolvedExecutable).parent.parent.path,
    'Resources',
    'spacy-w7',
  );
  _explicitNativeOptIn();
  final worker = await startSpacyWorker(
    bundle: const SpacyBundle.germanF32(),
    backendFactory: SpacyMacOSBackendFactory(
      bundleDirectory: p.join(resources, 'bundle'),
      libraryPath: p.join(resources, signedSha, 'libcrispembed-spacy.dylib'),
      librarySha256: signedSha,
    ),
  );
  final times = <int>[];
  LinguisticAnalysisResult? retained;
  var rssStart = 0;
  var fdStart = 0;
  var fdWarm = 0;
  final rss = <int>[];
  try {
    for (var i = 0; i < 28; i++) {
      final watch = Stopwatch()..start();
      final result = await worker.analyze(
        LinguisticAnalysisRequest(
          text: 'Eine freundliche Schildkröte schläft.',
          documentId: 'w7-signed-app-operational',
          blockId: 'sample-$i',
          revision: i,
          locale: 'de-DE',
          startOffset: 23,
          configurationId: 'w7-signed-app-native-component',
        ),
      );
      if (!result.isSuccess ||
          result.tokens.isEmpty ||
          result.tokens.first.text != 'Eine' ||
          result.tokens.last.text != '.') {
        throw StateError('The actual app worker returned incomplete analysis.');
      }
      if (result.identity != worker.identity) {
        throw StateError(
          'Worker identity changed during the signed app probe.',
        );
      }
      if (i == 2) {
        rssStart = ProcessInfo.currentRss;
        fdStart = Directory('/dev/fd').listSync().length;
      }
      if (i >= 3) {
        times.add(watch.elapsedMicroseconds);
        rss.add(ProcessInfo.currentRss);
      }
      retained = result;
    }
    fdWarm = Directory('/dev/fd').listSync().length;
  } finally {
    await worker.dispose();
  }
  if (retained == null || retained.tokens.first.text != 'Eine') {
    throw StateError('Owned analysis did not survive native worker disposal.');
  }
  final fdAfter = Directory('/dev/fd').listSync().length;
  final rssMax = rss.reduce((a, b) => a > b ? a : b);
  if (rssMax - rssStart > 32 * 1024 * 1024 || fdAfter > fdStart) {
    throw StateError('The finite signed-app resource bound failed.');
  }
  final sorted = times.toList()..sort();
  stdout.writeln(
    'CRISP_SPACY_W7_RESULT=' +
        jsonEncode({
          'schema': 'crispcloud.spacy.w7.signed-app-native.v1',
          'passed': true,
          'actual_Runner_entrypoint': true,
          'real_native_worker': true,
          'architecture': Abi.current().toString(),
          'dart': Platform.version,
          'signed_library_sha256': signedSha,
          'warmups': 3,
          'measured_requests': 25,
          'median_microseconds': sorted[sorted.length ~/ 2],
          'rss_start': rssStart,
          'rss_max': rssMax,
          'fds': {
            'after_warmup': fdStart,
            'before_dispose': fdWarm,
            'after_dispose': fdAfter,
          },
          'copied_analysis_survives_dispose': true,
          'analysis': retained.toJson(),
          'provider_default': 'OFF',
          'grammar_quality_qualified': false,
          'limits':
              'Diagnostic actual signed Runner/native worker operational sample; not UI/grammar accuracy or a leak proof.',
        }),
  );
}
