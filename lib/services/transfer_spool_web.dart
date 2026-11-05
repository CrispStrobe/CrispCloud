import 'package:universal_html/html.dart' as html;
import 'package:uuid/uuid.dart';

import 'bounded_transfer_stream.dart';
import 'filen_web_stub.dart' if (dart.library.js_util) 'dart:js_util' as js;
import 'log_service.dart';
import 'transfer_spool_contract.dart';
import 'web_streaming_service.dart';

Future<TransferSpool> createTransferSpool(
  Stream<List<int>> source, {
  int? expectedLength,
  int? maxBytes,
  Future<void> Function()? checkpoint,
}) async {
  final storage = js.getProperty(html.window.navigator, 'storage');
  if (storage == null || !js.hasProperty(storage, 'getDirectory')) {
    throw UnsupportedError(
      'This browser cannot spool unknown-size transfers. Use a source with a known size or a browser with private file storage.',
    );
  }
  final root = await js.promiseToFuture(
    js.callMethod(storage, 'getDirectory', []),
  );
  final name = 'crisp-transfer-spool-${const Uuid().v4()}';
  final create = js.newObject();
  js.setProperty(create, 'create', true);
  final file = await js.promiseToFuture(
    js.callMethod(root, 'getFileHandle', [name, create]),
  );
  dynamic writable;
  var length = 0;
  try {
    writable = await js.promiseToFuture(
      js.callMethod(file, 'createWritable', []),
    );
    await for (final chunk in transferParts(source, 64 * 1024)) {
      await checkpoint?.call();
      length += chunk.length;
      if ((maxBytes != null && length > maxBytes) ||
          (expectedLength != null && length > expectedLength)) {
        throw StateError('Temporary transfer data exceeds its size limit.');
      }
      await js.promiseToFuture(js.callMethod(writable, 'write', [chunk]));
    }
    if (expectedLength != null && length != expectedLength) {
      throw StateError('The source length changed while spooling.');
    }
    await js.promiseToFuture(js.callMethod(writable, 'close', []));
    writable = null;
    return _WebTransferSpool(root, file, name, length);
  } catch (_) {
    if (writable != null) {
      try {
        await js.promiseToFuture(js.callMethod(writable, 'abort', []));
      } catch (_) {
        /* Preserve the source/quota error. */
      }
    }
    await _remove(root, name);
    rethrow;
  }
}

Future<void> _remove(dynamic root, String name) async {
  try {
    await js.promiseToFuture(js.callMethod(root, 'removeEntry', [name]));
  } catch (error, stack) {
    const Log('TransferSpool')
        .warn('Could not remove a temporary browser spool', error, stack);
  }
}

class _WebTransferSpool implements TransferSpool {
  _WebTransferSpool(this.root, this.file, this.name, this.length);
  final dynamic root;
  final dynamic file;
  final String name;
  @override
  final int length;
  bool _closed = false;
  @override
  String? get localPath => null;
  @override
  Stream<List<int>> openRead() async* {
    if (_closed) throw StateError('This transfer spool was closed.');
    final blob = await js.promiseToFuture(js.callMethod(file, 'getFile', []));
    yield* WebStreamingService().streamFromBlob(blob as Object);
  }

  @override
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    await _remove(root, name);
  }
}
