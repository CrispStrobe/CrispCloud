import '../l10n/commander_strings.dart';
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
import '../l10n/file_operations_strings.dart';
import '../l10n/provider_operation_strings.dart';
import '../l10n/link_operation_strings.dart';
import '../l10n/checksum_error_strings.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/archive_service.dart';
import '../services/checksum_service.dart'
    show ChecksumService, ChecksumAlgorithm;
import '../services/file_operation_backend.dart';
import '../services/file_bytes_loader.dart';
import '../services/panel_source_service.dart';
import '../services/viewer_spool.dart';
import 'file_origin_actions.dart';
import 'command_extension_actions.dart';
import '../services/cloud_storage_interface.dart'
    show CloudStorageClientCapabilities;
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
import 'file_name_dialog.dart';
import 'file_clipboard_actions.dart';
import 'archive_workspace_dialog.dart';
import 'integrity_dialogs.dart';
import 'integrity_recovery_dialog.dart';
import '../services/file_operation_service.dart';
import 'diff_viewer_dialog.dart' show showDiffViewerDialog;
import 'hex_editor_dialog.dart' show showHexEditorDialog;
import 'editor_chooser_dialog.dart' show showEditorChooser;
import 'file_editor_dialog.dart' show showFileEditorDialog;
import 'pdf_editor_dialog.dart' show isPdfFileName;
import 'pdf_operations_dialog.dart';
import 'share_link_dialog.dart' show showShareLinkDialog;
import 'permissions_dialog.dart' show showPermissionsDialog;
import 'file_attributes_dialog.dart';
import 'version_history_dialog.dart' show showVersionHistoryDialog;

const _log = Log('FileContextMenu');

/// Text/code files are editable via the built-in F4 editor.

Future<void> openListedFileWithSystemEditor(
  BuildContext context,
  WidgetRef ref,
  FileItem file,
) async {
  try {
    if (kIsWeb) throw UnsupportedError('System editor not available');
    final origin = captureFileActionOrigin(ref, file);
    await withNativeFileAction(ref, origin, [requireFilePath(file)], () async {
      if (context.mounted) await openWithSystemEditor(context, file.path!);
    });
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}

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
          SnackBar(
            content: Text(
              context.commanderTr("No system editor found for this file type"),
            ),
          ),
        );
      }
    }
  } catch (e) {
    _log.error('Failed to open with system editor: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.commanderTr("Failed to open file: {0}", [e])),
        ),
      );
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
    panel.captureOperationGroups(files);
  } catch (_) {
    verified = false;
  }
  if (panel.isPagedCollection && !panel.collectionBusy) verified = true;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  PopupMenuItem<void> command(
    String label,
    IconData icon,
    FutureOr<void> Function() action, {
    bool requiresSource = true,
  }) => PopupMenuItem<void>(
    enabled: !requiresSource || verified,
    child: Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(label)),
      ],
    ),
    onTap: () => Future<void>.delayed(Duration.zero, () async {
      if (!context.mounted) {
        return;
      }
      try {
        if (requiresSource) files = await panel.prepareOperationFiles(files);
        if (!context.mounted) return;
        await action();
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(error.toString())));
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
        context.commanderTr("Copy files to clipboard"),
        Icons.content_copy,
        () => copyFilesToClipboard(context, ref, side, items: files),
      ),
      command(
        context.commanderTr("Cut files to clipboard"),
        Icons.content_cut,
        () => copyFilesToClipboard(context, ref, side, cut: true, items: files),
      ),
      if (files.length == 1 &&
          !files.single.isFolder &&
          ArchiveService.isArchive(files.single.name))
        command(
          context.commanderTr("Manage archive…"),
          Icons.archive_outlined,
          () => showArchiveWorkspaceDialog(context, ref, side, files.single),
        ),
      if (files.every((file) => !file.isFolder && file.path != null)) ...[
        command(
          context.commanderTr("Checksums…"),
          Icons.fingerprint,
          () => showChecksumToolsDialog(context, ref, side, files),
        ),
        command(
          context.commanderTr("Split/combine recovery…"),
          Icons.restore,
          () => showIntegrityRecoveryDialog(context, ref),
        ),
        if (files.every((file) => isChecksumManifest(file.name)))
          command(
            context.commanderTr("Verify checksum file"),
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
            context.commanderTr("Split file with integrity manifest…"),
            Icons.call_split,
            () => showSplitFileDialog(context, ref, side, files.single),
          ),
        if (files.every((file) => isSplitPartOrManifest(file.name)))
          command(
            context.commanderTr("Verify and combine parts…"),
            Icons.merge_type,
            () => showCombinePartsDialog(context, ref, side, files),
          ),
      ],
      if (files.length == 1)
        command(
          context.commanderTr("Open containing folder"),
          Icons.folder_open,
          () => panel.openContainingFolder(files.single),
        ),
      command(
        context.commanderTr("Copy with options…"),
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
        context.commanderTr("Move with options…"),
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
        context.commanderTr("Multi-Rename…"),
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
      command(
        context.commanderTr("Change attributes…"),
        Icons.tune,
        () => showFileAttributesDialog(context, ref, side, files),
      ),
      ...buildCommandExtensionMenuItems<void>(context, ref, side, files),
      const PopupMenuDivider(),
      command(
        context.commanderTr("Remove from list (keep files)"),
        Icons.playlist_remove,
        () => panel.removeFromFileList(files),
        requiresSource: false,
      ),
      command(
        context.commanderTr("Delete files…"),
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

  if (panel.isInArchive) {
    showCurrentArchiveWorkspaceDialog(
      context,
      ref,
      side,
      focusedMember: files.length == 1 ? files.single : null,
    );
    return;
  }
  final PanelFileOrigin origin;
  try {
    origin = panel.captureOperationOrigin(files);
  } catch (_) {
    _showResultListContextMenu(context, ref, side, files, position);
    return;
  }
  final native =
      !kIsWeb &&
      origin.source is LocalPanelSource &&
      files.every((entry) => entry.path != null);
  final remote = origin.source is RemotePanelSource
      ? origin.source as RemotePanelSource
      : null;
  final oppositeSide = side == PanelSide.local
      ? PanelSide.remote
      : PanelSide.local;
  PanelFileOrigin? destination;
  try {
    destination = ref.read(panelProvider(oppositeSide)).captureCurrentOrigin();
  } catch (_) {}
  bool current() {
    if (origin.isCurrent) {
      return true;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.commanderTr(
              "The original file account is no longer connected.",
            ),
          ),
        ),
      );
    }
    return false;
  }

  void nativeAction(Iterable<String> paths, Future<void> Function() action) {
    unawaited(() async {
      try {
        await withNativeFileAction(ref, origin, paths, action);
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$error')));
        }
      }
    }());
  }

  void transfer(FileOperationKind kind) {
    if (!context.mounted || !current()) {
      return;
    }
    showFileOperationDialog(
      context,
      ref,
      side,
      files,
      kind: kind,
      sourceOrigin: origin,
      destinationOrigin: destination,
      destinationPath: destination?.source.currentPath,
    );
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
            Expanded(child: Text(context.pdfOpTr(action.label))),
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
            Expanded(child: Text(AppLocalizations.of(context)!.open)),
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
    if (isTextEditableName(file.name)) {
      items.add(
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.tune),
              SizedBox(width: 8),
              Expanded(child: Text('Edit with…')),
            ],
          ),
          onTap: () => Future.delayed(Duration.zero, () {
            if (context.mounted) showEditorChooser(context, ref, file, side);
          }),
        ),
      );
    }
    items.add(
      PopupMenuItem(
        child: const Row(
          children: [
            Icon(Icons.hexagon_outlined),
            SizedBox(width: 8),
            Expanded(child: Text('Edit as Hex')),
          ],
        ),
        onTap: () => Future.delayed(Duration.zero, () {
          if (context.mounted && current())
            showHexEditorDialog(context, ref, file, side);
        }),
      ),
    );
    final preferExternal = native && ref.read(preferExternalEditorProvider);
    if (isImageEditorFileName(file.name)) {
      items.add(
        PopupMenuItem(
          child: Row(
            children: [
              const Icon(Icons.edit_outlined),
              const SizedBox(width: 8),
              Expanded(child: Text(context.imageTr('Edit Image'))),
            ],
          ),
          onTap: () => Future.delayed(Duration.zero, () {
            if (context.mounted) {
              showFileEditorDialog(context, ref, file, side);
            }
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
              Expanded(child: Text(context.pdfTr('Edit PDF'))),
            ],
          ),
          onTap: () => Future.delayed(Duration.zero, () {
            if (context.mounted) {
              showFileEditorDialog(context, ref, file, side);
            }
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
              Expanded(
                child: Text(
                  preferExternal
                      ? context.commanderTr("Edit (System Editor)")
                      : context.commanderTr("Edit (Built-in)"),
                ),
              ),
            ],
          ),
          onTap: () => Future.delayed(Duration.zero, () {
            if (!context.mounted) {
              return;
            }
            if (preferExternal) {
              if (current()) {
                nativeAction([
                  file.path!,
                ], () => openWithSystemEditor(context, file.path!));
              }
            } else {
              showFileEditorDialog(context, ref, file, side);
            }
          }),
        ),
      );
      // Native applications receive verified local paths only.
      if (native) {
        items.add(
          PopupMenuItem(
            child: Row(
              children: [
                Icon(
                  preferExternal ? Icons.edit_note : Icons.open_in_new,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    preferExternal
                        ? context.commanderTr("Edit (Built-in)")
                        : context.commanderTr("Open with System Editor"),
                  ),
                ),
              ],
            ),
            onTap: () => Future.delayed(Duration.zero, () {
              if (!context.mounted) {
                return;
              }
              if (preferExternal) {
                showFileEditorDialog(context, ref, file, side);
              } else if (current()) {
                nativeAction([
                  file.path!,
                ], () => openWithSystemEditor(context, file.path!));
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      context.commanderTr("System editor not available"),
                    ),
                  ),
                );
              }
            }),
          ),
        );
      }
    }
  }

  // Open with system default (all local non-folder files — DC-13 file associations)
  if (!isMultiSelect &&
      !isSingleFolder &&
      native &&
      file.path != null &&
      !isTextEditableName(file.name)) {
    items.add(
      PopupMenuItem(
        child: Row(
          children: [
            const Icon(Icons.open_in_new, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(context.commanderTr("Open with System App"))),
          ],
        ),
        onTap: () => Future.delayed(Duration.zero, () {
          if (!context.mounted) {
            return;
          }
          if (current()) {
            nativeAction([
              file.path!,
            ], () => openWithSystemEditor(context, file.path!));
          }
        }),
      ),
    );
  }

  // Verify copy: compare local file MD5 against same-named file in opposite panel (DC-15)
  if (!isMultiSelect &&
      !isSingleFolder &&
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
          child: Row(
            children: [
              const Icon(Icons.verified, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(context.commanderTr("Verify against other panel")),
              ),
            ],
          ),
          onTap: () => Future.delayed(Duration.zero, () {
            if (!context.mounted) {
              return;
            }
            _verifyAgainstRemote(context, ref, file, oppMatch.first);
          }),
        ),
      );
    }
  }

  // Compare with opposite panel (single non-folder file, both panels connected)
  if (!isMultiSelect && !isSingleFolder) {
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
          child: Row(
            children: [
              const Icon(Icons.compare_arrows),
              const SizedBox(width: 8),
              Expanded(child: Text(context.commanderTr("Compare"))),
            ],
          ),
          onTap: () => Future.delayed(Duration.zero, () {
            if (!context.mounted) {
              return;
            }
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
  if (origin.source is LocalPanelSource &&
      destination?.source is RemotePanelSource) {
    items.add(
      PopupMenuItem(
        child: Row(
          children: [
            const Icon(Icons.upload),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.commanderTr("Upload{0}", [
                  isMultiSelect ? ' (${files.length})' : '',
                ]),
              ),
            ),
          ],
        ),
        onTap: () => Future.delayed(
          Duration.zero,
          () => transfer(FileOperationKind.copy),
        ),
      ),
    );
  }

  // Download to Local
  if (remote != null && destination?.source is LocalPanelSource) {
    items.add(
      PopupMenuItem(
        child: Row(
          children: [
            const Icon(Icons.download),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.commanderTr("Download{0}", [
                  isMultiSelect ? ' (${files.length})' : '',
                ]),
              ),
            ),
          ],
        ),
        onTap: () => Future.delayed(
          Duration.zero,
          () => transfer(FileOperationKind.copy),
        ),
      ),
    );
  }

  // Share (mobile platforms only — local files)
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS) && native) {
    items.add(
      PopupMenuItem(
        child: Row(
          children: [
            const Icon(Icons.share),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.commanderTr("Share{0}", [
                  isMultiSelect ? ' (${files.length})' : '',
                ]),
              ),
            ),
          ],
        ),
        onTap: () => Future.delayed(Duration.zero, () {
          final paths = files
              .where((f) => f.path != null)
              .map((f) => f.path!)
              .toList();
          if (current()) {
            nativeAction(paths, () => ShareService.shareFiles(paths));
          }
        }),
      ),
    );
  }

  // Share (mobile platforms only — remote files)
  if (!kIsWeb &&
      (Platform.isAndroid || Platform.isIOS) &&
      remote != null &&
      !isMultiSelect &&
      !isSingleFolder) {
    final client = remote.client;

    // "Share Link" — only for providers with native share APIs
    if (client.capabilities.nativeShare) {
      items.add(
        PopupMenuItem(
          child: Row(
            children: [
              const Icon(Icons.link),
              const SizedBox(width: 8),
              Expanded(child: Text(AppLocalizations.of(context)!.shareLink)),
            ],
          ),
          onTap: () => Future.delayed(Duration.zero, () async {
            if (!context.mounted) {
              return;
            }
            try {
              showShareLinkDialog(context, ref, file, sourceOrigin: origin);
            } catch (e) {
              _log.warn('operation failed', e);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      context.commanderTr("Share link failed: {0}", [e]),
                    ),
                  ),
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
            Expanded(child: Text(AppLocalizations.of(context)!.shareLink)),
          ],
        ),
        onTap: () => Future.delayed(Duration.zero, () async {
          if (!context.mounted) {
            return;
          }
          // Show loading snackbar
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.commanderTr("Preparing file for sharing..."),
                    ),
                  ),
                ],
              ),
              duration: const Duration(seconds: 30),
            ),
          );
          try {
            requireCurrentOrigin(origin);
            final backend = CloudOperationBackend(
              client,
              isCurrent: () => origin.isCurrent,
            );
            final spool = await createViewerSpool(
              backend,
              file,
              isCancelled: () => !context.mounted,
            );
            try {
              requireCurrentOrigin(origin);
              if (!context.mounted) {
                return;
              }
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              await Share.shareXFiles([XFile(spool.path)], text: file.name);
            } finally {
              await spool.close();
            }
          } catch (e) {
            _log.warn('operation failed', e);
            if (context.mounted) {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(context.commanderTr("Share failed: {0}", [e])),
                ),
              );
            }
          }
        }),
      ),
    );
  }

  // Divider
  if (destination != null) {
    items.add(const PopupMenuDivider());
  }

  // Menus and keyboard shortcuts share the captured clipboard flow.
  items.addAll([
    PopupMenuItem(
      child: ListTile(
        leading: const Icon(Icons.content_copy),
        title: Text(context.commanderTr("Copy files to clipboard")),
      ),
      onTap: () => Future<void>.delayed(Duration.zero, () async {
        if (context.mounted) {
          await copyFilesToClipboard(context, ref, side, items: files);
        }
      }),
    ),
    PopupMenuItem(
      child: ListTile(
        leading: const Icon(Icons.content_cut),
        title: Text(context.commanderTr("Cut files to clipboard")),
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
      child: ListTile(
        leading: const Icon(Icons.content_paste),
        title: Text(context.commanderTr("Paste files with options…")),
      ),
      onTap: () => Future<void>.delayed(Duration.zero, () async {
        if (context.mounted) {
          await pasteFilesFromClipboard(context, ref, side);
        }
      }),
    ),
  ]);

  // Copy to... / Download (web local)
  if (kIsWeb && origin.source is LocalPanelSource) {
    items.add(
      PopupMenuItem(
        child: Row(
          children: [
            const Icon(Icons.download),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.commanderTr("Download{0}", [
                  isMultiSelect ? ' (${files.length})' : '',
                ]),
              ),
            ),
          ],
        ),
        onTap: () => Future.delayed(Duration.zero, () {
          if (context.mounted) {
            _downloadFilesOnWeb(context, ref, files, origin);
          }
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
            Expanded(
              child: Text(
                context.commanderTr("Copy to...{0}", [
                  isMultiSelect ? ' (${files.length})' : '',
                ]),
              ),
            ),
          ],
        ),
        onTap: () => Future.delayed(Duration.zero, () {
          if (!context.mounted) {
            return;
          }
          transfer(FileOperationKind.copy);
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
          Expanded(
            child: Text(
              context.commanderTr("Move to...{0}", [
                isMultiSelect ? ' (${files.length})' : '',
              ]),
            ),
          ),
        ],
      ),
      onTap: () => Future.delayed(Duration.zero, () {
        if (!context.mounted) {
          return;
        }
        transfer(FileOperationKind.move);
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
            Expanded(
              child: Text('${AppLocalizations.of(context)!.rename} (F2)'),
            ),
          ],
        ),
        onTap: () => Future.delayed(Duration.zero, () {
          if (!context.mounted) {
            return;
          }
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
            Expanded(
              child: Text(
                context.commanderTr("Batch Rename ({0})", [files.length]),
              ),
            ),
          ],
        ),
        onTap: () => Future.delayed(Duration.zero, () {
          if (!context.mounted) {
            return;
          }
          showBatchRenameDialog(context, ref, side, files);
        }),
      ),
    );
  }

  // Share link (remote, single file, provider supports sharing — non-mobile or no supportsNativeShare)
  if (remote != null && !isMultiSelect && remote.client.capabilities.sharing) {
    // On mobile with supportsNativeShare, Share Link is already shown above; avoid duplicate
    final isMobileNative =
        !kIsWeb &&
        (Platform.isAndroid || Platform.isIOS) &&
        remote.client.capabilities.nativeShare;
    if (!isMobileNative) {
      items.add(
        PopupMenuItem(
          child: Row(
            children: [
              const Icon(Icons.link),
              const SizedBox(width: 8),
              Expanded(child: Text(AppLocalizations.of(context)!.shareLink)),
            ],
          ),
          onTap: () => Future.delayed(Duration.zero, () {
            if (!context.mounted) {
              return;
            }
            showShareLinkDialog(context, ref, file, sourceOrigin: origin);
          }),
        ),
      );
    }
  }

  // Version history (remote, single file, provider supports versioning)
  if (remote != null &&
      !isMultiSelect &&
      !isSingleFolder &&
      remote.client.capabilities.versioning) {
    items.add(const PopupMenuDivider());
    items.add(
      PopupMenuItem(
        child: Row(
          children: [
            const Icon(Icons.history),
            const SizedBox(width: 8),
            Expanded(child: Text(context.commanderTr("Version History"))),
          ],
        ),
        onTap: () => Future.delayed(Duration.zero, () {
          if (!context.mounted) {
            return;
          }
          showVersionHistoryDialog(context, ref, file, sourceOrigin: origin);
        }),
      ),
    );
  }

  items.add(
    PopupMenuItem(
      child: Row(
        children: [
          const Icon(Icons.tune),
          const SizedBox(width: 8),
          Expanded(child: Text(context.commanderTr("Change attributes…"))),
        ],
      ),
      onTap: () => Future.delayed(Duration.zero, () {
        if (context.mounted) {
          showFileAttributesDialog(
            context,
            ref,
            side,
            files,
            sourceOrigin: origin,
          );
        }
      }),
    ),
  );

  // Permissions (SFTP only, single file)
  if (!isMultiSelect && remote != null) {
    if (remote.client is SFTPClientAdapter) {
      items.add(
        PopupMenuItem(
          child: Row(
            children: [
              const Icon(Icons.security),
              const SizedBox(width: 8),
              Expanded(child: Text(context.commanderTr("Permissions"))),
            ],
          ),
          onTap: () => Future.delayed(Duration.zero, () {
            if (!context.mounted) {
              return;
            }
            showPermissionsDialog(context, ref, file, sourceOrigin: origin);
          }),
        ),
      );
    }
  }

  if (!isMultiSelect && !file.isFolder && ArchiveService.isArchive(file.name)) {
    items.add(
      PopupMenuItem(
        child: ListTile(
          leading: const Icon(Icons.archive_outlined),
          title: Text(context.commanderTr("Manage archive…")),
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
  if (native) {
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
              Expanded(
                child: Text(AppLocalizations.of(context)!.browseArchive),
              ),
            ],
          ),
          onTap: () => Future.delayed(Duration.zero, () {
            if (current()) {
              ref.read(panelProvider(side)).enterArchive(file);
            }
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
              Expanded(child: Text(AppLocalizations.of(context)!.extractHere)),
            ],
          ),
          onTap: () => Future.delayed(Duration.zero, () async {
            try {
              final dir = p.dirname(file.path!);
              await withNativeFileAction(ref, origin, [
                dir,
              ], () => ArchiveService.extractArchive(file.path!, dir));
              ref.read(panelProvider(side)).refresh();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      context.commanderTr("Archive extracted successfully"),
                    ),
                  ),
                );
              }
            } catch (e) {
              _log.warn('operation failed', e);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      context.commanderTr("Extract failed: {0}", [e]),
                    ),
                  ),
                );
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
              Expanded(
                child: Text(
                  context.commanderTr("Create Zip{0}", [
                    isMultiSelect ? ' (${files.length})' : '',
                  ]),
                ),
              ),
            ],
          ),
          onTap: () => Future.delayed(Duration.zero, () async {
            try {
              final paths = files
                  .where((f) => f.path != null)
                  .map((f) => f.path!)
                  .toList();
              if (paths.isEmpty) {
                return;
              }
              final basePath = p.dirname(paths.first);
              final zipBytes = await withNativeFileAction(
                ref,
                origin,
                paths,
                () => ArchiveService.createZip(paths, basePath: basePath),
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
              await withNativeFileAction(ref, origin, [basePath], () async {
                await File(zipPath).create(exclusive: true);
                await File(zipPath).writeAsBytes(zipBytes, flush: true);
              });
              ref.read(panelProvider(side)).refresh();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      context.commanderTr("Created {0}", [zipName]),
                    ),
                  ),
                );
              }
            } catch (e) {
              _log.warn('operation failed', e);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      context.commanderTr("Zip creation failed: {0}", [e]),
                    ),
                  ),
                );
              }
            }
          }),
        ),
      );
    }
  }

  // Reveal in Finder / Explorer (local files only)
  if (native && file.path != null) {
    final revealLabel = Platform.isMacOS
        ? context.commanderTr("Reveal in Finder")
        : Platform.isWindows
        ? context.commanderTr("Show in Explorer")
        : context.commanderTr("Open containing folder");
    items.add(
      PopupMenuItem(
        child: Row(
          children: [
            const Icon(Icons.folder_open, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(revealLabel)),
          ],
        ),
        onTap: () async {
          try {
            requireCurrentOrigin(origin);
            final dir = file.isFolder ? file.path! : p.dirname(file.path!);
            await launchUrl(
              Uri.file(dir),
              mode: LaunchMode.externalApplication,
            );
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
            Expanded(child: Text(AppLocalizations.of(context)!.properties)),
          ],
        ),
        onTap: () => Future.delayed(Duration.zero, () {
          if (!context.mounted) {
            return;
          }
          _showPropertiesDialog(context, file);
        }),
      ),
    );
  }

  // Calculate Size (folders only, not on web)
  if (isSingleFolder && native) {
    items.add(
      PopupMenuItem(
        child: Row(
          children: [
            const Icon(Icons.data_usage),
            const SizedBox(width: 8),
            Expanded(child: Text(context.commanderTr("Calculate Size"))),
          ],
        ),
        onTap: () => Future.delayed(Duration.zero, () {
          if (!context.mounted) {
            return;
          }
          if (current()) {
            _showFolderSize(context, ref, file, origin);
          }
        }),
      ),
    );
  }

  // Copy names / paths to clipboard
  items.add(
    PopupMenuItem(
      child: Row(
        children: [
          const Icon(Icons.content_copy, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(context.commanderTr("Copy name(s)"))),
        ],
      ),
      onTap: () {
        final items2 = files.where((entry) => entry.name != '..');
        Clipboard.setData(
          ClipboardData(text: items2.map((f) => f.name).join('\n')),
        );
      },
    ),
  );
  items.add(
    PopupMenuItem(
      child: Row(
        children: [
          const Icon(Icons.link, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(context.commanderTr("Copy path(s)"))),
        ],
      ),
      onTap: () {
        final items2 = files.where((entry) => entry.name != '..');
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
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(context.commanderTr(label))),
        ],
      ),
      onTap: () => Future<void>.delayed(Duration.zero, () async {
        if (context.mounted) {
          await action();
        }
      }),
    );
    items.add(
      integrityCommand(
        'Checksums…',
        Icons.fingerprint,
        () => showChecksumToolsDialog(context, ref, side, files),
      ),
    );
    items.add(
      integrityCommand(
        'Split/combine recovery…',
        Icons.restore,
        () => showIntegrityRecoveryDialog(context, ref),
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

  // Native symbolic and hard links require a captured local file.
  if (native && !isMultiSelect) {
    if (!kIsWeb &&
        (Platform.isMacOS || Platform.isLinux || Platform.isWindows)) {
      items.add(
        PopupMenuItem(
          child: Row(
            children: [
              const Icon(Icons.link, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(context.commanderTr("Create Link..."))),
            ],
          ),
          onTap: () => Future.delayed(Duration.zero, () {
            if (!context.mounted) {
              return;
            }
            _showCreateLinkDialog(context, ref, side, file, origin);
          }),
        ),
      );
    }
  }

  // Secure wipe (local files, desktop only)
  if (native && (Platform.isMacOS || Platform.isLinux || Platform.isWindows)) {
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
            Expanded(
              child: Text(
                context.commanderTr("Secure Wipe{0}", [
                  isMultiSelect ? ' (${files.length})' : '',
                ]),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ),
        onTap: () => Future.delayed(Duration.zero, () {
          if (!context.mounted) {
            return;
          }
          _showSecureWipeDialog(context, ref, side, files, origin);
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
          Expanded(
            child: Text(
              context.commanderTr("Delete{0}", [
                isMultiSelect ? ' (${files.length})' : '',
              ]),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
      onTap: () => Future.delayed(Duration.zero, () {
        if (!context.mounted) {
          return;
        }
        confirmDelete(context, ref, side, files);
      }),
    ),
  );

  items.addAll(buildCommandExtensionMenuItems(context, ref, side, files));

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

Future<void> showRenameDialog(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
  FileItem file,
) async {
  await showCapturedRenameDialog(context, ref.read(panelProvider(side)), file);
}

/// Download local files on web via browser download.
Future<void> _downloadFilesOnWeb(
  BuildContext context,
  WidgetRef ref,
  List<FileItem> files,
  PanelFileOrigin origin,
) async {
  if (!kIsWeb) {
    return;
  }
  try {
    requireCurrentOrigin(origin);
    if (origin.source is! LocalPanelSource) {
      throw StateError('The original browser folder is unavailable.');
    }
    final backend = fileOperationBackend(
      source: origin.source,
      local: ref.read(localFileServiceProvider),
      isCurrent: () => origin.isCurrent,
    );
    for (final file in files) {
      if (file.isFolder) {
        continue;
      }
      final current = await backend.stat(requireFilePath(file));
      if (current == null || current.isFolder) {
        throw StateError('The original file is unavailable.');
      }
      // The browser Blob fallback necessarily buffers. Larger files use the
      // ordinary Copy dialog and its streaming destination instead.
      final bytes = await readFileBytesBounded(
        backend,
        current,
        maxBytes: 64 * 1024 * 1024,
      );
      requireCurrentOrigin(origin);
      _triggerBrowserDownload(bytes, file.name);
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
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
        if (mounted && _origin?.isCurrent == true) {
          setState(() => _stat = stat);
        }
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
    if (widget.file.path == null) {
      return;
    }
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
          _md5 = FileOperationsStrings(context).value('failed', e);
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
        ? context.commanderTr("Directory")
        : file.extension.isNotEmpty
        ? context.commanderTr("File ({0})", [file.extension.toUpperCase()])
        : context.commanderTr("File");

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
            _propertyRow(context, context.commanderTr("Type"), mimeType),
            if (file.isSymlink == true && file.symlinkTarget != null)
              _propertyRow(
                context,
                context.commanderTr("→ Target"),
                file.symlinkTarget!,
                mono: true,
              ),
            if (file.size != null)
              _propertyRow(
                context,
                context.commanderTr("Size"),
                context.commanderTr("{0} ({1} bytes)", [
                  formatBytes(file.size!),
                  file.size,
                ]),
              ),
            if (file.path != null)
              _propertyRow(
                context,
                context.commanderTr("Path"),
                file.path!,
                mono: true,
              ),
            if (file.uuid != null)
              _propertyRow(
                context,
                context.commanderTr("UUID"),
                file.uuid!,
                mono: true,
              ),
            if (file.updatedAt != null)
              _propertyRow(
                context,
                context.commanderTr("Modified"),
                formatDateFull(file.updatedAt!),
              ),
            if (_stat != null) ...[
              _propertyRow(
                context,
                context.commanderTr("Metadata changed"),
                formatDateFull(_stat!.changed),
              ),
              _propertyRow(
                context,
                context.commanderTr("Accessed"),
                formatDateFull(_stat!.accessed),
              ),
              if (!kIsWeb && !Platform.isWindows)
                _propertyRow(
                  context,
                  context.commanderTr("Permissions"),
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
                _propertyRow(
                  context,
                  context.commanderTr("MD5"),
                  _md5!,
                  mono: true,
                )
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
                  label: Text(context.commanderTr("Compute MD5")),
                ),
            ],
          ],
        ),
      ),
      actions: [
        if (_origin?.isCurrent == true)
          TextButton.icon(
            icon: const Icon(Icons.tune),
            label: Text(context.commanderTr("Change attributes…")),
            onPressed: () async {
              await showFileAttributesDialog(
                context,
                ref,
                ref.read(activePanelProvider),
                [file],
                sourceOrigin: _origin,
              );
              if (mounted) await _loadStat();
            },
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.commanderTr("Close")),
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
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: Theme.of(context).colorScheme.primary),
        ),
        const SizedBox(height: 4),
        SelectableText(
          value,
          textDirection: mono ? TextDirection.ltr : null,
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
  if (!await dir.exists()) {
    return 0;
  }
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

void _showFolderSize(
  BuildContext context,
  WidgetRef ref,
  FileItem file,
  PanelFileOrigin origin,
) {
  if (file.path == null) {
    return;
  }
  final result = withNativeFileAction(ref, origin, [
    file.path!,
  ], () => _calculateFolderSize(file.path!));
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return FutureBuilder<int>(
        future: result,
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
              content: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(width: 16),
                  Text(context.commanderTr("Calculating folder size...")),
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
                if (snapshot.hasError)
                  Text('${snapshot.error}')
                else
                  _propertyRow(
                    context,
                    context.commanderTr("Total Size"),
                    formatBytes(size),
                  ),
                _propertyRow(
                  context,
                  context.commanderTr("Bytes"),
                  size.toString(),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(context.commanderTr("Close")),
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
  PanelFileOrigin origin,
) {
  final controller = TextEditingController(
    text: file.path != null ? '${file.path!}_link' : '',
  );
  bool isSymlink = true;

  showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(context.commanderTr("Create Link")),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.commanderTr("Target: {0}", [file.name])),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: true,
                  label: Text(context.commanderTr("Symlink")),
                ),
                ButtonSegment(
                  value: false,
                  label: Text(context.commanderTr("Hard Link")),
                ),
              ],
              selected: {isSymlink},
              onSelectionChanged: (v) => setState(() => isSymlink = v.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: context.commanderTr("Link path"),
                border: const OutlineInputBorder(),
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
                final target = requireFilePath(file);
                final linkPath = controller.text.trim();
                if (!p.isAbsolute(linkPath) || linkPath == target) {
                  throw ArgumentError('Choose a different absolute link path.');
                }
                await withNativeFileAction(
                  ref,
                  origin,
                  [target, p.dirname(linkPath)],
                  () async {
                    if (isSymlink) {
                      await LinkService.createSymlink(target, linkPath);
                    } else {
                      await LinkService.createHardlink(target, linkPath);
                    }
                  },
                );
                ref.read(panelProvider(side)).refresh();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        context.commanderTr("{0} created", [
                          isSymlink
                              ? context.commanderTr("Symlink")
                              : context.commanderTr("Hard Link"),
                        ]),
                      ),
                    ),
                  );
                }
              } catch (e) {
                _log.warn('operation failed', e);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        context.commanderTr("Link creation failed: {0}", [e]),
                      ),
                    ),
                  );
                }
              }
            },
            child: Text(context.commanderTr("Create")),
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
  PanelFileOrigin origin,
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
        title: Text(context.commanderTr("Secure Wipe")),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.commanderTr(
                "This will overwrite {0} item(s) with random data before deletion. This cannot be undone.",
                [files.length],
              ),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: passes,
              decoration: InputDecoration(
                labelText: context.commanderTr("Overwrite passes"),
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                  value: 1,
                  child: Text(context.commanderTr("1 pass")),
                ),
                DropdownMenuItem(
                  value: 3,
                  child: Text(context.commanderTr("3 passes")),
                ),
                DropdownMenuItem(
                  value: 7,
                  child: Text(context.commanderTr("7 passes")),
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
                  if (file.path == null) {
                    continue;
                  }
                  await withNativeFileAction(
                    ref,
                    origin,
                    [file.path!],
                    () async {
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
                    },
                  );
                }
                ref.read(panelProvider(side)).refresh();
                ref.read(panelProvider(side)).clearSelection();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        context.commanderTr("Secure wipe completed"),
                      ),
                    ),
                  );
                }
              } catch (e) {
                _log.warn('operation failed', e);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        context.commanderTr("Secure wipe failed: {0}", [e]),
                      ),
                    ),
                  );
                }
              }
            },
            child: Text(context.commanderTr("Wipe")),
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
          return AlertDialog(
            content: Row(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(context.commanderTr("Computing checksum…")),
                ),
              ],
            ),
          );
        }
        if (snap.error != null) {
          return AlertDialog(
            title: Text(context.commanderTr("Verify failed")),
            content: Text('${snap.error}'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(context.commanderTr("OK")),
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
              Expanded(
                child: Text(
                  allOk
                      ? context.commanderTr("Files match")
                      : context.commanderTr("Possible mismatch"),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.commanderTr("Left: {0}", [formatBytes(localSize)]),
                style: const TextStyle(fontSize: 13),
              ),
              if (remoteSize != null)
                Text(
                  context.commanderTr("Right: {0}", [formatBytes(remoteSize)]),
                  style: TextStyle(
                    fontSize: 13,
                    color: sizeMatch ? null : Colors.red,
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                context.commanderTr("MD5: {0}…", [localMd5.substring(0, 12)]),
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
              if (remoteMd5 != null)
                Text(
                  context.commanderTr("Right MD5: {0}…", [
                    remoteMd5.substring(0, 12),
                  ]),
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
              child: Text(context.commanderTr("Close")),
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
