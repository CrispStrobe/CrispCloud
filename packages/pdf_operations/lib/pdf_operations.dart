/// Byte-in, byte-out PDF workflows shared by graphical and command-line hosts.
///
/// This library never reads files, connects to a service, or writes a result.
/// Hosts own credentials, storage, overwrite consent, and execution scheduling.
library;

export 'package:pdf_document/pdf_document.dart'
    show PdfEmbeddedFont, PdfRect, PdfOcrSpan;

export 'src/models.dart';
export 'src/page_range.dart';
export 'src/service.dart';
