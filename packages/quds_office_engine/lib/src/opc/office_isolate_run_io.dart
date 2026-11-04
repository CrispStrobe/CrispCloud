import 'dart:isolate';

/// VM path: encode on a worker isolate, with a same-isolate fallback.
Future<T> officeIsolateRun<T>(T Function() encode) async {
  try {
    return await Isolate.run(encode);
  } on IsolateSpawnException {
    return encode();
  } on UnsupportedError {
    return encode();
  } on ArgumentError catch (error) {
    final String text = error.toString();
    if (text.contains('isolate message') || text.contains('unsendable')) {
      return encode();
    }
    rethrow;
  }
}
