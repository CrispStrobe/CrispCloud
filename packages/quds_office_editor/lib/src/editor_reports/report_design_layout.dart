import 'dart:ui';

import 'package:quds_office_engine/quds_office_engine.dart';

/// One band on the design surface: a caption strip above its body.
class ReportDesignSlot {
  /// ReportDesignSlot API.
  const ReportDesignSlot({
    required this.band,
    required this.caption,
    required this.body,
  });

  /// band API.
  final ReportBand band;

  /// Caption strip, document points.
  final Rect caption;

  /// Band area, document points (its top is the band's y = 0).
  final Rect body;
}

/// Geometry of the band canvas in document points: x is the physical page
/// x, y stacks the bands top to bottom with a caption strip before each.
class ReportDesignLayout {
  ReportDesignLayout._(this.template, this.slots, this.height);

  /// Lays out [template]'s bands.
  factory ReportDesignLayout.of(ReportTemplate template) {
    final List<ReportDesignSlot> slots = <ReportDesignSlot>[];
    final double w = template.pageWidth;
    var y = 0.0;
    for (final ReportBand band in template.bands) {
      final Rect caption = Rect.fromLTWH(0, y, w, captionHeight);
      y += captionHeight;
      final double h = bodyHeight(template, band);
      slots.add(
        ReportDesignSlot(
          band: band,
          caption: caption,
          body: Rect.fromLTWH(0, y, w, h),
        ),
      );
      y += h;
    }
    return ReportDesignLayout._(template, slots, y);
  }

  /// Caption strip height, points.
  static const double captionHeight = 15;

  /// Smallest drawn band body, points.
  static const double minBody = 6;

  /// template API.
  final ReportTemplate template;

  /// Bands in order.
  final List<ReportDesignSlot> slots;

  /// Total height, points.
  final double height;

  /// Page width, points.
  double get width => template.pageWidth;

  /// Body height for [band]: its height or its content, whichever is taller.
  static double bodyHeight(ReportTemplate t, ReportBand band) {
    var h = band.height;
    for (final ReportElement e in band.elements) {
      final double bottom = e.y + visualHeight(t, band, e);
      if (bottom > h) {
        h = bottom;
      }
    }
    return h < minBody ? minBody : h;
  }

  /// Drawn height of [e]: tables show header, one body row, and totals.
  static double visualHeight(
    ReportTemplate t,
    ReportBand band,
    ReportElement e,
  ) {
    if (e is! ReportTableElement) {
      return e.height;
    }
    final TableRows rows = tableRows(t, band, e);
    final double needed = rows.header + rows.body + rows.footer;
    return e.height > needed ? e.height : needed;
  }

  /// Row heights of a table on the canvas.
  static TableRows tableRows(
    ReportTemplate t,
    ReportBand band,
    ReportTableElement e,
  ) {
    final double fs = e.fontSize ?? t.defaultFontSize;
    final double body =
        e.rowHeight ?? band.rowHeight ?? fs * 1.5 + 2 * e.padding;
    final double header = e.showHeader
        ? (e.headerHeight ?? e.rowHeight ?? band.rowHeight ?? body)
        : 0;
    return (
      header: header,
      body: body,
      footer: e.footerCells.isEmpty ? 0 : body,
    );
  }

  /// Slot of [kind], or null.
  ReportDesignSlot? slotOf(ReportBandKind kind) {
    for (final ReportDesignSlot s in slots) {
      if (s.band.kind == kind) {
        return s;
      }
    }
    return null;
  }

  /// Slot whose caption or body contains document y [y].
  ReportDesignSlot? slotAtY(double y) {
    for (final ReportDesignSlot s in slots) {
      if (y >= s.caption.top && y < s.body.bottom) {
        return s;
      }
    }
    return null;
  }

  /// Slot whose body contains document y [y], clamped to the first / last
  /// band when above or below every band.
  ReportDesignSlot? bodyNear(double y) {
    if (slots.isEmpty) {
      return null;
    }
    for (final ReportDesignSlot s in slots) {
      if (y >= s.caption.top && y < s.body.bottom) {
        return s;
      }
    }
    return y < slots.first.caption.top ? slots.first : slots.last;
  }

  /// Element box in document points.
  Rect elementRect(ReportDesignSlot slot, ReportElement e) => Rect.fromLTWH(
    template.elementLeft(e.x, e.width),
    slot.body.top + e.y,
    e.width,
    visualHeight(template, slot.band, e),
  );

  /// Slot holding element [id], with its element.
  (ReportDesignSlot, ReportElement)? find(String id) {
    for (final ReportDesignSlot s in slots) {
      for (final ReportElement e in s.band.elements) {
        if (e.id == id) {
          return (s, e);
        }
      }
    }
    return null;
  }

  /// Topmost element under document point [p]; [slop] widens thin shapes.
  (ReportDesignSlot, ReportElement)? hit(Offset p, {double slop = 3}) {
    for (final ReportDesignSlot s in slots.reversed) {
      for (final ReportElement e in s.band.elements.reversed) {
        final Rect r = elementRect(s, e);
        if (e is ReportShapeElement && e.kind == ReportShapeKind.line) {
          final (Offset a, Offset b) = lineEnds(r, e);
          if (_distanceToSegment(p, a, b) <= slop + e.strokeWidth / 2) {
            return (s, e);
          }
          continue;
        }
        if (r
            .inflate(r.width < 2 * slop || r.height < 2 * slop ? slop : 0)
            .contains(p)) {
          return (s, e);
        }
      }
    }
    return null;
  }

  /// Physical end points of a line in its box (rising flips when mirrored,
  /// matching the generator).
  (Offset, Offset) lineEnds(Rect r, ReportShapeElement e) {
    final bool rising = template.mirrored ? !e.rising : e.rising;
    return rising ? (r.bottomLeft, r.topRight) : (r.topLeft, r.bottomRight);
  }

  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final Offset ab = b - a;
    final double len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) {
      return (p - a).distance;
    }
    var t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2;
    t = t < 0 ? 0 : (t > 1 ? 1 : t);
    return (p - Offset(a.dx + ab.dx * t, a.dy + ab.dy * t)).distance;
  }
}

/// Header, body, and totals row heights of a table on the canvas.
typedef TableRows = ({double header, double body, double footer});
