import 'app_scaffold_messenger.dart';

import 'package:quds_office_editor/quds_office_editor.dart' as office;

import 'pdf_review_status.dart';

import '../services/pdf_open_preferences.dart';
import '../services/document_printing.dart';
import 'document_print_scope.dart';
import '../services/document_workspace_session.dart';
import '../services/document_activity.dart';

import 'dart:async';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb, listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:pdf_cos/pdf_cos.dart' show CosPasswordException;
import 'package:pdf_document/pdf_document.dart' show PdfAcroForm, PdfSignature;

import 'pdf_floating_toolbars.dart';
import '../l10n/pdf_editor_strings.dart';
import '../l10n/pdf_workspace_strings.dart';
import '../services/pdf_selection_note.dart';
import '../services/mac_browser_toolbar.dart';
import '../l10n/pdf_operations_strings.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/panel_source_provider.dart';
import '../providers/providers.dart';
import '../services/log_service.dart';
import '../services/panel_source_service.dart';
import '../services/pdf_edit_session.dart';
import '../services/pdf_device_export.dart';
import '../services/pdf_editor_menu.dart';
import '../services/pdf_file_store.dart';
import 'document_page_navigation.dart';

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
  PanelSide side, {
  PdfEditorBackend backend = PdfEditorBackend.pdfEditor,
}) => showDialog<void>(
  context: context,
  animationStyle: AnimationStyle.noAnimation,
  barrierDismissible: false,
  builder: (_) => Dialog.fullscreen(
    child: PdfEditorDialog(file: file, side: side, backend: backend),
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
    this.backend = PdfEditorBackend.pdfEditor,
  });

  final FileItem file;
  final PanelSide side;

  /// Embedding/test hooks. The host owns the store and borrowed preferences.
  final PdfFileStore? storeOverride;
  final PdfEditingPreferences? preferencesOverride;
  final PdfDeviceExporter? deviceExporterOverride;
  final bool autoRenderWorker;
  final PdfEditorBackend backend;

  @override
  ConsumerState<PdfEditorDialog> createState() => _PdfEditorDialogState();
}

class _PdfEditorDialogState extends ConsumerState<PdfEditorDialog> {
  DocumentWorkspaceSession? _workspace;
  DocumentActivity? _activity;
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  final _viewer = PdfViewerController();
  final _nativeId = DateTime.now().microsecondsSinceEpoch.toString();
  bool _notePromptOpen = false;
  PdfFileStore? _store;
  PdfEditSession? _session;
  PdfEditingController? _controller;
  PdfEditorCommands? _commands;
  PdfEditingPreferences? _preferences;
  office.PdfEditorController? _officeController;
  String _officePassword = "";
  int get _currentRevision =>
      _officeController?.contentRevision ?? _controller?.revisionId ?? 0;
  bool get _hasPendingInk =>
      _officeController == null && (_controller?.hasPendingInk ?? false);
  int _officeSnapshotRevision = 0;
  int _revision = 0;
  bool _hadPendingInk = false;
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
  PdfEditorMenuActions? _menuActions;
  ProviderContainer? _providerContainer;
  String? _menuSignature;

  bool get _isDirty =>
      (_session?.isDirty ?? false) ||
      (_officeController?.isDirty ?? false) ||
      _hasPendingInk;

  bool get _busy =>
      (_session?.isSaving ?? false) ||
      _exporting ||
      _choosingSave ||
      _notePromptOpen;
  String get _deviceExportLabel => kIsWeb ? 'Download a copy' : 'Export a copy';

  @override
  void initState() {
    super.initState();
    _viewer.addListener(_publishMenu);
    unawaited(_load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _providerContainer = ProviderScope.containerOf(context, listen: false);
    _menuSignature = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _publishMenu();
    });
  }

  void _clearMenu() {
    final container = _providerContainer;
    final actions = _menuActions;
    _menuActions = null;
    if (container == null || actions == null) return;
    // Route disposal can happen during build; clear after the tree settles,
    // and never remove a newer editor's registration.
    Future<void>.microtask(() {
      try {
        if (identical(container.read(pdfEditorMenuProvider), actions)) {
          container.read(pdfEditorMenuProvider.notifier).state = null;
        }
      } catch (_) {
        // The provider container may already be disposed.
      }
    });
  }

  @override
  void dispose() {
    _officeController?.removeListener(_onOfficeRevision);
    _officeController?.dispose();
    _workspace?.dispose();
    _clearMenu();
    _providerContainer = null;
    _viewer.removeListener(_publishMenu);
    _viewer.dispose();
    _controller?.removeListener(_onRevision);
    _commands?.dispose();
    _controller?.dispose();
    _session?.removeListener(_onSessionChanged);
    _session?.dispose();
    if (widget.preferencesOverride == null) _preferences?.dispose();
    super.dispose();
  }

  void _publishMenu() {
    final container = _providerContainer;
    if (container == null) return;
    final controller = _controller;
    final dirty = _isDirty;
    final operational = !_loading && _error == null && !_busy;
    final canUndo =
        operational &&
        (_officeController?.commands.canUndo ?? controller?.canUndo ?? false);
    final canRedo =
        operational &&
        (_officeController?.commands.canRedo ?? controller?.canRedo ?? false);
    final signature = <bool>[
      dirty,
      operational,
      _copyOnly,
      canUndo,
      canRedo,
      _canAttachNote,
    ].join('|');
    if (signature == _menuSignature && _menuActions != null) return;
    _menuSignature = signature;
    final actions = PdfEditorMenuActions(
      perform: _performMenuAction,
      canSave: operational && (dirty || _copyOnly),
      canSaveCopy: operational,
      canExport: operational,
      canClose: !_busy,
      canUndo: canUndo,
      canRedo: canRedo,
      canAttachNote: operational && _canAttachNote,
      title: '${widget.file.name}${dirty ? " *" : ""}',
      sessionId: _nativeId,
    );
    _menuActions = actions;
    container.read(pdfEditorMenuProvider.notifier).state = actions;
  }

  void _performMenuAction(PdfEditorMenuAction action) {
    switch (action) {
      case PdfEditorMenuAction.save:
        unawaited(_save());
        break;
      case PdfEditorMenuAction.saveCopy:
        unawaited(_save(copy: true));
        break;
      case PdfEditorMenuAction.exportCopy:
        unawaited(_exportDevice());
        break;
      case PdfEditorMenuAction.close:
        unawaited(_requestClose());
        break;
      case PdfEditorMenuAction.undo:
        if (_officeController case final c?) {
          c.undo();
        } else {
          _controller?.undo();
        }
        break;
      case PdfEditorMenuAction.redo:
        if (_officeController case final c?) {
          c.redo();
        } else {
          _controller?.redo();
        }
        break;
      case PdfEditorMenuAction.attachNote:
        unawaited(_attachNote());
        break;
    }
  }

  bool get _canAttachNote =>
      _officeController == null &&
      _controller != null &&
      (_viewer.hasSelection || _controller!.canSetSelectedContents);

  Future<void> _attachNote({PdfTextMenuRequest? request}) async {
    final controller = _controller;
    if (controller == null || _busy || !_flushPendingInk()) return;
    final quads =
        request?.quadsByPage ??
        {
          for (final page in _viewer.selectionPages)
            page: _viewer.selectionRectsOn(page),
        };
    final capture = PdfSelectionNote.capture(controller, quads);
    final slots = List<(int, int)>.of(controller.selectedAnnotationSlots);
    if (capture.isEmpty && !controller.canSetSelectedContents) return;
    final initial = capture.isEmpty
        ? controller.selectedAnnotation?.contents ?? ''
        : '';
    final revision = controller.revisionId;
    final field = TextEditingController(text: initial);
    setState(() => _notePromptOpen = true);
    _publishMenu();
    String? result;
    final route = DialogRoute<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('pdf-selection-note-dialog'),
        title: Text(pdfWorkspaceTr(context, 'Attach note')),
        content: SizedBox(
          width: 420,
          child: TextField(
            key: const ValueKey('pdf-selection-note-text'),
            controller: field,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            decoration: InputDecoration(
              labelText: pdfWorkspaceTr(context, 'Note'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.pdfTr('Cancel')),
          ),
          FilledButton(
            key: const ValueKey('pdf-selection-note-save'),
            onPressed: () => Navigator.pop(dialogContext, field.text),
            child: Text(context.pdfTr('Save')),
          ),
        ],
      ),
    );
    try {
      result = await Navigator.of(context, rootNavigator: true).push(route);
      if (!mounted || result == null || result.trim().isEmpty) return;
      if (controller.revisionId != revision ||
          (capture.isEmpty &&
              !listEquals(slots, controller.selectedAnnotationSlots))) {
        _notice(
          pdfWorkspaceTr(context, 'The PDF changed. Select the text again.'),
        );
        return;
      }
      if (capture.isEmpty) {
        controller.setSelectedContents(result.trim());
      } else {
        if (capture.attach(result)) {
          _viewer.clearSelection();
          final page = capture.quads.keys.first;
          controller.selectAnnotation(
            page,
            controller.document.page(page).annotations.length - 1,
          );
        }
      }
    } finally {
      await route.completed;
      field.dispose();
      if (mounted) {
        setState(() => _notePromptOpen = false);
        _publishMenu();
      }
    }
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
    _activity ??= captureDocumentActivity(ref, widget.file, widget.side);
    setState(() {
      _loading = true;
      _error = null;
      _errorDetail = null;
    });
    _publishMenu();
    PdfEditingController? candidate;
    office.PdfEditorController? officeCandidate;
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
      if (widget.backend == PdfEditorBackend.crispOffice) {
        officeCandidate = office.PdfEditorController.fromBytes(
          bytes,
          password: password,
          config: const office.OfficeSurfaceConfig(
            mode: office.OfficeInteractionMode.editing,
          ),
        )..markClean();
      }
      _copyOnly = PdfSignature.of(candidate.document).isNotEmpty;
      _updateRedactionStatus(candidate.document);
      _controller = candidate;
      _commands = PdfEditorCommands(
        controller: candidate,
        viewerController: _viewer,
        tools: _editingTools,
      );
      candidate = null;
      _revision = _controller!.revisionId;
      _session = PdfEditSession(initialBytes: bytes)
        ..addListener(_onSessionChanged);
      _controller!.addListener(_onRevision);
      _officeController = officeCandidate;
      officeCandidate = null;
      if (_officeController != null) {
        _officePassword = password;
        _officeController!.addListener(_onOfficeRevision);
      }
      _activity?.opened();
      _workspace ??= DocumentWorkspaceSession.attach(context, _requestClose);
      setState(() => _loading = false);
      _publishMenu();
    } catch (error, stack) {
      officeCandidate?.dispose();
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
      _publishMenu();
    }
  }

  Future<String?> _askPassword({
    required bool incorrect,
    String? fileName,
  }) async {
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
            if (fileName != null) ...[
              Text(fileName),
              const SizedBox(height: 8),
            ],
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
    if (!mounted) return;
    setState(() {});
    _publishMenu();
  }

  void _onRevision() {
    final controller = _controller!;
    final pendingChanged = _hadPendingInk != controller.hasPendingInk;
    _hadPendingInk = controller.hasPendingInk;
    if (controller.revisionId != _revision) {
      _revision = controller.revisionId;
      _updateRedactionStatus(controller.document);
      _session!.updateBytes(controller.bytes);
      _publishMenu();
    } else if (pendingChanged) {
      // Update host chrome only on draft transitions, not every pointer sample.
      if (mounted) setState(() {});
      _publishMenu();
    }
  }

  int _officeObservedRevision = 0;
  Object? _officeSelection;
  void _onOfficeRevision() {
    final c = _officeController;
    if (c == null || !mounted) return;
    if (c.contentRevision == _officeObservedRevision &&
        identical(c.selection, _officeSelection)) {
      return;
    }
    _officeObservedRevision = c.contentRevision;
    _officeSelection = c.selection;
    setState(() {});
    _publishMenu();
  }

  bool _flushPendingInk() {
    try {
      if (_officeController case final c?) {
        if (c.contentRevision != _officeSnapshotRevision) {
          _session?.updateBytes(c.saveBytes());
          _officeSnapshotRevision = c.contentRevision;
        }
        return true;
      }
      _controller?.finishInk();
      if (_controller != null) _onRevision();
      return true;
    } catch (error, stack) {
      _log.warn('Could not commit pending PDF ink', error, stack);
      if (mounted) _notice('Could not save PDF', detail: '$error');
      return false;
    }
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
    if (!_flushPendingInk()) return null;
    copy = copy || _copyOnly;
    if (!copy && !session.isDirty) return PdfSaveOutcome.savedOriginal;
    String? fileName;
    if (copy) {
      setState(() => _choosingSave = true);
      _publishMenu();
      try {
        fileName = await _askCopyName('edited');
      } finally {
        if (mounted) {
          setState(() => _choosingSave = false);
          _publishMenu();
        }
      }
      if (!mounted || fileName == null) return null;
    }
    if (_officeController == null) _onRevision();
    final savedRevision = _currentRevision;
    final copyName = fileName;
    try {
      final outcome = await session.save(
        copyName == null
            ? _store!.save
            : (bytes) => _store!.saveCopy(bytes, copyName),
      );
      if (outcome == PdfSaveOutcome.savedOriginal) {
        if (_currentRevision == savedRevision) {
          _officeController?.markClean();
          _publishMenu();
        }
        _activity?.edited();
      }
      if (outcome == PdfSaveOutcome.savedCopy && copyName != null) {
        _activity?.editedSibling(copyName);
      }
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
    if (!_flushPendingInk()) return null;
    final snapshot = Uint8List.fromList(_session!.bytes);
    final revision = _currentRevision;
    setState(() => _exporting = true);
    _publishMenu();
    try {
      final exporter = widget.deviceExporterOverride ?? exportPdfCopy;
      final outcome = await exporter(snapshot, _suggestCopyName('edited'));
      if (!mounted || outcome == null) return outcome;
      _lastCopyRevision = revision;
      _notice(
        outcome == PdfSaveOutcome.downloadedCopy
            ? 'Download started. Keep the downloaded file before closing.'
            : 'PDF exported to the selected destination.',
      );
      return outcome;
    } catch (error, stack) {
      _log.warn('Could not export PDF', error, stack);
      if (mounted) _notice('Could not export PDF', detail: '$error');
      return null;
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
        _publishMenu();
      }
    }
  }

  Future<void> _requestClose() async {
    if (_busy || _closing || _allowPop) return;
    _closing = true;
    try {
      if (!_flushPendingInk()) return;
      if (!_isDirty) {
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
          if (!_isDirty) {
            await _leave();
          } else {
            _notice(
              'New changes were made while saving. Save them before closing.',
            );
          }
        } else if (_lastCopyRevision == _currentRevision && !_hasPendingInk) {
          final close = await _confirm(
            'Close after saving a copy?',
            'Make sure the saved or downloaded copy is available before closing.',
            'Close editor',
          );
          if (close &&
              mounted &&
              _lastCopyRevision == _currentRevision &&
              !_hasPendingInk) {
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
    _messenger.currentState?.hideCurrentSnackBar();
    _clearMenu();
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

  Future<List<PdfInsertFile>> _pickPdfFiles() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        allowMultiple: true,
        withData: true,
      );
      if (!mounted || picked == null) return const [];
      final files = <PdfInsertFile>[];
      var totalBytes = _controller!.bytes.length;
      var importsProtectedPages = false;
      for (final file in picked.files) {
        final bytes = file.bytes;
        if (file.size > kPdfEditorInputLimitBytes ||
            (bytes?.length ?? 0) > kPdfEditorInputLimitBytes) {
          throw const PdfFileTooLargeException(kPdfEditorInputLimitBytes);
        }
        if (bytes == null) {
          throw const _PdfOpenMessage(
            'The browser did not provide file contents. Please select the file again.',
          );
        }
        totalBytes += bytes.length;
        if (totalBytes > 256 * 1024 * 1024) {
          throw _PdfOpenMessage(
            context.pdfOpTr('Selected PDFs exceed the 256 MiB input limit.'),
          );
        }
        PdfDocument? document;
        var password = '';
        var attemptedPassword = false;
        while (document == null) {
          try {
            document = PdfDocument.open(bytes, password: password);
          } on CosPasswordException {
            final entered = await _askPassword(
              incorrect: attemptedPassword,
              fileName: file.name,
            );
            if (!mounted || entered == null) return const [];
            password = entered;
            attemptedPassword = true;
          }
        }
        if (PdfAcroForm.of(document)?.hasXfa ?? false) {
          throw const _PdfOpenMessage(
            'XFA forms cannot be edited here. Open this PDF with an XFA-capable application.',
          );
        }
        importsProtectedPages |= document.cos.isEncrypted;
        files.add(PdfInsertFile(file.name, bytes, password: password));
      }
      if (importsProtectedPages && !_controller!.document.cos.isEncrypted) {
        if (!await _confirm(
              context.pdfOpTr('Insert protected pages?'),
              context.pdfOpTr(
                'The inserted pages will use this document’s protection. This document has no password protection.',
              ),
              'Continue',
            ) ||
            !mounted) {
          return const [];
        }
      }
      return files;
    } catch (error) {
      if (mounted) _notice('Could not read selected file', detail: '$error');
      return const [];
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

  Widget _buildSurface() {
    if (_officeController case final c?) {
      final editor = office.QudsPdfEditor(
        controller: c,
        config: c.config,
        toolbarBuilder: (context, c) => Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              key: const ValueKey('office-pdf-undo'),
              tooltip: context.pdfTr('Undo'),
              onPressed: !_busy && c.commands.canUndo ? c.undo : null,
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              tooltip: context.pdfTr('Redo'),
              onPressed: !_busy && c.commands.canRedo ? c.redo : null,
              icon: const Icon(Icons.redo),
            ),
            IconButton(
              key: const ValueKey('office-pdf-rotate'),
              tooltip: context.pdfTr('Rotate page'),
              onPressed: !_busy && (c.file?.permissions?.canModify ?? true)
                  ? () => c.rotateCurrentPage(90)
                  : null,
              icon: const Icon(Icons.rotate_right),
            ),
            IconButton(
              tooltip: context.pdfTr('Highlight'),
              onPressed:
                  !_busy &&
                      c.selection != null &&
                      (c.file?.permissions?.canAnnotate ?? true)
                  ? c.highlightSelection
                  : null,
              icon: const Icon(Icons.highlight),
            ),
            IconButton(
              tooltip: context.pdfTr('Zoom out'),
              onPressed: () => c.zoomBy(1 / 1.2),
              icon: const Icon(Icons.zoom_out),
            ),
            IconButton(
              tooltip: context.pdfTr('Zoom in'),
              onPressed: () => c.zoomBy(1.2),
              icon: const Icon(Icons.zoom_in),
            ),
            TextButton(
              onPressed: () => c.applyFitPolicy(office.PdfFitPolicy.width),
              child: Text(context.pdfTr('Fit width')),
            ),
            TextButton(
              onPressed: () => c.applyFitPolicy(office.PdfFitPolicy.page),
              child: Text(context.pdfTr('Fit page')),
            ),
          ],
        ),
      );
      return Column(
        children: [
          PdfReviewStatus(controller: c),
          Expanded(child: editor),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final floating = constraints.maxWidth >= 800;
        final view = PdfEditorView(
          controller: _controller!,
          commands: _commands,
          viewerController: _viewer,
          textMenuBuilder: (context, request) => [
            if (request.hasSelection)
              PdfTextMenuItem(
                key: const ValueKey('pdf-text-attach-note'),
                label: pdfWorkspaceTr(context, 'Attach note'),
                icon: Icons.add_comment_outlined,
                onSelected: (captured) => _attachNote(request: captured),
              ),
          ],
          documentId: _store!.documentId,
          autoRenderWorker: widget.autoRenderWorker,
          features: PdfEditorFeatures(tools: _editingTools, toolbar: !floating),
          // The surface owns Ctrl/Cmd+S. Registering another
          // host binding would risk starting two writes.
          showSaveButton: false,
          alwaysAllowSave: true,
          onSave: (_) => unawaited(_save()),
          onSaveAs: (_) => unawaited(_save(copy: true)),
          onPickPdfFilesToInsert: _pickPdfFiles,
          imagePicker: (_) => _pickFile(['png', 'jpg', 'jpeg']),
          onExportPages: (bytes) => unawaited(_exportPages([bytes])),
          onSplitPages: (bytes) => unawaited(_exportPages(bytes)),
          // No signing callback: the certificate-signing tool
          // stays hidden. Hand-drawn ink signatures remain.
        );
        if (!floating) return view;
        return PdfMaterialHost(
          child: PdfEditorCommandsScope(
            commands: _commands!,
            child: PdfFloatingToolbars(
              commands: _commands!,
              controller: _controller!,
              child: view,
              barBuilder: (context, primary, vertical, handle) =>
                  PdfEditingToolbar(
                    controller: _controller!,
                    viewerController: _viewer,
                    tools: _editingTools,
                    compact: false,
                    dense: true,
                    showPrimaryBar: primary,
                    showContextBar: !primary,
                    moveHandle: handle,
                    dock: vertical ? PdfPanelDock.left : PdfPanelDock.bottom,
                    imagePicker: (_) => _pickFile(['png', 'jpg', 'jpeg']),
                    onAnnotationLibraryPressed: () =>
                        _preferences!.showAnnotationLibraryPanel =
                            !_preferences!.showAnnotationLibraryPanel,
                  ),
            ),
          ),
        );
      },
    );
  }

  KeyEventResult _onPageKey(FocusNode node, KeyEvent event) {
    final direction = documentPageDirection(event);
    if (direction == null || (ModalRoute.of(context)?.isCurrent == false)) {
      return KeyEventResult.ignored;
    }
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus?.findAncestorWidgetOfExactType<EditableText>() != null) {
      return KeyEventResult.ignored;
    }
    if (_officeController case final controller?) {
      scrollOfficePdfViewport(controller, direction);
    } else {
      scrollPdfViewport(_viewer, direction);
    }
    return KeyEventResult.handled;
  }

  Future<void> _printDocument() async {
    if (!_flushPendingInk() || _controller == null) return;
    await printPdfDocumentSnapshot(
      context,
      _officeController != null
          ? PdfDocument.open(_session!.bytes, password: _officePassword)
          : _controller!.document,
      widget.file.name,
      currentPage: _officeController?.pageIndex ?? _viewer.currentPage,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dirty = _isDirty;
    final controller = _controller;
    final printContent = PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_requestClose());
      },
      child: AppScaffoldMessenger(
        key: _messenger,
        child: Scaffold(
          appBar: ref.watch(nativePdfToolbarReadyProvider)
              ? null
              : AppBar(
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
                    const DocumentPrintMenu(),
                    const DocumentPrintButton(),
                    if (controller != null) ...[
                      IconButton(
                        key: const ValueKey('pdf-save'),
                        tooltip: context.pdfTr(
                          _copyOnly ? 'Save a copy' : 'Save',
                        ),
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
                        onPressed: _busy
                            ? null
                            : () => unawaited(_exportDevice()),
                        icon: const Icon(Icons.download_outlined),
                      ),
                    ],
                    ListenableBuilder(
                      listenable: Listenable.merge([
                        _viewer,
                        if (_controller != null) _controller!,
                      ]),
                      builder: (context, _) => IconButton(
                        key: const ValueKey('pdf-attach-note'),
                        tooltip: pdfWorkspaceTr(context, 'Attach note'),
                        icon: const Icon(Icons.add_comment_outlined),
                        onPressed: !_busy && _canAttachNote
                            ? () => unawaited(_attachNote())
                            : null,
                      ),
                    ),
                  ],
                ),
          body: Column(
            children: [
              if (_busy && !_notePromptOpen) const LinearProgressIndicator(),
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
                    : _buildSurface(),
              ),
            ],
          ),
        ),
      ),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          if (ModalRoute.of(context)?.isCurrent != false) {
            unawaited(_save());
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () {
          if (ModalRoute.of(context)?.isCurrent != false) {
            unawaited(_save());
          }
        },
      },
      child: DocumentPrintScope(
        enabled: _controller != null && !_loading && !_busy && !_closing,
        onPrint: _printDocument,
        child: Focus(
          autofocus: true,
          onKeyEvent: _onPageKey,
          child: printContent,
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
