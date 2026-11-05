import 'dart:js_interop';
import 'dart:typed_data';

/// A Dart extension type for working with JavaScript `Blob` objects.
///
/// Provides factory constructors for creating `Blob` instances from byte data
/// and exposes properties such as `type`, `blobParts`, and `options`.
///
/// - `Blob.fromBytes`: Creates a `Blob` from a list of integers.
/// - `Blob.fromUint8List`: Creates a `Blob` from a `Uint8List`.
/// - `type`: Retrieves the MIME type of the `Blob`.
/// - `blobParts`: Accesses the parts of the `Blob` as a `JSArrayBuffer`.
/// - `options`: Retrieves the options used to create the `Blob`.
@JS('Blob')
extension type Blob._(JSObject _) implements JSObject {
  /// A JavaScript `Blob` factory for creating binary large objects.
  ///
  /// This factory allows you to create a `Blob` from a list of `ArrayBuffer`s.
  /// You can also provide optional configuration options.
  external factory Blob(JSArray<JSArrayBuffer> blobParts, JSObject? options);

  /// Creates a [Blob] from a list of bytes.
  ///
  /// This constructor converts the given [bytes] into a `Uint8List`,
  /// wraps it in a JavaScript `ArrayBuffer`, and passes it to the `Blob`
  /// constructor with no additional options.
  factory Blob.fromBytes(List<int> bytes) {
    final data = Uint8List.fromList(bytes).buffer.toJS;
    return Blob([data].toJS, null);
  }

  /// Creates a [Blob] directly from a [Uint8List].
  ///
  /// This constructor wraps the byte buffer in a JavaScript `ArrayBuffer`
  /// and passes it to the `Blob` constructor with no additional options.
  factory Blob.fromUint8List(Uint8List bytes) {
    final data = Uint8List.fromList(bytes).buffer.toJS;
    return Blob([data].toJS, null);
  }

  /// The MIME type of the `Blob` content as a string.
  @JS('type')
  external String get type;

  /// The internal blob parts as a JavaScript array of `ArrayBuffer`s.
  external JSArrayBuffer? get blobParts;

  /// The options used when the `Blob` was created.
  external JSObject? get options;
}
