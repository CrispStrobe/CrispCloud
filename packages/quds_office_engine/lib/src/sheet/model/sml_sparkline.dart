import 'sml_workbook.dart';

/// In-cell sparkline (line or column).
enum SmlSparklineKind { line, column }

/// A sparkline bound to a source range and drawn in [anchor].
class SmlSparkline {
  /// SmlSparkline API.
  SmlSparkline({
    required this.source,
    required this.anchor,
    this.kind = SmlSparklineKind.line,
  });

  /// source API.
  SmlRange source;

  /// Cell that hosts the sparkline.
  SmlCellRef anchor;

  /// kind API.
  SmlSparklineKind kind;

  /// Numeric samples from [sheet].
  List<double> samples(SmlWorksheet sheet) {
    final List<double> values = <double>[];
    for (final SmlCellRef ref in source.cells) {
      final double? n = sheet.cell(ref).asNumber;
      if (n != null) {
        values.add(n);
      }
    }
    return values;
  }
}
