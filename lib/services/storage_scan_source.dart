import 'package:path/path.dart' as p;

import '../models/file_item.dart';

/// The metadata-only contract needed by the storage analyzer.
///
/// Kept separate from file mutation and Flutter services so the production
/// traversal can also run in a native Dart worker and be benchmarked in AOT.
/// Source identity and access checks remain the responsibility of the adapter.
abstract interface class StorageScanSource {
  Object get identity;
  bool get isCurrent;
  p.Context get paths;
  String pathKey(String path);
  bool samePath(String first, String second);
  bool isWithin(String parent, String child);
  bool get supportsSymbolicLinks;
  Future<FileItem?> stat(String path);
  Future<List<FileItem>> list(String path);
}
