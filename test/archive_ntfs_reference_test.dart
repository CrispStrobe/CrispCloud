// Copyright (c) 2026 CrispCloud contributors
// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';

import 'support/archive_ntfs_web_acceptance.dart';

void main() {
  test('independent NTFS images, stream hashes, real refusal and derived controls pass portable acceptance', () async {
    final result = await runNtfsReferenceAcceptance();
    expect(result['independent_reference_images'], hasLength(3));
    expect(result['derived_partition_wrappers'], hasLength(3));
    expect(result['all_payload_and_complete_image_hashes_match'], isTrue);
    expect(result['named_streams_are_metadata_only'], isTrue);
  });
}
