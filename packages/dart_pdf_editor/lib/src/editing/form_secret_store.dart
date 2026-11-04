// CrispCloud modification: platform persistence is an optional companion.
// See UPSTREAM.md for provenance and patch details.
import 'dart:typed_data';

/// Where [PdfEditingController] keeps password-field values instead of the
/// PDF (ISO 32000 §12.7.4.3: readers "shall never store the value" of a
/// password field in the file).
///
/// Values are filed per document under a stable document id
/// ([pdfFormSecretDocumentId] - the trailer /ID, which incremental saves
/// carry forward) and per field under its fully qualified name, so
/// reopening the same document on the same device brings its passwords
/// back and a different document never sees them.
///
/// Mirrors [PdfIdentityStore]: async and backend-agnostic, with an
/// [InMemoryFormSecretStore] for tests and session-only use. The optional
/// `dart_pdf_editor_secure_storage` package supplies `SecureFormSecretStore`.
abstract interface class PdfFormSecretStore {
  /// Every value stored for [documentId], keyed by field name.
  Future<Map<String, String>> readAll(String documentId);

  /// The value stored for [fieldName] in [documentId], or null.
  Future<String?> read(String documentId, String fieldName);

  /// Stores [value] for [fieldName] in [documentId], replacing any other.
  Future<void> write(String documentId, String fieldName, String value);

  /// Forgets [fieldName]'s value in [documentId] (a no-op when absent).
  Future<void> remove(String documentId, String fieldName);

  /// Forgets every value stored for [documentId].
  Future<void> clearDocument(String documentId);
}

/// The [PdfFormSecretStore] key for a document whose permanent identifier
/// (`pdfPermanentDocumentId` in pdf_document) is [permanentId]: lowercase
/// hex.
String pdfFormSecretDocumentId(Uint8List permanentId) => [
      for (final b in permanentId) b.toRadixString(16).padLeft(2, '0'),
    ].join();

/// A [PdfFormSecretStore] held in memory - values live only as long as the
/// store object. Used for tests, and by hosts (the web app) that must not
/// persist passwords at all.
class InMemoryFormSecretStore implements PdfFormSecretStore {
  final Map<String, Map<String, String>> _byDocument = {};

  @override
  Future<Map<String, String>> readAll(String documentId) async =>
      Map.of(_byDocument[documentId] ?? const {});

  @override
  Future<String?> read(String documentId, String fieldName) async =>
      _byDocument[documentId]?[fieldName];

  @override
  Future<void> write(String documentId, String fieldName, String value) async {
    (_byDocument[documentId] ??= {})[fieldName] = value;
  }

  @override
  Future<void> remove(String documentId, String fieldName) async {
    final values = _byDocument[documentId];
    if (values == null) return;
    values.remove(fieldName);
    if (values.isEmpty) _byDocument.remove(documentId);
  }

  @override
  Future<void> clearDocument(String documentId) async {
    _byDocument.remove(documentId);
  }
}
