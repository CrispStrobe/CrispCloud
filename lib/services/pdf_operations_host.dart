import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:pdf_operations/pdf_operations.dart';

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/panel_source_provider.dart';
import '../providers/providers.dart';
import 'panel_source_service.dart';
import 'pdf_device_export.dart';
import 'pdf_file_store.dart';

typedef PdfOperationPasswordPrompt = Future<String?> Function(
  String fileName,
  bool incorrect,
);

enum PdfOperationAction {
  merge,
  extract,
  rotate,
  reorder,
  deletePages,
  watermark,
  fillForm,
  insertImage,
}

/// Data-only request, suitable for a native worker isolate. Page expressions
/// use the same one-based syntax as the CLI and the shared operations package.
class PdfOperationRequest {
  const PdfOperationRequest({
    required this.action,
    required this.sources,
    this.pages = 'all',
    this.degrees = 90,
    this.allowDecryption = false,
    this.watermark,
    this.imagePlacement,
    this.imageBytes,
    this.fields = const {},
    this.appearanceFont,
  });

  final PdfOperationAction action;
  final List<PdfMergeInput> sources;
  final String pages;
  final int degrees;
  final bool allowDecryption;
  final PdfWatermarkOptions? watermark;
  final PdfImagePlacement? imagePlacement;
  final Uint8List? imageBytes;
  final Map<String, Object?> fields;
  final PdfEmbeddedFont? appearanceFont;
}

class _PdfOperationWork {
  const _PdfOperationWork(this.operations, this.request);
  final PdfOperationsService operations;
  final PdfOperationRequest request;
}

class _PdfInspectionWork {
  const _PdfInspectionWork(this.operations, this.input);
  final PdfOperationsService operations;
  final PdfInput input;
}

PdfInspection _inspectPdf(_PdfInspectionWork work) => work.operations.inspect(work.input);

PdfOperationResult _performPdfOperation(_PdfOperationWork work) {
  final service = work.operations;
  final request = work.request;
  if (request.sources.isEmpty) throw ArgumentError('Select at least one PDF.');
  if (request.action != PdfOperationAction.merge && request.sources.length != 1) {
    throw ArgumentError('Select one PDF for this operation.');
  }
  if (request.action == PdfOperationAction.watermark && request.watermark == null) {
    throw ArgumentError('Choose watermark options.');
  }
  if (request.action == PdfOperationAction.insertImage &&
      (request.imagePlacement == null || request.imageBytes == null)) {
    throw ArgumentError('Choose an image and its placement.');
  }
  final input = request.sources.first.input;
  return switch (request.action) {
    PdfOperationAction.merge => service.merge(
      request.sources,
      allowDecryption: request.allowDecryption,
    ),
    PdfOperationAction.extract => service.extract(
      input,
      pages: request.pages,
      allowDecryption: request.allowDecryption,
    ),
    PdfOperationAction.rotate => service.rotate(
      input,
      pages: request.pages,
      degrees: request.degrees,
    ),
    PdfOperationAction.reorder => service.reorder(input, pages: request.pages),
    PdfOperationAction.deletePages => service.deletePages(input, pages: request.pages),
    PdfOperationAction.watermark => service.watermark(
      input,
      pages: request.pages,
      watermark: request.watermark!,
    ),
    PdfOperationAction.fillForm => service.fillForm(
      input,
      values: request.fields,
      appearanceFont: request.appearanceFont,
    ),
    PdfOperationAction.insertImage => service.insertImage(
      input,
      imageBytes: request.imageBytes!,
      placement: request.imagePlacement!,
      pages: request.pages,
    ),
  };
}

/// A freshly read PDF and the storage identity from which it was obtained.
class PdfOperationSource {
  const PdfOperationSource({
    required this.store,
    required this.input,
    required this.inspection,
  });

  final PdfFileStore store;
  final PdfInput input;
  final PdfInspection inspection;
}

class PdfOperationCancelled implements Exception {
  const PdfOperationCancelled();

  @override
  String toString() => 'PDF operation cancelled.';
}

/// Storage boundary for the shared, pure-Dart PDF operations package.
///
/// Source identities are captured before any asynchronous reads. Every input
/// bypasses the preview cache, and outputs are either new siblings of the first
/// selected source or an explicit device export. Folder saves never overwrite a
/// source; device exports honor the chosen destination. [PdfFileStore] retains
/// its account and destination preflight checks.
class PdfOperationsHost {
  PdfOperationsHost({
    required List<PdfFileStore> stores,
    PdfOperationsService? operations,
    PdfDeviceExporter? deviceExporter,
    void Function()? onDispose,
    this.useWorker = true,
  }) : stores = List.unmodifiable(stores),
       operations = operations ?? PdfOperationsService(),
       _exporter = PdfDeviceExport(exporter: deviceExporter),
       _onDispose = onDispose {
    if (stores.isEmpty) {
      throw ArgumentError('Select at least one PDF.');
    }
    if (stores.map((store) => store.documentId).toSet().length != stores.length) {
      throw ArgumentError('Select each PDF only once.');
    }
  }

  /// Captures only exact entries from a verified normal folder listing.
  factory PdfOperationsHost.capture({
    required WidgetRef ref,
    required PanelSide side,
    required List<FileItem> files,
  }) {
    final panel = ref.read(panelProvider(side));
    final selectedSource = ref.read(panelSourceProvider(side));
    if (panel.isInArchive ||
        selectedSource.isArchive ||
        selectedSource.isContainer) {
      throw StateError(
        'Extract these files from their archive or container first.',
      );
    }
    var active = true;
    final stores = <PdfFileStore>[];
    var knownBytes = 0;
    for (final file in files) {
      if (file.isFolder || !file.name.toLowerCase().endsWith('.pdf')) {
        throw ArgumentError('Select PDF files only.');
      }
      if ((file.size ?? 0) > kPdfEditorInputLimitBytes) {
        throw const PdfFileTooLargeException(kPdfEditorInputLimitBytes);
      }
      knownBytes += file.size ?? 0;
      if (knownBytes > maxTotalInputBytes) {
        throw ArgumentError('Selected PDFs exceed the 256 MiB input limit.');
      }
      final origin = panel.originForFile(file);
      if (origin == null) {
        throw StateError(
          'Refresh this folder before using PDF operations. '
          'The file source could not be verified.',
        );
      }
      final source = origin.source;
      if (source is LocalPanelSource) {
        stores.add(
          PdfFileStore.local(
            service: ref.read(localFileServiceProvider),
            file: file,
          ),
        );
      } else if (source is RemotePanelSource) {
        stores.add(
          PdfFileStore.remote(
            client: source.client,
            providerName: source.providerName,
            cache: ref.read(fileCacheProvider),
            file: file.path == null
                ? file.copyWith(path: p.posix.join(source.path, file.name))
                : file,
            isCurrentAccount: () => active && origin.isCurrent,
          ),
        );
      } else {
        throw StateError(
          'Extract these files from their archive or container first.',
        );
      }
    }
    return PdfOperationsHost(stores: stores, onDispose: () => active = false);
  }

  static const maxTotalInputBytes = 256 * 1024 * 1024;

  final List<PdfFileStore> stores;
  final PdfOperationsService operations;
  /// Native calls run in a worker isolate. Flutter's web compute adapter runs
  /// on the browser thread; the size limits still apply there.
  final bool useWorker;
  final PdfDeviceExport _exporter;
  final void Function()? _onDispose;
  bool _closed = false;
  bool _loading = false;
  bool _loaded = false;
  bool _saving = false;
  bool _computing = false;

  /// The destination remains the folder of the first originally selected PDF,
  /// even when the merge list is subsequently reordered.
  String get destinationPath => stores.first.path;
  bool get destinationIsRemote => stores.first.isRemote;

  Future<List<PdfOperationSource>> load({
    required PdfOperationPasswordPrompt requestPassword,
    void Function(int completed, int total)? onProgress,
  }) async {
    _assertOpen();
    if (_loading || _saving || _computing) throw StateError('A PDF operation is in progress.');
    _loading = true;
    _loaded = false;
    try {
      final sources = <PdfOperationSource>[];
      var totalBytes = 0;
      for (final store in stores) {
        _assertOpen();
        final bytes = await store.load();
        _assertOpen();
        if (bytes.length > kPdfEditorInputLimitBytes) {
          throw const PdfFileTooLargeException(kPdfEditorInputLimitBytes);
        }
        totalBytes += bytes.length;
        if (totalBytes > maxTotalInputBytes) {
          throw ArgumentError('Selected PDFs exceed the 256 MiB input limit.');
        }
        var password = '';
        while (true) {
          final input = PdfInput(bytes, name: store.displayName, password: password);
          try {
            final inspection = useWorker
                ? await compute(_inspectPdf, _PdfInspectionWork(operations, input))
                : operations.inspect(input);
            _assertOpen();
            sources.add(
              PdfOperationSource(store: store, input: input, inspection: inspection),
            );
            break;
          } on PdfOperationException catch (error) {
            if (error.code != 'passwordRequired' && error.code != 'invalidPassword') {
              rethrow;
            }
            final entered = await requestPassword(
              store.displayName,
              error.code == 'invalidPassword',
            );
            _assertOpen();
            if (entered == null) throw const PdfOperationCancelled();
            password = entered;
          }
        }
        onProgress?.call(sources.length, stores.length);
      }
      _loaded = true;
      return List.unmodifiable(sources);
    } finally {
      _loading = false;
    }
  }

  Future<PdfOperationResult> perform(PdfOperationRequest request) async {
    _assertReadyToSave();
    _computing = true;
    try {
      final work = _PdfOperationWork(operations, request);
      final result = useWorker
          ? await compute(_performPdfOperation, work)
          : _performPdfOperation(work);
      _assertOpen();
      return result;
    } finally {
      _computing = false;
    }
  }

  Future<PdfSaveOutcome> saveSibling(Uint8List bytes, String name) async {
    _assertReadyToSave();
    _saving = true;
    try {
      return await stores.first.saveCopy(bytes, name);
    } finally {
      _saving = false;
    }
  }

  Future<PdfSaveOutcome?> export(Uint8List bytes, String name) async {
    _assertReadyToSave();
    _saving = true;
    try {
      return await _exporter.exportCopy(bytes, name);
    } finally {
      _saving = false;
    }
  }

  void _assertReadyToSave() {
    _assertOpen();
    if (!_loaded || _loading) throw StateError('Wait for the PDFs to finish loading.');
    if (_computing) throw StateError('A PDF operation is in progress.');
    if (_saving) throw StateError('A PDF save is in progress.');
  }

  void _assertOpen() {
    if (_closed) throw const PdfOperationCancelled();
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    _onDispose?.call();
  }
}
