import 'analysis.dart';
import 'backend.dart';
import 'bundle.dart';
import 'source_text.dart';
import 'worker_unsupported.dart'
    if (dart.library.io) 'worker_native.dart'
    as platform;

/// A persistent, explicitly loaded analysis worker. Cancellation rejects a
/// caller immediately. Its native call retains the only in-flight slot until
/// it returns; neither cancellation nor shutdown destroys a live context.
abstract interface class SpacyTransport {
  SpacyBackendIdentity get identity;
  Future<LinguisticAnalysisResult> analyze(LinguisticAnalysisRequest request);
  void cancel(String key);

  /// Rejects pending callers immediately, then joins native cleanup. A native
  /// call which does not return delays this future; it is never force-killed.
  Future<void> dispose();
}

Future<SpacyTransport> startSpacyWorker({
  required SpacyBundle bundle,
  required SpacyBackendFactory backendFactory,
  int maximumPendingRequests = 3,
  int maximumTextCodeUnits = spacyMaximumTextBytes,
  Duration startupTimeout = const Duration(seconds: 60),
  Duration requestTimeout = const Duration(seconds: 30),
}) {
  if (maximumPendingRequests < 1 ||
      maximumPendingRequests > 8 ||
      maximumTextCodeUnits < 1 ||
      maximumTextCodeUnits > spacyMaximumTextBytes ||
      startupTimeout <= Duration.zero ||
      requestTimeout <= Duration.zero) {
    throw ArgumentError('Invalid spaCy worker limits.');
  }
  return platform.startWorker(
    bundle: bundle,
    backendFactory: backendFactory,
    maximumPendingRequests: maximumPendingRequests,
    maximumTextCodeUnits: maximumTextCodeUnits,
    startupTimeout: startupTimeout,
    requestTimeout: requestTimeout,
  );
}
