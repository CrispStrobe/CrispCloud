import '../models/file_item.dart';
import '../models/storage_reference.dart';
import '../models/terminal_workspace.dart';
import 'cloud_storage_interface.dart';
import 'terminal_workspace_service_stub.dart'
    if (dart.library.io) 'terminal_workspace_service_io.dart'
    as platform;

export '../models/terminal_workspace.dart';

/// Persistent, explicitly reviewed copies of files from one captured account.
/// The public boundary contains no dart:io types and is safe to import on web.
abstract class TerminalWorkspaceService {
  factory TerminalWorkspaceService({
    String? rootDirectory,
    int maxEntries = 10000,
    int maxDepth = 64,
    int maxTotalBytes = 16 * 1024 * 1024 * 1024,
  }) => platform.createTerminalWorkspaceService(
    rootDirectory: rootDirectory,
    maxEntries: maxEntries,
    maxDepth: maxDepth,
    maxTotalBytes: maxTotalBytes,
  );
  TerminalWorkspaceService.base();

  bool get isSupported;
  List<String> get warnings;

  Future<TerminalWorkspace> stage({
    required CloudStorageClient client,
    required String remoteRoot,
    required List<FileItem> items,
    required bool Function() isCurrent,
    StorageReference? storage,
    String? title,
    bool Function()? isCancelled,
    void Function(int completed, int total)? onProgress,
  });
  Future<List<TerminalWorkspace>> list({StorageReference? storage});
  Future<TerminalWorkspace?> load(String id);
  Future<TerminalWorkspace> resumeStage({
    required String workspaceId,
    required CloudStorageClient client,
    required bool Function() isCurrent,
    bool Function()? isCancelled,
  });
  Future<List<TerminalWorkspaceChange>> inspect(
    String workspaceId, {
    bool Function()? isCancelled,
  });
  Future<TerminalWorkspaceUploadResult> uploadReviewed({
    required String workspaceId,
    required CloudStorageClient client,
    required List<TerminalWorkspaceChange> changes,
    required bool Function() isCurrent,
    bool Function()? isCancelled,
  });
}
