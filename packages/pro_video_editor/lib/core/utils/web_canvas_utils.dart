import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart';

/// Extension on [HTMLCanvasElement] to provide a method for asynchronously
/// converting the canvas content to a [Blob].
///
/// The [toBlobAsync] method uses a [Completer] to handle the asynchronous
/// operation of the `toBlob` JavaScript API, allowing Dart code to work
/// seamlessly with the result.
///
/// - [mimeType]: The MIME type of the resulting [Blob].
/// - Returns: A [Future] that completes with the resulting [Blob] or an
///   error if the operation fails.
extension CanvasToBlobFuture on HTMLCanvasElement {
  /// Converts the current canvas content into a `Blob` asynchronously.
  ///
  /// This method generates a `Blob` object that represents the content of the
  /// canvas in the specified MIME type format.
  ///
  /// [mimeType] specifies the desired MIME type for the resulting `Blob`.
  /// Common examples include `image/png` or `image/jpeg`.
  ///
  /// Returns a `Future<Blob>` that completes with the generated `Blob` object.
  Future<Blob> toBlobAsync(String mimeType) {
    final completer = Completer<Blob>();

    // Define JS interop callback explicitly:
    final jsCallback = (JSAny? blob) {
      if (blob != null) {
        completer.complete(blob as Blob);
      } else {
        completer.completeError('toBlob failed');
      }
    }.toJS;

    toBlob(jsCallback, mimeType);

    return completer.future;
  }
}
