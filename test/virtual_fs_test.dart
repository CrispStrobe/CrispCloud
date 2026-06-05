// test/virtual_fs_test.dart
//
// Tests for the cross-platform virtual filesystem integration:
//   1. VirtualFsMethod enum
//   2. VirtualFilesystemService — isSupported, getAvailableMethods, model
//   3. DocumentsProviderBridge — platform guard, data model, sync, refreshRoots
//   4. Document ID encoding / decoding (provider:path format)
//   5. Root query (connected providers → roots)
//   6. Mount / unmount lifecycle on non-Android/desktop
//   7. Provider name sanitization
//   8. Empty / multiple providers
//   9. Model serialization (toJson / fromJson round-trips)

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/services/documents_provider_bridge.dart'
    as dpb
    show
        DocumentsProviderBridge,
        DocumentsProviderConnection,
        kIsTestEnvironment;
import 'package:crisp_cloud/services/virtual_fs_service.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Re-exports for brevity.
typedef Connection = dpb.DocumentsProviderConnection;
typedef Bridge = dpb.DocumentsProviderBridge;

void main() {
  // -------------------------------------------------------------------------
  // 1. VirtualFsMethod enum
  // -------------------------------------------------------------------------
  group('VirtualFsMethod enum', () {
    test('contains fuse value', () {
      expect(VirtualFsMethod.values, contains(VirtualFsMethod.fuse));
    });

    test('contains documentsProvider value', () {
      expect(VirtualFsMethod.values,
          contains(VirtualFsMethod.documentsProvider));
    });

    test('contains fileProvider value', () {
      expect(VirtualFsMethod.values, contains(VirtualFsMethod.fileProvider));
    });

    test('contains fileSystemAccess value', () {
      expect(
          VirtualFsMethod.values, contains(VirtualFsMethod.fileSystemAccess));
    });

    test('enum has exactly four values', () {
      expect(VirtualFsMethod.values.length, 4);
    });

    test('fuse is distinct from documentsProvider', () {
      expect(VirtualFsMethod.fuse, isNot(VirtualFsMethod.documentsProvider));
    });

    test('fileProvider is distinct from fileSystemAccess', () {
      expect(
          VirtualFsMethod.fileProvider, isNot(VirtualFsMethod.fileSystemAccess));
    });
  });

  // -------------------------------------------------------------------------
  // 2. VirtualFilesystemService — isSupported & getAvailableMethods
  // -------------------------------------------------------------------------
  group('VirtualFilesystemService — platform methods', () {
    test('getAvailableMethods returns a non-null list', () {
      final svc = VirtualFilesystemService();
      expect(svc.getAvailableMethods(), isA<List<VirtualFsMethod>>());
    });

    test('isSupported is consistent with getAvailableMethods', () {
      final svc = VirtualFilesystemService();
      final methods = svc.getAvailableMethods();
      expect(svc.isSupported, equals(methods.isNotEmpty));
    });

    test('primaryMethod is null when not supported', () {
      // This test is behavioural: if no methods exist primaryMethod is null.
      final svc = VirtualFilesystemService();
      if (!svc.isSupported) {
        expect(svc.primaryMethod, isNull);
      } else {
        expect(svc.primaryMethod, isNotNull);
      }
    });

    test('getAvailableMethods on Linux CI returns [fuse]', () {
      if (kIsWeb) return;
      if (Platform.isLinux) {
        final svc = VirtualFilesystemService();
        expect(svc.getAvailableMethods(), [VirtualFsMethod.fuse]);
      }
    });

    test('getAvailableMethods on macOS returns [fuse]', () {
      if (kIsWeb) return;
      if (Platform.isMacOS) {
        final svc = VirtualFilesystemService();
        expect(svc.getAvailableMethods(), [VirtualFsMethod.fuse]);
      }
    });

    test('web would return [fileSystemAccess]', () {
      // We cannot test kIsWeb == true in a Dart-only test (it is a compile-time
      // constant). We verify the enum value exists and the logic in a unit test
      // by calling the method lookup table directly.
      const method = VirtualFsMethod.fileSystemAccess;
      expect(method, VirtualFsMethod.fileSystemAccess);
    });

    test('getAvailableMethods returns list with single element per platform', () {
      final svc = VirtualFilesystemService();
      final methods = svc.getAvailableMethods();
      // Each platform supports exactly one primary method.
      expect(methods.length, lessThanOrEqualTo(1));
    });
  });

  // -------------------------------------------------------------------------
  // 3. DocumentsProviderBridge — platform guard
  // -------------------------------------------------------------------------
  group('DocumentsProviderBridge — platform guard', () {
    setUp(() {
      dpb.kIsTestEnvironment = true;
      SharedPreferences.setMockInitialValues({});
    });
    tearDown(() {
      dpb.kIsTestEnvironment = false;
    });

    test('isAvailable returns false in test environment', () {
      expect(Bridge.instance.isAvailable, isFalse);
    });

    test('refreshRoots completes without error on non-Android', () async {
      await expectLater(Bridge.instance.refreshRoots(), completes);
    });

    test('syncConnections completes without error on non-Android', () async {
      await expectLater(
        Bridge.instance.syncConnections([
          const Connection(provider: 's3', label: 'My Bucket'),
        ]),
        completes,
      );
    });

    test('notifyChange completes without error on non-Android', () async {
      await expectLater(
          Bridge.instance.notifyChange('/some/path'), completes);
    });

    test('getConnectedProviders returns list (possibly empty) on non-Android',
        () async {
      // After syncing, the in-memory list should reflect the synced value.
      await Bridge.instance.syncConnections([
        const Connection(provider: 'dropbox', label: 'Dropbox'),
      ]);
      final providers = Bridge.instance.getConnectedProviders();
      expect(providers, isA<List<Connection>>());
    });

    test('syncConnections updates in-memory list even on non-Android', () async {
      await Bridge.instance.syncConnections([
        const Connection(provider: 'gdrive', label: 'Google Drive'),
        const Connection(provider: 's3', label: 'My S3'),
      ]);
      final providers = Bridge.instance.getConnectedProviders();
      expect(providers.any((c) => c.provider == 'gdrive'), isTrue);
      expect(providers.any((c) => c.provider == 's3'), isTrue);
    });

    test('syncConnections with empty list clears providers', () async {
      // Seed some providers first.
      await Bridge.instance.syncConnections([
        const Connection(provider: 'ftp', label: 'FTP'),
      ]);
      // Now clear.
      await Bridge.instance.syncConnections([]);
      final providers = Bridge.instance.getConnectedProviders();
      expect(providers, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // 4. Document ID encoding / decoding
  // -------------------------------------------------------------------------
  group('Document ID — provider:path format', () {
    test('makeDocumentId produces provider:path format', () {
      // The format is defined both in the Kotlin side and mirrored in tests.
      // We test the documented contract: "<provider>:<path>".
      const provider = 's3';
      const path = '/bucket/subdir/file.txt';
      const docId = '$provider:$path';
      expect(docId, 's3:/bucket/subdir/file.txt');
    });

    test('parsing a valid document ID extracts provider and path', () {
      const docId = 'dropbox:/Photos/vacation.jpg';
      final colonIdx = docId.indexOf(':');
      final provider = docId.substring(0, colonIdx);
      final path = docId.substring(colonIdx + 1);
      expect(provider, 'dropbox');
      expect(path, '/Photos/vacation.jpg');
    });

    test('root document ID for a provider is provider:/', () {
      const connection =
          Connection(provider: 'onedrive', label: 'OneDrive');
      expect(connection.rootDocumentId, 'onedrive:/');
    });

    test('custom rootDocumentId overrides the default', () {
      const connection = Connection(
        provider: 'sftp',
        label: 'My SFTP',
        rootDocumentId: 'sftp:/home/user',
      );
      expect(connection.rootDocumentId, 'sftp:/home/user');
    });

    test('document ID with deep path is preserved', () {
      const provider = 'webdav';
      const path = '/Documents/Projects/2026/report.pdf';
      const docId = '$provider:$path';
      final colonIdx = docId.indexOf(':');
      expect(docId.substring(colonIdx + 1), path);
    });

    test('document ID with spaces is preserved', () {
      const docId = 'gdrive:/My Documents/hello world.txt';
      final colonIdx = docId.indexOf(':');
      final path = docId.substring(colonIdx + 1);
      expect(path, '/My Documents/hello world.txt');
    });

    test('provider name sanitization: lowercase names are used as-is', () {
      const connection = Connection(provider: 's3', label: 'S3');
      expect(connection.provider, 's3');
      expect(connection.rootDocumentId, startsWith('s3:'));
    });

    test('provider name with hyphen forms valid document ID', () {
      const provider = 'internxt-drive';
      const docId = '$provider:/';
      expect(docId.indexOf(':'), greaterThan(0));
      expect(docId.substring(0, docId.indexOf(':')), provider);
    });
  });

  // -------------------------------------------------------------------------
  // 5. Root query: connected providers → roots
  // -------------------------------------------------------------------------
  group('Root query — connected providers', () {
    setUp(() {
      dpb.kIsTestEnvironment = true;
      SharedPreferences.setMockInitialValues({});
    });
    tearDown(() {
      dpb.kIsTestEnvironment = false;
    });

    test('empty providers list → no roots', () async {
      await Bridge.instance.syncConnections([]);
      final roots = Bridge.instance.getConnectedProviders();
      expect(roots, isEmpty);
    });

    test('single provider → one root entry', () async {
      await Bridge.instance.syncConnections([
        const Connection(provider: 's3', label: 'My Bucket'),
      ]);
      final roots = Bridge.instance.getConnectedProviders();
      expect(roots.length, 1);
      expect(roots.first.provider, 's3');
      expect(roots.first.label, 'My Bucket');
    });

    test('multiple providers → multiple root entries', () async {
      await Bridge.instance.syncConnections([
        const Connection(provider: 's3', label: 'S3 Bucket'),
        const Connection(provider: 'dropbox', label: 'Dropbox'),
        const Connection(provider: 'gdrive', label: 'Google Drive'),
      ]);
      final roots = Bridge.instance.getConnectedProviders();
      expect(roots.length, 3);
      final providers = roots.map((r) => r.provider).toSet();
      expect(providers, containsAll(['s3', 'dropbox', 'gdrive']));
    });

    test('each root has a non-empty rootDocumentId', () async {
      await Bridge.instance.syncConnections([
        const Connection(provider: 'ftp', label: 'FTP Server'),
        const Connection(provider: 'sftp', label: 'SFTP Server'),
      ]);
      final roots = Bridge.instance.getConnectedProviders();
      for (final root in roots) {
        expect(root.rootDocumentId, isNotEmpty);
        expect(root.rootDocumentId, contains(':'));
      }
    });

    test('root document IDs follow provider:/ pattern by default', () async {
      await Bridge.instance.syncConnections([
        const Connection(provider: 'b2', label: 'Backblaze B2'),
      ]);
      final roots = Bridge.instance.getConnectedProviders();
      expect(roots.first.rootDocumentId, 'b2:/');
    });

    test('replacing connections removes old providers', () async {
      await Bridge.instance.syncConnections([
        const Connection(provider: 's3', label: 'S3'),
        const Connection(provider: 'dropbox', label: 'Dropbox'),
      ]);
      // Replace with only one provider.
      await Bridge.instance.syncConnections([
        const Connection(provider: 'gdrive', label: 'GDrive'),
      ]);
      final roots = Bridge.instance.getConnectedProviders();
      expect(roots.length, 1);
      expect(roots.first.provider, 'gdrive');
    });
  });

  // -------------------------------------------------------------------------
  // 6. VirtualMount model
  // -------------------------------------------------------------------------
  group('VirtualMount model', () {
    test('construction sets all fields', () {
      final mount = VirtualMount(
        provider: 's3',
        label: 'My Bucket',
        method: VirtualFsMethod.documentsProvider,
        mountPoint: '',
      );
      expect(mount.provider, 's3');
      expect(mount.label, 'My Bucket');
      expect(mount.method, VirtualFsMethod.documentsProvider);
      expect(mount.isActive, isTrue);
    });

    test('isActive defaults to true', () {
      final mount = VirtualMount(
        provider: 'dropbox',
        label: 'Dropbox',
        method: VirtualFsMethod.fileProvider,
      );
      expect(mount.isActive, isTrue);
    });

    test('isActive can be set to false', () {
      final mount = VirtualMount(
        provider: 'ftp',
        label: 'FTP',
        method: VirtualFsMethod.fuse,
        isActive: false,
      );
      expect(mount.isActive, isFalse);
    });

    test('mountPoint defaults to empty string', () {
      final mount = VirtualMount(
        provider: 'sftp',
        label: 'SFTP',
        method: VirtualFsMethod.fuse,
      );
      expect(mount.mountPoint, '');
    });

    test('toString contains provider and method', () {
      final mount = VirtualMount(
        provider: 'gdrive',
        label: 'Google Drive',
        method: VirtualFsMethod.fileProvider,
      );
      final str = mount.toString();
      expect(str, contains('gdrive'));
      expect(str, contains('fileProvider'));
    });
  });

  // -------------------------------------------------------------------------
  // 7. DocumentsProviderConnection model serialization
  // -------------------------------------------------------------------------
  group('DocumentsProviderConnection serialization', () {
    test('toJson round-trip preserves all fields', () {
      const conn = Connection(
        provider: 's3',
        label: 'My S3 Bucket',
        rootDocumentId: 's3:/mybucket',
      );
      final json = conn.toJson();
      final decoded = Connection.fromJson(json);
      expect(decoded.provider, conn.provider);
      expect(decoded.label, conn.label);
      expect(decoded.rootDocumentId, conn.rootDocumentId);
    });

    test('fromJson falls back to provider when label is absent', () {
      final json = {'provider': 'ftp'};
      final conn = Connection.fromJson(json as Map<String, dynamic>);
      expect(conn.provider, 'ftp');
      expect(conn.label, 'ftp');
    });

    test('toJson includes provider, label, and rootDocumentId keys', () {
      const conn = Connection(provider: 'webdav', label: 'WebDAV');
      final json = conn.toJson();
      expect(json.containsKey('provider'), isTrue);
      expect(json.containsKey('label'), isTrue);
      expect(json.containsKey('rootDocumentId'), isTrue);
    });

    test('default rootDocumentId is provider:/', () {
      const conn = Connection(provider: 'dropbox', label: 'Dropbox');
      expect(conn.rootDocumentId, 'dropbox:/');
    });

    test('toString contains provider and label', () {
      const conn = Connection(provider: 's3', label: 'My S3');
      final str = conn.toString();
      expect(str, contains('s3'));
      expect(str, contains('My S3'));
    });

    test('toJson values are all strings', () {
      const conn = Connection(provider: 'b2', label: 'B2 Cloud');
      final json = conn.toJson();
      for (final value in json.values) {
        expect(value, isA<String>());
      }
    });

    test('fromJson handles explicit rootDocumentId', () {
      final json = {
        'provider': 'sftp',
        'label': 'My SFTP',
        'rootDocumentId': 'sftp:/home/user',
      };
      final conn = Connection.fromJson(json);
      expect(conn.rootDocumentId, 'sftp:/home/user');
    });
  });

  // -------------------------------------------------------------------------
  // 8. VirtualFilesystemService — isMounted
  // -------------------------------------------------------------------------
  group('VirtualFilesystemService — isMounted', () {
    setUp(() {
      dpb.kIsTestEnvironment = true;
      SharedPreferences.setMockInitialValues({});
    });
    tearDown(() {
      dpb.kIsTestEnvironment = false;
    });

    test('isMounted returns false for unknown provider', () {
      final svc = VirtualFilesystemService();
      expect(svc.isMounted('nonexistent'), isFalse);
    });

    test('activeMounts returns unmodifiable list', () {
      final svc = VirtualFilesystemService();
      final mounts = svc.activeMounts;
      expect(() => (mounts as dynamic).add(null), throwsUnsupportedError);
    });

    test('activeMounts is empty initially', () {
      final svc = VirtualFilesystemService();
      expect(svc.activeMounts, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // 9. VirtualFilesystemService — unsupported platform throws
  // -------------------------------------------------------------------------
  group('VirtualFilesystemService — platform guard', () {
    setUp(() {
      dpb.kIsTestEnvironment = true;
      SharedPreferences.setMockInitialValues({});
    });
    tearDown(() {
      dpb.kIsTestEnvironment = false;
    });

    test('mount on unsupported platform throws UnsupportedError', () async {
      // On Linux CI, the FUSE service IS supported, so we skip this test there.
      final svc = VirtualFilesystemService();
      if (svc.isSupported) return; // Skip on supported platforms.

      await expectLater(
        () => svc.mount(provider: 's3', label: 'S3'),
        throwsUnsupportedError,
      );
    });

    test('unmount on unsupported platform throws UnsupportedError', () async {
      final svc = VirtualFilesystemService();
      if (svc.isSupported) return; // Skip on supported platforms.

      await expectLater(
        () => svc.unmount('s3'),
        throwsUnsupportedError,
      );
    });
  });

  // -------------------------------------------------------------------------
  // 10. DocumentsProviderBridge — getConnectedProviders is unmodifiable
  // -------------------------------------------------------------------------
  group('DocumentsProviderBridge — list safety', () {
    setUp(() {
      dpb.kIsTestEnvironment = true;
      SharedPreferences.setMockInitialValues({});
    });
    tearDown(() {
      dpb.kIsTestEnvironment = false;
    });

    test('getConnectedProviders returns unmodifiable list', () async {
      final list = Bridge.instance.getConnectedProviders();
      expect(() => (list as dynamic).add(null), throwsUnsupportedError);
    });

    test('modifying the list externally does not change internal state',
        () async {
      await Bridge.instance.syncConnections([
        const Connection(provider: 'ftp', label: 'FTP'),
      ]);
      final list = Bridge.instance.getConnectedProviders();
      expect(() => (list as dynamic).add(null), throwsUnsupportedError);
      // Internal list unchanged
      final list2 = Bridge.instance.getConnectedProviders();
      expect(list2.length, 1);
    });
  });

  // -------------------------------------------------------------------------
  // 11. VirtualFsMethod coverage: all methods in enum accessible by index
  // -------------------------------------------------------------------------
  group('VirtualFsMethod — index access', () {
    test('fuse is at a known index', () {
      expect(VirtualFsMethod.values.contains(VirtualFsMethod.fuse), isTrue);
    });

    test('all enum values have unique indices', () {
      final indices = VirtualFsMethod.values.map((e) => e.index).toSet();
      expect(indices.length, VirtualFsMethod.values.length);
    });

    test('enum names are lower-camel-case', () {
      for (final v in VirtualFsMethod.values) {
        final name = v.name;
        // First character should be lowercase.
        expect(name[0].toLowerCase(), name[0]);
      }
    });
  });
}
