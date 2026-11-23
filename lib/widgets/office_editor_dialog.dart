import '../services/document_printing.dart';
import '../services/office_measurement_preferences.dart';
import '../services/office_spacy.dart';
import '../services/office_spacy_preferences.dart';
import 'document_print_scope.dart';
import 'viewer_escape_scope.dart';
import 'app_scaffold_messenger.dart' show TransientSnackBar;
import '../services/document_workspace_session.dart';
import '../services/document_activity.dart';
import '../services/document_history.dart';
// lib/widgets/office_editor_dialog.dart
//
// F4 editor for Office Open XML documents (DOCX / XLSX / PPTX) built on the
// MIT-licensed `quds_office_editor` surfaces. The package paints the document;
// this dialog provides the host chrome: loading, save, undo/redo, dirty state
// and the unsaved-changes prompt.
//
// Legacy .xls workbooks are imported into the shared spreadsheet model and
// opened as XLSX; Save writes a new .xlsx copy so the original BIFF file is
// never overwritten. .doc/.ppt and ODT/ODP still get a clear message because
// they cannot be converted in-process yet.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb, listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/io_client.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:quds_office_editor/quds_office_editor.dart'
    hide WordPackagePreservation;
import 'package:quds_office_engine/quds_office_engine.dart'
    show
        LegacySheetReader,
        OdsSheetReader,
        OfficeIsolateSave,
        WordPackagePreservation;

import '../models/file_item.dart';
import '../models/storage_reference.dart';
import '../services/storage_identity.dart';
import '../services/panel_source_service.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/captured_file_target.dart';
import '../services/office_device_export.dart';
import '../services/office_page_preview.dart';
import '../services/log_service.dart';
import '../services/office_zotero.dart';
import '../l10n/file_bytes_error_strings.dart';
import '../l10n/office_editor_strings.dart';
import '../l10n/office_recovery_strings.dart';
import '../l10n/office_surface_strings.dart';
import '../l10n/word_format_strings.dart';
import '../services/office_editor_menu.dart';
import '../services/document_fonts.dart';
import 'office_editor_find_bar.dart';
import 'office_editor_ribbon.dart';
import 'office_worksheet_bar.dart';

const _log = Log('OfficeEditor');

/// Extensions that belong to the Office dialog (editable or message-only).
const Set<String> kOfficeExtensions = <String>{
  'docx',
  'docm',
  'dotx',
  'dotm',
  'xlsx',
  'xlsm',
  'xltx',
  'pptx',
  'pptm',
  'potx',
  'potm',
  'ppsx',
  'ppsm',
  'pot',
  'odt',
  'ods',
  'odp',
  'doc',
  'dot',
  'xls',
  'ppt',
  'pps',
};

bool isOfficeFileName(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return false;
  return kOfficeExtensions.contains(name.substring(dot + 1).toLowerCase());
}

bool _isEditableOoxml(String name) {
  final ext = name.split('.').last.toLowerCase();
  return ext == 'docx' ||
      WordPackagePreservation.contentTypesByExtension.containsKey(ext) ||
      ext == 'xlsx' ||
      ext == 'xlsm' ||
      ext == 'xltx' ||
      ext == 'pptx';
}

Future<void> showOfficeEditorDialog(
  BuildContext context,
  WidgetRef ref,
  FileItem file,
  PanelSide side, {
  Uint8List? bytesOverride,
  CapturedFileTarget? targetOverride,
  OfficeDeviceExporter copyExporter = exportOfficeCopy,
  OfficeSaveAsExporter saveAsExporter = saveOfficeAs,
  String? saveAsName,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => Dialog.fullscreen(
      child: OfficeEditorDialog(
        file: file,
        side: side,
        bytesOverride: bytesOverride,
        targetOverride: targetOverride,
        copyExporter: copyExporter,
        saveAsExporter: saveAsExporter,
        saveAsName: saveAsName,
      ),
    ),
  );
}

class OfficeEditorDialog extends ConsumerStatefulWidget {
  final FileItem file;
  final PanelSide side;

  /// Test/embedded hook: use these bytes instead of reading [file].
  final Uint8List? bytesOverride;

  /// Verified newly created document; keeps conversion/editor handoff bound
  /// to its original storage even if the invoking pane has changed.
  final CapturedFileTarget? targetOverride;

  /// Independent device-copy export; never changes the original save target.
  final OfficeDeviceExporter copyExporter;
  final OfficeSaveAsExporter saveAsExporter;

  /// Output name when the loaded workbook is a converted legacy `.xls`.
  final String? saveAsName;

  const OfficeEditorDialog({
    super.key,
    required this.file,
    required this.side,
    this.bytesOverride,
    this.targetOverride,
    this.copyExporter = exportOfficeCopy,
    this.saveAsExporter = saveOfficeAs,
    this.saveAsName,
  });

  @override
  ConsumerState<OfficeEditorDialog> createState() => _OfficeEditorDialogState();
}

class _OfficeEditorDialogState extends ConsumerState<OfficeEditorDialog> {
  late FileItem _file = widget.file;
  DocumentWorkspaceSession? _workspace;
  DocumentActivity? _activity;
  OfficeController? _controller;
  OfficeEditorKind _kind = OfficeEditorKind.unsupported;
  Uint8List? _loadedBytes;
  CapturedFileTarget? _target;
  WordPackagePreservation? _wordPreservation;
  bool _loading = true;
  bool _saving = false;
  bool _exporting = false;
  bool _closing = false;
  bool _dirty = false;
  bool _convertedLegacySheet = false;
  String? _error;
  final FocusNode _focusNode = FocusNode(debugLabel: 'QudsOfficeEditor');
  final GlobalKey<OfficeEditorRibbonState> _ribbonKey =
      GlobalKey<OfficeEditorRibbonState>();
  OfficeEditorMenuActions? _menuActions;
  ProviderContainer? _providerContainer;
  final ZoteroSession _zoteroSession = ZoteroSession();
  OfficeZoteroTransport? _zoteroTransport;
  bool _zoteroCredentialsLoaded = false;
  bool _zoteroOpen = false;

  int _unitRevision = 0;

  OfficeSurfaceConfig _config = const OfficeSurfaceConfig(
    mode: OfficeInteractionMode.editing,
    autofocus: true,
    adaptiveChrome: true,
  );

  @override
  void initState() {
    super.initState();
    OfficeSpacyPreferences.changes.addListener(_onSpacyChanged);
    _target = widget.targetOverride;
    unawaited(_load());
    unawaited(_loadUnits());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _providerContainer = ProviderScope.containerOf(context, listen: false);
    _config = _config.copyWith(strings: OfficeSurfaceStrings.of(context));
    _controller?.syncConfig(_config);
  }

  @override
  void dispose() {
    _spacyGeneration++;
    OfficeSpacyPreferences.changes.removeListener(_onSpacyChanged);
    _zoteroTransport?.dispose();
    _zoteroSession.apiKey = null;
    _workspace?.dispose();
    final ProviderContainer? container = _providerContainer;
    final OfficeEditorMenuActions? actions = _menuActions;
    _menuActions = null;
    _providerContainer = null;
    if (container != null && actions != null) {
      // Clearing the native-menu bridge mutates a provider. Do it after the
      // widget tree leaves its build/deactivate phases.
      scheduleMicrotask(() {
        try {
          if (identical(container.read(officeEditorMenuProvider), actions)) {
            container.read(officeEditorMenuProvider.notifier).state = null;
          }
        } catch (_) {
          // The provider container may already be disposed.
        }
      });
    }
    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  OfficeEditorKind _kindFor(String name) {
    final ext = name.split('.').last.toLowerCase();
    // Legacy Excel and ODS are converted to XLSX in memory before loading.
    if (ext == 'xls' || ext == 'xlt' || ext == 'ods') {
      return OfficeEditorKind.sheet;
    }
    if (!_isEditableOoxml(name)) return OfficeEditorKind.unsupported;
    switch (ext) {
      case 'docx':
      case 'docm':
      case 'dotx':
      case 'dotm':
        return OfficeEditorKind.word;
      case 'xlsx':
      case 'xlsm':
      case 'xltx':
        return OfficeEditorKind.sheet;
      case 'pptx':
        return OfficeEditorKind.slides;
      default:
        return OfficeEditorKind.unsupported;
    }
  }

  Future<void> _load() async {
    _activity ??= captureDocumentActivity(ref, _file, widget.side);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await DocumentFonts.ensureRegistered();
      Uint8List bytes;
      if (widget.bytesOverride case final supplied?) {
        bytes = supplied;
      } else {
        final panel = ref.read(panelProvider(widget.side));
        final target = _target ??= panel.captureFileTarget(
          _file,
          maxBytes: officeSlideInputLimit(
            _file.name,
            local: panel.directoryStorage?.isLocal ?? false,
          ),
        );
        bytes = await target.load();
      }
      if (!mounted) return;

      // Preserve the actual source even when legacy import itself is refused.
      _loadedBytes = Uint8List.fromList(bytes).asUnmodifiableView();

      // BIFF workbooks are imported into the shared model and opened as XLSX.
      // Saving writes a new .xlsx copy; the original .xls is never rewritten.
      final sourceExt = _file.name.split('.').last.toLowerCase();
      if (sourceExt == 'xls' || sourceExt == 'xlt' || sourceExt == 'ods') {
        final workbook = sourceExt == 'ods'
            ? OdsSheetReader.readBytes(bytes)
            : LegacySheetReader.readBytes(bytes);
        bytes = await OfficeIsolateSave.workbook(workbook, recalculate: false);
        _convertedLegacySheet = true;
      }

      final kind = _kindFor(widget.saveAsName ?? _file.name);
      if (kind == OfficeEditorKind.unsupported) {
        setState(() {
          _loading = false;
          _kind = kind;
        });
        return;
      }

      _wordPreservation = await WordPackagePreservation.capture(
        bytes,
        _file.name,
      );
      if (!mounted) return;
      final controller = switch (kind) {
        OfficeEditorKind.word => WordEditorController.fromBytes(
          bytes,
          config: _config,
        ),
        OfficeEditorKind.sheet => SheetEditorController.fromBytes(
          bytes,
          config: _config,
          formulaLocale: Localizations.maybeLocaleOf(context)?.toLanguageTag(),
        ),
        OfficeEditorKind.slides => SlideEditorController.fromBytes(
          bytes,
          config: _config,
        ),
        OfficeEditorKind.unsupported => null,
      };
      if (!mounted) {
        controller?.dispose();
        return;
      }
      controller?.addListener(_onControllerChanged);
      controller?.onPrintRequested = () =>
          ref.read(documentPrintProvider)?.run();
      // Documents with footnotes or endnotes open with the notes pane, the
      // place where their text is edited.
      if (controller is WordEditorController &&
          (controller.document.footnotes.isNotEmpty ||
              controller.document.endnotes.isNotEmpty)) {
        _config = _config.copyWith(showNotesPane: true);
        controller.syncConfig(_config);
      }
      setState(() {
        _controller = controller;
        _kind = kind;
        _dirty = controller?.isDirty ?? false;
        _loading = false;
      });
      _onSpacyChanged();
      _activity?.opened();
      _workspace ??= DocumentWorkspaceSession.attach(context, _close);
      _registerMenu();
    } catch (e, st) {
      _log.warn('office editor load failed', e, st);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            '${context.tr('Could not open this document')}: '
            '${_localizedError(e)}';
      });
    }
  }

  int _spacyGeneration = 0;

  void _onSpacyChanged() {
    final controller = _controller;
    final generation = ++_spacyGeneration;
    if (controller is! WordEditorController) return;
    controller.proofing.configureManual(null);
    unawaited(() async {
      try {
        final service = await openOfficeSpacyManualService();
        if (!mounted ||
            generation != _spacyGeneration ||
            !identical(controller, _controller)) {
          await service?.dispose();
          return;
        }
        controller.proofing.configureManual(service);
      } on Object catch (error, stack) {
        _log.warn('optional native grammar unavailable', error, stack);
        if (mounted && generation == _spacyGeneration) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Optional German grammar is unavailable: $error'),
            ),
          );
        }
      }
    }());
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final dirty = _controller?.isDirty ?? false;
    if (dirty == _dirty) return;
    setState(() => _dirty = dirty);
  }

  String _localizedError(Object error) {
    final locale = Localizations.localeOf(context);
    return OfficeRecoveryStrings.error(locale.languageCode, error) ??
        WordFormatStrings(locale).translate(error.toString()) ??
        localizedFileBytesError(context, error);
  }

  void _showNotice(SnackBar notice) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(notice);
  }

  Future<void> _save({bool popAfter = false}) async {
    final controller = _controller;
    if (controller == null || _saving || _exporting) return;
    if (_convertedLegacySheet) {
      // The source is BIFF; writing OOXML bytes over it would corrupt it.
      await _saveCopy(asLegacySave: true);
      if (popAfter &&
          mounted &&
          !_dirty &&
          ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pop();
      }
      return;
    }
    setState(() => _saving = true);
    try {
      // Keep the existing pre-save backup as well as the edited recovery copy.
      // A failed upload must not replace the only snapshot of either revision.
      final previousBytes = _loadedBytes;
      if (previousBytes != null) {
        await _saveSnapshot(previousBytes, kind: 'original');
      }
      if (!mounted) return;
      // Serialization captures this document revision. Editing remains enabled
      // while encoding/uploading, so completing this write cannot clean a newer
      // revision or dismiss it through Save and Close.
      // Inline notes, cells, and slide text can be visible before their undo
      // command is committed. Flush them before recording the saved revision.
      controller.commitPendingEdits();
      final savedRevision = controller.contentRevision;
      final bytes = await controller.saveBytesAsync();
      final saveLimit = controller is SlideEditorController
          ? officeSlideInputLimit(
              _file.name,
              local: _target?.reference.storage.isLocal ?? false,
            )
          : kOfficeCopyOutputLimitBytes;
      if (bytes.length > saveLimit) throw FileTargetTooLarge(saveLimit);
      await _wordPreservation?.validateSaved(bytes);
      await _saveSnapshot(bytes, kind: 'recovery');
      if (!mounted) return;
      final target = _target;
      if (target == null) {
        throw StateError(
          'This preview has no verified save target. Reopen the original file.',
        );
      }
      final outcome = await target.save(bytes);
      if (outcome != FileWriteOutcome.savedOriginal) {
        throw const FileTargetConflict(
          'A copy was downloaded. The original is unchanged.',
        );
      }
      _activity?.edited();
      _loadedBytes = Uint8List.fromList(bytes).asUnmodifiableView();
      if (!mounted) return;
      if (controller.contentRevision == savedRevision) controller.markClean();
      setState(() {
        _saving = false;
        _dirty = controller.isDirty;
      });
      ref.read(panelProvider(widget.side)).refreshFiles();
      _showNotice(
        TransientSnackBar(
          content: Text('${context.tr('Saved')}: ${_file.name}'),
        ),
      );
      // A notes/formatting dialog can hold a newer draft while the upload runs.
      // Only close this editor's own route; popping the current top route would
      // cancel that dialog and silently discard its unapplied text.
      if (popAfter &&
          mounted &&
          !_dirty &&
          ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pop();
      }
    } catch (e, st) {
      _log.warn('office editor save failed', e, st);
      if (!mounted) return;
      setState(() => _saving = false);
      _showNotice(
        SnackBar(
          content: Text(
            '${context.tr('Save failed')}: '
            '${_localizedError(e)}',
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
          action: SnackBarAction(
            label: context.tr('Save a copy'),
            onPressed: () => unawaited(_saveCopy()),
          ),
        ),
      );
    }
  }

  Future<void> _close() async {
    if (_saving || _exporting || _closing) return;
    _closing = true;
    try {
      // Pending inline drafts participate in the controller's dirty state. Keep
      // them pending until Save so Cancel and Discard also work for invalid input.
      if (!(_controller?.isDirty ?? _dirty)) {
        Navigator.of(context).pop();
        return;
      }
      final action = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(context.tr('Unsaved changes')),
          content: Text(
            '${context.tr('Save changes to')} ${_file.name} ${context.tr('before closing?')}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'cancel'),
              child: Text(context.tr('Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'discard'),
              child: Text(context.tr('Discard')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, 'save'),
              child: Text(context.tr('Save')),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (action == 'save') {
        await _save(popAfter: true);
      } else if (action == 'discard') {
        Navigator.of(context).pop();
      }
    } finally {
      _closing = false;
    }
  }

  Future<void> _saveAs() async {
    final controller = _controller;
    if (controller == null || _saving || _exporting) return;
    setState(() => _exporting = true);
    try {
      controller.commitPendingEdits();
      final revision = controller.contentRevision;
      final bytes = await controller.saveBytesAsync();
      if (bytes.length > kOfficeCopyOutputLimitBytes) {
        throw FileTargetTooLarge(kOfficeCopyOutputLimitBytes);
      }
      await _wordPreservation?.validateSaved(bytes);
      if (!mounted) return;
      final destination = await widget.saveAsExporter(
        Uint8List.fromList(bytes).asUnmodifiableView(),
        _copyOutputName(),
        context.tr('Save As'),
        initialDirectory: _copyInitialDirectory,
      );
      if (destination == null || !mounted) return;
      final file = FileItem(
        name: path.basename(destination),
        path: destination,
        isFolder: false,
        size: bytes.length,
      );
      final reference = FileReference(
        storage: storageReferenceForSource(
          LocalPanelSource(path.dirname(destination)),
        ),
        path: destination,
      );
      final target = CapturedFileTarget.local(
        reference: reference,
        service: ref.read(localFileServiceProvider),
        file: file,
        isCurrent: () => true,
        maxBytes: kOfficeCopyOutputLimitBytes,
      );
      final written = await target.load();
      if (!listEquals(written, bytes)) {
        throw const FileTargetConflict(
          'The new file changed before it could be opened.',
        );
      }
      if (!mounted) return;
      _target = target;
      _loadedBytes = Uint8List.fromList(bytes).asUnmodifiableView();
      _convertedLegacySheet = false;
      _activity = DocumentActivity(ref.read(documentHistoryProvider), reference)
        ..edited();
      if (controller.contentRevision == revision) controller.markClean();
      setState(() {
        _file = file;
        _dirty = controller.isDirty;
      });
      ref.read(panelProvider(widget.side)).refreshFiles();
      _showNotice(
        TransientSnackBar(
          content: Text('${context.tr('Saved')}: ${file.name}'),
        ),
      );
    } catch (error, stack) {
      _log.warn('office Save As failed', error, stack);
      if (mounted) {
        _showNotice(
          SnackBar(
            content: Text(
              '${context.tr('Save failed')}: ${_localizedError(error)}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String _odpOutputName() {
    final name = widget.saveAsName ?? _file.name;
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    return officeCopyName('$base.odp');
  }

  Future<void> _exportOdp() async {
    if (_saving || _exporting) return;
    final controller = _controller;
    if (controller is! SlideEditorController) return;
    setState(() => _exporting = true);
    try {
      controller.commitPendingEdits();
      final bytes = OdpPresentationWriter.writeBytes(controller.presentation);
      if (bytes.length > kOfficeCopyOutputLimitBytes) {
        throw FileTargetTooLarge(kOfficeCopyOutputLimitBytes);
      }
      if (!mounted) return;
      final outcome = await widget.copyExporter(
        Uint8List.fromList(bytes).asUnmodifiableView(),
        _odpOutputName(),
        context.tr('Export as ODP'),
        initialDirectory: _copyInitialDirectory,
      );
      if (!mounted || outcome == null) return;
      _showNotice(
        TransientSnackBar(
          content: Text(
            context.tr(
              outcome == OfficeCopyOutcome.savedCopy
                  ? 'Copy saved. The original is unchanged.'
                  : 'Copy download started. The original is unchanged.',
            ),
          ),
        ),
      );
    } catch (e, st) {
      _log.warn('ODP export failed', e, st);
      if (!mounted) return;
      _showNotice(
        SnackBar(
          content: Text(
            '${context.tr('Could not save a copy')}: ${_localizedError(e)}',
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String _odtOutputName() {
    final name = widget.saveAsName ?? _file.name;
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    return officeCopyName('$base.odt');
  }

  Future<void> _exportOdt() async {
    if (_saving || _exporting) return;
    final controller = _controller;
    if (controller is! WordEditorController) return;
    setState(() => _exporting = true);
    try {
      controller.commitPendingEdits();
      final bytes = OdtDocumentWriter.writeBytes(controller.document);
      if (bytes.length > kOfficeCopyOutputLimitBytes) {
        throw FileTargetTooLarge(kOfficeCopyOutputLimitBytes);
      }
      if (!mounted) return;
      final outcome = await widget.copyExporter(
        Uint8List.fromList(bytes).asUnmodifiableView(),
        _odtOutputName(),
        context.tr('Export as ODT'),
        initialDirectory: _copyInitialDirectory,
      );
      if (!mounted || outcome == null) return;
      _showNotice(
        TransientSnackBar(
          content: Text(
            context.tr(
              outcome == OfficeCopyOutcome.savedCopy
                  ? 'Copy saved. The original is unchanged.'
                  : 'Copy download started. The original is unchanged.',
            ),
          ),
        ),
      );
    } catch (e, st) {
      _log.warn('ODT export failed', e, st);
      if (!mounted) return;
      _showNotice(
        SnackBar(
          content: Text(
            '${context.tr('Could not save a copy')}: ${_localizedError(e)}',
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String _odsOutputName() {
    final name = widget.saveAsName ?? _file.name;
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    return officeCopyName('$base.ods');
  }

  Future<void> _exportOds() async {
    if (_saving || _exporting) return;
    final controller = _controller;
    if (controller is! SheetEditorController) return;
    setState(() => _exporting = true);
    try {
      controller.commitPendingEdits();
      final bytes = OdsSheetWriter.writeBytes(controller.workbook);
      if (bytes.length > kOfficeCopyOutputLimitBytes) {
        throw FileTargetTooLarge(kOfficeCopyOutputLimitBytes);
      }
      if (!mounted) return;
      final outcome = await widget.copyExporter(
        Uint8List.fromList(bytes).asUnmodifiableView(),
        _odsOutputName(),
        context.tr('Export as ODS'),
        initialDirectory: _copyInitialDirectory,
      );
      if (!mounted || outcome == null) return;
      _showNotice(
        TransientSnackBar(
          content: Text(
            context.tr(
              outcome == OfficeCopyOutcome.savedCopy
                  ? 'Copy saved. The original is unchanged.'
                  : 'Copy download started. The original is unchanged.',
            ),
          ),
        ),
      );
    } catch (e, st) {
      _log.warn('ODS export failed', e, st);
      if (!mounted) return;
      _showNotice(
        SnackBar(
          content: Text(
            '${context.tr('Could not save a copy')}: ${_localizedError(e)}',
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _saveCopy({
    bool original = false,
    bool asLegacySave = false,
  }) async {
    if (_saving || _exporting) return;
    final controller = _controller;
    if ((!original && controller == null) ||
        (original && _loadedBytes == null)) {
      return;
    }
    setState(() => _exporting = true);
    try {
      final Uint8List bytes;
      int? exportedRevision;
      if (original) {
        bytes = _loadedBytes!;
      } else {
        controller!.commitPendingEdits();
        exportedRevision = controller.contentRevision;
        bytes = await controller.saveBytesAsync();
        await _wordPreservation?.validateSaved(bytes);
      }
      if (bytes.length > kOfficeCopyOutputLimitBytes) {
        throw FileTargetTooLarge(kOfficeCopyOutputLimitBytes);
      }
      if (!mounted) return;
      final outcome = await widget.copyExporter(
        Uint8List.fromList(bytes).asUnmodifiableView(),
        _copyOutputName(original: original),
        context.tr(original ? 'Export original' : 'Save a copy'),
        initialDirectory: _copyInitialDirectory,
      );
      if (!mounted || outcome == null) return;
      // Legacy Save has no writable original target. A completed native copy
      // may clean precisely the exported revision, never a later edit or a
      // merely initiated browser download. Ordinary Save a copy stays dirty.
      if (asLegacySave &&
          outcome == OfficeCopyOutcome.savedCopy &&
          controller != null &&
          controller.contentRevision == exportedRevision) {
        controller.markClean();
        setState(() => _dirty = controller.isDirty);
      }
      _showNotice(
        TransientSnackBar(
          content: Text(
            context.tr(
              outcome == OfficeCopyOutcome.savedCopy
                  ? 'Copy saved. The original is unchanged.'
                  : 'Copy download started. The original is unchanged.',
            ),
          ),
        ),
      );
      // Exporting a copy does not mark the original clean, replace its loaded
      // bytes, or close the editor. New edits made during the picker stay live.
    } catch (e, st) {
      _log.warn('office copy export failed', e, st);
      if (!mounted) return;
      _showNotice(
        SnackBar(
          content: Text(
            '${context.tr('Could not save a copy')}: '
            '${_localizedError(e)}',
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String? get _copyInitialDirectory {
    final reference = _target?.reference;
    // A remote provider path is not a device directory. Use the captured
    // original identity, independent of navigation in either browser pane.
    if (reference == null || !reference.storage.isLocal || kIsWeb) return null;
    return path.dirname(reference.path);
  }

  String _copyOutputName({bool original = false}) {
    if (original) return officeCopyName(_file.name);
    if (_convertedLegacySheet) {
      final source = _file.name;
      final converted =
          '${source.substring(0, source.lastIndexOf('.') + 1)}xlsx';
      return officeCopyName(widget.saveAsName ?? converted);
    }
    return officeCopyName(_file.name);
  }

  Future<void> _saveSnapshot(Uint8List bytes, {required String kind}) async {
    if (kIsWeb) return;
    try {
      final support = await getApplicationSupportDirectory();
      final dir = Directory('${support.path}/editor_snapshots');
      if (!await dir.exists()) await dir.create(recursive: true);
      final safeName = _file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final name = '${DateTime.now().microsecondsSinceEpoch}_${kind}_$safeName';
      await File('${dir.path}/$name').writeAsBytes(bytes, flush: true);
    } catch (_) {
      // Snapshots are best-effort.
    }
  }

  void _registerMenu() {
    final OfficeEditorMenuActions actions = OfficeEditorMenuActions(
      kind: _kind,
      perform: (OfficeEditorAction action) =>
          _ribbonKey.currentState?.perform(action),
    );
    _menuActions = actions;
    ref.read(officeEditorMenuProvider.notifier).state = actions;
  }

  Future<void> _loadUnits() async {
    final revision = _unitRevision;
    try {
      final unit = await OfficeMeasurementPreferences.read();
      if (!mounted || revision != _unitRevision) return;
      setState(() => _config = _config.copyWith(lengthUnit: unit));
      _controller?.syncConfig(_config);
    } catch (_) {
      /* Existing defaults remain usable. */
    }
  }

  void _onConfigChanged(OfficeSurfaceConfig next) {
    if (next.lengthUnit != _config.lengthUnit) {
      _unitRevision++;
      unawaited(
        OfficeMeasurementPreferences.write(next.lengthUnit).catchError((
          Object error,
        ) {
          _log.warn('Could not save measurement units', error);
        }),
      );
    }
    setState(() => _config = next);
    _controller?.syncConfig(next);
  }

  void _requestFind() {
    _controller?.requestFind();
  }

  void _handleEscape() {
    final OfficeController? controller = _controller;
    if (controller != null && controller.findSession.active) {
      controller.closeFind();
      return;
    }
    unawaited(_close());
  }

  void _wordShortcut(void Function(WmlRunProps props) update) {
    final OfficeController? controller = _controller;
    if (controller is WordEditorController) {
      controller.applyRunFormat(update);
    }
  }

  void _wordAlignment(WmlJustification value) {
    final controller = _controller;
    if (controller is WordEditorController) {
      controller.applyParagraphFormat((props) => props.justification = value);
    }
  }

  Future<void> _printDocument() async {
    final controller = _controller;
    if (controller == null) return;
    controller.commitPendingEdits();
    final bytes = await controller.saveBytesAsync();
    final pdf = await officePrintPdf(bytes);
    if (mounted) await printPdfSnapshot(context, pdf, _file.name);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final printContent = PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_close());
      },
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
              unawaited(_save()),
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
              unawaited(_save()),
          const SingleActivator(
            LogicalKeyboardKey.f12,
            includeRepeats: false,
          ): () =>
              unawaited(_saveAs()),
          for (final meta in [false, true]) ...{
            for (final entry in {
              LogicalKeyboardKey.keyL: WmlJustification.left,
              LogicalKeyboardKey.keyE: WmlJustification.center,
              LogicalKeyboardKey.keyR: WmlJustification.right,
              LogicalKeyboardKey.keyJ: WmlJustification.justify,
            }.entries)
              SingleActivator(entry.key, control: !meta, meta: meta): () =>
                  _wordAlignment(entry.value),
            SingleActivator(
              LogicalKeyboardKey.keyS,
              control: !meta,
              meta: meta,
              shift: true,
              includeRepeats: false,
            ): () =>
                unawaited(_saveAs()),
            SingleActivator(
              LogicalKeyboardKey.keyZ,
              control: !meta,
              meta: meta,
              shift: true,
            ): () =>
                _controller?.redo(),
            SingleActivator(
              LogicalKeyboardKey.keyH,
              control: !meta,
              meta: meta,
              includeRepeats: false,
            ): () =>
                _controller?.requestReplace(),
            SingleActivator(
              LogicalKeyboardKey.keyF,
              control: !meta,
              meta: meta,
              shift: true,
              includeRepeats: false,
            ): () =>
                _controller?.requestReplace(),
            SingleActivator(
              LogicalKeyboardKey.enter,
              control: !meta,
              meta: meta,
              includeRepeats: false,
            ): () =>
                _ribbonKey.currentState?.perform(OfficeEditorAction.pageBreak),
            SingleActivator(
              LogicalKeyboardKey.keyD,
              control: !meta,
              meta: meta,
              includeRepeats: false,
            ): () =>
                _ribbonKey.currentState?.perform(OfficeEditorAction.font),
          },
          const SingleActivator(
            LogicalKeyboardKey.keyW,
            control: true,
            includeRepeats: false,
          ): () =>
              unawaited(_close()),
          const SingleActivator(
            LogicalKeyboardKey.keyW,
            meta: true,
            includeRepeats: false,
          ): () =>
              unawaited(_close()),
          const SingleActivator(LogicalKeyboardKey.escape): _handleEscape,
          const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
              _ribbonKey.currentState?.perform(
                OfficeEditorAction.insertHyperlink,
              ),
          const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
              _ribbonKey.currentState?.perform(
                OfficeEditorAction.insertHyperlink,
              ),
          const SingleActivator(LogicalKeyboardKey.keyF, control: true):
              _requestFind,
          const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
              _requestFind,
          const SingleActivator(LogicalKeyboardKey.keyB, control: true): () =>
              _wordShortcut((WmlRunProps p) => p.bold = !p.bold),
          const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () =>
              _wordShortcut((WmlRunProps p) => p.bold = !p.bold),
          const SingleActivator(LogicalKeyboardKey.keyI, control: true): () =>
              _wordShortcut((WmlRunProps p) => p.italic = !p.italic),
          const SingleActivator(LogicalKeyboardKey.keyI, meta: true): () =>
              _wordShortcut((WmlRunProps p) => p.italic = !p.italic),
          const SingleActivator(LogicalKeyboardKey.keyU, control: true): () =>
              _wordShortcut(
                (WmlRunProps p) =>
                    p.underline = p.underline == WmlUnderline.none
                    ? WmlUnderline.single
                    : WmlUnderline.none,
              ),
          const SingleActivator(LogicalKeyboardKey.keyU, meta: true): () =>
              _wordShortcut(
                (WmlRunProps p) =>
                    p.underline = p.underline == WmlUnderline.none
                    ? WmlUnderline.single
                    : WmlUnderline.none,
              ),
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () =>
              _controller?.undo(),
          const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): () =>
              _controller?.undo(),
          const SingleActivator(LogicalKeyboardKey.keyY, control: true): () =>
              _controller?.redo(),
          const SingleActivator(LogicalKeyboardKey.keyY, meta: true): () =>
              _controller?.redo(),
        },
        child: Scaffold(
          body: SafeArea(top: true, bottom: false, child: _buildBody(theme)),
        ),
      ),
    );
    return ViewerEscapeScope(
      onEscape: _handleEscape,
      child: DocumentPrintScope(
        enabled: _controller != null && !_loading && !_saving && !_exporting,
        onPrint: _printDocument,
        child: printContent,
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error;
    if (error != null) {
      return _messagePane(error, theme);
    }
    if (_kind == OfficeEditorKind.unsupported) {
      return _messagePane(
        context.tr(
          'This Office format cannot be edited safely. Use F3 to view it, or save it as .docx / .xlsx / .pptx and edit that.',
        ),
        theme,
      );
    }
    final controller = _controller;
    if (controller == null) {
      return _messagePane(
        context.tr('The document could not be loaded.'),
        theme,
      );
    }
    final Widget editor = switch (_kind) {
      OfficeEditorKind.word => QudsWordEditor(
        controller: controller as WordEditorController,
        config: _config,
        focusNode: _focusNode,
        findBarBuilder: (BuildContext context, WordEditorController c) =>
            OfficeFindBar(controller: c),
      ),
      OfficeEditorKind.sheet => QudsSheetEditor(
        controller: controller as SheetEditorController,
        config: _config,
        focusNode: _focusNode,
        findBarBuilder: (BuildContext context, SheetEditorController c) =>
            OfficeFindBar(controller: c),
        navigationBuilder: (BuildContext context, SheetEditorController c) =>
            OfficeWorksheetBar(controller: c, editorFocusNode: _focusNode),
      ),
      OfficeEditorKind.slides => QudsSlideEditor(
        controller: controller as SlideEditorController,
        config: _config,
        focusNode: _focusNode,
        findBarBuilder: (BuildContext context, SlideEditorController c) =>
            OfficeFindBar(controller: c),
      ),
      OfficeEditorKind.unsupported => const SizedBox.shrink(),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        OfficeEditorRibbon(
          key: _ribbonKey,
          controller: controller,
          kind: _kind,
          config: _config,
          onSave: () => unawaited(_save()),
          onSaveCopy: () => unawaited(_saveCopy()),
          onExportOds: _kind == OfficeEditorKind.sheet
              ? () => unawaited(_exportOds())
              : null,
          onExportOdt: _kind == OfficeEditorKind.word
              ? () => unawaited(_exportOdt())
              : null,
          onExportOdp: _kind == OfficeEditorKind.slides
              ? () => unawaited(_exportOdp())
              : null,
          onSaveAs: kIsWeb ? null : () => unawaited(_saveAs()),
          onPrint: () => ref.read(documentPrintProvider)?.run(),
          onZotero: _kind == OfficeEditorKind.word
              ? () => unawaited(_showZotero())
              : null,
          onClose: () => unawaited(_close()),
          onConfigChanged: _onConfigChanged,
          onFind: _requestFind,
          title: _file.name,
          dirty: _dirty,
          saving: _saving || _exporting,
        ),
        Expanded(child: editor),
      ],
    );
  }

  Future<void> _showZotero() async {
    final controller = _controller;
    if (_zoteroOpen ||
        controller is! WordEditorController ||
        !controller.config.allowsMutation) {
      return;
    }
    controller.commitPendingEdits();
    final target = officeZoteroEditTarget(controller);
    _zoteroOpen = true;
    OfficeZoteroTransport? transport;
    try {
      final credentials = OfficeZoteroCredentials(
        ref.read(secureStorageProvider),
      );
      if (!_zoteroCredentialsLoaded) {
        try {
          final saved = await credentials.load();
          if (!mounted || !identical(controller, _controller)) return;
          _zoteroSession.apiKey = saved;
          _zoteroSession.rememberKey = saved != null;
          _zoteroCredentialsLoaded = true;
        } on OfficeZoteroException catch (error) {
          if (!mounted) return;
          // Keep a key entered during this document session even if the
          // initial credential-store read was unavailable.
          _zoteroCredentialsLoaded = true;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(context.tr(error.message))));
        }
      }
      if (!mounted ||
          !identical(controller, _controller) ||
          officeZoteroEditTarget(controller) != target ||
          !controller.config.allowsMutation) {
        return;
      }
      final supportsDesktopZotero =
          !kIsWeb &&
          (Platform.isLinux || Platform.isWindows || Platform.isMacOS);
      transport = OfficeZoteroTransport(
        createClient: ref.read(proxyServiceProvider).createHttpClient,
        createLocalClient: supportsDesktopZotero
            ? () => IOClient(HttpClient()..findProxy = (_) => 'DIRECT')
            : null,
      );
      _zoteroTransport = transport;
      await showWordZoteroDialog(
        context,
        controller: controller,
        session: _zoteroSession,
        transport: transport.send,
        localTransport: transport.supportsLocal ? transport.send : null,
        persistApiKey: credentials.canPersist ? credentials.save : null,
      );
    } catch (_) {
      if (mounted) {
        _showNotice(
          SnackBar(
            content: Text(
              context.tr('Could not open Zotero. Please try again.'),
            ),
          ),
        );
      }
    } finally {
      transport?.dispose();
      if (identical(_zoteroTransport, transport)) _zoteroTransport = null;
      _zoteroOpen = false;
    }
  }

  Widget _messagePane(String message, ThemeData theme) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.info_outline,
              size: 36,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (_loadedBytes != null) ...[
              OutlinedButton.icon(
                onPressed: _exporting
                    ? null
                    : () => unawaited(_saveCopy(original: true)),
                icon: const Icon(Icons.file_download_outlined),
                label: Text(context.tr('Export original')),
              ),
              const SizedBox(height: 8),
            ],
            OutlinedButton(
              onPressed: _exporting ? null : () => unawaited(_close()),
              child: Text(context.tr('Close')),
            ),
          ],
        ),
      ),
    );
  }
}
