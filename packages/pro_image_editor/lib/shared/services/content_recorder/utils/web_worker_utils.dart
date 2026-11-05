import 'dart:js_interop';
import 'dart:typed_data';

/// A function that converts a Dart object to a JavaScript object.
@JS('Object.getOwnPropertyDescriptor')
external JSObject? jsGetOwnPropertyDescriptor(
  JSObject obj,
  JSString propertyName,
);

/// A function that converts a Dart object to a JavaScript object.
@JS('Reflect.get')
external JSAny? reflectGet(JSAny? target, JSAny? propertyKey);

/// A function that converts a Dart object to a JavaScript object.
JSAny? jsGetProperty(JSObject obj, String propertyName) {
  // get the descriptor object
  final descriptor = jsGetOwnPropertyDescriptor(obj, propertyName.toJS);
  if (descriptor == null) return null;

  // retrieve descriptor.value using Reflect.get(descriptor, "value")
  return reflectGet(descriptor, 'value'.toJS);
}

/// Returns the JS implementation from Dart Object.
JSAny? jsify(Object? dartObject) {
  if (dartObject == null) {
    return dartObject?.jsify();
  }

  if (dartObject is Uint8List) {
    // Encoder results can be views into a larger capacity buffer. Only this
    // view belongs to the message: sending the backing buffer adds padding or
    // unrelated prefix bytes and corrupts the encoded image at the receiver.
    final bytes = dartObject.offsetInBytes == 0 &&
            dartObject.lengthInBytes == dartObject.buffer.lengthInBytes
        ? dartObject
        : Uint8List.fromList(dartObject);
    return bytes.buffer.toJS;
  }

  if (dartObject is List) {
    return dartObject.map(jsify).toList().toJS;
  }

  if (dartObject is Map) {
    return dartObject
        .map((key, value) => MapEntry(jsify(key), jsify(value)))
        .jsify();
  }

  if (dartObject is JSAny Function()) {
    return dartObject.toJS;
  }

  return dartObject.jsify();
}
