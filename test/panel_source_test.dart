// test/panel_source_test.dart
//
// Tests for PanelSource sealed hierarchy and PanelSourceService.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';

// ---------------------------------------------------------------------------
// Minimal stub CloudStorageClient for tests
// ---------------------------------------------------------------------------

class StubCloudClient extends CloudStorageClient {
  final String _name;
  StubCloudClient(this._name);

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
// Tests
// ---------------------------------------------------------------------------

void main() {
  const service = PanelSourceService();

  // ---- PanelSource hierarchy: type checks ----------------------------------

  group('PanelSource type hierarchy', () {
    test('LocalPanelSource isLocal', () {
      const src = LocalPanelSource('/home/user');
      expect(src.isLocal, isTrue);
      expect(src.isRemote, isFalse);
      expect(src.isArchive, isFalse);
      expect(src.isContainer, isFalse);
    });

    test('RemotePanelSource isRemote', () {
      final client = StubCloudClient('Dropbox');
      final src = RemotePanelSource(
        providerName: 'Dropbox',
        client: client,
        path: '/photos',
      );
      expect(src.isRemote, isTrue);
      expect(src.isLocal, isFalse);
      expect(src.isArchive, isFalse);
      expect(src.isContainer, isFalse);
    });

    test('ArchivePanelSource isArchive', () {
      const parent = LocalPanelSource('/home');
      const src = ArchivePanelSource(
        archivePath: '/home/archive.zip',
        innerPath: '',
        parent: parent,
      );
      expect(src.isArchive, isTrue);
      expect(src.isLocal, isFalse);
      expect(src.isRemote, isFalse);
      expect(src.isContainer, isFalse);
    });

    test('ContainerPanelSource isContainer', () {
      const parent = LocalPanelSource('/home');
      final src = ContainerPanelSource(
        containerPath: '/home/vault.vc',
        innerPath: '',
        parent: parent,
        unlockSession: Object(),
      );
      expect(src.isContainer, isTrue);
      expect(src.isLocal, isFalse);
      expect(src.isRemote, isFalse);
      expect(src.isArchive, isFalse);
    });
  });

  // ---- Display names -------------------------------------------------------

  group('PanelSource displayName', () {
    test('LocalPanelSource displayName is "Local"', () {
      expect(const LocalPanelSource('/').displayName, 'Local');
    });

    test('RemotePanelSource displayName is providerName', () {
      final src = RemotePanelSource(
        providerName: 'S3',
        client: StubCloudClient('S3'),
        path: '/',
      );
      expect(src.displayName, 'S3');
    });

    test('ArchivePanelSource displayName contains archive filename', () {
      const src = ArchivePanelSource(
        archivePath: '/home/user/backup.zip',
        innerPath: '',
        parent: LocalPanelSource('/home/user'),
      );
      expect(src.displayName, contains('backup.zip'));
    });

    test('ContainerPanelSource displayName contains container filename', () {
      final src = ContainerPanelSource(
        containerPath: '/data/secure.vc',
        innerPath: '',
        parent: const LocalPanelSource('/data'),
        unlockSession: Object(),
      );
      expect(src.displayName, contains('secure.vc'));
    });
  });

  // ---- currentPath ---------------------------------------------------------

  group('PanelSource currentPath', () {
    test('LocalPanelSource currentPath matches constructor path', () {
      expect(const LocalPanelSource('/tmp').currentPath, '/tmp');
    });

    test('ArchivePanelSource currentPath is innerPath', () {
      const src = ArchivePanelSource(
        archivePath: '/a.zip',
        innerPath: 'subdir/',
        parent: LocalPanelSource('/'),
      );
      expect(src.currentPath, 'subdir/');
    });

    test('ContainerPanelSource currentPath is innerPath', () {
      final src = ContainerPanelSource(
        containerPath: '/a.vc',
        innerPath: 'docs/',
        parent: const LocalPanelSource('/'),
        unlockSession: Object(),
      );
      expect(src.currentPath, 'docs/');
    });
  });

  // ---- withPath ------------------------------------------------------------

  group('withPath', () {
    test('LocalPanelSource withPath returns new LocalPanelSource', () {
      const src = LocalPanelSource('/home');
      final next = src.withPath('/home/downloads');
      expect(next, isA<LocalPanelSource>());
      expect(next.currentPath, '/home/downloads');
    });

    test('RemotePanelSource withPath preserves client and provider', () {
      final client = StubCloudClient('Filen');
      final src = RemotePanelSource(
        providerName: 'Filen',
        client: client,
        path: '/',
      );
      final next = src.withPath('/documents');
      expect(next, isA<RemotePanelSource>());
      expect((next as RemotePanelSource).providerName, 'Filen');
      expect(next.currentPath, '/documents');
    });

    test('ArchivePanelSource withPath updates innerPath', () {
      const src = ArchivePanelSource(
        archivePath: '/a.zip',
        innerPath: '',
        parent: LocalPanelSource('/'),
      );
      final next = src.withPath('folder/');
      expect((next as ArchivePanelSource).innerPath, 'folder/');
      expect(next.archivePath, '/a.zip');
    });
  });

  // ---- Archive detection ---------------------------------------------------

  group('isArchive', () {
    test('.zip is archive', () => expect(service.isArchive('backup.zip'), isTrue));
    test('.tar.gz is archive', () => expect(service.isArchive('src.tar.gz'), isTrue));
    test('.tgz is archive', () => expect(service.isArchive('data.tgz'), isTrue));
    test('.7z is archive', () => expect(service.isArchive('files.7z'), isTrue));
    test('.rar is archive', () => expect(service.isArchive('docs.rar'), isTrue));
    test('.txt is not archive', () => expect(service.isArchive('readme.txt'), isFalse));
    test('.pdf is not archive', () => expect(service.isArchive('report.pdf'), isFalse));
    test('case insensitive ZIP', () => expect(service.isArchive('BACKUP.ZIP'), isTrue));
  });

  // ---- Container detection -------------------------------------------------

  group('isEncryptedContainer', () {
    test('.vc is container', () => expect(service.isEncryptedContainer('vault.vc'), isTrue));
    test('.hc is container', () => expect(service.isEncryptedContainer('secure.hc'), isTrue));
    test('vault.cryptomator is container',
        () => expect(service.isEncryptedContainer('vault.cryptomator'), isTrue));
    test('.zip is not container', () => expect(service.isEncryptedContainer('files.zip'), isFalse));
    test('.txt is not container', () => expect(service.isEncryptedContainer('notes.txt'), isFalse));
  });

  // ---- canEnter ------------------------------------------------------------

  group('canEnter', () {
    test('zip can be entered', () => expect(service.canEnter('photos.zip'), isTrue));
    test('.vc can be entered', () => expect(service.canEnter('data.vc'), isTrue));
    test('.hc can be entered', () => expect(service.canEnter('data.hc'), isTrue));
    test('vault.cryptomator can be entered',
        () => expect(service.canEnter('vault.cryptomator'), isTrue));
    test('.mp4 cannot be entered', () => expect(service.canEnter('video.mp4'), isFalse));
    test('.docx cannot be entered', () => expect(service.canEnter('document.docx'), isFalse));
    test('.7z can be entered', () => expect(service.canEnter('backup.7z'), isTrue));
  });

  // ---- enterArchive --------------------------------------------------------

  group('enterArchive', () {
    test('returns ArchivePanelSource with empty innerPath', () {
      const parent = LocalPanelSource('/home/user');
      final archive = service.enterArchive('/home/user/photos.zip', parent);
      expect(archive, isA<ArchivePanelSource>());
      expect(archive.archivePath, '/home/user/photos.zip');
      expect(archive.innerPath, '');
      expect(archive.currentPath, '');
    });

    test('parent source is preserved', () {
      const parent = LocalPanelSource('/data');
      final archive = service.enterArchive('/data/backup.zip', parent);
      expect(archive.parent, parent);
    });

    test('entering archive from remote preserves remote as parent', () {
      final client = StubCloudClient('S3');
      final remote = RemotePanelSource(
        providerName: 'S3',
        client: client,
        path: '/backups',
      );
      final archive = service.enterArchive('/backups/data.zip', remote);
      expect(archive.parent, remote);
    });
  });

  // ---- enterContainer ------------------------------------------------------

  group('enterContainer', () {
    test('returns ContainerPanelSource with empty innerPath', () {
      const parent = LocalPanelSource('/mnt');
      final container = service.enterContainer('/mnt/secure.vc', 'p@ssw0rd', parent);
      expect(container, isA<ContainerPanelSource>());
      expect(container.containerPath, '/mnt/secure.vc');
      expect(container.innerPath, '');
    });

    test('parent source is preserved', () {
      const parent = LocalPanelSource('/mnt');
      final container = service.enterContainer('/mnt/vault.vc', 'pass', parent);
      expect(container.parent, parent);
    });

    test('unlockSession is not null', () {
      const parent = LocalPanelSource('/');
      final container = service.enterContainer('/vault.vc', 'secret', parent);
      expect(container.unlockSession, isNotNull);
    });
  });

  // ---- exitToParent --------------------------------------------------------

  group('exitToParent', () {
    test('exit archive returns parent LocalPanelSource', () {
      const parent = LocalPanelSource('/home');
      const archive = ArchivePanelSource(
        archivePath: '/home/a.zip',
        innerPath: '',
        parent: parent,
      );
      final result = service.exitToParent(archive);
      expect(result, parent);
    });

    test('exit container returns parent source', () {
      const parent = LocalPanelSource('/data');
      final container = ContainerPanelSource(
        containerPath: '/data/vault.vc',
        innerPath: '',
        parent: parent,
        unlockSession: Object(),
      );
      final result = service.exitToParent(container);
      expect(result, parent);
    });

    test('exit local returns same local source', () {
      const local = LocalPanelSource('/home');
      final result = service.exitToParent(local);
      expect(result, local);
    });

    test('nested archive: exit inner returns outer archive, exit outer returns local', () {
      const localParent = LocalPanelSource('/docs');
      const outerArchive = ArchivePanelSource(
        archivePath: '/docs/outer.zip',
        innerPath: '',
        parent: localParent,
      );
      const innerArchive = ArchivePanelSource(
        archivePath: '/docs/outer.zip',
        innerPath: 'inner/',
        parent: outerArchive,
      );

      final afterFirstExit = service.exitToParent(innerArchive);
      expect(afterFirstExit, outerArchive);

      final afterSecondExit = service.exitToParent(afterFirstExit);
      expect(afterSecondExit, localParent);
    });
  });

  // ---- Both panels same type -----------------------------------------------

  group('Both panels same type', () {
    test('both panels can be local simultaneously', () {
      const left = LocalPanelSource('/home/user');
      const right = LocalPanelSource('/tmp');
      expect(left.isLocal, isTrue);
      expect(right.isLocal, isTrue);
      // They are independent objects.
      expect(left == right, isFalse);
    });

    test('both panels can be remote simultaneously', () {
      final clientA = StubCloudClient('Dropbox');
      final clientB = StubCloudClient('S3');
      final left = RemotePanelSource(
        providerName: 'Dropbox',
        client: clientA,
        path: '/',
      );
      final right = RemotePanelSource(
        providerName: 'S3',
        client: clientB,
        path: '/backup',
      );
      expect(left.isRemote, isTrue);
      expect(right.isRemote, isTrue);
      expect(left == right, isFalse);
    });

    test('left panel archive + right panel remote', () {
      const leftParent = LocalPanelSource('/home');
      const leftArchive = ArchivePanelSource(
        archivePath: '/home/photos.zip',
        innerPath: '',
        parent: leftParent,
      );
      final rightRemote = RemotePanelSource(
        providerName: 'OneDrive',
        client: StubCloudClient('OneDrive'),
        path: '/',
      );
      expect(leftArchive.isArchive, isTrue);
      expect(rightRemote.isRemote, isTrue);
    });
  });

  // ---- Serialisation -------------------------------------------------------

  group('PanelSource serialisation', () {
    test('LocalPanelSource toJson / fromJson round-trip', () {
      const src = LocalPanelSource('/home/user/docs');
      final json = src.toJson();
      expect(json['type'], 'local');
      expect(json['path'], '/home/user/docs');

      final restored = PanelSourceService.fromJson(json);
      expect(restored, isA<LocalPanelSource>());
      expect(restored.currentPath, '/home/user/docs');
    });

    test('ArchivePanelSource toJson includes parent and paths', () {
      const parent = LocalPanelSource('/downloads');
      const src = ArchivePanelSource(
        archivePath: '/downloads/backup.zip',
        innerPath: 'subdir/',
        parent: parent,
      );
      final json = src.toJson();
      expect(json['type'], 'archive');
      expect(json['archivePath'], '/downloads/backup.zip');
      expect(json['innerPath'], 'subdir/');
      expect(json['parent']['type'], 'local');
    });

    test('ArchivePanelSource fromJson restores correctly', () {
      const src = ArchivePanelSource(
        archivePath: '/a.zip',
        innerPath: 'inner/',
        parent: LocalPanelSource('/'),
      );
      final json = src.toJson();
      final restored = PanelSourceService.fromJson(json);
      expect(restored, isA<ArchivePanelSource>());
      expect((restored as ArchivePanelSource).archivePath, '/a.zip');
      expect(restored.innerPath, 'inner/');
    });

    test('ContainerPanelSource toJson omits unlockSession', () {
      final src = ContainerPanelSource(
        containerPath: '/vault.vc',
        innerPath: '',
        parent: const LocalPanelSource('/'),
        unlockSession: Object(),
      );
      final json = src.toJson();
      expect(json.containsKey('unlockSession'), isFalse);
      expect(json['type'], 'container');
    });

    test('ContainerPanelSource fromJson restores correctly', () {
      final src = ContainerPanelSource(
        containerPath: '/vault.hc',
        innerPath: 'docs/',
        parent: const LocalPanelSource('/'),
        unlockSession: Object(),
      );
      final json = src.toJson();
      final restored = PanelSourceService.fromJson(json);
      expect(restored, isA<ContainerPanelSource>());
      expect((restored as ContainerPanelSource).containerPath, '/vault.hc');
      expect(restored.innerPath, 'docs/');
    });

    test('unknown type fromJson returns LocalPanelSource at root', () {
      final restored = PanelSourceService.fromJson({'type': 'unknown'});
      expect(restored, isA<LocalPanelSource>());
      expect(restored.currentPath, '/');
    });
  });

  // ---- Equality & hashCode -------------------------------------------------

  group('PanelSource equality', () {
    test('same LocalPanelSource paths are equal', () {
      expect(const LocalPanelSource('/a'), const LocalPanelSource('/a'));
    });

    test('different LocalPanelSource paths are not equal', () {
      expect(
          const LocalPanelSource('/a') == const LocalPanelSource('/b'), isFalse);
    });

    test('RemotePanelSource equality by provider + path', () {
      final clientA = StubCloudClient('X');
      final clientB = StubCloudClient('X');
      final a = RemotePanelSource(
        providerName: 'X',
        client: clientA,
        path: '/p',
      );
      final b = RemotePanelSource(
        providerName: 'X',
        client: clientB,
        path: '/p',
      );
      expect(a, b);
    });
  });
}
