import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'bounded_http_transfer.dart';
import 'bounded_transfer_stream.dart';
import 'conditional_file_publication.dart';

/// Dropbox's revision-update publication, separate from compatibility uploads.
/// Every operation captures one token and verifies its immutable account ID.
/// No retry can silently switch the credentials of an in-flight publication.
class DropboxFilePublication implements ConditionalFilePublication {
  const DropboxFilePublication({required this.accessToken, this.now});
  final Future<String> Function() accessToken;
  final DateTime Function()? now;
  static const _block = 4 * 1024 * 1024;
  static const _timeout = Duration(seconds: 30);

  static Never _fail(FilePublicationFailure failure) =>
      throw FilePublicationException(failure);

  void Function() _bounded(void Function() checkCurrent) {
    final deadline = (now?.call() ?? DateTime.now()).add(
      const Duration(minutes: 2),
    );
    return () {
      checkCurrent();
      if (!(now?.call() ?? DateTime.now()).isBefore(deadline)) {
        _fail(FilePublicationFailure.unavailable);
      }
    };
  }

  static String _path(String value) {
    if (!p.posix.isAbsolute(value) ||
        p.posix.normalize(value) != value ||
        value == '/' ||
        value.length > 4096 ||
        value.contains('\u0000')) {
      _fail(FilePublicationFailure.invalid);
    }
    return value;
  }

  static String _header(Object value) {
    final result = StringBuffer();
    for (final unit in jsonEncode(value).codeUnits) {
      result.write(
        unit >= 0x7f
            ? '\\u${unit.toRadixString(16).padLeft(4, '0')}'
            : String.fromCharCode(unit),
      );
    }
    return result.toString();
  }

  static Map<String, dynamic> _json(http.Response response) {
    try {
      final value = jsonDecode(response.body);
      if (value is Map<String, dynamic>) return value;
    } on FormatException {
      /* Bounded public error below. */
    }
    _fail(FilePublicationFailure.unavailable);
  }

  Future<String> _token(void Function() checkCurrent) async {
    checkCurrent();
    final token = await accessToken();
    checkCurrent();
    if (token.isEmpty) _fail(FilePublicationFailure.unavailable);
    return token;
  }

  static bool _revisionConflict(http.Response response) {
    if (response.statusCode != 409) return false;
    try {
      final data = jsonDecode(response.body);
      final error = data is Map ? data['error'] : null;
      final path = error is Map ? error['path'] : null;
      return error is Map &&
          error['.tag'] == 'path' &&
          path is Map &&
          path['.tag'] == 'conflict';
    } on FormatException {
      return false;
    }
  }

  Future<http.Response> _rpc(
    http.Client client,
    String token,
    String route,
    Object? body,
    void Function() checkCurrent,
  ) async {
    final request =
        http.Request('POST', Uri.https('api.dropboxapi.com', '/2$route'))
          ..followRedirects = false
          ..headers.addAll({
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          })
          ..body = jsonEncode(body);
    checkCurrent();
    final response = await sendTransferRequest(
      client,
      request,
      operation: 'Dropbox file review',
    ).timeout(_timeout);
    checkCurrent();
    if (response.statusCode == 409) _fail(FilePublicationFailure.conflict);
    if (response.statusCode != 200) _fail(FilePublicationFailure.unavailable);
    return response;
  }

  Future<String> _account(
    http.Client client,
    String token,
    void Function() checkCurrent,
  ) async {
    final data = _json(
      await _rpc(
        client,
        token,
        '/users/get_current_account',
        null,
        checkCurrent,
      ),
    );
    final id = data['account_id'];
    if (id is! String || !id.startsWith('dbid:') || id.length > 512) {
      _fail(FilePublicationFailure.unavailable);
    }
    return sha256.convert(utf8.encode('dropbox-account:$id')).toString();
  }

  static FilePublicationVersion _metadata(
    Map<String, dynamic> data,
    String account,
    String path, {
    bool requireFileTag = true,
  }) {
    final id = data['id'], rev = data['rev'], length = data['size'];
    final hash = data['content_hash'], lower = data['path_lower'];
    if ((requireFileTag && data['.tag'] != 'file') ||
        data['is_downloadable'] == false ||
        data['symlink_info'] != null ||
        data['sharing_info'] is Map &&
            (data['sharing_info'] as Map)['read_only'] == true ||
        id is! String ||
        !id.startsWith('id:') ||
        rev is! String ||
        !RegExp(r'^[0-9a-f]{9,}$').hasMatch(rev) ||
        length is! int ||
        hash is! String ||
        lower is! String ||
        lower != path.toLowerCase()) {
      _fail(FilePublicationFailure.changed);
    }
    final version = FilePublicationVersion(
      accountIdentity: account,
      path: lower,
      objectId: id,
      revision: rev,
      length: length,
      contentHash: hash,
    );
    version.validate();
    return version;
  }

  Future<FilePublicationVersion> _inspect(
    http.Client client,
    String token,
    String account,
    String path,
    void Function() checkCurrent,
  ) async => _metadata(
    _json(
      await _rpc(client, token, '/files/get_metadata', {
        'path': path,
        'include_deleted': false,
      }, checkCurrent),
    ),
    account,
    path,
  );

  @override
  Future<FilePublicationVersion> inspectForPublication(
    String path, {
    required void Function() checkCurrent,
  }) async {
    checkCurrent = _bounded(checkCurrent);
    _path(path);
    final token = await _token(checkCurrent);
    final client = http.Client();
    try {
      final account = await _account(client, token, checkCurrent);
      return await _inspect(client, token, account, path, checkCurrent);
    } finally {
      client.close();
    }
  }

  @override
  Stream<List<int>> readForPublication(
    FilePublicationVersion version, {
    required void Function() checkCurrent,
  }) async* {
    checkCurrent = _bounded(checkCurrent);
    version.validate();
    final token = await _token(checkCurrent);
    final client = http.Client();
    try {
      if (await _account(client, token, checkCurrent) !=
          version.accountIdentity) {
        _fail(FilePublicationFailure.changed);
      }
    } finally {
      client.close();
    }
    final hashes = <int>[];
    final stream = streamHttpDownload(
      Uri.https('content.dropboxapi.com', '/2/files/download'),
      operation: 'Dropbox revision download',
      headers: {
        'Authorization': 'Bearer $token',
        'Dropbox-API-Arg': _header({'path': 'rev:${version.revision}'}),
      },
      followRedirects: false,
      checkCurrent: checkCurrent,
      responseLength: (headers) {
        final raw = jsonDecode(headers['dropbox-api-result'] ?? '{}');
        if (raw is! Map<String, dynamic> ||
            _metadata(
                  raw,
                  version.accountIdentity,
                  version.path,
                  requireFileTag: false,
                ) !=
                version) {
          _fail(FilePublicationFailure.changed);
        }
        return version.length;
      },
    ).timeout(_timeout);
    await for (final part in transferParts(stream, _block)) {
      checkCurrent();
      hashes.addAll(sha256.convert(part).bytes);
      yield part;
    }
    checkCurrent();
    if (sha256.convert(hashes).toString() != version.contentHash) {
      _fail(FilePublicationFailure.changed);
    }
  }

  @override
  Future<FilePublicationVersion> publishFileVersion(
    FilePublicationVersion expected,
    Stream<List<int>> contents, {
    required int length,
    required void Function() checkCurrent,
    required Future<void> Function(String contentHash) prepareCommit,
  }) async {
    checkCurrent = _bounded(checkCurrent);
    expected.validate();
    if (length < 0 || length > conditionalFilePublicationLimit) {
      _fail(FilePublicationFailure.invalid);
    }
    final token = await _token(checkCurrent);
    final client = http.Client();
    var commitStarted = false;
    Future<http.Response> send(
      String route,
      Object args,
      List<int> bytes, {
      bool commit = false,
    }) async {
      final request =
          http.Request(
              'POST',
              Uri.https(
                'content.dropboxapi.com',
                '/2/files/upload_session/$route',
              ),
            )
            ..followRedirects = false
            ..headers.addAll({
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/octet-stream',
              'Dropbox-API-Arg': _header(args),
            })
            ..bodyBytes = bytes;
      checkCurrent();
      if (commit) commitStarted = true;
      final response = await sendTransferRequest(
        client,
        request,
        operation: 'Dropbox conditional publication',
      ).timeout(_timeout);
      if (commit && _revisionConflict(response)) {
        commitStarted = false;
        _fail(FilePublicationFailure.conflict);
      }
      checkCurrent();
      if (response.statusCode != 200) _fail(FilePublicationFailure.unavailable);
      return response;
    }

    try {
      final account = await _account(client, token, checkCurrent);
      if (account != expected.accountIdentity) {
        _fail(FilePublicationFailure.changed);
      }
      if (await _inspect(client, token, account, expected.path, checkCurrent) !=
          expected) {
        _fail(FilePublicationFailure.conflict);
      }
      final session = _json(
        await send('start', {'close': false}, const []),
      )['session_id'];
      if (session is! String || session.isEmpty || session.length > 1024) {
        _fail(FilePublicationFailure.unavailable);
      }
      final hashes = <int>[];
      var offset = 0;
      await for (final part in validatedTransferParts(
        contents
            .map((chunk) {
              checkCurrent();
              return chunk;
            })
            .timeout(_timeout),
        length,
        _block,
      )) {
        hashes.addAll(sha256.convert(part).bytes);
        await send('append_v2', {
          'cursor': {'session_id': session, 'offset': offset},
          'close': false,
          // This route's hash covers this request's bytes, not the whole session.
          'content_hash': sha256.convert(sha256.convert(part).bytes).toString(),
        }, part);
        offset += part.length;
      }
      final contentHash = sha256.convert(hashes).toString();
      // Recheck both object and revision immediately before durable review.
      if (await _inspect(client, token, account, expected.path, checkCurrent) !=
          expected) {
        _fail(FilePublicationFailure.conflict);
      }
      await prepareCommit(contentHash);
      checkCurrent();
      final response = await send(
        'finish',
        {
          'cursor': {'session_id': session, 'offset': offset},
          'commit': {
            'path': expected.path,
            'mode': {'.tag': 'update', 'update': expected.revision},
            'autorename': false,
            'strict_conflict': true,
            'mute': false,
          },
          'content_hash': sha256.convert(const <int>[]).toString(),
        },
        const [],
        commit: true,
      );
      final result = _metadata(
        _json(response),
        account,
        expected.path,
        requireFileTag: false,
      );
      if (!result.sameObject(expected) ||
          result.length != length ||
          result.contentHash != contentHash) {
        _fail(FilePublicationFailure.uncertain);
      }
      return result;
    } catch (error) {
      if (commitStarted) _fail(FilePublicationFailure.uncertain);
      rethrow;
    } finally {
      // Uncommitted sessions expire. Never compensate by deleting the original.
      client.close();
    }
  }
}
