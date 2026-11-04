import 'dart:typed_data';

import 'pdf_annot.dart';

/// Catalog `/ViewerPreferences` (ISO 32000-1 §12.2).
class PdfViewerPrefs {
  /// PdfViewerPrefs API.
  const PdfViewerPrefs({
    this.direction = 'L2R',
    this.fitWindow = false,
    this.centerWindow = false,
    this.hideToolbar = false,
    this.hideMenubar = false,
    this.hideWindowUI = false,
    this.displayDocTitle = false,
  });

  /// `/Direction`: `L2R` or `R2L`.
  final String direction;

  /// `/FitWindow`.
  final bool fitWindow;

  /// `/CenterWindow`.
  final bool centerWindow;

  /// `/HideToolbar`.
  final bool hideToolbar;

  /// `/HideMenubar`.
  final bool hideMenubar;

  /// `/HideWindowUI`.
  final bool hideWindowUI;

  /// `/DisplayDocTitle`.
  final bool displayDocTitle;
}

/// Optional content group (ISO 32000-1 §8.11).
class PdfLayer {
  /// PdfLayer API.
  PdfLayer({
    required this.name,
    required this.visible,
    this.objectId,
  });

  /// name API.
  final String name;

  /// visible API.
  bool visible;

  /// objectId API.
  final int? objectId;
}

/// Embedded file from the `/EmbeddedFiles` name tree.
class PdfEmbeddedFile {
  /// PdfEmbeddedFile API.
  const PdfEmbeddedFile({required this.name, required this.bytes});

  /// name API.
  final String name;

  /// bytes API.
  final Uint8List bytes;
}

/// How a signature field is treated (P6.6).
enum PdfSignatureStatus {
  /// No `/Sig` fields.
  none,

  /// `/ByteRange` covers the file except `/Contents`, but CMS was not compared.
  unverified,

  /// CMS `messageDigest` matches the ByteRange payload (no RSA / trust list).
  valid,

  /// CMS parsed, but the digest does not match the ByteRange payload.
  invalid,

  /// `/ByteRange` missing or does not cover the file (excluding `/Contents`).
  broken,

  /// Filter / SubFilter / digest algorithm is not a CMS name we inspect.
  unsupported,
}

/// Tagged-PDF node from `/StructTreeRoot` (ISO 32000-1 §14.7). Read-only.
class PdfStructNode {
  /// PdfStructNode API.
  PdfStructNode({
    required this.role,
    this.alt = '',
    this.actualText = '',
    List<PdfStructNode>? kids,
    this.pageIndex,
    this.mcid,
  }) : kids = kids ?? <PdfStructNode>[];

  /// Structure type (`P`, `H1`, `Document`, `MCR`, …).
  final String role;

  /// `/Alt` when present.
  final String alt;

  /// `/ActualText` when present.
  final String actualText;

  /// kids API.
  final List<PdfStructNode> kids;

  /// Page index for an MCR / kid with `/Pg`.
  final int? pageIndex;

  /// Marked-content identifier.
  final int? mcid;
}

/// Signature field snapshot. Creation of new signatures is out of Phase 6.
class PdfSignatureInfo {
  /// PdfSignatureInfo API.
  const PdfSignatureInfo({
    required this.fieldName,
    required this.status,
    this.byteRangeLength = 0,
  });

  /// fieldName API.
  final String fieldName;

  /// status API.
  final PdfSignatureStatus status;

  /// Length of `/ByteRange` when present.
  final int byteRangeLength;
}

/// Visual markup vs content-removal redaction (ISO 32000-1 §12.5.6).
enum PdfRedactMode {
  /// Annotation only; glyphs stay in the stream.
  visual,

  /// Overlay + hide matching extractable text. Not a certified sanitizer.
  removeContent,
}

/// One redaction rectangle recorded on a page.
class PdfRedactRect {
  /// PdfRedactRect API.
  const PdfRedactRect({required this.pageIndex, required this.rect});

  /// pageIndex API.
  final int pageIndex;

  /// rect API.
  final PdfRect rect;
}
