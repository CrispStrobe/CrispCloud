// lib/widgets/connection_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/cloud_storage_interface.dart';
import '../services/connection_profiles.dart';
import '../services/log_service.dart';
import 'proxy_settings_dialog.dart';

class ConnectionDialog extends ConsumerStatefulWidget {
  const ConnectionDialog({super.key});

  @override
  ConsumerState<ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends ConsumerState<ConnectionDialog> {
  static final _log = Log('ConnectionDialog');

  // General Controllers
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _tfaController = TextEditingController();
  
  // SFTP Specific Controllers
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '22'); // Default SFTP port
  final _sftpUserController = TextEditingController();

  // FTP Specific Controllers
  final _ftpHostController = TextEditingController();
  final _ftpPortController = TextEditingController(text: '21'); // Default FTP port
  final _ftpUserController = TextEditingController();
  bool _ftpUseTLS = false;

  // S3 Specific Controllers
  final _s3EndpointController = TextEditingController(text: 'https://s3.amazonaws.com');
  final _s3RegionController = TextEditingController(text: 'us-east-1');
  final _s3BucketController = TextEditingController();
  final _s3AccessKeyController = TextEditingController();
  final _s3SecretKeyController = TextEditingController();

  // Encryption
  bool _enableEncryption = false;
  final _passphraseController = TextEditingController();

  bool _isLoading = false;
  bool _needs2fa = false;
  String? _error;

  // Connection profiles
  List<ConnectionProfile> _profiles = [];
  ConnectionProfileService? _profileService;

  // Google Drive Controllers
  final _gdriveClientIdController = TextEditingController();
  final _gdriveClientSecretController = TextEditingController();

  // OneDrive Controllers
  final _onedriveClientIdController = TextEditingController();
  final _onedriveClientSecretController = TextEditingController();

  // Dropbox Controllers
  final _dropboxAppKeyController = TextEditingController();
  final _dropboxAppSecretController = TextEditingController();

  // Default to Filen, or SFTP if preferred
  CloudProvider _selectedProvider = CloudProvider.filen;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    _profileService = ConnectionProfileService(ref.read(secureStorageProvider));
    _profiles = await _profileService!.getForProvider(_selectedProvider.name);
    if (mounted) setState(() {});
  }

  /// Collect current form fields into a map for saving.
  Map<String, String> _collectFields() {
    switch (_selectedProvider) {
      case CloudProvider.sftp:
        return {'host': _hostController.text, 'port': _portController.text, 'user': _sftpUserController.text};
      case CloudProvider.ftp:
        return {'host': _ftpHostController.text, 'port': _ftpPortController.text, 'user': _ftpUserController.text, 'tls': _ftpUseTLS.toString()};
      case CloudProvider.s3:
        return {'endpoint': _s3EndpointController.text, 'region': _s3RegionController.text, 'bucket': _s3BucketController.text, 'accessKey': _s3AccessKeyController.text};
      case CloudProvider.gdrive:
        return {'clientId': _gdriveClientIdController.text, 'clientSecret': _gdriveClientSecretController.text};
      case CloudProvider.onedrive:
        return {'clientId': _onedriveClientIdController.text, 'clientSecret': _onedriveClientSecretController.text};
      case CloudProvider.dropbox:
        return {'appKey': _dropboxAppKeyController.text, 'appSecret': _dropboxAppSecretController.text};
      case CloudProvider.webdav:
        return {'host': _hostController.text, 'user': _emailController.text};
      default:
        return {'email': _emailController.text};
    }
  }

  /// Restore form fields from a profile.
  void _applyProfile(ConnectionProfile profile) {
    final f = profile.fields;
    switch (_selectedProvider) {
      case CloudProvider.sftp:
        _hostController.text = f['host'] ?? '';
        _portController.text = f['port'] ?? '22';
        _sftpUserController.text = f['user'] ?? '';
        break;
      case CloudProvider.ftp:
        _ftpHostController.text = f['host'] ?? '';
        _ftpPortController.text = f['port'] ?? '21';
        _ftpUserController.text = f['user'] ?? '';
        _ftpUseTLS = f['tls'] == 'true';
        break;
      case CloudProvider.s3:
        _s3EndpointController.text = f['endpoint'] ?? 'https://s3.amazonaws.com';
        _s3RegionController.text = f['region'] ?? 'us-east-1';
        _s3BucketController.text = f['bucket'] ?? '';
        _s3AccessKeyController.text = f['accessKey'] ?? '';
        break;
      case CloudProvider.gdrive:
        _gdriveClientIdController.text = f['clientId'] ?? '';
        _gdriveClientSecretController.text = f['clientSecret'] ?? '';
        break;
      case CloudProvider.onedrive:
        _onedriveClientIdController.text = f['clientId'] ?? '';
        _onedriveClientSecretController.text = f['clientSecret'] ?? '';
        break;
      case CloudProvider.dropbox:
        _dropboxAppKeyController.text = f['appKey'] ?? '';
        _dropboxAppSecretController.text = f['appSecret'] ?? '';
        break;
      case CloudProvider.webdav:
        _hostController.text = f['host'] ?? '';
        _emailController.text = f['user'] ?? '';
        break;
      default:
        _emailController.text = f['email'] ?? '';
    }
    setState(() {});
  }

  Future<void> _saveProfile() async {
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save Profile'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Profile Name',
            hintText: 'e.g., Work S3, Personal SFTP',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, nameController.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await _profileService?.save(ConnectionProfile(
      name: name,
      provider: _selectedProvider.name,
      fields: _collectFields(),
    ));
    await _loadProfiles();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Profile "$name" saved')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine which fields to show based on provider
    final isDropbox = _selectedProvider == CloudProvider.dropbox;
    final isFtp = _selectedProvider == CloudProvider.ftp;
    final isGDrive = _selectedProvider == CloudProvider.gdrive;
    final isOneDrive = _selectedProvider == CloudProvider.onedrive;
    final isSftp = _selectedProvider == CloudProvider.sftp;
    final isS3 = _selectedProvider == CloudProvider.s3;
    final isInternxt = _selectedProvider == CloudProvider.internxt;
    final isWebDav = _selectedProvider == CloudProvider.webdav;
    final isOAuth = isGDrive || isOneDrive || isDropbox;

    return AlertDialog(
      title: const Text('Connect to Cloud Storage'),
      scrollable: true, // Allow scrolling if keyboard covers fields
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // --- 1. Provider Selection ---
            DropdownButtonFormField<CloudProvider>(
              value: _selectedProvider,
              decoration: const InputDecoration(
                labelText: 'Provider',
                border: OutlineInputBorder(),
              ),
              items: [
                // Dropbox
                const DropdownMenuItem(
                  value: CloudProvider.dropbox,
                  child: Text('Dropbox'),
                ),
                const DropdownMenuItem(
                  value: CloudProvider.filen,
                  child: Text('Filen'),
                ),
                // FTP / FTPS
                const DropdownMenuItem(
                  value: CloudProvider.ftp,
                  child: Text('FTP / FTPS'),
                ),
                // Google Drive
                const DropdownMenuItem(
                  value: CloudProvider.gdrive,
                  child: Text('Google Drive'),
                ),
                // OneDrive
                const DropdownMenuItem(
                  value: CloudProvider.onedrive,
                  child: Text('OneDrive / SharePoint'),
                ),
                // SFTP / Storage Box
                const DropdownMenuItem(
                  value: CloudProvider.sftp,
                  child: Text('SFTP / Storage Box'),
                ),
                // S3
                const DropdownMenuItem(
                  value: CloudProvider.s3,
                  child: Text('S3 / S3-Compatible'),
                ),
                // WebDAV
                const DropdownMenuItem(
                  value: CloudProvider.webdav,
                  child: Text('WebDAV'),
                ),
                // Internxt (Conditional)
                DropdownMenuItem(
                  value: CloudProvider.internxt,
                  enabled: CloudStorageFactory.isInternxtSupported, 
                  child: Text(
                    CloudStorageFactory.isInternxtSupported 
                      ? 'Internxt' 
                      : 'Internxt (Disabled)',
                    style: TextStyle(
                      color: CloudStorageFactory.isInternxtSupported 
                          ? null 
                          : Theme.of(context).disabledColor,
                    ),
                  ),
                ),
              ],
              onChanged: _isLoading ? null : (value) {
                if (value != null) {
                  if (value == CloudProvider.internxt && !CloudStorageFactory.isInternxtSupported) {
                    return; 
                  }
                  setState(() {
                    _selectedProvider = value;
                    _error = null;
                    _needs2fa = false;
                  });
                  _loadProfiles();
                }
              },
            ),

            // --- 1b. Connection Profiles ---
            if (_profiles.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Saved Profiles',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      hint: const Text('Load a saved profile...'),
                      items: _profiles.map((p) => DropdownMenuItem(
                        value: p.name,
                        child: Text(p.name),
                      )).toList(),
                      onChanged: (name) {
                        if (name == null) return;
                        final profile = _profiles.firstWhere((p) => p.name == name);
                        _applyProfile(profile);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.delete, size: 18),
                    tooltip: 'Delete selected profile',
                    onPressed: () async {
                      if (_profiles.isEmpty) return;
                      // Delete the last selected (or first)
                      final name = await showDialog<String>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Delete Profile'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: _profiles.map((p) => ListTile(
                              title: Text(p.name),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                                onPressed: () => Navigator.pop(ctx, p.name),
                              ),
                            )).toList(),
                          ),
                          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel'))],
                        ),
                      );
                      if (name != null) {
                        await _profileService?.delete(name, _selectedProvider.name);
                        _loadProfiles();
                      }
                    },
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.save, size: 14),
                label: const Text('Save as Profile', style: TextStyle(fontSize: 12)),
                onPressed: _saveProfile,
              ),
            ),
            const SizedBox(height: 8),

            // --- 2. Error Message ---
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 16),
                color: Colors.red.shade100,
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13))),
                  ],
                ),
              ),

            // --- 3. Dynamic Fields ---

            if (isDropbox) ...[
              TextField(
                controller: _dropboxAppKeyController,
                decoration: const InputDecoration(
                  labelText: 'App Key',
                  hintText: 'your_app_key',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.key),
                  helperText: 'From Dropbox App Console → Settings',
                ),
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _dropboxAppSecretController,
                decoration: const InputDecoration(
                  labelText: 'App Secret (optional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                obscureText: true,
                enabled: !_isLoading,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Click Connect to open Dropbox sign-in in your browser. '
                        'Authorize CrispCloud, then return here.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (isGDrive) ...[
              TextField(
                controller: _gdriveClientIdController,
                decoration: const InputDecoration(
                  labelText: 'OAuth2 Client ID',
                  hintText: '123456789.apps.googleusercontent.com',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.key),
                  helperText: 'From Google Cloud Console → APIs & Services → Credentials',
                ),
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _gdriveClientSecretController,
                decoration: const InputDecoration(
                  labelText: 'Client Secret (optional for desktop)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                obscureText: true,
                enabled: !_isLoading,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Click Connect to open Google sign-in in your browser. '
                        'Authorize CrispCloud, then return here.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (isOneDrive) ...[
              TextField(
                controller: _onedriveClientIdController,
                decoration: const InputDecoration(
                  labelText: 'Application (Client) ID',
                  hintText: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.key),
                  helperText: 'From Azure Portal → App Registrations',
                ),
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _onedriveClientSecretController,
                decoration: const InputDecoration(
                  labelText: 'Client Secret (optional for public apps)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                obscureText: true,
                enabled: !_isLoading,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Click Connect to open Microsoft sign-in in your browser. '
                        'Authorize CrispCloud, then return here.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (isS3) ...[
              // S3: Endpoint URL
              TextField(
                controller: _s3EndpointController,
                decoration: const InputDecoration(
                  labelText: 'Endpoint URL',
                  hintText: 'https://s3.amazonaws.com',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.link),
                ),
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              // S3: Region & Bucket Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _s3RegionController,
                      decoration: const InputDecoration(
                        labelText: 'Region',
                        hintText: 'us-east-1',
                        border: OutlineInputBorder(),
                      ),
                      enabled: !_isLoading,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _s3BucketController,
                      decoration: const InputDecoration(
                        labelText: 'Bucket',
                        hintText: 'my-bucket',
                        border: OutlineInputBorder(),
                      ),
                      enabled: !_isLoading,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // S3: Access Key
              TextField(
                controller: _s3AccessKeyController,
                decoration: const InputDecoration(
                  labelText: 'Access Key',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.vpn_key_outlined),
                ),
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              // S3: Secret Key
              TextField(
                controller: _s3SecretKeyController,
                decoration: const InputDecoration(
                  labelText: 'Secret Key',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                obscureText: true,
                enabled: !_isLoading,
              ),
            ] else if (isFtp) ...[
              // FTP: Host & Port Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _ftpHostController,
                      decoration: const InputDecoration(
                        labelText: 'Host',
                        hintText: 'ftp.example.com',
                        border: OutlineInputBorder(),
                      ),
                      enabled: !_isLoading,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: TextField(
                      controller: _ftpPortController,
                      decoration: const InputDecoration(
                        labelText: 'Port',
                        hintText: '21',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      enabled: !_isLoading,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // FTP: Username
              TextField(
                controller: _ftpUserController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  hintText: 'ftpuser',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                ),
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              // FTP: Use TLS checkbox
              CheckboxListTile(
                title: const Text('Use TLS (FTPS)'),
                value: _ftpUseTLS,
                onChanged: _isLoading ? null : (value) {
                  setState(() {
                    _ftpUseTLS = value ?? false;
                  });
                },
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ] else if (isSftp) ...[
              // SFTP: Host & Port Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _hostController,
                      decoration: const InputDecoration(
                        labelText: 'Host',
                        hintText: 'u123.your-storagebox.de',
                        border: OutlineInputBorder(),
                      ),
                      enabled: !_isLoading,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: TextField(
                      controller: _portController,
                      decoration: const InputDecoration(
                        labelText: 'Port',
                        hintText: '22',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      enabled: !_isLoading,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // SFTP: Username
              TextField(
                controller: _sftpUserController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  hintText: 'u12345',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                ),
                enabled: !_isLoading,
              ),
            ] else if (isWebDav) ...[
               // WebDAV Fields
               TextField(
                controller: _hostController,
                decoration: const InputDecoration(
                  labelText: 'Server URL',
                  hintText: 'https://cloud.example.com/remote.php/dav/files/user/',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.link),
                ),
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _emailController, // Reuse as Username
                decoration: const InputDecoration(
                  labelText: 'Username',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                enabled: !_isLoading,
              ),
            
            ] else ...[
              // Standard: Email
              TextField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: isInternxt ? 'Email' : 'Email Address',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.email_outlined),
                ),
                enabled: !_isLoading,
              ),
            ],

            const SizedBox(height: 16),

            // --- 4. Password (Common — hidden for S3/OAuth providers which use own auth) ---
            if (!isS3 && !isOAuth) ...[
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                obscureText: true,
                enabled: !_isLoading,
              ),
            ],

            // --- 5. 2FA (Conditional) ---
            if (_needs2fa) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _tfaController,
                decoration: const InputDecoration(
                  labelText: '2FA Code',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.security),
                ),
                enabled: !_isLoading,
              ),
            ],

            // --- Proxy Settings ---
            const SizedBox(height: 8),
            const Divider(),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.vpn_lock, size: 16),
                label: const Text('Proxy Settings', style: TextStyle(fontSize: 12)),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => const ProxySettingsDialog(),
                  );
                },
              ),
            ),

            // --- Encryption Toggle ---
            const Divider(),
            CheckboxListTile(
              value: _enableEncryption,
              onChanged: (v) => setState(() => _enableEncryption = v ?? false),
              title: const Text('Enable Client-Side Encryption', style: TextStyle(fontSize: 14)),
              subtitle: const Text('Encrypt files before upload (AES-256-GCM)', style: TextStyle(fontSize: 12)),
              secondary: Icon(
                _enableEncryption ? Icons.lock : Icons.lock_open,
                color: _enableEncryption ? Theme.of(context).colorScheme.primary : null,
              ),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
            if (_enableEncryption) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _passphraseController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Encryption Passphrase',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.key),
                  helperText: 'Files will be encrypted/decrypted with this passphrase',
                ),
                enabled: !_isLoading,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _handleLogin,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Connect'),
        ),
      ],
    );
  }

  Future<void> _handleLogin() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final auth = ref.read(authProvider);

    try {
      // 1. Switch provider if needed
      if (auth.currentProvider != _selectedProvider) {
        await auth.switchProvider(_selectedProvider);
      }

      // 2. Prepare Credentials
      String identity;
      String password;
      if (_selectedProvider == CloudProvider.dropbox) {
        if (_dropboxAppKeyController.text.isEmpty) {
          throw Exception('App Key is required');
        }
        final appKey = _dropboxAppKeyController.text.trim();
        final appSecret = _dropboxAppSecretController.text.trim();
        identity = appSecret.isNotEmpty ? '$appKey|$appSecret' : appKey;
        password = '';
      } else if (_selectedProvider == CloudProvider.gdrive) {
        // Google Drive: OAuth2 browser flow
        if (_gdriveClientIdController.text.isEmpty) {
          throw Exception('OAuth2 Client ID is required');
        }
        final clientId = _gdriveClientIdController.text.trim();
        final clientSecret = _gdriveClientSecretController.text.trim();
        identity = clientSecret.isNotEmpty ? '$clientId|$clientSecret' : clientId;
        password = '';
      } else if (_selectedProvider == CloudProvider.onedrive) {
        // OneDrive: OAuth2 browser flow
        if (_onedriveClientIdController.text.isEmpty) {
          throw Exception('Application (Client) ID is required');
        }
        final clientId = _onedriveClientIdController.text.trim();
        final clientSecret = _onedriveClientSecretController.text.trim();
        identity = clientSecret.isNotEmpty ? '$clientId|$clientSecret' : clientId;
        password = '';
      } else if (_selectedProvider == CloudProvider.s3) {
        // S3 Validation
        if (_s3EndpointController.text.isEmpty ||
            _s3BucketController.text.isEmpty ||
            _s3AccessKeyController.text.isEmpty ||
            _s3SecretKeyController.text.isEmpty) {
          throw Exception('Endpoint, Bucket, Access Key, and Secret Key are required');
        }
        final endpoint = _s3EndpointController.text.trim();
        if (!endpoint.startsWith('http://') && !endpoint.startsWith('https://')) {
          throw Exception('Endpoint must start with http:// or https://');
        }
        final region = _s3RegionController.text.trim().isEmpty
            ? 'us-east-1'
            : _s3RegionController.text.trim();
        final bucket = _s3BucketController.text.trim();
        // Pack as: accessKey@endpoint/bucket?region=us-east-1
        identity = '${_s3AccessKeyController.text.trim()}@$endpoint/$bucket?region=$region';
        password = _s3SecretKeyController.text;
      } else if (_selectedProvider == CloudProvider.ftp) {
        // FTP Validation
        if (_ftpHostController.text.isEmpty || _ftpUserController.text.isEmpty) {
          throw Exception('Host and Username are required');
        }

        // Validate port
        final portStr = _ftpPortController.text.isEmpty ? '21' : _ftpPortController.text;
        final portNum = int.tryParse(portStr);
        if (portNum == null || portNum < 1 || portNum > 65535) {
          throw Exception('Port must be a number between 1 and 65535');
        }
        // Construct composite identity for FTP Adapter: "username@host:port?tls=true"
        final tlsFlag = _ftpUseTLS ? '?tls=true' : '';
        identity = '${_ftpUserController.text}@${_ftpHostController.text}:$portStr$tlsFlag';
        password = _passwordController.text;
      } else if (_selectedProvider == CloudProvider.sftp) {
        // SFTP Validation
        if (_hostController.text.isEmpty || _sftpUserController.text.isEmpty) {
          throw Exception('Host and Username are required');
        }
        
        // Validate port
        final portStr = _portController.text.isEmpty ? '22' : _portController.text;
        final portNum = int.tryParse(portStr);
        if (portNum == null || portNum < 1 || portNum > 65535) {
          throw Exception('Port must be a number between 1 and 65535');
        }
        // Construct composite identity for SFTP Adapter: "username@host:port"
        identity = '${_sftpUserController.text}@${_hostController.text}:$portStr';
        password = _passwordController.text;
      } else if (_selectedProvider == CloudProvider.webdav) {
         if (_hostController.text.isEmpty || _emailController.text.isEmpty) {
            throw Exception('Server URL and Username are required');
         }
         final url = _hostController.text.trim();
         if (!url.startsWith('http://') && !url.startsWith('https://')) {
            throw Exception('Server URL must start with http:// or https://');
         }
         final parsed = Uri.tryParse(url);
         if (parsed == null || !parsed.hasAuthority) {
            throw Exception('Invalid server URL');
         }
         // Pack as: username@https://server.com/dav
         identity = '${_emailController.text}@$url';
         password = _passwordController.text;
      } else {
        // Standard Email
        if (_emailController.text.isEmpty) {
          throw Exception('Email is required');
        }
        identity = _emailController.text;
        password = _passwordController.text;
      }

      // 3. Check 2FA (Internxt/Filen only)
      final skipTwoFa = _selectedProvider == CloudProvider.dropbox || _selectedProvider == CloudProvider.gdrive || _selectedProvider == CloudProvider.onedrive || _selectedProvider == CloudProvider.ftp || _selectedProvider == CloudProvider.sftp || _selectedProvider == CloudProvider.s3;
      if (!_needs2fa && !skipTwoFa && auth.client.isAuthenticated == false) {
        try {
          final needs2fa = await auth.client.is2faNeeded(identity);
          if (needs2fa) {
            setState(() {
              _needs2fa = true;
              _isLoading = false;
            });
            return;
          }
        } catch (e) {
          _log.debug('2FA check skipped/failed: $e');
        }
      }

      // 4. Perform Login
      await auth.login(
        identity,
        password,
        _tfaController.text.isEmpty ? null : _tfaController.text,
      );

      // 5. Refresh remote panel after login
      await ref.read(panelProvider(PanelSide.remote)).refresh();

      // 6. Enable encryption if toggled
      if (_enableEncryption && _passphraseController.text.isNotEmpty) {
        auth.enableEncryption(_passphraseController.text);
      }

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceAll('Exception:', '').trim();
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _tfaController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _sftpUserController.dispose();
    _ftpHostController.dispose();
    _ftpPortController.dispose();
    _ftpUserController.dispose();
    _dropboxAppKeyController.dispose();
    _dropboxAppSecretController.dispose();
    _gdriveClientIdController.dispose();
    _gdriveClientSecretController.dispose();
    _onedriveClientIdController.dispose();
    _onedriveClientSecretController.dispose();
    _s3EndpointController.dispose();
    _s3RegionController.dispose();
    _s3BucketController.dispose();
    _s3AccessKeyController.dispose();
    _s3SecretKeyController.dispose();
    _passphraseController.dispose();
    super.dispose();
  }
}