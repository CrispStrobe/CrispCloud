import '../model/pdf_page_info.dart';

/// Maps unrotated crop-space points into the clockwise `/Rotate` view.
///
/// `/Rotate` turns the page 90° at a time. It does not rewrite [PdfBox] or
/// reflow content into the other orientation. [PdfPageInfo.width] is only the
/// size of the view after that turn.
abstract final class PdfPageView {
  /// Content point `(x, y)` (top-left of the unrotated crop) in view space.
  static ({double x, double y}) toView(
    PdfPageInfo page,
    double x,
    double y,
  ) {
    final double w = page.cropBox.width;
    final double h = page.cropBox.height;
    return switch (_norm(page.rotate)) {
      90 => (x: h - y, y: x),
      180 => (x: w - x, y: h - y),
      270 => (x: y, y: w - x),
      _ => (x: x, y: y),
    };
  }

  /// Inverse of [toView]. Hit-testing uses this before content coordinates.
  static ({double x, double y}) fromView(
    PdfPageInfo page,
    double x,
    double y,
  ) {
    final double w = page.cropBox.width;
    final double h = page.cropBox.height;
    return switch (_norm(page.rotate)) {
      90 => (x: y, y: h - x),
      180 => (x: w - x, y: h - y),
      270 => (x: w - y, y: x),
      _ => (x: x, y: y),
    };
  }

  /// Clockwise quarter-turns only. Other values are rejected.
  static int normalizeQuarter(int degrees) {
    final int turned = degrees % 360;
    final int norm = turned < 0 ? turned + 360 : turned;
    if (norm % 90 != 0) {
      throw ArgumentError('PDF rotation is 90° steps, not an orientation swap');
    }
    return norm;
  }

  static int _norm(int degrees) => normalizeQuarter(degrees);
}
