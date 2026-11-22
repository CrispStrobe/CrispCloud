import 'web_vba_conformance.dart' as conformance;

/// Runs word_cell_paragraphs_v1.json supplied through
/// -DVBA_CONFORMANCE_BASE64 on the Dart VM or compiled JavaScript. Expectations
/// are independently authored native plans and stable source diagnostics, with
/// explicit specification-derived and bounded-dialect provenance.
void main() => conformance.main();
