import 'package:pdf_cos/pdf_cos.dart';

/// Reads a COS rectangle array (`[x1 y1 x2 y2]`), normalizing the corner
/// order as required for boxes (§7.9.5). Returns null on anything malformed.
PdfRect? pdfRectFrom(CosDocument cos, CosObject? value) {
  final array = cos.resolve(value);
  if (array is! CosArray || array.length < 4) return null;
  final values = <double>[];
  for (var i = 0; i < 4; i++) {
    final n = cos.resolve(array[i]);
    if (n is CosInteger) {
      values.add(n.value.toDouble());
    } else if (n is CosReal) {
      values.add(n.value);
    } else {
      return null;
    }
  }
  return PdfRect.normalized(values[0], values[1], values[2], values[3]);
}

/// A rectangle in PDF user space (origin bottom-left, y grows upward).
class PdfRect {
  const PdfRect(this.left, this.bottom, this.right, this.top);

  /// Builds a rect with corners sorted so width and height are non-negative,
  /// as required for boxes (§7.9.5).
  factory PdfRect.normalized(double x1, double y1, double x2, double y2) =>
      PdfRect(
        x1 < x2 ? x1 : x2,
        y1 < y2 ? y1 : y2,
        x1 < x2 ? x2 : x1,
        y1 < y2 ? y2 : y1,
      );

  final double left;
  final double bottom;
  final double right;
  final double top;

  double get width => right - left;
  double get height => top - bottom;

  bool contains(double x, double y) =>
      x >= left && x <= right && y >= bottom && y <= top;

  PdfRect intersect(PdfRect other) => PdfRect(
        left > other.left ? left : other.left,
        bottom > other.bottom ? bottom : other.bottom,
        right < other.right ? right : other.right,
        top < other.top ? top : other.top,
      );

  @override
  bool operator ==(Object other) =>
      other is PdfRect &&
      other.left == left &&
      other.bottom == bottom &&
      other.right == right &&
      other.top == top;

  @override
  int get hashCode => Object.hash(left, bottom, right, top);

  @override
  String toString() => 'PdfRect($left, $bottom, $right, $top)';
}
