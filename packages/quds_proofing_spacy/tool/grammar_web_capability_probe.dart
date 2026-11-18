// Compile with dart2js and execute with a browser-compatible JavaScript host.
// This exercises the public optional grammar entry point without model assets.
import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy_grammar.dart';

Future<void> main() async {
  if (const bool.fromEnvironment('dart.library.io')) {
    throw StateError('This capability gate must execute as JavaScript.');
  }
  final factory = _CountingFactory();
  String? disabledLoad;
  try {
    await SpacyGrammarProvider.load(backendFactory: factory);
  } on SpacyUnavailableException catch (error) {
    disabledLoad = error.message;
  }
  if (disabledLoad != 'Optional manual German grammar is disabled.') {
    throw StateError('Grammar loading must default to disabled.');
  }

  final transport = _CountingTransport();
  final provider = SpacyGrammarProvider.withTransport(transport: transport);
  final result = await provider.check(
    OfficeProofingRequest(
      documentId: 'browser-capability-control',
      blockId: 'empty-block',
      revision: 0,
      text: '',
    ),
  );
  await provider.dispose();
  await provider.dispose();
  if (provider.enabled ||
      result.status != OfficeProofingStatus.unavailable ||
      result.findings.isNotEmpty ||
      transport.analyzeCalls != 0 ||
      transport.disposeCalls != 1) {
    throw StateError('A default-disabled provider invoked analysis.');
  }

  String? enabledLoad;
  try {
    await SpacyGrammarProvider.load(backendFactory: factory, enabled: true);
  } on SpacyUnavailableException catch (error) {
    enabledLoad = error.message;
  }
  if (enabledLoad != 'Local spaCy analysis is unavailable on this platform.' ||
      factory.openCalls != 0) {
    throw StateError('Browser grammar must reject native worker startup.');
  }
  // Executable developer gate output, consumed by the qualification receipt.
  // ignore: avoid_print
  print(
    jsonEncode({
      'passed': true,
      'public_grammar_import': true,
      'default_enabled': provider.enabled,
      'disabled_load': 'unavailable',
      'disabled_check': result.status.name,
      'enabled_browser_load': 'unavailable',
      'backend_open_calls': factory.openCalls,
      'transport_analyze_calls': transport.analyzeCalls,
      'transport_dispose_calls': transport.disposeCalls,
      'native_calls': 0,
    }),
  );
}

final class _CountingFactory implements SpacyBackendFactory {
  int openCalls = 0;

  @override
  Future<SpacyBackend> open(SpacyBundle bundle) async {
    openCalls++;
    throw StateError('The browser must never open this backend.');
  }
}

final class _CountingTransport implements SpacyTransport {
  int analyzeCalls = 0;
  int disposeCalls = 0;

  @override
  SpacyBackendIdentity get identity =>
      const SpacyBackendIdentity(librarySha256: spacyGrammarNativeSha256);

  @override
  Future<LinguisticAnalysisResult> analyze(
    LinguisticAnalysisRequest request,
  ) async {
    analyzeCalls++;
    throw StateError('The disabled provider must not analyze.');
  }

  @override
  void cancel(String key) {}

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}
