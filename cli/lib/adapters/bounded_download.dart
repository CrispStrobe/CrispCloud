import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Optional capability for consumers that must bound bytes before buffering.
/// The ordinary storage interface remains unchanged for existing clients.
abstract interface class CliBoundedDownload {
  Future<Uint8List> downloadBytesBounded(
    String remotePath, {
    required int maxBytes,
  });
}

class CliDownloadLimitException implements Exception {
  const CliDownloadLimitException(this.maxBytes);

  final int maxBytes;

  @override
  String toString() => 'The download exceeds the $maxBytes-byte limit.';
}

/// Fetch without forwarding credentials through redirects or buffering an
/// unbounded error body. Closing the client also cancels an oversized stream.
Future<Uint8List> boundedHttpDownload(
  Uri uri, {
  required Map<String, String> headers,
  required int maxBytes,
  http.Client? client,
}) async {
  if (maxBytes < 1) throw ArgumentError.value(maxBytes, 'maxBytes');
  final transport = client ?? http.Client();
  try {
    final request = http.Request('GET', uri)
      ..followRedirects = false
      ..headers.addAll(headers);
    final response = await transport
        .send(request)
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      throw StateError('Download failed (HTTP ${response.statusCode}).');
    }
    if ((response.contentLength ?? 0) > maxBytes) {
      throw CliDownloadLimitException(maxBytes);
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk
        in response.stream.timeout(const Duration(seconds: 60))) {
      if (builder.length + chunk.length > maxBytes) {
        throw CliDownloadLimitException(maxBytes);
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  } finally {
    transport.close();
  }
}
