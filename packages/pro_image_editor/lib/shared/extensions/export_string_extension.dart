import '../services/import_export/utils/key_minifier.dart';

/// Extension on [String] to convert keys using [EditorKeyMinifier].
extension ExportStringExtension on String {
  /// Converts this string to a main key using [minifier].
  String toMainKey(EditorKeyMinifier minifier) {
    return minifier.convertMainKey(this);
  }

  /// Converts this string to a size key using [minifier].
  String toSizeKey(EditorKeyMinifier minifier) {
    return minifier.convertSizeKey(this);
  }

  /// Converts this string to a history key using [minifier].
  String toHistoryKey(EditorKeyMinifier minifier) {
    return minifier.convertHistoryKey(this);
  }
}
