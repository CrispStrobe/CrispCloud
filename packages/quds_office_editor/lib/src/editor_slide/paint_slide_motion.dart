import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

/// Canvas compositing for PowerPoint-like slide transitions and shape samples.
class PaintSlideMotion {
  /// applyShapeSample API.
  static void applyShapeSample(Canvas canvas, Rect rect, PmlAnimSample sample) {
    if (!sample.visible || sample.opacity <= 0.01) {
      return;
    }
    final Offset c = rect.center;
    canvas.translate(c.dx, c.dy);
    canvas.translate(sample.dx * rect.width, sample.dy * rect.height);
    if ((sample.scale - 1).abs() > 0.001) {
      canvas.scale(sample.scale);
    }
    if (sample.rotationDeg.abs() > 0.05) {
      canvas.rotate(sample.rotationDeg * math.pi / 180);
    }
    canvas.translate(-c.dx, -c.dy);
    if (sample.usesClip) {
      canvas.save();
      if (sample.splitClip) {
        canvas.clipPath(_splitPath(rect, sample.clipDir, sample.reveal));
      } else {
        canvas.clipRect(_wipeRect(rect, sample.clipDir, sample.reveal));
      }
    }
    if (sample.opacity < 0.999) {
      canvas.saveLayer(
        rect.inflate(rect.longestSide),
        Paint()..color = Color.fromRGBO(255, 255, 255, sample.opacity),
      );
    }
  }

  /// restoreShapeSample API.
  static void restoreShapeSample(Canvas canvas, PmlAnimSample sample) {
    if (!sample.visible || sample.opacity <= 0.01) {
      return;
    }
    if (sample.opacity < 0.999) {
      canvas.restore();
    }
    if (sample.usesClip) {
      canvas.restore();
    }
  }

  /// paintTransition API.
  static void paintTransition({
    required Canvas canvas,
    required Size size,
    required PmlSlideTransition transition,
    required double progress,
    required Color background,
    required void Function(Canvas canvas) paintOutgoing,
    required void Function(Canvas canvas) paintIncoming,
  }) {
    final double p = progress.clamp(0.0, 1.0);
    if (transition.isNone || p >= 1) {
      paintIncoming(canvas);
      return;
    }
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    switch (transition.kind) {
      case PmlTransitionKind.cut:
        paintIncoming(canvas);
      case PmlTransitionKind.fade:
        paintOutgoing(canvas);
        _fadeLayer(canvas, size, p, paintIncoming);
      case PmlTransitionKind.fadeThroughBlack:
      case PmlTransitionKind.flash:
        if (p < 0.5) {
          _fadeLayer(canvas, size, 1 - p * 2, paintOutgoing);
          canvas.drawRect(
            Offset.zero & size,
            Paint()
              ..color =
                  (transition.kind == PmlTransitionKind.flash
                          ? const Color(0xFFFFFFFF)
                          : const Color(0xFF000000))
                      .withValues(alpha: p * 2),
          );
        } else {
          canvas.drawRect(Offset.zero & size, Paint()..color = background);
          _fadeLayer(canvas, size, (p - 0.5) * 2, paintIncoming);
        }
      case PmlTransitionKind.push:
      case PmlTransitionKind.cover:
      case PmlTransitionKind.uncover:
      case PmlTransitionKind.reveal:
      case PmlTransitionKind.gallery:
        _pushFamily(canvas, size, transition, p, paintOutgoing, paintIncoming);
      case PmlTransitionKind.wipe:
      case PmlTransitionKind.split:
      case PmlTransitionKind.doors:
      case PmlTransitionKind.blinds:
      case PmlTransitionKind.comb:
      case PmlTransitionKind.strips:
      case PmlTransitionKind.randomBars:
      case PmlTransitionKind.checkerboard:
      case PmlTransitionKind.dissolve:
      case PmlTransitionKind.clock:
      case PmlTransitionKind.shapeCircle:
      case PmlTransitionKind.shapeDiamond:
      case PmlTransitionKind.shapePlus:
        paintOutgoing(canvas);
        canvas.save();
        _clipReveal(canvas, size, transition, p);
        paintIncoming(canvas);
        canvas.restore();
      case PmlTransitionKind.newsflash:
      case PmlTransitionKind.zoom:
        paintOutgoing(canvas);
        canvas.save();
        final Offset c = Offset(size.width / 2, size.height / 2);
        canvas.translate(c.dx, c.dy);
        final double s = transition.kind == PmlTransitionKind.newsflash
            ? 0.4 + 0.6 * p
            : p;
        canvas.scale(s <= 0.01 ? 0.01 : s);
        if (transition.kind == PmlTransitionKind.newsflash) {
          canvas.rotate((1 - p) * 0.45);
        }
        canvas.translate(-c.dx, -c.dy);
        _fadeLayer(canvas, size, p, paintIncoming);
        canvas.restore();
      case PmlTransitionKind.none:
        paintIncoming(canvas);
      case PmlTransitionKind.morph:
        paintOutgoing(canvas);
        _fadeLayer(canvas, size, p, paintIncoming);
    }
    canvas.restore();
  }

  static void _fadeLayer(
    Canvas canvas,
    Size size,
    double opacity,
    void Function(Canvas canvas) paint,
  ) {
    canvas.saveLayer(
      Offset.zero & size,
      Paint()..color = Color.fromRGBO(255, 255, 255, opacity.clamp(0, 1)),
    );
    paint(canvas);
    canvas.restore();
  }

  static void _pushFamily(
    Canvas canvas,
    Size size,
    PmlSlideTransition transition,
    double p,
    void Function(Canvas canvas) out,
    void Function(Canvas canvas) incoming,
  ) {
    final Offset delta = _dirDelta(transition.direction, size);
    final bool incomingMoves =
        transition.kind != PmlTransitionKind.uncover &&
        transition.kind != PmlTransitionKind.reveal;
    final bool outgoingMoves = transition.kind != PmlTransitionKind.cover;
    if (outgoingMoves) {
      canvas.save();
      canvas.translate(-delta.dx * p, -delta.dy * p);
      if (transition.kind == PmlTransitionKind.gallery) {
        canvas.scale(1 - 0.08 * p);
      }
      out(canvas);
      canvas.restore();
    } else {
      out(canvas);
    }
    canvas.save();
    if (incomingMoves) {
      canvas.translate(delta.dx * (1 - p), delta.dy * (1 - p));
    }
    if (transition.kind == PmlTransitionKind.reveal) {
      _fadeLayer(canvas, size, p, incoming);
    } else {
      incoming(canvas);
    }
    canvas.restore();
  }

  static Offset _dirDelta(PmlTransitionDir dir, Size size) {
    return switch (dir) {
      PmlTransitionDir.left ||
      PmlTransitionDir.horizontal ||
      PmlTransitionDir.inward ||
      PmlTransitionDir.outward => Offset(size.width, 0),
      PmlTransitionDir.right => Offset(-size.width, 0),
      PmlTransitionDir.up ||
      PmlTransitionDir.vertical => Offset(0, size.height),
      PmlTransitionDir.down => Offset(0, -size.height),
    };
  }

  static void _clipReveal(
    Canvas canvas,
    Size size,
    PmlSlideTransition transition,
    double p,
  ) {
    final Rect full = Offset.zero & size;
    switch (transition.kind) {
      case PmlTransitionKind.wipe:
        canvas.clipRect(_wipeRect(full, transition.direction, p));
      case PmlTransitionKind.split:
      case PmlTransitionKind.doors:
        canvas.clipPath(_splitPath(full, transition.direction, p));
      case PmlTransitionKind.blinds:
      case PmlTransitionKind.comb:
      case PmlTransitionKind.randomBars:
        canvas.clipPath(_barsPath(full, transition, p));
      case PmlTransitionKind.strips:
        canvas.clipPath(_stripsPath(full, p));
      case PmlTransitionKind.checkerboard:
      case PmlTransitionKind.dissolve:
        canvas.clipPath(
          _cellsPath(
            full,
            p,
            dissolve: transition.kind == PmlTransitionKind.dissolve,
          ),
        );
      case PmlTransitionKind.clock:
        canvas.clipPath(_clockPath(full, p));
      case PmlTransitionKind.shapeCircle:
        canvas.clipPath(
          Path()..addOval(
            Rect.fromCircle(
              center: full.center,
              radius: full.longestSide * p * 0.75,
            ),
          ),
        );
      case PmlTransitionKind.shapeDiamond:
        canvas.clipPath(_diamondPath(full, p));
      case PmlTransitionKind.shapePlus:
        canvas.clipPath(_plusPath(full, p));
      default:
        canvas.clipRect(full);
    }
  }

  static Rect _wipeRect(Rect full, PmlTransitionDir dir, double p) {
    return switch (dir) {
      PmlTransitionDir.right => Rect.fromLTWH(
        full.right - full.width * p,
        full.top,
        full.width * p,
        full.height,
      ),
      PmlTransitionDir.up => Rect.fromLTWH(
        full.left,
        full.top,
        full.width,
        full.height * p,
      ),
      PmlTransitionDir.down => Rect.fromLTWH(
        full.left,
        full.bottom - full.height * p,
        full.width,
        full.height * p,
      ),
      _ => Rect.fromLTWH(full.left, full.top, full.width * p, full.height),
    };
  }

  static Path _splitPath(Rect full, PmlTransitionDir dir, double p) {
    final Path path = Path();
    if (dir == PmlTransitionDir.vertical ||
        dir == PmlTransitionDir.up ||
        dir == PmlTransitionDir.down) {
      final double h = full.height * p / 2;
      path
        ..addRect(Rect.fromLTWH(full.left, full.top, full.width, h))
        ..addRect(Rect.fromLTWH(full.left, full.bottom - h, full.width, h));
    } else {
      final double w = full.width * p / 2;
      path
        ..addRect(Rect.fromLTWH(full.left, full.top, w, full.height))
        ..addRect(Rect.fromLTWH(full.right - w, full.top, w, full.height));
    }
    return path;
  }

  static Path _barsPath(Rect full, PmlSlideTransition t, double p) {
    final Path path = Path();
    const int n = 12;
    final bool vert =
        t.direction == PmlTransitionDir.up ||
        t.direction == PmlTransitionDir.down ||
        t.direction == PmlTransitionDir.vertical;
    for (int i = 0; i < n; i++) {
      var local = p;
      if (t.kind == PmlTransitionKind.randomBars) {
        local = ((i * 37 + 11) % 10) / 10 * 0.4 + p * 0.6;
        local = local.clamp(0, 1);
      }
      final bool flip = t.kind == PmlTransitionKind.comb && i.isOdd;
      if (vert) {
        final double h = full.height / n;
        final double left = flip ? full.right - full.width * local : full.left;
        path.addRect(
          Rect.fromLTWH(left, full.top + i * h, full.width * local, h),
        );
      } else {
        final double w = full.width / n;
        final double top = flip ? full.bottom - full.height * local : full.top;
        path.addRect(
          Rect.fromLTWH(full.left + i * w, top, w, full.height * local),
        );
      }
    }
    return path;
  }

  static Path _stripsPath(Rect full, double p) {
    final Path path = Path();
    const int n = 10;
    for (int i = 0; i < n; i++) {
      final double y = full.top + i * (full.height / n);
      path.addRect(
        Rect.fromLTWH(
          full.left,
          y,
          full.width * ((p + i / n) / 2).clamp(0, 1),
          full.height / n,
        ),
      );
    }
    return path;
  }

  static Path _cellsPath(Rect full, double p, {required bool dissolve}) {
    final Path path = Path();
    const int cols = 10;
    const int rows = 6;
    final double cw = full.width / cols;
    final double ch = full.height / rows;
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final double thresh = dissolve
            ? ((r * 13 + c * 7) % 17) / 17
            : ((r + c) / (rows + cols - 2));
        if (p >= thresh) {
          path.addRect(
            Rect.fromLTWH(
              full.left + c * cw,
              full.top + r * ch,
              cw + 0.5,
              ch + 0.5,
            ),
          );
        }
      }
    }
    return path;
  }

  static Path _clockPath(Rect full, double p) {
    return Path()
      ..moveTo(full.center.dx, full.center.dy)
      ..arcTo(
        Rect.fromCircle(center: full.center, radius: full.longestSide),
        -math.pi / 2,
        2 * math.pi * p,
        false,
      )
      ..close();
  }

  static Path _diamondPath(Rect full, double p) {
    final Offset c = full.center;
    final double w = full.width * p;
    final double h = full.height * p;
    return Path()
      ..moveTo(c.dx, c.dy - h)
      ..lineTo(c.dx + w, c.dy)
      ..lineTo(c.dx, c.dy + h)
      ..lineTo(c.dx - w, c.dy)
      ..close();
  }

  static Path _plusPath(Rect full, double p) {
    final double bw = full.width * 0.18 * (0.3 + p);
    final double bh = full.height * 0.18 * (0.3 + p);
    final Path path = Path()
      ..addRect(
        Rect.fromCenter(center: full.center, width: full.width * p, height: bh),
      )
      ..addRect(
        Rect.fromCenter(
          center: full.center,
          width: bw,
          height: full.height * p,
        ),
      );
    return path;
  }
}
