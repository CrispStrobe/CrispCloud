/// Installation and authenticated DAV home are separate: a login can be an
/// email alias while the server's principal has an unrelated account ID.
class NextcloudEndpoint {
  NextcloudEndpoint._(this.server, this.davRoot, this.explicitHome);

  final Uri server;
  final Uri davRoot;
  final bool explicitHome;

  static NextcloudEndpoint parse(String value, String username) {
    final uri = Uri.parse(value.trim());
    if (!['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        username.isEmpty) {
      throw const FormatException('Invalid Nextcloud endpoint');
    }
    final parts = uri.pathSegments.where((part) => part.isNotEmpty).toList();
    if (parts.any(
      (part) => part == '.' || part == '..' || part.contains('/'),
    )) {
      throw const FormatException('Invalid Nextcloud installation path');
    }
    final remote = parts.indexOf('remote.php');
    if (remote >= 0) {
      final suffix = parts.sublist(remote + 1);
      final server = _withoutTrailingSlash(_path(uri, parts.take(remote)));
      if (suffix.length == 1 && suffix.first == 'webdav') {
        return NextcloudEndpoint._(server, _path(uri, [...parts, '']), true);
      }
      if (suffix.isNotEmpty && suffix.first == 'dav') {
        if (suffix.length == 1 ||
            (suffix.length == 2 && suffix[1] == 'files')) {
          return _home(server, username);
        }
        if (suffix.length == 3 && suffix[1] == 'files') {
          return NextcloudEndpoint._(server, _path(uri, [...parts, '']), true);
        }
      }
      throw const FormatException('Expected a Nextcloud files DAV URL');
    }
    return _home(_withoutTrailingSlash(_path(uri, parts)), username);
  }

  static Uri _withoutTrailingSlash(Uri uri) =>
      Uri.parse(uri.toString().replaceFirst(RegExp(r'/+$'), ''));

  static Uri _path(Uri uri, Iterable<String> parts) =>
      uri.replace(path: '/${parts.map(Uri.encodeComponent).join('/')}');

  static NextcloudEndpoint _home(Uri server, String username) =>
      NextcloudEndpoint._(
        server,
        _path(server, [
          ...server.pathSegments.where((part) => part.isNotEmpty),
          'remote.php',
          'dav',
          'files',
          username,
          '',
        ]),
        false,
      );

  Uri get discoveryUri => _path(server, [
    ...server.pathSegments.where((part) => part.isNotEmpty),
    'remote.php',
    'dav',
    '',
  ]);

  /// Accept only a principal inside this installation. A response must never
  /// cause credentials to be retried at a different host or installation.
  NextcloudEndpoint? forPrincipal(String href) {
    final principal = discoveryUri.resolve(href);
    final prefix = [
      ...server.pathSegments.where((part) => part.isNotEmpty),
      'remote.php',
      'dav',
      'principals',
      'users',
    ];
    final parts = principal.pathSegments
        .where((part) => part.isNotEmpty)
        .toList();
    if (principal.origin != server.origin ||
        principal.userInfo.isNotEmpty ||
        principal.hasQuery ||
        principal.hasFragment ||
        parts.length != prefix.length + 1 ||
        !_startsWith(parts, prefix)) {
      return null;
    }
    final user = parts.last;
    if (user == '.' ||
        user == '..' ||
        user.contains('/') ||
        user.contains('\\')) {
      return null;
    }
    return _home(server, user);
  }

  NextcloudEndpoint withSavedRoot(String value) {
    final saved = NextcloudEndpoint.parse(value, 'unused');
    if (!saved.explicitHome || saved.server != server) {
      throw const FormatException(
        'Saved DAV home does not match its installation',
      );
    }
    return NextcloudEndpoint._(server, saved.davRoot, explicitHome);
  }

  Uri uriForPath(String path) => _path(davRoot, [
    ...davRoot.pathSegments.where((part) => part.isNotEmpty),
    ...path.split('/').where((part) => part.isNotEmpty),
    if (path == '/' || path.isEmpty) '',
  ]);

  String? relativePath(String href) {
    final uri = davRoot.resolve(href);
    final root = davRoot.pathSegments.where((part) => part.isNotEmpty).toList();
    final parts = uri.pathSegments.where((part) => part.isNotEmpty).toList();
    if (uri.origin != davRoot.origin || !_startsWith(parts, root)) return null;
    return '/${parts.skip(root.length).join('/')}';
  }

  String? get davUserId {
    final parts = davRoot.pathSegments;
    final files = parts.indexOf(
      'files',
      server.pathSegments.where((p) => p.isNotEmpty).length,
    );
    return files >= 0 && files + 1 < parts.length ? parts[files + 1] : null;
  }

  static bool _startsWith(List<String> parts, List<String> prefix) =>
      parts.length >= prefix.length &&
      Iterable<int>.generate(prefix.length)
          .every((index) => parts[index] == prefix[index]);
}
