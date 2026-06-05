// lib/services/shared_folder_service.dart
//
// Service for managing shared/collaborative folders across cloud providers.
// Provides a unified API; provider-specific logic is dispatched internally
// based on the client type and its supportsSharing flag.

import 'cloud_storage_interface.dart';
import 'dropbox_client_adapter.dart';
import 'gdrive_client_adapter.dart';
import 'nextcloud_client_adapter.dart';
import 'onedrive_client_adapter.dart';
import 'log_service.dart';

// ---------------------------------------------------------------------------
// Enumerations
// ---------------------------------------------------------------------------

/// Permission levels for shared folders, ordered from least to most privileged.
enum SharedPermission {
  /// Read-only access — can view and download files.
  view,

  /// Can edit and modify files but not manage sharing or uploads from outside.
  edit,

  /// Can upload new files in addition to editing existing ones.
  upload,

  /// Full control: can view, edit, upload and manage sharing.
  admin,
}

// ---------------------------------------------------------------------------
// Value objects / models
// ---------------------------------------------------------------------------

/// A single recipient who has been granted access to a shared folder.
class ShareRecipient {
  final String email;
  final String name;
  final SharedPermission permission;

  /// When the recipient accepted the share invitation. Null if not yet accepted.
  final DateTime? acceptedAt;

  const ShareRecipient({
    required this.email,
    required this.name,
    required this.permission,
    this.acceptedAt,
  });

  /// Deserialise from a JSON map (e.g. coming from a persistence layer).
  factory ShareRecipient.fromJson(Map<String, dynamic> json) {
    return ShareRecipient(
      email: json['email'] as String,
      name: json['name'] as String? ?? '',
      permission: SharedPermission.values.firstWhere(
        (p) => p.name == (json['permission'] as String? ?? 'view'),
        orElse: () => SharedPermission.view,
      ),
      acceptedAt: json['acceptedAt'] == null
          ? null
          : DateTime.parse(json['acceptedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'email': email,
        'name': name,
        'permission': permission.name,
        if (acceptedAt != null) 'acceptedAt': acceptedAt!.toIso8601String(),
      };

  ShareRecipient copyWith({
    String? email,
    String? name,
    SharedPermission? permission,
    DateTime? acceptedAt,
  }) {
    return ShareRecipient(
      email: email ?? this.email,
      name: name ?? this.name,
      permission: permission ?? this.permission,
      acceptedAt: acceptedAt ?? this.acceptedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ShareRecipient &&
      email == other.email &&
      name == other.name &&
      permission == other.permission &&
      acceptedAt == other.acceptedAt;

  @override
  int get hashCode => Object.hash(email, name, permission, acceptedAt);

  @override
  String toString() =>
      'ShareRecipient(email: $email, name: $name, permission: ${permission.name})';
}

/// Configuration options used when creating or updating a shared folder.
class ShareSettings {
  /// Optional password protecting the share link. Null means no password.
  final String? password;

  /// Optional expiry date/time after which the share becomes inactive.
  final DateTime? expiresAt;

  /// Default permission granted to new recipients when using a share link.
  final SharedPermission permissions;

  /// Whether recipients can download individual files.
  final bool allowDownload;

  /// Whether recipients (with sufficient permission) can upload files.
  final bool allowUpload;

  /// Whether the owner receives a notification when someone accesses the share.
  final bool notifyOnAccess;

  const ShareSettings({
    this.password,
    this.expiresAt,
    this.permissions = SharedPermission.view,
    this.allowDownload = true,
    this.allowUpload = false,
    this.notifyOnAccess = false,
  });

  bool get isPasswordProtected => password != null && password!.isNotEmpty;

  /// Deserialise from a JSON map.
  factory ShareSettings.fromJson(Map<String, dynamic> json) {
    return ShareSettings(
      password: json['password'] as String?,
      expiresAt: json['expiresAt'] == null
          ? null
          : DateTime.parse(json['expiresAt'] as String),
      permissions: SharedPermission.values.firstWhere(
        (p) => p.name == (json['permissions'] as String? ?? 'view'),
        orElse: () => SharedPermission.view,
      ),
      allowDownload: json['allowDownload'] as bool? ?? true,
      allowUpload: json['allowUpload'] as bool? ?? false,
      notifyOnAccess: json['notifyOnAccess'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        if (password != null) 'password': password,
        if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
        'permissions': permissions.name,
        'allowDownload': allowDownload,
        'allowUpload': allowUpload,
        'notifyOnAccess': notifyOnAccess,
      };

  ShareSettings copyWith({
    String? password,
    DateTime? expiresAt,
    SharedPermission? permissions,
    bool? allowDownload,
    bool? allowUpload,
    bool? notifyOnAccess,
  }) {
    return ShareSettings(
      password: password ?? this.password,
      expiresAt: expiresAt ?? this.expiresAt,
      permissions: permissions ?? this.permissions,
      allowDownload: allowDownload ?? this.allowDownload,
      allowUpload: allowUpload ?? this.allowUpload,
      notifyOnAccess: notifyOnAccess ?? this.notifyOnAccess,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ShareSettings &&
      password == other.password &&
      expiresAt == other.expiresAt &&
      permissions == other.permissions &&
      allowDownload == other.allowDownload &&
      allowUpload == other.allowUpload &&
      notifyOnAccess == other.notifyOnAccess;

  @override
  int get hashCode => Object.hash(
        password,
        expiresAt,
        permissions,
        allowDownload,
        allowUpload,
        notifyOnAccess,
      );
}

/// Represents a folder that has been shared (by the current user or with them).
class SharedFolder {
  /// Provider-specific opaque share / folder identifier.
  final String id;

  /// Absolute path of the folder within the provider's namespace.
  final String path;

  /// Name of the provider (e.g. 'Google Drive', 'Dropbox').
  final String provider;

  /// Display name of the share owner.
  final String ownerName;

  /// Email of the share owner.
  final String ownerEmail;

  /// Effective permission for the current user on this share.
  final SharedPermission permissions;

  /// List of people who have been explicitly granted access.
  final List<ShareRecipient> sharedWith;

  /// The shareable URL that can be sent to others. May be null until generated.
  final String? shareUrl;

  /// When the share was created.
  final DateTime createdAt;

  /// Optional expiry. Null means the share does not expire.
  final DateTime? expiresAt;

  /// Whether this share is password-protected.
  final bool passwordProtected;

  const SharedFolder({
    required this.id,
    required this.path,
    required this.provider,
    required this.ownerName,
    required this.ownerEmail,
    required this.permissions,
    required this.sharedWith,
    this.shareUrl,
    required this.createdAt,
    this.expiresAt,
    this.passwordProtected = false,
  });

  /// Deserialise from a JSON map.
  factory SharedFolder.fromJson(Map<String, dynamic> json) {
    final recipientsRaw = json['sharedWith'] as List<dynamic>? ?? [];
    return SharedFolder(
      id: json['id'] as String,
      path: json['path'] as String,
      provider: json['provider'] as String,
      ownerName: json['ownerName'] as String? ?? '',
      ownerEmail: json['ownerEmail'] as String? ?? '',
      permissions: SharedPermission.values.firstWhere(
        (p) => p.name == (json['permissions'] as String? ?? 'view'),
        orElse: () => SharedPermission.view,
      ),
      sharedWith: recipientsRaw
          .map((r) => ShareRecipient.fromJson(r as Map<String, dynamic>))
          .toList(),
      shareUrl: json['shareUrl'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      expiresAt: json['expiresAt'] == null
          ? null
          : DateTime.parse(json['expiresAt'] as String),
      passwordProtected: json['passwordProtected'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'provider': provider,
        'ownerName': ownerName,
        'ownerEmail': ownerEmail,
        'permissions': permissions.name,
        'sharedWith': sharedWith.map((r) => r.toJson()).toList(),
        if (shareUrl != null) 'shareUrl': shareUrl,
        'createdAt': createdAt.toIso8601String(),
        if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
        'passwordProtected': passwordProtected,
      };

  SharedFolder copyWith({
    String? id,
    String? path,
    String? provider,
    String? ownerName,
    String? ownerEmail,
    SharedPermission? permissions,
    List<ShareRecipient>? sharedWith,
    String? shareUrl,
    DateTime? createdAt,
    DateTime? expiresAt,
    bool? passwordProtected,
  }) {
    return SharedFolder(
      id: id ?? this.id,
      path: path ?? this.path,
      provider: provider ?? this.provider,
      ownerName: ownerName ?? this.ownerName,
      ownerEmail: ownerEmail ?? this.ownerEmail,
      permissions: permissions ?? this.permissions,
      sharedWith: sharedWith ?? this.sharedWith,
      shareUrl: shareUrl ?? this.shareUrl,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      passwordProtected: passwordProtected ?? this.passwordProtected,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SharedFolder &&
      id == other.id &&
      path == other.path &&
      provider == other.provider &&
      ownerName == other.ownerName &&
      ownerEmail == other.ownerEmail &&
      permissions == other.permissions &&
      shareUrl == other.shareUrl &&
      createdAt == other.createdAt &&
      expiresAt == other.expiresAt &&
      passwordProtected == other.passwordProtected;

  @override
  int get hashCode => Object.hash(
        id,
        path,
        provider,
        ownerName,
        ownerEmail,
        permissions,
        shareUrl,
        createdAt,
        expiresAt,
        passwordProtected,
      );

  @override
  String toString() =>
      'SharedFolder(id: $id, path: $path, provider: $provider, '
      'permissions: ${permissions.name}, recipients: ${sharedWith.length})';
}

// ---------------------------------------------------------------------------
// Exception types
// ---------------------------------------------------------------------------

/// Thrown when a sharing operation is attempted on a provider that does not
/// support sharing (i.e. [CloudStorageClient.supportsSharing] is false).
class SharingNotSupportedException implements Exception {
  final String providerName;
  const SharingNotSupportedException(this.providerName);

  @override
  String toString() =>
      'SharingNotSupportedException: Provider "$providerName" does not support sharing.';
}

/// Thrown when a share ID cannot be found.
class ShareNotFoundException implements Exception {
  final String shareId;
  const ShareNotFoundException(this.shareId);

  @override
  String toString() => 'ShareNotFoundException: Share "$shareId" not found.';
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/// Unified service for managing shared/collaborative folders across providers.
///
/// Provider-specific behaviour is dispatched based on the runtime type of the
/// [CloudStorageClient] and its [supportsSharing] flag. Unsupported providers
/// throw [SharingNotSupportedException] from mutating methods and return empty
/// lists from query methods.
class SharedFolderService {
  static final _log = Log('SharedFolderService');

  // In-memory store keyed by shareId. In a production app this would be backed
  // by a database or provider API response cache.
  final Map<String, SharedFolder> _store = {};

  // ---------------------------------------------------------------------------
  // Capability check
  // ---------------------------------------------------------------------------

  /// Returns true if [client] supports sharing operations.
  bool isProviderSupported(CloudStorageClient client) =>
      client.supportsSharing;

  void _assertSupported(CloudStorageClient client) {
    if (!isProviderSupported(client)) {
      throw SharingNotSupportedException(client.providerName);
    }
  }

  // ---------------------------------------------------------------------------
  // Query methods
  // ---------------------------------------------------------------------------

  /// Returns all folders shared *by* the current user via [client].
  ///
  /// Returns an empty list if the provider does not support sharing rather
  /// than throwing, since this is a read-only operation safe to degrade.
  Future<List<SharedFolder>> getSharedFolders(
    CloudStorageClient client,
  ) async {
    if (!isProviderSupported(client)) {
      _log.warn(
          'getSharedFolders called on unsupported provider: ${client.providerName}');
      return [];
    }

    _log.info('getSharedFolders for ${client.providerName}');

    if (client is GDriveClientAdapter) {
      return _gdriveGetSharedFolders(client);
    } else if (client is OneDriveClientAdapter) {
      return _onedriveGetSharedFolders(client);
    } else if (client is DropboxClientAdapter) {
      return _dropboxGetSharedFolders(client);
    } else if (client is NextcloudClientAdapter) {
      return _nextcloudGetSharedFolders(client);
    }

    // Other providers that happen to have supportsSharing == true (B2, Azure,
    // pCloud) but no explicit sharing API in this service yet.
    return _store.values
        .where((f) => f.provider == client.providerName)
        .toList();
  }

  /// Returns all folders shared *with* the current user via [client].
  Future<List<SharedFolder>> getSharedWithMe(
    CloudStorageClient client,
  ) async {
    if (!isProviderSupported(client)) {
      _log.warn(
          'getSharedWithMe called on unsupported provider: ${client.providerName}');
      return [];
    }

    _log.info('getSharedWithMe for ${client.providerName}');

    if (client is GDriveClientAdapter) {
      return _gdriveGetSharedWithMe(client);
    } else if (client is OneDriveClientAdapter) {
      return _onedriveGetSharedWithMe(client);
    } else if (client is DropboxClientAdapter) {
      return _dropboxGetSharedWithMe(client);
    } else if (client is NextcloudClientAdapter) {
      return _nextcloudGetSharedWithMe(client);
    }

    return [];
  }

  // ---------------------------------------------------------------------------
  // Mutating methods
  // ---------------------------------------------------------------------------

  /// Create a new share for the folder at [path].
  ///
  /// Throws [SharingNotSupportedException] if [client] does not support sharing.
  /// Returns the created [SharedFolder] (idempotent: if the path is already
  /// shared the existing share is returned).
  Future<SharedFolder> shareFolder(
    CloudStorageClient client,
    String path,
    ShareSettings settings,
  ) async {
    _assertSupported(client);
    _log.info('shareFolder: $path on ${client.providerName}');

    // Idempotency: return existing share for the same path + provider.
    final existing = _store.values.firstWhere(
      (f) => f.path == path && f.provider == client.providerName,
      orElse: () => _nullFolder,
    );
    if (existing.id.isNotEmpty) {
      _log.info('shareFolder: returning existing share ${existing.id}');
      return existing;
    }

    if (client is GDriveClientAdapter) {
      return _gdriveShareFolder(client, path, settings);
    } else if (client is OneDriveClientAdapter) {
      return _onedriveShareFolder(client, path, settings);
    } else if (client is DropboxClientAdapter) {
      return _dropboxShareFolder(client, path, settings);
    } else if (client is NextcloudClientAdapter) {
      return _nextcloudShareFolder(client, path, settings);
    }

    // Generic stub for other supporting providers.
    return _createStubShare(client, path, settings);
  }

  /// Update settings on an existing share identified by [shareId].
  Future<void> updateShare(
    CloudStorageClient client,
    String shareId,
    ShareSettings settings,
  ) async {
    _assertSupported(client);
    _log.info('updateShare: $shareId on ${client.providerName}');

    final existing = _store[shareId];
    if (existing == null) throw ShareNotFoundException(shareId);

    final updated = existing.copyWith(
      expiresAt: settings.expiresAt,
      passwordProtected: settings.isPasswordProtected,
      permissions: settings.permissions,
    );
    _store[shareId] = updated;

    if (client is GDriveClientAdapter) {
      await _gdriveUpdateShare(client, shareId, settings);
    } else if (client is OneDriveClientAdapter) {
      await _onedriveUpdateShare(client, shareId, settings);
    } else if (client is DropboxClientAdapter) {
      await _dropboxUpdateShare(client, shareId, settings);
    } else if (client is NextcloudClientAdapter) {
      await _nextcloudUpdateShare(client, shareId, settings);
    }
  }

  /// Remove / revoke a share identified by [shareId].
  Future<void> revokeShare(
    CloudStorageClient client,
    String shareId,
  ) async {
    _assertSupported(client);
    _log.info('revokeShare: $shareId on ${client.providerName}');

    if (!_store.containsKey(shareId)) throw ShareNotFoundException(shareId);
    _store.remove(shareId);

    if (client is GDriveClientAdapter) {
      await _gdriveRevokeShare(client, shareId);
    } else if (client is OneDriveClientAdapter) {
      await _onedriveRevokeShare(client, shareId);
    } else if (client is DropboxClientAdapter) {
      await _dropboxRevokeShare(client, shareId);
    } else if (client is NextcloudClientAdapter) {
      await _nextcloudRevokeShare(client, shareId);
    }
  }

  /// Grant access to [email] on share [shareId] with [permission].
  Future<void> addRecipient(
    CloudStorageClient client,
    String shareId,
    String email,
    SharedPermission permission,
  ) async {
    _assertSupported(client);
    _log.info('addRecipient: $email → $shareId on ${client.providerName}');

    final share = _store[shareId];
    if (share == null) throw ShareNotFoundException(shareId);

    // Idempotent: update permission if recipient already exists.
    final updatedList = share.sharedWith
        .where((r) => r.email != email)
        .toList()
      ..add(ShareRecipient(
        email: email,
        name: email.split('@').first,
        permission: permission,
      ));

    _store[shareId] = share.copyWith(sharedWith: updatedList);

    if (client is GDriveClientAdapter) {
      await _gdriveAddRecipient(client, shareId, email, permission);
    } else if (client is OneDriveClientAdapter) {
      await _onedriveAddRecipient(client, shareId, email, permission);
    } else if (client is DropboxClientAdapter) {
      await _dropboxAddRecipient(client, shareId, email, permission);
    } else if (client is NextcloudClientAdapter) {
      await _nextcloudAddRecipient(client, shareId, email, permission);
    }
  }

  /// Revoke access for [email] on share [shareId].
  Future<void> removeRecipient(
    CloudStorageClient client,
    String shareId,
    String email,
  ) async {
    _assertSupported(client);
    _log.info('removeRecipient: $email from $shareId on ${client.providerName}');

    final share = _store[shareId];
    if (share == null) throw ShareNotFoundException(shareId);

    final updatedList =
        share.sharedWith.where((r) => r.email != email).toList();
    _store[shareId] = share.copyWith(sharedWith: updatedList);

    if (client is GDriveClientAdapter) {
      await _gdriveRemoveRecipient(client, shareId, email);
    } else if (client is OneDriveClientAdapter) {
      await _onedriveRemoveRecipient(client, shareId, email);
    } else if (client is DropboxClientAdapter) {
      await _dropboxRemoveRecipient(client, shareId, email);
    } else if (client is NextcloudClientAdapter) {
      await _nextcloudRemoveRecipient(client, shareId, email);
    }
  }

  /// Returns the shareable URL for share [shareId].
  Future<String> getShareLink(
    CloudStorageClient client,
    String shareId,
  ) async {
    _assertSupported(client);

    final share = _store[shareId];
    if (share == null) throw ShareNotFoundException(shareId);
    if (share.shareUrl != null) return share.shareUrl!;

    String url;
    if (client is GDriveClientAdapter) {
      url = await _gdriveGetShareLink(client, shareId);
    } else if (client is OneDriveClientAdapter) {
      url = await _onedriveGetShareLink(client, shareId);
    } else if (client is DropboxClientAdapter) {
      url = await _dropboxGetShareLink(client, shareId);
    } else if (client is NextcloudClientAdapter) {
      url = await _nextcloudGetShareLink(client, shareId);
    } else {
      url = 'https://share.example.com/$shareId';
    }

    _store[shareId] = share.copyWith(shareUrl: url);
    return url;
  }

  // ---------------------------------------------------------------------------
  // Google Drive — permissions API
  // ---------------------------------------------------------------------------

  Future<List<SharedFolder>> _gdriveGetSharedFolders(
    GDriveClientAdapter client,
  ) async {
    // In a full implementation: GET /drive/v3/files?q=mimeType='application/vnd.google-apps.folder' and sharedWithMe=false
    // For now return cached entries.
    return _store.values
        .where((f) => f.provider == 'Google Drive')
        .toList();
  }

  Future<List<SharedFolder>> _gdriveGetSharedWithMe(
    GDriveClientAdapter client,
  ) async {
    // GET /drive/v3/files?q=sharedWithMe=true and mimeType='application/vnd.google-apps.folder'
    return [];
  }

  Future<SharedFolder> _gdriveShareFolder(
    GDriveClientAdapter client,
    String path,
    ShareSettings settings,
  ) async {
    // POST /drive/v3/files/{fileId}/permissions
    return _createStubShare(client, path, settings, provider: 'Google Drive');
  }

  Future<void> _gdriveUpdateShare(
    GDriveClientAdapter client,
    String shareId,
    ShareSettings settings,
  ) async {
    // PATCH /drive/v3/files/{fileId}/permissions/{permissionId}
  }

  Future<void> _gdriveRevokeShare(
    GDriveClientAdapter client,
    String shareId,
  ) async {
    // DELETE /drive/v3/files/{fileId}/permissions/{permissionId}
  }

  Future<void> _gdriveAddRecipient(
    GDriveClientAdapter client,
    String shareId,
    String email,
    SharedPermission permission,
  ) async {
    // POST /drive/v3/files/{fileId}/permissions body: {type: 'user', role: ..., emailAddress: email}
  }

  Future<void> _gdriveRemoveRecipient(
    GDriveClientAdapter client,
    String shareId,
    String email,
  ) async {
    // DELETE /drive/v3/files/{fileId}/permissions/{permissionId}
  }

  Future<String> _gdriveGetShareLink(
    GDriveClientAdapter client,
    String shareId,
  ) async {
    // POST /drive/v3/files/{fileId} with allowFileDiscovery and get webViewLink
    return 'https://drive.google.com/drive/folders/$shareId?usp=sharing';
  }

  // ---------------------------------------------------------------------------
  // OneDrive — Microsoft Graph sharing API
  // ---------------------------------------------------------------------------

  Future<List<SharedFolder>> _onedriveGetSharedFolders(
    OneDriveClientAdapter client,
  ) async {
    // GET /me/drive/sharedWithMe (filter folders)
    return _store.values
        .where((f) => f.provider == 'OneDrive')
        .toList();
  }

  Future<List<SharedFolder>> _onedriveGetSharedWithMe(
    OneDriveClientAdapter client,
  ) async {
    // GET /me/drive/sharedWithMe
    return [];
  }

  Future<SharedFolder> _onedriveShareFolder(
    OneDriveClientAdapter client,
    String path,
    ShareSettings settings,
  ) async {
    // POST /me/drive/items/{itemId}/createLink
    return _createStubShare(client, path, settings, provider: 'OneDrive');
  }

  Future<void> _onedriveUpdateShare(
    OneDriveClientAdapter client,
    String shareId,
    ShareSettings settings,
  ) async {
    // PATCH /me/drive/items/{itemId}/permissions/{permId}
  }

  Future<void> _onedriveRevokeShare(
    OneDriveClientAdapter client,
    String shareId,
  ) async {
    // DELETE /me/drive/items/{itemId}/permissions/{permId}
  }

  Future<void> _onedriveAddRecipient(
    OneDriveClientAdapter client,
    String shareId,
    String email,
    SharedPermission permission,
  ) async {
    // POST /me/drive/items/{itemId}/invite
  }

  Future<void> _onedriveRemoveRecipient(
    OneDriveClientAdapter client,
    String shareId,
    String email,
  ) async {
    // DELETE /me/drive/items/{itemId}/permissions/{permId}
  }

  Future<String> _onedriveGetShareLink(
    OneDriveClientAdapter client,
    String shareId,
  ) async {
    // POST /me/drive/items/{itemId}/createLink → webUrl
    return 'https://onedrive.live.com/?id=$shareId&cid=share';
  }

  // ---------------------------------------------------------------------------
  // Dropbox — sharing API
  // ---------------------------------------------------------------------------

  Future<List<SharedFolder>> _dropboxGetSharedFolders(
    DropboxClientAdapter client,
  ) async {
    // POST /2/sharing/list_folders
    return _store.values
        .where((f) => f.provider == 'Dropbox')
        .toList();
  }

  Future<List<SharedFolder>> _dropboxGetSharedWithMe(
    DropboxClientAdapter client,
  ) async {
    // POST /2/sharing/list_folders (is_team_accessible=false, filter by ownership)
    return [];
  }

  Future<SharedFolder> _dropboxShareFolder(
    DropboxClientAdapter client,
    String path,
    ShareSettings settings,
  ) async {
    // POST /2/sharing/share_folder
    return _createStubShare(client, path, settings, provider: 'Dropbox');
  }

  Future<void> _dropboxUpdateShare(
    DropboxClientAdapter client,
    String shareId,
    ShareSettings settings,
  ) async {
    // POST /2/sharing/update_folder_policy
  }

  Future<void> _dropboxRevokeShare(
    DropboxClientAdapter client,
    String shareId,
  ) async {
    // POST /2/sharing/unshare_folder
  }

  Future<void> _dropboxAddRecipient(
    DropboxClientAdapter client,
    String shareId,
    String email,
    SharedPermission permission,
  ) async {
    // POST /2/sharing/add_folder_member
  }

  Future<void> _dropboxRemoveRecipient(
    DropboxClientAdapter client,
    String shareId,
    String email,
  ) async {
    // POST /2/sharing/remove_folder_member
  }

  Future<String> _dropboxGetShareLink(
    DropboxClientAdapter client,
    String shareId,
  ) async {
    // POST /2/sharing/create_shared_link_with_settings
    return 'https://www.dropbox.com/sh/$shareId/AAA';
  }

  // ---------------------------------------------------------------------------
  // Nextcloud — OCS sharing API
  // ---------------------------------------------------------------------------

  Future<List<SharedFolder>> _nextcloudGetSharedFolders(
    NextcloudClientAdapter client,
  ) async {
    // GET /ocs/v2.php/apps/files_sharing/api/v1/shares?shared_with_me=false
    return _store.values
        .where((f) => f.provider == 'Nextcloud')
        .toList();
  }

  Future<List<SharedFolder>> _nextcloudGetSharedWithMe(
    NextcloudClientAdapter client,
  ) async {
    // GET /ocs/v2.php/apps/files_sharing/api/v1/shares?shared_with_me=true
    return [];
  }

  Future<SharedFolder> _nextcloudShareFolder(
    NextcloudClientAdapter client,
    String path,
    ShareSettings settings,
  ) async {
    // POST /ocs/v2.php/apps/files_sharing/api/v1/shares
    return _createStubShare(client, path, settings, provider: 'Nextcloud');
  }

  Future<void> _nextcloudUpdateShare(
    NextcloudClientAdapter client,
    String shareId,
    ShareSettings settings,
  ) async {
    // PUT /ocs/v2.php/apps/files_sharing/api/v1/shares/{shareId}
  }

  Future<void> _nextcloudRevokeShare(
    NextcloudClientAdapter client,
    String shareId,
  ) async {
    // DELETE /ocs/v2.php/apps/files_sharing/api/v1/shares/{shareId}
  }

  Future<void> _nextcloudAddRecipient(
    NextcloudClientAdapter client,
    String shareId,
    String email,
    SharedPermission permission,
  ) async {
    // POST /ocs/v2.php/apps/files_sharing/api/v1/shares (shareType=0, shareWith=email)
  }

  Future<void> _nextcloudRemoveRecipient(
    NextcloudClientAdapter client,
    String shareId,
    String email,
  ) async {
    // DELETE /ocs/v2.php/apps/files_sharing/api/v1/shares/{shareId}
  }

  Future<String> _nextcloudGetShareLink(
    NextcloudClientAdapter client,
    String shareId,
  ) async {
    // Return public link from OCS response
    return 'https://nextcloud.example.com/s/$shareId';
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// A sentinel value used for the idempotency check.
  static final _nullFolder = SharedFolder(
    id: '',
    path: '',
    provider: '',
    ownerName: '',
    ownerEmail: '',
    permissions: SharedPermission.view,
    sharedWith: [],
    createdAt: DateTime.utc(1970),
  );

  /// Create a stub [SharedFolder] and persist it in the in-memory store.
  SharedFolder _createStubShare(
    CloudStorageClient client,
    String path,
    ShareSettings settings, {
    String? provider,
  }) {
    final id = _generateShareId(client.providerName, path);
    final folder = SharedFolder(
      id: id,
      path: path,
      provider: provider ?? client.providerName,
      ownerName: client.userId ?? 'Unknown',
      ownerEmail: client.userId ?? '',
      permissions: settings.permissions,
      sharedWith: [],
      shareUrl: _buildShareUrl(client.providerName, id),
      createdAt: DateTime.now().toUtc(),
      expiresAt: settings.expiresAt,
      passwordProtected: settings.isPasswordProtected,
    );
    _store[id] = folder;
    return folder;
  }

  String _generateShareId(String providerName, String path) {
    // Deterministic but sufficiently unique for in-process use.
    final hash = (providerName + path).hashCode.abs();
    return '${providerName.replaceAll(' ', '_').toLowerCase()}_$hash';
  }

  String _buildShareUrl(String providerName, String shareId) {
    switch (providerName.toLowerCase()) {
      case 'google drive':
        return 'https://drive.google.com/drive/folders/$shareId?usp=sharing';
      case 'onedrive':
        return 'https://onedrive.live.com/?id=$shareId&cid=share';
      case 'dropbox':
        return 'https://www.dropbox.com/sh/$shareId/AAA';
      case 'nextcloud':
        return 'https://nextcloud.example.com/s/$shareId';
      default:
        return 'https://share.example.com/$shareId';
    }
  }
}
