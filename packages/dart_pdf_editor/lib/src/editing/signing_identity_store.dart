// CrispCloud modification: platform persistence is an optional companion.
// See UPSTREAM.md for provenance and patch details.
import 'package:pdf_document/pdf_document.dart';

/// Persistence for one-tap [PdfSigningIdentity]s (see
/// [PdfSigningIdentity.generate]). An identity is stored by a caller-chosen
/// [id] as its PEM (`toPem()`), which carries the unprotected private key -
/// so persistent implementations must use protected storage. The optional
/// `dart_pdf_editor_secure_storage` package supplies `SecureIdentityStore`.
///
/// Implementations are async and backend-agnostic; the "Create signing
/// identity" dialog takes one so the host chooses where keys live (or passes
/// an [InMemoryIdentityStore] for an ephemeral, in-session identity).
abstract interface class PdfIdentityStore {
  /// The ids of every stored identity.
  Future<List<String>> ids();

  /// Loads the identity stored under [id], or null when there is none.
  Future<PdfSigningIdentity?> load(String id);

  /// Stores [identity] under [id], replacing any existing one.
  Future<void> save(String id, PdfSigningIdentity identity);

  /// Removes the identity stored under [id] (a no-op when absent).
  Future<void> delete(String id);
}

/// An in-memory [PdfIdentityStore] - identities live only for the session.
/// Useful for tests and for a "don't remember me" flow.
class InMemoryIdentityStore implements PdfIdentityStore {
  final Map<String, String> _pemById = {};

  @override
  Future<List<String>> ids() async => _pemById.keys.toList(growable: false);

  @override
  Future<PdfSigningIdentity?> load(String id) async {
    final pem = _pemById[id];
    return pem == null ? null : PdfSigningIdentity.fromPem(pem, name: id);
  }

  @override
  Future<void> save(String id, PdfSigningIdentity identity) async {
    _pemById[id] = identity.toPem();
  }

  @override
  Future<void> delete(String id) async {
    _pemById.remove(id);
  }
}
