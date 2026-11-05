abstract class TransferSpool {
  int get length;
  String? get localPath;
  Stream<List<int>> openRead();
  Future<void> dispose();
}
