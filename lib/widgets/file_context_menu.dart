// widgets/file_context_menu.dart

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/archive_service.dart';
import '../services/checksum_service.dart';
import '../services/cloud_storage_interface.dart' show CloudProvider;
import '../services/sftp_client_adapter.dart';
import '../services/share_service.dart';
import '../utils/formatters.dart' show formatBytes, formatDateFull;
import 'package:path/path.dart' as p;
import 'batch_rename_dialog.dart' show showBatchRenameDialog;
import 'diff_viewer_dialog.dart' show showDiffViewerDialog;
import 'file_editor_dialog.dart' show showFileEditorDialog;
import 'file_list_view.dart' show getFileIcon;
import 'share_link_dialog.dart' show showShareLinkDialog;
import 'permissions_dialog.dart' show showPermissionsDialog;
import 'version_history_dialog.dart' show showVersionHistoryDialog;

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

  // Edit (single text/code file, not folder)
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
    if (editableExts.contains(ext) || !file.name.contains('.')) {
      items.add(
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.edit),
              SizedBox(width: 8),
              Text('Edit'),
            ],
          ),
          onTap: () => Future.delayed(
            Duration.zero,
            () => showFileEditorDialog(context, ref, file, side),
          ),
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

  // Share (mobile platforms only)
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

  // Share link (remote, single file, provider supports sharing)
  if (side == PanelSide.remote && !isMultiSelect && ref.read(authProvider).client.supportsSharing) {
    items.add(
      PopupMenuItem(
        child: const Row(
          children: [Icon(Icons.link), SizedBox(width: 8), Text('Share Link')],
        ),
        onTap: () => Future.delayed(Duration.zero, () => showShareLinkDialog(context, ref, file)),
      ),
    );
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
    // Extract: show for single .zip file
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
    builder: (context) => AlertDialog(
      title: Row(
        children: [
          Icon(file.isFolder ? Icons.folder : Icons.insert_drive_file),
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
          children: [
            _propertyRow(context, 'Type', file.isFolder ? 'Folder' : 'File'),
            if (file.size != null)
              _propertyRow(context, 'Size', formatBytes(file.size!)),
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
            if (!file.isFolder && file.name.contains('.'))
              _propertyRow(
                context,
                'Extension',
                file.name.split('.').last.toUpperCase(),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
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

// showSearchDialog, showFindDialog, showSearchResultsDialog moved to search_dialogs.dart
