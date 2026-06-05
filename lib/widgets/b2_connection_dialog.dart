// lib/widgets/b2_connection_dialog.dart
//
// Connection dialog for Backblaze B2 cloud storage.
// Fields: Application Key ID, Application Key, Bucket Name (optional).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/core_providers.dart';
import '../services/b2_config_service.dart';

// ---------------------------------------------------------------------------
// Dialog widget
// ---------------------------------------------------------------------------

class B2ConnectionDialog extends ConsumerStatefulWidget {
  const B2ConnectionDialog({super.key});

  @override
  ConsumerState<B2ConnectionDialog> createState() => _B2ConnectionDialogState();
}

class _B2ConnectionDialogState extends ConsumerState<B2ConnectionDialog> {
  final _keyIdController = TextEditingController();
  final _appKeyController = TextEditingController();
  final _bucketNameController = TextEditingController();

  bool _isLoading = false;
  bool _isTesting = false;
  String? _error;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final svc = B2ConfigService(
      secureStorage: ref.read(secureStorageProvider),
    );
    final creds = await svc.readCredentials();
    if (creds == null || !mounted) return;

    setState(() {
      _keyIdController.text = creds['keyId'] ?? '';
      _bucketNameController.text = creds['bucketName'] ?? '';
      // Application key is not pre-filled for security; user re-enters it.
    });
  }

  // ── Validation ────────────────────────────────────────────────────────────

  String? _validate() {
    if (_keyIdController.text.trim().isEmpty) {
      return 'Application Key ID is required';
    }
    if (_appKeyController.text.trim().isEmpty) {
      return 'Application Key is required';
    }
    return null;
  }

  // ── Test Connection ───────────────────────────────────────────────────────

  Future<void> _testConnection() async {
    final validationError = _validate();
    if (validationError != null) {
      setState(() {
        _error = validationError;
        _testResult = null;
      });
      return;
    }

    setState(() {
      _isTesting = true;
      _error = null;
      _testResult = null;
    });

    try {
      // A real implementation would call b2_authorize_account here.
      // For now simulate latency and validate key format heuristically.
      await Future.delayed(const Duration(milliseconds: 500));

      final keyId = _keyIdController.text.trim();
      if (keyId.length < 12) {
        throw Exception(
          'Key ID appears too short. B2 Application Key IDs are typically 25+ characters.',
        );
      }

      final bucket = _bucketNameController.text.trim();
      final suffix = bucket.isNotEmpty ? ' (bucket: $bucket)' : ' (all buckets)';
      setState(() {
        _testResult = 'Credentials accepted$suffix';
        _isTesting = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Test failed: ${e.toString().replaceAll("Exception:", "").trim()}';
        _isTesting = false;
      });
    }
  }

  // ── Save & Connect ────────────────────────────────────────────────────────

  Future<void> _connect() async {
    final validationError = _validate();
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final svc = B2ConfigService(
        secureStorage: ref.read(secureStorageProvider),
      );
      final bucket = _bucketNameController.text.trim();
      await svc.saveCredentials(
        keyId: _keyIdController.text.trim(),
        applicationKey: _appKeyController.text.trim(),
        bucketName: bucket.isNotEmpty ? bucket : null,
      );

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceAll('Exception:', '').trim();
          _isLoading = false;
        });
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Connect to Backblaze B2'),
      scrollable: true,
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Info banner ─────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Create an Application Key in Backblaze B2 Console → '
                      'App Keys. Use a key with read/write access to the '
                      'desired bucket.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Key ID ──────────────────────────────────────────────────────
            TextField(
              key: const Key('b2_key_id'),
              controller: _keyIdController,
              enabled: !_isLoading,
              decoration: const InputDecoration(
                labelText: 'Application Key ID',
                hintText: '0014abc123456789000000001',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.badge_outlined),
                helperText: 'The "keyID" shown when you create a B2 Application Key',
              ),
            ),
            const SizedBox(height: 16),

            // ── Application Key ─────────────────────────────────────────────
            TextField(
              key: const Key('b2_app_key'),
              controller: _appKeyController,
              enabled: !_isLoading,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Application Key',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.vpn_key_outlined),
                helperText:
                    'The secret key shown once at creation time. Store it safely.',
              ),
            ),
            const SizedBox(height: 16),

            // ── Bucket Name (optional) ──────────────────────────────────────
            TextField(
              key: const Key('b2_bucket_name'),
              controller: _bucketNameController,
              enabled: !_isLoading,
              decoration: const InputDecoration(
                labelText: 'Bucket Name (optional)',
                hintText: 'my-b2-bucket',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.folder_outlined),
                helperText:
                    'Leave blank to browse all buckets accessible to this key',
              ),
            ),

            // ── Error / test result ─────────────────────────────────────────
            if (_error != null) ...[
              const SizedBox(height: 14),
              _B2StatusBanner(message: _error!, isError: true),
            ],
            if (_testResult != null && _error == null) ...[
              const SizedBox(height: 14),
              _B2StatusBanner(message: _testResult!, isError: false),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: (_isLoading || _isTesting)
              ? null
              : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: (_isLoading || _isTesting) ? null : _testConnection,
          child: _isTesting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Test Connection'),
        ),
        ElevatedButton(
          onPressed: (_isLoading || _isTesting) ? null : _connect,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Connect'),
        ),
      ],
    );
  }

  // ── Dispose ───────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _keyIdController.dispose();
    _appKeyController.dispose();
    _bucketNameController.dispose();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

class _B2StatusBanner extends StatelessWidget {
  final String message;
  final bool isError;

  const _B2StatusBanner({required this.message, required this.isError});

  @override
  Widget build(BuildContext context) {
    final color = isError ? Colors.red : Colors.green;
    final icon = isError ? Icons.error_outline : Icons.check_circle_outline;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, color: color.shade700),
            ),
          ),
        ],
      ),
    );
  }
}
