// lib/widgets/connection_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/cloud_storage_interface.dart';

class ConnectionDialog extends ConsumerStatefulWidget {
  const ConnectionDialog({super.key});

  @override
  ConsumerState<ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends ConsumerState<ConnectionDialog> {
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
                }
              },
            ),
            const SizedBox(height: 16),

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

            // --- Encryption Toggle ---
            const SizedBox(height: 8),
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
          debugPrint('2FA check skipped/failed: $e');
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