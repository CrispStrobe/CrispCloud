// lib/widgets/panel_source_selector.dart
//
// PanelSourceSelector — dropdown in the panel header to switch between
// Local, connected cloud providers, and currently open archives/containers.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/panel_side.dart';
import '../providers/panel_source_provider.dart';
import '../services/panel_source_service.dart';

// ---------------------------------------------------------------------------
// PanelSourceSelector widget
// ---------------------------------------------------------------------------

class PanelSourceSelector extends ConsumerWidget {
  final PanelSide side;

  const PanelSourceSelector({super.key, required this.side});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentSource = ref.watch(panelSourceProvider(side));
    final availableSources = ref.watch(availableSourcesProvider);

    return _SourceDropdown(
      current: currentSource,
      available: availableSources,
      onSelect: (source) =>
          ref.read(panelSourceProvider(side).notifier).setSource(source),
    );
  }
}

// ---------------------------------------------------------------------------
// Internal dropdown
// ---------------------------------------------------------------------------

class _SourceDropdown extends StatelessWidget {
  final PanelSource current;
  final List<AvailableSource> available;
  final void Function(PanelSource source) onSelect;

  const _SourceDropdown({
    required this.current,
    required this.available,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DropdownButton<String>(
      value: _keyFor(current),
      underline: const SizedBox.shrink(),
      icon: const Icon(Icons.arrow_drop_down, size: 18),
      style: theme.textTheme.bodySmall,
      isDense: true,
      items: available.map((entry) {
        return DropdownMenuItem<String>(
          value: entry.key,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_iconFor(entry.source), size: 16),
              const SizedBox(width: 4),
              Text(
                entry.label,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      }).toList(),
      onChanged: (key) {
        if (key == null) return;
        final entry = available.firstWhere(
          (e) => e.key == key,
          orElse: () => available.first,
        );
        onSelect(entry.source);
      },
      selectedItemBuilder: (context) {
        return available.map((entry) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _iconFor(entry.source),
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(
                  entry.label,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          );
        }).toList();
      },
    );
  }

  static String _keyFor(PanelSource source) {
    return switch (source) {
      LocalPanelSource _ => 'local',
      RemotePanelSource s => 'remote:${s.providerName}',
      ArchivePanelSource s => 'archive:${s.archivePath}',
      ContainerPanelSource s => 'container:${s.containerPath}',
    };
  }

  static IconData _iconFor(PanelSource source) {
    return switch (source) {
      LocalPanelSource _ => Icons.folder_outlined,
      RemotePanelSource _ => Icons.cloud_outlined,
      ArchivePanelSource _ => Icons.archive_outlined,
      ContainerPanelSource _ => Icons.lock_outlined,
    };
  }
}

// AvailableSource is defined in panel_source_provider.dart
