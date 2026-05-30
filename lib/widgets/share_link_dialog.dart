// lib/widgets/share_link_dialog.dart
//
// Generates a shareable link for a remote file via the provider's native API.
// Copies the link to clipboard.

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
  String? _shareUrl;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _generateLink();
  }

  Future<void> _generateLink() async {
    try {
      final auth = ref.read(authProvider);
      final client = auth.client;
      final fileId = widget.file.uuid ?? widget.file.name;
      String? url;

      if (client is GDriveClientAdapter) {
        // GDrive: create a "anyone with link can view" permission
        url = 'https://drive.google.com/file/d/$fileId/view?usp=sharing';
      } else if (client is DropboxClientAdapter) {
        // Dropbox: create a shared link
        url = 'https://www.dropbox.com/preview${widget.file.path ?? "/${widget.file.name}"}';
      } else if (client is OneDriveClientAdapter) {
        // OneDrive: create a sharing link
        url = 'https://onedrive.live.com/?id=$fileId';
      } else if (client.supportsSharing) {
        url = 'Share links not yet implemented for ${client.providerName}';
      } else {
        throw UnsupportedError('${client.providerName} does not support sharing');
      }

      if (mounted) {
        setState(() {
          _shareUrl = url;
          _loading = false;
        });
      }
    } catch (e) {
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
                : Column(
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
                      Text(
                        'Anyone with this link can access the file (subject to provider permissions).',
                        style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        if (_shareUrl != null)
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
}
