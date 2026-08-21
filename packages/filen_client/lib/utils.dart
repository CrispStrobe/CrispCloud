/// Utility functions for the Filen CLI.
import 'package:crypto/crypto.dart' as crypto;

/// Helper class to capture hash results from chunked hash computation.
class DigestSink implements Sink<crypto.Digest> {
  crypto.Digest? value;
  @override
  void add(crypto.Digest data) {
    value = data;
  }

  @override
  void close() {}
}

/// Format a byte count into a human-readable string (e.g., "1.5 MB").
String formatSize(dynamic b) {
  int bytes = (b is int) ? b : int.tryParse(b.toString()) ?? 0;
  if (bytes <= 0) return '0 B';
  const s = ['B', 'KB', 'MB', 'GB', 'TB'];
  var i = 0;
  double v = bytes.toDouble();
  while (v >= 1024 && i < s.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(1)} ${s[i]}';
}

/// Format a date value (int timestamp or string) into YYYY-MM-DD.
String formatDate(dynamic dateValue) {
  if (dateValue == null) return '';
  try {
    if (dateValue is int) {
      final dt = DateTime.fromMillisecondsSinceEpoch(dateValue);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    }
    if (dateValue is String) {
      if (dateValue.length >= 10) {
        return dateValue.substring(0, 10);
      }
    }
    return dateValue.toString();
  } catch (e) {
    return '';
  }
}

/// Check if a filename should be included based on include/exclude glob patterns.
bool shouldIncludeFile(
    String fileName, List<String> include, List<String> exclude) {
  if (include.isNotEmpty) {
    final matchesInclude =
        include.any((pattern) => _globMatches(pattern, fileName));
    if (!matchesInclude) return false;
  }

  if (exclude.isNotEmpty) {
    final matchesExclude =
        exclude.any((pattern) => _globMatches(pattern, fileName));
    if (matchesExclude) return false;
  }

  return true;
}

bool _globMatches(String pattern, String input) {
  // Glob -> RegExp. Translate the wildcards `*` and `?`, and escape every
  // other character so regex metacharacters in the pattern (`.`, `+`, `(`,
  // `[`, `$`, `|`, ...) are matched literally rather than interpreted.
  final buf = StringBuffer('^');
  for (final ch in pattern.split('')) {
    if (ch == '*') {
      buf.write('.*');
    } else if (ch == '?') {
      buf.write('.');
    } else {
      buf.write(RegExp.escape(ch));
    }
  }
  buf.write(r'$');
  return RegExp(buf.toString(), caseSensitive: false).hasMatch(input);
}
