// lib/widgets/version_history_dialog.dart
//
// Shows file version history and allows restoring previous versions.
// Works with providers that support versioning (GDrive, Dropbox, OneDrive).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/gdrive_client_adapter.dart';
import '../services/dropbox_client_adapter.dart';
import '../services/onedrive_client_adapter.dart';
import '../services/log_service.dart';
import '../utils/formatters.dart';
import 'diff_viewer_dialog.dart';

void showVersionHistoryDialog(BuildContext context, WidgetRef ref, FileItem file) {
  showDialog(
    context: context,
    builder: (_) => _VersionHistoryDialog(file: file),
  );
}

class _VersionHistoryDialog extends ConsumerStatefulWidget {
  final FileItem file;
  const _VersionHistoryDialog({required this.file});

  @override
  ConsumerState<_VersionHistoryDialog> createState() => _VersionHistoryDialogState();
}

class _VersionHistoryDialogState extends ConsumerState<_VersionHistoryDialog> {
  static const _log = Log('VersionHistory');

  List<Map<String, dynamic>> _versions = [];
  bool _loading = true;
  bool _restoring = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadVersions();
  }

  Future<void> _loadVersions() async {
    try {
      final auth = ref.read(authProvider);
      final client = auth.client;
      final fileId = widget.file.uuid ?? widget.file.name;

      List<Map<String, dynamic>> versions = [];

      if (client is GDriveClientAdapter) {
        versions = await _loadGDriveVersions(client, fileId);
      } else if (client is DropboxClientAdapter) {
        versions = await _loadDropboxVersions(client, widget.file);
      } else if (client is OneDriveClientAdapter) {
        versions = await _loadOneDriveVersions(client, widget.file);
      } else {
        throw UnsupportedError('${client.providerName} does not support version history');
      }

      if (mounted) {
        setState(() {
          _versions = versions;
          _loading = false;
        });
      }
    } catch (e) {
      _log.error('Failed to load versions', e);
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<List<Map<String, dynamic>>> _loadGDriveVersions(GDriveClientAdapter client, String fileId) async {
    final token = client.accessToken;
    if (token == null) throw Exception('Not authenticated');
    final resp = await http.get(
      Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId/revisions?fields=revisions(id,modifiedTime,size,lastModifyingUser/displayName)'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (resp.statusCode != 200) return [];
    final data = json.decode(resp.body);
    return ((data['revisions'] as List?) ?? []).map((r) => <String, dynamic>{
      'id': r['id'],
      'modified': r['modifiedTime'],
      'size': int.tryParse(r['size']?.toString() ?? '0') ?? 0,
      'author': r['lastModifyingUser']?['displayName'] ?? 'Unknown',
      'provider': 'gdrive',
      'fileId': fileId,
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _loadDropboxVersions(DropboxClientAdapter client, FileItem file) async {
    final token = client.accessToken;
    if (token == null) throw Exception('Not authenticated');
    final path = file.path ?? '/${file.name}';
    final resp = await http.post(
      Uri.parse('https://api.dropboxapi.com/2/files/list_revisions'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode({'path': path, 'limit': 50}),
    );
    if (resp.statusCode != 200) return [];
    final data = json.decode(resp.body);
    return ((data['entries'] as List?) ?? []).map((r) => <String, dynamic>{
      'id': r['rev'],
      'modified': r['server_modified'],
      'size': r['size'] ?? 0,
      'author': '',
      'provider': 'dropbox',
      'path': path,
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _loadOneDriveVersions(OneDriveClientAdapter client, FileItem file) async {
    final token = client.accessToken;
    if (token == null) throw Exception('Not authenticated');
    final fileId = file.uuid ?? file.name;
    final resp = await http.get(
      Uri.parse('https://graph.microsoft.com/v1.0/me/drive/items/$fileId/versions'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (resp.statusCode != 200) return [];
    final data = json.decode(resp.body);
    return ((data['value'] as List?) ?? []).map((r) => <String, dynamic>{
      'id': r['id'],
      'modified': r['lastModifiedDateTime'],
      'size': r['size'] ?? 0,
      'author': r['lastModifiedBy']?['user']?['displayName'] ?? '',
      'provider': 'onedrive',
      'fileId': fileId,
    }).toList();
  }

  // --- Restore Methods ---

  Future<void> _restoreVersion(Map<String, dynamic> version) async {
    final provider = version['provider'] as String;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore Version?'),
        content: Text(
          'This will replace the current file with the version from '
          '${version['modified'] ?? 'unknown date'}. '
          'The current version will be preserved in the version history.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restore')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _restoring = true);

    try {
      final auth = ref.read(authProvider);
      final client = auth.client;

      switch (provider) {
        case 'gdrive':
          await _restoreGDriveVersion(client as GDriveClientAdapter, version);
          break;
        case 'dropbox':
          await _restoreDropboxVersion(client as DropboxClientAdapter, version);
          break;
        case 'onedrive':
          await _restoreOneDriveVersion(client as OneDriveClientAdapter, version);
          break;
      }

      _log.info('Restored version ${version['id']} for ${widget.file.name}');

      // Refresh the panel to show updated file
      await ref.read(panelProvider(PanelSide.remote)).refresh();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restored ${widget.file.name} to version from ${version['modified']}')),
        );
        // Reload versions to reflect the change
        setState(() {
          _loading = true;
          _restoring = false;
        });
        _loadVersions();
      }
    } catch (e) {
      _log.error('Failed to restore version', e);
      if (mounted) {
        setState(() => _restoring = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restore failed: $e')),
        );
      }
    }
  }

  /// GDrive: Copy the revision content back to the file.
  /// Uses the revisions.get endpoint with alt=media to download the revision,
  /// then re-uploads it to the same file via PATCH.
  Future<void> _restoreGDriveVersion(GDriveClientAdapter client, Map<String, dynamic> version) async {
    final token = client.accessToken!;
    final fileId = version['fileId'] as String;
    final revisionId = version['id'] as String;

    // Download the revision content
    final downloadResp = await http.get(
      Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId/revisions/$revisionId?alt=media'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (downloadResp.statusCode != 200) {
      throw Exception('Failed to download revision: ${downloadResp.statusCode}');
    }

    // Re-upload the content to the same file (creates a new revision)
    final uploadResp = await http.patch(
      Uri.parse('https://www.googleapis.com/upload/drive/v3/files/$fileId?uploadType=media'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/octet-stream',
      },
      body: downloadResp.bodyBytes,
    );
    if (uploadResp.statusCode != 200) {
      throw Exception('Failed to upload restored content: ${uploadResp.statusCode}');
    }
  }

  /// Dropbox: Use restore endpoint to promote a revision.
  Future<void> _restoreDropboxVersion(DropboxClientAdapter client, Map<String, dynamic> version) async {
    final token = client.accessToken!;
    final path = version['path'] as String;
    final rev = version['id'] as String;

    final resp = await http.post(
      Uri.parse('https://api.dropboxapi.com/2/files/restore'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode({'path': path, 'rev': rev}),
    );
    if (resp.statusCode != 200) {
      throw Exception('Dropbox restore failed: ${resp.statusCode} ${resp.body}');
    }
  }

  /// OneDrive: Restore a version using the restoreVersion action.
  Future<void> _restoreOneDriveVersion(OneDriveClientAdapter client, Map<String, dynamic> version) async {
    final token = client.accessToken!;
    final fileId = version['fileId'] as String;
    final versionId = version['id'] as String;

    final resp = await http.post(
      Uri.parse('https://graph.microsoft.com/v1.0/me/drive/items/$fileId/versions/$versionId/restoreVersion'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    // 204 = success, 200 = success with body
    if (resp.statusCode != 204 && resp.statusCode != 200) {
      throw Exception('OneDrive restore failed: ${resp.statusCode} ${resp.body}');
    }
  }

  /// Download version content for diff comparison.
  Future<String?> _downloadVersionContent(Map<String, dynamic> version) async {
    try {
      final auth = ref.read(authProvider);
      final client = auth.client;
      final provider = version['provider'] as String;

      if (provider == 'gdrive') {
        final token = (client as GDriveClientAdapter).accessToken!;
        final fileId = version['fileId'] as String;
        final revisionId = version['id'] as String;
        final resp = await http.get(
          Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId/revisions/$revisionId?alt=media'),
          headers: {'Authorization': 'Bearer $token'},
        );
        if (resp.statusCode == 200) return utf8.decode(resp.bodyBytes, allowMalformed: true);
      } else if (provider == 'dropbox') {
        final token = (client as DropboxClientAdapter).accessToken!;
        final rev = version['id'] as String;
        final arg = json.encode({'path': 'rev:$rev'});
        final resp = await http.post(
          Uri.parse('https://content.dropboxapi.com/2/files/download'),
          headers: {'Authorization': 'Bearer $token', 'Dropbox-API-Arg': arg},
        );
        if (resp.statusCode == 200) return utf8.decode(resp.bodyBytes, allowMalformed: true);
      } else if (provider == 'onedrive') {
        final token = (client as OneDriveClientAdapter).accessToken!;
        final fileId = version['fileId'] as String;
        final versionId = version['id'] as String;
        final resp = await http.get(
          Uri.parse('https://graph.microsoft.com/v1.0/me/drive/items/$fileId/versions/$versionId/content'),
          headers: {'Authorization': 'Bearer $token'},
        );
        if (resp.statusCode == 200) return utf8.decode(resp.bodyBytes, allowMalformed: true);
      }
    } catch (e) {
      _log.error('Failed to download version content', e);
    }
    return null;
  }

  /// Compare a version with the current version using the diff viewer.
  Future<void> _compareVersion(Map<String, dynamic> version) async {
    setState(() => _restoring = true); // reuse loading overlay

    try {
      // Download the old version
      final oldContent = await _downloadVersionContent(version);
      if (oldContent == null) throw Exception('Failed to download version');

      // Download the current version
      final auth = ref.read(authProvider);
      final remotePath = widget.file.path ?? '/${widget.file.name}';
      final currentBytes = await auth.client.downloadFileBytes(remotePath);
      final currentContent = utf8.decode(currentBytes, allowMalformed: true);

      if (!mounted) return;
      setState(() => _restoring = false);

      final modified = DateTime.tryParse(version['modified'] ?? '');
      final versionLabel = modified != null ? formatDateFull(modified) : 'Version ${version['id']}';

      showDiffViewerFromContent(
        context,
        leftContent: oldContent,
        rightContent: currentContent,
        leftLabel: 'Version: $versionLabel',
        rightLabel: 'Current',
      );
    } catch (e) {
      _log.error('Version diff failed', e);
      if (mounted) {
        setState(() => _restoring = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Diff failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.history, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('Version History — ${widget.file.name}', overflow: TextOverflow.ellipsis)),
        ],
      ),
      content: SizedBox(
        width: 500,
        height: 400,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)))
                : _versions.isEmpty
                    ? const Center(child: Text('No version history available'))
                    : Stack(
                        children: [
                          ListView.builder(
                            itemCount: _versions.length,
                            itemBuilder: (context, index) {
                              final v = _versions[index];
                              final modified = DateTime.tryParse(v['modified'] ?? '');
                              return ListTile(
                                leading: CircleAvatar(
                                  radius: 16,
                                  backgroundColor: index == 0 ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
                                  child: Text('${index + 1}', style: TextStyle(
                                    fontSize: 12,
                                    color: index == 0 ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
                                  )),
                                ),
                                title: Text(
                                  modified != null ? formatDateFull(modified) : 'Version ${v['id']}',
                                  style: const TextStyle(fontSize: 13),
                                ),
                                subtitle: Text(
                                  '${formatBytes(v['size'] as int)}${v['author']?.isNotEmpty == true ? ' • ${v['author']}' : ''}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                trailing: index == 0
                                    ? const Chip(label: Text('Current', style: TextStyle(fontSize: 10)), visualDensity: VisualDensity.compact)
                                    : Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          TextButton(
                                            onPressed: _restoring ? null : () => _compareVersion(v),
                                            child: const Text('Diff', style: TextStyle(fontSize: 12)),
                                          ),
                                          TextButton(
                                            onPressed: _restoring ? null : () => _restoreVersion(v),
                                            child: const Text('Restore', style: TextStyle(fontSize: 12)),
                                          ),
                                        ],
                                      ),
                              );
                            },
                          ),
                          if (_restoring)
                            Container(
                              color: Colors.black26,
                              child: const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(),
                                    SizedBox(height: 12),
                                    Text('Restoring...', style: TextStyle(color: Colors.white)),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }
}
