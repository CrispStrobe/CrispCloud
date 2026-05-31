// lib/adapters/webdav_adapter.dart
//
// Pure-Dart WebDAV adapter for the crisp CLI.
// Uses only package:http (no Flutter, no webdav_client package which has
// a transitive flutter dep). Implements the subset of WebDAV we need:
// PROPFIND, GET, PUT, DELETE, MKCOL, MOVE.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../config/cli_config.dart';
import 'cli_storage_client.dart';

class WebDavCliAdapter implements CliStorageClient {
  final String _baseUrl; // e.g. https://dav.example.com (no trailing slash)
  final String _username;
  final String _password;

  late final Map<String, String> _authHeader;

  WebDavCliAdapter({
    required String baseUrl,
    required String username,
    required String password,
  })  : _baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
        _username = username,
        _password = password {
    final encoded = base64Encode(utf8.encode('$_username:$_password'));
    _authHeader = {'Authorization': 'Basic $encoded'};
  }

  factory WebDavCliAdapter.fromConfig(Map<String, dynamic> cfg) {
    final username = cfg['username'] as String?;
    final password = cfg['password'] as String?;
    final host = cfg['host'] as String?;

    if (username == null || password == null || host == null) {
      throw CliConfigException(
        'WebDAV provider config missing required fields: username, password, host',
      );
    }
    return WebDavCliAdapter(
      baseUrl: host,
      username: username,
      password: password,
    );
  }

  /// Parse the identity string used with `crisp connect`:
  ///   user@https://dav.example.com
  static Map<String, String> parseIdentity(String identity, String password) {
    final splitIndex = identity.lastIndexOf('@http');
    if (splitIndex < 0) {
      throw CliConfigException(
        'Invalid WebDAV identity format. Expected: username@https://host',
      );
    }
    final username = identity.substring(0, splitIndex);
    final host = identity.substring(splitIndex + 1);
    return {
      'username': username,
      'password': password,
      'host': host,
    };
  }

  @override
  String get providerName => 'WebDAV';

  String _url(String remotePath) {
    final clean = remotePath.startsWith('/') ? remotePath : '/$remotePath';
    return '$_baseUrl$clean';
  }

  Map<String, String> get _headers => {
        ..._authHeader,
        'Accept': '*/*',
      };

  // ---------------------------------------------------------------------------
  // PROPFIND helper — parses a basic WebDAV multi-status response
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> _propfind(String remotePath, {int depth = 1}) async {
    final response = await http.Client().send(
      http.Request('PROPFIND', Uri.parse(_url(remotePath)))
        ..headers.addAll({
          ..._headers,
          'Depth': depth.toString(),
          'Content-Type': 'application/xml',
        })
        ..body = '''<?xml version="1.0" encoding="utf-8"?>
<propfind xmlns="DAV:">
  <prop>
    <displayname/>
    <getcontentlength/>
    <getlastmodified/>
    <resourcetype/>
  </prop>
</propfind>''',
    );

    final body = await http.Response.fromStream(response);
    if (body.statusCode != 207 && body.statusCode != 200) {
      throw Exception(
        'WebDAV PROPFIND failed (HTTP ${body.statusCode}): ${body.body}',
      );
    }

    return _parseMultiStatus(body.body, remotePath);
  }

  List<Map<String, dynamic>> _parseMultiStatus(String xml, String basePath) {
    final results = <Map<String, dynamic>>[];
    // Extract each <response> block
    final responseRe = RegExp(r'<[Dd]:[Rr]esponse>(.*?)</[Dd]:[Rr]esponse>', dotAll: true);
    for (final rm in responseRe.allMatches(xml)) {
      final block = rm.group(1)!;

      // href — decode the path
      final hrefM = RegExp(r'<[Dd]:[Hh]ref>(.*?)</[Dd]:[Hh]ref>').firstMatch(block);
      if (hrefM == null) continue;
      final href = Uri.decodeComponent(hrefM.group(1)!.trim());

      // resourcetype — contains <collection/> if directory
      final rtM = RegExp(
        r'<[Dd]:[Rr]esourcetype>(.*?)</[Dd]:[Rr]esourcetype>',
        dotAll: true,
      ).firstMatch(block);
      final isDir = rtM != null && rtM.group(1)!.contains('collection');

      // size
      final sizeM = RegExp(r'<[Dd]:[Gg]etcontentlength>(.*?)</[Dd]:[Gg]etcontentlength>')
          .firstMatch(block);
      final size = sizeM != null ? int.tryParse(sizeM.group(1)!.trim()) : null;

      // modified
      final modM = RegExp(r'<[Dd]:[Gg]etlastmodified>(.*?)</[Dd]:[Gg]etlastmodified>')
          .firstMatch(block);
      final modified = modM?.group(1)?.trim();

      // name: last non-empty path segment of href
      final segments = href.split('/').where((s) => s.isNotEmpty).toList();
      final name = segments.isNotEmpty ? segments.last : '';

      results.add({
        'href': href,
        'name': name,
        'isDir': isDir,
        'size': size,
        'modified': modified,
      });
    }
    return results;
  }

  // ---------------------------------------------------------------------------
  // CliStorageClient implementation
  // ---------------------------------------------------------------------------

  @override
  Future<List<CliFileItem>> list(String remotePath) async {
    final entries = await _propfind(remotePath, depth: 1);
    final items = <CliFileItem>[];

    // Skip the first entry — it's the directory itself
    final normalizedBase = remotePath.endsWith('/') ? remotePath : '$remotePath/';

    for (final e in entries) {
      final href = e['href'] as String;
      // Skip the base dir itself
      if (_hrefMatchesBase(href, normalizedBase)) continue;

      items.add(CliFileItem(
        name: e['name'] as String,
        path: href,
        isDirectory: e['isDir'] as bool,
        size: e['size'] as int?,
        modifiedAt: e['modified'] as String?,
      ));
    }
    return items;
  }

  bool _hrefMatchesBase(String href, String basePath) {
    // Strip host prefix from href if present
    final hrefPath = Uri.tryParse(href)?.path ?? href;
    final normalized = hrefPath.endsWith('/') ? hrefPath : '$hrefPath/';
    final baseNorm =
        basePath.endsWith('/') ? basePath : '$basePath/';
    return normalized == baseNorm || hrefPath == basePath.replaceAll(RegExp(r'/$'), '');
  }

  @override
  Future<void> upload(
    List<int> data,
    String fileName,
    String remoteDir, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final remotePath = p.posix.join(remoteDir, fileName);
    final response = await http.put(
      Uri.parse(_url(remotePath)),
      headers: {
        ..._headers,
        'Content-Type': 'application/octet-stream',
        'Content-Length': data.length.toString(),
      },
      body: Uint8List.fromList(data),
    );

    if (response.statusCode != 200 &&
        response.statusCode != 201 &&
        response.statusCode != 204) {
      throw Exception(
        'WebDAV upload failed (HTTP ${response.statusCode}): ${response.body}',
      );
    }
    onProgress?.call(data.length, data.length);
  }

  @override
  Future<List<int>> downloadBytes(String remotePath) async {
    final response = await http.get(
      Uri.parse(_url(remotePath)),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception(
        'WebDAV download failed (HTTP ${response.statusCode}): ${response.body}',
      );
    }
    return response.bodyBytes;
  }

  @override
  Future<void> download(
    String remotePath,
    String localPath, {
    void Function(int received, int total)? onProgress,
  }) async {
    final bytes = await downloadBytes(remotePath);
    await File(localPath).writeAsBytes(bytes);
    onProgress?.call(bytes.length, bytes.length);
  }

  @override
  Future<void> createDirectory(String remotePath) async {
    final response = await http.Client().send(
      http.Request('MKCOL', Uri.parse(_url(remotePath)))
        ..headers.addAll(_headers),
    );
    final status = response.statusCode;
    if (status != 201 && status != 405 /* already exists */) {
      throw Exception('WebDAV MKCOL failed (HTTP $status)');
    }
  }

  @override
  Future<void> delete(String remotePath) async {
    final response = await http.delete(
      Uri.parse(_url(remotePath)),
      headers: _headers,
    );
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception(
        'WebDAV delete failed (HTTP ${response.statusCode}): ${response.body}',
      );
    }
  }

  @override
  Future<void> move(String sourcePath, String targetPath) async {
    final destination = _url(targetPath);
    final response = await http.Client().send(
      http.Request('MOVE', Uri.parse(_url(sourcePath)))
        ..headers.addAll({
          ..._headers,
          'Destination': destination,
          'Overwrite': 'T',
        }),
    );
    final status = response.statusCode;
    if (status != 201 && status != 204) {
      throw Exception('WebDAV MOVE failed (HTTP $status)');
    }
  }

  @override
  Future<CliFileItem?> stat(String remotePath) async {
    try {
      final entries = await _propfind(remotePath, depth: 0);
      if (entries.isEmpty) return null;
      final e = entries.first;
      return CliFileItem(
        name: e['name'] as String,
        path: remotePath,
        isDirectory: e['isDir'] as bool,
        size: e['size'] as int?,
        modifiedAt: e['modified'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String> share(String remotePath, {Duration? expires}) {
    throw UnsupportedError(
      'WebDAV does not have a standard share-link API. '
      'If your server supports Nextcloud/ownCloud sharing, use their web UI.',
    );
  }

  @override
  Future<void> dispose() async {}
}
