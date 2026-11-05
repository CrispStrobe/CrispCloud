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

import '../l10n/access_and_fkey_strings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/mount_provider.dart';
import '../services/fuse_mount_service.dart';
import '../l10n/app_localizations.dart';
import '../l10n/mount_dialog_strings.dart';
import '../l10n/mount_backend_strings.dart';
import '../l10n/mount_error_presentation.dart';
import '../l10n/terminal_mount_error_strings.dart';

void showMountDialog(BuildContext context) {
  showDialog(context: context, builder: (_) => const _MountManagerDialog());
}

Future<bool> _confirmFuseT(BuildContext context) async {
  final strings = MountBackendStrings(context);
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(strings.fuseTTitle),
          content: SelectableText(strings.fuseTMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(AppLocalizations.of(dialogContext)!.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(strings.fuseTAccept),
            ),
          ],
        ),
      ) ??
      false;
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
          Text(MountDialogStrings(context).text('mountDrive')),
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
              message: localizedMountError(context, mount.availabilityError!),
              child: const Icon(
                Icons.warning_amber,
                color: Colors.orange,
                size: 20,
              ),
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
            else if (mount.availabilityError != null &&
                mount.availabilityError!.isNotEmpty)
              _FuseUnavailableBanner(
                message: localizedMountError(context, mount.availabilityError!),
              ),

            const SizedBox(height: 8),

            // Active / configured mounts
            if (mount.mounts.isEmpty)
              _EmptyMountList(
                showExperimental:
                    !kIsWeb &&
                    defaultTargetPlatform == TargetPlatform.macOS &&
                    !mount.isCheckingAvailability &&
                    mount.availabilityError != FuseMountService.bridgeMissing,
              )
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
            label: Text(MountDialogStrings(context).text('newMount')),
            onPressed:
                mount.availabilityError != null &&
                    mount.availabilityError!.isNotEmpty
                ? null
                : () => _showAddMountDialog(context, ref),
          ),
      ],
    );
  }

  void _showAddMountDialog(BuildContext context, WidgetRef ref) {
    showDialog(context: context, builder: (_) => const _AddMountDialog());
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
  MacFuseBackend _backend = MacFuseBackend.automatic;

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
      title: Text(MountDialogStrings(context).text('newMount')),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) ...[
                if (_backend != MacFuseBackend.rcloneNfs) Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        MountDialogStrings(context).text('readOnlyWarning'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<MacFuseBackend>(
                  initialValue: _backend,
                  decoration: InputDecoration(
                    labelText: MountBackendStrings(context).title,
                    border: const OutlineInputBorder(),
                  ),
                  items: MacFuseBackend.values.map((backend) => DropdownMenuItem(
                    value: backend,
                    child: Text(MountBackendStrings(context).label(backend)),
                  )).toList(),
                  onChanged: _mounting ? null : (value) {
                    if (value != null) setState(() => _backend = value);
                  },
                ),
                if (_backend == MacFuseBackend.macFuseKernel) ...[
                  const SizedBox(height: 8),
                  Text(MountBackendStrings(context).kernelWarning),
                ],
                if (_backend == MacFuseBackend.rcloneNfs) ...[
                  const SizedBox(height: 8),
                  Text(MountBackendStrings(context).rcloneHint),
                ],
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _labelController,
                decoration: InputDecoration(
                  labelText: MountDialogStrings(context).text('displayName'),
                  hintText: MountDialogStrings(context).text('nameHint'),
                  border: const OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _remoteController,
                decoration: InputDecoration(
                  labelText: MountDialogStrings(context).text('remotePath'),
                  hintText: AccessAndFKeyStrings(Localizations.localeOf(context)).remotePathHint,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.cloud),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _mountPointController,
                      decoration: InputDecoration(
                        labelText: MountDialogStrings(context)
                            .text('mountPoint'),
                        hintText: '/mnt/mycloud',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.folder_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _BrowseButton(
                    onSelected: (path) {
                      setState(() => _mountPointController.text = path);
                    },
                  ),
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
                      const Icon(
                        Icons.error_outline,
                        color: Colors.red,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.red,
                          ),
                        ),
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
              : Text(MountDialogStrings(context).text('mount')),
        ),
      ],
    );
  }

  Future<void> _doMount(BuildContext context) async {
    final remote = _remoteController.text.trim();
    final mp = _mountPointController.text.trim();

    if (mp.isEmpty) {
      setState(() => _error = MountDialogStrings(context).text('required'));
      return;
    }
    if (_backend == MacFuseBackend.rcloneNfs &&
        !FuseMountService.isValidRcloneRemote(remote)) {
      setState(() => _error = MountBackendStrings(context).rcloneHint);
      return;
    }

    if (_backend == MacFuseBackend.fuseT && !await _confirmFuseT(context)) return;
    if (!context.mounted) return;
    setState(() {
      _mounting = true;
      _error = null;
    });

    final label = _labelController.text.trim().isEmpty
        ? null
        : _labelController.text.trim();

    try {
      final entry = await ref
          .read(mountProvider)
          .mount(
            remotePath: remote.isEmpty ? '/' : remote,
            mountPoint: mp,
            label: label,
            macBackend: _backend,
            fuseTNonCommercialAcknowledged: _backend == MacFuseBackend.fuseT,
          );
      if (!context.mounted) return;
      if (entry == null || entry.status == MountStatus.error) {
        final failure = ref.read(mountProvider).lastMountFailure;
        setState(
          () => _error = entry?.errorMessage == null
              ? (failure == null
                    ? MountDialogStrings(context).text('failed')
                    : localizedTerminalMountError(context, failure))
              : localizedMountEntryError(context, entry!),
        );
      } else {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = localizedTerminalMountError(context, e));
      }
    } finally {
      if (mounted) {
        setState(() => _mounting = false);
      }
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
    final isBusy =
        entry.status == MountStatus.mounting ||
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
              message: entry.errorMessage == null
                  ? MountDialogStrings(context).text('unknown')
                  : localizedMountEntryError(context, entry),
              child: const Icon(
                Icons.info_outline,
                size: 16,
                color: Colors.red,
              ),
            ),
          if (isBusy)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (entry.status == MountStatus.mounted ||
              (entry.status == MountStatus.error && entry.helperPid != null))
            IconButton(
              icon: const Icon(Icons.eject, size: 20),
              tooltip: MountDialogStrings(context).text('unmount'),
              onPressed: () =>
                  ref.read(mountProvider).unmount(entry.mountPoint),
            )
          else
            IconButton(
              icon: const Icon(Icons.play_arrow, size: 20),
              tooltip: MountDialogStrings(context).text('mount'),
              onPressed: () => _remount(context, ref, entry),
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            tooltip: MountDialogStrings(context).text('remove'),
            onPressed: isBusy
                ? null
                : () => ref.read(mountProvider).removeMount(entry.mountPoint),
          ),
        ],
      ),
    );
  }

  Future<void> _remount(
    BuildContext context,
    WidgetRef ref,
    MountEntry entry,
  ) async {
    if (entry.macBackend == MacFuseBackend.fuseT && !await _confirmFuseT(context)) return;
    if (!context.mounted) return;
    await ref
        .read(mountProvider)
        .mount(
          remotePath: entry.remotePath,
          mountPoint: entry.mountPoint,
          label: entry.label,
          macBackend: entry.macBackend,
          fuseTNonCommercialAcknowledged: entry.macBackend == MacFuseBackend.fuseT,
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
      label: Text(MountDialogStrings(context).text('browse')),
      onPressed: () async {
        try {
          final path = await getDirectoryPath(
            confirmButtonText: MountDialogStrings(context).text('selectPoint'),
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
      message: MountDialogStrings(context).text('unsupported'),
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
  const _EmptyMountList({required this.showExperimental});

  final bool showExperimental;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          const Icon(Icons.storage_outlined, size: 48, color: Colors.grey),
          const SizedBox(height: 8),
          Text(MountDialogStrings(context).text('empty')),
          const SizedBox(height: 4),
          Text(
            MountDialogStrings(context)
                .text(showExperimental ? 'readOnlyWarning' : 'bridgeMissing'),
            style: const TextStyle(fontSize: 12, color: Colors.grey),
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
          Expanded(child: Text(message, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}
