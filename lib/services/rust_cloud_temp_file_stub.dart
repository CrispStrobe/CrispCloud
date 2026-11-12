// Browser builds never construct a Rust cloud session (the native library is
// unavailable there), so these members are unreachable placeholders.
class RustCloudTempFile {
  RustCloudTempFile._();
  String get path => throw UnsupportedError('Rust engines need a native build.');

  static Future<RustCloudTempFile> create(String name) async =>
      throw UnsupportedError('Rust engines need a native build.');

  Future<void> writeBytes(List<int> bytes) async => throw UnsupportedError('');
  Future<void> writeStream(Stream<List<int>> source, int length) async =>
      throw UnsupportedError('');
  Stream<List<int>> openRead() => throw UnsupportedError('');
  Future<int> length() async => throw UnsupportedError('');
  Future<void> delete() async {}
}
