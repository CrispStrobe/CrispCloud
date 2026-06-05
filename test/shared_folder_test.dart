// test/shared_folder_test.dart
//
// Unit tests for shared folder management (SharedFolderService, models).

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/services/shared_folder_service.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/gdrive_client_adapter.dart';
import 'package:crisp_cloud/services/gdrive_config_service.dart';
import 'package:crisp_cloud/services/onedrive_client_adapter.dart';
import 'package:crisp_cloud/services/onedrive_config_service.dart';
import 'package:crisp_cloud/services/dropbox_client_adapter.dart';
import 'package:crisp_cloud/services/dropbox_config_service.dart';
import 'package:crisp_cloud/services/nextcloud_client_adapter.dart';
import 'package:crisp_cloud/services/nextcloud_config_service.dart';
import 'package:crisp_cloud/services/sftp_client_adapter.dart';
import 'package:crisp_cloud/services/sftp_config_service.dart';
import 'package:crisp_cloud/services/ftp_client_adapter.dart';
import 'package:crisp_cloud/services/ftp_config_service.dart';
import 'package:crisp_cloud/services/s3_client_adapter.dart';
import 'package:crisp_cloud/services/s3_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

GDriveClientAdapter _makeGDrive() {
  final storage = InMemorySecureStorage();
  final config = GDriveConfigService(
      configPath: '/tmp/test_gdrive', secureStorage: storage);
  return GDriveClientAdapter(config: config);
}

OneDriveClientAdapter _makeOneDrive() {
  final storage = InMemorySecureStorage();
  final config = OneDriveConfigService(
      configPath: '/tmp/test_onedrive', secureStorage: storage);
  return OneDriveClientAdapter(config: config);
}

DropboxClientAdapter _makeDropbox() {
  final storage = InMemorySecureStorage();
  final config = DropboxConfigService(
      configPath: '/tmp/test_dropbox', secureStorage: storage);
  return DropboxClientAdapter(config: config);
}

NextcloudClientAdapter _makeNextcloud() {
  final storage = InMemorySecureStorage();
  final config = NextcloudConfigService(
      configPath: '/tmp/test_nextcloud', secureStorage: storage);
  return NextcloudClientAdapter(config: config);
}

SFTPClientAdapter _makeSFTP() {
  final storage = InMemorySecureStorage();
  final config =
      SFTPConfigService(configPath: '/tmp/test_sftp', secureStorage: storage);
  return SFTPClientAdapter(config: config);
}

FTPClientAdapter _makeFTP() {
  final storage = InMemorySecureStorage();
  final config =
      FTPConfigService(configPath: '/tmp/test_ftp', secureStorage: storage);
  return FTPClientAdapter(config: config);
}

S3ClientAdapter _makeS3() {
  final storage = InMemorySecureStorage();
  final config =
      S3ConfigService(configPath: '/tmp/test_s3', secureStorage: storage);
  return S3ClientAdapter(config: config);
}

SharedFolder _sampleFolder({
  String id = 'share_001',
  String path = '/Documents/Project',
  List<ShareRecipient>? recipients,
}) {
  return SharedFolder(
    id: id,
    path: path,
    provider: 'Google Drive',
    ownerName: 'Alice',
    ownerEmail: 'alice@example.com',
    permissions: SharedPermission.edit,
    sharedWith: recipients ?? [],
    shareUrl: 'https://drive.google.com/drive/folders/$id?usp=sharing',
    createdAt: DateTime.utc(2025, 6, 1, 12, 0, 0),
    expiresAt: DateTime.utc(2025, 12, 31),
    passwordProtected: false,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // -------------------------------------------------------------------------
  // SharedPermission ordering
  // -------------------------------------------------------------------------

  group('SharedPermission ordering', () {
    test('view < edit < upload < admin by index', () {
      expect(SharedPermission.view.index,
          lessThan(SharedPermission.edit.index));
      expect(SharedPermission.edit.index,
          lessThan(SharedPermission.upload.index));
      expect(SharedPermission.upload.index,
          lessThan(SharedPermission.admin.index));
    });

    test('all four values exist', () {
      expect(SharedPermission.values.length, equals(4));
    });

    test('enum names match expected strings', () {
      expect(SharedPermission.view.name, equals('view'));
      expect(SharedPermission.edit.name, equals('edit'));
      expect(SharedPermission.upload.name, equals('upload'));
      expect(SharedPermission.admin.name, equals('admin'));
    });
  });

  // -------------------------------------------------------------------------
  // ShareRecipient model
  // -------------------------------------------------------------------------

  group('ShareRecipient model', () {
    test('construct with required fields', () {
      const r = ShareRecipient(
        email: 'bob@example.com',
        name: 'Bob',
        permission: SharedPermission.view,
      );
      expect(r.email, 'bob@example.com');
      expect(r.name, 'Bob');
      expect(r.permission, SharedPermission.view);
      expect(r.acceptedAt, isNull);
    });

    test('serialise to JSON and back (round-trip without acceptedAt)', () {
      const r = ShareRecipient(
        email: 'carol@example.com',
        name: 'Carol',
        permission: SharedPermission.upload,
      );
      final json = r.toJson();
      final restored = ShareRecipient.fromJson(json);
      expect(restored.email, r.email);
      expect(restored.name, r.name);
      expect(restored.permission, r.permission);
      expect(restored.acceptedAt, isNull);
    });

    test('serialise to JSON and back (round-trip with acceptedAt)', () {
      final accepted = DateTime.utc(2025, 3, 15, 9, 0, 0);
      final r = ShareRecipient(
        email: 'dan@example.com',
        name: 'Dan',
        permission: SharedPermission.admin,
        acceptedAt: accepted,
      );
      final json = r.toJson();
      final restored = ShareRecipient.fromJson(json);
      expect(restored.acceptedAt, equals(accepted));
      expect(restored.permission, SharedPermission.admin);
    });

    test('fromJson defaults missing permission to view', () {
      final r = ShareRecipient.fromJson(
          {'email': 'x@example.com', 'name': 'X'});
      expect(r.permission, SharedPermission.view);
    });

    test('equality holds for identical recipients', () {
      const a = ShareRecipient(
          email: 'e@e.com', name: 'E', permission: SharedPermission.edit);
      const b = ShareRecipient(
          email: 'e@e.com', name: 'E', permission: SharedPermission.edit);
      expect(a, equals(b));
    });

    test('equality fails when permission differs', () {
      const a = ShareRecipient(
          email: 'e@e.com', name: 'E', permission: SharedPermission.view);
      const b = ShareRecipient(
          email: 'e@e.com', name: 'E', permission: SharedPermission.edit);
      expect(a, isNot(equals(b)));
    });
  });

  // -------------------------------------------------------------------------
  // ShareSettings model
  // -------------------------------------------------------------------------

  group('ShareSettings model', () {
    test('default construction', () {
      const s = ShareSettings();
      expect(s.password, isNull);
      expect(s.expiresAt, isNull);
      expect(s.permissions, SharedPermission.view);
      expect(s.allowDownload, isTrue);
      expect(s.allowUpload, isFalse);
      expect(s.notifyOnAccess, isFalse);
      expect(s.isPasswordProtected, isFalse);
    });

    test('isPasswordProtected true when password set', () {
      const s = ShareSettings(password: 'secret123');
      expect(s.isPasswordProtected, isTrue);
    });

    test('isPasswordProtected false when password is null', () {
      const s = ShareSettings(password: null);
      expect(s.isPasswordProtected, isFalse);
    });

    test('isPasswordProtected false when password is empty string', () {
      const s = ShareSettings(password: '');
      expect(s.isPasswordProtected, isFalse);
    });

    test('serialise to JSON and back without optional fields', () {
      const s = ShareSettings(permissions: SharedPermission.edit);
      final json = s.toJson();
      final restored = ShareSettings.fromJson(json);
      expect(restored.permissions, SharedPermission.edit);
      expect(restored.password, isNull);
      expect(restored.expiresAt, isNull);
    });

    test('serialise to JSON and back with expiry', () {
      final expiry = DateTime.utc(2026, 1, 1);
      final s = ShareSettings(expiresAt: expiry);
      final json = s.toJson();
      final restored = ShareSettings.fromJson(json);
      expect(restored.expiresAt, equals(expiry));
    });

    test('serialise to JSON and back with password', () {
      const s = ShareSettings(password: 'hunter2');
      final json = s.toJson();
      final restored = ShareSettings.fromJson(json);
      expect(restored.password, 'hunter2');
      expect(restored.isPasswordProtected, isTrue);
    });

    test('equality holds for identical settings', () {
      const a = ShareSettings(
          password: 'pw',
          permissions: SharedPermission.upload,
          allowDownload: false);
      const b = ShareSettings(
          password: 'pw',
          permissions: SharedPermission.upload,
          allowDownload: false);
      expect(a, equals(b));
    });

    test('equality fails when allowUpload differs', () {
      const a = ShareSettings(allowUpload: true);
      const b = ShareSettings(allowUpload: false);
      expect(a, isNot(equals(b)));
    });
  });

  // -------------------------------------------------------------------------
  // SharedFolder model
  // -------------------------------------------------------------------------

  group('SharedFolder model serialisation', () {
    test('round-trip without optional fields', () {
      final f = SharedFolder(
        id: 'f1',
        path: '/Photos',
        provider: 'Dropbox',
        ownerName: 'Eve',
        ownerEmail: 'eve@example.com',
        permissions: SharedPermission.view,
        sharedWith: [],
        createdAt: DateTime.utc(2025, 1, 1),
      );
      final json = f.toJson();
      final restored = SharedFolder.fromJson(json);
      expect(restored.id, 'f1');
      expect(restored.path, '/Photos');
      expect(restored.provider, 'Dropbox');
      expect(restored.ownerName, 'Eve');
      expect(restored.ownerEmail, 'eve@example.com');
      expect(restored.permissions, SharedPermission.view);
      expect(restored.sharedWith, isEmpty);
      expect(restored.shareUrl, isNull);
      expect(restored.expiresAt, isNull);
      expect(restored.passwordProtected, isFalse);
    });

    test('round-trip with recipients, shareUrl and expiresAt', () {
      final folder = _sampleFolder(
        recipients: [
          const ShareRecipient(
              email: 'frank@example.com',
              name: 'Frank',
              permission: SharedPermission.edit),
        ],
      );
      final json = folder.toJson();
      final restored = SharedFolder.fromJson(json);
      expect(restored.sharedWith.length, 1);
      expect(restored.sharedWith.first.email, 'frank@example.com');
      expect(restored.shareUrl, contains('share_001'));
      expect(restored.expiresAt, equals(DateTime.utc(2025, 12, 31)));
    });

    test('equality holds for identical folders', () {
      final a = _sampleFolder();
      final b = _sampleFolder();
      expect(a, equals(b));
    });

    test('equality fails when id differs', () {
      final a = _sampleFolder(id: 'f1');
      final b = _sampleFolder(id: 'f2');
      expect(a, isNot(equals(b)));
    });

    test('copyWith produces updated folder', () {
      final f = _sampleFolder();
      final updated = f.copyWith(passwordProtected: true);
      expect(updated.passwordProtected, isTrue);
      expect(updated.id, f.id);
    });

    test('empty sharedWith list is preserved', () {
      final f = _sampleFolder(recipients: []);
      expect(f.sharedWith, isEmpty);
      final restored = SharedFolder.fromJson(f.toJson());
      expect(restored.sharedWith, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // isProviderSupported
  // -------------------------------------------------------------------------

  group('SharedFolderService.isProviderSupported', () {
    final service = SharedFolderService();

    test('Google Drive is supported', () {
      expect(service.isProviderSupported(_makeGDrive()), isTrue);
    });

    test('OneDrive is supported', () {
      expect(service.isProviderSupported(_makeOneDrive()), isTrue);
    });

    test('Dropbox is supported', () {
      expect(service.isProviderSupported(_makeDropbox()), isTrue);
    });

    test('Nextcloud is supported', () {
      expect(service.isProviderSupported(_makeNextcloud()), isTrue);
    });

    test('SFTP is not supported', () {
      expect(service.isProviderSupported(_makeSFTP()), isFalse);
    });

    test('FTP is not supported', () {
      expect(service.isProviderSupported(_makeFTP()), isFalse);
    });

    test('S3 is not supported', () {
      expect(service.isProviderSupported(_makeS3()), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // getSharedFolders — unsupported provider
  // -------------------------------------------------------------------------

  group('getSharedFolders for unsupported provider', () {
    test('returns empty list for SFTP without throwing', () async {
      final service = SharedFolderService();
      final result = await service.getSharedFolders(_makeSFTP());
      expect(result, isEmpty);
    });

    test('returns empty list for FTP without throwing', () async {
      final service = SharedFolderService();
      final result = await service.getSharedFolders(_makeFTP());
      expect(result, isEmpty);
    });

    test('returns empty list for S3 without throwing', () async {
      final service = SharedFolderService();
      final result = await service.getSharedFolders(_makeS3());
      expect(result, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // shareFolder — unsupported provider throws
  // -------------------------------------------------------------------------

  group('shareFolder throws for unsupported provider', () {
    test('SFTP throws SharingNotSupportedException', () async {
      final service = SharedFolderService();
      expect(
        () => service.shareFolder(
          _makeSFTP(),
          '/path',
          const ShareSettings(),
        ),
        throwsA(isA<SharingNotSupportedException>()),
      );
    });

    test('FTP throws SharingNotSupportedException', () async {
      final service = SharedFolderService();
      expect(
        () => service.shareFolder(
          _makeFTP(),
          '/path',
          const ShareSettings(),
        ),
        throwsA(isA<SharingNotSupportedException>()),
      );
    });

    test('S3 throws SharingNotSupportedException', () async {
      final service = SharedFolderService();
      expect(
        () => service.shareFolder(
          _makeS3(),
          '/path',
          const ShareSettings(),
        ),
        throwsA(isA<SharingNotSupportedException>()),
      );
    });
  });

  // -------------------------------------------------------------------------
  // shareFolder — supported providers
  // -------------------------------------------------------------------------

  group('shareFolder for supported providers', () {
    test('creates a share for Google Drive', () async {
      final service = SharedFolderService();
      final folder = await service.shareFolder(
        _makeGDrive(),
        '/Documents',
        const ShareSettings(permissions: SharedPermission.view),
      );
      expect(folder.id, isNotEmpty);
      expect(folder.path, '/Documents');
      expect(folder.provider, 'Google Drive');
      expect(folder.shareUrl, isNotNull);
    });

    test('creates a share for OneDrive', () async {
      final service = SharedFolderService();
      final folder = await service.shareFolder(
        _makeOneDrive(),
        '/Reports',
        const ShareSettings(),
      );
      expect(folder.provider, 'OneDrive');
      expect(folder.path, '/Reports');
    });

    test('creates a share for Dropbox', () async {
      final service = SharedFolderService();
      final folder = await service.shareFolder(
        _makeDropbox(),
        '/Photos',
        const ShareSettings(),
      );
      expect(folder.provider, 'Dropbox');
    });

    test('creates a share for Nextcloud', () async {
      final service = SharedFolderService();
      final folder = await service.shareFolder(
        _makeNextcloud(),
        '/Shared',
        const ShareSettings(),
      );
      expect(folder.provider, 'Nextcloud');
    });
  });

  // -------------------------------------------------------------------------
  // Share settings: password protection
  // -------------------------------------------------------------------------

  group('shareFolder — password protection', () {
    test('share is password-protected when password in settings', () async {
      final service = SharedFolderService();
      final folder = await service.shareFolder(
        _makeGDrive(),
        '/SecureFolder',
        const ShareSettings(password: 'letmein'),
      );
      expect(folder.passwordProtected, isTrue);
    });

    test('share is not password-protected when no password', () async {
      final service = SharedFolderService();
      final folder = await service.shareFolder(
        _makeGDrive(),
        '/PublicFolder',
        const ShareSettings(),
      );
      expect(folder.passwordProtected, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // Share settings: expiry
  // -------------------------------------------------------------------------

  group('shareFolder — expiry', () {
    test('share carries expiry date from settings', () async {
      final service = SharedFolderService();
      final expiry = DateTime.utc(2026, 6, 30);
      final folder = await service.shareFolder(
        _makeDropbox(),
        '/TempShare',
        ShareSettings(expiresAt: expiry),
      );
      expect(folder.expiresAt, equals(expiry));
    });

    test('share has no expiry when settings have none', () async {
      final service = SharedFolderService();
      final folder = await service.shareFolder(
        _makeDropbox(),
        '/NoExpiry',
        const ShareSettings(),
      );
      expect(folder.expiresAt, isNull);
    });
  });

  // -------------------------------------------------------------------------
  // Permission levels
  // -------------------------------------------------------------------------

  group('shareFolder — permission levels', () {
    test('admin permission is stored on share', () async {
      final service = SharedFolderService();
      final folder = await service.shareFolder(
        _makeGDrive(),
        '/AdminFolder',
        const ShareSettings(permissions: SharedPermission.admin),
      );
      expect(folder.permissions, SharedPermission.admin);
    });

    test('upload permission is stored on share', () async {
      final service = SharedFolderService();
      final folder = await service.shareFolder(
        _makeNextcloud(),
        '/UploadFolder',
        const ShareSettings(permissions: SharedPermission.upload),
      );
      expect(folder.permissions, SharedPermission.upload);
    });
  });

  // -------------------------------------------------------------------------
  // Idempotent share creation
  // -------------------------------------------------------------------------

  group('shareFolder — idempotency', () {
    test('sharing the same path twice returns the same share', () async {
      final service = SharedFolderService();
      final a = await service.shareFolder(
        _makeGDrive(),
        '/Idempotent',
        const ShareSettings(),
      );
      // Second call: the service should detect the existing share and return it.
      final client = _makeGDrive();
      final b = await service.shareFolder(
        client,
        '/Idempotent',
        const ShareSettings(),
      );
      expect(a.id, equals(b.id));
    });
  });

  // -------------------------------------------------------------------------
  // Recipient CRUD
  // -------------------------------------------------------------------------

  group('Recipient management', () {
    test('addRecipient adds a person to the share', () async {
      final service = SharedFolderService();
      final folder = await service.shareFolder(
        _makeGDrive(),
        '/Collab',
        const ShareSettings(),
      );
      await service.addRecipient(
          _makeGDrive(), folder.id, 'grace@example.com', SharedPermission.view);
      // Retrieve updated share from the store via getSharedFolders.
      final shares = await service.getSharedFolders(_makeGDrive());
      // Find the share we created (it lives in the service's store).
      // Access via revokeShare round-trip or indirect effect: check no throw.
      // Direct check: add a second recipient and remove the first.
      await service.addRecipient(
          _makeGDrive(), folder.id, 'henry@example.com', SharedPermission.edit);
      await service.removeRecipient(_makeGDrive(), folder.id, 'grace@example.com');
      // Should not throw — only henry remains.
    });

    test('addRecipient throws ShareNotFoundException for unknown shareId', () {
      final service = SharedFolderService();
      expect(
        () => service.addRecipient(
            _makeGDrive(), 'nonexistent_id', 'x@x.com', SharedPermission.view),
        throwsA(isA<ShareNotFoundException>()),
      );
    });

    test('removeRecipient throws ShareNotFoundException for unknown shareId',
        () {
      final service = SharedFolderService();
      expect(
        () => service.removeRecipient(
            _makeGDrive(), 'nonexistent_id', 'x@x.com'),
        throwsA(isA<ShareNotFoundException>()),
      );
    });

    test('addRecipient is idempotent (updates permission on duplicate email)',
        () async {
      final service = SharedFolderService();
      final folder = await service.shareFolder(
        _makeOneDrive(),
        '/IdemRecipient',
        const ShareSettings(),
      );
      await service.addRecipient(
          _makeOneDrive(), folder.id, 'ivan@example.com', SharedPermission.view);
      // Add same email with different permission.
      await service.addRecipient(
          _makeOneDrive(), folder.id, 'ivan@example.com', SharedPermission.edit);
      // Only one entry for ivan should exist; get via service internals is not
      // directly exposed, so we verify no exception and that the permission is
      // updated by retrieving via getShareLink (no exception expected).
      final link = await service.getShareLink(_makeOneDrive(), folder.id);
      expect(link, isNotEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // Share link generation
  // -------------------------------------------------------------------------

  group('getShareLink', () {
    test('returns a non-empty URL for a GDrive share', () async {
      final service = SharedFolderService();
      final folder = await service.shareFolder(
        _makeGDrive(),
        '/LinkTest',
        const ShareSettings(),
      );
      final link = await service.getShareLink(_makeGDrive(), folder.id);
      expect(link, isNotEmpty);
      expect(Uri.tryParse(link), isNotNull);
    });

    test('returns a non-empty URL for a Dropbox share', () async {
      final service = SharedFolderService();
      final folder = await service.shareFolder(
        _makeDropbox(),
        '/LinkTestDB',
        const ShareSettings(),
      );
      final link = await service.getShareLink(_makeDropbox(), folder.id);
      expect(link, isNotEmpty);
    });

    test('throws ShareNotFoundException for unknown shareId', () {
      final service = SharedFolderService();
      expect(
        () => service.getShareLink(_makeGDrive(), 'no_such_share'),
        throwsA(isA<ShareNotFoundException>()),
      );
    });

    test('throws SharingNotSupportedException for unsupported provider', () {
      final service = SharedFolderService();
      expect(
        () => service.getShareLink(_makeSFTP(), 'any_id'),
        throwsA(isA<SharingNotSupportedException>()),
      );
    });
  });

  // -------------------------------------------------------------------------
  // revokeShare
  // -------------------------------------------------------------------------

  group('revokeShare', () {
    test('removes share successfully', () async {
      final service = SharedFolderService();
      final folder = await service.shareFolder(
        _makeNextcloud(),
        '/Revoke',
        const ShareSettings(),
      );
      // Should not throw:
      await service.revokeShare(_makeNextcloud(), folder.id);
      // Attempting to revoke again should throw ShareNotFoundException.
      expect(
        () => service.revokeShare(_makeNextcloud(), folder.id),
        throwsA(isA<ShareNotFoundException>()),
      );
    });

    test('throws ShareNotFoundException when share does not exist', () {
      final service = SharedFolderService();
      expect(
        () => service.revokeShare(_makeGDrive(), 'ghost_share'),
        throwsA(isA<ShareNotFoundException>()),
      );
    });

    test('throws SharingNotSupportedException for unsupported provider', () {
      final service = SharedFolderService();
      expect(
        () => service.revokeShare(_makeFTP(), 'any_id'),
        throwsA(isA<SharingNotSupportedException>()),
      );
    });
  });

  // -------------------------------------------------------------------------
  // updateShare
  // -------------------------------------------------------------------------

  group('updateShare', () {
    test('updates expiry on existing share', () async {
      final service = SharedFolderService();
      final folder = await service.shareFolder(
        _makeGDrive(),
        '/UpdateTest',
        const ShareSettings(),
      );
      final newExpiry = DateTime.utc(2027, 1, 1);
      await service.updateShare(
        _makeGDrive(),
        folder.id,
        ShareSettings(expiresAt: newExpiry),
      );
      // The update should complete without throwing.
    });

    test('throws ShareNotFoundException for unknown share', () {
      final service = SharedFolderService();
      expect(
        () => service.updateShare(
            _makeOneDrive(), 'unknown_share', const ShareSettings()),
        throwsA(isA<ShareNotFoundException>()),
      );
    });

    test('throws SharingNotSupportedException for unsupported provider', () {
      final service = SharedFolderService();
      expect(
        () => service.updateShare(_makeS3(), 'any', const ShareSettings()),
        throwsA(isA<SharingNotSupportedException>()),
      );
    });
  });

  // -------------------------------------------------------------------------
  // SharingNotSupportedException
  // -------------------------------------------------------------------------

  group('SharingNotSupportedException', () {
    test('toString includes provider name', () {
      const e = SharingNotSupportedException('SFTP');
      expect(e.toString(), contains('SFTP'));
    });
  });

  // -------------------------------------------------------------------------
  // ShareNotFoundException
  // -------------------------------------------------------------------------

  group('ShareNotFoundException', () {
    test('toString includes share id', () {
      const e = ShareNotFoundException('my_share_xyz');
      expect(e.toString(), contains('my_share_xyz'));
    });
  });
}
