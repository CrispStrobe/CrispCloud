import 'web_vba_conformance.dart' as conformance;

/// Runs word_join_v1.json supplied through -DVBA_CONFORMANCE_BASE64 on the
/// Dart VM or compiled JavaScript. The canonical corpus contains independently
/// authored native plans and diagnostics with explicit evidence provenance.
void main() => conformance.main();
