// Compile to JavaScript and run through run_web_metadata_probe.mjs. The same
// compiled adapter also runs in a real browser with the --browser option.
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:crisp_ebook_conversion/crisp_ebook_conversion.dart';

@JS('metadataFixtureBase64')
external String get _fixture;
@JS('metadataSmokeFinished')
external void _finished(String json);

var _checks = 0;
void check(bool value, String message) {
  if (!value) throw StateError(message);
  _checks++;
}

bool equalBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Future<void> fails(Future<Object?> result, String code) async {
  try {
    await result;
    throw StateError('Expected $code');
  } on EbookConversionException catch (error) {
    check(error.code == code, 'Expected $code; got ${error.code}');
  }
}

Future<void> main() async {
  try {
    final input = base64Decode(_fixture);
    final baseline = Uint8List.fromList(input);
    final converter = KindlingConverter();
    final capability = await converter.capabilities();
    check(capability.available, capability.reason ?? 'Unavailable');
    check(
      capability.runtime == EbookConversionRuntime.webAssembly,
      'Wasm runtime',
    );
    check(
      capability.cancellationMode == EbookCancellationMode.workerTermination,
      'Worker cancellation',
    );
    check(
      capability.canRewriteKindleMetadata && !capability.canReplaceKindleCover,
      'Metadata-only capability',
    );
    check(
      !capability.canExportAzw3 && !capability.canExportLegacyMobi,
      'Native export flags stay false',
    );
    final noop = await converter.rewriteMetadata(
      input,
      patch: KindleMetadataPatch(),
    );
    check(noop.noOp && equalBytes(noop.bytes, input), 'Byte-identical no-op');
    final patch = KindleMetadataPatch(
      title: 'Dart Wasm café 世界',
      authors: ['One', 'Zwei'],
    );
    final edited = await converter.rewriteMetadata(input, patch: patch);
    check(!edited.noOp && edited.changes.isNotEmpty, 'Real metadata edit');
    check(
      utf8
          .decode(edited.bytes, allowMalformed: true)
          .contains('Dart Wasm café 世界'),
      'Unicode title',
    );
    final repeat = await converter.rewriteMetadata(edited.bytes, patch: patch);
    check(repeat.noOp && equalBytes(repeat.bytes, edited.bytes), 'Idempotence');
    check(equalBytes(input, baseline), 'Original bytes unchanged');
    await fails(converter.exportKindle(input), 'unsupportedFormat');
    await fails(
      converter.rewriteMetadata(input, patch: patch, cover: Uint8List(1)),
      'unsupportedOperation',
    );

    final mutable = Uint8List.fromList(input);
    final inFlight = converter.rewriteMetadata(mutable, patch: patch);
    mutable.fillRange(0, mutable.length, 0);
    await fails(converter.rewriteMetadata(input, patch: patch), 'busy');
    check(
      (await inFlight).bytes.length > 78,
      'Private snapshot survives caller mutation',
    );

    final token = EbookCancellationToken();
    final cancelled = converter.rewriteMetadata(
      input,
      patch: patch,
      cancellation: token,
    );
    token.cancel();
    await fails(cancelled, 'cancelled');
    final precancelled = EbookCancellationToken()..cancel();
    await fails(
      converter.rewriteMetadata(
        input,
        patch: patch,
        cancellation: precancelled,
      ),
      'cancelled',
    );
    final fast = KindlingConverter(timeout: const Duration(microseconds: 1));
    await fails(fast.rewriteMetadata(input, patch: patch), 'timeout');
    check(
      (await converter.rewriteMetadata(input, patch: patch)).bytes.length > 78,
      'Next operation after cancellation/timeout',
    );

    final small = KindlingConverter(
      limits: const EbookConversionLimits(maxInputBytes: 10),
    );
    await fails(small.rewriteMetadata(input, patch: patch), 'limitExceeded');
    final smallOutput = KindlingConverter(
      limits: const EbookConversionLimits(maxOutputBytes: 10),
    );
    await fails(
      smallOutput.rewriteMetadata(input, patch: patch),
      'limitExceeded',
    );
    await fails(
      converter.rewriteMetadata(
        input,
        patch: KindleMetadataPatch(title: 'x' * 131073),
      ),
      'limitExceeded',
    );
    await fails(
      converter.rewriteMetadata(Uint8List.fromList([1, 2, 3]), patch: patch),
      'conversionFailed',
    );
    final missing = KindlingConverter(
      webWorkerUri: Uri.parse('missing-metadata-worker.js'),
    );
    check(
      !(await missing.capabilities()).available,
      'Missing worker is unavailable',
    );
    final external = KindlingConverter(
      webWorkerUri: Uri.parse('https://example.invalid/worker.js'),
    );
    check(
      !(await external.capabilities()).available,
      'External worker is refused',
    );
    _finished(jsonEncode({'ok': true, 'checks': _checks}));
  } catch (error, stack) {
    _finished(
      jsonEncode({'ok': false, 'message': '$error', 'stack': '$stack'}),
    );
  }
}
