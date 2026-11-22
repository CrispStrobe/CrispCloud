import 'web_vba_conformance.dart' as conformance;

/// Supply strreverse_v1.json through -DVBA_CONFORMANCE_BASE64 to run the
/// same complete native-plan and positioned-diagnostic expectations on the
/// Dart VM or compiled JavaScript. This runner does not use dart:io.
void main() => conformance.main();
