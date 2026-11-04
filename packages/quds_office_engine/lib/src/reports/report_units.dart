/// Length units and colors used by `.qrep` report templates.
library;

/// Length unit accepted by template attributes such as `x="10mm"`.
enum ReportUnit {
  /// Typographic point (1/72 inch).
  pt('pt', 1),

  /// Millimetre.
  mm('mm', 72 / 25.4),

  /// Centimetre.
  cm('cm', 72 / 2.54),

  /// Inch.
  inch('in', 72),

  /// CSS pixel at 96 DPI.
  px('px', 0.75);

  const ReportUnit(this.suffix, this.points);

  /// Attribute suffix (`mm`, `pt`, ...).
  final String suffix;

  /// Points per one unit.
  final double points;

  /// Unit for [suffix], or null when unknown.
  static ReportUnit? fromSuffix(String suffix) {
    final String s = suffix.trim().toLowerCase();
    for (final ReportUnit unit in ReportUnit.values) {
      if (unit.suffix == s) {
        return unit;
      }
    }
    if (s == 'inch' || s == '"') {
      return ReportUnit.inch;
    }
    return null;
  }
}

/// Thrown when a length or color attribute cannot be parsed.
class ReportFormatException implements Exception {
  /// ReportFormatException API.
  const ReportFormatException(this.message);

  /// Human-readable reason.
  final String message;

  @override
  String toString() => 'ReportFormatException: $message';
}

/// Length parsing and formatting. All engine geometry is in points.
abstract final class ReportUnits {
  static final RegExp _length = RegExp(
    r'^\s*([+-]?(?:\d+\.?\d*|\.\d+))\s*([a-zA-Z"]*)\s*$',
  );

  /// Parses `20mm`, `1.5cm`, `12pt`, `1in`, `16px`, or a bare number in
  /// [defaultUnit]. Returns points.
  static double parse(String raw, {ReportUnit defaultUnit = ReportUnit.mm}) {
    final RegExpMatch? m = _length.firstMatch(raw);
    if (m == null) {
      throw ReportFormatException('Invalid length "$raw"');
    }
    final double value = double.parse(m.group(1)!);
    final String suffix = m.group(2) ?? '';
    if (suffix.isEmpty) {
      return value * defaultUnit.points;
    }
    final ReportUnit? unit = ReportUnit.fromSuffix(suffix);
    if (unit == null) {
      throw ReportFormatException('Unknown length unit "$suffix" in "$raw"');
    }
    return value * unit.points;
  }

  /// Like [parse] but returns null for malformed input.
  static double? tryParse(
    String? raw, {
    ReportUnit defaultUnit = ReportUnit.mm,
  }) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    final RegExpMatch? m = _length.firstMatch(raw);
    if (m == null) {
      return null;
    }
    final String suffix = m.group(2) ?? '';
    final ReportUnit? unit = suffix.isEmpty
        ? defaultUnit
        : ReportUnit.fromSuffix(suffix);
    if (unit == null) {
      return null;
    }
    return double.parse(m.group(1)!) * unit.points;
  }

  /// Formats [points] in [unit] with at most two decimals (`12.5mm`).
  static String format(double points, {ReportUnit unit = ReportUnit.mm}) {
    final double v = points / unit.points;
    return '${trimNumber(v)}${unit.suffix}';
  }

  /// `12.50` → `12.5`, `3.00` → `3`.
  static String trimNumber(double value, {int decimals = 2}) {
    final double rounded = double.parse(value.toStringAsFixed(decimals));
    if (rounded == rounded.roundToDouble()) {
      return rounded.round().toString();
    }
    String s = rounded.toStringAsFixed(decimals);
    while (s.endsWith('0')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }
}

/// Opaque or translucent sRGB color.
class ReportColor {
  /// ReportColor API.
  const ReportColor(this.argb);

  /// From RGB components (0–255).
  const ReportColor.rgb(int r, int g, int b)
    : argb = 0xFF000000 | (r << 16) | (g << 8) | b;

  /// 0xAARRGGBB.
  final int argb;

  /// black API.
  static const ReportColor black = ReportColor(0xFF000000);

  /// white API.
  static const ReportColor white = ReportColor(0xFFFFFFFF);

  /// transparent API.
  static const ReportColor transparent = ReportColor(0x00000000);

  /// Alpha 0–255.
  int get alpha => (argb >> 24) & 0xFF;

  /// Red 0–255.
  int get red => (argb >> 16) & 0xFF;

  /// Green 0–255.
  int get green => (argb >> 8) & 0xFF;

  /// Blue 0–255.
  int get blue => argb & 0xFF;

  /// True when fully transparent.
  bool get isTransparent => alpha == 0;

  /// `RRGGBB` without `#` (PDF / OOXML form).
  String get hex =>
      (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

  /// `#RRGGBB`, or `#AARRGGBB` when translucent.
  String get cssHex => alpha == 0xFF
      ? '#$hex'
      : '#${argb.toRadixString(16).padLeft(8, '0').toUpperCase()}';

  static const Map<String, int> _named = <String, int>{
    'black': 0x000000,
    'white': 0xFFFFFF,
    'red': 0xFF0000,
    'green': 0x008000,
    'lime': 0x00FF00,
    'blue': 0x0000FF,
    'navy': 0x000080,
    'yellow': 0xFFFF00,
    'orange': 0xFFA500,
    'purple': 0x800080,
    'gray': 0x808080,
    'grey': 0x808080,
    'silver': 0xC0C0C0,
    'lightgray': 0xD3D3D3,
    'lightgrey': 0xD3D3D3,
    'darkgray': 0xA9A9A9,
    'darkgrey': 0xA9A9A9,
    'maroon': 0x800000,
    'olive': 0x808000,
    'teal': 0x008080,
    'aqua': 0x00FFFF,
    'cyan': 0x00FFFF,
    'fuchsia': 0xFF00FF,
    'magenta': 0xFF00FF,
    'brown': 0xA52A2A,
    'gold': 0xFFD700,
    'pink': 0xFFC0CB,
  };

  /// Parses `#RGB`, `#RRGGBB`, `#AARRGGBB`, bare hex, or a CSS color name.
  static ReportColor? tryParse(String? raw) {
    if (raw == null) {
      return null;
    }
    final String s = raw.trim();
    if (s.isEmpty) {
      return null;
    }
    final String lower = s.toLowerCase();
    if (lower == 'transparent' || lower == 'none') {
      return transparent;
    }
    final int? named = _named[lower];
    if (named != null) {
      return ReportColor(0xFF000000 | named);
    }
    final String h = s.startsWith('#') ? s.substring(1) : s;
    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(h)) {
      return null;
    }
    switch (h.length) {
      case 3:
        final int n = int.parse(h, radix: 16);
        final int r = (n >> 8) & 0xF;
        final int g = (n >> 4) & 0xF;
        final int b = n & 0xF;
        return ReportColor.rgb(r * 17, g * 17, b * 17);
      case 6:
        return ReportColor(0xFF000000 | int.parse(h, radix: 16));
      case 8:
        return ReportColor(int.parse(h, radix: 16));
    }
    return null;
  }

  @override
  bool operator ==(Object other) => other is ReportColor && other.argb == argb;

  @override
  int get hashCode => argb.hashCode;

  @override
  String toString() => cssHex;
}
