import 'dart:typed_data';

import 'converter_stub.dart'
    if (dart.library.io) 'converter_io.dart'
    if (dart.library.js_interop) 'converter_web.dart'
    as platform;
import 'models.dart';

/// Export/update service. Returns bytes; only CrispCloud's host save session
/// may overwrite a user's document. The default native runtime is bundled by
/// the package build hook, including mobile where its Rust target is built.
/// Browsers use the bundled metadata-only Wasm worker. [webWorkerUri] can select
/// another bundled worker location on the same origin; native builds ignore it.
class KindlingConverter {
  KindlingConverter({
    String? executablePath,
    String? libraryPath,
    Uri? webWorkerUri,
    Duration timeout = const Duration(minutes: 2),
    EbookConversionLimits limits = const EbookConversionLimits(),
  }) : _backend = platform.createBackend(
         executablePath: executablePath,
         libraryPath: libraryPath,
         webWorkerUri: webWorkerUri,
         timeout: timeout,
         limits: limits,
       );

  final EbookConversionBackend _backend;

  Future<EbookConversionCapabilities> capabilities() => _backend.capabilities();

  Future<EbookConversionResult> exportKindle(
    Uint8List epub, {
    KindleExportFormat format = KindleExportFormat.azw3,
    EbookCancellationToken? cancellation,
  }) => _backend.convert(
    epub,
    metadataOnly: false,
    format: format,
    cancellation: cancellation,
  );

  /// [format] preserves the input container kind and determines the suggested
  /// filename extension. This does not convert between MOBI and AZW3.
  Future<EbookConversionResult> rewriteMetadata(
    Uint8List mobi, {
    required KindleMetadataPatch patch,
    KindleExportFormat format = KindleExportFormat.azw3,
    Uint8List? cover,
    EbookCancellationToken? cancellation,
  }) => _backend.convert(
    mobi,
    metadataOnly: true,
    format: format,
    patch: patch,
    cover: cover,
    cancellation: cancellation,
  );
}
