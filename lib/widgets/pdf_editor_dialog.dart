import 'dart:async';
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:pdf_cos/pdf_cos.dart' show CosPasswordException;
import 'package:pdf_document/pdf_document.dart' show PdfAcroForm, PdfSignature;

import '../l10n/pdf_editor_strings.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/panel_source_provider.dart';
import '../providers/providers.dart';
import '../services/log_service.dart';
import '../services/panel_source_service.dart';
import '../services/pdf_edit_session.dart';
import '../services/pdf_device_export.dart';
import '../services/pdf_file_store.dart';

const _log = Log('PdfEditor');
final _editingTools = Set<PdfEditTool>.unmodifiable(
  PdfEditTool.values.where(
    (tool) => tool != PdfEditTool.redact && tool != PdfEditTool.signatureBox,
  ),
);

bool isPdfFileName(String name) => name.toLowerCase().endsWith('.pdf');

Future<void> showPdfEditorDialog(
  BuildContext context,
  WidgetRef ref,
  FileItem file,
  PanelSide side,
) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => Dialog.fullscreen(
    child: PdfEditorDialog(file: file, side: side),
  ),
);

/// PDF editing surface with a host-owned, asynchronous save lifecycle.
///
/// The editor's void callbacks request a save; only [PdfEditSession] records
/// its completion. The source is captured at open, so changing panes or cloud
/// accounts never redirects an existing editing session's writes.
class PdfEditorDialog extends ConsumerStatefulWidget {
  const PdfEditorDialog({
    super.key,
    required this.file,
    required this.side,
    this.storeOverride,
    this.preferencesOverride,
    this.deviceExporterOverride,
    this.autoRenderWorker = true,
  });

  final FileItem file;
  final PanelSide side;

  /// Embedding/test hooks. The host owns the store and borrowed preferences.
  final PdfFileStore? storeOverride;
  final PdfEditingPreferences? preferencesOverride;
  final PdfDeviceExporter? deviceExporterOverride;
  final bool autoRenderWorker;

  @override
  ConsumerState<PdfEditorDialog> createState() => _PdfEditorDialogState();
}

class _PdfEditorDialogState extends ConsumerState<PdfEditorDialog> {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  PdfFileStore? _store;
  PdfEditSession? _session;
  PdfEditingController? _controller;
  PdfEditingPreferences? _preferences;
  int _revision = 0;
  int? _lastCopyRevision;
  bool _loading = true;
  bool _exporting = false;
  bool _choosingSave = false;
  bool _closing = false;
  bool _allowPop = false;
  bool _copyOnly = false;
  bool _pendingRedactions = false;
  String? _error;
  String? _errorDetail;

  bool get _busy =>
      (_session?.isSaving ?? false) || _exporting || _choosingSave;
  String get _deviceExportLabel => kIsWeb ? 'Download a copy' : 'Export a copy';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _controller?.removeListener(_onRevision);
    _controller?.dispose();
    _session?.removeListener(_onSessionChanged);
    _session?.dispose();
    if (widget.preferencesOverride == null) _preferences?.dispose();
    super.dispose();
  }

  PdfFileStore _captureStore() {
    if (widget.storeOverride case final store?) return store;
    final panel = ref.read(panelProvider(widget.side));
    final selectedSource = ref.read(panelSourceProvider(widget.side));
    if (panel.isInArchive ||
        selectedSource.isArchive ||
        selectedSource.isContainer) {
      throw const _PdfOpenMessage(
        'Extract this file from its archive or container before editing.',
      );
    }
    final origin = panel.originForFile(widget.file);
    if (origin == null) {
      throw const _PdfOpenMessage(
        'Refresh this folder before editing. The file’s source could not be verified.',
      );
    }
    final source = origin.source;
    if (source is LocalPanelSource) {
      return PdfFileStore.local(
        service: ref.read(localFileServiceProvider),
        file: widget.file,
      );
    }
    if (source is! RemotePanelSource) {
      throw const _PdfOpenMessage(
        'Extract this file from its archive or container before editing.',
      );
    }

    return PdfFileStore.remote(
      client: source.client,
      providerName: source.providerName,
      cache: ref.read(fileCacheProvider),
      file: widget.file.path == null
          ? widget.file.copyWith(
              path: p.posix.join(source.path, widget.file.name),
            )
          : widget.file,
      isCurrentAccount: () => mounted && origin.isCurrent,
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _errorDetail = null;
    });
    PdfEditingController? candidate;
    try {
      if ((widget.file.size ?? 0) > kPdfEditorInputLimitBytes) {
        throw const _PdfOpenMessage(
          'PDF editing is limited to files up to 64 MiB.',
        );
      }
      final store = _store ??= _captureStore();
      final bytes = await store.load();
      if (!mounted) return;
      if (bytes.length > kPdfEditorInputLimitBytes) {
        throw const _PdfOpenMessage(
          'PDF editing is limited to files up to 64 MiB.',
        );
      }
      _preferences ??= widget.preferencesOverride ?? PdfEditingPreferences();
      var password = '';
      var attemptedPassword = false;
      while (candidate == null) {
        try {
          candidate = PdfEditingController(
            bytes,
            password: password,
            preferences: _preferences,
            // Newly entered password-field values stay out of serialization;
            // this does not sanitize secrets already present in the input.
            formSecretStore: InMemoryFormSecretStore(),
          );
        } on CosPasswordException {
          final entered = await _askPassword(incorrect: attemptedPassword);
          if (!mounted) return;
          if (entered == null) {
            throw const _PdfOpenMessage('Password entry cancelled.');
          }
          password = entered;
          attemptedPassword = true;
        }
      }
      if (PdfAcroForm.of(candidate.document)?.hasXfa ?? false) {
        throw const _PdfOpenMessage(
          'XFA forms cannot be edited here. Open this PDF with an XFA-capable application.',
        );
      }
      if (candidate.document.pageCount == 0) {
        throw const _PdfOpenMessage('This PDF contains no pages.');
      }
      _copyOnly = PdfSignature.of(candidate.document).isNotEmpty;
      _updateRedactionStatus(candidate.document);
      _controller = candidate;
      candidate = null;
      _revision = _controller!.revisionId;
      _session = PdfEditSession(initialBytes: bytes)
        ..addListener(_onSessionChanged);
      _controller!.addListener(_onRevision);
      setState(() => _loading = false);
    } catch (error, stack) {
      candidate?.dispose();
      _log.warn('Could not open PDF', error, stack);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is _PdfOpenMessage
            ? error.message
            : 'Could not open PDF';
        _errorDetail = error is _PdfOpenMessage ? null : '$error';
      });
    }
  }

  Future<String?> _askPassword({required bool incorrect}) async {
    final text = TextEditingController();
    final route = DialogRoute<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.pdfTr('Password required')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.pdfTr(
                incorrect
                    ? 'Incorrect password. Try again.'
                    : 'This PDF needs a password to open.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: text,
              autofocus: true,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(labelText: context.pdfTr('Password')),
              onSubmitted: (value) => Navigator.pop(dialogContext, value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.pdfTr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, text.text),
            child: Text(context.pdfTr('Open')),
          ),
        ],
      ),
    );
    try {
      return await Navigator.of(context, rootNavigator: true).push(route);
    } finally {
      // Keep the controller alive through the route's exit animation.
      await route.completed;
      text.dispose();
    }
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  void _onRevision() {
    final controller = _controller!;
    if (controller.revisionId == _revision) return;
    _revision = controller.revisionId;
    // Revision IDs also distinguish undo + a new edit with the same byte
    // length. The editor's onDocumentChanged length check alone does not.
    _updateRedactionStatus(controller.document);
    _session!.updateBytes(controller.bytes);
  }

  void _updateRedactionStatus(PdfDocument document) {
    _pendingRedactions = false;
    for (var page = 0; page < document.pageCount; page++) {
      if (document.page(page).annotations.any((a) => a.subtype == 'Redact')) {
        _pendingRedactions = true;
        break;
      }
    }
  }

  Future<PdfSaveOutcome?> _save({bool copy = false}) async {
    final session = _session;
    if (session == null || _busy) return null;
    copy = copy || _copyOnly;
    if (!copy && !session.isDirty) return PdfSaveOutcome.savedOriginal;
    String? fileName;
    if (copy) {
      setState(() => _choosingSave = true);
      try {
        fileName = await _askCopyName('edited');
      } finally {
        if (mounted) setState(() => _choosingSave = false);
      }
      if (!mounted || fileName == null) return null;
    }
    _onRevision();
    final savedRevision = _controller!.revisionId;
    final copyName = fileName;
    try {
      final outcome = await session.save(
        copyName == null
            ? _store!.save
            : (bytes) => _store!.saveCopy(bytes, copyName),
      );
      if (!mounted) return outcome;
      if (outcome != PdfSaveOutcome.savedOriginal) {
        _lastCopyRevision = savedRevision;
      }
      _notice(switch (outcome) {
        PdfSaveOutcome.savedOriginal => 'Saved',
        PdfSaveOutcome.savedCopy =>
          'Copy saved. The original has not been updated.',
        PdfSaveOutcome.downloadedCopy =>
          'Copy downloaded. The original has not been updated.',
      });
      _refreshPanel();
      return outcome;
    } catch (error, stack) {
      _log.warn('Could not save PDF', error, stack);
      if (mounted) _notice('Could not save PDF', detail: '$error');
      return null;
    }
  }

  void _refreshPanel() {
    if (widget.storeOverride != null) return;
    // A listing failure must not turn an already completed write into a
    // failed save, or cause the user to retry that write unknowingly.
    unawaited(
      ref.read(panelProvider(widget.side)).refresh().catchError((
        Object error,
        StackTrace stack,
      ) {
        _log.warn('Could not refresh panel after PDF save', error, stack);
      }),
    );
  }

  Future<String?> _askCopyName(String suffix) async {
    final text = TextEditingController(text: _suggestCopyName(suffix));
    final form = GlobalKey<FormState>();
    final route = DialogRoute<String>(
      context: context,
      builder: (dialogContext) {
        void submit() {
          if (!(form.currentState?.validate() ?? false)) return;
          var value = text.text.trim();
          if (!isPdfFileName(value)) value = '$value.pdf';
          Navigator.pop(dialogContext, value);
        }

        return AlertDialog(
          title: Text(context.pdfTr('Save PDF copy')),
          content: Form(
            key: form,
            child: TextFormField(
              key: const ValueKey('pdf-copy-name'),
              controller: text,
              autofocus: true,
              decoration: InputDecoration(
                labelText: context.pdfTr('File name'),
              ),
              onFieldSubmitted: (_) => submit(),
              validator: (value) {
                final name = value?.trim() ?? '';
                if (name.isEmpty ||
                    name == '.' ||
                    name == '..' ||
                    name == '.pdf' ||
                    RegExp(r'[<>:"/\\|?*\x00-\x1f]').hasMatch(name)) {
                  return context.pdfTr(
                    'Choose a new PDF file name without a folder path.',
                  );
                }
                final pdfName = isPdfFileName(name) ? name : '$name.pdf';
                if (pdfName.toLowerCase() == widget.file.name.toLowerCase()) {
                  return context.pdfTr(
                    'Use a different file name to preserve the original.',
                  );
                }
                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.pdfTr('Cancel')),
            ),
            FilledButton(
              onPressed: submit,
              child: Text(context.pdfTr('Save a copy')),
            ),
          ],
        );
      },
    );
    try {
      return await Navigator.of(context, rootNavigator: true).push(route);
    } finally {
      await route.completed;
      text.dispose();
    }
  }

  String _suggestCopyName(String suffix) {
    final name = widget.file.name;
    final stem = isPdfFileName(name)
        ? name.substring(0, name.length - 4)
        : name;
    return '$stem-$suffix-${DateTime.now().millisecondsSinceEpoch}.pdf';
  }

  /// Recovery path independent of cloud credentials, original-file conflicts,
  /// and the source folder's writability. Export never marks the source clean.
  Future<PdfSaveOutcome?> _exportDevice() async {
    if (_session == null || _busy) return null;
    _onRevision();
    final snapshot = Uint8List.fromList(_session!.bytes);
    final revision = _controller!.revisionId;
    setState(() => _exporting = true);
    try {
      final exporter = widget.deviceExporterOverride ?? exportPdfCopy;
      final outcome = await exporter(snapshot, _suggestCopyName('edited'));
      if (!mounted || outcome == null) return outcome;
      _lastCopyRevision = revision;
      _notice(
        outcome == PdfSaveOutcome.downloadedCopy
            ? 'Copy downloaded. The original has not been updated.'
            : 'Copy saved. The original has not been updated.',
      );
      return outcome;
    } catch (error, stack) {
      _log.warn('Could not export PDF', error, stack);
      if (mounted) _notice('Could not export PDF', detail: '$error');
      return null;
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _requestClose() async {
    if (_busy || _closing || _allowPop) return;
    _closing = true;
    try {
      if (_controller != null) _onRevision();
      if (!(_session?.isDirty ?? false)) {
        await _leave();
        return;
      }
      final action = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          key: const ValueKey('pdf-unsaved-dialog'),
          title: Text(context.pdfTr('Unsaved changes')),
          content: Text(context.pdfTr('Save changes before closing?')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'cancel'),
              child: Text(context.pdfTr('Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'discard'),
              child: Text(context.pdfTr('Discard')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'export'),
              child: Text(context.pdfTr(_deviceExportLabel)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'save'),
              child: Text(context.pdfTr(_copyOnly ? 'Save a copy' : 'Save')),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (action == 'discard') {
        await _leave();
      } else if (action == 'save' || action == 'export') {
        final outcome = action == 'export'
            ? await _exportDevice()
            : await _save();
        if (!mounted || outcome == null) return;
        if (outcome == PdfSaveOutcome.savedOriginal) {
          if (!_session!.isDirty) {
            await _leave();
          } else {
            _notice(
              'New changes were made while saving. Save them before closing.',
            );
          }
        } else if (_lastCopyRevision == _controller!.revisionId) {
          final close = await _confirm(
            'Close after saving a copy?',
            'Keep the saved copy before closing; the original file is unchanged.',
            'Close editor',
          );
          if (close &&
              mounted &&
              _lastCopyRevision == _controller!.revisionId) {
            await _leave();
          }
        } else {
          _notice(
            'New changes were made while saving. Save them before closing.',
          );
        }
      }
    } finally {
      _closing = false;
    }
  }

  Future<void> _leave() async {
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(context.pdfTr(title)),
          content: Text(context.pdfTr(message)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(context.pdfTr('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(context.pdfTr(action)),
            ),
          ],
        ),
      ) ??
      false;

  Future<Uint8List?> _pickFile(List<String> extensions) async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: extensions,
        withData: true,
      );
      if (!mounted || picked == null) return null;
      final file = picked.files.single;
      if (file.size > kPdfEditorInputLimitBytes ||
          (file.bytes?.length ?? 0) > kPdfEditorInputLimitBytes) {
        _notice('The selected file is too large. Choose a file up to 64 MiB.');
        return null;
      }
      if (file.bytes == null) {
        _notice(
          'The browser did not provide file contents. Please select the file again.',
        );
      }
      return file.bytes;
    } catch (error) {
      if (mounted) _notice('Could not read selected file', detail: '$error');
      return null;
    }
  }

  Future<void> _exportPages(List<Uint8List> documents) async {
    if (_busy || documents.isEmpty) return;
    setState(() => _exporting = true);
    var completed = 0;
    try {
      final document = _controller!.document;
      var message = context.pdfTr(
        'Exported pages do not retain document-wide form fields or bookmarks, and some internal links may stop working. Review the new files before sharing.',
      );
      if (_copyOnly) {
        message +=
            '\n\n${context.pdfTr('Exported page copies do not retain digital signatures.')}';
      }
      if (document.cos.isEncrypted) {
        message +=
            '\n\n${context.pdfTr('The exported copies will not be password-protected.')}';
      }
      if (!await _confirm('Export page copies', message, 'Continue') ||
          !mounted) {
        return;
      }
      final name = await _askCopyName(documents.length == 1 ? 'pages' : 'part');
      if (!mounted || name == null) return;
      var downloaded = false;
      for (var i = 0; i < documents.length; i++) {
        final outputName = documents.length == 1
            ? name
            : '${name.substring(0, name.length - 4)}-${i + 1}.pdf';
        final outcome = await _store!.saveCopy(documents[i], outputName);
        downloaded = downloaded || outcome == PdfSaveOutcome.downloadedCopy;
        completed++;
        if (!mounted) return;
      }
      _notice(downloaded ? 'Page copies downloaded' : 'Page copies saved');
      _refreshPanel();
    } catch (error, stack) {
      _log.warn('Could not export PDF pages', error, stack);
      if (mounted) {
        _notice(
          'Could not export pages',
          detail: '$completed/${documents.length}\n$error',
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _notice(String message, {String? detail}) {
    _messenger.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '${context.pdfTr(message)}${detail == null ? '' : '\n$detail'}',
          ),
          duration: Duration(seconds: detail == null ? 4 : 8),
        ),
      );
  }

  Widget _banner(String message) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: Text(context.pdfTr(message)),
  );

  @override
  Widget build(BuildContext context) {
    final dirty = _session?.isDirty ?? false;
    final controller = _controller;
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_requestClose());
      },
      child: ScaffoldMessenger(
        key: _messenger,
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            leading: IconButton(
              key: const ValueKey('pdf-close'),
              tooltip: context.pdfTr('Close'),
              onPressed: _busy ? null : _requestClose,
              icon: const Icon(Icons.close),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.file.name}${dirty ? ' *' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  context.pdfTr(
                    _busy
                        ? 'Saving…'
                        : dirty
                        ? 'Unsaved changes'
                        : 'PDF editor',
                  ),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
            actions: [
              if (controller != null) ...[
                IconButton(
                  key: const ValueKey('pdf-save'),
                  tooltip: context.pdfTr(_copyOnly ? 'Save a copy' : 'Save'),
                  onPressed: !_busy && (dirty || _copyOnly)
                      ? () => unawaited(_save())
                      : null,
                  icon: const Icon(Icons.save_outlined),
                ),
                if (!_copyOnly)
                  IconButton(
                    key: const ValueKey('pdf-save-copy'),
                    tooltip: context.pdfTr('Save a copy'),
                    onPressed: _busy
                        ? null
                        : () => unawaited(_save(copy: true)),
                    icon: const Icon(Icons.save_as_outlined),
                  ),
                IconButton(
                  key: const ValueKey('pdf-export-copy'),
                  tooltip: context.pdfTr(_deviceExportLabel),
                  onPressed: _busy ? null : () => unawaited(_exportDevice()),
                  icon: const Icon(Icons.download_outlined),
                ),
              ],
            ],
          ),
          body: Column(
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_copyOnly)
                _banner(
                  'This PDF contains digital signatures. Save a copy to preserve the signed original.',
                ),
              if (_pendingRedactions)
                _banner(
                  'Redaction is unavailable here. Existing redaction marks do not remove the underlying content.',
                ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.picture_as_pdf_outlined,
                                size: 48,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                context.pdfTr(_error!),
                                textAlign: TextAlign.center,
                              ),
                              if (_errorDetail != null) ...[
                                const SizedBox(height: 8),
                                SelectableText(_errorDetail!),
                              ],
                              const SizedBox(height: 16),
                              TextButton(
                                onPressed: _load,
                                child: Text(context.pdfTr('Retry')),
                              ),
                            ],
                          ),
                        ),
                      )
                    : PdfEditorView(
                        controller: controller!,
                        documentId: _store!.documentId,
                        autoRenderWorker: widget.autoRenderWorker,
                        features: PdfEditorFeatures(tools: _editingTools),
                        // The surface owns Ctrl/Cmd+S. Registering another
                        // host binding would risk starting two writes.
                        showSaveButton: false,
                        alwaysAllowSave: true,
                        onSave: (_) => unawaited(_save()),
                        onSaveAs: (_) => unawaited(_save(copy: true)),
                        onPickPdfToInsert: () => _pickFile(['pdf']),
                        imagePicker: (_) => _pickFile(['png', 'jpg', 'jpeg']),
                        onExportPages: (bytes) =>
                            unawaited(_exportPages([bytes])),
                        onSplitPages: (bytes) => unawaited(_exportPages(bytes)),
                        // No signing callback: the certificate-signing tool
                        // stays hidden. Hand-drawn ink signatures remain.
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PdfOpenMessage implements Exception {
  const _PdfOpenMessage(this.message);
  final String message;

  @override
  String toString() => message;
}
