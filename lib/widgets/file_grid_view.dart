// lib/widgets/file_grid_view.dart
//
// Grid/gallery view for file listing. Alternative to FileListView.
// Shows files as icon cards with name and size underneath.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:typed_data';
import 'dart:io';

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/thumbnail_service.dart';
import '../utils/formatters.dart';
import 'file_context_menu.dart';
import 'file_list_view.dart' show getFileIcon;

class FileGridView extends ConsumerWidget {
  final PanelSide side;
  final List<FileItem> files;
  final ScrollController scrollController;

  const FileGridView({
    super.key,
    required this.side,
    required this.files,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final panel = ref.watch(panelProvider(side));

    if (files.isEmpty) {
      return const Center(child: Text('Empty folder'));
    }

    return GridView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 140,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: 0.85,
      ),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = files[index];
        final isSelected = panel.isSelected(file);

        return _FileGridTile(
          file: file,
          side: side,
          isSelected: isSelected,
          onTap: () {
            final shiftPressed = HardwareKeyboard.instance.isShiftPressed;
            final ctrlPressed = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
            panel.toggleSelection(file, shiftKey: shiftPressed, ctrlKey: ctrlPressed);
          },
          onDoubleTap: () => panel.navigateInto(file),
          onSecondaryTap: (details) => showFileContextMenu(context, ref, side, file, details.globalPosition),
        );
      },
    );
  }
}

class _FileGridTile extends ConsumerStatefulWidget {
  final FileItem file;
  final PanelSide side;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final Function(TapDownDetails) onSecondaryTap;

  const _FileGridTile({
    required this.file,
    required this.side,
    required this.isSelected,
    required this.onTap,
    required this.onDoubleTap,
    required this.onSecondaryTap,
  });

  @override
  ConsumerState<_FileGridTile> createState() => _FileGridTileState();
}

class _FileGridTileState extends ConsumerState<_FileGridTile> {
  Uint8List? _thumbnail;
  bool _loadingThumb = false;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  @override
  void didUpdateWidget(covariant _FileGridTile old) {
    super.didUpdateWidget(old);
    if (old.file != widget.file) _loadThumbnail();
  }

  Future<void> _loadThumbnail() async {
    if (widget.file.isFolder || !ThumbnailService.isSupported(widget.file.name)) return;
    if (_loadingThumb) return;

    final thumbService = ref.read(thumbnailServiceProvider);
    final key = widget.side == PanelSide.local
        ? ThumbnailService.localKey(widget.file.path ?? widget.file.name)
        : ThumbnailService.remoteKey(
            ref.read(authProvider).providerName,
            widget.file.path ?? '/${widget.file.name}',
          );

    // Check memory cache first (sync)
    final cached = thumbService.getCached(key);
    if (cached != null) {
      if (mounted) setState(() => _thumbnail = cached);
      return;
    }

    // For local files, load and generate thumbnail
    if (widget.side == PanelSide.local && widget.file.path != null) {
      setState(() => _loadingThumb = true);
      try {
        final bytes = await File(widget.file.path!).readAsBytes();
        final thumb = await thumbService.generate(key, bytes);
        if (mounted) setState(() { _thumbnail = thumb; _loadingThumb = false; });
      } catch (_) {
        if (mounted) setState(() => _loadingThumb = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final file = widget.file;

    Widget iconWidget;
    if (_thumbnail != null) {
      iconWidget = ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.memory(_thumbnail!, width: 48, height: 48, fit: BoxFit.cover),
      );
    } else {
      iconWidget = Icon(
        file.isFolder ? Icons.folder : getFileIcon(file.name),
        color: file.isFolder ? Colors.amber : theme.colorScheme.onSurfaceVariant,
        size: 40,
      );
    }

    return GestureDetector(
      onSecondaryTapDown: widget.onSecondaryTap,
      onDoubleTap: widget.onDoubleTap,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: widget.isSelected
                ? theme.colorScheme.primaryContainer.withOpacity(0.5)
                : null,
            border: widget.isSelected
                ? Border.all(color: theme.colorScheme.primary, width: 1.5)
                : Border.all(color: Colors.transparent, width: 1.5),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              iconWidget,
              const SizedBox(height: 6),
              Text(
                file.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              if (!file.isFolder && file.size != null)
                Text(
                  formatBytes(file.size!),
                  style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
