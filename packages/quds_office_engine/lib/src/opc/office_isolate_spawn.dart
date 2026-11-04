import 'dart:typed_data';

import 'office_open_types.dart';

/// Web / Wasm: no worker isolate — caller falls back to [_openSync].
Future<Object?> officeTrySpawnOpen({
  required Uint8List bytes,
  required String? password,
  required String kind,

  /// Function API.
  void Function(OfficeOpenProgress progress)? onProgress,
}) async {
  return null;
}
