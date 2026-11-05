import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'bounded_transfer_stream.dart';

/// Small provider-specific file actions retain the selected account throughout
/// the request, response and every follow-up mutation. File bodies are streamed;
/// JSON and comparison text have explicit memory limits.
class FileActionRequests {
  FileActionRequests({required this.ensureCurrent, http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  final void Function() ensureCurrent;
  final http.Client _client;
  final bool _ownsClient;
  bool _closed = false;

  void check() {
    if (_closed) throw StateError('The file action was closed.');
    ensureCurrent();
  }

  void close() {
    _closed = true;
    if (_ownsClient) _client.close();
  }

  Future<http.StreamedResponse> open(http.Request request) async {
    var next = request;
    for (var redirects = 0; ; redirects++) {
      check();
      next.followRedirects = false;
      final http.StreamedResponse response;
      try {
        response = await _client.send(next);
      } on http.ClientException {
        throw StateError('The provider request was interrupted.');
      }
      try {
        check();
      } catch (_) {
        await response.stream.listen(null).cancel();
        rethrow;
      }
      if (next.method != 'GET' ||
          !const [301, 302, 303, 307, 308].contains(response.statusCode)) {
        return http.StreamedResponse(
          _guarded(response.stream),
          response.statusCode,
          headers: response.headers,
          contentLength: response.contentLength,
        );
      }
      await response.stream.listen(null).cancel();
      final location = response.headers['location'];
      if (redirects >= 5 || location == null) {
        throw StateError('The provider returned an invalid download redirect.');
      }
      final target = next.url.resolve(location);
      if (target.scheme != 'https' ||
          target.host.isEmpty ||
          target.userInfo.isNotEmpty) {
        throw StateError('The provider returned an unsafe download redirect.');
      }
      // Signed download URLs can use another host. Never forward an account
      // token or provider-specific authentication header across origins.
      next = http.Request('GET', target)
        ..headers.addAll(target.origin == next.url.origin ? next.headers : {});
    }
  }

  Stream<List<int>> _guarded(Stream<List<int>> source) async* {
    check();
    try {
      await for (final bytes in source) {
        check();
        yield bytes;
      }
      check();
    } on http.ClientException {
      throw StateError('The provider response was interrupted.');
    }
  }

  Future<http.Response> request(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    Object? body,
    int maxBytes = 256 * 1024,
  }) async {
    final request = http.Request(method, uri)..headers.addAll(headers);
    if (body is String) {
      request.body = body;
    } else if (body is List<int>) {
      request.bodyBytes = body;
    } else if (body != null) {
      throw ArgumentError.value(body, 'body');
    }
    final response = await open(request);
    final data = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      if (data.length + chunk.length > maxBytes) {
        throw StateError('The file action response exceeds its size limit.');
      }
      data.add(chunk);
    }
    return http.Response.bytes(
      data.takeBytes(),
      response.statusCode,
      headers: response.headers,
    );
  }

  /// Drive revisions have no promote endpoint. Restore the exact file ID using
  /// resumable upload parts, validating EOF before the final part is committed.
  /// https://developers.google.com/workspace/drive/api/guides/manage-uploads
  Future<void> restoreDriveRevision({
    required String fileId,
    required String revisionId,
    required String token,
    required int? expectedLength,
  }) async {
    final headers = {'Authorization': 'Bearer $token'};
    final download = await open(
      http.Request(
        'GET',
        Uri(
          scheme: 'https',
          host: 'www.googleapis.com',
          pathSegments: [
            'drive',
            'v3',
            'files',
            fileId,
            'revisions',
            revisionId,
          ],
          queryParameters: {'alt': 'media'},
        ),
      )..headers.addAll(headers),
    );
    final length = expectedLength ?? download.contentLength;
    if (download.statusCode != 200 || length == null || length < 0) {
      await download.stream.listen(null).cancel();
      throw StateError(
        'The revision could not be downloaded with a verified length.',
      );
    }
    if (length == 0) {
      await validatedTransferParts(download.stream, 0, 1).drain<void>();
      final response = await request(
        'PATCH',
        Uri(
          scheme: 'https',
          host: 'www.googleapis.com',
          pathSegments: ['upload', 'drive', 'v3', 'files', fileId],
          queryParameters: {'uploadType': 'media', 'fields': 'id,size'},
        ),
        headers: {...headers, 'Content-Type': 'application/octet-stream'},
        body: const <int>[],
      );
      _checkDriveCompletion(response, fileId, 0);
      return;
    }
    http.Response session;
    try {
      session = await request(
        'PATCH',
        Uri(
          scheme: 'https',
          host: 'www.googleapis.com',
          pathSegments: ['upload', 'drive', 'v3', 'files', fileId],
          queryParameters: {'uploadType': 'resumable', 'fields': 'id,size'},
        ),
        headers: {
          ...headers,
          'Content-Type': 'application/json; charset=UTF-8',
          'X-Upload-Content-Type': 'application/octet-stream',
          'X-Upload-Content-Length': '$length',
        },
        body: '{}',
      );
      if (session.statusCode != 200 && session.statusCode != 201) {
        throw StateError(
          'The provider could not start revision restoration (${session.statusCode}).',
        );
      }
      final location = Uri.tryParse(session.headers['location'] ?? '');
      if (location == null ||
          location.scheme != 'https' ||
          location.userInfo.isNotEmpty ||
          location.port != 443 ||
          !(location.host == 'googleapis.com' ||
              location.host.endsWith('.googleapis.com'))) {
        throw StateError('The provider returned an invalid upload session.');
      }
      var offset = 0;
      await for (final part in validatedTransferParts(
        download.stream,
        length,
        2 * 1024 * 1024,
      )) {
        final end = offset + part.length;
        final response = await request(
          'PUT',
          location,
          headers: {
            ...headers,
            'Content-Type': 'application/octet-stream',
            'Content-Range': 'bytes $offset-${end - 1}/$length',
          },
          body: part,
        );
        if (end == length) {
          _checkDriveCompletion(response, fileId, length);
        } else {
          final range = RegExp(r'^bytes=0-(\d+)$')
              .firstMatch(response.headers['range'] ?? '');
          if (response.statusCode != 308 ||
              range == null ||
              int.tryParse(range.group(1)!) != end - 1) {
            throw StateError(
              'The provider did not acknowledge the restored range.',
            );
          }
        }
        offset = end;
      }
    } catch (_) {
      // Cancellation before the upload starts must release the unread GET.
      // Once consumed, its async iterator already cancels on failure.
      try {
        await download.stream.listen(null).cancel();
      } catch (_) {}
      rethrow;
    }
  }

  void _checkDriveCompletion(
    http.Response response,
    String fileId,
    int length,
  ) {
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw StateError(
        'The provider did not confirm revision restoration (${response.statusCode}).',
      );
    }
    final metadata = json.decode(response.body) as Map<String, dynamic>;
    if (metadata['id'] != fileId ||
        int.tryParse('${metadata['size']}') != length) {
      throw StateError(
        'The restored file identity or length could not be verified.',
      );
    }
  }
}
