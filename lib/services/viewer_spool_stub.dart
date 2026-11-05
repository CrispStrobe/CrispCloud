import '../models/file_item.dart';
import 'file_operation_service.dart';

class ViewerSpool {
  String get path => throw UnsupportedError(
    'Temporary disk viewing is unavailable in the browser.',
  );
  Future<void> close() async {}
}

Future<ViewerSpool> createViewerSpool(
  FileOperationBackend source,
  FileItem file, {
  int maxBytes = 2 * 1024 * 1024 * 1024,
  bool Function()? isCancelled,
  void Function(int bytes, int? total)? onProgress,
}) async => throw UnsupportedError(
  'Temporary disk viewing is unavailable in the browser.',
);
