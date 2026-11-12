// Compile with `dart compile js` and run with Node to check the public range
// decoder's JavaScript backend and the known-size encoder without dart:io.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/services/archive_lzma_codec.dart';
import 'package:crisp_cloud/services/archive_types.dart';

void main() {
  // Original liblzma fixture with lc=1, lp=2, pb=4 and a terminal marker.
  final reference = base64Decode(
    'xwAAAQD//////////wAnG8nC0zrfyDAa3KEfjAyT0JeTaaS1qFxf5A6h/kIFxuZl'
    'N/BLFHRn8FR8VN8/sOLAp+n59keniaEGmUvRxQfmrXueKX3jnfIUXuS38rc0ko4V'
    'Ipkc5KIfP//9g4wA',
  );
  final expected = Uint8List.fromList([
    for (var i = 0; i < 500; i++) ...[
      ...ascii.encode('Non-default literal positions'),
      0,
      255,
    ],
  ]);
  void compare(Uint8List actual) {
    if (actual.length != expected.length) {
      throw StateError('Wrong output size.');
    }
    for (var i = 0; i < actual.length; i++) {
      if (actual[i] != expected[i]) throw StateError('Wrong output byte $i.');
    }
  }

  compare(decodeArchiveLzma(reference));
  final packed = encodeArchiveLzma(expected);
  compare(decodeArchiveLzma(packed));
  final withTail = Uint8List.fromList([...packed, 0]);
  var refused = false;
  try {
    decodeArchiveLzma(withTail);
  } on ArchiveViewException {
    refused = true;
  }
  if (!refused) throw StateError('Trailing LZMA data was silently ignored.');
  print('Portable LZMA native fixture, writer and exact framing verified.');
}
