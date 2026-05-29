// lib/utils/formatters.dart
//
// Centralised formatting helpers used across the app for displaying
// file sizes, dates, and durations in a human-friendly way.

/// Format a byte count into a human-readable string (e.g. "1.2 MB").
///
/// Uses binary units (1 KB = 1024 bytes) to match OS file-manager conventions.
String formatBytes(int bytes) {
  if (bytes < 0) return '0 B';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes < 1024 * 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  return '${(bytes / (1024 * 1024 * 1024 * 1024)).toStringAsFixed(1)} TB';
}

/// Format a [DateTime] as a short relative or absolute string.
///
/// Returns "Today", "Yesterday", "N days ago" for recent dates,
/// and "YYYY-MM-DD" for older dates.
///
/// An optional [now] parameter allows callers (and tests) to pin the
/// reference point.
String formatDate(DateTime date, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final difference = reference.difference(date);

  if (difference.inDays == 0 && date.day == reference.day) {
    return 'Today';
  } else if (difference.inDays == 1 ||
      (difference.inDays == 0 && date.day != reference.day)) {
    // Handle the edge-case where the difference is < 24 h but crosses midnight.
    final yesterday = reference.subtract(const Duration(days: 1));
    if (date.year == yesterday.year &&
        date.month == yesterday.month &&
        date.day == yesterday.day) {
      return 'Yesterday';
    }
    if (difference.inDays == 1) return 'Yesterday';
    return 'Today';
  } else if (difference.inDays < 7) {
    return '${difference.inDays} days ago';
  } else {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

/// Format a [DateTime] with both date and time (e.g. "Today at 14:05").
String formatDateFull(DateTime date, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final today = DateTime(reference.year, reference.month, reference.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final fileDate = DateTime(date.year, date.month, date.day);

  String dateStr;
  if (fileDate == today) {
    dateStr = 'Today';
  } else if (fileDate == yesterday) {
    dateStr = 'Yesterday';
  } else {
    dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  final timeStr =
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  return '$dateStr at $timeStr';
}

/// Format a [Duration] as a compact human-readable string.
///
/// Examples: "3s", "2m 15s", "1h 30m", "2d 5h".
String formatDuration(Duration duration) {
  if (duration.isNegative) return '0s';

  final days = duration.inDays;
  final hours = duration.inHours % 24;
  final minutes = duration.inMinutes % 60;
  final seconds = duration.inSeconds % 60;

  if (days > 0) return '${days}d ${hours}h';
  if (hours > 0) return '${hours}h ${minutes}m';
  if (minutes > 0) return '${minutes}m ${seconds}s';
  return '${seconds}s';
}

/// Format a transfer speed in bytes/second as a human-readable string.
///
/// Example: "12.5 MB/s".
String formatSpeed(double bytesPerSecond) {
  if (bytesPerSecond <= 0) return '0 B/s';
  return '${formatBytes(bytesPerSecond.round())}/s';
}
