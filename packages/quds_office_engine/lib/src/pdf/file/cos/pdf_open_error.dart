/// Typed failure while opening or decoding a PDF file (ISO 32000).
enum PdfOpenError {
  /// Missing or invalid `%PDF-` header.
  badHeader,

  /// Cross-reference table or stream could not be parsed or repaired.
  badXref,

  /// Standard handler is present and no password was supplied.
  encrypted,

  /// Password did not unlock the Standard handler.
  wrongPassword,

  /// A required stream uses a filter this build cannot decode.
  unsupportedFilter,

  /// Public-key or unknown security handler.
  unsupportedHandler,

  /// Page count, stream size, or nesting exceeded the safety cap.
  limit,
}

/// Exception carrying a [PdfOpenError].
class PdfOpenException implements Exception {
  /// PdfOpenException API.
  const PdfOpenException(this.error, [this.message = '']);

  /// error API.
  final PdfOpenError error;

  /// message API.
  final String message;

  @override
  String toString() =>
      message.isEmpty ? 'PdfOpenException.$error' : 'PdfOpenException.$error: $message';
}

/// Stream filter that the interpreter must skip rather than crash.
class PdfFilterUnsupported implements Exception {
  /// PdfFilterUnsupported API.
  const PdfFilterUnsupported(this.filter);

  /// PDF filter name without the leading slash.
  final String filter;

  @override
  String toString() => 'PdfFilterUnsupported($filter)';
}
