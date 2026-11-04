// lib/widgets/permissions_dialog.dart
//
// File permissions editor for SFTP connections.
// Allows changing chmod (rwxrwxrwx) and chown (user:group).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/permissions_strings.dart';
import '../models/file_item.dart';
import '../providers/providers.dart';
import '../services/sftp_client_adapter.dart';
import '../services/log_service.dart';

void showPermissionsDialog(BuildContext context, WidgetRef ref, FileItem file) {
  showDialog(
    context: context,
    builder: (_) => _PermissionsDialog(file: file),
  );
}

class _PermissionsDialog extends ConsumerStatefulWidget {
  final FileItem file;
  const _PermissionsDialog({required this.file});

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
  Object? _errorDetail;

  @override
  void initState() {
    super.initState();
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    try {
      final auth = ref.read(authProvider);
      final client = auth.client;
      if (client is! SFTPClientAdapter) {
        setState(() {
          _error = 'Permissions are only available for SFTP connections';
          _loading = false;
        });
        return;
      }

      final path = widget.file.path ?? '/${widget.file.name}';
      final attrs = await client.getAttributes(path);

      // Parse permissions from SftpFileAttrs
      final mode = attrs.mode?.value ?? 0;
      _parseMode(mode);

      // Load ownership
      try {
        final ownership = await client.getOwnership(path);
        _ownerController.text = ownership['user'] ?? '';
        _groupController.text = ownership['group'] ?? '';
      } catch (_) {
        // stat command may not be available on all systems
      }

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      _log.error('Failed to load permissions', e);
      if (mounted) {
        setState(() {
          _error = 'Failed to load permissions: {error}';
          _errorDetail = e;
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
    final strings = PermissionsStrings(context);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.security, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(strings.format('Permissions — {name}', {'name': widget.file.name}), overflow: TextOverflow.ellipsis)),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(strings.format(_error!, {'error': _errorDetail}), style: TextStyle(color: theme.colorScheme.error)))
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
                            Text(_toOctal(), style: const TextStyle(fontSize: 24, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                            const SizedBox(width: 16),
                            Text(_toSymbolic(), style: const TextStyle(fontSize: 18, fontFamily: 'monospace')),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Permission grid
                      _buildPermissionRow(strings.text('Owner'), 0),
                      _buildPermissionRow(strings.text('Group'), 3),
                      _buildPermissionRow(strings.text('Other'), 6),
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
                              decoration: InputDecoration(
                                labelText: strings.text('Owner'),
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _groupController,
                              decoration: InputDecoration(
                                labelText: strings.text('Group'),
                                border: const OutlineInputBorder(),
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
          child: Text(strings.text('Cancel')),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(strings.text('Apply')),
        ),
      ],
    );
  }

  Widget _buildPermissionRow(String label, int startIndex) {
    final strings = PermissionsStrings(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 90, child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500))),
          _permCheckbox('R', strings.text('Read'), startIndex),
          _permCheckbox('W', strings.text('Write'), startIndex + 1),
          _permCheckbox('X', strings.text('Execute'), startIndex + 2),
        ],
      ),
    );
  }

  Widget _permCheckbox(String label, String description, int index) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: description,
          child: Checkbox(
            value: _perms[index],
            onChanged: (v) => setState(() => _perms[index] = v ?? false),
            visualDensity: VisualDensity.compact,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _presetChip(String octal, String symbolic) {
    return ActionChip(
      label: Text('$octal ($symbolic)', style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
      onPressed: () {
        final mode = int.parse(octal, radix: 8);
        setState(() => _parseMode(mode));
      },
      visualDensity: VisualDensity.compact,
    );
  }

  Future<void> _save() async {
    final strings = PermissionsStrings(context);
    setState(() => _saving = true);

    try {
      final auth = ref.read(authProvider);
      final client = auth.client as SFTPClientAdapter;
      final path = widget.file.path ?? '/${widget.file.name}';

      // Apply chmod
      await client.chmod(path, _toOctal());

      // Apply chown if changed
      final owner = _ownerController.text.trim();
      final group = _groupController.text.trim();
      if (owner.isNotEmpty) {
        final ownerStr = group.isNotEmpty ? '$owner:$group' : owner;
        await client.chown(path, ownerStr);
      }

      _log.info('Permissions updated for $path: ${_toOctal()} ${_toSymbolic()}');

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.format('Permissions set to {octal} ({symbolic}) for {name}', {'octal': _toOctal(), 'symbolic': _toSymbolic(), 'name': widget.file.name}))),
        );
      }
    } catch (e) {
      _log.error('Failed to set permissions', e);
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.format('Failed to set permissions: {error}', {'error': e}))),
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
