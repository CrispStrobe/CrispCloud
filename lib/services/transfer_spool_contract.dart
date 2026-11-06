abstract class TransferSpool {
  int get length;
  String? get localPath;

  /// A browser File backed by private storage, suitable for a native fetch body.
  /// Never materializes the file in Dart memory. Null on native platforms.
  Object? get webUploadBody;
  Stream<List<int>> openRead();
  Future<void> dispose();
}
