import 'file_delete_dialog.dart';
// widgets/file_context_menu.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:universal_html/html.dart' as html;
import 'package:url_launcher/url_launcher.dart';

import 'dart:io';

import 'package:share_plus/share_plus.dart';

import '../l10n/app_localizations.dart';
import '../l10n/image_editor_strings.dart';
import '../l10n/pdf_editor_strings.dart';
import '../l10n/pdf_operations_strings.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/archive_service.dart';
import '../services/checksum_service.dart'
    show ChecksumService, ChecksumAlgorithm;
import '../services/file_operation_backend.dart';
import '../services/cloud_storage_interface.dart'
    show CloudStorageClientCapabilities;
import '../services/file_split_service.dart';
import '../services/image_edit_session.dart' show isImageEditorFileName;
import '../services/link_service.dart';
import '../services/secure_wipe_service.dart';
import '../services/log_service.dart';
import '../services/sftp_client_adapter.dart';
import '../services/share_service.dart';
import '../utils/file_editability.dart';
import '../utils/formatters.dart' show formatBytes, formatDateFull;

import 'package:path/path.dart' as p;

import 'batch_rename_dialog.dart' show showBatchRenameDialog;
import 'file_operation_dialog.dart';
import 'file_clipboard_actions.dart';
import 'archive_workspace_dialog.dart';
import 'integrity_dialogs.dart';
import '../services/file_operation_service.dart';
import 'diff_viewer_dialog.dart' show showDiffViewerDialog;
import 'file_editor_dialog.dart' show showFileEditorDialog;
import 'pdf_editor_dialog.dart' show isPdfFileName;
import 'pdf_operations_dialog.dart';
import 'share_link_dialog.dart' show showShareLinkDialog;
import 'permissions_dialog.dart' show showPermissionsDialog;
import 'version_history_dialog.dart' show showVersionHistoryDialog;

const _log = Log('FileContextMenu');

/// Text/code files are editable via the built-in F4 editor.

/// Open a local file with the OS default application via a file:// URI.
Future<void> openWithSystemEditor(BuildContext context, String path) async {
  try {
    final uri = Uri.file(path);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _log.warn('Cannot launch file URI: $uri');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No system editor found for this file type'),
          ),
        );
      }
    }
  } catch (e) {
    _log.error('Failed to open with system editor: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to open file: $e')));
    }
  }
}

void _showResultListContextMenu(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
  List<FileItem> files,
  Offset position,
) {
  final panel = ref.read(panelProvider(side));
  var verified = true;
  try {
    panel.captureOperationOrigin(files);
  } catch (_) {
    verified = false;
  }
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  PopupMenuItem<void> command(
    String label,
    IconData icon,
    FutureOr<void> Function() action, {
    bool requiresSource = true,
  }) => PopupMenuItem<void>(
    enabled: !requiresSource || verified,
    child: Row(
      children: [Icon(icon, size: 18), const SizedBox(width: 10), Text(label)],
    ),
    onTap: () => Future<void>.delayed(Duration.zero, () async {
      if (!context.mounted) return;
      try {
        await action();
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(error.toString())));
        }
      }
    }),
  );
  showMenu<void>(
    context: context,
    position: RelativeRect.fromRect(
      Rect.fromLTWH(position.dx, position.dy, 0, 0),
      Offset.zero & overlay.size,
    ),
    items: [
      command(
        'Copy files to clipboard',
        Icons.content_copy,
        () => copyFilesToClipboard(context, ref, side, items: files),
      ),
      command(
        'Cut files to clipboard',
        Icons.content_cut,
        () => copyFilesToClipboard(context, ref, side, cut: true, items: files),
      ),
      if (files.length == 1 &&
          !files.single.isFolder &&
          ArchiveService.isArchive(files.single.name))
        command(
          'Manage archive…',
          Icons.archive_outlined,
          () => showArchiveWorkspaceDialog(context, ref, side, files.single),
        ),
      if (files.every((file) => !file.isFolder && file.path != null)) ...[
        command(
          'Checksums…',
          Icons.fingerprint,
          () => showChecksumToolsDialog(context, ref, side, files),
        ),
        if (files.every((file) => isChecksumManifest(file.name)))
          command(
            'Verify checksum file',
            Icons.verified,
            () => showChecksumToolsDialog(
              context,
              ref,
              side,
              files,
              verifyInitially: true,
            ),
          ),
        if (files.length == 1)
          command(
            'Split file with integrity manifest…',
            Icons.call_split,
            () => showSplitFileDialog(context, ref, side, files.single),
          ),
        if (files.every((file) => isSplitPartOrManifest(file.name)))
          command(
            'Verify and combine parts…',
            Icons.merge_type,
            () => showCombinePartsDialog(context, ref, side, files),
          ),
      ],
      if (files.length == 1)
        command(
          'Open containing folder',
          Icons.folder_open,
          () => panel.openContainingFolder(files.single),
        ),
      command(
        'Copy with options…',
        Icons.copy,
        () => showFileOperationDialog(
          context,
          ref,
          side,
          files,
          kind: FileOperationKind.copy,
        ),
      ),
      command(
        'Move with options…',
        Icons.drive_file_move,
        () => showFileOperationDialog(
          context,
          ref,
          side,
          files,
          kind: FileOperationKind.move,
        ),
      ),
      command(
        'Multi-Rename…',
        Icons.drive_file_rename_outline,
        () => showBatchRenameDialog(
          context,
          ref,
          side,
          (panel.displayedFiles ?? const <FileItem>[])
              .where(files.contains)
              .toList(),
        ),
      ),
      const PopupMenuDivider(),
      command(
        'Remove from list (keep files)',
        Icons.playlist_remove,
        () => panel.removeFromFileList(files),
        requiresSource: false,
      ),
      command(
        'Delete files…',
        Icons.delete_outline,
        () => confirmDelete(context, ref, side, files),
      ),
    ],
  );
}

void showFileContextMenu(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
  FileItem file,
  Offset position,
) {
  _log.debug('file=${file.name} side=${side.name} web=$kIsWeb');
  final panel = ref.read(panelProvider(side));
  final selection = panel.selection;

  final files = selection.contains(file) && selection.isNotEmpty
      ? selection.toList()
      : [file];

  if (!selection.contains(file)) {
    panel.clearSelection();
    panel.toggleSelection(file);
  }

  if (panel.showingSearchResults) {
    _showResultListContextMenu(context, ref, side, files, position);
    return;
  }

  final isMultiSelect = files.length > 1;
  final isSingleFolder = files.length == 1 && files.first.isFolder;

  // Build items list dynamically
  final items = <PopupMenuEntry<dynamic>>[];

  for (final action in pdfOperationsForSelection(files)) {
    items.add(
      PopupMenuItem(
        child: Row(
          children: [
            Icon(action.icon),
            const SizedBox(width: 8),
            Text(context.pdfOpTr(action.label)),
          ],
        ),
        onTap: () => Future.delayed(Duration.zero, () {
          if (context.mounted) {
            showPdfOperationsDialog(context, ref, files, side, action);
          }
        }),
      ),
    );
  }

  // Open (folders only)
  if (isSingleFolder) {
    items.add(
      PopupMenuItem(
        child: Row(
          children: [
            const Icon(Icons.folder_open),
            const SizedBox(width: 8),
            Text(AppLocalizations.of(context)!.open),
          ],
        ),
        onTap: () => Future.delayed(
          Duration.zero,
          () => ref.read(panelProvider(side)).navigateInto(file),
        ),
      ),
    );
  }

  // Specialized editors and text/code editing for a single file.
  if (!isMultiSelect && !isSingleFolder) {
    final preferExternal = ref.read(preferExternalEditorProvider);
    if (isImageEditorFileName(file.name)) {
      items.add(
        PopupMenuItem(
          child: Row(
            children: [
              const Icon(Icons.edit_outlined),
              const SizedBox(width: 8),
              Text(context.imageTr('Edit Image')),
            ],
          ),
          onTap: () => Future.delayed(Duration.zero, () {
            if (context.mounted) showFileEditorDialog(context, ref, file, side);
          }),
        ),
      );
    }
    if (isPdfFileName(file.name)) {
      items.add(
        PopupMenuItem(
          child: Row(
            children: [
              const Icon(Icons.edit_document),
              const SizedBox(width: 8),
              Text(context.pdfTr('Edit PDF')),
            ],
          ),
          onTap: () => Future.delayed(Duration.zero, () {
            if (context.mounted) showFileEditorDialog(context, ref, file, side);
          }),
        ),
      );
    }
    if (isTextEditableName(file.name)) {
      // Primary "Edit" action respects the user's editor preference
      items.add(
        PopupMenuItem(
          child: Row(
            children: [
              const Icon(Icons.edit),
              const SizedBox(width: 8),
              Text(preferExternal ? 'Edit (System Editor)' : 'Edit (Built-in)'),
            ],
          ),
          onTap: () => Future.delayed(Duration.zero, () {
            if (!context.mounted) return;
            if (preferExternal && file.path != null && !kIsWeb) {
              openWithSystemEditor(context, file.path!);
            } else {
              showFileEditorDialog(context, ref, file, side);
            }
          }),
        ),
      );
      // Secondary option (the other editor)
      items.add(
        PopupMenuItem(
          child: Row(
            children: [
              Icon(
                preferExternal ? Icons.edit_note : Icons.open_in_new,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                preferExternal ? 'Edit (Built-in)' : 'Open with System Editor',
              ),
            ],
          ),
          onTap: () => Future.delayed(Duration.zero, () {
            if (!context.mounted) return;
            if (preferExternal) {
              showFileEditorDialog(context, ref, file, side);
            } else if (file.path != null && !kIsWeb) {
              openWithSystemEditor(context, file.path!);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('System editor not available')),
              );
            }
          }),
        ),
      );
    }
  }

  // Open with system default (all local non-folder files — DC-13 file associations)
  if (!isMultiSelect &&
      !isSingleFolder &&
      !kIsWeb &&
      side == PanelSide.local &&
      file.path != null &&
      !isTextEditableName(file.name)) {
    items.add(
      PopupMenuItem(
        child: const Row(
          children: [
            Icon(Icons.open_in_new, size: 20),
            SizedBox(width: 8),
            Text('Open with System App'),
          ],
        ),
        onTap: () => Future.delayed(Duration.zero, () {
          if (!context.mounted) return;
          openWithSystemEditor(context, file.path!);
        }),
      ),
    );
  }

  // Verify copy: compare local file MD5 against same-named file in opposite panel (DC-15)
  if (!isMultiSelect &&
      !isSingleFolder &&
      !kIsWeb &&
      side == PanelSide.local &&
      file.path != null &&
      !file.isFolder) {
    const oppSide = PanelSide.remote;
    final oppPanel = ref.read(panelProvider(oppSide));
    final oppMatch = (oppPanel.files ?? [])
        .where((f) => f.name == file.name && !f.isFolder)
        .toList();
    if (oppMatch.isNotEmpty) {
      items.add(
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.verified, size: 20),
              SizedBox(width: 8),
              Text('Verify against remote'),
            ],
          ),
          onTap: () => Future.delayed(Duration.zero, () {
            if (!context.mounted) return;
            _verifyAgainstRemote(context, ref, file, oppMatch.first);
          }),
        ),
      );
    }
  }

  // Compare with opposite panel (single non-folder file, both panels connected)
  if (!isMultiSelect && !isSingleFolder && ref.read(authProvider).isConnected) {
    final oppositeSide = side == PanelSide.local
        ? PanelSide.remote
        : PanelSide.local;
    final oppositePanel = ref.read(panelProvider(oppositeSide));
    // Look for a file with the same name in the opposite panel
    final matchingFile = (oppositePanel.files ?? [])
        .where((f) => f.name == file.name && !f.isFolder)
        .toList();
    if (matchingFile.isNotEmpty) {
      items.add(
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.compare_arrows),
              SizedBox(width: 8),
              Text('Compare'),
            ],
          ),
          onTap: () => Future.delayed(Duration.zero, () {
            if (!context.mounted) return;
            if (side == PanelSide.local) {
              showDiffViewerDialog(
                context,
                ref,
                file,
                matchingFile.first,
                leftSide: PanelSide.local,
                rightSide: PanelSide.remote,
              );
            } else {
              showDiffViewerDialog(
                context,
                ref,
                matchingFile.first,
                file,
                leftSide: PanelSide.local,
                rightSide: PanelSide.remote,
              );
            }
          }),
        ),
      );
    }
  }

  // Upload to Remote
  if (side == PanelSide.local && ref.read(authProvider).isConnected) {
    items.add(
      PopupMenuItem(
        child: Row(
          children: [
            const Icon(Icons.upload),
            const SizedBox(width: 8),
            Text('Upload${isMultiSelect ? ' (${files.length})' : ''}'),
          ],
        ),
        onTap: () => Future.delayed(
          Duration.zero,
          () => ref.read(transferProvider).uploadFiles(files),
        ),
      ),
    );
  }

  // Download to Local
  if (side == PanelSide.remote) {
    items.add(
      PopupMenuItem(
        child: Row(
          children: [
            const Icon(Icons.download),
            const SizedBox(width: 8),
            Text('Download${isMultiSelect ? ' (${files.length})' : ''}'),
          ],
        ),
        onTap: () => Future.delayed(
          Duration.zero,
          () => ref.read(transferProvider).downloadFiles(files),
        ),
      ),
    );
  }

  // Share (mobile platforms only — local files)
  if (!kIsWeb &&
      (Platform.isAndroid || Platform.isIOS) &&
      side == PanelSide.local) {
    items.add(
      PopupMenuItem(
        child: Row(
          children: [
            const Icon(Icons.share),
            const SizedBox(width: 8),
            Text('Share${isMultiSelect ? ' (${files.length})' : ''}'),
          ],
        ),
        onTap: () => Future.delayed(Duration.zero, () {
          final paths = files
              .where((f) => f.path != null)
              .map((f) => f.path!)
              .toList();
          ShareService.shareFiles(paths);
        }),
      ),
    );
  }

  // Share (mobile platforms only — remote files)
  if (!kIsWeb &&
      (Platform.isAndroid || Platform.isIOS) &&
      side == PanelSide.remote &&
      !isMultiSelect &&
      !isSingleFolder) {
    final client = ref.read(authProvider).client;

    // "Share Link" — only for providers with native share APIs
    if (client.capabilities.nativeShare) {
      items.add(
        PopupMenuItem(
          child: Row(
            children: [
              const Icon(Icons.link),
              const SizedBox(width: 8),
              Text(AppLocalizations.of(context)!.shareLink),
            ],
          ),
          onTap: () => Future.delayed(Duration.zero, () async {
            if (!context.mounted) return;
            try {
              showShareLinkDialog(context, ref, file);
            } catch (e) {
              _log.warn('operation failed', e);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Share link failed: $e')),
                );
              }
            }
          }),
        ),
      );
    }

    // "Share File" — download to temp then share binary
    items.add(
      PopupMenuItem(
        child: Row(
          children: [
            const Icon(Icons.share),
            const SizedBox(width: 8),
            Text(AppLocalizations.of(context)!.shareLink),
          ],
        ),
        onTap: () => Future.delayed(Duration.zero, () async {
          if (!context.mounted) return;
          // Show loading snackbar
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('Preparing file for sharing...'),
                ],
              ),
              duration: Duration(seconds: 30),
            ),
          );
          try {
            final remotePath =
                file.path ?? p.posix.join(panel.currentPath, file.name);
            final tempPath = p.join(Directory.systemTemp.path, file.name);
            await client.downloadFileByPath(remotePath, tempPath);
            if (context.mounted) {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
            }
            await Share.shareXFiles([XFile(tempPath)], text: file.name);
          } catch (e) {
            _log.warn('operation failed', e);
            if (context.mounted) {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Share failed: $e')));
            }
          }
        }),
      ),
    );
  }

  // Divider
  if ((side == PanelSide.local && ref.read(authProvider).isConnected) ||
      side == PanelSide.remote) {
    items.add(const PopupMenuDivider());
  }

  // Menus and keyboard shortcuts share the captured clipboard flow.
  items.addAll([
    PopupMenuItem(
      child: const ListTile(
        leading: Icon(Icons.content_copy),
        title: Text('Copy files to clipboard'),
      ),
      onTap: () => Future<void>.delayed(Duration.zero, () async {
        if (context.mounted) {
          await copyFilesToClipboard(context, ref, side, items: files);
        }
      }),
    ),
    PopupMenuItem(
      child: const ListTile(
        leading: Icon(Icons.content_cut),
        title: Text('Cut files to clipboard'),
      ),
      onTap: () => Future<void>.delayed(Duration.zero, () async {
        if (context.mounted) {
          await copyFilesToClipboard(
            context,
            ref,
            side,
            cut: true,
            items: files,
          );
        }
      }),
    ),
    PopupMenuItem(
      child: const ListTile(
        leading: Icon(Icons.content_paste),
        title: Text('Paste files with options…'),
      ),
      onTap: () => Future<void>.delayed(Duration.zero, () async {
        if (context.mounted) {
          await pasteFilesFromClipboard(context, ref, side);
        }
      }),
    ),
  ]);

  // Copy to... / Download (web local)
  if (kIsWeb && side == PanelSide.local) {
    items.add(
      PopupMenuItem(
        child: Row(
          children: [
            const Icon(Icons.download),
            const SizedBox(width: 8),
            Text('Download${isMultiSelect ? ' (${files.length})' : ''}'),
          ],
        ),
        onTap: () => Future.delayed(Duration.zero, () {
          _downloadFilesOnWeb(ref, files);
        }),
      ),
    );
  } else {
    items.add(
      PopupMenuItem(
        child: Row(
          children: [
            const Icon(Icons.content_copy),
            const SizedBox(width: 8),
            Text('Copy to...${isMultiSelect ? ' (${files.length})' : ''}'),
          ],
        ),
        onTap: () => Future.delayed(Duration.zero, () {
          if (!context.mounted) return;
          _showCopyDialog(context, ref, side, files);
        }),
      ),
    );
  }

  // Move to...
  items.add(
    PopupMenuItem(
      child: Row(
        children: [
          const Icon(Icons.drive_file_move),
          const SizedBox(width: 8),
          Text('Move to...${isMultiSelect ? ' (${files.length})' : ''}'),
        ],
      ),
      onTap: () => Future.delayed(Duration.zero, () {
        if (!context.mounted) return;
        _showMoveDialog(context, ref, side, files);
      }),
    ),
  );

  // Rename (single item only)
  if (!isMultiSelect) {
    items.add(
      PopupMenuItem(
        child: Row(
          children: [
            const Icon(Icons.edit),
            const SizedBox(width: 8),
            Text('${AppLocalizations.of(context)!.rename} (F2)'),
          ],
        ),
        onTap: () => Future.delayed(Duration.zero, () {
          if (!context.mounted) return;
          showRenameDialog(context, ref, side, file);
        }),
      ),
    );
  }

  // Batch rename (multi-select)
  if (isMultiSelect) {
    items.add(
      PopupMenuItem(
        child: Row(
          children: [
            const Icon(Icons.drive_file_rename_outline),
            const SizedBox(width: 8),
            Text('Batch Rename (${files.length})'),
          ],
        ),
        onTap: () => Future.delayed(Duration.zero, () {
          if (!context.mounted) return;
          showBatchRenameDialog(context, ref, side, files);
        }),
      ),
    );
  }

  // Share link (remote, single file, provider supports sharing — non-mobile or no supportsNativeShare)
  if (side == PanelSide.remote &&
      !isMultiSelect &&
      ref.read(authProvider).client.capabilities.sharing) {
    // On mobile with supportsNativeShare, Share Link is already shown above; avoid duplicate
    final isMobileNative =
        !kIsWeb &&
        (Platform.isAndroid || Platform.isIOS) &&
        ref.read(authProvider).client.capabilities.nativeShare;
    if (!isMobileNative) {
      items.add(
        PopupMenuItem(
          child: Row(
            children: [
              const Icon(Icons.link),
              const SizedBox(width: 8),
              Text(AppLocalizations.of(context)!.shareLink),
            ],
          ),
          onTap: () => Future.delayed(Duration.zero, () {
            if (!context.mounted) return;
            showShareLinkDialog(context, ref, file);
          }),
        ),
      );
    }
  }

  // Version history (remote, single file, provider supports versioning)
  if (side == PanelSide.remote &&
      !isMultiSelect &&
      !isSingleFolder &&
      ref.read(authProvider).client.capabilities.versioning) {
    items.add(const PopupMenuDivider());
    items.add(
      PopupMenuItem(
        child: const Row(
          children: [
            Icon(Icons.history),
            SizedBox(width: 8),
            Text('Version History'),
          ],
        ),
        onTap: () => Future.delayed(Duration.zero, () {
          if (!context.mounted) return;
          showVersionHistoryDialog(context, ref, file);
        }),
      ),
    );
  }

  // Permissions (SFTP only, single file)
  if (!isMultiSelect && side == PanelSide.remote) {
    final auth = ref.read(authProvider);
    if (auth.client is SFTPClientAdapter) {
      items.add(
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.security),
              SizedBox(width: 8),
              Text('Permissions'),
            ],
          ),
          onTap: () => Future.delayed(Duration.zero, () {
            if (!context.mounted) return;
            showPermissionsDialog(context, ref, file);
          }),
        ),
      );
    }
  }

  if (!isMultiSelect && !file.isFolder && ArchiveService.isArchive(file.name)) {
    items.add(
      PopupMenuItem(
        child: const ListTile(
          leading: Icon(Icons.archive_outlined),
          title: Text('Manage archive…'),
        ),
        onTap: () => Future<void>.delayed(Duration.zero, () async {
          if (context.mounted) {
            await showArchiveWorkspaceDialog(context, ref, side, file);
          }
        }),
      ),
    );
  }

  // Archive operations (local files only, not on web)
  if (!kIsWeb && side == PanelSide.local) {
    // Browse archive: show for single archive file
    if (!isMultiSelect &&
        ArchiveService.isArchive(file.name) &&
        file.path != null) {
      items.add(
        PopupMenuItem(
          child: Row(
            children: [
              const Icon(Icons.folder_zip),
              const SizedBox(width: 8),
              Text(AppLocalizations.of(context)!.browseArchive),
            ],
          ),
          onTap: () => Future.delayed(Duration.zero, () {
            ref.read(panelProvider(side)).enterArchive(file);
          }),
        ),
      );
    }
    // Extract: show for single archive file
    if (!isMultiSelect &&
        ArchiveService.isArchive(file.name) &&
        file.path != null) {
      items.add(
        PopupMenuItem(
          child: Row(
            children: [
              const Icon(Icons.unarchive),
              const SizedBox(width: 8),
              Text(AppLocalizations.of(context)!.extractHere),
            ],
          ),
          onTap: () => Future.delayed(Duration.zero, () async {
            try {
              final dir = p.dirname(file.path!);
              await ArchiveService.extractArchive(file.path!, dir);
              ref.read(panelProvider(PanelSide.local)).refresh();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Archive extracted successfully'),
                  ),
                );
              }
            } catch (e) {
              _log.warn('operation failed', e);
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Extract failed: $e')));
              }
            }
          }),
        ),
      );
    }

    // Create zip: show when files are selected
    if (files.isNotEmpty && files.any((f) => f.path != null)) {
      items.add(
        PopupMenuItem(
          child: Row(
            children: [
              const Icon(Icons.archive),
              const SizedBox(width: 8),
              Text('Create Zip${isMultiSelect ? ' (${files.length})' : ''}'),
            ],
          ),
          onTap: () => Future.delayed(Duration.zero, () async {
            try {
              final paths = files
                  .where((f) => f.path != null)
                  .map((f) => f.path!)
                  .toList();
              if (paths.isEmpty) return;
              final basePath = p.dirname(paths.first);
              final zipBytes = await ArchiveService.createZip(
                paths,
                basePath: basePath,
              );
              final zipName = isMultiSelect
                  ? 'archive.zip'
                  : '${p.basenameWithoutExtension(files.first.name)}.zip';
              var zipPath = p.join(basePath, zipName);
              var suffix = 2;
              while (await FileSystemEntity.type(zipPath, followLinks: false) !=
                  FileSystemEntityType.notFound) {
                zipPath = p.join(
                  basePath,
                  '${p.basenameWithoutExtension(zipName)} ($suffix).zip',
                );
                suffix++;
              }
              await File(zipPath).create(exclusive: true);
              await File(zipPath).writeAsBytes(zipBytes, flush: true);
              ref.read(panelProvider(PanelSide.local)).refresh();
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Created $zipName')));
              }
            } catch (e) {
              _log.warn('operation failed', e);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Zip creation failed: $e')),
                );
              }
            }
          }),
        ),
      );
    }
  }

  // Reveal in Finder / Explorer (local files only)
  if (!kIsWeb && side == PanelSide.local && file.path != null) {
    final revealLabel = Platform.isMacOS
        ? 'Reveal in Finder'
        : Platform.isWindows
        ? 'Show in Explorer'
        : 'Open containing folder';
    items.add(
      PopupMenuItem(
        child: Row(
          children: [
            const Icon(Icons.folder_open, size: 20),
            const SizedBox(width: 8),
            Text(revealLabel),
          ],
        ),
        onTap: () async {
          try {
            if (Platform.isMacOS) {
              await Process.run('open', ['-R', file.path!]);
            } else if (Platform.isWindows) {
              await Process.run('explorer', ['/select,', file.path!]);
            } else if (Platform.isLinux) {
              final dir = file.isFolder ? file.path! : p.dirname(file.path!);
              await Process.run('xdg-open', [dir]);
            }
          } catch (e) {
            _log.warn('operation failed', e);
          }
        },
      ),
    );
  }

  items.add(const PopupMenuDivider());

  // Properties / Info
  if (!isMultiSelect) {
    items.add(
      PopupMenuItem(
        child: Row(
          children: [
            const Icon(Icons.info_outline),
            const SizedBox(width: 8),
            Text(AppLocalizations.of(context)!.properties),
          ],
        ),
        onTap: () => Future.delayed(Duration.zero, () {
          if (!context.mounted) return;
          _showPropertiesDialog(context, file);
        }),
      ),
    );
  }

  // Calculate Size (folders only, not on web)
  if (isSingleFolder && !kIsWeb && side == PanelSide.local) {
    items.add(
      PopupMenuItem(
        child: const Row(
          children: [
            Icon(Icons.data_usage),
            SizedBox(width: 8),
            Text('Calculate Size'),
          ],
        ),
        onTap: () => Future.delayed(Duration.zero, () {
          if (!context.mounted) return;
          _showFolderSize(context, file);
        }),
      ),
    );
  }

  // Copy names / paths to clipboard
  items.add(
    PopupMenuItem(
      child: const Row(
        children: [
          Icon(Icons.content_copy, size: 20),
          SizedBox(width: 8),
          Text('Copy name(s)'),
        ],
      ),
      onTap: () {
        final sel = panel.selection;
        final items2 = sel.isEmpty
            ? (file.name != '..' ? {file} : <FileItem>{})
            : sel;
        Clipboard.setData(
          ClipboardData(text: items2.map((f) => f.name).join('\n')),
        );
      },
    ),
  );
  items.add(
    PopupMenuItem(
      child: const Row(
        children: [
          Icon(Icons.link, size: 20),
          SizedBox(width: 8),
          Text('Copy path(s)'),
        ],
      ),
      onTap: () {
        final sel = panel.selection;
        final items2 = sel.isEmpty
            ? (file.name != '..' ? {file} : <FileItem>{})
            : sel;
        Clipboard.setData(
          ClipboardData(text: items2.map((f) => f.path ?? f.name).join('\n')),
        );
      },
    ),
  );

  // Integrity tools route through the storage account that produced each row.
  if (!panel.isInArchive &&
      files.every((entry) => !entry.isFolder && entry.path != null)) {
    PopupMenuItem<void> integrityCommand(
      String label,
      IconData icon,
      Future<void> Function() action,
    ) => PopupMenuItem<void>(
      child: Row(
        children: [Icon(icon, size: 20), const SizedBox(width: 8), Text(label)],
      ),
      onTap: () => Future<void>.delayed(Duration.zero, () async {
        if (context.mounted) await action();
      }),
    );
    items.add(
      integrityCommand(
        'Checksums…',
        Icons.fingerprint,
        () => showChecksumToolsDialog(context, ref, side, files),
      ),
    );
    if (files.every((entry) => isChecksumManifest(entry.name))) {
      items.add(
        integrityCommand(
          'Verify checksum file',
          Icons.verified,
          () => showChecksumToolsDialog(
            context,
            ref,
            side,
            files,
            verifyInitially: true,
          ),
        ),
      );
    }
    if (files.length == 1) {
      items.add(
        integrityCommand(
          'Split file with integrity manifest…',
          Icons.call_split,
          () => showSplitFileDialog(context, ref, side, files.single),
        ),
      );
    }
    if (files.every((entry) => isSplitPartOrManifest(entry.name))) {
      items.add(
        integrityCommand(
          'Verify and combine parts…',
          Icons.merge_type,
          () => showCombinePartsDialog(context, ref, side, files),
        ),
      );
    }
  }

  // Create symlink (local or SFTP, single file, desktop only)
  if (!kIsWeb &&
      !isMultiSelect &&
      (side == PanelSide.local ||
          (side == PanelSide.remote &&
              ref.read(authProvider).client is SFTPClientAdapter))) {
    if (!kIsWeb &&
        (Platform.isMacOS || Platform.isLinux || Platform.isWindows)) {
      items.add(
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.link, size: 20),
              SizedBox(width: 8),
              Text('Create Link...'),
            ],
          ),
          onTap: () => Future.delayed(Duration.zero, () {
            if (!context.mounted) return;
            _showCreateLinkDialog(context, ref, side, file);
          }),
        ),
      );
    }
  }

  // Secure wipe (local files, desktop only)
  if (!kIsWeb &&
      side == PanelSide.local &&
      (Platform.isMacOS || Platform.isLinux || Platform.isWindows)) {
    items.add(
      PopupMenuItem(
        child: Row(
          children: [
            Icon(
              Icons.delete_forever,
              size: 20,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 8),
            Text(
              'Secure Wipe${isMultiSelect ? ' (${files.length})' : ''}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ),
        onTap: () => Future.delayed(Duration.zero, () {
          if (!context.mounted) return;
          _showSecureWipeDialog(context, ref, side, files);
        }),
      ),
    );
  }

  items.add(const PopupMenuDivider());

  // Delete
  items.add(
    PopupMenuItem(
      child: Row(
        children: [
          Icon(Icons.delete, color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 8),
          Text(
            'Delete${isMultiSelect ? ' (${files.length})' : ''}',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ),
      onTap: () => Future.delayed(Duration.zero, () {
        if (!context.mounted) return;
        confirmDelete(context, ref, side, files);
      }),
    ),
  );

  // Plugin-contributed context menu items
  final pluginRegistry = ref.read(pluginRegistryProvider);
  final filePaths = files
      .where((f) => f.path != null)
      .map((f) => f.path!)
      .toList();
  final pluginItems = pluginRegistry.getContextMenuItems(filePaths);
  if (pluginItems.isNotEmpty) {
    items.add(const PopupMenuDivider());
    for (final menuItem in pluginItems) {
      if (!menuItem.enabled) continue;
      items.add(
        PopupMenuItem(
          onTap: menuItem.onSelected != null
              ? () => Future.delayed(
                  Duration.zero,
                  () => menuItem.onSelected!(filePaths),
                )
              : null,
          child: Row(
            children: [
              const Icon(Icons.extension, size: 20),
              const SizedBox(width: 8),
              Text(menuItem.label),
            ],
          ),
        ),
      );
    }
  }

  showMenu(
    context: context,
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      position.dx + 1,
      position.dy + 1,
    ),
    items: items,
  );
}

void showRenameDialog(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
  FileItem file,
) {
  final controller = TextEditingController(text: file.name);

  // Select filename without extension
  final dotIndex = file.name.lastIndexOf('.');
  if (dotIndex > 0 && !file.isFolder) {
    controller.selection = TextSelection(baseOffset: 0, extentOffset: dotIndex);
  } else {
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: file.name.length,
    );
  }

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(AppLocalizations.of(context)!.rename),
      content: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: 'New name',
          border: const OutlineInputBorder(),
          prefixIcon: Icon(
            file.isFolder ? Icons.folder : Icons.insert_drive_file,
          ),
        ),
        autofocus: true,
        onSubmitted: (value) async {
          if (value.isNotEmpty && value != file.name) {
            try {
              await ref.read(panelProvider(side)).renameFile(file, value);
              if (context.mounted) Navigator.pop(context);
            } catch (e) {
              _log.warn('operation failed', e);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '${AppLocalizations.of(context)!.renameFailed}: $e',
                    ),
                  ),
                );
              }
            }
          }
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context)!.cancel),
        ),
        ElevatedButton(
          onPressed: () async {
            if (controller.text.isNotEmpty && controller.text != file.name) {
              try {
                await ref
                    .read(panelProvider(side))
                    .renameFile(file, controller.text);
                if (context.mounted) Navigator.pop(context);
              } catch (e) {
                _log.warn('operation failed', e);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${AppLocalizations.of(context)!.renameFailed}: $e',
                      ),
                    ),
                  );
                }
              }
            }
          },
          child: Text(AppLocalizations.of(context)!.rename),
        ),
      ],
    ),
  );
}

/// Download local files on web via browser download.
void _downloadFilesOnWeb(WidgetRef ref, List<FileItem> files) {
  _log.debug('downloadFilesOnWeb: ${files.length} files');
  if (!kIsWeb) return;
  final localSvc = ref.read(localFileServiceProvider);
  for (final file in files) {
    if (file.isFolder || file.path == null) continue;
    localSvc
        .readFile(file.path!, fileItem: file)
        .then((bytes) {
          _triggerBrowserDownload(bytes, file.name);
        })
        .catchError((_) {});
  }
}

/// Trigger a browser download for [bytes] with the given [filename].
void _triggerBrowserDownload(Uint8List bytes, String filename) {
  // Use universal_html for cross-platform web download.
  final blob = html.Blob([bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  // ignore: unused_local_variable
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}

void _showCopyDialog(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
  List<FileItem> files,
) {
  showFileOperationDialog(
    context,
    ref,
    side,
    files,
    kind: FileOperationKind.copy,
  );
}

void _showMoveDialog(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
  List<FileItem> files,
) {
  showFileOperationDialog(
    context,
    ref,
    side,
    files,
    kind: FileOperationKind.move,
  );
}

void showCopyDialog(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
  List<FileItem> files,
) {
  _showCopyDialog(context, ref, side, files);
}

void showMoveDialog(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
  List<FileItem> files,
) {
  _showMoveDialog(context, ref, side, files);
}

void confirmDelete(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
  List<FileItem> files,
) {
  showFileDeleteDialog(context, ref, side, files);
}

void _showPropertiesDialog(BuildContext context, FileItem file) =>
    showPropertiesDialog(context, file);

/// Public entry point — also callable from keyboard shortcuts (Ctrl+I).
void showPropertiesDialog(BuildContext context, FileItem file) {
  showDialog(
    context: context,
    builder: (context) => _PropertiesDialog(file: file),
  );
}

class _PropertiesDialog extends ConsumerStatefulWidget {
  final FileItem file;
  const _PropertiesDialog({required this.file});

  @override
  ConsumerState<_PropertiesDialog> createState() => _PropertiesDialogState();
}

class _PropertiesDialogState extends ConsumerState<_PropertiesDialog> {
  FileStat? _stat;
  String? _md5;
  bool _computingMd5 = false;
  PanelFileOrigin? _origin;

  @override
  void initState() {
    super.initState();
    final origins = [
      for (final side in PanelSide.values)
        ref.read(panelProvider(side)).originForOperation(widget.file),
    ].whereType<PanelFileOrigin>().toList();
    if (origins.map((origin) => origin.storageId).toSet().length == 1) {
      _origin = origins.first;
    }
    _loadStat();
  }

  Future<void> _loadStat() async {
    if (_origin?.isCurrent == true &&
        _origin!.source.isLocal &&
        widget.file.path != null &&
        !kIsWeb) {
      try {
        final stat = await FileStat.stat(widget.file.path!);
        if (mounted && _origin?.isCurrent == true) setState(() => _stat = stat);
      } catch (e) {
        _log.warn('initState failed', e);
      }
    }
  }

  String _modeString(int mode) {
    final bits = mode & 0x1FF;
    final chars = <String>[];
    for (final shift in [6, 3, 0]) {
      final seg = (bits >> shift) & 7;
      chars.add((seg & 4) != 0 ? 'r' : '-');
      chars.add((seg & 2) != 0 ? 'w' : '-');
      chars.add((seg & 1) != 0 ? 'x' : '-');
    }
    return chars.join();
  }

  Future<void> _computeMd5() async {
    if (widget.file.path == null) return;
    setState(() => _computingMd5 = true);
    try {
      final origin = _origin;
      if (origin == null || !origin.isCurrent) {
        throw StateError('The original file source is unavailable.');
      }
      final backend = fileOperationBackend(
        source: origin.source,
        local: ref.read(localFileServiceProvider),
        isCurrent: () => mounted && origin.isCurrent,
      );
      final hash = await ChecksumService.hashFile(
        backend,
        widget.file,
        ChecksumAlgorithm.md5,
        isCancelled: () => !mounted,
      );
      if (mounted) {
        setState(() {
          _md5 = hash;
          _computingMd5 = false;
        });
      }
    } catch (e) {
      _log.warn('operation failed', e);
      if (mounted) {
        setState(() {
          _md5 = 'Error: $e';
          _computingMd5 = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    final canRead = _origin?.isCurrent == true && file.path != null;
    final mimeType = file.isFolder
        ? 'Directory'
        : file.extension.isNotEmpty
        ? 'File (${file.extension.toUpperCase()})'
        : 'File';

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            file.isSymlink == true
                ? Icons.link
                : file.isFolder
                ? Icons.folder
                : Icons.insert_drive_file,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(file.name, overflow: TextOverflow.ellipsis)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _propertyRow(context, 'Type', mimeType),
            if (file.isSymlink == true && file.symlinkTarget != null)
              _propertyRow(
                context,
                '→ Target',
                file.symlinkTarget!,
                mono: true,
              ),
            if (file.size != null)
              _propertyRow(
                context,
                'Size',
                '${formatBytes(file.size!)} (${file.size} bytes)',
              ),
            if (file.path != null)
              _propertyRow(context, 'Path', file.path!, mono: true),
            if (file.uuid != null)
              _propertyRow(context, 'UUID', file.uuid!, mono: true),
            if (file.updatedAt != null)
              _propertyRow(
                context,
                'Modified',
                formatDateFull(file.updatedAt!),
              ),
            if (_stat != null) ...[
              _propertyRow(
                context,
                'Metadata changed',
                formatDateFull(_stat!.changed),
              ),
              _propertyRow(
                context,
                'Accessed',
                formatDateFull(_stat!.accessed),
              ),
              if (!kIsWeb && !Platform.isWindows)
                _propertyRow(
                  context,
                  'Permissions',
                  _modeString(_stat!.mode),
                  mono: true,
                ),
            ],
            if (file.metadata != null)
              ...file.metadata!.entries.map(
                (e) => _propertyRow(context, e.key, '${e.value}', mono: true),
              ),
            // Hashing stays bound to the original verified local or cloud source.
            if (canRead && !file.isFolder) ...[
              const Divider(),
              if (_md5 != null)
                _propertyRow(context, 'MD5', _md5!, mono: true)
              else
                TextButton.icon(
                  onPressed: _computingMd5 ? null : _computeMd5,
                  icon: _computingMd5
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.fingerprint, size: 16),
                  label: const Text('Compute MD5'),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

Widget _propertyRow(
  BuildContext context,
  String label,
  String value, {
  bool mono = false,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 4),
        SelectableText(
          value,
          style: TextStyle(
            fontFamily: mono ? 'monospace' : null,
            fontSize: mono ? 12 : null,
          ),
        ),
      ],
    ),
  );
}

Future<int> _calculateFolderSize(String path) async {
  int totalSize = 0;
  final dir = Directory(path);
  if (!await dir.exists()) return 0;
  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is File) {
      try {
        totalSize += await entity.length();
      } catch (e) {
        // Skip files we can't read
      }
    }
  }
  return totalSize;
}

void _showFolderSize(BuildContext context, FileItem file) {
  if (file.path == null) return;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return FutureBuilder<int>(
        future: _calculateFolderSize(file.path!),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.folder),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(file.name, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
              content: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 16),
                  Text('Calculating folder size...'),
                ],
              ),
            );
          }

          final size = snapshot.data ?? 0;
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.folder),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(file.name, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _propertyRow(context, 'Total Size', formatBytes(size)),
                _propertyRow(context, 'Bytes', size.toString()),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    },
  );
}

void _showCreateLinkDialog(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
  FileItem file,
) {
  final controller = TextEditingController(
    text: file.path != null ? '${file.path!}_link' : '',
  );
  bool isSymlink = true;

  showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Create Link'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Target: ${file.name}'),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Symlink')),
                ButtonSegment(value: false, label: Text('Hard Link')),
              ],
              selected: {isSymlink},
              onSelectionChanged: (v) => setState(() => isSymlink = v.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Link path',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                if (isSymlink) {
                  await LinkService.createSymlink(file.path!, controller.text);
                } else {
                  await LinkService.createHardlink(file.path!, controller.text);
                }
                ref.read(panelProvider(side)).refresh();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${isSymlink ? "Symlink" : "Hard link"} created',
                      ),
                    ),
                  );
                }
              } catch (e) {
                _log.warn('operation failed', e);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Link creation failed: $e')),
                  );
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    ),
  );
}

void _showSecureWipeDialog(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
  List<FileItem> files,
) {
  int passes = 3;

  showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        icon: Icon(
          Icons.warning,
          color: Theme.of(context).colorScheme.error,
          size: 48,
        ),
        title: const Text('Secure Wipe'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'This will overwrite ${files.length} item(s) with random data before deletion. This cannot be undone.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: passes,
              decoration: const InputDecoration(
                labelText: 'Overwrite passes',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 1, child: Text('1 pass (quick)')),
                DropdownMenuItem(
                  value: 3,
                  child: Text('3 passes (DoD standard)'),
                ),
                DropdownMenuItem(
                  value: 7,
                  child: Text('7 passes (high security)'),
                ),
              ],
              onChanged: (v) => setState(() => passes = v!),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () async {
              Navigator.pop(context);
              try {
                for (final file in files) {
                  if (file.path == null) continue;
                  if (file.isFolder) {
                    await SecureWipeService.secureWipeDirectory(
                      file.path!,
                      passes: passes,
                    );
                  } else {
                    await SecureWipeService.secureWipe(
                      file.path!,
                      passes: passes,
                    );
                  }
                }
                ref.read(panelProvider(side)).refresh();
                ref.read(panelProvider(side)).clearSelection();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Secure wipe completed')),
                  );
                }
              } catch (e) {
                _log.warn('operation failed', e);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Secure wipe failed: $e')),
                  );
                }
              }
            },
            child: const Text('Wipe'),
          ),
        ],
      ),
    ),
  );
}

// showSearchDialog, showFindDialog, showSearchResultsDialog moved to search_dialogs.dart

/// DC-15: Compare local file MD5 against a remote file's size (or MD5 if downloadable).
void _verifyAgainstRemote(
  BuildContext context,
  WidgetRef ref,
  FileItem localFile,
  FileItem remoteFile,
) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => FutureBuilder<Map<String, dynamic>>(
      future: _computeVerification(localFile, remoteFile, ref),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('Computing checksum…'),
              ],
            ),
          );
        }
        if (snap.error != null) {
          return AlertDialog(
            title: const Text('Verify failed'),
            content: Text('${snap.error}'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          );
        }
        final data = snap.data!;
        final localMd5 = data['localMd5'] as String;
        final remoteMd5 = data['remoteMd5'] as String?;
        final localSize = data['localSize'] as int;
        final remoteSize = data['remoteSize'] as int?;
        final sizeMatch = remoteSize == null || localSize == remoteSize;
        final md5Match = remoteMd5 == null || localMd5 == remoteMd5;
        final allOk = sizeMatch && md5Match;

        return AlertDialog(
          title: Row(
            children: [
              Icon(
                allOk ? Icons.check_circle : Icons.warning,
                color: allOk ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 8),
              Text(allOk ? 'Files match' : 'Possible mismatch'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Local: ${formatBytes(localSize)}',
                style: const TextStyle(fontSize: 13),
              ),
              if (remoteSize != null)
                Text(
                  'Remote: ${formatBytes(remoteSize)}',
                  style: TextStyle(
                    fontSize: 13,
                    color: sizeMatch ? null : Colors.red,
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'MD5: ${localMd5.substring(0, 12)}…',
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
              if (remoteMd5 != null)
                Text(
                  'Remote MD5: ${remoteMd5.substring(0, 12)}…',
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: md5Match ? null : Colors.red,
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        );
      },
    ),
  );
}

Future<Map<String, dynamic>> _computeVerification(
  FileItem localFile,
  FileItem remoteFile,
  WidgetRef ref,
) async {
  final left = ref
      .read(panelProvider(PanelSide.local))
      .originForOperation(localFile);
  final right = ref
      .read(panelProvider(PanelSide.remote))
      .originForOperation(remoteFile);
  if (left == null || right == null || !left.isCurrent || !right.isCurrent) {
    throw StateError(
      'Refresh both original sources before verifying their contents.',
    );
  }
  final local = ref.read(localFileServiceProvider);
  final leftBackend = fileOperationBackend(
    source: left.source,
    local: local,
    isCurrent: () => left.isCurrent,
  );
  final rightBackend = fileOperationBackend(
    source: right.source,
    local: local,
    isCurrent: () => right.isCurrent,
  );
  final localMd5 = await ChecksumService.hashFile(
    leftBackend,
    localFile,
    ChecksumAlgorithm.md5,
  );
  final remoteMd5 = await ChecksumService.hashFile(
    rightBackend,
    remoteFile,
    ChecksumAlgorithm.md5,
  );
  return {
    'localMd5': localMd5,
    'remoteMd5': remoteMd5,
    'localSize': (await leftBackend.stat(localFile.path!))!.size ?? 0,
    'remoteSize': (await rightBackend.stat(remoteFile.path!))!.size,
  };
}
