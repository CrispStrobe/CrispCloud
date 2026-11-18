import 'backend.dart';
import 'bundle.dart';
import 'transport.dart';

Future<SpacyTransport> startWorker({
  required SpacyBundle bundle,
  required SpacyBackendFactory backendFactory,
  required int maximumPendingRequests,
  required int maximumTextCodeUnits,
  required Duration startupTimeout,
  required Duration requestTimeout,
}) async => throw const SpacyUnavailableException(
  'Local spaCy analysis is unavailable on this platform.',
);
