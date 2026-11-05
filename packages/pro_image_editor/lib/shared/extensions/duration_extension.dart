/// Extension for formatting [Duration] as a time string.
extension DurationFormatter on Duration {
  /// Converts the duration to a formatted time string (MM:SS).
  ///
  /// Example:
  /// ```dart
  /// Duration(seconds: 75).toTimeString(); // "01:15"
  /// ```
  String toTimeString() {
    int totalSeconds = inSeconds;
    int minutes = totalSeconds ~/ 60;
    int seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
}
