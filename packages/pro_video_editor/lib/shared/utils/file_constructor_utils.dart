import '/core/platform/io/io_helper.dart';

/// Converts a given dynamic input into a `File` instance.
///
/// This function ensures that the provided input is either:
/// - A `String` representing a file path, which is then converted into a
/// `File`.
/// - An existing `File` instance, which is returned as is.
///
/// Throws an [ArgumentError] if the input is neither a `String` nor a `File`.
///
/// Example usage:
/// ```dart
/// // Converts String to File
/// File file1 = ensureFileInstance('path/to/file.txt');
/// // Returns existing File
/// File file2 = ensureFileInstance(existingFile);
/// ```
///
/// @param [file] A `String` (file path) or a `File` instance.
///
/// @returns A `File` instance corresponding to the given input.
///
/// @throws [ArgumentError] If the input is neither a `String` nor a `File`.
File ensureFileInstance(dynamic file) {
  if (file is String) {
    return File(file);
  } else if (file is File) {
    return file;
  }

  throw ArgumentError(
    'Only type `File` or `String` which is the path from the file is '
    'allowed!',
  );
}
