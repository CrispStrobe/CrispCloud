import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../l10n/archive_endpoint_strings.dart';
import '../l10n/archive_transfer_strings.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/core_providers.dart';
import '../providers/panel_provider.dart';
import '../services/archive_browser_session.dart';
import '../services/archive_endpoint.dart';
import '../services/archive_service.dart';
import '../services/archive_workspace.dart';
import '../services/file_operation_backend.dart';
import '../services/file_operation_service.dart';
import '../services/local_file_service.dart';
import 'archive_endpoint_dialog.dart';

/// A destination captured before clipboard reads, source materialization or a
/// popup await. The archive member directory never becomes a physical path.
class CapturedArchiveImportDestination {
  CapturedArchiveImportDestination._({
    required this.side,
    required this.panel,
    required this.origin,
    required this.location,
    required this.backend,
    required this.directory,
    required this.currentCheck,
  });

  final PanelSide side;
  final PanelNotifier panel;
  final PanelFileOrigin origin;
  final ArchiveWorkspaceLocation location;
  final FileOperationBackend backend;
  final String directory;
  final bool Function() currentCheck;
  bool get isCurrent => currentCheck();

  static CapturedArchiveImportDestination capture(
    WidgetRef ref,
    PanelSide side,
  ) {
    final panel = ref.read(panelProvider(side));
    final origin = panel.captureArchiveOrigin();
    final location = panel.captureArchiveWorkspaceLocation();
    final session = panel.captureOperationSession();
    final navigation = panel.navigationIntentRevision;
    final directory = p.posix.normalize('/${panel.archiveSource!.innerPath}');
    final local = ref.read(localFileServiceProvider);
    final identities = local is LocalFileSourceIdentity
        ? local as LocalFileSourceIdentity
        : null;
    final grant = origin.source.isLocal
        ? identities?.sourceIdentityForPath(location.file.path!)
        : null;
    if (origin.source.isLocal && identities != null && grant == null) {
      throw StateError(archiveEndpointText(ref.context, 'unavailable'));
    }
    var lost = false;
    bool current() {
      if (lost) return false;
      lost =
          !ref.context.mounted ||
          !session() ||
          !origin.isCurrent ||
          !location.isCurrent() ||
          panel.navigationIntentRevision != navigation ||
          origin.source.isLocal &&
              identities != null &&
              !identical(
                identities.sourceIdentityForPath(location.file.path!),
                grant,
              );
      return !lost;
    }

    return CapturedArchiveImportDestination._(
      side: side,
      panel: panel,
      origin: origin,
      location: location,
      directory: directory,
      currentCheck: current,
      backend: fileOperationBackend(
        source: origin.source,
        local: local,
        isCurrent: current,
      ),
    );
  }
}

/// A read-only archive selection captured with its physical container, nested
/// route and exact panel rows. Virtual member paths never reach a disk backend.
class CapturedArchiveCopySource {
  CapturedArchiveCopySource._(this.location, this.files);

  final CapturedArchiveImportDestination location;
  final List<FileItem> files;
  bool get isCurrent => location.isCurrent;

  static CapturedArchiveCopySource capture(
    WidgetRef ref,
    PanelSide side,
    List<FileItem> files,
  ) {
    final location = CapturedArchiveImportDestination.capture(ref, side);
    final rows = location.panel.files ?? const <FileItem>[];
    if (files.isEmpty ||
        files.any(
          (file) =>
              file.name == '..' ||
              file.path == null ||
              !rows.any((row) => identical(row, file)),
        )) {
      throw StateError(archiveEndpointText(ref.context, 'sourceChanged'));
    }
    return CapturedArchiveCopySource._(
      location,
      List.unmodifiable([
        for (final file in files)
          file.copyWith(
            path:
                '/${ArchiveService.safeMemberPath(file.path!.replaceAll(RegExp(r'^/+|/+$'), ''))}',
          ),
      ]),
    );
  }
}

/// Reviews a copy or move between independently captured containers. A move
/// publishes the destination before its separately reviewed source removal.
Future<ArchiveEndpointTransferResult?> showCapturedArchiveCopy(
  BuildContext context,
  WidgetRef ref, {
  required CapturedArchiveCopySource source,
  required CapturedArchiveImportDestination destination,
  bool moveSources = false,
  bool Function()? isReviewCurrent,
}) async {
  try {
    var lost = false;
    bool current() {
      if (!lost) {
        lost =
            !context.mounted ||
            !source.isCurrent ||
            !destination.isCurrent ||
            !(isReviewCurrent?.call() ?? true);
      }
      return !lost;
    }

    if (!current()) {
      if (!context.mounted) return null;
      throw StateError(archiveEndpointText(context, 'sourceChanged'));
    }
    final captured = source.location;
    final showTransfer = moveSources
        ? showArchiveEndpointMoveDialog
        : showArchiveEndpointCopyDialog;
    final result = await showTransfer(
      context,
      sourceContainerBackend: fileOperationBackend(
        source: captured.origin.source,
        local: ref.read(localFileServiceProvider),
        isCurrent: current,
      ),
      sourceContainerFile: captured.location.file,
      sourceNestedMembers: captured.location.nestedMembers,
      expectedSourceFingerprint: captured.location.fingerprint,
      files: source.files,
      containerBackend: destination.backend,
      containerFile: destination.location.file,
      nestedMembers: destination.location.nestedMembers,
      directory: destination.directory,
      expectedOuterFingerprint: destination.location.fingerprint,
    );
    // Recovery can change either archive even without a new move receipt.
    // Ordinary copies keep the source view and its selection untouched.
    final refreshSource = moveSources && source.isCurrent;
    if (context.mounted && destination.isCurrent) {
      await destination.panel.refresh();
    }
    if (context.mounted && refreshSource && source.isCurrent) {
      await source.location.panel.refresh();
    }
    return result;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
    return null;
  }
}

/// Borrows an unlocked source for a physical transfer. The owner retains its
/// draft and lifetime. After a move result, it must close or reopen the source.
Future<ArchiveEndpointTransferResult?> showCapturedArchiveWorkspaceCopy(
  BuildContext context, {
  required ArchiveWorkspace source,
  required List<FileItem> files,
  required CapturedArchiveImportDestination destination,
  bool moveSources = false,
  bool Function()? isReviewCurrent,
  VoidCallback? onSourceInvalidated,
}) async {
  if (files.isEmpty) return null;
  try {
    if (source.dirty || source.pendingPublication != null) {
      throw StateError(
        moveSources
            ? archiveTransferText(context, 'sourceDraft')
            : archiveEndpointText(context, 'sourceDraft'),
      );
    }
    final snapshot = source.captureCopySource();
    final selected = List<FileItem>.unmodifiable(files);
    var lost = false;
    bool current() {
      if (!lost) {
        lost =
            !context.mounted ||
            !snapshot.isCurrent ||
            !destination.isCurrent ||
            !(isReviewCurrent?.call() ?? true);
      }
      return !lost;
    }

    if (!current()) {
      if (!context.mounted) return null;
      throw StateError(archiveEndpointText(context, 'sourceChanged'));
    }
    final showTransfer = moveSources
        ? showArchiveWorkspaceMoveDialog
        : showArchiveWorkspaceCopyDialog;
    final result = await showTransfer(
      context,
      source,
      files: selected,
      containerBackend: destination.backend,
      containerFile: destination.location.file,
      nestedMembers: destination.location.nestedMembers,
      directory: destination.directory,
      expectedOuterFingerprint: destination.location.fingerprint,
      isCopyCurrent: current,
      onSourceInvalidated: onSourceInvalidated,
    );
    if (context.mounted && destination.isCurrent) {
      await destination.panel.refresh();
    }
    return result;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
    return null;
  }
}

/// Routes a captured local/remote or archive selection into one destination
/// transaction. No stage-only file-operation result escapes this UI.
Future<ArchiveEndpointTransferResult?> showCapturedArchiveImport(
  BuildContext context,
  WidgetRef ref, {
  required PanelSide sourceSide,
  required List<FileItem> files,
  required CapturedArchiveImportDestination destination,
  PanelFileOrigin? sourceOrigin,
  Map<PanelFileOrigin, List<FileItem>>? sourceGroups,
  bool moveSources = false,
  bool Function()? isReviewCurrent,
}) async {
  if (files.isEmpty) return null;
  try {
    if (!context.mounted ||
        !destination.isCurrent ||
        !(isReviewCurrent?.call() ?? true)) {
      if (!context.mounted) return null;
      throw StateError(archiveEndpointText(context, 'unavailable'));
    }
    final panel = ref.read(panelProvider(sourceSide));
    final sourceSession = panel.captureOperationSession();
    final sourceNavigation = panel.navigationIntentRevision;
    if (sourceOrigin == null && sourceGroups == null && panel.isInArchive) {
      final source = CapturedArchiveCopySource.capture(ref, sourceSide, files);
      return await showCapturedArchiveCopy(
        context,
        ref,
        source: source,
        destination: destination,
        moveSources: moveSources,
        isReviewCurrent: isReviewCurrent,
      );
    }
    final explicitSource = sourceOrigin != null || sourceGroups != null;
    if (!explicitSource) {
      files = await panel.prepareOperationFiles(List.unmodifiable(files));
      if (!context.mounted) return null;
      if (!sourceSession() ||
          panel.navigationIntentRevision != sourceNavigation) {
        throw StateError(archiveEndpointText(context, 'unavailable'));
      }
      sourceGroups = panel.captureOperationGroups(files);
    }
    if (sourceGroups != null) {
      if (sourceGroups.length != 1) {
        throw StateError(archiveEndpointText(context, 'mixedSources'));
      }
      sourceOrigin = sourceGroups.keys.single;
      files = List.unmodifiable(sourceGroups.values.single);
    }
    final origin = sourceOrigin;
    if (origin == null ||
        !origin.isCurrent ||
        !destination.isCurrent ||
        !(isReviewCurrent?.call() ?? true)) {
      throw StateError(archiveEndpointText(context, 'unavailable'));
    }
    var sourceLost = false;
    bool current() {
      if (!sourceLost) {
        sourceLost =
            !context.mounted ||
            !origin.isCurrent ||
            !destination.isCurrent ||
            !(isReviewCurrent?.call() ?? true) ||
            !explicitSource &&
                (!sourceSession() ||
                    panel.navigationIntentRevision != sourceNavigation);
      }
      return !sourceLost;
    }

    final source = fileOperationBackend(
      source: origin.source,
      local: ref.read(localFileServiceProvider),
      isCurrent: current,
    );
    if (!context.mounted || !current()) return null;
    final remember = panel.captureSelectionMemoryForOperation(files);
    final result = await showArchiveEndpointImportDialog(
      context,
      source: source,
      files: List.unmodifiable(files),
      containerBackend: destination.backend,
      containerFile: destination.location.file,
      nestedMembers: destination.location.nestedMembers,
      directory: destination.directory,
      expectedOuterFingerprint: destination.location.fingerprint,
      moveSources: moveSources,
    );
    if (context.mounted) {
      if (result != null) remember?.call();
      // Recovery may restore or finish an earlier publication without producing
      // an import receipt. Refresh only the still-captured destination view.
      if (destination.isCurrent) await destination.panel.refresh();
      if (result != null &&
          sourceSide != destination.side &&
          sourceSession() &&
          panel.navigationIntentRevision == sourceNavigation &&
          origin.isCurrent) {
        await panel.refresh();
      }
    }
    return result;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
    return null;
  }
}

/// Recovery can run from an ordinary folder if an interrupted two-move
/// publication temporarily left the original archive path absent.
Future<void> showArchiveRecoveryForActiveSource(
  BuildContext context,
  WidgetRef ref,
) async {
  try {
    final side = ref.read(activePanelProvider);
    final panel = ref.read(panelProvider(side));
    final origin = panel.isInArchive
        ? panel.captureArchiveOrigin()
        : panel.captureCurrentOrigin();
    final session = panel.captureOperationSession();
    final navigation = panel.navigationIntentRevision;
    var lost = false;
    bool current() {
      if (!lost) {
        lost =
            !context.mounted ||
            !origin.isCurrent ||
            !session() ||
            panel.navigationIntentRevision != navigation;
      }
      return !lost;
    }

    final backend = fileOperationBackend(
      source: origin.source,
      local: ref.read(localFileServiceProvider),
      isCurrent: current,
    );
    final changed = await showArchivePublicationRecoveryDialog(
      context,
      backend: backend,
    );
    if (changed && current()) await panel.refresh();
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}
