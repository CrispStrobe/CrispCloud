import 'filen_web_stub.dart' if (dart.library.js_util) 'dart:js_util' as js;
import 'transfer_spool_contract.dart';
import 'web_streaming_service.dart';

TransferSpool sliceSpool(TransferSpool spool, int start, int end) {
  final blob = spool.webUploadBody;
  if (blob == null) throw StateError('The upload has no browser spool.');
  return _Slice(
    js.callMethod(blob, 'slice', [start, end]) as Object,
    end - start,
  );
}

class _Slice implements TransferSpool {
  _Slice(this.webUploadBody, this.length);
  @override
  final Object webUploadBody;
  @override
  final int length;
  @override
  String? get localPath => null;
  @override
  Stream<List<int>> openRead() =>
      WebStreamingService().streamFromBlob(webUploadBody);
  @override
  Future<void> dispose() async {}
}

Future<void> saveDownload(
  Stream<List<int>> source,
  String path, {
  required void Function() checkCurrent,
}) async => throw UnsupportedError('Use browser downloads on the web.');
