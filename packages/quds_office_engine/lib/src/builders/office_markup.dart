import '../xml/xml_reader.dart';

/// Shared OOXML text helpers used by the document builders.
abstract final class OfficeMarkup {
  /// escape API.
  static String escape(String text) => encodeXmlText(text);

  /// escapeAttr API.
  static String escapeAttr(String text) => encodeXmlAttribute(text);

  /// rgb API.
  static String rgb(String hex) {
    final String h = hex.replaceAll('#', '').toUpperCase();
    if (h.length == 8) {
      return h;
    }
    if (h.length == 6) {
      return 'FF$h';
    }
    if (h.length == 3) {
      return 'FF${h[0]}${h[0]}${h[1]}${h[1]}${h[2]}${h[2]}';
    }
    return 'FF000000';
  }

  /// srgb API.
  static String srgb(String hex) {
    final String full = rgb(hex);
    return full.length == 8 ? full.substring(2) : full;
  }

  /// colName API.
  static String colName(int zeroBased) {
    var n = zeroBased;
    final List<int> chars = <int>[];
    while (n >= 0) {
      chars.add(65 + (n % 26));
      n = (n ~/ 26) - 1;
    }
    return String.fromCharCodes(chars.reversed);
  }

  /// sheetName API.
  static String sheetName(String name, int fallbackId) {
    var n = name.replaceAll(RegExp(r'[\\/*?:\[\]]'), '_').trim();
    if (n.isEmpty) {
      n = 'Sheet$fallbackId';
    }
    if (n.length > 31) {
      n = n.substring(0, 31);
    }
    return n;
  }
}

/// Class ChartPoint.
class ChartPoint {
  /// ChartPoint API.
  const ChartPoint({
    required this.label,
    required this.value,
    this.color = '4472C4',
    this.x,
    this.size,
  });

  /// label API.
  final String label;

  /// value API.
  final double value;

  /// color API.
  final String color;

  /// Scatter / bubble X. Null uses the category index.
  final double? x;

  /// Bubble size. Null uses a fixed marker.
  final double? size;

  /// copyWith API.
  ChartPoint copyWith({
    String? label,
    double? value,
    String? color,
    double? x,
    double? size,
  }) {
    return ChartPoint(
      label: label ?? this.label,
      value: value ?? this.value,
      color: color ?? this.color,
      x: x ?? this.x,
      size: size ?? this.size,
    );
  }
}

/// Named series used by multi-series line / area / stacked charts.
class ChartSeries {
  /// ChartSeries API.
  const ChartSeries({required this.name, required this.points, this.color});

  /// name API.
  final String name;

  /// points API.
  final List<ChartPoint> points;

  /// color API.
  final String? color;
}
