import 'dart:typed_data';

import 'office_open_types.dart';

/// Web / Wasm: no worker isolate — the caller awaits current-isolate decoding.
Future<Object?> officeTrySpawnOpen({
  required Uint8List bytes,
  required String? password,
  required String kind,
  String? formulaLocale,

  /// Function API.
  void Function(OfficeOpenProgress progress)? onProgress,
}) async {
  return null;
}
