/// Display/input units only. Document geometry remains in points.
enum OfficeLengthUnit {
  inches,
  centimeters,
  millimeters;

  String get suffix => switch (this) {
    inches => 'in',
    centimeters => 'cm',
    millimeters => 'mm',
  };
  double get pointsPerUnit => switch (this) {
    inches => 72,
    centimeters => 72 / 2.54,
    millimeters => 72 / 25.4,
  };
  double fromPoints(double value) => value / pointsPerUnit;
  double toPoints(double value) => value * pointsPerUnit;
  double get rulerMajorPoints => this == inches ? 72 : 72 / 2.54;
  int get rulerDivisions => this == inches ? 8 : 10;
  int get rulerLabelMultiplier => this == millimeters ? 10 : 1;
  double get snapPoints => this == inches ? 4.5 : 72 / 25.4;

  /// Explicit suffixes override the selected unit; decimal commas are accepted.
  double? parsePoints(String input) {
    final match = RegExp(
      r'^\s*([+-]?(?:\d+(?:[.,]\d*)?|[.,]\d+))\s*(mm|cm|inches|inch|in|pt|["″])?\s*$',
      caseSensitive: false,
    ).firstMatch(input);
    if (match == null) return null;
    final number = double.tryParse(match[1]!.replaceAll(',', '.'));
    if (number == null || !number.isFinite) return null;
    final unit = match[2]?.toLowerCase();
    final result = switch (unit) {
      'mm' => millimeters.toPoints(number),
      'cm' => centimeters.toPoints(number),
      'in' || 'inch' || 'inches' || '"' || '″' => inches.toPoints(number),
      'pt' => number,
      _ => toPoints(number),
    };
    return result.isFinite ? result : null;
  }
}
