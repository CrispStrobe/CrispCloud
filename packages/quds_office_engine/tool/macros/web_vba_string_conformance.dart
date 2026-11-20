import 'dart:convert';

import '../../test/support/vba_conformance.dart';

/// Run the exact canonical JSON corpus on either VM or JavaScript.
///
/// Supply base64-encoded fixture bytes with -DVBA_CONFORMANCE_BASE64=... to
/// `dart run` or `dart compile js`. This runner has no dart:io dependency and
/// never maintains a second generated copy of the expected cases.
void main() {
  const encoded = String.fromEnvironment('VBA_CONFORMANCE_BASE64');
  if (encoded.isEmpty) {
    throw StateError(
      'Supply the canonical corpus using -DVBA_CONFORMANCE_BASE64.',
    );
  }
  final source = utf8.decode(base64Decode(encoded));
  final suite = VbaConformanceSuite.parse(source);
  print(canonicalVbaConformanceJson(runVbaConformanceSuite(suite)));
}
