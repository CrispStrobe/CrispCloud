// lib/providers/auth_provider.dart
//
// Manages cloud provider connection: login, logout, provider switching,
// encryption toggle, and auto-login on startup.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../services/azure_blob_adapter.dart';
import '../services/azure_config_service.dart';
import '../services/b2_client_adapter.dart';
import '../services/b2_config_service.dart';
import '../services/hetzner_adapter.dart';
import '../utils/async_lock.dart';
import '../services/cloud_storage_interface.dart';
import '../services/dropbox_client_adapter.dart';
import '../services/dropbox_config_service.dart';
import '../services/encrypted_storage_wrapper.dart';
import '../services/encryption_service.dart';
import '../services/filen_client_adapter.dart';
import '../services/filen_config_service.dart';
import '../services/ftp_client_adapter.dart';
import '../services/ftp_config_service.dart';
import '../services/gdrive_client_adapter.dart';
import '../services/gdrive_config_service.dart';
import '../services/internxt_flutter/secure_config_storage.dart';
import '../services/onedrive_client_adapter.dart';
import '../services/onedrive_config_service.dart';
import '../services/internxt_client_adapter.dart';
import '../services/s3_client_adapter.dart';
import '../services/s3_config_service.dart';
import '../services/secure_storage_service.dart';
import '../services/nextcloud_client_adapter.dart';
import '../services/nextcloud_config_service.dart';
import '../services/pcloud_client_adapter.dart';
import '../services/pcloud_config_service.dart';
import '../services/sftp_client_adapter.dart';
import '../services/sftp_config_service.dart';
import '../services/webdav_client_adapter.dart';
import '../services/webdav_config_service.dart';
import '../services/smb_config_service.dart';
import '../services/smb_client_adapter.dart';
import '../services/log_service.dart';
import 'error_provider.dart';
import 'multi_cloud_provider.dart';
import '../services/auth_sync_notice.dart';

class AuthNotifier extends ChangeNotifier {
  static const _log = Log('AuthNotifier');
  final Ref _ref;

  CloudProvider _currentProvider;
  late CloudStorageClient _cloudClient;
  final String _configPath;
  final SecureStorage _secureStorage;

  bool _isConnected = false;
  String? _userEmail;

  final _switchLock = AsyncLock();
  final _autoLoginLock = AsyncLock();

  AuthNotifier(
    this._ref, {
    required CloudProvider initialProvider,
    required dynamic config,
    required String configPath,
    required SecureStorage secureStorage,
  }) : _currentProvider = initialProvider,
       _configPath = configPath,
       _secureStorage = secureStorage {
    _cloudClient = CloudStorageFactory.create(initialProvider, config: config);
    _attemptAutoLogin();
  }

  // --- Getters ---
  CloudProvider get currentProvider => _currentProvider;
  CloudStorageClient get client => _cloudClient;
  String get providerName => _cloudClient.providerName;
  bool get isConnected => _isConnected;
  String? get userEmail => _userEmail;
  bool get isEncryptionEnabled => _cloudClient is EncryptedStorageWrapper;

  // --- Provider switching ---
  Future<void> switchProvider(
    CloudProvider provider, {
    bool newConnection = false,
  }) async {
    if (_currentProvider == provider && !newConnection) return;
    await _switchLock.synchronized(() async {
      if (_currentProvider == provider && !newConnection) return;
      // Finish any startup restoration before retiring that primary client.
      await _autoLoginLock.synchronized(() async {});
      _log.info('Switching cloud provider to $provider');

      // Construct first: a failed replacement must leave the live session intact.
      final config = _createConfigForProvider(provider);
      final client = CloudStorageFactory.create(provider, config: config);
      if (_isConnected) {
        _ref
            .read(multiCloudProvider)
            .addConnection(
              id: 'retained-${const Uuid().v4()}',
              label: '$providerName · ${_cloudClient.userId ?? "connected"}',
              provider: _currentProvider,
              client: _cloudClient,
            );
      }

      // Persist preference
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cloud_provider', provider.name);

      // The retained wrapper owns its own key copy. Clear only the new primary
      // session's key-management state, without unwrapping the old connection.
      _encryptionKey = null;
      _encryptionSalt = null;
      _isConnected = false;
      _userEmail = null;
      _currentProvider = provider;
      _cloudClient = client;

      notifyListeners();
      if (!newConnection) await _attemptAutoLogin();
    });
  }

  dynamic _createConfigForProvider(CloudProvider provider) {
    switch (provider) {
      case CloudProvider.dropbox:
        return DropboxConfigService(
          configPath: _configPath,
          secureStorage: _secureStorage,
        );
      case CloudProvider.filen:
        return FilenConfigService(
          configPath: _configPath,
          secureStorage: _secureStorage,
        );
      case CloudProvider.ftp:
        return FTPConfigService(
          configPath: _configPath,
          secureStorage: _secureStorage,
        );
      case CloudProvider.gdrive:
        return GDriveConfigService(
          configPath: _configPath,
          secureStorage: _secureStorage,
        );
      case CloudProvider.onedrive:
        return OneDriveConfigService(
          configPath: _configPath,
          secureStorage: _secureStorage,
        );
      case CloudProvider.s3:
        return S3ConfigService(
          configPath: _configPath,
          secureStorage: _secureStorage,
        );
      case CloudProvider.sftp:
        return SFTPConfigService(
          configPath: _configPath,
          secureStorage: _secureStorage,
        );
      case CloudProvider.nextcloud:
        return NextcloudConfigService(
          configPath: _configPath,
          secureStorage: _secureStorage,
        );
      case CloudProvider.pcloud:
        return PCloudConfigService(
          configPath: _configPath,
          secureStorage: _secureStorage,
        );
      case CloudProvider.webdav:
        return WebDavConfigService(
          configPath: _configPath,
          secureStorage: _secureStorage,
        );
      case CloudProvider.smb:
        return SmbConfigService(_secureStorage);
      case CloudProvider.internxt:
        return createSecureInternxtConfig(
          configPath: _configPath,
          secureStorage: _secureStorage,
        );
      case CloudProvider.azure:
        return AzureConfigService(secureStorage: _secureStorage);
      case CloudProvider.b2:
        return B2ConfigService(secureStorage: _secureStorage);
    }
  }

  // --- Login / Logout ---
  Future<void> login(String email, String password, String? tfaCode) async {
    _log.info('login: $email provider=$providerName');
    await _cloudClient.login(email, password, twoFactorCode: tfaCode);

    // Save credentials per provider
    await _saveCredentialsAfterLogin(email);

    _userEmail = email;
    _isConnected = true;
    _ref.read(errorProvider).clearErrors();
    notifyListeners();
  }

  /// Key material never enters the generic password/2FA flow or logs.
  Future<void> loginSftpWithPrivateKey(
    String identity,
    String privateKey,
    String? passphrase,
  ) async {
    final client = _cloudClient;
    if (client is! SFTPClientAdapter) {
      throw StateError('SFTP provider is not selected');
    }
    await client.loginWithPrivateKey(identity, privateKey, passphrase);
    _userEmail = identity;
    _isConnected = true;
    _ref.read(errorProvider).clearErrors();
    notifyListeners();
  }

  Future<void> logout() async {
    _log.info('logout: provider=$providerName');
    try {
      await _cloudClient.logout();
      // The Filen adapter performs and verifies its own credential cleanup.
      if (_currentProvider != CloudProvider.filen) await _clearCredentials();
    } on FilenCredentialDeletionFailure {
      // Filen has already discarded its API key and master keys. Retain this
      // adapter so the same logout operation can retry durable cleanup, while
      // reporting the actual disconnected session state to the rest of the UI.
      _isConnected = false;
      _userEmail = null;
      notifyListeners();
      rethrow;
    }
    _isConnected = false;
    _userEmail = null;
    // Session encryption must not follow a later account/provider login, or
    // leave key-management UI displaying a key for an unwrapped client.
    disableEncryption();
    notifyListeners();
  }

  // --- Encryption ---
  Uint8List? _encryptionKey;
  Uint8List? _encryptionSalt;

  /// The current encryption key (null if encryption is disabled).
  Uint8List? get encryptionKey =>
      _encryptionKey == null ? null : Uint8List.fromList(_encryptionKey!);

  /// The salt used to derive the encryption key.
  Uint8List? get encryptionSalt =>
      _encryptionSalt == null ? null : Uint8List.fromList(_encryptionSalt!);

  void enableEncryption(String passphrase) {
    if (_cloudClient is EncryptedStorageWrapper) return;
    if (passphrase.isEmpty) {
      throw ArgumentError('File encryption requires a nonempty passphrase');
    }
    final salt = EncryptionService.generateSalt();
    final key = EncryptionService.deriveKey(passphrase, salt);
    enableEncryptionWithKey(key, salt);
  }

  /// Enable encryption with a pre-existing key and salt (e.g. from mnemonic recovery).
  void enableEncryptionWithKey(Uint8List key, Uint8List salt) {
    EncryptionService.validateKey(key);
    if (_cloudClient is EncryptedStorageWrapper) {
      if (listEquals(_encryptionKey, key)) return;
      throw const EncryptionFormatException(
        'Disable file encryption before importing a different key',
        EncryptionFormatError.encryptionAlreadyEnabled,
      );
    }
    _encryptionKey = Uint8List.fromList(key);
    _encryptionSalt = Uint8List.fromList(salt);
    _cloudClient = EncryptedStorageWrapper(
      inner: _cloudClient,
      encryptionKey: key,
    );
    notifyListeners();
  }

  void disableEncryption() {
    final hadEncryption =
        isEncryptionEnabled ||
        _encryptionKey != null ||
        _encryptionSalt != null;
    if (_cloudClient is EncryptedStorageWrapper) {
      _cloudClient = (_cloudClient as EncryptedStorageWrapper).inner;
    }
    _encryptionKey = null;
    _encryptionSalt = null;
    if (hadEncryption) notifyListeners();
  }

  // --- Ensure authenticated (used by transfer provider) ---
  Future<void> ensureAuthenticated() async {
    if (_cloudClient is DropboxClientAdapter) {
      final creds = await (_cloudClient as DropboxClientAdapter).config
          .readCredentials();
      if (creds == null) throw Exception('Not authenticated');
    } else if (_cloudClient is InternxtClientAdapter) {
      final creds = await (_cloudClient as InternxtClientAdapter).config
          .readCredentials();
      if (creds == null) throw Exception('Not authenticated');
    } else if (_cloudClient is FilenClientAdapter) {
      final creds = await (_cloudClient as FilenClientAdapter).filenConfig
          .readCredentials();
      if (creds == null) throw Exception('Not authenticated');
    } else if (_cloudClient is FTPClientAdapter) {
      final creds = await (_cloudClient as FTPClientAdapter).config
          .readCredentials();
      if (creds == null) throw Exception('Not authenticated');
    } else if (_cloudClient is GDriveClientAdapter) {
      final creds = await (_cloudClient as GDriveClientAdapter).config
          .readCredentials();
      if (creds == null) throw Exception('Not authenticated');
    } else if (_cloudClient is OneDriveClientAdapter) {
      final creds = await (_cloudClient as OneDriveClientAdapter).config
          .readCredentials();
      if (creds == null) throw Exception('Not authenticated');
    } else if (_cloudClient is S3ClientAdapter) {
      final creds = await (_cloudClient as S3ClientAdapter).config
          .readCredentials();
      if (creds == null) throw Exception('Not authenticated');
    } else if (_cloudClient is SFTPClientAdapter) {
      final creds = await (_cloudClient as SFTPClientAdapter).config
          .readCredentials();
      if (creds == null) throw Exception('Not authenticated');
    } else if (_cloudClient is SmbClientAdapter) {
      if (await (_cloudClient as SmbClientAdapter).config.readCredentials() ==
          null)
        throw StateError('Not authenticated');
    } else if (_cloudClient is WebDavClientAdapter) {
      final creds = await (_cloudClient as WebDavClientAdapter).config
          .readCredentials();
      if (creds == null) throw Exception('Not authenticated');
    } else if (_cloudClient is NextcloudClientAdapter) {
      final creds = await (_cloudClient as NextcloudClientAdapter).config
          .readCredentials();
      if (creds == null) throw Exception('Not authenticated');
    } else if (_cloudClient is PCloudClientAdapter) {
      final creds = await (_cloudClient as PCloudClientAdapter).config
          .readCredentials();
      if (creds == null) throw Exception('Not authenticated');
    }
  }

  // --- Auto-login ---
  Future<void> _attemptAutoLogin() async {
    await _autoLoginLock.synchronized(() async {
      _log.info('Attempting auto-login for ${_cloudClient.providerName}');
      try {
        if (_cloudClient is DropboxClientAdapter) {
          final adapter = _cloudClient as DropboxClientAdapter;
          final restored = await adapter.restoreCredentials();
          if (restored) {
            _userEmail = adapter.userId ?? 'Dropbox';
            _isConnected = true;
            notifyListeners();
          }
        } else if (_cloudClient is InternxtClientAdapter) {
          final adapter = _cloudClient as InternxtClientAdapter;
          final rawCreds = await adapter.config.readCredentials();
          final creds = rawCreds?.cast<String, String>();
          // Rust-format sessions restore only through the Rust engine.
          if (creds == null || !await adapter.restoreSavedSession(creds))
            return;
          _userEmail = creds['email'];
          _isConnected = true;
          notifyListeners();
        } else if (_cloudClient is FilenClientAdapter) {
          final adapter = _cloudClient as FilenClientAdapter;
          final creds = await adapter.filenConfig.readCredentials();
          if (creds == null || creds['email'] == null) return;
          if (await adapter.restoreSavedSession(creds)) {
            _userEmail = creds['email'];
            _isConnected = true;
            notifyListeners();
          }
        } else if (_cloudClient is FTPClientAdapter) {
          final adapter = _cloudClient as FTPClientAdapter;
          final creds = await adapter.config.readCredentials();
          if (creds != null &&
              creds['host'] != null &&
              creds['username'] != null) {
            _userEmail = '${creds['username']}@${creds['host']}';
            _isConnected = true;
            notifyListeners();
          }
        } else if (_cloudClient is SFTPClientAdapter) {
          final adapter = _cloudClient as SFTPClientAdapter;
          final creds = await adapter.config.readCredentials();
          if (creds != null &&
              creds['host'] != null &&
              creds['username'] != null) {
            _userEmail = '${creds['username']}@${creds['host']}';
            _isConnected = true;
            notifyListeners();
          }
        } else if (_cloudClient is GDriveClientAdapter) {
          final adapter = _cloudClient as GDriveClientAdapter;
          final restored = await adapter.restoreCredentials();
          if (restored) {
            _userEmail = adapter.userId ?? 'Google Drive';
            _isConnected = true;
            notifyListeners();
          }
        } else if (_cloudClient is OneDriveClientAdapter) {
          final adapter = _cloudClient as OneDriveClientAdapter;
          final restored = await adapter.restoreCredentials();
          if (restored) {
            _userEmail = adapter.userId ?? 'OneDrive';
            _isConnected = true;
            notifyListeners();
          }
        } else if (_cloudClient is S3ClientAdapter) {
          final adapter = _cloudClient as S3ClientAdapter;
          final restored = await adapter.restoreCredentials();
          if (restored) {
            _userEmail = '${adapter.userId}@${adapter.bucketId}';
            _isConnected = true;
            notifyListeners();
          }
        } else if (_cloudClient is SmbClientAdapter) {
          final adapter = _cloudClient as SmbClientAdapter;
          if (await adapter.restoreCredentials()) {
            _userEmail = '${adapter.userId}@${adapter.bucketId}';
            _isConnected = true;
            notifyListeners();
          }
        } else if (_cloudClient is WebDavClientAdapter) {
          final adapter = _cloudClient as WebDavClientAdapter;
          final creds = await adapter.config.readCredentials();
          if (creds != null &&
              creds['host'] != null &&
              creds['username'] != null) {
            _userEmail = '${creds['username']}@${creds['host']}';
            _isConnected = true;
            notifyListeners();
          }
        } else if (_cloudClient is NextcloudClientAdapter) {
          final adapter = _cloudClient as NextcloudClientAdapter;
          final restored = await adapter.restoreCredentials();
          if (restored) {
            _userEmail = '${adapter.userId}@${adapter.bucketId}';
            _isConnected = true;
            notifyListeners();
          }
        } else if (_cloudClient is PCloudClientAdapter) {
          final adapter = _cloudClient as PCloudClientAdapter;
          final restored = await adapter.restoreCredentials();
          if (restored) {
            _userEmail = adapter.userId ?? 'pCloud';
            _isConnected = true;
            notifyListeners();
          }
        }
      } catch (e) {
        _log.warn('Auto-login exception', e);
        _ref
            .read(errorProvider)
            .addError(
              'Session expired. Please log in again.',
              cause: const AuthSyncNotice(AuthSyncNoticeCode.sessionExpired),
            );
        _isConnected = false;
        notifyListeners();
      }
    });
  }

  Future<void> _saveCredentialsAfterLogin(String email) async {
    if (_cloudClient is InternxtClientAdapter) {
      final adapter = _cloudClient as InternxtClientAdapter;
      final response = adapter.lastLoginResponse;
      if (response != null) {
        await adapter.config.saveCredentials({
          'email': email,
          'token': response['token'] ?? '',
          'mnemonic': response['mnemonic'] ?? '',
          'userId': response['userId'] ?? '',
          'bridgeUser': response['bridgeUser'] ?? '',
          'userIdForAuth': response['userIdForAuth'] ?? '',
          'bucketId': response['bucketId'] ?? '',
          'rootFolderId': response['rootFolderId'] ?? '',
          'newToken': response['newToken'] ?? '',
        });
      }
    }
    // Other providers save credentials internally during login
  }

  Future<void> _clearCredentials() async {
    if (_cloudClient is DropboxClientAdapter) {
      await (_cloudClient as DropboxClientAdapter).config.clearCredentials();
    } else if (_cloudClient is InternxtClientAdapter) {
      await (_cloudClient as InternxtClientAdapter).config.clearCredentials();
    } else if (_cloudClient is FilenClientAdapter) {
      await (_cloudClient as FilenClientAdapter).filenConfig.clearCredentials();
    } else if (_cloudClient is FTPClientAdapter) {
      await (_cloudClient as FTPClientAdapter).config.clearCredentials();
    } else if (_cloudClient is GDriveClientAdapter) {
      await (_cloudClient as GDriveClientAdapter).config.clearCredentials();
    } else if (_cloudClient is OneDriveClientAdapter) {
      await (_cloudClient as OneDriveClientAdapter).config.clearCredentials();
    } else if (_cloudClient is S3ClientAdapter) {
      await (_cloudClient as S3ClientAdapter).config.clearCredentials();
    } else if (_cloudClient is SFTPClientAdapter) {
      await (_cloudClient as SFTPClientAdapter).config.clearCredentials();
    } else if (_cloudClient is SmbClientAdapter) {
      await (_cloudClient as SmbClientAdapter).config.clearCredentials();
    } else if (_cloudClient is WebDavClientAdapter) {
      await (_cloudClient as WebDavClientAdapter).config.clearCredentials();
    } else if (_cloudClient is NextcloudClientAdapter) {
      await (_cloudClient as NextcloudClientAdapter).config.clearCredentials();
    } else if (_cloudClient is PCloudClientAdapter) {
      await (_cloudClient as PCloudClientAdapter).config.clearCredentials();
    } else if (_cloudClient is AzureBlobAdapter) {
      await (_cloudClient as AzureBlobAdapter).config.clearCredentials();
    } else if (_cloudClient is B2ClientAdapter) {
      await (_cloudClient as B2ClientAdapter).config.clearCredentials();
    } else if (_cloudClient is HetznerStorageBoxAdapter) {
      await (_cloudClient as HetznerStorageBoxAdapter).config
          .clearCredentials();
    }
  }
}

final authProvider = ChangeNotifierProvider<AuthNotifier>((ref) {
  throw UnimplementedError(
    'authProvider must be overridden in ProviderScope — '
    'it requires startup config from main()',
  );
});
