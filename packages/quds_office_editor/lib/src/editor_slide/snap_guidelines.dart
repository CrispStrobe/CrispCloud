import 'dart:ui';

/// Snap-to-object guides. Only the lines that actually catch the moving
/// shape are kept for painting — PowerPoint-style, not a full lattice.
class SnapGuidelines {
  /// SnapGuidelines API.
  SnapGuidelines({this.threshold = 4});

  /// threshold API.
  final double threshold;
  final List<double> _vertical = <double>[];
  final List<double> _horizontal = <double>[];
  final List<double> _activeVertical = <double>[];
  final List<double> _activeHorizontal = <double>[];

  /// activeGuideCount API.
  int get activeGuideCount => _activeVertical.length + _activeHorizontal.length;

  /// clear API.
  void clear() {
    _vertical.clear();
    _horizontal.clear();
    _activeVertical.clear();
    _activeHorizontal.clear();
  }

  /// addTarget API.
  void addTarget(Rect box) {
    _addUnique(_vertical, box.left);
    _addUnique(_vertical, box.center.dx);
    _addUnique(_vertical, box.right);
    _addUnique(_horizontal, box.top);
    _addUnique(_horizontal, box.center.dy);
    _addUnique(_horizontal, box.bottom);
  }

  /// addSlide API.
  void addSlide(Size size) {
    addTarget(Rect.fromLTWH(0, 0, size.width, size.height));
  }

  /// snap API.
  Offset snap(Rect moving) {
    _activeVertical.clear();
    _activeHorizontal.clear();
    final double? dx = _bestDelta(<double>[
      moving.left,
      moving.center.dx,
      moving.right,
    ], _vertical);
    final double? dy = _bestDelta(<double>[
      moving.top,
      moving.center.dy,
      moving.bottom,
    ], _horizontal);
    if (dx != null) {
      _collectActive(
        <double>[moving.left + dx, moving.center.dx + dx, moving.right + dx],
        _vertical,
        _activeVertical,
      );
    }
    if (dy != null) {
      _collectActive(
        <double>[moving.top + dy, moving.center.dy + dy, moving.bottom + dy],
        _horizontal,
        _activeHorizontal,
      );
    }
    return Offset(dx ?? 0, dy ?? 0);
  }

  /// paint API.
  void paint(
    Canvas canvas,
    Size size, {
    Color color = const Color(0xFFFF4FA0),
  }) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (final double x in _activeVertical) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (final double y in _activeHorizontal) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  double? _bestDelta(List<double> edges, List<double> guides) {
    var best = threshold + 1;
    double? delta;
    for (final double edge in edges) {
      for (final double g in guides) {
        final double d = g - edge;
        if (d.abs() <= threshold && d.abs() < best) {
          best = d.abs();
          delta = d;
        }
      }
    }
    return delta;
  }

  void _collectActive(
    List<double> edges,
    List<double> guides,
    List<double> into,
  ) {
    for (final double edge in edges) {
      for (final double g in guides) {
        if ((edge - g).abs() <= 0.51) {
          _addUnique(into, g);
        }
      }
    }
  }

  static void _addUnique(List<double> into, double value) {
    for (final double existing in into) {
      if ((existing - value).abs() < 0.5) {
        return;
      }
    }
    into.add(value);
  }
}
