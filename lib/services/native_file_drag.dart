import 'package:path/path.dart' as p;

import '../models/panel_drag_data.dart';
import 'local_file_service.dart';
import 'native_file_operations.dart';
import 'panel_source_service.dart';

/// Export the captured local selection as OS file URLs. Keep every original
/// sandbox scope alive until the receiving app accepts or cancels the drag.
Future<bool> startNativeFileDrag(
  PanelDragData data,
  LocalFileService local, {
  NativeFileOperations native = const NativeFileOperations(),
}) async {
  final groups = await data.prepareForDrop();
  if (groups.keys.any((origin) => origin.source is! LocalPanelSource)) {
    throw StateError(
      'Save these files locally before dragging them into another app.',
    );
  }
  final uniquePaths = <String>{};
  for (final files in groups.values) {
    for (final file in files) {
      final path = file.path;
      if (path == null || !p.isAbsolute(path) || path.contains('\u0000')) {
        throw StateError('The original file location is unavailable.');
      }
      uniquePaths.add(path);
    }
  }
  final paths = uniquePaths.toList(growable: false);
  Future<bool> withAccess(int index) {
    if (index == paths.length) {
      if (!data.isCurrent) {
        throw const PanelDragException(PanelDragFailure.sourceChanged);
      }
      return native.startFileDrag(paths);
    }
    return local.withFileOperationAccess(
      paths[index],
      () => withAccess(index + 1),
    );
  }

  return withAccess(0);
}
