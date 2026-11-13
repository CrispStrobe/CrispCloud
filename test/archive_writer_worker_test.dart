import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/verify_archive_writer_worker.dart';

void main() {
  test(
    'native writer worker roundtrips streamed formats and raw HFSX',
    verifyArchiveWorkerRoundTrips,
  );
  test(
    'native writer worker preserves buffered compression and protection options',
    verifyArchiveWorkerBufferedOptions,
  );
  test(
    'native writer worker retains opaque DMG preservation evidence',
    verifyArchiveWorkerPreservation,
  );
  test(
    'native writer worker pauses pulls and honors sink backpressure',
    verifyArchiveWorkerPauseAndBackpressure,
  );
  test(
    'native writer worker cancels stalled input and paused checkpoints',
    verifyArchiveWorkerCancellation,
  );
  test(
    'native writer worker rejects faults and cleans up crashed codec spools',
    verifyArchiveWorkerFailures,
  );
  for (final (kind, label) in [('zip', 'ZIP'), ('7z', '7z'), ('tgz', 'TGZ')]) {
    test(
      '$label worker streams and verifies a member beyond 2 GiB',
      () => verifyArchiveWorkerLarge(kind),
      skip: ![
        '1',
        kind,
      ].contains(Platform.environment['CRISP_ARCHIVE_WORKER_LARGE']),
      timeout: const Timeout(Duration(minutes: 20)),
    );
  }
}
