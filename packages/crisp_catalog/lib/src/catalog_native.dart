/// Desktop-native catalogue API. Metadata stays in Rust/SQLite; only bounded
/// query results and summaries cross FFI. The worker keeps callers responsive.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:io' show Platform;
import 'catalog_types.dart';
import 'package:ffi/ffi.dart';

const _asset = 'package:crisp_catalog/crisp_catalog_bridge';
@Native<Pointer<Utf8> Function(Pointer<Utf8>)>(
  symbol: 'crisp_catalog_call',
  assetId: _asset,
)
external Pointer<Utf8> _call(Pointer<Utf8> request);
@Native<Void Function(Pointer<Utf8>)>(
  symbol: 'crisp_catalog_free',
  assetId: _asset,
)
external void _free(Pointer<Utf8> value);

class CrispCatalog implements CatalogBackend {
  const CrispCatalog();
  @override
  bool get supported =>
      Platform.isMacOS ||
      Platform.isLinux ||
      Platform.isWindows ||
      Platform.isIOS ||
      Platform.isAndroid;
  @override
  Future<Map<String, dynamic>> execute(Map<String, Object?> request) async {
    if (!supported) {
      throw CatalogException(
        'Native catalogues require the desktop app.',
        code: 'unsupported_platform',
      );
    }
    final encoded = jsonEncode(request);
    if (utf8.encode(encoded).length > 1024 * 1024) {
      throw ArgumentError('Catalogue request exceeds 1 MiB.');
    }
    final response = await Isolate.run(() => _execute(encoded));
    final decoded = jsonDecode(response) as Map<String, dynamic>;
    if (decoded['error'] case final String error) {
      throw CatalogException(error, code: decoded['code'] as String?);
    }
    return decoded['result'] as Map<String, dynamic>;
  }
}

String _execute(String encoded) {
  final input = encoded.toNativeUtf8();
  Pointer<Utf8>? output;
  try {
    output = _call(input);
    if (output == nullptr) {
      throw StateError('Native catalogue returned no result.');
    }
    return output.toDartString();
  } finally {
    malloc.free(input);
    if (output != null && output != nullptr) _free(output);
  }
}
