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
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/file_bytes_loader.dart';
import '../services/log_service.dart';
import '../l10n/file_bytes_error_strings.dart';
import '../l10n/provider_operation_strings.dart';
import '../l10n/office_editor_strings.dart';
import '../l10n/office_fallback_strings.dart';
import '../l10n/office_surface_strings.dart';
import '../services/office_editor_menu.dart';
import 'office_editor_find_bar.dart';
import 'office_editor_ribbon.dart';

const _log = Log('OfficeEditor');

const int _kOfficeEditorCap = 64 * 1024 * 1024;

/// Extensions that belong to the Office dialog (editable or message-only).
const Set<String> kOfficeExtensions = <String>{
  'docx',
  'docm',
  'dotx',
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
  return ext == 'docx' || ext == 'xlsx' || ext == 'pptx';
}

Future<void> showOfficeEditorDialog(
  BuildContext context,
  WidgetRef ref,
  FileItem file,
  PanelSide side, {
  Uint8List? bytesOverride,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => Dialog.fullscreen(
      child: OfficeEditorDialog(
        file: file,
        side: side,
        bytesOverride: bytesOverride,
      ),
    ),
  );
}

class OfficeEditorDialog extends ConsumerStatefulWidget {
  final FileItem file;
  final PanelSide side;

  /// Test/embedded hook: use these bytes instead of reading [file].
  final Uint8List? bytesOverride;

  const OfficeEditorDialog({
    super.key,
    required this.file,
    required this.side,
    this.bytesOverride,
  });

  @override
  ConsumerState<OfficeEditorDialog> createState() => _OfficeEditorDialogState();
}

class _OfficeEditorDialogState extends ConsumerState<OfficeEditorDialog> {
  OfficeController? _controller;
  OfficeEditorKind _kind = OfficeEditorKind.unsupported;
  Uint8List? _loadedBytes;
  bool _loading = true;
  bool _saving = false;
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
    _controller?.commands.removeListener(_onControllerChanged);
    _controller?.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  OfficeEditorKind _kindFor(String name) {
    final ext = name.split('.').last.toLowerCase();
    if (!_isEditableOoxml(name)) return OfficeEditorKind.unsupported;
    switch (ext) {
      case 'docx':
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
      await OfficeHostFonts.ensureRegistered();
      final bytes = widget.bytesOverride ??
          await loadFileBytes(
            ref,
            widget.file,
            widget.side,
            capBytes: _kOfficeEditorCap,
          );
      if (!mounted) return;

      final kind = _kindFor(widget.file.name);
      if (kind == OfficeEditorKind.unsupported) {
        setState(() {
          _loading = false;
          _loadedBytes = bytes;
          _kind = kind;
        });
        return;
      }

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
      controller?.commands.addListener(_onControllerChanged);
      setState(() {
        _loadedBytes = bytes;
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
        _error = '${context.tr('Could not open this document')}: '
            '${localizedFileBytesError(context, e)}';
      });
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final dirty = _controller?.isDirty ?? false;
    if (dirty == _dirty) return;
    setState(() => _dirty = dirty);
  }

  Future<void> _save({bool popAfter = false}) async {
    final controller = _controller;
    if (controller == null || _saving) return;
    setState(() => _saving = true);
    try {
      await _saveSnapshot();
      final bytes = await controller.saveBytesAsync();
      final path = widget.file.path;
      if (widget.side == PanelSide.local && path != null) {
        await ref.read(localFileServiceProvider).saveFile(path, bytes);
      } else {
        final remotePath = path ?? '/${widget.file.name}';
        final client = ref.read(authProvider).client;
        await client.uploadFile(
          bytes,
          p.posix.basename(remotePath),
          p.posix.dirname(remotePath),
        );
      }
      controller.markClean();
      if (!mounted) return;
      setState(() {
        _saving = false;
        _dirty = false;
      });
      ref.read(panelProvider(widget.side)).refreshFiles();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${context.tr('Saved')}: ${widget.file.name}')),
      );
      if (popAfter && mounted) Navigator.of(context).pop();
    } catch (e, st) {
      _log.warn('office editor save failed', e, st);
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${context.tr('Save failed')}: '
              '${localizedProviderError(context, e)}'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _close() async {
    if (_saving) return;
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('Unsaved changes')),
        content: Text(OfficeFallbackStrings.closeConfirmation(
          Localizations.maybeLocaleOf(dialogContext)?.languageCode ?? 'en',
          widget.file.name,
        )),
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
  }

  Future<void> _saveSnapshot() async {
    final bytes = _loadedBytes;
    if (bytes == null || kIsWeb) return;
    try {
      final support = await getApplicationSupportDirectory();
      final dir = Directory('${support.path}/editor_snapshots');
      if (!await dir.exists()) await dir.create(recursive: true);
      final safeName =
          widget.file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final name = '${DateTime.now().millisecondsSinceEpoch}_$safeName';
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
    return CallbackShortcuts(
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
              (WmlRunProps p) => p.underline = p.underline == WmlUnderline.none
                  ? WmlUnderline.single
                  : WmlUnderline.none,
            ),
        const SingleActivator(LogicalKeyboardKey.keyU, meta: true): () =>
            _wordShortcut(
              (WmlRunProps p) => p.underline = p.underline == WmlUnderline.none
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
        body: SafeArea(
          top: true,
          bottom: false,
          child: _buildBody(theme),
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
            'This Office format cannot be edited safely. Use F3 to view it, or save it as .docx / .xlsx / .pptx and edit that.'),
        theme,
      );
    }
    final controller = _controller;
    if (controller == null) {
      return _messagePane(
          context.tr('The document could not be loaded.'), theme);
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
          onClose: () => unawaited(_close()),
          onConfigChanged: _onConfigChanged,
          onFind: _requestFind,
          title: widget.file.name,
          dirty: _dirty,
          saving: _saving,
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
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.tr('Close')),
            ),
          ],
        ),
      ),
    );
  }
}
