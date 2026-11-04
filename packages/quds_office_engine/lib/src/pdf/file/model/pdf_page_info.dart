/// Page boxes and rotation after inheritance (ISO 32000-1 §7.7.3 / §14.11.2).
class PdfPageInfo {
  /// PdfPageInfo API.
  const PdfPageInfo({
    required this.index,
    required this.mediaBox,
    required this.cropBox,
    this.bleedBox,
    this.trimBox,
    this.artBox,
    this.rotate = 0,
    this.label = '',
  });

  /// Zero-based page index.
  final int index;

  /// mediaBox API.
  final PdfBox mediaBox;

  /// cropBox API.
  final PdfBox cropBox;

  /// bleedBox API.
  final PdfBox? bleedBox;

  /// trimBox API.
  final PdfBox? trimBox;

  /// artBox API.
  final PdfBox? artBox;

  /// /Rotate in degrees (0, 90, 180, 270).
  final int rotate;

  /// Page label when `/PageLabels` is present.
  final String label;

  /// Paint width after rotation.
  double get width =>
      rotate == 90 || rotate == 270 ? cropBox.height : cropBox.width;

  /// Paint height after rotation.
  double get height =>
      rotate == 90 || rotate == 270 ? cropBox.width : cropBox.height;
}

/// Axis-aligned PDF rectangle in user space.
class PdfBox {
  /// PdfBox API.
  const PdfBox({
    required this.llx,
    required this.lly,
    required this.urx,
    required this.ury,
  });

  /// llx API.
  final double llx;

  /// lly API.
  final double lly;

  /// urx API.
  final double urx;

  /// ury API.
  final double ury;

  /// width API.
  double get width => (urx - llx).abs();

  /// height API.
  double get height => (ury - lly).abs();
}

/// Document Info dictionary (ISO 32000-1 §14.3.3).
class PdfDocInfo {
  /// PdfDocInfo API.
  const PdfDocInfo({
    this.title = '',
    this.author = '',
    this.subject = '',
    this.keywords = '',
    this.creator = '',
    this.producer = '',
    this.xmp = '',
    this.pdfAPart,
    this.pdfAConformance,
  });

  /// title API.
  final String title;

  /// author API.
  final String author;

  /// subject API.
  final String subject;

  /// keywords API.
  final String keywords;

  /// creator API.
  final String creator;

  /// producer API.
  final String producer;

  /// Raw XMP packet when present.
  final String xmp;

  /// pdfAPart API.
  final String? pdfAPart;

  /// pdfAConformance API.
  final String? pdfAConformance;
}

/// Outline node (ISO 32000-1 §12.3.3).
class PdfOutlineNode {
  /// PdfOutlineNode API.
  PdfOutlineNode({
    required this.title,
    this.pageIndex,
    this.destY,
    this.uri,
    List<PdfOutlineNode>? children,
  }) : children = children ?? <PdfOutlineNode>[];

  /// title API.
  final String title;

  /// pageIndex API.
  final int? pageIndex;

  /// destY API.
  final double? destY;

  /// uri API.
  final String? uri;

  /// children API.
  final List<PdfOutlineNode> children;
}

/// Resolved navigation action the host may follow.
class PdfLinkAction {
  /// PdfLinkAction API.
  const PdfLinkAction({
    this.uri,
    this.pageIndex,
    this.destY,
    this.remoteFile,
    this.kind = PdfLinkKind.uri,
  });

  /// uri API.
  final String? uri;

  /// pageIndex API.
  final int? pageIndex;

  /// destY API.
  final double? destY;

  /// remoteFile API.
  final String? remoteFile;

  /// kind API.
  final PdfLinkKind kind;
}

/// Class PdfLinkKind.
enum PdfLinkKind { uri, goTo, goToR, named, ignored }
