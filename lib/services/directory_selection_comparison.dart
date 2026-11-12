import '../models/file_item.dart';

/// Nonrecursive metadata comparison of two directory listings.
/// Equal timestamps with different known sizes select the active file too.
List<FileItem> compareDirectorySelection(
  Iterable<FileItem> active,
  Iterable<FileItem> other,
) {
  final peers = {for (final file in other) file.name: file};
  return active.where((file) {
    if (file.name == '..' || file.isFolder) return false;
    final peer = peers[file.name];
    if (peer == null) return true;
    if (peer.isFolder) return false;
    final date = file.updatedAt;
    final peerDate = peer.updatedAt;
    if (date != null && peerDate != null) {
      if (date.isAfter(peerDate)) return true;
      if (date.isBefore(peerDate)) return false;
    }
    return file.size != null && peer.size != null && file.size != peer.size;
  }).toList();
}
