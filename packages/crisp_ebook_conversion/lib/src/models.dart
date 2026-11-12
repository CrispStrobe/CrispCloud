import 'dart:async';
import 'dart:typed_data';

enum KindleExportFormat {
  azw3('azw3'),
  legacyMobi('mobi');

  const KindleExportFormat(this.extension);
  final String extension;
}

enum EbookConversionRuntime { native, process, webAssembly, unavailable }

/// Native cancellation discards output and checks between library stages.
/// A synchronous Kindling build already in progress cannot be preempted.
enum EbookCancellationMode {
  cooperative,
  processTermination,
  workerTermination,
  unavailable,
}

class EbookConversionCapabilities {
  const EbookConversionCapabilities({
    required this.available,
    required this.runtime,
    required this.cancellationMode,
    this.engineVersion,
    this.reason,
    bool? canExportAzw3,
    bool? canExportLegacyMobi,
    bool? canRewriteKindleMetadata,
    bool? canReplaceKindleCover,
  }) : _exportAzw3 = canExportAzw3 ?? available,
       _exportLegacyMobi = canExportLegacyMobi ?? available,
       _rewriteMetadata = canRewriteKindleMetadata ?? available,
       _replaceCover = canReplaceKindleCover ?? available;

  final bool available;
  final EbookConversionRuntime runtime;
  final EbookCancellationMode cancellationMode;
  final String? engineVersion;
  final String? reason;
  final bool _exportAzw3;
  final bool _exportLegacyMobi;
  final bool _rewriteMetadata;
  final bool _replaceCover;
  bool get canExportAzw3 => available && _exportAzw3;
  bool get canExportLegacyMobi => available && _exportLegacyMobi;
  bool get canRewriteKindleMetadata => available && _rewriteMetadata;
  bool get canReplaceKindleCover => canRewriteKindleMetadata && _replaceCover;
}

class EbookConversionLimits {
  const EbookConversionLimits({
    this.maxInputBytes = 64 * 1024 * 1024,
    this.maxOutputBytes = 128 * 1024 * 1024,
    this.maxExpandedBytes = 192 * 1024 * 1024,
    this.maxEntryBytes = 32 * 1024 * 1024,
    this.maxArchiveEntries = 10000,
    this.maxImagePixels = 50000000,
  });
  final int maxInputBytes;
  final int maxOutputBytes;
  final int maxExpandedBytes;
  final int maxEntryBytes;
  final int maxArchiveEntries;
  final int maxImagePixels;

  Map<String, int> toJson() => {
    'input_bytes': maxInputBytes,
    'output_bytes': maxOutputBytes,
    'expanded_bytes': maxExpandedBytes,
    'entry_bytes': maxEntryBytes,
    'entries': maxArchiveEntries,
    'image_pixels': maxImagePixels,
  };
}

/// Null leaves an existing field unchanged; an empty value removes that field
/// where the Kindle format permits removal. Series is intentionally absent:
/// the upstream engine has no sound series-record mapping.
class KindleMetadataPatch {
  KindleMetadataPatch({
    this.title,
    List<String>? authors,
    this.publisher,
    this.description,
    this.language,
    this.isbn,
    this.asin,
    this.publicationDate,
    List<String>? subjects,
    this.identifier,
  }) : authors = authors == null ? null : List.unmodifiable(authors),
       subjects = subjects == null ? null : List.unmodifiable(subjects);

  final String? title;
  final List<String>? authors;
  final String? publisher;
  final String? description;
  final String? language;
  final String? isbn;
  final String? asin;
  final String? publicationDate;
  final List<String>? subjects;
  final String? identifier;

  Map<String, Object?> toJson() => {
    if (title != null) 'title': title,
    if (authors != null) 'authors': authors,
    if (publisher != null) 'publisher': publisher,
    if (description != null) 'description': description,
    if (language != null) 'language': language,
    if (isbn != null) 'isbn': isbn,
    if (asin != null) 'asin': asin,
    if (publicationDate != null) 'publication_date': publicationDate,
    if (subjects != null) 'subjects': subjects,
    if (identifier != null) 'identifier': identifier,
  };
}

class EbookCancellationToken {
  final Completer<void> _cancelled = Completer<void>();
  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;
  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

class EbookMetadataChange {
  const EbookMetadataChange(this.record, this.action);
  final int record;
  final String action;
}

class EbookConversionResult {
  EbookConversionResult({
    required Uint8List bytes,
    required this.format,
    required this.engineVersion,
    Iterable<String> warnings = const [],
    Iterable<EbookMetadataChange> changes = const [],
    this.noOp = false,
  }) : bytes = Uint8List.fromList(bytes).asUnmodifiableView(),
       warnings = List.unmodifiable(warnings),
       changes = List.unmodifiable(changes);

  final Uint8List bytes;
  final KindleExportFormat format;
  final String engineVersion;
  final List<String> warnings;
  final List<EbookMetadataChange> changes;
  final bool noOp;
  String get extension => format.extension;
}

class EbookConversionException implements Exception {
  const EbookConversionException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'EbookConversionException($code): $message';
}

abstract interface class EbookConversionBackend {
  Future<EbookConversionCapabilities> capabilities();
  Future<EbookConversionResult> convert(
    Uint8List input, {
    required bool metadataOnly,
    required KindleExportFormat format,
    KindleMetadataPatch? patch,
    Uint8List? cover,
    EbookCancellationToken? cancellation,
  });
}
