// lib/widgets/drive_bar.dart
//
// DC-style drive/volume bar — compact row of buttons above the file list.
// On macOS: enumerates /Volumes; Linux: /proc/mounts; Windows: drive letters.
// On remote panels: shows bookmarks.

import 'dart:io' show Directory, File, Platform, Process;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/panel_side.dart';
import '../providers/providers.dart';

/// A volume/drive entry shown in the drive bar.
class _DriveEntry {
  final String path;
  final String label;
  final IconData icon;

  const _DriveEntry({required this.path, required this.label, required this.icon});
}

/// Provider that caches the list of local drives/volumes.
final _drivesProvider = FutureProvider<List<_DriveEntry>>((ref) async {
  if (kIsWeb) return [];
  if (Platform.isMacOS) return _macVolumes();
  if (Platform.isLinux) return _linuxMounts();
  if (Platform.isWindows) return _windowsDrives();
  return [];
});

Future<List<_DriveEntry>> _macVolumes() async {
  try {
    final entries = <_DriveEntry>[];
    // Always include home
    final home = Platform.environment['HOME'] ?? '/Users';
    entries.add(_DriveEntry(path: home, label: 'Home', icon: Icons.home));

    final volumesDir = Directory('/Volumes');
    if (await volumesDir.exists()) {
      final dirs = await volumesDir.list().toList();
      for (final d in dirs) {
        if (d is Directory) {
          final name = d.path.split('/').last;
          if (name.startsWith('.')) continue;
          entries.add(_DriveEntry(path: d.path, label: name, icon: Icons.storage));
        }
      }
    }
    return entries;
  } catch (e) {
    // TODO: add logging
    return [];
  }
}

Future<List<_DriveEntry>> _linuxMounts() async {
  try {
    final entries = <_DriveEntry>[];
    final home = Platform.environment['HOME'] ?? '/home';
    entries.add(_DriveEntry(path: home, label: 'Home', icon: Icons.home));
    entries.add(const _DriveEntry(path: '/', label: '/', icon: Icons.computer));

    final mountsFile = File('/proc/mounts');
    if (await mountsFile.exists()) {
      final lines = await mountsFile.readAsLines();
      for (final line in lines) {
        final parts = line.split(' ');
        if (parts.length < 2) continue;
        final mountPoint = parts[1].replaceAll(r'\040', ' ');
        final fsType = parts.length > 2 ? parts[2] : '';
        // Skip system pseudo-filesystems
        if (const {'proc', 'sysfs', 'devtmpfs', 'devpts', 'tmpfs', 'cgroup', 'bpf',
                    'pstore', 'autofs', 'mqueue', 'hugetlbfs', 'debugfs', 'tracefs',
                    'securityfs', 'configfs', 'fusectl', 'none'}.contains(fsType)) {
          continue;
        }
        if (mountPoint == '/' || mountPoint == home) continue;
        if (mountPoint.startsWith('/dev') || mountPoint.startsWith('/proc') ||
            mountPoint.startsWith('/sys') || mountPoint.startsWith('/run')) {
          continue;
        }
        final label = mountPoint.split('/').last;
        entries.add(_DriveEntry(path: mountPoint, label: label.isEmpty ? mountPoint : label, icon: Icons.usb));
      }
    }
    return entries;
  } catch (e) {
    // TODO: add logging
    return [];
  }
}

Future<List<_DriveEntry>> _windowsDrives() async {
  try {
    final result = await Process.run(
      'wmic', ['logicaldisk', 'get', 'DeviceID,Description'],
    );
    final entries = <_DriveEntry>[];
    final lines = result.stdout.toString().trim().split('\n');
    for (final line in lines.skip(1)) {
      final parts = line.trim().split(RegExp(r'\s{2,}'));
      if (parts.isEmpty || parts.first.isEmpty) continue;
      final desc = parts.first.trim();
      final letter = parts.length > 1 ? parts.last.trim() : desc;
      if (letter.length >= 2 && letter[1] == ':') {
        final icon = desc.toLowerCase().contains('cd') ? Icons.album
            : desc.toLowerCase().contains('removable') ? Icons.usb
            : Icons.storage;
        entries.add(_DriveEntry(path: '$letter\\', label: letter, icon: icon));
      }
    }
    return entries;
  } catch (e) {
    // TODO: add logging
    return [];
  }
}

class DriveBar extends ConsumerWidget {
  final PanelSide side;

  const DriveBar({super.key, required this.side});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kIsWeb) return const SizedBox.shrink();

    final panel = ref.watch(panelProvider(side));
    final currentPath = panel.currentPath;
    final theme = Theme.of(context);

    // Remote panel: show bookmarks
    if (side == PanelSide.remote) {
      final bookmarksNotifier = ref.watch(bookmarksProvider);
      final bookmarks = bookmarksNotifier.bookmarks;
      if (bookmarks.isEmpty) return const SizedBox.shrink();
      return _DriveBarRow(
        entries: bookmarks
            .map((b) => _DriveEntry(path: b.path, label: b.name, icon: Icons.bookmark))
            .toList(),
        currentPath: currentPath,
        onTap: (entry) => panel.navigateToPath(entry.path),
        theme: theme,
      );
    }

    // Local panel: show drives/volumes
    final drives = ref.watch(_drivesProvider);
    return drives.when(
      loading: () => const SizedBox(height: 22),
      error: (_, __) => const SizedBox.shrink(),
      data: (entries) => _DriveBarRow(
        entries: entries,
        currentPath: currentPath,
        onTap: (entry) => panel.navigateToPath(entry.path),
        theme: theme,
      ),
    );
  }
}

class _DriveBarRow extends StatelessWidget {
  final List<_DriveEntry> entries;
  final String currentPath;
  final void Function(_DriveEntry) onTap;
  final ThemeData theme;

  const _DriveBarRow({
    required this.entries,
    required this.currentPath,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 22,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(width: 2),
        itemBuilder: (_, i) {
          final entry = entries[i];
          final isActive = currentPath.startsWith(entry.path);
          return Tooltip(
            message: entry.path,
            child: GestureDetector(
              onTap: () => onTap(entry),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isActive ? theme.colorScheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(entry.icon, size: 12,
                        color: isActive
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      entry.label,
                      style: TextStyle(
                        fontSize: 11,
                        color: isActive
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
