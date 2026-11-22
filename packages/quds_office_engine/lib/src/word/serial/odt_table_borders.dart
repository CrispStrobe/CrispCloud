/// The solid, uniform stroke shared by one editable native table.
///
/// Widths use Word's eighth-point precision. Restricting the range to the
/// ordinary line-border envelope avoids accepting a value that changes on a
/// subsequent DOCX save. ODF colors are explicit opaque RGB values.
final class OdtTableBorder {
  OdtTableBorder(double width, String color)
    : width = _width(width),
      color = _color(color);

  final double width;
  final String color;

  static double _width(double value) {
    if (!value.isFinite ||
        value < 0.25 ||
        value > 12 ||
        (value * 8 - (value * 8).round()).abs() > 0.000001) {
      throw UnsupportedError(
        'Editable ODT table borders need widths from 0.25 to 12 points in '
        'exact eighth-point steps.',
      );
    }
    return (value * 8).round() / 8;
  }

  static String _color(String value) {
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(value)) {
      throw UnsupportedError('Editable ODT table borders need opaque RGB.');
    }
    return value.toUpperCase();
  }

  String get odf => '${width.toStringAsFixed(3)}pt solid #$color';

  @override
  bool operator ==(Object other) =>
      other is OdtTableBorder && width == other.width && color == other.color;

  @override
  int get hashCode => Object.hash(width, color);
}
