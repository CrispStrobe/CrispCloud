import '../models/file_item.dart';
import '../models/storage_reference.dart';
import 'cloud_storage_interface.dart';
import 'terminal_workspace_service.dart';

TerminalWorkspaceService createTerminalWorkspaceService({
  String? rootDirectory,
  required int maxEntries,
  required int maxDepth,
  required int maxTotalBytes,
}) => UnsupportedTerminalWorkspaceService();

class UnsupportedTerminalWorkspaceService extends TerminalWorkspaceService {
  UnsupportedTerminalWorkspaceService() : super.base();
  @override
  bool get isSupported => false;
  @override
  List<String> get warnings => const [];
  Never _unsupported() =>
      throw UnsupportedError('Terminal workspaces require a native app.');
  @override
  Future<TerminalWorkspace> stage({
    required CloudStorageClient client,
    required String remoteRoot,
    required List<FileItem> items,
    required bool Function() isCurrent,
    StorageReference? storage,
    String? title,
    bool Function()? isCancelled,
    void Function(int, int)? onProgress,
  }) async => _unsupported();
  @override
  Future<List<TerminalWorkspace>> list({StorageReference? storage}) async =>
      const [];
  @override
  Future<TerminalWorkspace?> load(String id) async => _unsupported();
  @override
  Future<TerminalWorkspace> resumeStage({
    required String workspaceId,
    required CloudStorageClient client,
    required bool Function() isCurrent,
    bool Function()? isCancelled,
  }) async => _unsupported();
  @override
  Future<List<TerminalWorkspaceChange>> inspect(
    String workspaceId, {
    bool Function()? isCancelled,
  }) async => _unsupported();
  @override
  Future<TerminalWorkspaceUploadResult> uploadReviewed({
    required String workspaceId,
    required CloudStorageClient client,
    required List<TerminalWorkspaceChange> changes,
    required bool Function() isCurrent,
    bool Function()? isCancelled,
  }) async => _unsupported();
}
