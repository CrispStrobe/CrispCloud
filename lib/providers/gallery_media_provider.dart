import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../services/cloud_storage_interface.dart';
import '../services/gallery_media_service.dart';
import '../services/local_file_service.dart';
import '../services/panel_source_service.dart';
import 'auth_provider.dart';
import 'core_providers.dart';
import 'panel_provider.dart';
import 'panel_source_provider.dart';

final galleryMediaServiceProvider = Provider<GalleryMediaService>((ref) =>
    GalleryMediaService(thumbnails: ref.watch(thumbnailServiceProvider)));

final _sessionTokens = Expando<String>('gallery source session');
final _sessionNonce = DateTime.now().microsecondsSinceEpoch.toString();
var _nextSessionToken = 0;
String _sessionToken(Object source) => _sessionTokens[source] ??=
    '$_sessionNonce:${_nextSessionToken++}';

class _GalleryAccountEpoch {
  var value = 0;
}
final _galleryAccountEpochProvider = Provider<_GalleryAccountEpoch>((ref) {
  final epoch = _GalleryAccountEpoch();
  // Even reconnecting an adapter to an identically named endpoint/account
  // must invalidate a previous read and ambiguous session namespace.
  ref.listen(authProvider, (_, __) => epoch.value++);
  return epoch;
});

bool _needsSessionScope(CloudStorageClient client) {
  // Two decryption keys over the same account/path are different image
  // sources. Reuse would expose a prior key's decrypted cached thumbnail.
  if (client.providerName.endsWith(' (Encrypted)')) return true;
  final name = client.providerName.replaceAll(' (Encrypted)', '').toLowerCase();
  return const {'s3', 'sftp', 'ftp', 'hetzner storage box'}.contains(name);
}

/// Catalog namespaces never store raw account identifiers or endpoint URLs.
/// Identified accounts are stable across app restarts. Anonymous clients and
/// browser-granted folders are session scoped because a same-named source is
/// not proof of the same account or physical directory.
String galleryNamespaceForSource(PanelSource source,
    {String? localScopeId, String? connectionScopeId}) {
  Object identity;
  if (source is LocalPanelSource) {
    identity = ['local', localScopeId ?? (kIsWeb ? _sessionNonce : 'native')];
  } else if (source is RemotePanelSource) {
    final client = source.client;
    final user = client.userId;
    identity = [
      'remote', source.providerName, client.providerName, '${client.runtimeType}',
      user, client.bucketId, client.rootPath,
      // These adapters omit endpoint/port from the shared identity contract.
      // Never reuse another endpoint's images or catalog under default keys.
      if (user == null || user.isEmpty || _needsSessionScope(client))
        [_sessionToken(client), connectionScopeId],
    ];
  } else if (source is ArchivePanelSource) {
    identity = [
      'archive', galleryNamespaceForSource(source.parent,
          localScopeId: localScopeId, connectionScopeId: connectionScopeId),
      source.archivePath,
    ];
  } else {
    // Container views cannot be read through a plain filesystem/cloud client.
    identity = ['unavailable', _sessionToken(source)];
  }
  return sha256.convert(utf8.encode(jsonEncode(identity))).toString();
}

GalleryMediaRequest? tryCaptureGalleryMediaRequest(
    WidgetRef ref, PanelSide side, FileItem file) {
  try { return captureGalleryMediaRequest(ref, side, file); }
  on GalleryMediaException { return null; }
}

/// Resolves the storage that produced this file, regardless of panel position.
/// Capturing is synchronous and performs no filesystem or network reads.
GalleryMediaRequest captureGalleryMediaRequest(
    WidgetRef ref, PanelSide side, FileItem file) {
  final panel = ref.read(panelProvider(side));
  final selectedSource = ref.read(panelSourceProvider(side));
  final local = ref.read(localFileServiceProvider);
  final accountEpoch = ref.read(_galleryAccountEpochProvider);
  Object? localIdentity(String path) => local is LocalFileSourceIdentity
      ? (local as LocalFileSourceIdentity).sourceIdentityForPath(path) : null;
  String namespace(PanelSource source, {Object? localRoot}) =>
      galleryNamespaceForSource(source,
        localScopeId: localRoot != null ? _sessionToken(localRoot)
            : kIsWeb ? _sessionToken(local) : null,
        connectionScopeId: '${_sessionToken(accountEpoch)}:${accountEpoch.value}');
  if (file.isFolder) throw const GalleryMediaException('Choose an image file.');
  if (selectedSource.isContainer) {
    throw const GalleryMediaException('Extract this image from its container to preview it.');
  }
  bool listed() => panel.files?.any((item) => identical(item, file)) ?? false;
  final archive = panel.archiveSource;
  if (archive != null) {
    if (!listed()) throw const GalleryMediaException('Refresh the archive before opening this image.');
    final parentGuard = _captureSourceGuard(ref, archive.parent);
    final localRoot = archive.parent is LocalPanelSource
        ? localIdentity(archive.archivePath) : null;
    bool current() => parentGuard() &&
        (localRoot == null || identical(localIdentity(archive.archivePath), localRoot)) &&
        panel.archiveSource?.archivePath == archive.archivePath &&
        identical(panel.archiveSource?.parent, archive.parent);
    return GalleryMediaRequest(
      file: file,
      namespaceId: namespace(archive, localRoot: localRoot),
      path: file.path ?? p.posix.join(archive.innerPath, file.name),
      isRemote: archive.parent is RemotePanelSource,
      isArchive: true,
      isCurrent: current,
      // A reopened/changed archive must not reuse an old member thumbnail.
      revisionSalt: _sessionToken(archive.parent),
      readBytes: (limit) async {
        if (!current()) throw const GalleryMediaException('This archive is no longer open.');
        return panel.readArchiveMember(file, maxBytes: limit);
      },
    );
  }

  final origin = panel.originForFile(file);
  final source = origin?.source;
  // Search/collection rows and branch-view entries carry verified origins.
  // A panel dropdown cannot authorize reading an unresolved or stale row.
  if (source == null) {
    throw const GalleryMediaException(
      'Refresh this folder before previewing. The image source could not be verified.',
    );
  }
  final accountGuard = _captureSourceGuard(ref, source);
  bool current() => origin!.isCurrent && accountGuard();

  if (source is LocalPanelSource) {
    final path = file.path ?? file.xFile?.path ??
        (kIsWeb ? p.posix : p.context).join(source.path, file.name);
    final localRoot = localIdentity(path);
    return GalleryMediaRequest(
      file: file,
      namespaceId: namespace(source, localRoot: localRoot),
      path: path,
      isCurrent: () => current() &&
          (localRoot == null || identical(localIdentity(path), localRoot)),
      // Browser File objects are snapshots; a fresh listing invalidates the
      // preview even on platforms which omit last-modified metadata.
      revisionSalt: kIsWeb || !GalleryMediaRequest.hasRevisionMetadata(file)
          ? _sessionToken(file) : '',
      readBytes: (limit) => local.readFileForEdit(path,
          fileItem: file, maxBytes: limit),
    );
  }
  if (source is! RemotePanelSource) {
    throw const GalleryMediaException('This storage source cannot preview images.');
  }
  final client = source.client;
  final path = file.path ?? p.posix.join(source.path, file.name);
  return GalleryMediaRequest(
    file: file,
    namespaceId: namespace(source),
    path: path,
    isRemote: true,
    isCurrent: current,
    // Some adapters (including SMB listings) have no revision or mtime.
    // A new listing must not reuse same-size, old image bytes indefinitely.
    revisionSalt: GalleryMediaRequest.hasRevisionMetadata(file)
        ? '' : _sessionToken(file),
    readProviderThumbnail: client.supportsThumbnails
        ? () => client.getThumbnail(path).timeout(const Duration(seconds: 30))
        : null,
    readBytes: (limit) => readGalleryRemoteBytes(client, path, file, limit,
        isCurrent: current),
  );
}

bool Function() _captureSourceGuard(WidgetRef ref, PanelSource source) {
  if (source is LocalPanelSource) return () => true;
  if (source is ArchivePanelSource) return _captureSourceGuard(ref, source.parent);
  if (source is! RemotePanelSource) return () => false;
  final client = source.client;
  final userId = client.userId;
  final bucketId = client.bucketId;
  final auth = ref.read(authProvider);
  final isPrimary = identical(auth.client, client);
  final email = isPrimary ? auth.userEmail : null;
  final epoch = ref.read(_galleryAccountEpochProvider);
  final generation = epoch.value;
  return () {
    if (!client.isAuthenticated || client.userId != userId || client.bucketId != bucketId) {
      return false;
    }
    if (!isPrimary) return true;
    final latest = ref.read(authProvider);
    return epoch.value == generation && latest.isConnected &&
        identical(latest.client, client) && latest.userEmail == email;
  };
}

/// Bounded remote read. Require a known size even when streaming support
/// is advertised: some adapters inherit a buffered single-chunk fallback.
/// Actual chunk streams stop at the limit; internally buffered transports
/// receive progress guards, but cannot guarantee a transport-memory bound.
@visibleForTesting
Future<Uint8List> readGalleryRemoteBytes(
    CloudStorageClient client, String path, FileItem file, int maxBytes,
    {required bool Function() isCurrent}) async {
  void checkCurrent() {
    if (!isCurrent()) throw const GalleryMediaException('The image source changed.');
  }
  void checkSize(int size) {
    if (size > maxBytes) {
      throw GalleryMediaException('This image exceeds the ${(maxBytes / (1024 * 1024)).ceil()} MiB preview limit.');
    }
  }
  checkCurrent();
  var size = file.size;
  if (size != null) checkSize(size);
  if (size == null || size < 0) {
    final info = await client.resolvePath(path)
        .timeout(const Duration(seconds: 30));
    size = int.tryParse('${info?['size']}');
    checkCurrent();
    if (size == null || size < 0) {
      throw const GalleryMediaException(
        'The provider did not report this image’s size. Download it before previewing.',
      );
    }
    checkSize(size);
  }
  void checkProgress(int done, int total) {
    checkCurrent();
    checkSize(done);
    checkSize(total);
  }
  if (client.supportsStreaming) {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in client.downloadStream(path,
        onProgress: checkProgress)
        .timeout(const Duration(seconds: 30))) {
      checkCurrent();
      checkSize(builder.length + chunk.length);
      builder.add(chunk);
    }
    checkCurrent();
    return builder.takeBytes();
  }
  final bytes = await client.downloadFileBytes(path,
      onProgress: checkProgress).timeout(const Duration(seconds: 60));
  checkCurrent();
  checkSize(bytes.length);
  return bytes;
}
