// lib/widgets/permissions_dialog.dart
//
// File permissions editor for SFTP connections.
// Allows changing chmod (rwxrwxrwx) and chown (user:group).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/file_item.dart';
import '../providers/providers.dart';
import 'file_origin_actions.dart';
import '../services/sftp_client_adapter.dart';
import '../services/log_service.dart';

void showPermissionsDialog(
  BuildContext context,
  WidgetRef ref,
  FileItem file, {
  PanelFileOrigin? sourceOrigin,
}) {
  try {
    final origin = captureFileActionOrigin(
      ref,
      file,
      sourceOrigin: sourceOrigin,
    );
    capturedRemoteClient(origin);
    showDialog(
      context: context,
      builder: (_) => _PermissionsDialog(file: file, origin: origin),
    );
  } catch (error) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$error')));
  }
}

class _PermissionsDialog extends ConsumerStatefulWidget {
  final FileItem file;
  final PanelFileOrigin origin;
  const _PermissionsDialog({required this.file, required this.origin});

  @override
  ConsumerState<_PermissionsDialog> createState() => _PermissionsDialogState();
}

class _PermissionsDialogState extends ConsumerState<_PermissionsDialog> {
  static const _log = Log('PermissionsDialog');

  // Permission bits: owner(rwx), group(rwx), other(rwx)
  final List<bool> _perms = List.filled(9, false);
  final _ownerController = TextEditingController();
  final _groupController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    try {
      final client = capturedRemoteClient(widget.origin);
      if (client is! SFTPClientAdapter) {
        setState(() {
          _error = 'Permissions are only available for SFTP connections';
          _loading = false;
        });
        return;
      }

      final path = requireFilePath(widget.file);
      final attrs = await client.getAttributes(path);
      if (!mounted) return;
      capturedRemoteClient(widget.origin);

      // Parse permissions from SftpFileAttrs
      final mode = attrs.mode?.value ?? 0;
      _parseMode(mode);

      // Load ownership
      try {
        final ownership = await client.getOwnership(path);
        if (!mounted) return;
        capturedRemoteClient(widget.origin);
        _ownerController.text = ownership['user'] ?? '';
        _groupController.text = ownership['group'] ?? '';
      } catch (_) {
        // stat command may not be available on all systems
      }

      if (!mounted) return;
      capturedRemoteClient(widget.origin);
      setState(() => _loading = false);
    } catch (e) {
      _log.error('Failed to load permissions', e);
      if (mounted) {
        setState(() {
          _error = 'Failed to load permissions: $e';
          _loading = false;
        });
      }
    }
  }

  void _parseMode(int mode) {
    // mode is the full POSIX mode including file type bits
    // We only care about the last 9 bits (rwxrwxrwx)
    for (int i = 0; i < 9; i++) {
      _perms[8 - i] = (mode >> i) & 1 == 1;
    }
  }

  int _toMode() {
    int mode = 0;
    for (int i = 0; i < 9; i++) {
      if (_perms[8 - i]) mode |= (1 << i);
    }
    return mode;
  }

  String _toOctal() {
    return _toMode().toRadixString(8).padLeft(3, '0');
  }

  String _toSymbolic() {
    const chars = 'rwxrwxrwx';
    final buf = StringBuffer();
    for (int i = 0; i < 9; i++) {
      buf.write(_perms[i] ? chars[i] : '-');
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.security, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Permissions — ${widget.file.name}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Octal + symbolic display
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _toOctal(),
                          style: const TextStyle(
                            fontSize: 24,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          _toSymbolic(),
                          style: const TextStyle(
                            fontSize: 18,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Permission grid
                  _buildPermissionRow('Owner', 0),
                  _buildPermissionRow('Group', 3),
                  _buildPermissionRow('Other', 6),
                  const SizedBox(height: 16),

                  // Quick presets
                  Wrap(
                    spacing: 8,
                    children: [
                      _presetChip('644', 'rw-r--r--'),
                      _presetChip('755', 'rwxr-xr-x'),
                      _presetChip('700', 'rwx------'),
                      _presetChip('600', 'rw-------'),
                      _presetChip('777', 'rwxrwxrwx'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),

                  // Ownership
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ownerController,
                          decoration: const InputDecoration(
                            labelText: 'Owner',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _groupController,
                          decoration: const InputDecoration(
                            labelText: 'Group',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving || _loading || _error != null ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Apply'),
        ),
      ],
    );
  }

  Widget _buildPermissionRow(String label, int startIndex) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          _permCheckbox('R', startIndex),
          _permCheckbox('W', startIndex + 1),
          _permCheckbox('X', startIndex + 2),
        ],
      ),
    );
  }

  Widget _permCheckbox(String label, int index) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(
          value: _perms[index],
          onChanged: (v) => setState(() => _perms[index] = v ?? false),
          visualDensity: VisualDensity.compact,
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _presetChip(String octal, String symbolic) {
    return ActionChip(
      label: Text(
        '$octal ($symbolic)',
        style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
      ),
      onPressed: () {
        final mode = int.parse(octal, radix: 8);
        setState(() => _parseMode(mode));
      },
      visualDensity: VisualDensity.compact,
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    try {
      final client = capturedRemoteClient(widget.origin) as SFTPClientAdapter;
      final path = requireFilePath(widget.file);

      // Apply chmod
      await client.chmod(path, _toOctal());
      if (!mounted) return;
      capturedRemoteClient(widget.origin);

      // Apply chown if changed
      final owner = _ownerController.text.trim();
      final group = _groupController.text.trim();
      if (owner.isNotEmpty) {
        final ownerStr = group.isNotEmpty ? '$owner:$group' : owner;
        await client.chown(path, ownerStr);
      }

      capturedRemoteClient(widget.origin);
      _log.info(
        'Permissions updated for $path: ${_toOctal()} ${_toSymbolic()}',
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Permissions set to ${_toOctal()} (${_toSymbolic()}) for ${widget.file.name}',
            ),
          ),
        );
      }
    } catch (e) {
      _log.error('Failed to set permissions', e);
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to set permissions: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _ownerController.dispose();
    _groupController.dispose();
    super.dispose();
  }
}
