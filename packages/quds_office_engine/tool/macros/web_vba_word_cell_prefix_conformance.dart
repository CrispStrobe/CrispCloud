import 'web_vba_conformance.dart' as conformance;

/// Runs word_cell_prefix_v1.json supplied through
/// -DVBA_CONFORMANCE_BASE64 on the Dart VM or compiled JavaScript. Expected
/// plans and positioned diagnostics are independently authored; specification
/// provenance does not claim execution in an installed Microsoft Word host.
void main() => conformance.main();
