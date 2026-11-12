import 'dart:typed_data';
import 'models.dart';

EbookConversionBackend createBackend({
  String? executablePath,
  String? libraryPath,
  required Duration timeout,
  required EbookConversionLimits limits,
}) => _UnavailableBackend();

class _UnavailableBackend implements EbookConversionBackend {
  @override
  Future<EbookConversionCapabilities>
  capabilities() async => const EbookConversionCapabilities(
    available: false,
    runtime: EbookConversionRuntime.unavailable,
    cancellationMode: EbookCancellationMode.unavailable,
    reason:
        'Kindle conversion is not available in the browser. Export EPUB instead.',
  );

  @override
  Future<EbookConversionResult> convert(
    Uint8List input, {
    required bool metadataOnly,
    required KindleExportFormat format,
    KindleMetadataPatch? patch,
    Uint8List? cover,
    EbookCancellationToken? cancellation,
  }) => Future.error(
    const EbookConversionException(
      'unavailable',
      'Kindle conversion is not available in this build.',
    ),
  );
}
