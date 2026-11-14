import 'dart:async';

import 'package:http/http.dart' as http;

import '../transfer_bandwidth.dart';

const _browserTransport =
    bool.fromEnvironment('dart.library.js_interop') ||
    bool.fromEnvironment('dart.library.html');

/// Binds the complete finalized body at the HTTP client's handoff boundary.
/// This includes buffered parts and multipart framing after preparation or
/// encryption. The explicit context was captured by the calling operation;
/// finalizing this request in another zone cannot adopt that zone's job.
///
/// BrowserClient collects the body before fetch. That path is reported as
/// unsupported and retains its ordinary delivery; it is not upload pacing.
http.BaseRequest bindHttpTransferBandwidth(
  http.BaseRequest request,
  TransferBandwidthContext? context,
) => context == null ? request : _BandwidthRequest(request, context);

class _BandwidthRequest extends http.BaseRequest implements http.Abortable {
  _BandwidthRequest(this._request, this._context)
    : abortTrigger = _abortSignal(_request, _context),
      super(_request.method, _request.url) {
    followRedirects = _request.followRedirects;
    maxRedirects = _request.maxRedirects;
    persistentConnection = _request.persistentConnection;
    contentLength = _request.contentLength;
    headers.addAll(_request.headers);
  }

  final http.BaseRequest _request;
  final TransferBandwidthContext _context;

  @override
  final Future<void>? abortTrigger;

  static Future<void> _abortSignal(
    http.BaseRequest request,
    TransferBandwidthContext context,
  ) {
    final original = request is http.Abortable ? request.abortTrigger : null;
    return original == null
        ? context.cancellationFuture
        : Future.any([original, context.cancellationFuture]);
  }

  @override
  http.ByteStream finalize() {
    // MultipartRequest determines its boundary and headers during finalize.
    // Copy the finalized metadata before freezing this transport request.
    final body = _request.finalize();
    contentLength = _request.contentLength;
    headers
      ..clear()
      ..addAll(_request.headers);
    super.finalize();
    if (contentLength == 0) return body;
    return http.ByteStream(
      _context.bind(
        body,
        direction: TransferBandwidthDirection.upload,
        supported: !_browserTransport,
      ),
    );
  }
}
