// lib/widgets/panel_source_selector.dart
//
// PanelSourceSelector — dropdown in the panel header to switch between
// Local, connected cloud providers, and currently open archives/containers.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../l10n/navigation_strings.dart';
import '../models/panel_side.dart';
import '../models/storage_reference.dart';
import '../providers/panel_source_provider.dart';
import '../services/panel_source_service.dart';
import '../services/storage_identity.dart';

// ---------------------------------------------------------------------------
// PanelSourceSelector widget
// ---------------------------------------------------------------------------

class PanelSourceSelector extends ConsumerWidget {
  final PanelSide side;

  /// A panel header can provide its actual requested/listed storage. Keeping
  /// this projection optional avoids starting a panel just to render a picker.
  final PanelSource? currentSource;
  final StorageReference? currentStorage;
  final String? currentLabel;
  final bool currentAvailable;
  final ValueChanged<PanelSource>? onSelected;

  const PanelSourceSelector({
    super.key,
    required this.side,
    this.currentSource,
    this.currentStorage,
    this.currentLabel,
    this.currentAvailable = true,
    this.onSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedSource = ref.watch(panelSourceProvider(side));
    final availableSources = ref.watch(availableSourcesProvider);
    final source = currentStorage == null
        ? currentSource ?? selectedSource
        : currentSource;

    return _SourceDropdown(
      current: source,
      currentLabel:
          currentLabel ??
          source?.displayName ??
          currentStorage?.provider ??
          selectedSource.displayName,
      currentIsLocal: currentStorage?.isLocal ?? source?.isLocal ?? false,
      currentAvailable: currentAvailable,
      available: availableSources,
      onSelect: (entry) {
        if (!context.mounted) return;
        // A menu can remain open across a connection change. Revalidate the
        // selected entry by its key and exact source, never by provider label.
        for (final live in ref.read(availableSourcesProvider)) {
          if (live.key == entry.key &&
              _sameSource(live.source, entry.source!) &&
              _sourceStorage(live.source) == entry.storage &&
              _sourceAvailable(live.source)) {
            if (onSelected case final select?) {
              select(live.source);
            } else {
              ref
                  .read(panelSourceProvider(side).notifier)
                  .setSource(live.source);
            }
            return;
          }
        }
      },
    );
  }
}

bool _sameSource(PanelSource first, PanelSource second) => switch (first) {
  LocalPanelSource _ => second is LocalPanelSource,
  RemotePanelSource source =>
    second is RemotePanelSource && identical(source.client, second.client),
  ArchivePanelSource source =>
    second is ArchivePanelSource &&
        source.archivePath == second.archivePath &&
        _sameSource(source.parent, second.parent),
  ContainerPanelSource source =>
    second is ContainerPanelSource &&
        source.containerPath == second.containerPath &&
        identical(source.unlockSession, second.unlockSession) &&
        _sameSource(source.parent, second.parent),
};

bool _sourceAvailable(PanelSource source) => switch (source) {
  LocalPanelSource _ => true,
  RemotePanelSource source => source.client.isAuthenticated,
  ArchivePanelSource source => _sourceAvailable(source.parent),
  ContainerPanelSource source => _sourceAvailable(source.parent),
};

StorageReference _sourceStorage(PanelSource source) => switch (source) {
  ArchivePanelSource source => _sourceStorage(source.parent),
  ContainerPanelSource source => _sourceStorage(source.parent),
  _ => storageReferenceForSource(source),
};

class _SourceOption {
  const _SourceOption({
    required this.key,
    required this.label,
    required this.icon,
    required this.enabled,
    this.source,
    this.storage,
  });

  final String key;
  final String label;
  final IconData icon;
  final bool enabled;
  final PanelSource? source;
  final StorageReference? storage;
}

// ---------------------------------------------------------------------------
// Internal dropdown
// ---------------------------------------------------------------------------

class _SourceDropdown extends StatelessWidget {
  final PanelSource? current;
  final String currentLabel;
  final bool currentIsLocal;
  final bool currentAvailable;
  final List<AvailableSource> available;
  final void Function(_SourceOption entry) onSelect;

  const _SourceDropdown({
    required this.current,
    required this.currentLabel,
    required this.currentIsLocal,
    required this.currentAvailable,
    required this.available,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final disconnected = l?.notConnected ?? 'Not connected';
    final entries = [
      for (final entry in available)
        _SourceOption(
          key: entry.key,
          label: entry.source.isLocal
              ? (entry.key == 'local' ? l?.local ?? entry.label : entry.label)
              : _sourceAvailable(entry.source)
              ? entry.label
              : '${entry.label} · $disconnected',
          icon: _sourceAvailable(entry.source)
              ? _iconFor(entry.source)
              : Icons.cloud_off,
          enabled: _sourceAvailable(entry.source),
          source: entry.source,
          storage: _sourceStorage(entry.source),
        ),
    ];
    _SourceOption? selected;
    if (currentAvailable && current != null) {
      // Prefer an exact location entry (for example a local Home shortcut),
      // then find the same storage while browsing one of its subfolders.
      for (final entry in entries) {
        if (entry.source == current) {
          selected = entry;
          break;
        }
      }
      if (selected == null) {
        for (final entry in entries) {
          if (_sameSource(entry.source!, current!)) {
            selected = entry;
            break;
          }
        }
      }
    }
    if (selected == null) {
      var key = 'unavailable';
      while (entries.any((entry) => entry.key == key)) {
        key = '$key:';
      }
      selected = _SourceOption(
        key: key,
        label:
            current is RemotePanelSource || (current == null && !currentIsLocal)
            ? '$currentLabel · $disconnected'
            : currentLabel,
        icon: currentIsLocal
            ? Icons.folder_outlined
            : current == null || current is RemotePanelSource
            ? Icons.cloud_off
            : _iconFor(current!),
        enabled: false,
        source: current,
      );
      entries.add(selected);
    }

    Widget label(_SourceOption entry, {bool selected = false}) {
      final text = Text(
        entry.label,
        overflow: TextOverflow.ellipsis,
        style: selected
            ? theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)
            : null,
      );
      return Tooltip(
        message: entry.enabled
            ? entry.label
            : '${entry.label}\n${NavigationStrings(context).text('unavailable')}',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              entry.icon,
              size: 16,
              color: selected ? theme.colorScheme.primary : null,
            ),
            const SizedBox(width: 4),
            Flexible(child: text),
          ],
        ),
      );
    }

    return DropdownButton<String>(
      value: selected.key,
      underline: const SizedBox.shrink(),
      icon: const Icon(Icons.arrow_drop_down, size: 18),
      style: theme.textTheme.bodySmall,
      isDense: true,
      isExpanded: true,
      items: entries.map((entry) {
        return DropdownMenuItem<String>(
          value: entry.key,
          enabled: entry.enabled,
          child: label(entry),
        );
      }).toList(),
      onChanged: (key) {
        if (key == null) return;
        for (final entry in entries) {
          if (entry.key == key && entry.enabled && entry.source != null) {
            onSelect(entry);
            return;
          }
        }
      },
      selectedItemBuilder: (context) => [
        for (final entry in entries) label(entry, selected: true),
      ],
    );
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
