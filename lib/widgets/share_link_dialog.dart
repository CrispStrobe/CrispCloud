// lib/widgets/share_link_dialog.dart
//
// Generates a shareable link for a remote file via the provider's native API.
// Supports password protection and expiration for providers that support it.

import '../l10n/commander_strings.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../models/file_item.dart';
import '../providers/providers.dart';
import 'file_origin_actions.dart';
import '../services/gdrive_client_adapter.dart';
import '../services/file_action_requests.dart';
import '../services/panel_source_service.dart';
import '../services/dropbox_client_adapter.dart';
import '../services/onedrive_client_adapter.dart';
import '../services/s3_client_adapter.dart';
import '../services/log_service.dart';
import '../l10n/provider_operation_strings.dart';
import '../l10n/app_localizations.dart';
import '../l10n/share_link_strings.dart';

void showShareLinkDialog(
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
      builder: (_) =>
          _ShareLinkDialog(file: file, origin: origin, httpClient: httpClient),
    );
  } catch (error) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$error')));
  }
}

class _ShareMessage implements Exception {
  const _ShareMessage(this.message);
  final String message;
  @override
  String toString() => message;
}

class _ShareLinkDialog extends ConsumerStatefulWidget {
  final FileItem file;
  final PanelFileOrigin origin;
  final http.Client? httpClient;
  const _ShareLinkDialog({
    required this.file,
    required this.origin,
    this.httpClient,
  });

  @override
  ConsumerState<_ShareLinkDialog> createState() => _ShareLinkDialogState();
}

class _ShareLinkDialogState extends ConsumerState<_ShareLinkDialog> {
  static const _log = Log('ShareLink');

  late final FileActionRequests _requests;
  final _urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _requests = FileActionRequests(
      client: widget.httpClient,
      ensureCurrent: () {
        if (!mounted) throw StateError('The share dialog was closed.');
        capturedRemoteClient(widget.origin);
      },
    );
  }

  String? _shareUrl;
  bool _loading = false;
  String? _error;

  // Share options
  final _passwordController = TextEditingController();
  bool _usePassword = false;
  bool _useExpiration = false;
  int _expirationDays = 7;
  bool _generated = false;

  @override
  void dispose() {
    _requests.close();
    _urlController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _supportsPassword {
    final client = (widget.origin.source as RemotePanelSource).client;
    return client is DropboxClientAdapter || client is OneDriveClientAdapter;
  }

  bool get _supportsExpiration {
    final client = (widget.origin.source as RemotePanelSource).client;
    return client is DropboxClientAdapter || client is OneDriveClientAdapter;
  }

  Future<void> _generateLink() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = capturedRemoteClient(widget.origin);
      if (_usePassword && _passwordController.text.isEmpty) {
        throw ArgumentError('Enter a link password.');
      }
      final fileId =
          client is GDriveClientAdapter || client is OneDriveClientAdapter
          ? requireFileId(widget.file)
          : '';
      final path = requireFilePath(widget.file);
      String? url;

      if (client is GDriveClientAdapter) {
        final token = client.accessToken!;
        // Create "anyone with link" permission
        final response = await _requests.request(
          'POST',
          Uri.parse(
            'https://www.googleapis.com/drive/v3/files/$fileId/permissions',
          ),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: json.encode({'role': 'reader', 'type': 'anyone'}),
        );
        if (response.statusCode != 200 && response.statusCode != 201) {
          throw StateError(
            'Google Drive share failed (${response.statusCode}).',
          );
        }
        url = widget.file.isFolder
            ? 'https://drive.google.com/drive/folders/$fileId?usp=sharing'
            : 'https://drive.google.com/file/d/$fileId/view?usp=sharing';
      } else if (client is DropboxClientAdapter) {
        final token = client.accessToken!;
        final body = <String, dynamic>{
          'path': path,
          'settings': <String, dynamic>{
            'requested_visibility': 'public',
            'audience': 'public',
          },
        };
        // Add password if requested
        if (_usePassword && _passwordController.text.isNotEmpty) {
          body['settings'] = {
            ...body['settings'] as Map<String, dynamic>,
            'link_password': _passwordController.text,
            'requested_visibility': 'password',
          };
        }
        // Add expiration if requested
        if (_useExpiration) {
          final expiry = DateTime.now().add(Duration(days: _expirationDays));
          body['settings'] = {
            ...body['settings'] as Map<String, dynamic>,
            'expires': expiry.toUtc().toIso8601String(),
          };
        }

        final resp = await _requests.request(
          'POST',
          Uri.parse(
            'https://api.dropboxapi.com/2/sharing/create_shared_link_with_settings',
          ),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: json.encode(body),
        );
        if (resp.statusCode == 200 || resp.statusCode == 409) {
          final data = json.decode(resp.body);
          url = data['url'] as String?;
          // On 409 (already exists), try to get the existing link
          if (resp.statusCode == 409) {
            if (data['error']?['.tag'] != 'shared_link_already_exists') {
              throw StateError('Dropbox could not create this share link.');
            }
            if (_usePassword || _useExpiration) {
              throw StateError(
                'This file already has a link. Update its password or expiration in Dropbox sharing settings.',
              );
            }
            final listResp = await _requests.request(
              'POST',
              Uri.parse(
                'https://api.dropboxapi.com/2/sharing/list_shared_links',
              ),
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: json.encode({'path': path, 'direct_only': true}),
            );
            if (listResp.statusCode == 200) {
              final links = json.decode(listResp.body)['links'] as List?;
              if (links != null && links.isNotEmpty) url = links.first['url'];
            }
          }
        } else {
          throw Exception(
            'Dropbox share failed: ${resp.statusCode} ${resp.body}',
          );
        }
      } else if (client is OneDriveClientAdapter) {
        final token = client.accessToken!;
        final body = <String, dynamic>{'type': 'view', 'scope': 'anonymous'};
        if (_usePassword && _passwordController.text.isNotEmpty) {
          body['password'] = _passwordController.text;
        }
        if (_useExpiration) {
          final expiry = DateTime.now().add(Duration(days: _expirationDays));
          body['expirationDateTime'] = expiry.toUtc().toIso8601String();
        }

        final resp = await _requests.request(
          'POST',
          Uri.parse(
            'https://graph.microsoft.com/v1.0/me/drive/items/$fileId/createLink',
          ),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: json.encode(body),
        );
        if (resp.statusCode == 200 || resp.statusCode == 201) {
          final data = json.decode(resp.body);
          url = data['link']?['webUrl'];
        } else {
          throw Exception(
            'OneDrive share failed: ${resp.statusCode} ${resp.body}',
          );
        }
      } else if (client is S3ClientAdapter) {
        final expiry = _useExpiration
            ? Duration(days: _expirationDays)
            : const Duration(hours: 1);
        url = client.generatePresignedUrl(path, expires: expiry);
      } else {
        throw UnsupportedError(
          '${client.providerName} does not support sharing',
        );
      }

      _requests.check();
      final parsed = Uri.tryParse(url ?? '');
      if (parsed == null ||
          !parsed.hasAuthority ||
          !const ['https', 'http'].contains(parsed.scheme)) {
        throw StateError('The provider did not return a share link.');
      }
      if (mounted) {
        setState(() {
          _shareUrl = url;
          _urlController.text = url!;
          _loading = false;
          _generated = true;
        });
      }
    } catch (e) {
      _log.error('Share link generation failed', e);
      if (mounted) {
        setState(() {
          _error = localizedProviderError(context, e);
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = ShareLinkStrings(context);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.link, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.commanderTr("Share — {0}", [widget.file.name]),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 450,
          child: _loading
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                )
              : _error != null
              ? Text(_error!, style: TextStyle(color: theme.colorScheme.error))
              : _generated
              ? _buildResultView(theme)
              : _buildOptionsView(theme),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context)!.close),
        ),
        if (!_generated && !_loading)
          ElevatedButton.icon(
            icon: const Icon(Icons.link, size: 16),
            label: Text(context.commanderTr("Generate Link")),
            onPressed: _generateLink,
          ),
        if (_generated && _shareUrl != null)
          ElevatedButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: Text(context.commanderTr("Copy Link")),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _shareUrl ?? ''));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    context.commanderTr("Link copied to clipboard"),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildOptionsView(ThemeData theme) {
    final strings = ShareLinkStrings(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.commanderTr("Share Options"),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 12),

        // Password protection
        if (_supportsPassword) ...[
          SwitchListTile(
            title: Text(context.commanderTr("Password Protection")),
            subtitle: Text(context.commanderTr("Require password to access")),
            value: _usePassword,
            onChanged: (v) => setState(() => _usePassword = v),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
          if (_usePassword)
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 8),
              child: TextField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: context.commanderTr("Link Password"),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock),
                  isDense: true,
                ),
                obscureText: true,
              ),
            ),
        ],

        // Expiration
        if (_supportsExpiration) ...[
          SwitchListTile(
            title: Text(context.commanderTr("Expiration")),
            subtitle: Text(
              _useExpiration
                  ? context.commanderTr("Expires in {0} days", [
                      _expirationDays,
                    ])
                  : context.commanderTr("Link never expires"),
            ),
            value: _useExpiration,
            onChanged: (v) => setState(() => _useExpiration = v),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
          if (_useExpiration)
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.commanderTr("Expires in: ")),
                  const SizedBox(height: 8),
                  DropdownButton<int>(
                    isExpanded: true,
                    value: _expirationDays,
                    items: [
                      DropdownMenuItem(
                        value: 1,
                        child: Text(context.commanderTr("1 day")),
                      ),
                      DropdownMenuItem(
                        value: 3,
                        child: Text(context.commanderTr("3 days")),
                      ),
                      DropdownMenuItem(
                        value: 7,
                        child: Text(context.commanderTr("7 days")),
                      ),
                      DropdownMenuItem(
                        value: 14,
                        child: Text(context.commanderTr("14 days")),
                      ),
                      DropdownMenuItem(
                        value: 30,
                        child: Text(context.commanderTr("30 days")),
                      ),
                      DropdownMenuItem(
                        value: 90,
                        child: Text(context.commanderTr("90 days")),
                      ),
                    ],
                    onChanged: (v) => setState(() => _expirationDays = v ?? 7),
                  ),
                ],
              ),
            ),
        ],

        if (!_supportsPassword && !_supportsExpiration)
          Text(
            context.commanderTr(
              "This provider does not support password or expiration options.",
            ),
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  Widget _buildResultView(ThemeData theme) {
    final strings = ShareLinkStrings(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _urlController,
          readOnly: true,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: context.commanderTr("Share URL"),
            suffixIcon: IconButton(
              icon: const Icon(Icons.copy),
              tooltip: context.commanderTr("Copy to clipboard"),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _shareUrl ?? ''));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      context.commanderTr("Link copied to clipboard"),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_usePassword)
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(Icons.lock, size: 14, color: theme.colorScheme.primary),
              const SizedBox(width: 4),
              Text(
                context.commanderTr("Password protected"),
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        if (_useExpiration)
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(Icons.timer, size: 14, color: theme.colorScheme.tertiary),
              const SizedBox(width: 4),
              Text(
                context.commanderTr("Expires in {0} days", [_expirationDays]),
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.tertiary,
                ),
              ),
            ],
          ),
        const SizedBox(height: 8),
        Text(
          _usePassword
              ? context.commanderTr(
                  "Anyone with this link and password can access the file.",
                )
              : context.commanderTr(
                  "Anyone with this link can access the file.",
                ),
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
