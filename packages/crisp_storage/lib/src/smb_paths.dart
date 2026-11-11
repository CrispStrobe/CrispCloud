import 'remote_client.dart';

/// Shared URL confinement for both SMB engines.
class SmbPaths {
  final RemoteConnection connection;
  SmbPaths(this.connection);

  /// Convert a share-root-relative app path into a confined server URL.
  String urlForPath(String path) {
    final parts = path.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.any(
      (s) => s == '.' || s == '..' || s.contains(r'\') || s.contains('\u0000'),
    )) {
      throw const RemoteFormatException(
        'Invalid SMB path.',
        RemoteErrorCode.invalidPath,
        arguments: {'protocol': 'SMB'},
      );
    }
    return connection.url
        .replace(
          path: '${Uri.decodeComponent(connection.url.path)}${parts.join('/')}',
        )
        .toString();
  }

  String path(String path) {
    final base = connection.url;
    final raw = Uri.parse(path);
    if (raw.pathSegments.any(
      (s) =>
          s == '.' ||
          s == '..' ||
          s.contains('/') ||
          s.contains(r'\') ||
          s.contains('\u0000'),
    )) {
      throw const RemoteException(
        'Invalid SMB path.',
        code: RemoteErrorCode.invalidPath,
        arguments: {'protocol': 'SMB'},
      );
    }
    final target = base.resolve(path.isEmpty ? base.toString() : path);
    final parts = target.pathSegments;
    if (target.scheme != base.scheme ||
        target.host != base.host ||
        target.port != base.port ||
        target.userInfo.isNotEmpty ||
        target.hasQuery ||
        target.hasFragment ||
        !target.path.startsWith(base.path) ||
        parts.any(
          (s) =>
              s == '.' ||
              s == '..' ||
              s.contains('/') ||
              s.contains(r'\') ||
              s.contains('\u0000'),
        )) {
      throw const RemoteException(
        'The SMB path is outside this connection’s root.',
        code: RemoteErrorCode.outsideRoot,
        arguments: {'protocol': 'SMB'},
      );
    }
    return parts.skip(1).where((s) => s.isNotEmpty).join('/');
  }

  String get root =>
      connection.url.pathSegments.skip(1).where((s) => s.isNotEmpty).join('/');
  String relative(String value) {
    final full = path(value);
    return root.isEmpty
        ? full
        : full == root
        ? ''
        : full.substring(root.length + 1);
  }
}
