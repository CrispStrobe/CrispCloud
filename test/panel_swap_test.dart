// test/panel_swap_test.dart
//
// Tests for PanelSwapService — Ctrl+U panel exchange.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/services/panel_swap_service.dart';

// ---------------------------------------------------------------------------
// Minimal stub CloudStorageClient
// ---------------------------------------------------------------------------

class _StubClient extends CloudStorageClient {
  final String _name;
  _StubClient(this._name);

  @override
  String get providerName => _name;

  @override
  String get rootPath => '/';

  @override
  bool get isAuthenticated => false;

  @override
  Future<void> login(String email, String password,
      {String? twoFactorCode}) async {}

  @override
  Future<bool> is2faNeeded(String email) async => false;

  @override
  Future<void> logout() async {}

  @override
  String? get userId => null;

  @override
  String? get bucketId => null;

  @override
  Future<Map<String, dynamic>?> resolvePath(String path) async => null;

  @override
  Future<Map<String, dynamic>> listPath(String path) async =>
      {'folders': <dynamic>[], 'files': <dynamic>[]};

  @override
  Future<void> uploadFile(List<int> fileData, String fileName, String targetPath,
      {Function(int, int)? onProgress}) async {}

  @override
  Future<void> downloadFileByPath(String remotePath, String localPath,
      {Function(int, int)? onProgress}) async {}

  @override
  Future<Uint8List> downloadFileBytes(String remotePath,
      {Function(int, int)? onProgress}) async =>
      Uint8List(0);

  @override
  Future<void> createFolderPath(String path) async {}

  @override
  Future<void> deletePath(String path) async {}

  @override
  Future<void> movePath(String sourcePath, String targetPath) async {}

  @override
  Future<void> renamePath(String path, String newName) async {}
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _svc = PanelSwapService();

const _localLeft = LocalPanelSource('/home/user');
const _localRight = LocalPanelSource('/tmp');

final _remoteDropbox = RemotePanelSource(
  providerName: 'Dropbox',
  client: _StubClient('Dropbox'),
  path: '/Documents',
);

final _remoteGdrive = RemotePanelSource(
  providerName: 'Google Drive',
  client: _StubClient('Google Drive'),
  path: '/Photos',
);

const _archiveSource = ArchivePanelSource(
  archivePath: '/home/user/archive.zip',
  innerPath: 'subdir/',
  parent: _localLeft,
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ---- canSwap is always true ----------------------------------------------

  group('canSwap', () {
    test('canSwap Local↔Local is true', () {
      expect(_svc.canSwap(_localLeft, _localRight), isTrue);
    });

    test('canSwap Local↔Remote is true', () {
      expect(_svc.canSwap(_localLeft, _remoteDropbox), isTrue);
    });

    test('canSwap Remote↔Remote is true', () {
      expect(_svc.canSwap(_remoteDropbox, _remoteGdrive), isTrue);
    });

    test('canSwap Archive↔Local is true', () {
      expect(_svc.canSwap(_archiveSource, _localRight), isTrue);
    });

    test('canSwap with identical panels is true', () {
      expect(_svc.canSwap(_localLeft, _localLeft), isTrue);
    });
  });

  // ---- swap Local↔Remote --------------------------------------------------

  group('swap Local↔Remote', () {
    test('left panel becomes Remote after swap', () {
      final (left, _) = _svc.swap(_localLeft, _remoteDropbox);
      expect(left, isA<RemotePanelSource>());
    });

    test('right panel becomes Local after swap', () {
      final (_, right) = _svc.swap(_localLeft, _remoteDropbox);
      expect(right, isA<LocalPanelSource>());
    });

    test('left path is former right path', () {
      final (left, _) = _svc.swap(_localLeft, _remoteDropbox);
      expect(left.currentPath, _remoteDropbox.currentPath);
    });

    test('right path is former left path', () {
      final (_, right) = _svc.swap(_localLeft, _remoteDropbox);
      expect(right.currentPath, _localLeft.currentPath);
    });
  });

  // ---- swap Remote↔Remote -------------------------------------------------

  group('swap Remote↔Remote', () {
    test('left becomes former right remote source', () {
      final (left, _) = _svc.swap(_remoteDropbox, _remoteGdrive);
      final leftRemote = left as RemotePanelSource;
      expect(leftRemote.providerName, 'Google Drive');
    });

    test('right becomes former left remote source', () {
      final (_, right) = _svc.swap(_remoteDropbox, _remoteGdrive);
      final rightRemote = right as RemotePanelSource;
      expect(rightRemote.providerName, 'Dropbox');
    });

    test('paths are preserved after swap', () {
      final (left, right) = _svc.swap(_remoteDropbox, _remoteGdrive);
      expect(left.currentPath, _remoteGdrive.currentPath);
      expect(right.currentPath, _remoteDropbox.currentPath);
    });
  });

  // ---- swap Archive↔Local -------------------------------------------------

  group('swap Archive↔Local', () {
    test('left becomes Local after swap', () {
      final (left, _) = _svc.swap(_archiveSource, _localRight);
      expect(left, isA<LocalPanelSource>());
    });

    test('right becomes Archive after swap', () {
      final (_, right) = _svc.swap(_archiveSource, _localRight);
      expect(right, isA<ArchivePanelSource>());
    });

    test('archive inner path is preserved', () {
      final (_, right) = _svc.swap(_archiveSource, _localRight);
      expect(right.currentPath, _archiveSource.currentPath);
    });
  });

  // ---- swap preserves paths -----------------------------------------------

  group('swap preserves paths', () {
    test('local source paths are preserved intact', () {
      final (left, right) = _svc.swap(_localLeft, _localRight);
      expect(left.currentPath, _localRight.currentPath);
      expect(right.currentPath, _localLeft.currentPath);
    });

    test('remote display names are preserved', () {
      final (left, right) = _svc.swap(_remoteDropbox, _remoteGdrive);
      expect(left.displayName, _remoteGdrive.displayName);
      expect(right.displayName, _remoteDropbox.displayName);
    });
  });

  // ---- swap is its own inverse (double swap = original) -------------------

  group('swap is its own inverse', () {
    test('Local↔Remote double swap returns original', () {
      final (a1, b1) = _svc.swap(_localLeft, _remoteDropbox);
      final (a2, b2) = _svc.swap(a1, b1);
      expect(a2, equals(_localLeft));
      expect(b2.currentPath, equals(_remoteDropbox.currentPath));
    });

    test('Local↔Local double swap returns original', () {
      final (a1, b1) = _svc.swap(_localLeft, _localRight);
      final (a2, b2) = _svc.swap(a1, b1);
      expect(a2, equals(_localLeft));
      expect(b2, equals(_localRight));
    });

    test('Remote↔Remote double swap restores original paths', () {
      final (a1, b1) = _svc.swap(_remoteDropbox, _remoteGdrive);
      final (a2, b2) = _svc.swap(a1, b1);
      expect(a2.currentPath, equals(_remoteDropbox.currentPath));
      expect(b2.currentPath, equals(_remoteGdrive.currentPath));
    });
  });
}
