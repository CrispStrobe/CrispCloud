import 'double_extension.dart';

/// Extension on [num] to provide smart rounding functionality.
extension NumExtension on num {
  /// Rounds the number to [decimals] decimal places.
  ///
  /// If the result has no fractional part, returns it as [int].
  /// Returns the original number if it's not a [double].
  num roundSmart(int decimals) {
    if (this is! double || isNaN || isInfinite) return this;

    final value = this as double;
    final result = value.roundToDecimals(decimals);

    // Return as int if there's no fractional part
    if (result == result.toInt()) return result.toInt();
    return result;
  }
}
