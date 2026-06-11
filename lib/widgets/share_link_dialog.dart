// lib/widgets/share_link_dialog.dart
//
// Generates a shareable link for a remote file via the provider's native API.
// Supports password protection and expiration for providers that support it.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../models/file_item.dart';
import '../providers/providers.dart';
import '../services/gdrive_client_adapter.dart';
import '../services/dropbox_client_adapter.dart';
import '../services/onedrive_client_adapter.dart';
import '../services/s3_client_adapter.dart';
import '../services/log_service.dart';
import '../l10n/app_localizations.dart';

void showShareLinkDialog(BuildContext context, WidgetRef ref, FileItem file) {
  showDialog(
    context: context,
    builder: (_) => _ShareLinkDialog(file: file),
  );
}

class _ShareLinkDialog extends ConsumerStatefulWidget {
  final FileItem file;
  const _ShareLinkDialog({required this.file});

  @override
  ConsumerState<_ShareLinkDialog> createState() => _ShareLinkDialogState();
}

class _ShareLinkDialogState extends ConsumerState<_ShareLinkDialog> {
  static const _log = Log('ShareLink');

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
    _passwordController.dispose();
    super.dispose();
  }

  bool get _supportsPassword {
    final client = ref.read(authProvider).client;
    return client is DropboxClientAdapter || client is OneDriveClientAdapter;
  }

  bool get _supportsExpiration {
    final client = ref.read(authProvider).client;
    return client is DropboxClientAdapter || client is OneDriveClientAdapter;
  }

  Future<void> _generateLink() async {
    setState(() { _loading = true; _error = null; });

    try {
      final auth = ref.read(authProvider);
      final client = auth.client;
      final fileId = widget.file.uuid ?? widget.file.name;
      final path = widget.file.path ?? '/${widget.file.name}';
      String? url;

      if (client is GDriveClientAdapter) {
        final token = client.accessToken!;
        // Create "anyone with link" permission
        await http.post(
          Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId/permissions'),
          headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
          body: json.encode({'role': 'reader', 'type': 'anyone'}),
        );
        url = 'https://drive.google.com/file/d/$fileId/view?usp=sharing';
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

        final resp = await http.post(
          Uri.parse('https://api.dropboxapi.com/2/sharing/create_shared_link_with_settings'),
          headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
          body: json.encode(body),
        );
        if (resp.statusCode == 200 || resp.statusCode == 409) {
          final data = json.decode(resp.body);
          url = data['url'] ?? data['error']?['.tag'] == 'shared_link_already_exists'
              ? 'Link already exists (check Dropbox sharing settings)'
              : null;
          // On 409 (already exists), try to get the existing link
          if (resp.statusCode == 409) {
            final listResp = await http.post(
              Uri.parse('https://api.dropboxapi.com/2/sharing/list_shared_links'),
              headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
              body: json.encode({'path': path, 'direct_only': true}),
            );
            if (listResp.statusCode == 200) {
              final links = json.decode(listResp.body)['links'] as List?;
              if (links != null && links.isNotEmpty) url = links.first['url'];
            }
          }
        } else {
          throw Exception('Dropbox share failed: ${resp.statusCode} ${resp.body}');
        }
      } else if (client is OneDriveClientAdapter) {
        final token = client.accessToken!;
        final body = <String, dynamic>{
          'type': 'view',
          'scope': 'anonymous',
        };
        if (_usePassword && _passwordController.text.isNotEmpty) {
          body['password'] = _passwordController.text;
        }
        if (_useExpiration) {
          final expiry = DateTime.now().add(Duration(days: _expirationDays));
          body['expirationDateTime'] = expiry.toUtc().toIso8601String();
        }

        final resp = await http.post(
          Uri.parse('https://graph.microsoft.com/v1.0/me/drive/items/$fileId/createLink'),
          headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
          body: json.encode(body),
        );
        if (resp.statusCode == 200 || resp.statusCode == 201) {
          final data = json.decode(resp.body);
          url = data['link']?['webUrl'];
        } else {
          throw Exception('OneDrive share failed: ${resp.statusCode} ${resp.body}');
        }
      } else if (client is S3ClientAdapter) {
        final expiry = _useExpiration
            ? Duration(days: _expirationDays)
            : const Duration(hours: 1);
        url = client.generatePresignedUrl(path, expires: expiry);
      } else if (client.supportsSharing) {
        url = 'Share links not yet implemented for ${client.providerName}';
      } else {
        throw UnsupportedError('${client.providerName} does not support sharing');
      }

      if (mounted) {
        setState(() {
          _shareUrl = url;
          _loading = false;
          _generated = true;
        });
      }
    } catch (e) {
      _log.error('Share link generation failed', e);
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.link, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('Share — ${widget.file.name}', overflow: TextOverflow.ellipsis)),
        ],
      ),
      content: SizedBox(
        width: 450,
        child: _loading
            ? const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            : _error != null
                ? Text(_error!, style: TextStyle(color: theme.colorScheme.error))
                : _generated
                    ? _buildResultView(theme)
                    : _buildOptionsView(theme),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context)!.close)),
        if (!_generated && !_loading)
          ElevatedButton.icon(
            icon: const Icon(Icons.link, size: 16),
            label: const Text('Generate Link'),
            onPressed: _generateLink,
          ),
        if (_generated && _shareUrl != null)
          ElevatedButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy Link'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _shareUrl ?? ''));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Link copied to clipboard')),
              );
            },
          ),
      ],
    );
  }

  Widget _buildOptionsView(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Share Options', style: theme.textTheme.titleSmall),
        const SizedBox(height: 12),

        // Password protection
        if (_supportsPassword) ...[
          SwitchListTile(
            title: const Text('Password Protection'),
            subtitle: const Text('Require password to access'),
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
                decoration: const InputDecoration(
                  labelText: 'Link Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                  isDense: true,
                ),
                obscureText: true,
              ),
            ),
        ],

        // Expiration
        if (_supportsExpiration) ...[
          SwitchListTile(
            title: const Text('Expiration'),
            subtitle: Text(_useExpiration ? 'Expires in $_expirationDays days' : 'Link never expires'),
            value: _useExpiration,
            onChanged: (v) => setState(() => _useExpiration = v),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
          if (_useExpiration)
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 8),
              child: Row(
                children: [
                  const Text('Expires in: '),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: _expirationDays,
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('1 day')),
                      DropdownMenuItem(value: 3, child: Text('3 days')),
                      DropdownMenuItem(value: 7, child: Text('7 days')),
                      DropdownMenuItem(value: 14, child: Text('14 days')),
                      DropdownMenuItem(value: 30, child: Text('30 days')),
                      DropdownMenuItem(value: 90, child: Text('90 days')),
                    ],
                    onChanged: (v) => setState(() => _expirationDays = v ?? 7),
                  ),
                ],
              ),
            ),
        ],

        if (!_supportsPassword && !_supportsExpiration)
          Text(
            'This provider does not support password or expiration options.',
            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
          ),
      ],
    );
  }

  Widget _buildResultView(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: TextEditingController(text: _shareUrl),
          readOnly: true,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: 'Share URL',
            suffixIcon: IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Copy to clipboard',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _shareUrl ?? ''));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Link copied to clipboard')),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_usePassword)
          Row(
            children: [
              Icon(Icons.lock, size: 14, color: theme.colorScheme.primary),
              const SizedBox(width: 4),
              Text('Password protected', style: TextStyle(fontSize: 12, color: theme.colorScheme.primary)),
            ],
          ),
        if (_useExpiration)
          Row(
            children: [
              Icon(Icons.timer, size: 14, color: theme.colorScheme.tertiary),
              const SizedBox(width: 4),
              Text('Expires in $_expirationDays days', style: TextStyle(fontSize: 12, color: theme.colorScheme.tertiary)),
            ],
          ),
        const SizedBox(height: 8),
        Text(
          'Anyone with this link can access the file.',
          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
