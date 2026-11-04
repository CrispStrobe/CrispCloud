/// Optional platform persistence for the PDF editor's secret-store interfaces.
///
/// Hosts opt in explicitly; the editor core has no secure-storage dependency.
library;

export 'src/form_secret_store.dart';
export 'src/signing_identity_store.dart';
