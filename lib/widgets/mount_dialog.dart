// lib/widgets/mount_dialog.dart
//
// Dialog for configuring and managing FUSE-mounted drives.
//
// Features:
//   • Mount a cloud provider path at a local directory.
//   • List active and configured mounts with status indicators.
//   • Unmount button per active mount.
//   • "Browse" button to pick a local mount point directory (desktop).
//   • Shows a warning if the platform FUSE library is not installed.

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/mount_provider.dart';
import '../services/fuse_mount_service.dart';
import '../l10n/app_localizations.dart';
import '../services/log_service.dart';

void showMountDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (_) => const _MountManagerDialog(),
  );
}

// ---------------------------------------------------------------------------
// Main dialog
// ---------------------------------------------------------------------------

class _MountManagerDialog extends ConsumerWidget {
  const _MountManagerDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mount = ref.watch(mountProvider);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.storage_rounded),
          const SizedBox(width: 8),
          const Text('Mount as Drive'),
          const Spacer(),
          if (mount.isCheckingAvailability)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          if (!mount.isCheckingAvailability &&
              mount.availabilityError != null &&
              mount.availabilityError!.isNotEmpty)
            Tooltip(
              message: mount.availabilityError!,
              child: const Icon(Icons.warning_amber, color: Colors.orange, size: 20),
            ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Platform warning banner
            if (!mount.isSupported)
              _PlatformUnsupportedBanner()
            else if (mount.availabilityError != null && mount.availabilityError!.isNotEmpty)
              _FuseUnavailableBanner(message: mount.availabilityError!),

            const SizedBox(height: 8),

            // Active / configured mounts
            if (mount.mounts.isEmpty)
              const _EmptyMountList()
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: mount.mounts.length,
                  itemBuilder: (context, i) =>
                      _MountTile(entry: mount.mounts[i]),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context)!.close),
        ),
        if (mount.isSupported)
          ElevatedButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New Mount'),
            onPressed: mount.availabilityError != null && mount.availabilityError!.isNotEmpty
                ? null
                : () => _showAddMountDialog(context, ref),
          ),
      ],
    );
  }

  void _showAddMountDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => const _AddMountDialog(),
    );
  }
}

// ---------------------------------------------------------------------------
// Add-mount dialog
// ---------------------------------------------------------------------------

class _AddMountDialog extends ConsumerStatefulWidget {
  const _AddMountDialog();

  @override
  ConsumerState<_AddMountDialog> createState() => _AddMountDialogState();
}

class _AddMountDialogState extends ConsumerState<_AddMountDialog> {
  final _remoteController = TextEditingController(text: '/');
  final _mountPointController = TextEditingController();
  final _labelController = TextEditingController();
  bool _mounting = false;
  String? _error;

  @override
  void dispose() {
    _remoteController.dispose();
    _mountPointController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Mount'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _labelController,
                decoration: const InputDecoration(
                  labelText: 'Display Name (optional)',
                  hintText: 'e.g., My Dropbox Drive',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _remoteController,
                decoration: const InputDecoration(
                  labelText: 'Remote Path',
                  hintText: '/ or /Documents',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.cloud),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _mountPointController,
                      decoration: const InputDecoration(
                        labelText: 'Local Mount Point',
                        hintText: '/mnt/mycloud',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.folder_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _BrowseButton(onSelected: (path) {
                    setState(() => _mountPointController.text = path);
                  }),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(_error!,
                            style: const TextStyle(fontSize: 12, color: Colors.red)),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _mounting ? null : () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context)!.cancel),
        ),
        ElevatedButton(
          onPressed: _mounting ? null : () => _doMount(context),
          child: _mounting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Mount'),
        ),
      ],
    );
  }

  Future<void> _doMount(BuildContext context) async {
    final remote = _remoteController.text.trim();
    final mp = _mountPointController.text.trim();

    if (mp.isEmpty) {
      setState(() => _error = 'Please specify a local mount point directory.');
      return;
    }

    setState(() {
      _mounting = true;
      _error = null;
    });

    final label = _labelController.text.trim().isEmpty
        ? null
        : _labelController.text.trim();

    try {
      final entry = await ref.read(mountProvider).mount(
            remotePath: remote.isEmpty ? '/' : remote,
            mountPoint: mp,
            label: label,
          );
      if (!context.mounted) return;
      if (entry == null || entry.status == MountStatus.error) {
        setState(() => _error = entry?.errorMessage ?? 'Mount failed');
      } else {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _mounting = false);
    }
  }
}

// ---------------------------------------------------------------------------
// Mount tile
// ---------------------------------------------------------------------------

class _MountTile extends ConsumerWidget {
  final MountEntry entry;
  const _MountTile({required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isBusy = entry.status == MountStatus.mounting ||
        entry.status == MountStatus.unmounting;

    return ListTile(
      leading: _StatusIcon(status: entry.status),
      title: Text(entry.label, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${entry.provider} · ${entry.remotePath}\n→ ${entry.mountPoint}',
        style: const TextStyle(fontSize: 11),
        overflow: TextOverflow.ellipsis,
        maxLines: 2,
      ),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (entry.status == MountStatus.error)
            Tooltip(
              message: entry.errorMessage ?? 'Unknown error',
              child: const Icon(Icons.info_outline, size: 16, color: Colors.red),
            ),
          if (isBusy)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (entry.status == MountStatus.mounted)
            IconButton(
              icon: const Icon(Icons.eject, size: 20),
              tooltip: 'Unmount',
              onPressed: () => ref.read(mountProvider).unmount(entry.mountPoint),
            )
          else
            IconButton(
              icon: const Icon(Icons.play_arrow, size: 20),
              tooltip: 'Mount',
              onPressed: () => _remount(context, ref, entry),
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            tooltip: 'Remove',
            onPressed: isBusy
                ? null
                : () => ref.read(mountProvider).removeMount(entry.mountPoint),
          ),
        ],
      ),
    );
  }

  Future<void> _remount(
      BuildContext context, WidgetRef ref, MountEntry entry) async {
    await ref.read(mountProvider).mount(
          remotePath: entry.remotePath,
          mountPoint: entry.mountPoint,
          label: entry.label,
        );
  }
}

// ---------------------------------------------------------------------------
// Status icon
// ---------------------------------------------------------------------------

class _StatusIcon extends StatelessWidget {
  final MountStatus status;
  const _StatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case MountStatus.mounted:
        return const Icon(Icons.check_circle, color: Colors.green);
      case MountStatus.mounting:
      case MountStatus.unmounting:
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case MountStatus.error:
        return const Icon(Icons.error, color: Colors.red);
      case MountStatus.unmounted:
        return const Icon(Icons.circle_outlined, color: Colors.grey);
    }
  }
}

// ---------------------------------------------------------------------------
// Browse button (local directory picker)
// ---------------------------------------------------------------------------

class _BrowseButton extends StatelessWidget {
  final void Function(String path) onSelected;
  const _BrowseButton({required this.onSelected});

  @override
  Widget build(BuildContext context) {
    // File picker is only meaningful on desktop.
    if (kIsWeb) return const SizedBox.shrink();

    return OutlinedButton.icon(
      icon: const Icon(Icons.folder_open, size: 16),
      label: const Text('Browse'),
      onPressed: () async {
        try {
          final path = await getDirectoryPath(
            confirmButtonText: 'Select Mount Point',
          );
          if (path != null) onSelected(path);
        } catch (_) {
          // file_selector not available (e.g. on Linux without GTK portal)
          // fall through; user can type the path manually.
        }
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Banner widgets
// ---------------------------------------------------------------------------

class _PlatformUnsupportedBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _Banner(
      color: Colors.orange.shade50,
      borderColor: Colors.orange.shade300,
      icon: Icons.warning_amber,
      iconColor: Colors.orange,
      message: 'FUSE mounts are only available on macOS, Linux, and Windows desktop.',
    );
  }
}

class _FuseUnavailableBanner extends StatelessWidget {
  final String message;
  const _FuseUnavailableBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return _Banner(
      color: Colors.amber.shade50,
      borderColor: Colors.amber.shade300,
      icon: Icons.build_circle_outlined,
      iconColor: Colors.amber.shade800,
      message: message,
    );
  }
}

class _EmptyMountList extends StatelessWidget {
  const _EmptyMountList();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(Icons.storage_outlined, size: 48, color: Colors.grey),
          SizedBox(height: 8),
          Text('No mounts configured'),
          SizedBox(height: 4),
          Text(
            'Add a mount to expose your cloud storage as a local drive.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final Color color;
  final Color borderColor;
  final IconData icon;
  final Color iconColor;
  final String message;

  const _Banner({
    required this.color,
    required this.borderColor,
    required this.icon,
    required this.iconColor,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
