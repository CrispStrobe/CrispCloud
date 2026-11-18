// Compile with dart2js and run under a browser-compatible JavaScript runtime.
// This deliberately imports both public entry points. No network/model access
// or native fallback is permitted on the unsupported platform.
import 'dart:convert';

import 'package:quds_proofing_spacy/quds_proofing_spacy_native.dart';

Future<void> main() async {
  final factory = SpacyNativeBackendFactory(
    bundleDirectory: 'unavailable-on-web',
    libraryPath: 'unavailable-on-web',
    librarySha256:
        'ea89842ebf22c08508aff1cfbf18d78a107118af320523009616ff62b6e42977',
  );
  var rejected = 0;
  try {
    await factory.open(const SpacyBundle.germanF32());
  } on SpacyUnavailableException {
    rejected++;
  }
  try {
    await startSpacyWorker(
      bundle: const SpacyBundle.germanF32(),
      backendFactory: factory,
    );
  } on SpacyUnavailableException {
    rejected++;
  }
  if (rejected != 2) {
    throw StateError('Web must explicitly reject both native capabilities.');
  }
  print(
    jsonEncode({
      'passed': true,
      'public_native_factory': 'unavailable',
      'worker': 'unavailable',
      'native_calls': 0,
    }),
  );
}
