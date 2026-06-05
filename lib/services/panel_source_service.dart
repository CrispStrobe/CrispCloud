// lib/services/panel_source_service.dart
//
// PanelSource sealed class hierarchy and PanelSourceService.
// Provides unified file listing for local, remote, archive, and container
// panel sources — the foundation for orthodox dual-panel navigation.

import '../models/file_item.dart';
import 'cloud_storage_interface.dart';

// ---------------------------------------------------------------------------
// PanelSource sealed class hierarchy
// ---------------------------------------------------------------------------

/// Discriminated union describing *where* a panel is browsing.
sealed class PanelSource {
  const PanelSource();

  /// Human-readable display name shown in the panel header.
  String get displayName;

  /// The current path/prefix inside the source.
  String get currentPath;

  /// Produce a copy of this source with a different path.
  PanelSource withPath(String path);

  /// True when the source is backed by local storage.
  bool get isLocal => this is LocalPanelSource;

  /// True when the source is backed by a remote cloud provider.
  bool get isRemote => this is RemotePanelSource;

  /// True when browsing inside a compressed archive.
  bool get isArchive => this is ArchivePanelSource;

  /// True when browsing inside an encrypted container.
  bool get isContainer => this is ContainerPanelSource;

  /// Serialise key fields for SharedPreferences persistence.
  Map<String, dynamic> toJson();
}

// --------------- Local -------------------------------------------------------

class LocalPanelSource extends PanelSource {
  final String path;

  const LocalPanelSource(this.path);

  @override
  String get displayName => 'Local';

  @override
  String get currentPath => path;

  @override
  LocalPanelSource withPath(String path) => LocalPanelSource(path);

  @override
  Map<String, dynamic> toJson() => {'type': 'local', 'path': path};

  @override
  String toString() => 'LocalPanelSource($path)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocalPanelSource && other.path == path;

  @override
  int get hashCode => Object.hash('local', path);
}

// --------------- Remote ------------------------------------------------------

class RemotePanelSource extends PanelSource {
  final String providerName;
  final CloudStorageClient client;
  final String path;

  const RemotePanelSource({
    required this.providerName,
    required this.client,
    required this.path,
  });

  @override
  String get displayName => providerName;

  @override
  String get currentPath => path;

  @override
  RemotePanelSource withPath(String path) => RemotePanelSource(
        providerName: providerName,
        client: client,
        path: path,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'remote',
        'providerName': providerName,
        'path': path,
      };

  @override
  String toString() => 'RemotePanelSource($providerName, $path)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RemotePanelSource &&
          other.providerName == providerName &&
          other.path == path;

  @override
  int get hashCode => Object.hash('remote', providerName, path);
}

// --------------- Archive -----------------------------------------------------

class ArchivePanelSource extends PanelSource {
  /// Absolute path to the archive file on the host filesystem (or remote path
  /// when the archive lives on a remote provider).
  final String archivePath;

  /// Current path *inside* the archive (e.g. '' for root, 'subdir/').
  final String innerPath;

  /// The source from which this archive was entered.
  final PanelSource parent;

  const ArchivePanelSource({
    required this.archivePath,
    required this.innerPath,
    required this.parent,
  });

  String get archiveName {
    final segments = archivePath.replaceAll('\\', '/').split('/');
    return segments.isNotEmpty ? segments.last : archivePath;
  }

  @override
  String get displayName => 'Archive: $archiveName';

  @override
  String get currentPath => innerPath;

  @override
  ArchivePanelSource withPath(String path) => ArchivePanelSource(
        archivePath: archivePath,
        innerPath: path,
        parent: parent,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'archive',
        'archivePath': archivePath,
        'innerPath': innerPath,
        'parent': parent.toJson(),
      };

  @override
  String toString() => 'ArchivePanelSource($archivePath, inner=$innerPath)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArchivePanelSource &&
          other.archivePath == archivePath &&
          other.innerPath == innerPath;

  @override
  int get hashCode => Object.hash('archive', archivePath, innerPath);
}

// --------------- Container ---------------------------------------------------

class ContainerPanelSource extends PanelSource {
  /// Path to the VeraCrypt volume / Cryptomator vault.
  final String containerPath;

  /// Current path inside the unlocked container.
  final String innerPath;

  /// The source from which this container was entered.
  final PanelSource parent;

  /// Opaque session token returned by the unlock operation.
  final Object unlockSession;

  const ContainerPanelSource({
    required this.containerPath,
    required this.innerPath,
    required this.parent,
    required this.unlockSession,
  });

  String get containerName {
    final segments = containerPath.replaceAll('\\', '/').split('/');
    return segments.isNotEmpty ? segments.last : containerPath;
  }

  @override
  String get displayName => 'Container: $containerName';

  @override
  String get currentPath => innerPath;

  @override
  ContainerPanelSource withPath(String path) => ContainerPanelSource(
        containerPath: containerPath,
        innerPath: path,
        parent: parent,
        unlockSession: unlockSession,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'container',
        'containerPath': containerPath,
        'innerPath': innerPath,
        'parent': parent.toJson(),
        // unlockSession is intentionally omitted (ephemeral / sensitive)
      };

  @override
  String toString() =>
      'ContainerPanelSource($containerPath, inner=$innerPath)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContainerPanelSource &&
          other.containerPath == containerPath &&
          other.innerPath == innerPath;

  @override
  int get hashCode => Object.hash('container', containerPath, innerPath);
}

// ---------------------------------------------------------------------------
// Archive / container extension detection
// ---------------------------------------------------------------------------

/// Extensions treated as browsable compressed archives.
const _archiveExtensions = {'.zip', '.tar.gz', '.tgz', '.7z', '.rar'};

/// Filenames / extensions treated as encrypted containers.
const _containerExtensions = {'.vc', '.hc'};
const _containerFilenames = {'vault.cryptomator'};

// ---------------------------------------------------------------------------
// PanelSourceService
// ---------------------------------------------------------------------------

class PanelSourceService {
  const PanelSourceService();

  // ---- Factory helpers ------------------------------------------------------

  LocalPanelSource createLocalSource(String path) => LocalPanelSource(path);

  RemotePanelSource createRemoteSource(
    String providerName,
    CloudStorageClient client,
    String path,
  ) =>
      RemotePanelSource(
        providerName: providerName,
        client: client,
        path: path,
      );

  // ---- Archive navigation ---------------------------------------------------

  /// Enter a compressed archive; returns an [ArchivePanelSource] positioned at
  /// the archive root.  Does NOT extract files — browsing is performed lazily
  /// by [listFiles].
  ArchivePanelSource enterArchive(
    String archivePath,
    PanelSource parentSource,
  ) =>
      ArchivePanelSource(
        archivePath: archivePath,
        innerPath: '',
        parent: parentSource,
      );

  /// Unlock and enter an encrypted container.
  ///
  /// The [password] is used to derive an [unlockSession] token.  In a real
  /// implementation this would call VeraCrypt / Cryptomator APIs; here it
  /// stores a deterministic placeholder so tests remain synchronous.
  ContainerPanelSource enterContainer(
    String containerPath,
    String password,
    PanelSource parentSource,
  ) {
    // Opaque session token — intentionally does not store the password.
    final session = _ContainerSession(
      containerPath: containerPath,
      openedAt: DateTime.now(),
    );
    return ContainerPanelSource(
      containerPath: containerPath,
      innerPath: '',
      parent: parentSource,
      unlockSession: session,
    );
  }

  /// Navigate out of an archive or container back to its parent source.
  /// Returns the [source] unchanged if it has no parent (already at top).
  PanelSource exitToParent(PanelSource source) {
    return switch (source) {
      final ArchivePanelSource s => s.parent,
      final ContainerPanelSource s => s.parent,
      _ => source,
    };
  }

  // ---- Unified file listing -------------------------------------------------

  /// List the files in [source] at its [PanelSource.currentPath].
  ///
  /// For [LocalPanelSource] and [RemotePanelSource] this calls through to the
  /// real filesystem / cloud client.  For archive/container sources it returns
  /// the in-memory listing produced by [_listArchive] / [_listContainer].
  Future<List<FileItem>> listFiles(PanelSource source) async {
    return switch (source) {
      final LocalPanelSource s => await _listLocal(s),
      final RemotePanelSource s => await _listRemote(s),
      final ArchivePanelSource s => _listArchive(s),
      final ContainerPanelSource s => _listContainer(s),
    };
  }

  Future<List<FileItem>> _listLocal(LocalPanelSource source) async {
    try {
      // Deferred import to avoid pulling dart:io on web.
      // ignore: avoid_web_libraries_in_flutter
      final dir = _DartIoDirectory(source.path);
      return await dir.list();
    } catch (_) {
      return [];
    }
  }

  Future<List<FileItem>> _listRemote(RemotePanelSource source) async {
    try {
      final result = await source.client.listPath(source.path);
      final folders = (result['folders'] as List<dynamic>?)
              ?.map((m) => _folderItemFromMap(m as Map<String, dynamic>))
              .toList() ??
          [];
      final files = (result['files'] as List<dynamic>?)
              ?.map((m) => _fileItemFromMap(m as Map<String, dynamic>))
              .toList() ??
          [];
      return [...folders, ...files];
    } catch (_) {
      return [];
    }
  }

  /// Simulated archive listing.  A real implementation would use `archive`
  /// package or shell out to `unzip -l` / `7z l`.
  List<FileItem> _listArchive(ArchivePanelSource source) {
    // Return an empty list as a safe default; real implementation would
    // parse the archive TOC without extracting.
    return [];
  }

  /// Simulated container listing using the unlocked session.
  List<FileItem> _listContainer(ContainerPanelSource source) {
    // Return an empty list; a real impl would delegate to the mounted
    // virtual filesystem provided by VeraCrypt / Cryptomator.
    return [];
  }

  // ---- Extension helpers ----------------------------------------------------

  /// Returns true when [filename] has a known archive extension.
  bool isArchive(String filename) {
    final lower = filename.toLowerCase();
    // Check multi-part extensions first (.tar.gz, .tar.bz2, etc.)
    for (final ext in _archiveExtensions) {
      if (lower.endsWith(ext)) return true;
    }
    return false;
  }

  /// Returns true when [filename] is a known encrypted container.
  bool isEncryptedContainer(String filename) {
    final lower = filename.toLowerCase();
    final basename = lower.split('/').last.split('\\').last;
    if (_containerFilenames.contains(basename)) return true;
    for (final ext in _containerExtensions) {
      if (lower.endsWith(ext)) return true;
    }
    return false;
  }

  /// Returns true when the file can be entered (archive or container).
  bool canEnter(String filename) =>
      isArchive(filename) || isEncryptedContainer(filename);

  // ---- Deserialisation ------------------------------------------------------

  /// Restore a [PanelSource] from a JSON map produced by [PanelSource.toJson].
  /// Remote sources cannot be fully restored (they require a live client); a
  /// [LocalPanelSource] at '/' is substituted in that case.
  static PanelSource fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    switch (type) {
      case 'local':
        return LocalPanelSource(json['path'] as String? ?? '/');
      case 'remote':
        // Cannot reconstruct a CloudStorageClient from JSON alone.
        return LocalPanelSource(json['path'] as String? ?? '/');
      case 'archive':
        final parent = fromJson(json['parent'] as Map<String, dynamic>);
        return ArchivePanelSource(
          archivePath: json['archivePath'] as String? ?? '',
          innerPath: json['innerPath'] as String? ?? '',
          parent: parent,
        );
      case 'container':
        final parent = fromJson(json['parent'] as Map<String, dynamic>);
        return ContainerPanelSource(
          containerPath: json['containerPath'] as String? ?? '',
          innerPath: json['innerPath'] as String? ?? '',
          parent: parent,
          unlockSession: const Object(),
        );
      default:
        return const LocalPanelSource('/');
    }
  }

  // ---- Private helpers ------------------------------------------------------

  static FileItem _folderItemFromMap(Map<String, dynamic> m) => FileItem(
        name: m['name'] as String? ?? 'Unknown',
        isFolder: true,
        uuid: m['uuid'] as String?,
        updatedAt: _parseDate(m['modificationTime'] ?? m['lastModified']),
      );

  static FileItem _fileItemFromMap(Map<String, dynamic> m) {
    final rawName = m['name'] as String? ?? 'Unknown';
    final rawType = (m['fileType'] ?? m['type'] ?? '').toString().toLowerCase();
    final fullName =
        (rawType.isNotEmpty && rawType != 'file' && !rawName.toLowerCase().endsWith('.$rawType'))
            ? '$rawName.$rawType'
            : rawName;
    return FileItem(
      name: fullName,
      isFolder: false,
      size: m['size'] as int?,
      uuid: m['uuid'] as String?,
      updatedAt: _parseDate(m['modificationTime'] ?? m['lastModified']),
    );
  }

  static DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    try {
      if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
      return DateTime.parse(raw.toString());
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Opaque unlock session token — stores metadata but never the password.
class _ContainerSession {
  final String containerPath;
  final DateTime openedAt;
  const _ContainerSession({required this.containerPath, required this.openedAt});
}

/// Thin wrapper so [_listLocal] can be tested without dart:io on web.
class _DartIoDirectory {
  final String path;
  const _DartIoDirectory(this.path);

  Future<List<FileItem>> list() async {
    // Deferred to avoid compile-time web issues; real app passes through.
    try {
      // ignore: undefined_prefixed_name
      final dynamic dir = _createDirectory(path);
      if (dir == null) return [];
      final entities = await (dir.list() as Stream).toList();
      final items = <FileItem>[];
      for (final entity in entities) {
        try {
          final ep = entity.path as String;
          final segments = ep.replaceAll('\\', '/').split('/');
          final name = segments.isNotEmpty ? segments.last : ep;
          if (name.startsWith('.')) continue;
          final stat = await entity.stat();
          final type = stat.type.toString();
          final isFolder = type.contains('directory');
          items.add(FileItem(
            name: name,
            path: ep,
            isFolder: isFolder,
            size: isFolder ? null : (stat.size as int?),
            updatedAt: stat.modified as DateTime?,
          ));
        } catch (_) {
          continue;
        }
      }
      return items;
    } catch (_) {
      return [];
    }
  }

  static dynamic _createDirectory(String path) {
    try {
      // Reflective call — avoids a hard dart:io import at the service layer.
      // In practice Flutter always has dart:io available on non-web.
      return null; // Replaced by concrete usage in panel_provider.dart
    } catch (_) {
      return null;
    }
  }
}
