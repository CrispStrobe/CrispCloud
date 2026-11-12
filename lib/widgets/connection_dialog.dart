import 'package:crisp_storage/crisp_storage.dart'
    show SmbBackend, parseSmbBackend;

import 'smb_backend_field.dart';
import 'cloud_engine_field.dart';
import 'package:crisp_storage/rust_cloud.dart'
    show CloudEngine, RustCloudProvider, RustCloudUnavailable, RustCloudException, RustCloudErrorCode, configuredCloudEngine, parseCloudEngine;
import '../services/filen_client_adapter.dart';
import '../services/internxt_client_adapter.dart';
import '../services/sftp_client_adapter.dart';
import '../services/smb_client_adapter.dart';

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
// lib/widgets/connection_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/cloud_storage_interface.dart';
import '../services/connection_profiles.dart';
import '../services/encryption_service.dart';
import '../services/log_service.dart';
import '../services/s3_client_adapter.dart';
import 'azure_connection_dialog.dart';
import 'b2_connection_dialog.dart';
import 'proxy_settings_dialog.dart';
import 'file_encryption_recovery_dialog.dart';
import '../l10n/app_localizations.dart';
import '../l10n/s3_storage_class_strings.dart';
import '../l10n/connection_dialog_extra_strings.dart';
import '../l10n/connection_strings.dart';
import '../l10n/connection_failure_strings.dart';
import '../l10n/provider_operation_strings.dart';
import '../l10n/sftp_key_strings.dart';
import '../l10n/key_management_strings.dart';
import '../services/nextcloud_client_adapter.dart';

class ConnectionDialog extends ConsumerStatefulWidget {
  const ConnectionDialog({super.key});

  @override
  ConsumerState<ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends ConsumerState<ConnectionDialog> {
  static const _log = Log('ConnectionDialog');

  // General Controllers
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _tfaController = TextEditingController();

  // SFTP Specific Controllers
  final _hostController = TextEditingController();
  final _portController = TextEditingController(
    text: '22',
  ); // Default SFTP port
  final _sftpUserController = TextEditingController();
  final _sftpKeyPassphraseController = TextEditingController();
  bool _sftpUsePrivateKey = false;
  String? _sftpPrivateKey;
  String? _sftpPrivateKeyName;

  // FTP Specific Controllers
  final _ftpHostController = TextEditingController();
  final _ftpPortController = TextEditingController(
    text: '21',
  ); // Default FTP port
  final _ftpUserController = TextEditingController();
  bool _ftpUseTLS = false;
  bool _smbRequireEncryption = true;
  SmbBackend _smbBackend = SmbBackend.libsmb2;
  bool _invalidSmbProfile = false;
  CloudEngine _cloudEngine = configuredCloudEngine(RustCloudProvider.filen);

  bool get _usesCloudEngine =>
      _selectedProvider == CloudProvider.filen ||
      _selectedProvider == CloudProvider.internxt;

  static CloudEngine _defaultEngineFor(CloudProvider provider) =>
      configuredCloudEngine(
        provider == CloudProvider.internxt
            ? RustCloudProvider.internxt
            : RustCloudProvider.filen,
      );

  bool get _smbProfileNeedsTransport =>
      _selectedProvider == CloudProvider.smb && _invalidSmbProfile;

  // S3 Specific Controllers
  final _s3EndpointController = TextEditingController(
    text: 'https://s3.amazonaws.com',
  );
  final _s3RegionController = TextEditingController(text: 'us-east-1');
  final _s3BucketController = TextEditingController();
  final _s3AccessKeyController = TextEditingController();
  final _s3SecretKeyController = TextEditingController();
  S3Encryption _s3Encryption = S3Encryption.none;
  final _s3KmsKeyIdController = TextEditingController();
  S3StorageClass _s3StorageClass = S3StorageClass.standard;

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

  // pCloud Controllers
  final _pcloudAppKeyController = TextEditingController();
  bool _pcloudUseEu = false;

  // Nextcloud Controllers
  final _nextcloudServerUrlController = TextEditingController();
  final _nextcloudUsernameController = TextEditingController();

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
      case CloudProvider.azure:
        return {'email': _emailController.text};
      case CloudProvider.b2:
        return {'email': _emailController.text};
      case CloudProvider.sftp:
        return {
          'host': _hostController.text,
          'port': _portController.text,
          'user': _sftpUserController.text,
        };
      case CloudProvider.ftp:
        return {
          'host': _ftpHostController.text,
          'port': _ftpPortController.text,
          'user': _ftpUserController.text,
          'tls': _ftpUseTLS.toString(),
        };
      case CloudProvider.s3:
        return {
          'endpoint': _s3EndpointController.text,
          'region': _s3RegionController.text,
          'bucket': _s3BucketController.text,
          'accessKey': _s3AccessKeyController.text,
          'encryption': _s3Encryption.name,
          'storageClass': _s3StorageClass.headerValue,
          if (_s3KmsKeyIdController.text.isNotEmpty)
            'kmsKeyId': _s3KmsKeyIdController.text,
        };
      case CloudProvider.gdrive:
        return {
          'clientId': _gdriveClientIdController.text,
          'clientSecret': _gdriveClientSecretController.text,
        };
      case CloudProvider.onedrive:
        return {
          'clientId': _onedriveClientIdController.text,
          'clientSecret': _onedriveClientSecretController.text,
        };
      case CloudProvider.dropbox:
        return {
          'appKey': _dropboxAppKeyController.text,
          'appSecret': _dropboxAppSecretController.text,
        };
      case CloudProvider.pcloud:
        return {
          'appKey': _pcloudAppKeyController.text,
          'eu': _pcloudUseEu.toString(),
        };
      case CloudProvider.nextcloud:
        return {
          'serverUrl': _nextcloudServerUrlController.text,
          'username': _nextcloudUsernameController.text,
        };
      case CloudProvider.webdav:
        return {'host': _hostController.text, 'user': _emailController.text};
      case CloudProvider.smb:
        return {
          'host': _hostController.text,
          'user': _emailController.text,
          'requireEncryption': '$_smbRequireEncryption',
          'smbBackend': _smbBackend.name,
        };
      default:
        return {
          'email': _emailController.text,
          if (_usesCloudEngine) 'engine': _cloudEngine.name,
        };
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
        _s3EndpointController.text =
            f['endpoint'] ?? 'https://s3.amazonaws.com';
        _s3RegionController.text = f['region'] ?? 'us-east-1';
        _s3BucketController.text = f['bucket'] ?? '';
        _s3AccessKeyController.text = f['accessKey'] ?? '';
        final encName = f['encryption'];
        if (encName != null) {
          _s3Encryption = S3Encryption.values.firstWhere(
            (e) => e.name == encName,
            orElse: () => S3Encryption.none,
          );
        }
        final scVal = f['storageClass'];
        if (scVal != null) {
          _s3StorageClass = S3StorageClassX.fromHeaderValue(scVal);
        }
        _s3KmsKeyIdController.text = f['kmsKeyId'] ?? '';
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
      case CloudProvider.pcloud:
        _pcloudAppKeyController.text = f['appKey'] ?? '';
        _pcloudUseEu = f['eu'] == 'true';
        break;
      case CloudProvider.nextcloud:
        _nextcloudServerUrlController.text = f['serverUrl'] ?? '';
        _nextcloudUsernameController.text = f['username'] ?? '';
        break;
      case CloudProvider.webdav:
        _hostController.text = f['host'] ?? '';
        _emailController.text = f['user'] ?? '';
        break;
      case CloudProvider.smb:
        // Reject the whole profile before changing fields or reusing the
        // previous transport. Recovery requires an explicit valid choice.
        final SmbBackend backend;
        try {
          backend = parseSmbBackend(f['smbBackend']) ?? SmbBackend.libsmb2;
        } on FormatException {
          setState(() {
            _invalidSmbProfile = true;
            _error = null;
          });
          return;
        }
        _hostController.text = f['host'] ?? '';
        _emailController.text = f['user'] ?? '';
        _smbRequireEncryption = f['requireEncryption'] != 'false';
        _smbBackend = backend;
        _invalidSmbProfile = false;
        _error = null;
        break;
      case CloudProvider.filen:
      case CloudProvider.internxt:
        final CloudEngine engine;
        try {
          engine =
              parseCloudEngine(f['engine']) ??
              _defaultEngineFor(_selectedProvider);
        } on FormatException {
          setState(
            () => _error = ConnectionDialogExtraStrings(
              context,
            ).text('invalidCloudEngineProfile'),
          );
          return;
        }
        _emailController.text = f['email'] ?? '';
        _cloudEngine = engine;
        _error = null;
      default:
        _emailController.text = f['email'] ?? '';
    }
    setState(() {});
  }

  Future<void> _saveProfile() async {
    final t = ConnectionDialogExtraStrings(context);
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.text('saveProfile')),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(
            labelText: t.text('profileName'),
            hintText: t.text('profileHint'),
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, nameController.text),
            child: Text(AppLocalizations.of(context)!.save),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await _profileService?.save(
      ConnectionProfile(
        name: name,
        provider: _selectedProvider.name,
        fields: _collectFields(),
      ),
    );
    await _loadProfiles();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.text('profileSaved', {'name': name}))),
      );
    }
  }

  String _credentialHintKey(CloudProvider provider) => switch (provider) {
    CloudProvider.dropbox ||
    CloudProvider.gdrive ||
    CloudProvider.onedrive ||
    CloudProvider.pcloud => 'hintOauth',
    CloudProvider.azure => 'hintAzure',
    CloudProvider.b2 => 'hintB2',
    CloudProvider.s3 => 'hintS3',
    CloudProvider.ftp ||
    CloudProvider.sftp ||
    CloudProvider.smb ||
    CloudProvider.webdav ||
    CloudProvider.nextcloud => 'hintServer',
    _ => 'hintSecure',
  };

  @override
  Widget build(BuildContext context) {
    final t = ConnectionDialogExtraStrings(context);
    final l10n = AppLocalizations.of(context)!;
    final error = _smbProfileNeedsTransport
        ? t.text('invalidSmbBackendProfile')
        : _error;
    // Determine which fields to show based on provider
    final isAzure = _selectedProvider == CloudProvider.azure;
    final isB2 = _selectedProvider == CloudProvider.b2;
    final isDropbox = _selectedProvider == CloudProvider.dropbox;
    final isFtp = _selectedProvider == CloudProvider.ftp;
    final isGDrive = _selectedProvider == CloudProvider.gdrive;
    final isOneDrive = _selectedProvider == CloudProvider.onedrive;
    final isPCloud = _selectedProvider == CloudProvider.pcloud;
    final isNextcloud = _selectedProvider == CloudProvider.nextcloud;
    final isSftp = _selectedProvider == CloudProvider.sftp;
    final isS3 = _selectedProvider == CloudProvider.s3;
    final isWebDav = _selectedProvider == CloudProvider.webdav;
    final isSmb = _selectedProvider == CloudProvider.smb;
    final isOAuth = isGDrive || isOneDrive || isDropbox || isPCloud;

    return AlertDialog(
      title: Text(t.text('connectTitle')),
      scrollable: true, // Allow scrolling if keyboard covers fields
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // --- 1. Provider Selection ---
            DropdownButtonFormField<CloudProvider>(
              initialValue: _selectedProvider,
              decoration: InputDecoration(
                labelText: l10n.provider,
                border: const OutlineInputBorder(),
              ),
              items: CloudProvider.values.map((provider) {
                final enabled =
                    (provider != CloudProvider.internxt ||
                        CloudStorageFactory.isInternxtSupported) &&
                    !(kIsWeb && provider == CloudProvider.smb);
                return DropdownMenuItem(
                  value: provider,
                  enabled: enabled,
                  child: Text(
                    enabled
                        ? provider.displayName
                        : t.text('disabled', {'name': provider.displayName}),
                    style: TextStyle(
                      color: enabled ? null : Theme.of(context).disabledColor,
                    ),
                  ),
                );
              }).toList(),
              onChanged: _isLoading
                  ? null
                  : (value) {
                      if (value != null) {
                        if (value == CloudProvider.internxt &&
                            !CloudStorageFactory.isInternxtSupported) {
                          return;
                        }
                        setState(() {
                          _selectedProvider = value;
                          _cloudEngine = _defaultEngineFor(value);
                          if (value == CloudProvider.azure ||
                              value == CloudProvider.b2) {
                            _enableEncryption = false;
                            _passphraseController.clear();
                          }
                          _error = null;
                          _needs2fa = false;
                        });
                        _loadProfiles();
                      }
                    },
            ),

            const SizedBox(height: 8),
            Semantics(
              label: t.text('providerGuidance'),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.text(
                        'provider${_selectedProvider.name[0].toUpperCase()}${_selectedProvider.name.substring(1)}',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t.text(_credentialHintKey(_selectedProvider)),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // --- 1b. Connection Profiles ---
            if (_profiles.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      decoration: InputDecoration(
                        labelText: t.text('savedProfiles'),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      hint: Text(t.text('loadProfile')),
                      items: _profiles
                          .map(
                            (p) => DropdownMenuItem(
                              value: p.name,
                              child: Text(p.name),
                            ),
                          )
                          .toList(),
                      onChanged: (name) {
                        if (name == null) return;
                        final profile = _profiles.firstWhere(
                          (p) => p.name == name,
                        );
                        _applyProfile(profile);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.delete, size: 18),
                    tooltip: t.text('deleteSelected'),
                    onPressed: () async {
                      if (_profiles.isEmpty) return;
                      // Delete the last selected (or first)
                      final name = await showDialog<String>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(t.text('deleteProfile')),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: _profiles
                                .map(
                                  (p) => ListTile(
                                    title: Text(p.name),
                                    trailing: IconButton(
                                      icon: const Icon(
                                        Icons.delete,
                                        color: Colors.red,
                                        size: 18,
                                      ),
                                      onPressed: () =>
                                          Navigator.pop(ctx, p.name),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: Text(AppLocalizations.of(context)!.cancel),
                            ),
                          ],
                        ),
                      );
                      if (name != null) {
                        await _profileService?.delete(
                          name,
                          _selectedProvider.name,
                        );
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
                label: Text(
                  t.text('saveProfile'),
                  style: const TextStyle(fontSize: 12),
                ),
                onPressed: _saveProfile,
              ),
            ),
            const SizedBox(height: 8),

            // --- 2. Error Message ---
            if (error != null)
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 16),
                color: Colors.red.shade100,
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        error,
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

            // --- 3. Dynamic Fields ---
            if (isAzure) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t.text('azureHelp'),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (isB2) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t.text('b2Help'),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (isDropbox) ...[
              TextField(
                controller: _dropboxAppKeyController,
                decoration: InputDecoration(
                  labelText: l10n.appKey,
                  hintText: 'your_app_key',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.key),
                  helperText: t.text('dropboxConsole'),
                ),
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _dropboxAppSecretController,
                decoration: InputDecoration(
                  labelText: t.text('appSecretOptional'),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock_outline),
                ),
                obscureText: true,
                enabled: !_isLoading,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t.text('oauthHelp', {'provider': 'Dropbox'}),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (isGDrive) ...[
              TextField(
                controller: _gdriveClientIdController,
                decoration: InputDecoration(
                  labelText: t.text('oauthId'),
                  hintText: '123456789.apps.googleusercontent.com',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.key),
                  helperText: t.text('googleConsole'),
                ),
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _gdriveClientSecretController,
                decoration: InputDecoration(
                  labelText: t.text('clientSecretDesktop'),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock_outline),
                ),
                obscureText: true,
                enabled: !_isLoading,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t.text('oauthHelp', {'provider': 'Google'}),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (isOneDrive) ...[
              TextField(
                controller: _onedriveClientIdController,
                decoration: InputDecoration(
                  labelText: t.text('appClientId'),
                  hintText: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.key),
                  helperText: t.text('azureConsole'),
                ),
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _onedriveClientSecretController,
                decoration: InputDecoration(
                  labelText: t.text('clientSecretPublic'),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock_outline),
                ),
                obscureText: true,
                enabled: !_isLoading,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t.text('oauthHelp', {'provider': 'Microsoft'}),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (isPCloud) ...[
              TextField(
                controller: _pcloudAppKeyController,
                decoration: InputDecoration(
                  labelText: l10n.appKey,
                  hintText: 'your_pcloud_app_key',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.key),
                  helperText: t.text('pcloudConsole'),
                ),
                enabled: !_isLoading,
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                title: Text(t.text('useEu')),
                subtitle: Text(
                  t.text('euRequired'),
                  style: const TextStyle(fontSize: 11),
                ),
                value: _pcloudUseEu,
                onChanged: _isLoading
                    ? null
                    : (v) => setState(() => _pcloudUseEu = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t.text('oauthHelp', {'provider': 'pCloud'}),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (isS3) ...[
              // S3: Endpoint URL
              TextField(
                controller: _s3EndpointController,
                decoration: InputDecoration(
                  labelText: l10n.endpoint,
                  hintText: 'https://s3.amazonaws.com',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.link),
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
                      decoration: InputDecoration(
                        labelText: l10n.region,
                        hintText: 'us-east-1',
                        border: const OutlineInputBorder(),
                      ),
                      enabled: !_isLoading,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _s3BucketController,
                      decoration: InputDecoration(
                        labelText: l10n.bucket,
                        hintText: 'my-bucket',
                        border: const OutlineInputBorder(),
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
                decoration: InputDecoration(
                  labelText: l10n.accessKey,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.vpn_key_outlined),
                ),
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              // S3: Secret Key
              TextField(
                controller: _s3SecretKeyController,
                decoration: InputDecoration(
                  labelText: l10n.secretKey,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock_outline),
                ),
                obscureText: true,
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              // S3: Server-Side Encryption
              DropdownButtonFormField<S3Encryption>(
                value: _s3Encryption,
                decoration: InputDecoration(
                  labelText: t.text('serverEncryption'),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.enhanced_encryption_outlined),
                ),
                items: [
                  DropdownMenuItem(
                    value: S3Encryption.none,
                    child: Text(t.text('none')),
                  ),
                  DropdownMenuItem(
                    value: S3Encryption.sseS3,
                    child: Text('SSE-S3 (AES-256)'),
                  ),
                  DropdownMenuItem(
                    value: S3Encryption.sseKms,
                    child: Text('SSE-KMS'),
                  ),
                ],
                onChanged: _isLoading
                    ? null
                    : (v) {
                        if (v != null) setState(() => _s3Encryption = v);
                      },
              ),
              if (_s3Encryption == S3Encryption.sseKms) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _s3KmsKeyIdController,
                  decoration: InputDecoration(
                    labelText: t.text('kmsOptional'),
                    border: const OutlineInputBorder(),
                    hintText: 'arn:aws:kms:region:account:key/key-id',
                  ),
                  enabled: !_isLoading,
                ),
              ],
              const SizedBox(height: 16),
              // S3: Storage Class
              DropdownButtonFormField<S3StorageClass>(
                value: _s3StorageClass,
                decoration: InputDecoration(
                  labelText: t.text('storageClass'),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.storage_outlined),
                ),
                items: S3StorageClass.values
                    .map(
                      (sc) => DropdownMenuItem(
                        value: sc,
                        child: Text(S3StorageClassStrings(context).label(sc)),
                      ),
                    )
                    .toList(),
                onChanged: _isLoading
                    ? null
                    : (v) {
                        if (v != null) setState(() => _s3StorageClass = v);
                      },
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
                      decoration: InputDecoration(
                        labelText: l10n.host,
                        hintText: 'ftp.example.com',
                        border: const OutlineInputBorder(),
                      ),
                      enabled: !_isLoading,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: TextField(
                      controller: _ftpPortController,
                      decoration: InputDecoration(
                        labelText: l10n.port,
                        hintText: '21',
                        border: const OutlineInputBorder(),
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
                decoration: InputDecoration(
                  labelText: l10n.username,
                  hintText: 'ftpuser',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.person_outline),
                ),
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              // FTP: Use TLS checkbox
              CheckboxListTile(
                title: Text(t.text('useTls')),
                value: _ftpUseTLS,
                onChanged: _isLoading
                    ? null
                    : (value) {
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
                      decoration: InputDecoration(
                        labelText: l10n.host,
                        hintText: 'u123.your-storagebox.de',
                        border: const OutlineInputBorder(),
                      ),
                      enabled: !_isLoading,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: TextField(
                      controller: _portController,
                      decoration: InputDecoration(
                        labelText: l10n.port,
                        hintText: '22',
                        border: const OutlineInputBorder(),
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
                decoration: InputDecoration(
                  labelText: l10n.username,
                  hintText: 'u12345',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.person_outline),
                ),
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<bool>(
                initialValue: _sftpUsePrivateKey,
                decoration: InputDecoration(
                  labelText: SftpKeyStrings(context).authentication,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: false,
                    child: Text(SftpKeyStrings(context).password),
                  ),
                  DropdownMenuItem(
                    value: true,
                    child: Text(SftpKeyStrings(context).privateKey),
                  ),
                ],
                onChanged: _isLoading
                    ? null
                    : (value) {
                        if (value != null)
                          setState(() => _sftpUsePrivateKey = value);
                      },
              ),
              if (_sftpUsePrivateKey) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _chooseSftpPrivateKey,
                  icon: const Icon(Icons.key),
                  label: Text(SftpKeyStrings(context).chooseKey),
                ),
                if (_sftpPrivateKeyName != null)
                  Text(
                    '${SftpKeyStrings(context).keySelected}: $_sftpPrivateKeyName',
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: _sftpKeyPassphraseController,
                  obscureText: true,
                  enabled: !_isLoading,
                  decoration: InputDecoration(
                    labelText: SftpKeyStrings(context).passphrase,
                    helperText: SftpKeyStrings(context).storageHelp,
                    helperMaxLines: 3,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ] else if (isWebDav || isSmb) ...[
              // WebDAV Fields
              TextField(
                controller: _hostController,
                decoration: InputDecoration(
                  labelText: l10n.serverUrl,
                  hintText: isSmb
                      ? 'smb://nas.local/Share/'
                      : 'https://cloud.example.com/remote.php/dav/files/user/',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.link),
                ),
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _emailController, // Reuse as Username
                decoration: InputDecoration(
                  labelText: l10n.username,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.person),
                ),
                enabled: !_isLoading,
              ),
              if (isSmb)
                SmbBackendField(
                  value: _smbBackend,
                  onChanged: _isLoading
                      ? null
                      : (v) => setState(() {
                          _smbBackend = v;
                          _invalidSmbProfile = false;
                        }),
                ),
              if (isSmb)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t.text('requireSmb')),
                  subtitle: Text(t.text('smbHelp')),
                  value: _smbRequireEncryption,
                  onChanged: _isLoading
                      ? null
                      : (v) => setState(() => _smbRequireEncryption = v!),
                ),
            ] else if (isNextcloud) ...[
              // Nextcloud: Server URL
              TextField(
                controller: _nextcloudServerUrlController,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.serverUrl,
                  hintText: 'https://nextcloud.example.com',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.cloud_outlined),
                  helperText: ConnectionStrings.of(context).serverAddress,
                ),
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              // Nextcloud: Username
              TextField(
                controller: _nextcloudUsernameController,
                decoration: InputDecoration(
                  labelText: l10n.username,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.person_outline),
                ),
                enabled: !_isLoading,
              ),
            ] else ...[
              // Standard: Email
              TextField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: t.text('email'),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.email_outlined),
                ),
                enabled: !_isLoading,
              ),
              if (_usesCloudEngine && !kIsWeb)
                CloudEngineField(
                  value: _cloudEngine,
                  onChanged: _isLoading
                      ? null
                      : (v) => setState(() => _cloudEngine = v),
                ),
            ],

            const SizedBox(height: 16),

            // --- 4. Password (Common — hidden for S3/OAuth providers which use own auth) ---
            if (!isS3 && !isOAuth && !(isSftp && _sftpUsePrivateKey)) ...[
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: isNextcloud
                      ? ConnectionStrings.of(context).passwordOrAppPassword
                      : AppLocalizations.of(context)!.password,
                  helperText: isNextcloud
                      ? ConnectionStrings.of(context).appPasswordHelp
                      : null,
                  helperMaxLines: 2,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock_outline),
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
                decoration: InputDecoration(
                  labelText: l10n.twoFactorCode,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.security),
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
                label: Text(
                  l10n.proxySettings,
                  style: const TextStyle(fontSize: 12),
                ),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => const ProxySettingsDialog(),
                  );
                },
              ),
            ),

            // --- Encryption Toggle ---
            if (!isAzure && !isB2) ...[
              const Divider(),
              CheckboxListTile(
                key: const Key('connection_file_encryption_toggle'),
                value: _enableEncryption,
                onChanged: _isLoading
                    ? null
                    : (v) => setState(() => _enableEncryption = v ?? false),
                title: Text(
                  t.text('clientEncryption'),
                  style: const TextStyle(fontSize: 14),
                ),
                subtitle: Text(
                  t.text('encryptHelp'),
                  style: const TextStyle(fontSize: 12),
                ),
                secondary: Icon(
                  _enableEncryption ? Icons.lock : Icons.lock_open,
                  color: _enableEncryption
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
              if (_enableEncryption) ...[
                const SizedBox(height: 8),
                TextField(
                  key: const Key('connection_file_encryption_passphrase'),
                  controller: _passphraseController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: t.text('passphrase'),
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.key),
                    helperText: t.text('passphraseHelp'),
                  ),
                  enabled: !_isLoading,
                ),
              ],
            ] else
              Text(
                KeyManagementStrings(context).text('fileEncryptionDelegated'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context)!.cancel),
        ),
        ElevatedButton(
          onPressed: _isLoading || _smbProfileNeedsTransport
              ? null
              : _handleLogin,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.connect),
        ),
      ],
    );
  }

  Future<void> _chooseSftpPrivateKey() async {
    try {
      final result = await FilePicker.platform.pickFiles(withData: true);
      if (!mounted || result == null) return;
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty || bytes.length > 1024 * 1024) {
        setState(() {
          _sftpPrivateKey = null;
          _sftpPrivateKeyName = null;
          _error = SftpKeyStrings(context).readFailed;
        });
        return;
      }
      final pem = utf8.decode(bytes);
      setState(() {
        _sftpPrivateKey = pem;
        _sftpPrivateKeyName = file.name;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _sftpPrivateKey = null;
          _sftpPrivateKeyName = null;
          _error = SftpKeyStrings(context).readFailed;
        });
      }
    }
  }

  Future<void> _handleLogin() async {
    if (_isLoading || _smbProfileNeedsTransport) return;
    final t = ConnectionDialogExtraStrings(context);
    final encryptionRequested = _enableEncryption;
    final encryptionPassphrase = _passphraseController.text;
    if (encryptionRequested &&
        (_selectedProvider == CloudProvider.azure ||
            _selectedProvider == CloudProvider.b2)) {
      setState(() {
        _error = KeyManagementStrings(context).text('fileEncryptionDelegated');
      });
      return;
    }
    if (encryptionRequested && encryptionPassphrase.trim().isEmpty) {
      setState(() {
        _error = KeyManagementStrings(context).text('passphraseRequired');
      });
      return;
    }
    if (_selectedProvider == CloudProvider.sftp &&
        _sftpUsePrivateKey &&
        _sftpPrivateKey == null) {
      setState(() => _error = SftpKeyStrings(context).keyRequired);
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final auth = ref.read(authProvider);
    // Keep post-login settings independent of controllers that may be disposed
    // if the connection dialog is closed while authentication is in progress.
    final s3Encryption = _s3Encryption;
    final s3KmsKeyId = _s3KmsKeyIdController.text.trim();
    final s3StorageClass = _s3StorageClass;

    try {
      // 1. Switch provider if needed
      if (auth.currentProvider != _selectedProvider) {
        await auth.switchProvider(_selectedProvider);
      }
      if (!mounted) return;

      // 2. Prepare Credentials
      String identity;
      String password;
      if (_selectedProvider == CloudProvider.azure) {
        // Delegate to the dedicated Azure dialog.
        setState(() => _isLoading = false);
        if (mounted) {
          Navigator.pop(context);
          showDialog(
            context: context,
            builder: (_) => const _AzureDialogProxy(),
          );
        }
        return;
      } else if (_selectedProvider == CloudProvider.b2) {
        // Delegate to the dedicated B2 dialog.
        setState(() => _isLoading = false);
        if (mounted) {
          Navigator.pop(context);
          showDialog(context: context, builder: (_) => const _B2DialogProxy());
        }
        return;
      } else if (_selectedProvider == CloudProvider.dropbox) {
        if (_dropboxAppKeyController.text.isEmpty) {
          throw Exception(t.text('keyRequired'));
        }
        final appKey = _dropboxAppKeyController.text.trim();
        final appSecret = _dropboxAppSecretController.text.trim();
        identity = appSecret.isNotEmpty ? '$appKey|$appSecret' : appKey;
        password = '';
      } else if (_selectedProvider == CloudProvider.gdrive) {
        // Google Drive: OAuth2 browser flow
        if (_gdriveClientIdController.text.isEmpty) {
          throw Exception(t.text('oauthIdRequired'));
        }
        final clientId = _gdriveClientIdController.text.trim();
        final clientSecret = _gdriveClientSecretController.text.trim();
        identity = clientSecret.isNotEmpty
            ? '$clientId|$clientSecret'
            : clientId;
        password = '';
      } else if (_selectedProvider == CloudProvider.onedrive) {
        // OneDrive: OAuth2 browser flow
        if (_onedriveClientIdController.text.isEmpty) {
          throw Exception(t.text('applicationIdRequired'));
        }
        final clientId = _onedriveClientIdController.text.trim();
        final clientSecret = _onedriveClientSecretController.text.trim();
        identity = clientSecret.isNotEmpty
            ? '$clientId|$clientSecret'
            : clientId;
        password = '';
      } else if (_selectedProvider == CloudProvider.pcloud) {
        // pCloud: OAuth2 browser flow
        if (_pcloudAppKeyController.text.isEmpty) {
          throw Exception(t.text('keyRequired'));
        }
        final appKey = _pcloudAppKeyController.text.trim();
        identity = _pcloudUseEu ? '$appKey|eu' : appKey;
        password = '';
      } else if (_selectedProvider == CloudProvider.s3) {
        // S3 Validation
        if (_s3EndpointController.text.isEmpty ||
            _s3BucketController.text.isEmpty ||
            _s3AccessKeyController.text.isEmpty ||
            _s3SecretKeyController.text.isEmpty) {
          throw Exception(t.text('s3Required'));
        }
        final endpoint = _s3EndpointController.text.trim();
        if (!endpoint.startsWith('http://') &&
            !endpoint.startsWith('https://')) {
          throw Exception(t.text('endpointScheme'));
        }
        final region = _s3RegionController.text.trim().isEmpty
            ? 'us-east-1'
            : _s3RegionController.text.trim();
        final bucket = _s3BucketController.text.trim();
        // Pack as: accessKey@endpoint/bucket?region=us-east-1
        identity =
            '${_s3AccessKeyController.text.trim()}@$endpoint/$bucket?region=$region';
        password = _s3SecretKeyController.text;
      } else if (_selectedProvider == CloudProvider.ftp) {
        // FTP Validation
        if (_ftpHostController.text.isEmpty ||
            _ftpUserController.text.isEmpty) {
          throw Exception(t.text('hostUserRequired'));
        }

        // Validate port
        final portStr = _ftpPortController.text.isEmpty
            ? '21'
            : _ftpPortController.text;
        final portNum = int.tryParse(portStr);
        if (portNum == null || portNum < 1 || portNum > 65535) {
          throw Exception(t.text('portInvalid'));
        }
        // Construct composite identity for FTP Adapter: "username@host:port?tls=true"
        final tlsFlag = _ftpUseTLS ? '?tls=true' : '';
        identity =
            '${_ftpUserController.text}@${_ftpHostController.text}:$portStr$tlsFlag';
        password = _passwordController.text;
      } else if (_selectedProvider == CloudProvider.sftp) {
        // SFTP Validation
        if (_hostController.text.trim().isEmpty ||
            _sftpUserController.text.trim().isEmpty) {
          throw Exception(t.text('hostUserRequired'));
        }

        // Validate port
        final portStr = _portController.text.isEmpty
            ? '22'
            : _portController.text;
        final portNum = int.tryParse(portStr);
        if (portNum == null || portNum < 1 || portNum > 65535) {
          throw Exception(t.text('portInvalid'));
        }
        identity = SFTPClientAdapter.identityFromFields(
          username: _sftpUserController.text,
          host: _hostController.text,
          port: portNum,
          web: kIsWeb,
        );
        password = _passwordController.text;
      } else if (_selectedProvider == CloudProvider.smb) {
        if (_hostController.text.trim().isEmpty ||
            _emailController.text.trim().isEmpty) {
          throw Exception(t.text('urlUserRequired'));
        }
        identity =
            '${_emailController.text.trim()}@${_hostController.text.trim()}';
        password = _passwordController.text;
      } else if (_selectedProvider == CloudProvider.webdav) {
        if (_hostController.text.isEmpty || _emailController.text.isEmpty) {
          throw Exception(t.text('urlUserRequired'));
        }
        final url = _hostController.text.trim();
        if (!url.startsWith('http://') && !url.startsWith('https://')) {
          throw Exception(t.text('urlScheme'));
        }
        final parsed = Uri.tryParse(url);
        if (parsed == null || !parsed.hasAuthority) {
          throw Exception(t.text('invalidUrl'));
        }
        // Pack as: username@https://server.com/dav
        identity = '${_emailController.text}@$url';
        password = _passwordController.text;
      } else if (_selectedProvider == CloudProvider.nextcloud) {
        if (_nextcloudUsernameController.text.isEmpty ||
            _nextcloudServerUrlController.text.isEmpty) {
          throw Exception(t.text('urlUserRequired'));
        }
        final url = _nextcloudServerUrlController.text.trim();
        if (!url.startsWith('http://') && !url.startsWith('https://')) {
          throw Exception(t.text('urlScheme'));
        }
        final parsed = Uri.tryParse(url);
        if (parsed == null || !parsed.hasAuthority) {
          throw Exception(t.text('invalidUrl'));
        }
        // Pack as: username@https://nextcloud.example.com
        identity = '${_nextcloudUsernameController.text.trim()}@$url';
        password = _passwordController.text;
      } else {
        // Standard Email
        if (_emailController.text.isEmpty) {
          throw Exception(t.text('emailRequired'));
        }
        identity = _emailController.text;
        password = _passwordController.text;
      }

      // 3. Check 2FA (Internxt/Filen only)
      final skipTwoFa =
          _selectedProvider == CloudProvider.dropbox ||
          _selectedProvider == CloudProvider.gdrive ||
          _selectedProvider == CloudProvider.onedrive ||
          _selectedProvider == CloudProvider.pcloud ||
          _selectedProvider == CloudProvider.nextcloud ||
          _selectedProvider == CloudProvider.ftp ||
          _selectedProvider == CloudProvider.sftp ||
          _selectedProvider == CloudProvider.s3;
      if (!_needs2fa && !skipTwoFa && auth.client.isAuthenticated == false) {
        try {
          final needs2fa = await auth.client.is2faNeeded(identity);
          if (!mounted) return;
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
      if (!mounted) return;

      // Prepare once, then require recovery of this exact key before login.
      // The ciphertext format does not carry the derivation salt and the key
      // is session-only, so deriving another key on a later login loses access.
      Uint8List? preparedKey;
      Uint8List? preparedSalt;
      if (encryptionRequested && !auth.isEncryptionEnabled) {
        preparedSalt = EncryptionService.generateSalt();
        preparedKey = EncryptionService.deriveKey(
          encryptionPassphrase,
          preparedSalt,
        );
        final confirmed = await showFileEncryptionRecoveryDialog(
          context,
          encryptionKey: preparedKey,
          salt: preparedSalt,
        );
        if (!mounted) return;
        if (!confirmed) {
          setState(() => _isLoading = false);
          return;
        }
      }

      if (auth.client is SFTPClientAdapter) {
        (auth.client as SFTPClientAdapter).confirmHostKey =
            (endpoint, fingerprint) async {
              if (!mounted) return false;
              return await showDialog<bool>(
                    context: context,
                    barrierDismissible: false,
                    builder: (ctx) => AlertDialog(
                      title: Text(t.text('verifySsh')),
                      content: SelectableText(
                        t.text('sshFingerprint', {
                          'endpoint': endpoint,
                          'fingerprint': fingerprint,
                        }),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(AppLocalizations.of(context)!.cancel),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(t.text('trust')),
                        ),
                      ],
                    ),
                  ) ??
                  false;
            };
      }
      // 4. Perform Login
      if (auth.client is SmbClientAdapter) {
        (auth.client as SmbClientAdapter).requireEncryption =
            _smbRequireEncryption;
        (auth.client as SmbClientAdapter).smbBackend = _smbBackend;
      }
      final engineClient = auth.client;
      if (engineClient is FilenClientAdapter) engineClient.engine = _cloudEngine;
      if (engineClient is InternxtClientAdapter) {
        engineClient.engine = _cloudEngine;
      }
      if (_selectedProvider == CloudProvider.sftp && _sftpUsePrivateKey) {
        await auth.loginSftpWithPrivateKey(
          identity,
          _sftpPrivateKey!,
          _sftpKeyPassphraseController.text.isEmpty
              ? null
              : _sftpKeyPassphraseController.text,
        );
      } else {
        await auth.login(
          identity,
          password,
          _tfaController.text.isEmpty ? null : _tfaController.text,
        );
      }

      // 5. Apply S3-specific settings after login
      if (_selectedProvider == CloudProvider.s3) {
        final client = auth.client;
        if (client is S3ClientAdapter) {
          client.encryption = s3Encryption;
          if (s3Encryption == S3Encryption.sseKms && s3KmsKeyId.isNotEmpty) {
            client.kmsKeyId = s3KmsKeyId;
          }
          client.storageClass = s3StorageClass;
        }
      }

      // 6. Activate only the key whose recovery phrase was confirmed. This
      // must happen even if this dialog closed during a successful login.
      if (preparedKey != null && preparedSalt != null) {
        auth.enableEncryptionWithKey(preparedKey, preparedSalt);
      }
      if (!mounted) return;

      // 7. Refresh through the wrapper, after encryption has been installed.
      await ref.read(panelProvider(PanelSide.remote)).refresh();

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (e is RustCloudException &&
              e.code == RustCloudErrorCode.twoFactorRequired) {
            _needs2fa = true;
          }
          _error = e is RustCloudUnavailable
              ? ConnectionDialogExtraStrings(
                  context,
                ).text('rustEngineUnavailable')
              : e is EncryptionFormatException
              ? KeyManagementStrings(context).text(e.code.name, e.arguments)
              : e is NextcloudAuthenticationException
              ? ConnectionStrings.of(context).authenticationFailed
              : localizedKnownProviderError(context, e) ??
                    localizedConnectionFailure(context, e) ??
                    e.toString().replaceAll('Exception:', '').trim();
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
    _sftpKeyPassphraseController.dispose();
    _ftpHostController.dispose();
    _ftpPortController.dispose();
    _ftpUserController.dispose();
    _dropboxAppKeyController.dispose();
    _dropboxAppSecretController.dispose();
    _pcloudAppKeyController.dispose();
    _nextcloudServerUrlController.dispose();
    _nextcloudUsernameController.dispose();
    _gdriveClientIdController.dispose();
    _gdriveClientSecretController.dispose();
    _onedriveClientIdController.dispose();
    _onedriveClientSecretController.dispose();
    _s3EndpointController.dispose();
    _s3RegionController.dispose();
    _s3BucketController.dispose();
    _s3AccessKeyController.dispose();
    _s3SecretKeyController.dispose();
    _s3KmsKeyIdController.dispose();
    _passphraseController.dispose();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Thin proxy widgets — allows showDialog to reference the dedicated dialogs
// without a circular import (they are defined in separate files).
// ---------------------------------------------------------------------------

class _AzureDialogProxy extends StatelessWidget {
  const _AzureDialogProxy();

  @override
  Widget build(BuildContext context) => const AzureConnectionDialog();
}

class _B2DialogProxy extends StatelessWidget {
  const _B2DialogProxy();

  @override
  Widget build(BuildContext context) => const B2ConnectionDialog();
}
