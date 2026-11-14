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

/// A location offered alongside connected storage accounts.
class PanelSourceLocation {
  const PanelSourceLocation({
    required this.key,
    required this.label,
    required this.icon,
    required this.onSelected,
  });
  final String key;
  final String label;
  final IconData icon;
  final VoidCallback onSelected;
}

class PanelSourceSelector extends ConsumerWidget {
  final PanelSide side;
  final List<PanelSourceLocation> locations;

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
    this.locations = const [],
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
      locations: locations,
      onSelect: (entry) {
        if (!context.mounted) return;
        if (entry.location case final location?) {
          location.onSelected();
          return;
        }
        // A menu can remain open across a connection change. Revalidate the
        // selected entry by its key and exact source, never by provider label.
        for (final live in ref.read(availableSourcesProvider)) {
          if (live.key == entry.key &&
              _sameSource(live.source, entry.source!) &&
              live.source.currentPath == entry.source!.currentPath &&
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
  final RemotePanelSource source =>
    second is RemotePanelSource && identical(source.client, second.client),
  final ArchivePanelSource source =>
    second is ArchivePanelSource &&
        source.archivePath == second.archivePath &&
        _sameSource(source.parent, second.parent),
  final ContainerPanelSource source =>
    second is ContainerPanelSource &&
        source.containerPath == second.containerPath &&
        identical(source.unlockSession, second.unlockSession) &&
        _sameSource(source.parent, second.parent),
};

bool _sourceAvailable(PanelSource source) => switch (source) {
  LocalPanelSource _ => true,
  final RemotePanelSource source => source.client.isAuthenticated,
  final ArchivePanelSource source => _sourceAvailable(source.parent),
  final ContainerPanelSource source => _sourceAvailable(source.parent),
};

StorageReference _sourceStorage(PanelSource source) => switch (source) {
  final ArchivePanelSource source => _sourceStorage(source.parent),
  final ContainerPanelSource source => _sourceStorage(source.parent),
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
    this.location,
  });

  final String key;
  final String label;
  final IconData icon;
  final bool enabled;
  final PanelSource? source;
  final StorageReference? storage;
  final PanelSourceLocation? location;
}

// ---------------------------------------------------------------------------
// Internal dropdown
// ---------------------------------------------------------------------------

class _SourceDropdown extends StatefulWidget {
  final PanelSource? current;
  final String currentLabel;
  final bool currentIsLocal;
  final bool currentAvailable;
  final List<AvailableSource> available;
  final List<PanelSourceLocation> locations;
  final void Function(_SourceOption entry) onSelect;

  const _SourceDropdown({
    required this.current,
    required this.currentLabel,
    required this.currentIsLocal,
    required this.currentAvailable,
    required this.available,
    required this.locations,
    required this.onSelect,
  });

  @override
  State<_SourceDropdown> createState() => _SourceDropdownState();
}

class _SourceDropdownState extends State<_SourceDropdown> {
  List<_SourceOption>? _menuEntries;
  void Function(_SourceOption)? _menuSelect;

  @override
  Widget build(BuildContext context) {
    final current = widget.current;
    final currentLabel = widget.currentLabel;
    final currentIsLocal = widget.currentIsLocal;
    final currentAvailable = widget.currentAvailable;
    final available = widget.available;
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
          if (entry.source != null && _sameSource(entry.source!, current)) {
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
            : _iconFor(current),
        enabled: false,
        source: current,
      );
      entries.add(selected);
    }

    entries.addAll(
      widget.locations.map(
        (location) => _SourceOption(
          key: 'location:${location.key}',
          label: location.label,
          icon: location.icon,
          enabled: true,
          location: location,
        ),
      ),
    );
    final currentEntry = selected;
    Widget label(_SourceOption entry, {bool selected = false}) {
      final text = Text(
        selected && entry.label.characters.length > 15
            ? '${entry.label.characters.take(14)}…'
            : entry.label,
        maxLines: 1,
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final caption = currentEntry.label.characters.length > 15
            ? '${currentEntry.label.characters.take(14)}…'
            : currentEntry.label;
        final painter = TextPainter(
          text: TextSpan(
            text: caption,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final width = (painter.width + 42)
            .clamp(
              0.0,
              constraints.hasBoundedWidth ? constraints.maxWidth : 132.0,
            )
            .toDouble();
        painter.dispose();
        return Align(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: 1,
          heightFactor: 1,
          child: SizedBox(
            width: width,
            child: DropdownButton<String>(
              value: currentEntry.key,
              underline: const SizedBox.shrink(),
              icon: const Icon(Icons.arrow_drop_down, size: 18),
              style: theme.textTheme.bodySmall,
              isDense: true,
              isExpanded: true,
              menuWidth: MediaQuery.sizeOf(context).width
                  .clamp(0, 360)
                  .toDouble(),
              items: entries.map((entry) {
                return DropdownMenuItem<String>(
                  value: entry.key,
                  enabled: entry.enabled,
                  child: label(entry),
                );
              }).toList(),
              onTap: () {
                // DropdownButton returns only a key through its latest callback when
                // the route closes. Preserve the choices and owning callback that the
                // user actually opened, even if accounts or the panel rebuild meanwhile.
                _menuEntries = List<_SourceOption>.unmodifiable(entries);
                _menuSelect = widget.onSelect;
              },
              onChanged: (key) {
                final openedEntries = _menuEntries;
                final select = _menuSelect;
                _menuEntries = null;
                _menuSelect = null;
                if (key == null || openedEntries == null || select == null) {
                  return;
                }
                for (final entry in openedEntries) {
                  if (entry.key == key &&
                      entry.enabled &&
                      (entry.source != null || entry.location != null)) {
                    select(entry);
                    return;
                  }
                }
              },
              selectedItemBuilder: (context) => [
                for (var i = 0; i < entries.length; i++)
                  label(currentEntry, selected: true),
              ],
            ),
          ),
        );
      },
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
