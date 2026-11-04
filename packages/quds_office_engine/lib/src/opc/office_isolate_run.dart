/// Web / Wasm fallback: run the encode callback on the current isolate.
Future<T> officeIsolateRun<T>(T Function() encode) async => encode();
