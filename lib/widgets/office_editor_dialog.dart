// lib/widgets/office_editor_dialog.dart
//
// F4 editor for Office Open XML documents (DOCX / XLSX / PPTX) built on the
// MIT-licensed `quds_office_editor` surfaces. The package paints the document;
// this dialog provides the host chrome: loading, save, undo/redo, dirty state
// and the unsaved-changes prompt.
//
// Legacy (.doc/.xls/.ppt) and ODF (.odt/.ods/.odp) files cannot be written
// back safely with the OOXML serializer, so they get a clear message instead
// of opening a text editor that would corrupt them.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:quds_office_editor/quds_office_editor.dart'
    hide WordPackagePreservation;
import 'package:quds_office_engine/quds_office_engine.dart'
    show WordPackagePreservation;

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/captured_file_target.dart';
import '../services/office_device_export.dart';
import '../services/log_service.dart';
import '../l10n/file_bytes_error_strings.dart';
import '../l10n/office_editor_strings.dart';
import '../l10n/office_recovery_strings.dart';
import '../l10n/office_surface_strings.dart';
import '../l10n/word_format_strings.dart';
import '../services/office_editor_menu.dart';
import '../services/document_fonts.dart';
import 'office_editor_find_bar.dart';
import 'office_editor_ribbon.dart';

const _log = Log('OfficeEditor');

const int _kOfficeEditorCap = 64 * 1024 * 1024;

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

  const OfficeEditorDialog({
    super.key,
    required this.file,
    required this.side,
    this.bytesOverride,
    this.targetOverride,
    this.copyExporter = exportOfficeCopy,
  });

  @override
  ConsumerState<OfficeEditorDialog> createState() => _OfficeEditorDialogState();
}

class _OfficeEditorDialogState extends ConsumerState<OfficeEditorDialog> {
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
  String? _error;
  final FocusNode _focusNode = FocusNode(debugLabel: 'QudsOfficeEditor');
  final GlobalKey<OfficeEditorRibbonState> _ribbonKey =
      GlobalKey<OfficeEditorRibbonState>();
  OfficeEditorMenuActions? _menuActions;
  ProviderContainer? _providerContainer;

  OfficeSurfaceConfig _config = const OfficeSurfaceConfig(
    mode: OfficeInteractionMode.editing,
    autofocus: true,
    adaptiveChrome: true,
  );

  @override
  void initState() {
    super.initState();
    _target = widget.targetOverride;
    unawaited(_load());
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
    if (!_isEditableOoxml(name)) return OfficeEditorKind.unsupported;
    switch (ext) {
      case 'docx':
      case 'docm':
      case 'dotx':
      case 'dotm':
        return OfficeEditorKind.word;
      case 'xlsx':
        return OfficeEditorKind.sheet;
      case 'pptx':
        return OfficeEditorKind.slides;
      default:
        return OfficeEditorKind.unsupported;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await DocumentFonts.ensureRegistered();
      final Uint8List bytes;
      if (widget.bytesOverride case final supplied?) {
        bytes = supplied;
      } else {
        final target = _target ??= ref
            .read(panelProvider(widget.side))
            .captureFileTarget(widget.file, maxBytes: _kOfficeEditorCap);
        bytes = await target.load();
      }
      if (!mounted) return;

      // Retain an immutable original even if safe-edit admission rejects it.
      // Recovery must never run a refused package through a serializer.
      _loadedBytes = Uint8List.fromList(bytes).asUnmodifiableView();

      final kind = _kindFor(widget.file.name);
      if (kind == OfficeEditorKind.unsupported) {
        setState(() {
          _loading = false;
          _kind = kind;
        });
        return;
      }

      _wordPreservation = await WordPackagePreservation.capture(
        bytes,
        widget.file.name,
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

  Future<void> _save({bool popAfter = false}) async {
    final controller = _controller;
    if (controller == null || _saving || _exporting) return;
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
      _loadedBytes = Uint8List.fromList(bytes).asUnmodifiableView();
      if (!mounted) return;
      if (controller.contentRevision == savedRevision) controller.markClean();
      setState(() {
        _saving = false;
        _dirty = controller.isDirty;
      });
      ref.read(panelProvider(widget.side)).refreshFiles();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${context.tr('Saved')}: ${widget.file.name}')),
      );
      if (popAfter && mounted && !_dirty) Navigator.of(context).pop();
    } catch (e, st) {
      _log.warn('office editor save failed', e, st);
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
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
            '${context.tr('Save changes to')} ${widget.file.name} ${context.tr('before closing?')}',
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

  Future<void> _saveCopy({bool original = false}) async {
    if (_saving || _exporting) return;
    final controller = _controller;
    if ((!original && controller == null) ||
        (original && _loadedBytes == null)) {
      return;
    }
    setState(() => _exporting = true);
    try {
      final Uint8List bytes;
      if (original) {
        bytes = _loadedBytes!;
      } else {
        controller!.commitPendingEdits();
        bytes = await controller.saveBytesAsync();
        await _wordPreservation?.validateSaved(bytes);
      }
      if (bytes.length > kOfficeCopyOutputLimitBytes) {
        throw FileTargetTooLarge(kOfficeCopyOutputLimitBytes);
      }
      if (!mounted) return;
      final outcome = await widget.copyExporter(
        Uint8List.fromList(bytes).asUnmodifiableView(),
        officeCopyName(widget.file.name),
        context.tr(original ? 'Export original' : 'Save a copy'),
      );
      if (!mounted || outcome == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
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
      ScaffoldMessenger.of(context).showSnackBar(
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

  Future<void> _saveSnapshot(Uint8List bytes, {required String kind}) async {
    if (kIsWeb) return;
    try {
      final support = await getApplicationSupportDirectory();
      final dir = Directory('${support.path}/editor_snapshots');
      if (!await dir.exists()) await dir.create(recursive: true);
      final safeName = widget.file.name.replaceAll(
        RegExp(r'[^A-Za-z0-9._-]'),
        '_',
      );
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

  void _onConfigChanged(OfficeSurfaceConfig next) {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope<void>(
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
          const SingleActivator(LogicalKeyboardKey.escape): _handleEscape,
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
          onClose: () => unawaited(_close()),
          onConfigChanged: _onConfigChanged,
          onFind: _requestFind,
          title: widget.file.name,
          dirty: _dirty,
          saving: _saving || _exporting,
        ),
        Expanded(child: editor),
      ],
    );
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
