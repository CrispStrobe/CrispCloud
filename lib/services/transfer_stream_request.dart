import 'package:http/http.dart' as http;

/// A one-shot request body consumed with the transport's backpressure. It avoids
/// filling a StreamedRequest controller before the socket is ready to read.
/// Browser callers must use a file-backed request because BrowserClient buffers
/// request streams; this class is for native transports and bounded small parts.
class TransferStreamRequest extends http.BaseRequest {
  TransferStreamRequest(super.method, super.url, this.body, int length) {
    if (length < 0) throw ArgumentError.value(length, 'length');
    contentLength = length;
    followRedirects = false;
  }
  final Stream<List<int>> body;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(body);
  }
}
