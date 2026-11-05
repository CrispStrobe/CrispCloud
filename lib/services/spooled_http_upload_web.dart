import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:universal_html/html.dart' as html;

import 'filen_web_stub.dart' if (dart.library.js_util) 'dart:js_util' as js;
import 'transfer_spool_contract.dart';

/// The default browser HTTP client collects every request into a Uint8List.
/// Passing an OPFS-backed File directly to fetch keeps the upload on disk.
Future<http.Response> uploadSpooledHttpBody(
  Uri uri,
  TransferSpool spool, {
  required String operation,
  required void Function() checkCurrent,
  String method = 'PUT',
  Map<String, String> headers = const {},
  bool allowHttp = false,
  void Function(int, int)? onProgress,
}) async {
  if ((uri.scheme != 'https' && !(allowHttp && uri.scheme == 'http')) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw StateError('$operation requires a secure upload address.');
  }
  final blob = spool.webUploadBody;
  if (blob == null) throw StateError('$operation has no browser file body.');
  if (method != 'PUT' && method != 'POST') {
    throw ArgumentError.value(method, 'method', 'Expected PUT or POST.');
  }
  final uploadHeaders = <String, String>{
    'content-type': 'application/octet-stream',
  };
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == 'content-length') {
      if (int.tryParse(entry.value) != spool.length) {
        throw StateError(
          '$operation upload length does not match the private file.',
        );
      }
      // fetch calculates Content-Length from the File; browsers forbid setting it.
      continue;
    }
    uploadHeaders[entry.key.toLowerCase()] = entry.value;
  }
  checkCurrent();
  final abort = js.callConstructor(
    js.getProperty(html.window, 'AbortController'),
    [],
  );
  final options = js.newObject();
  js.setProperty(options, 'method', method);
  js.setProperty(options, 'headers', js.jsify(uploadHeaders));
  js.setProperty(options, 'body', blob);
  js.setProperty(options, 'redirect', 'error');
  js.setProperty(options, 'credentials', 'omit');
  js.setProperty(options, 'signal', js.getProperty(abort, 'signal'));
  dynamic reader;
  try {
    onProgress?.call(0, spool.length);
    dynamic response;
    try {
      response = await js.promiseToFuture(
        js.callMethod(html.window, 'fetch', [uri.toString(), options]),
      );
    } catch (_) {
      throw StateError('$operation connection failed; completion is unknown.');
    }
    checkCurrent();
    // Keep only the response headers the browser exposes through CORS. In
    // particular, multipart services must expose ETag for verified completion.
    final responseHeaders = <String, String>{};
    final entries = js.callMethod(
      js.getProperty(response, 'headers'),
      'entries',
      [],
    );
    var headerBytes = 0;
    while (true) {
      final next = js.callMethod(entries, 'next', []);
      if (js.getProperty(next, 'done') == true) break;
      final pair = js.getProperty(next, 'value');
      final name = js.getProperty(pair, '0') as String;
      final value = js.getProperty(pair, '1') as String;
      headerBytes += name.length + value.length;
      if (responseHeaders.length >= 256 || headerBytes > 64 * 1024) {
        throw StateError('$operation returned oversized response headers.');
      }
      responseHeaders[name.toLowerCase()] = value;
    }
    final body = js.getProperty(response, 'body');
    final bytes = BytesBuilder(copy: false);
    if (body != null) {
      reader = js.callMethod(body, 'getReader', []);
      while (true) {
        dynamic part;
        try {
          part = await js.promiseToFuture(js.callMethod(reader, 'read', []));
        } catch (_) {
          throw StateError(
            '$operation response was interrupted; completion is unknown.',
          );
        }
        checkCurrent();
        if (js.getProperty(part, 'done') == true) break;
        final chunk = js.getProperty(part, 'value') as Uint8List;
        if (bytes.length + chunk.length > 256 * 1024) {
          throw StateError('$operation returned oversized metadata.');
        }
        bytes.add(chunk);
      }
    }
    final status = (js.getProperty(response, 'status') as num).toInt();
    onProgress?.call(spool.length, spool.length);
    return http.Response.bytes(
      bytes.takeBytes(),
      status,
      headers: responseHeaders,
    );
  } finally {
    js.callMethod(abort, 'abort', []);
    if (reader != null) {
      try {
        await js.promiseToFuture(js.callMethod(reader, 'cancel', []));
      } catch (_) {
        // Preserve the response/account error.
      }
    }
  }
}
