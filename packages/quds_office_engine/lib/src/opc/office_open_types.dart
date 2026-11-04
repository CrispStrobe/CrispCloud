import '../word/layout/word_layout.dart';
import '../word/model/wml_document.dart';

export '../pdf/file/io/pdf_open_payload.dart';

/// Progress while a package is decoded on a worker isolate.
class OfficeOpenProgress {
  /// Creates a progress tick.
  const OfficeOpenProgress({required this.value, required this.stage});

  /// 0–1.
  final double value;

  /// `archive`, `document`, `layout`, `formulas`, or `apply`.
  final String stage;
}

/// Word document plus its print layout after an isolate (or sync) open.
class WordOpenPayload {
  /// Creates a successful Word open result.
  const WordOpenPayload({required this.document, required this.laidOut});

  /// Parsed WordprocessingML document.
  final WmlDocument document;

  /// Paginated layout used for caret, print, and PDF.
  final LaidOutDocument laidOut;
}
