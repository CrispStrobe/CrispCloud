import 'web_vba_conformance.dart' as conformance;

/// Runs the canonical text_intrinsics_v1.json supplied through
/// -DVBA_CONFORMANCE_BASE64 on the Dart VM or compiled JavaScript.
///
/// The shared runner consumes the exact fixture bytes, preserving one set of
/// independently authored expectations and provenance for both runtimes.
void main() => conformance.main();
