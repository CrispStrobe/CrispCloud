// ignore_for_file: public_member_api_docs

/// An exception thrown when there was a problem in the image library.
class ImageException implements Exception {
  ImageException(this.message);

  /// A message describing the error.
  final String message;

  @override
  String toString() => 'ImageException: $message';
}
