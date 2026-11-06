// lib/widgets/version_history_dialog.dart
//
// Shows file version history and allows restoring previous versions.
// Works with providers that support versioning (GDrive, Dropbox, OneDrive).

import '../l10n/commander_strings.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import 'file_origin_actions.dart';
import '../services/gdrive_client_adapter.dart';
import '../services/file_action_requests.dart';
import '../services/file_operation_backend.dart';
import '../services/file_bytes_loader.dart';
import '../services/file_comparison_service.dart';
import '../services/dropbox_client_adapter.dart';
import '../services/onedrive_client_adapter.dart';
import '../services/log_service.dart';
import '../utils/formatters.dart';
import 'diff_viewer_dialog.dart';
import '../l10n/provider_operation_strings.dart';
import '../l10n/version_history_strings.dart';

void showVersionHistoryDialog(
  BuildContext context,
  WidgetRef ref,
  FileItem file, {
  PanelFileOrigin? sourceOrigin,
  http.Client? httpClient,
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
      builder: (_) => _VersionHistoryDialog(
        file: file,
        origin: origin,
        httpClient: httpClient,
      ),
    );
  } catch (error) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$error')));
  }
}

class _VersionMessage implements Exception {
  const _VersionMessage(this.template, [this.values = const {}]);
  final String template;
  final Map<String, Object?> values;
  String localized(VersionHistoryStrings strings) => strings.format(template, values);
}

class _VersionHistoryDialog extends ConsumerStatefulWidget {
  final FileItem file;
  final PanelFileOrigin origin;
  final http.Client? httpClient;
  const _VersionHistoryDialog({
    required this.file,
    required this.origin,
    this.httpClient,
  });

  @override
  ConsumerState<_VersionHistoryDialog> createState() =>
      _VersionHistoryDialogState();
}

class _VersionHistoryDialogState extends ConsumerState<_VersionHistoryDialog> {
  static const _log = Log('VersionHistory');

  late final FileActionRequests _requests;

  List<Map<String, dynamic>> _versions = [];
  bool _loading = true;
  bool _restoring = false;
  bool _comparing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _requests = FileActionRequests(
      client: widget.httpClient,
      ensureCurrent: () {
        if (!mounted) throw StateError('The version dialog was closed.');
        capturedRemoteClient(widget.origin);
      },
    );
    _loadVersions();
  }

  @override
  void dispose() {
    _requests.close();
    super.dispose();
  }

  Future<void> _loadVersions() async {
    try {
      final client = capturedRemoteClient(widget.origin);

      List<Map<String, dynamic>> versions = [];

      if (client is GDriveClientAdapter) {
        versions = await _loadGDriveVersions(
          client,
          requireFileId(widget.file),
        );
      } else if (client is DropboxClientAdapter) {
        versions = await _loadDropboxVersions(client, widget.file);
      } else if (client is OneDriveClientAdapter) {
        versions = await _loadOneDriveVersions(client, widget.file);
      } else {
        throw UnsupportedError(
          '${client.providerName} does not support version history',
        );
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
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<List<Map<String, dynamic>>> _loadGDriveVersions(
    GDriveClientAdapter client,
    String fileId,
  ) async {
    final token = client.accessToken;
    if (token == null) throw Exception('Not authenticated');
    final resp = await _requests.request(
      'GET',
      Uri.parse(
        'https://www.googleapis.com/drive/v3/files/$fileId/revisions?fields=revisions(id,modifiedTime,size,lastModifyingUser/displayName)',
      ),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (resp.statusCode != 200) {
      throw StateError(
        'Version history could not be read (${resp.statusCode}).',
      );
    }
    final data = json.decode(resp.body);
    return ((data['revisions'] as List?) ?? [])
        .map(
          (r) => <String, dynamic>{
            'id': r['id'],
            'modified': r['modifiedTime'],
            'size': int.tryParse(r['size']?.toString() ?? '0') ?? 0,
            'expectedLength': int.tryParse(r['size']?.toString() ?? ''),
            'author': r['lastModifyingUser']?['displayName'] ?? '',
            'provider': 'gdrive',
            'fileId': fileId,
          },
        )
        .toList();
  }

  Future<List<Map<String, dynamic>>> _loadDropboxVersions(
    DropboxClientAdapter client,
    FileItem file,
  ) async {
    final token = client.accessToken;
    if (token == null) throw Exception('Not authenticated');
    final path = requireFilePath(file);
    final resp = await _requests.request(
      'POST',
      Uri.parse('https://api.dropboxapi.com/2/files/list_revisions'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode({'path': path, 'limit': 50}),
    );
    if (resp.statusCode != 200) {
      throw StateError(
        'Version history could not be read (${resp.statusCode}).',
      );
    }
    final data = json.decode(resp.body);
    return ((data['entries'] as List?) ?? [])
        .map(
          (r) => <String, dynamic>{
            'id': r['rev'],
            'modified': r['server_modified'],
            'size': r['size'] ?? 0,
            'author': '',
            'provider': 'dropbox',
            'path': path,
          },
        )
        .toList();
  }

  Future<List<Map<String, dynamic>>> _loadOneDriveVersions(
    OneDriveClientAdapter client,
    FileItem file,
  ) async {
    final token = client.accessToken;
    if (token == null) throw Exception('Not authenticated');
    final fileId = requireFileId(file);
    final resp = await _requests.request(
      'GET',
      Uri.parse(
        'https://graph.microsoft.com/v1.0/me/drive/items/$fileId/versions',
      ),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (resp.statusCode != 200) {
      throw StateError(
        'Version history could not be read (${resp.statusCode}).',
      );
    }
    final data = json.decode(resp.body);
    return ((data['value'] as List?) ?? [])
        .map(
          (r) => <String, dynamic>{
            'id': r['id'],
            'modified': r['lastModifiedDateTime'],
            'size': r['size'] ?? 0,
            'author': r['lastModifiedBy']?['user']?['displayName'] ?? '',
            'provider': 'onedrive',
            'fileId': fileId,
          },
        )
        .toList();
  }

  // --- Restore Methods ---

  Future<void> _restoreVersion(Map<String, dynamic> version) async {
    final strings = VersionHistoryStrings(context);
    final provider = version['provider'] as String;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: Text(context.commanderTr("Restore Version?")),
        content: Text(
          context.commanderTr(
            "This will replace the current file with the version from {0}. The current version will be preserved in the version history.",
            [version['modified'] ?? context.commanderTr("Unknown date")],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.commanderTr("Cancel")),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.commanderTr("Restore")),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() {
      _restoring = true;
      _comparing = false;
    });

    try {
      final client = capturedRemoteClient(widget.origin);

      switch (provider) {
        case 'gdrive':
          await _restoreGDriveVersion(client as GDriveClientAdapter, version);
          break;
        case 'dropbox':
          await _restoreDropboxVersion(client as DropboxClientAdapter, version);
          break;
        case 'onedrive':
          await _restoreOneDriveVersion(
            client as OneDriveClientAdapter,
            version,
          );
          break;
      }

      _log.info('Restored version ${version['id']} for ${widget.file.name}');

      _requests.check();
      // Both panes can display this account. Refresh only matching origins.
      for (final side in PanelSide.values) {
        final panel = ref.read(panelProvider(side));
        try {
          if (panel.captureCurrentOrigin().storageId ==
              widget.origin.storageId) {
            await panel.refresh();
          }
        } catch (_) {
          // Collections and an unrelated/disconnected pane need no refresh.
        }
        _requests.check();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.commanderTr("Restored {0} to version from {1}", [
                widget.file.name,
                version['modified'],
              ]),
            ),
          ),
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
          SnackBar(
            content: Text(context.commanderTr("Restore failed: {0}", [e])),
          ),
        );
      }
    }
  }

  /// GDrive: Copy the revision content back to the file.
  /// Uses the revisions.get endpoint with alt=media to download the revision,
  /// then re-uploads it to the same file via PATCH.
  Future<void> _restoreGDriveVersion(
    GDriveClientAdapter client,
    Map<String, dynamic> version,
  ) async {
    await _requests.restoreDriveRevision(
      fileId: version['fileId'] as String,
      revisionId: version['id'] as String,
      token: client.accessToken!,
      expectedLength: version['expectedLength'] as int?,
    );
  }

  /// Dropbox: Use restore endpoint to promote a revision.
  Future<void> _restoreDropboxVersion(
    DropboxClientAdapter client,
    Map<String, dynamic> version,
  ) async {
    final token = client.accessToken!;
    final path = version['path'] as String;
    final rev = version['id'] as String;

    final resp = await _requests.request(
      'POST',
      Uri.parse('https://api.dropboxapi.com/2/files/restore'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode({'path': path, 'rev': rev}),
    );
    if (resp.statusCode != 200) {
      throw Exception(
        'Dropbox restore failed: ${resp.statusCode} ${resp.body}',
      );
    }
  }

  /// OneDrive: Restore a version using the restoreVersion action.
  Future<void> _restoreOneDriveVersion(
    OneDriveClientAdapter client,
    Map<String, dynamic> version,
  ) async {
    final token = client.accessToken!;
    final fileId = version['fileId'] as String;
    final versionId = version['id'] as String;

    final resp = await _requests.request(
      'POST',
      Uri.parse(
        'https://graph.microsoft.com/v1.0/me/drive/items/$fileId/versions/$versionId/restoreVersion',
      ),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    // 204 = success, 200 = success with body
    if (resp.statusCode != 204 && resp.statusCode != 200) {
      throw Exception(
        'OneDrive restore failed: ${resp.statusCode} ${resp.body}',
      );
    }
  }

  /// Download version content for diff comparison.
  Future<String?> _downloadVersionContent(Map<String, dynamic> version) async {
    try {
      final client = capturedRemoteClient(widget.origin);
      final provider = version['provider'] as String;

      if (provider == 'gdrive') {
        final token = (client as GDriveClientAdapter).accessToken!;
        final fileId = version['fileId'] as String;
        final revisionId = version['id'] as String;
        final resp = await _requests.request(
          'GET',
          Uri.parse(
            'https://www.googleapis.com/drive/v3/files/$fileId/revisions/$revisionId?alt=media',
          ),
          headers: {'Authorization': 'Bearer $token'},
          maxBytes: MergeDocumentSession.maxTextBytes,
        );
        if (resp.statusCode == 200) {
          return utf8.decode(resp.bodyBytes, allowMalformed: true);
        }
      } else if (provider == 'dropbox') {
        final token = (client as DropboxClientAdapter).accessToken!;
        final rev = version['id'] as String;
        final arg = json.encode({'path': 'rev:$rev'});
        final resp = await _requests.request(
          'POST',
          Uri.parse('https://content.dropboxapi.com/2/files/download'),
          headers: {'Authorization': 'Bearer $token', 'Dropbox-API-Arg': arg},
          maxBytes: MergeDocumentSession.maxTextBytes,
        );
        if (resp.statusCode == 200) {
          return utf8.decode(resp.bodyBytes, allowMalformed: true);
        }
      } else if (provider == 'onedrive') {
        final token = (client as OneDriveClientAdapter).accessToken!;
        final fileId = version['fileId'] as String;
        final versionId = version['id'] as String;
        final resp = await _requests.request(
          'GET',
          Uri.parse(
            'https://graph.microsoft.com/v1.0/me/drive/items/$fileId/versions/$versionId/content',
          ),
          headers: {'Authorization': 'Bearer $token'},
          maxBytes: MergeDocumentSession.maxTextBytes,
        );
        if (resp.statusCode == 200) {
          return utf8.decode(resp.bodyBytes, allowMalformed: true);
        }
      }
    } catch (e) {
      _log.error('Failed to download version content', e);
      rethrow;
    }
    return null;
  }

  /// Compare a version with the current version using the diff viewer.
  Future<void> _compareVersion(Map<String, dynamic> version) async {
    setState(() {
      _restoring = true;
      _comparing = true;
    });

    try {
      // Download the old version
      final oldContent = await _downloadVersionContent(version);
      if (oldContent == null) throw const _VersionMessage('Failed to download version');

      // Download the current version
      final client = capturedRemoteClient(widget.origin);
      final backend = CloudOperationBackend(
        client,
        isCurrent: () => widget.origin.isCurrent && mounted,
      );
      final current = await backend.stat(requireFilePath(widget.file));
      if (current == null ||
          (widget.file.uuid != null && current.uuid != widget.file.uuid)) {
        throw StateError('The original file is missing or was replaced.');
      }
      final currentBytes = await readFileBytesBounded(
        backend,
        current,
        maxBytes: MergeDocumentSession.maxTextBytes,
      );
      _requests.check();
      final currentContent = utf8.decode(currentBytes, allowMalformed: true);

      if (!mounted) return;
      setState(() => _restoring = false);

      final modified = DateTime.tryParse(version['modified'] ?? '');
      final versionLabel = modified != null
          ? formatDateFull(modified)
          : '${version['id']}';

      showDiffViewerFromContent(
        context,
        leftContent: oldContent,
        rightContent: currentContent,
        leftLabel: context.commanderTr("Version {0}", [versionLabel]),
        rightLabel: context.commanderTr("Current"),
      );
    } catch (e) {
      _log.error('Version diff failed', e);
      if (mounted) {
        setState(() => _restoring = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.commanderTr("Diff failed: {0}", [e]))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = VersionHistoryStrings(context);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.history, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.commanderTr("Version History — {0}", [widget.file.name]),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        height: 400,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              )
            : _versions.isEmpty
            ? Center(
                child: Text(
                  context.commanderTr("No version history available"),
                ),
              )
            : Stack(
                children: [
                  ListView.builder(
                    itemCount: _versions.length,
                    itemBuilder: (context, index) {
                      final v = _versions[index];
                      final modified = DateTime.tryParse(v['modified'] ?? '');
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                modified != null
                                    ? formatDateFull(modified)
                                    : context.commanderTr("Version {0}", [
                                        v['id'],
                                      ]),
                                style: theme.textTheme.titleSmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${formatBytes(v['size'] as int)}${v['author']?.isNotEmpty == true ? ' • ${v['author']}' : ''}',
                                style: theme.textTheme.bodySmall,
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  TextButton.icon(
                                    icon: const Icon(
                                      Icons.compare_arrows,
                                      size: 18,
                                    ),
                                    onPressed: _restoring
                                        ? null
                                        : () => _compareVersion(v),
                                    label: Text(context.commanderTr("Diff")),
                                  ),
                                  TextButton.icon(
                                    icon: const Icon(Icons.restore, size: 18),
                                    onPressed: _restoring
                                        ? null
                                        : () => _restoreVersion(v),
                                    label: Text(context.commanderTr("Restore")),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  if (_restoring)
                    Container(
                      color: Colors.black26,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 12),
                            Text(
                              _comparing
                                  ? context.commanderTr("Loading…")
                                  : context.commanderTr("Restoring..."),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
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
      ],
    );
  }
}
