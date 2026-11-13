import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/verify_archive_rar_stored.dart';

void main() {
  test(
    'RAR5 Store streams creation and folder-style member rewrites',
    () => verifyRarStoredRoundTrips(),
  );
  test(
    'RAR5 Store preserves exact supported metadata',
    () => verifyRarStoredMetadata(),
  );
  test(
    'RAR5 Store rejects unsafe profiles, corruption, source changes and cancellation',
    verifyRarStoredGuards,
  );
  test(
    'RAR5 Store writes and fully reads a container larger than 2 GiB',
    () => verifyRarStoredLarge(),
    skip: Platform.environment['CRISP_RAR_STORED_LARGE'] != '1',
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
