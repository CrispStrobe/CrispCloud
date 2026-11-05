import 'dart:math';

/// Extension for formatting an [int] value representing bytes.
extension IntFormatter on int {
  /// Converts a byte value into a human-readable string with units.
  ///
  /// Example:
  /// ```dart
  /// 1024.toBytesString(); // "1.00 KB"
  /// 1048576.toBytesString(1); // "1.0 MB"
  /// ```
  ///
  /// [decimals] specifies the number of decimal places (default is 2).
  String toBytesString([int decimals = 2]) {
    if (this <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = (log(this) / log(1024)).floor();
    var size = this / pow(1024, i);
    return '${size.toStringAsFixed(decimals)} ${suffixes[i]}';
  }
}
