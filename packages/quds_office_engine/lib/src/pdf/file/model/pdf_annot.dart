/// Markup or navigation annotation (ISO 32000-1 §12.5).
class PdfAnnot {
  /// PdfAnnot API.
  PdfAnnot({
    required this.id,
    required this.subtype,
    required this.rect,
    this.quads = const <PdfQuad>[],
    this.contents = '',
    this.color = 0xFFFFE066,
    this.uri,
    this.goToPage,
    this.goToY,
    this.ink = const <List<PdfPoint>>[],
    this.fieldName = '',
    this.objectId,
  });

  /// Stable editor id (not the COS object number).
  final int id;

  /// subtype API.
  final String subtype;

  /// rect API.
  PdfRect rect;

  /// quads API.
  List<PdfQuad> quads;

  /// contents API.
  String contents;

  /// ARGB color.
  int color;

  /// uri API.
  String? uri;

  /// goToPage API.
  int? goToPage;

  /// goToY API.
  double? goToY;

  /// ink API.
  List<List<PdfPoint>> ink;

  /// fieldName API.
  String fieldName;

  /// COS object number when loaded from the file.
  int? objectId;
}

/// Class PdfRect.
class PdfRect {
  /// PdfRect API.
  const PdfRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  /// x API.
  final double x;

  /// y API.
  final double y;

  /// width API.
  final double width;

  /// height API.
  final double height;

  /// contains API.
  bool contains(double px, double py) {
    final double left = width < 0 ? x + width : x;
    final double top = height < 0 ? y + height : y;
    final double w = width.abs();
    final double h = height.abs();
    return px >= left && py >= top && px <= left + w && py <= top + h;
  }
}

/// Class PdfQuad.
class PdfQuad {
  /// PdfQuad API.
  const PdfQuad({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.x3,
    required this.y3,
    required this.x4,
    required this.y4,
  });

  /// x1 API.
  final double x1;

  /// y1 API.
  final double y1;

  /// x2 API.
  final double x2;

  /// y2 API.
  final double y2;

  /// x3 API.
  final double x3;

  /// y3 API.
  final double y3;

  /// x4 API.
  final double x4;

  /// y4 API.
  final double y4;
}

/// Class PdfPoint.
class PdfPoint {
  /// PdfPoint API.
  const PdfPoint(this.x, this.y);

  /// x API.
  final double x;

  /// y API.
  final double y;
}
