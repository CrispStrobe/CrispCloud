import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/verify_archive_streaming_writer.dart';

void main() {
  test(
    'streamed common formats preserve content, times, modes and empty entries',
    () => verifyArchiveStreamingRoundTrips(),
  );
  test(
    'streamed writers enforce size, source, cancellation and backpressure contracts',
    verifyArchiveStreamingGuards,
  );
  test(
    'ZIP64 handles entry count and >4GiB member header boundaries',
    () => verifyArchiveStreamingZip64(),
  );
  test(
    'ZIP, TGZ and 7z stream a source larger than 2GiB with bounded memory',
    () => verifyArchiveStreamingLarge(),
    skip: Platform.environment['CRISP_STREAMING_ARCHIVE_LARGE'] != '1',
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
