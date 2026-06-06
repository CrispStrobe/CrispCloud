// widgets/file_context_menu.dart
// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/archive_service.dart';
import '../services/checksum_service.dart' show ChecksumService, ChecksumVerifyResult;
import '../services/file_split_service.dart';
import '../services/link_service.dart';
import '../services/secure_wipe_service.dart';
import '../services/log_service.dart';
import '../services/sftp_client_adapter.dart';
import '../services/share_service.dart';
import '../utils/formatters.dart' show formatBytes, formatDateFull;
import 'package:path/path.dart' as p;
import 'batch_rename_dialog.dart' show showBatchRenameDialog;
import 'diff_viewer_dialog.dart' show showDiffViewerDialog;
import 'file_editor_dialog.dart' show showFileEditorDialog;
import 'share_link_dialog.dart' show showShareLinkDialog;
import 'permissions_dialog.dart' show showPermissionsDialog;
import 'version_history_dialog.dart' show showVersionHistoryDialog;

const _log = Log('FileContextMenu');

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
          const SnackBar(content: Text('No system editor found for this file type')),
        );
      }
    }
  } catch (e) {
    _log.error('Failed to open with system editor: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open file: $e')),
      );
    }
  }
}

void showFileContextMenu(BuildContext context, WidgetRef ref, PanelSide side, FileItem file, Offset position) {
  final panel = ref.read(panelProvider(side));
  final selection = panel.selection;

  final files = selection.contains(file) && selection.isNotEmpty
      ? selection.toList()
      : [file];

  if (!selection.contains(file)) {
    panel.clearSelection();
    panel.toggleSelection(file);
  }

  final isMultiSelect = files.length > 1;
  final isSingleFolder = files.length == 1 && files.first.isFolder;

  // Build items list dynamically
  final items = <PopupMenuEntry<dynamic>>[];

  // Open (folders only)
  if (isSingleFolder) {
    items.add(
      PopupMenuItem(
        child: const Row(
          children: [
            Icon(Icons.folder_open),
            SizedBox(width: 8),
            Text('Open'),
          ],
        ),
        onTap: () => Future.delayed(
          Duration.zero,
          () => ref.read(panelProvider(side)).navigateInto(file),
        ),
      ),
    );
  }

  // Edit (single text/code file, not folder) — submenu: built-in vs system editor
  if (!isMultiSelect && !isSingleFolder) {
    final editableExts = {
      'txt', 'json', 'yaml', 'yml', 'xml', 'csv', 'log', 'ini', 'cfg',
      'conf', 'toml', 'env', 'gitignore', 'dockerfile', 'md', 'markdown',
      'dart', 'js', 'ts', 'jsx', 'tsx', 'py', 'rb', 'go', 'rs', 'java',
      'kt', 'swift', 'c', 'cpp', 'h', 'hpp', 'cs', 'php', 'html', 'css',
      'scss', 'less', 'sql', 'sh', 'bash', 'zsh', 'ps1', 'bat', 'r',
      'lua', 'vim', 'makefile', 'properties', 'gradle',
    };
    final ext = file.name.split('.').last.toLowerCase();
    final preferExternal = ref.read(preferExternalEditorProvider);
    if (editableExts.contains(ext) || !file.name.contains('.')) {
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
              Icon(preferExternal ? Icons.edit_note : Icons.open_in_new, size: 20),
              const SizedBox(width: 8),
              Text(preferExternal ? 'Edit (Built-in)' : 'Open with System Editor'),
            ],
          ),
          onTap: () => Future.delayed(Duration.zero, () {
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

  // Compare with opposite panel (single non-folder file, both panels connected)
  if (!isMultiSelect && !isSingleFolder && ref.read(authProvider).isConnected) {
    final oppositeSide = side == PanelSide.local ? PanelSide.remote : PanelSide.local;
    final oppositePanel = ref.read(panelProvider(oppositeSide));
    // Look for a file with the same name in the opposite panel
    final matchingFile = (oppositePanel.files ?? []).where((f) => f.name == file.name && !f.isFolder).toList();
    if (matchingFile.isNotEmpty) {
      items.add(
        PopupMenuItem(
          child: const Row(
            children: [Icon(Icons.compare_arrows), SizedBox(width: 8), Text('Compare')],
          ),
          onTap: () => Future.delayed(Duration.zero, () {
            if (side == PanelSide.local) {
              showDiffViewerDialog(context, ref, file, matchingFile.first,
                  leftSide: PanelSide.local, rightSide: PanelSide.remote);
            } else {
              showDiffViewerDialog(context, ref, matchingFile.first, file,
                  leftSide: PanelSide.local, rightSide: PanelSide.remote);
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
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS) && side == PanelSide.local) {
    items.add(
      PopupMenuItem(
        child: Row(
          children: [
            const Icon(Icons.share),
            const SizedBox(width: 8),
            Text('Share${isMultiSelect ? ' (${files.length})' : ''}'),
          ],
        ),
        onTap: () => Future.delayed(
          Duration.zero,
          () {
            final paths = files.where((f) => f.path != null).map((f) => f.path!).toList();
            ShareService.shareFiles(paths);
          },
        ),
      ),
    );
  }

  // Share (mobile platforms only — remote files)
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS) && side == PanelSide.remote && !isMultiSelect && !isSingleFolder) {
    final client = ref.read(authProvider).client;

    // "Share Link" — only for providers with native share APIs
    if (client.supportsNativeShare) {
      items.add(
        PopupMenuItem(
          child: const Row(
            children: [Icon(Icons.link), SizedBox(width: 8), Text('Share Link')],
          ),
          onTap: () => Future.delayed(Duration.zero, () async {
            try {
              showShareLinkDialog(context, ref, file);
            } catch (e) {
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
        child: const Row(
          children: [Icon(Icons.share), SizedBox(width: 8), Text('Share File')],
        ),
        onTap: () => Future.delayed(Duration.zero, () async {
          // Show loading snackbar
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 12),
                  Text('Preparing file for sharing...'),
                ],
              ),
              duration: Duration(seconds: 30),
            ),
          );
          try {
            final remotePath = file.path ?? p.posix.join(panel.currentPath, file.name);
            final tempPath = p.join(Directory.systemTemp.path, file.name);
            await client.downloadFileByPath(remotePath, tempPath);
            if (context.mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
            await Share.shareXFiles([XFile(tempPath)], text: file.name);
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Share failed: $e')),
              );
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

  // Copy to...
  items.add(
    PopupMenuItem(
      child: Row(
        children: [
          const Icon(Icons.content_copy),
          const SizedBox(width: 8),
          Text('Copy to...${isMultiSelect ? ' (${files.length})' : ''}'),
        ],
      ),
      onTap: () => Future.delayed(
        Duration.zero,
        () => _showCopyDialog(context, ref, side, files),
      ),
    ),
  );

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
      onTap: () => Future.delayed(
        Duration.zero,
        () => _showMoveDialog(context, ref, side, files),
      ),
    ),
  );

  // Rename (single item only)
  if (!isMultiSelect) {
    items.add(
      PopupMenuItem(
        child: const Row(
          children: [
            Icon(Icons.edit),
            SizedBox(width: 8),
            Text('Rename (F2)'),
          ],
        ),
        onTap: () => Future.delayed(
          Duration.zero,
          () => showRenameDialog(context, ref, side, file),
        ),
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
        onTap: () => Future.delayed(
          Duration.zero,
          () => showBatchRenameDialog(context, ref, side, files),
        ),
      ),
    );
  }

  // Share link (remote, single file, provider supports sharing — non-mobile or no supportsNativeShare)
  if (side == PanelSide.remote && !isMultiSelect && ref.read(authProvider).client.supportsSharing) {
    // On mobile with supportsNativeShare, Share Link is already shown above; avoid duplicate
    final isMobileNative = !kIsWeb && (Platform.isAndroid || Platform.isIOS) && ref.read(authProvider).client.supportsNativeShare;
    if (!isMobileNative) {
      items.add(
        PopupMenuItem(
          child: const Row(
            children: [Icon(Icons.link), SizedBox(width: 8), Text('Share Link')],
          ),
          onTap: () => Future.delayed(Duration.zero, () => showShareLinkDialog(context, ref, file)),
        ),
      );
    }
  }

  // Version history (remote, single file, provider supports versioning)
  if (side == PanelSide.remote && !isMultiSelect && !isSingleFolder && ref.read(authProvider).client.supportsVersioning) {
    items.add(const PopupMenuDivider());
    items.add(
      PopupMenuItem(
        child: const Row(
          children: [Icon(Icons.history), SizedBox(width: 8), Text('Version History')],
        ),
        onTap: () => Future.delayed(Duration.zero, () => showVersionHistoryDialog(context, ref, file)),
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
            children: [Icon(Icons.security), SizedBox(width: 8), Text('Permissions')],
          ),
          onTap: () => Future.delayed(Duration.zero, () => showPermissionsDialog(context, ref, file)),
        ),
      );
    }
  }

  // Archive operations (local files only, not on web)
  if (!kIsWeb && side == PanelSide.local) {
    // Browse archive: show for single archive file
    if (!isMultiSelect && ArchiveService.isArchive(file.name) && file.path != null) {
      items.add(
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.folder_zip),
              SizedBox(width: 8),
              Text('Browse Archive'),
            ],
          ),
          onTap: () => Future.delayed(Duration.zero, () {
            ref.read(panelProvider(side)).enterArchive(file);
          }),
        ),
      );
    }
    // Extract: show for single archive file
    if (!isMultiSelect && ArchiveService.isArchive(file.name) && file.path != null) {
      items.add(
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.unarchive),
              SizedBox(width: 8),
              Text('Extract Here'),
            ],
          ),
          onTap: () => Future.delayed(Duration.zero, () async {
            try {
              final dir = p.dirname(file.path!);
              await ArchiveService.extractZip(file.path!, dir);
              ref.read(panelProvider(PanelSide.local)).refresh();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Archive extracted successfully')),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Extract failed: $e')),
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
              Text('Create Zip${isMultiSelect ? ' (${files.length})' : ''}'),
            ],
          ),
          onTap: () => Future.delayed(Duration.zero, () async {
            try {
              final paths = files.where((f) => f.path != null && !f.isFolder).map((f) => f.path!).toList();
              if (paths.isEmpty) return;
              final basePath = p.dirname(paths.first);
              final zipBytes = await ArchiveService.createZip(paths, basePath: basePath);
              final zipName = isMultiSelect ? 'archive.zip' : '${p.basenameWithoutExtension(files.first.name)}.zip';
              final zipPath = p.join(basePath, zipName);
              await File(zipPath).writeAsBytes(zipBytes);
              ref.read(panelProvider(PanelSide.local)).refresh();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Created $zipName')),
                );
              }
            } catch (e) {
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

  items.add(const PopupMenuDivider());

  // Properties / Info
  if (!isMultiSelect) {
    items.add(
      PopupMenuItem(
        child: const Row(
          children: [
            Icon(Icons.info_outline),
            SizedBox(width: 8),
            Text('Properties'),
          ],
        ),
        onTap: () => Future.delayed(
          Duration.zero,
          () => _showPropertiesDialog(context, file),
        ),
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
        onTap: () => Future.delayed(
          Duration.zero,
          () => _showFolderSize(context, file),
        ),
      ),
    );
  }

  // Copy names / paths to clipboard
  items.add(
    PopupMenuItem(
      child: const Row(children: [Icon(Icons.content_copy, size: 20), SizedBox(width: 8), Text('Copy name(s)')]),
      onTap: () {
        final sel = panel.selection;
        final items2 = sel.isEmpty
            ? (file.name != '..' ? {file} : <FileItem>{})
            : sel;
        Clipboard.setData(ClipboardData(
          text: items2.map((f) => f.name).join('\n'),
        ));
      },
    ),
  );
  items.add(
    PopupMenuItem(
      child: const Row(children: [Icon(Icons.link, size: 20), SizedBox(width: 8), Text('Copy path(s)')]),
      onTap: () {
        final sel = panel.selection;
        final items2 = sel.isEmpty
            ? (file.name != '..' ? {file} : <FileItem>{})
            : sel;
        Clipboard.setData(ClipboardData(
          text: items2.map((f) => f.path ?? f.name).join('\n'),
        ));
      },
    ),
  );

  // Checksum (local files only, not folders, not on web)
  if (!isMultiSelect && !file.isFolder && !kIsWeb && side == PanelSide.local && file.path != null) {
    items.add(
      PopupMenuItem(
        child: const Row(
          children: [
            Icon(Icons.fingerprint),
            SizedBox(width: 8),
            Text('Checksum'),
          ],
        ),
        onTap: () => Future.delayed(
          Duration.zero,
          () => _showChecksumDialog(context, file),
        ),
      ),
    );
  }

  // Create/verify .md5 checksum files (local files, not web)
  if (!kIsWeb && side == PanelSide.local) {
    final selectedFiles = panel.selection.isEmpty ? [file] : panel.selection.toList();
    final localFiles = selectedFiles.where((f) => !f.isFolder && f.path != null && f.name != '..').toList();
    if (localFiles.isNotEmpty) {
      items.add(
        PopupMenuItem(
          child: const Row(children: [
            Icon(Icons.playlist_add_check, size: 20), SizedBox(width: 8), Text('Create .md5 file'),
          ]),
          onTap: () => Future.delayed(Duration.zero, () =>
            _createChecksumFileDialog(context, localFiles, 'md5')),
        ),
      );
    }
    // Verify if single .md5/.sha256 file selected
    if (!isMultiSelect && !file.isFolder && file.path != null) {
      final ext = file.name.toLowerCase();
      if (ext.endsWith('.md5') || ext.endsWith('.sha256')) {
        items.add(
          PopupMenuItem(
            child: const Row(children: [
              Icon(Icons.verified, size: 20), SizedBox(width: 8), Text('Verify checksum file'),
            ]),
            onTap: () => Future.delayed(Duration.zero, () =>
              _verifyChecksumFileDialog(context, file.path!)),
          ),
        );
      }
    }
  }

  // Split file (local, single file > 1 MB, not web)
  if (!kIsWeb && side == PanelSide.local && !isMultiSelect && !file.isFolder && file.path != null && (file.size ?? 0) > 1024 * 1024) {
    items.add(
      PopupMenuItem(
        child: const Row(
          children: [Icon(Icons.call_split, size: 20), SizedBox(width: 8), Text('Split File')],
        ),
        onTap: () => Future.delayed(Duration.zero, () => _showSplitDialog(context, ref, side, file)),
      ),
    );
  }

  // Combine parts (local, multi-select with .partNNN files)
  if (!kIsWeb && side == PanelSide.local && isMultiSelect && files.any((f) => RegExp(r'\.part\d{3}$').hasMatch(f.name))) {
    items.add(
      PopupMenuItem(
        child: const Row(
          children: [Icon(Icons.merge_type, size: 20), SizedBox(width: 8), Text('Combine Parts')],
        ),
        onTap: () => Future.delayed(Duration.zero, () => _showCombineDialog(context, ref, side, files)),
      ),
    );
  }

  // Create symlink (local or SFTP, single file, desktop only)
  if (!kIsWeb && !isMultiSelect && (side == PanelSide.local || (side == PanelSide.remote && ref.read(authProvider).client is SFTPClientAdapter))) {
    if (!kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows)) {
      items.add(
        PopupMenuItem(
          child: const Row(
            children: [Icon(Icons.link, size: 20), SizedBox(width: 8), Text('Create Link...')],
          ),
          onTap: () => Future.delayed(Duration.zero, () => _showCreateLinkDialog(context, ref, side, file)),
        ),
      );
    }
  }

  // Secure wipe (local files, desktop only)
  if (!kIsWeb && side == PanelSide.local && (Platform.isMacOS || Platform.isLinux || Platform.isWindows)) {
    items.add(
      PopupMenuItem(
        child: Row(
          children: [
            Icon(Icons.delete_forever, size: 20, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 8),
            Text(
              'Secure Wipe${isMultiSelect ? ' (${files.length})' : ''}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ),
        onTap: () => Future.delayed(Duration.zero, () => _showSecureWipeDialog(context, ref, side, files)),
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
      onTap: () => Future.delayed(
        Duration.zero,
        () => confirmDelete(context, ref, side, files),
      ),
    ),
  );

  // Plugin-contributed context menu items
  final pluginRegistry = ref.read(pluginRegistryProvider);
  final filePaths = files.where((f) => f.path != null).map((f) => f.path!).toList();
  final pluginItems = pluginRegistry.getContextMenuItems(filePaths);
  if (pluginItems.isNotEmpty) {
    items.add(const PopupMenuDivider());
    for (final menuItem in pluginItems) {
      if (!menuItem.enabled) continue;
      items.add(
        PopupMenuItem(
          onTap: menuItem.onSelected != null
              ? () => Future.delayed(Duration.zero, () => menuItem.onSelected!(filePaths))
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
    position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
    items: items,
  );
}

void showRenameDialog(BuildContext context, WidgetRef ref, PanelSide side, FileItem file) {
  final controller = TextEditingController(text: file.name);

  // Select filename without extension
  final dotIndex = file.name.lastIndexOf('.');
  if (dotIndex > 0 && !file.isFolder) {
    controller.selection = TextSelection(baseOffset: 0, extentOffset: dotIndex);
  } else {
    controller.selection = TextSelection(baseOffset: 0, extentOffset: file.name.length);
  }

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Rename'),
      content: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: 'New name',
          border: const OutlineInputBorder(),
          prefixIcon: Icon(file.isFolder ? Icons.folder : Icons.insert_drive_file),
        ),
        autofocus: true,
        onSubmitted: (value) async {
          if (value.isNotEmpty && value != file.name) {
            await ref.read(panelProvider(side)).renameFile(file, value);
            if (context.mounted) Navigator.pop(context);
          }
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            if (controller.text.isNotEmpty && controller.text != file.name) {
              await ref.read(panelProvider(side)).renameFile(file, controller.text);
              if (context.mounted) Navigator.pop(context);
            }
          },
          child: const Text('Rename'),
        ),
      ],
    ),
  );
}

void _showCopyDialog(BuildContext context, WidgetRef ref, PanelSide side, List<FileItem> files) {
  _showPathDialog(context, ref, side, files, 'Copy',
      (fs, path) => ref.read(panelProvider(side)).copyFiles(fs, path));
}

void _showMoveDialog(BuildContext context, WidgetRef ref, PanelSide side, List<FileItem> files) {
  _showPathDialog(context, ref, side, files, 'Move',
      (fs, path) => ref.read(panelProvider(side)).moveFiles(fs, path));
}

void showCopyDialog(BuildContext context, WidgetRef ref, PanelSide side, List<FileItem> files) {
  _showCopyDialog(context, ref, side, files);
}

void showMoveDialog(BuildContext context, WidgetRef ref, PanelSide side, List<FileItem> files) {
  _showMoveDialog(context, ref, side, files);
}

void _showPathDialog(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
  List<FileItem> files,
  String operation,
  Future<void> Function(List<FileItem>, String) action,
) {
  final controller = TextEditingController(
    text: ref.read(panelProvider(side)).currentPath,
  );

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('$operation ${files.length} item(s)'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Items:',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          ...files.take(3).map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Icon(
                  f.isFolder ? Icons.folder : Icons.insert_drive_file,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    f.name,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          )),
          if (files.length > 3)
            Text(
              '... and ${files.length - 3} more',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Target path',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.folder_open),
            ),
            autofocus: true,
            onSubmitted: (value) async {
              if (value.isNotEmpty) {
                await action(files, value);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            if (controller.text.isNotEmpty) {
              await action(files, controller.text);
              if (context.mounted) Navigator.pop(context);
            }
          },
          child: Text(operation),
        ),
      ],
    ),
  );
}

void confirmDelete(BuildContext context, WidgetRef ref, PanelSide side, List<FileItem> files) {
  final totalSize = files.fold<int>(0, (sum, file) => sum + (file.size ?? 0));

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(
        Icons.warning,
        color: Theme.of(context).colorScheme.error,
        size: 48,
      ),
      title: const Text('Confirm Delete'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Are you sure you want to delete ${files.length} item(s)?',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          if (totalSize > 0)
            Text(
              'Total size: ${formatBytes(totalSize)}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This action cannot be undone.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            await ref.read(panelProvider(side)).deleteFiles(files);
            if (context.mounted) Navigator.pop(context);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
}

void _showPropertiesDialog(BuildContext context, FileItem file) {
  showDialog(
    context: context,
    builder: (context) => _PropertiesDialog(file: file),
  );
}

class _PropertiesDialog extends StatefulWidget {
  final FileItem file;
  const _PropertiesDialog({required this.file});

  @override
  State<_PropertiesDialog> createState() => _PropertiesDialogState();
}

class _PropertiesDialogState extends State<_PropertiesDialog> {
  FileStat? _stat;
  String? _md5;
  bool _computingMd5 = false;

  @override
  void initState() {
    super.initState();
    _loadStat();
  }

  Future<void> _loadStat() async {
    if (widget.file.path != null && !kIsWeb) {
      try {
        final stat = await FileStat.stat(widget.file.path!);
        if (mounted) setState(() => _stat = stat);
      } catch (_) {}
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
      final hash = await ChecksumService.md5File(widget.file.path!);
      if (mounted) setState(() { _md5 = hash; _computingMd5 = false; });
    } catch (e) {
      if (mounted) setState(() { _md5 = 'Error: $e'; _computingMd5 = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    final isLocal = file.path != null && !kIsWeb;
    final mimeType = file.isFolder ? 'Directory'
        : file.extension.isNotEmpty ? 'File (${file.extension.toUpperCase()})' : 'File';

    return AlertDialog(
      title: Row(
        children: [
          Icon(file.isSymlink == true ? Icons.link
              : file.isFolder ? Icons.folder : Icons.insert_drive_file),
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
              _propertyRow(context, '→ Target', file.symlinkTarget!, mono: true),
            if (file.size != null)
              _propertyRow(context, 'Size', '${formatBytes(file.size!)} (${file.size} bytes)'),
            if (file.path != null)
              _propertyRow(context, 'Path', file.path!, mono: true),
            if (file.uuid != null)
              _propertyRow(context, 'UUID', file.uuid!, mono: true),
            if (file.updatedAt != null)
              _propertyRow(context, 'Modified', formatDateFull(file.updatedAt!)),
            if (_stat != null) ...[
              _propertyRow(context, 'Created', formatDateFull(_stat!.changed)),
              _propertyRow(context, 'Accessed', formatDateFull(_stat!.accessed)),
              if (!kIsWeb && !Platform.isWindows)
                _propertyRow(context, 'Permissions', _modeString(_stat!.mode), mono: true),
            ],
            if (file.metadata != null)
              ...file.metadata!.entries.map(
                (e) => _propertyRow(context, e.key, '${e.value}', mono: true),
              ),
            // MD5 on demand (local files only)
            if (isLocal && !file.isFolder) ...[
              const Divider(),
              if (_md5 != null)
                _propertyRow(context, 'MD5', _md5!, mono: true)
              else
                TextButton.icon(
                  onPressed: _computingMd5 ? null : _computeMd5,
                  icon: _computingMd5
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.fingerprint, size: 16),
                  label: const Text('Compute MD5'),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }
}

Widget _propertyRow(BuildContext context, String label, String value, {bool mono = false}) {
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
      } catch (_) {
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
                    child: Text(
                      file.name,
                      overflow: TextOverflow.ellipsis,
                    ),
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
                  child: Text(
                    file.name,
                    overflow: TextOverflow.ellipsis,
                  ),
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

void _showChecksumDialog(BuildContext context, FileItem file) {
  if (file.path == null) return;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return FutureBuilder<Map<String, String>>(
        future: () async {
          final md5 = await ChecksumService.md5File(file.path!);
          final sha256 = await ChecksumService.sha256File(file.path!);
          return {'MD5': md5, 'SHA-256': sha256};
        }(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.fingerprint),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      file.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 16),
                  Text('Calculating checksums...'),
                ],
              ),
            );
          }

          if (snapshot.hasError) {
            return AlertDialog(
              title: const Text('Checksum Error'),
              content: Text('Failed to calculate checksum: ${snapshot.error}'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ],
            );
          }

          final checksums = snapshot.data!;
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.fingerprint),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    file.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: checksums.entries.map((e) =>
                  _propertyRow(context, e.key, e.value, mono: true),
                ).toList(),
              ),
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

// --- Split / Combine / Link / Secure Wipe dialogs ---

void _showSplitDialog(BuildContext context, WidgetRef ref, PanelSide side, FileItem file) {
  int chunkSize = 10 * 1024 * 1024; // 10 MB default
  showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Split File'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('File: ${file.name}'),
            if (file.size != null) Text('Size: ${formatBytes(file.size!)}'),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: chunkSize,
              decoration: const InputDecoration(
                labelText: 'Chunk size',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 1024 * 1024, child: Text('1 MB')),
                DropdownMenuItem(value: 10 * 1024 * 1024, child: Text('10 MB')),
                DropdownMenuItem(value: 50 * 1024 * 1024, child: Text('50 MB')),
                DropdownMenuItem(value: 100 * 1024 * 1024, child: Text('100 MB')),
                DropdownMenuItem(value: 500 * 1024 * 1024, child: Text('500 MB')),
              ],
              onChanged: (v) => setState(() => chunkSize = v!),
            ),
            if (file.size != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Will create ${((file.size! + chunkSize - 1) / chunkSize).ceil()} parts',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final dir = p.dirname(file.path!);
                await FileSplitService.splitFile(file.path!, dir, chunkSizeBytes: chunkSize);
                ref.read(panelProvider(side)).refresh();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('File split successfully')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Split failed: $e')),
                  );
                }
              }
            },
            child: const Text('Split'),
          ),
        ],
      ),
    ),
  );
}

void _showCombineDialog(BuildContext context, WidgetRef ref, PanelSide side, List<FileItem> files) {
  // Find the base name from the first part file
  final partFile = files.firstWhere((f) => RegExp(r'\.part\d{3}$').hasMatch(f.name));
  final baseName = partFile.name.replaceAll(RegExp(r'\.part\d{3}$'), '');
  final dir = p.dirname(partFile.path ?? '');

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Combine Parts'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Base name: $baseName'),
          const SizedBox(height: 8),
          const Text('Will scan for all .partNNN files in the directory.'),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () async {
            Navigator.pop(context);
            try {
              final parts = FileSplitService.detectParts(dir, baseName);
              if (parts.isEmpty) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No parts found')),
                  );
                }
                return;
              }
              final outputPath = p.join(dir, baseName);
              await FileSplitService.combineFiles(parts, outputPath);
              ref.read(panelProvider(side)).refresh();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Combined ${parts.length} parts into $baseName')),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Combine failed: $e')),
                );
              }
            }
          },
          child: const Text('Combine'),
        ),
      ],
    ),
  );
}

void _showCreateLinkDialog(BuildContext context, WidgetRef ref, PanelSide side, FileItem file) {
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
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
                    SnackBar(content: Text('${isSymlink ? "Symlink" : "Hard link"} created')),
                  );
                }
              } catch (e) {
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

void _showSecureWipeDialog(BuildContext context, WidgetRef ref, PanelSide side, List<FileItem> files) {
  int passes = 3;

  showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        icon: Icon(Icons.warning, color: Theme.of(context).colorScheme.error, size: 48),
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
                DropdownMenuItem(value: 3, child: Text('3 passes (DoD standard)')),
                DropdownMenuItem(value: 7, child: Text('7 passes (high security)')),
              ],
              onChanged: (v) => setState(() => passes = v!),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
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
                    await SecureWipeService.secureWipeDirectory(file.path!, passes: passes);
                  } else {
                    await SecureWipeService.secureWipe(file.path!, passes: passes);
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

Future<void> _createChecksumFileDialog(
  BuildContext context,
  List<FileItem> files,
  String format,
) async {
  if (files.isEmpty) return;
  final dir = p.dirname(files.first.path!);
  final defaultName = 'checksums.$format';

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => FutureBuilder<String>(
      future: format == 'md5'
          ? ChecksumService.generateMd5File(files.map((f) => f.path!).toList(), dir, outputName: defaultName)
          : ChecksumService.generateSha256File(files.map((f) => f.path!).toList(), dir, outputName: defaultName),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const AlertDialog(
            content: Row(children: [
              CircularProgressIndicator(), SizedBox(width: 16), Text('Generating checksums...'),
            ]),
          );
        }
        final error = snap.error;
        return AlertDialog(
          title: error != null ? const Text('Error') : const Text('Checksum file created'),
          content: error != null
              ? Text('Failed: $error')
              : Text('Created: ${snap.data}'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        );
      },
    ),
  );
}

Future<void> _verifyChecksumFileDialog(BuildContext context, String checksumPath) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => FutureBuilder<List<ChecksumVerifyResult>>(
      future: ChecksumService.verifyChecksumFile(checksumPath),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const AlertDialog(
            content: Row(children: [
              CircularProgressIndicator(), SizedBox(width: 16), Text('Verifying...'),
            ]),
          );
        }
        if (snap.error != null) {
          return AlertDialog(
            title: const Text('Verify failed'),
            content: Text('${snap.error}'),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          );
        }
        final results = snap.data ?? [];
        final failed = results.where((r) => !r.ok).toList();
        return AlertDialog(
          title: Row(children: [
            Icon(failed.isEmpty ? Icons.check_circle : Icons.error,
                color: failed.isEmpty ? Colors.green : Colors.red),
            const SizedBox(width: 8),
            Text(failed.isEmpty ? 'All OK' : '${failed.length} mismatch(es)'),
          ]),
          content: SizedBox(
            width: 400,
            child: ListView(
              shrinkWrap: true,
              children: results.map((r) => ListTile(
                dense: true,
                leading: Icon(r.ok ? Icons.check : Icons.close,
                    color: r.ok ? Colors.green : Colors.red, size: 16),
                title: Text(r.filename, style: const TextStyle(fontSize: 12)),
                subtitle: r.ok ? null : Text('Expected: ${r.expected.substring(0, 8)}…\nGot: ${r.actual.substring(0, 8)}…',
                    style: const TextStyle(fontSize: 11)),
              )).toList(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ],
        );
      },
    ),
  );
}
