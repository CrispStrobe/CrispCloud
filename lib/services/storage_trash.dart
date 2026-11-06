/// A provider/native trash identity, independent of the active directory.
class TrashReceipt {
  const TrashReceipt({required this.originalPath, required this.trashId});
  final String originalPath;
  final String trashId;
  Map<String, dynamic> toJson() => {
    'originalPath': originalPath,
    'trashId': trashId,
  };
  factory TrashReceipt.fromJson(Map<String, dynamic> json) {
    final path = json['originalPath'];
    final id = json['trashId'];
    if (path is! String || id is! String || path.isEmpty || id.isEmpty) {
      throw const FormatException('Invalid trash restore information.');
    }
    return TrashReceipt(originalPath: path, trashId: id);
  }
}

/// Only adapters with a real reversible delete implement this contract.
/// Legacy `supportsTrash` never grants restore permission by itself.
abstract interface class StorageTrashOperations {
  Future<TrashReceipt> trashPath(String path);
  Future<void> restoreTrash(TrashReceipt receipt);
  Future<void> deletePermanently(String path);
}
