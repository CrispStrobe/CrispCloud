import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:madedit2_hex/madedit2_hex.dart';

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/file_operation_backend.dart';
import '../services/file_operation_service.dart';
import '../services/hex_file_session.dart';

/// Capture the file's verified storage before navigation. Neither a later tab
/// switch nor a matching path on another account can redirect a save.
Future<void> showHexEditorDialog(
  BuildContext context,
  WidgetRef ref,
  FileItem file,
  PanelSide side,
) async {
  if (file.isFolder) return;
  try {
    final panel = ref.read(panelProvider(side));
    final origin = panel.originForOperation(file);
    if (origin == null || !origin.isCurrent) {
      throw const HexSaveConflict(
        'Refresh or reopen the original file before hex editing. Archive previews are read-only.',
      );
    }
    final backend = fileOperationBackend(
      source: origin.source,
      local: ref.read(localFileServiceProvider),
      isCurrent: () => origin.isCurrent,
    );
    final original = file.copyWith(
      path:
          file.path ?? backend.paths.join(origin.source.currentPath, file.name),
    );
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => HexFileEditorPage(file: original, backend: backend),
      ),
    );
    // Refresh only after the editor has closed; an active session must retain
    // the origin it captured. Invalidate stale file previews independently.
    try {
      await ref
          .read(fileCacheProvider)
          .remove(original.path!, origin.storageId);
    } catch (_) {}
    try {
      await panel.refresh();
    } catch (_) {}
    panel.restoreCursorAndFocus(file);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Cannot open hex editor: $error')));
    }
  }
}

/// Public injection boundary for real-backend integration tests.
class HexFileEditorPage extends StatefulWidget {
  const HexFileEditorPage({
    super.key,
    required this.file,
    required this.backend,
  });
  final FileItem file;
  final FileOperationBackend backend;
  @override
  State<HexFileEditorPage> createState() => _HexFileEditorPageState();
}

class _HexFileEditorPageState extends State<HexFileEditorPage> {
  HexFileSession? _session;
  HexEditorController? _controller;
  bool _loading = true, _saving = false, _cancelled = false, _disposed = false;
  bool _canPop = false, _closing = false, _saveAgain = false;
  String? _error;
  int _progress = 0;
  int? _total;
  Future<bool>? _activeSave;
  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  void _progressChanged(int done, int? total) {
    if (mounted)
      setState(() {
        _progress = done;
        _total = total;
      });
  }

  Future<void> _open() async {
    try {
      final session = await HexFileSession.open(
        backend: widget.backend,
        file: widget.file,
        cancelled: () => _cancelled || _disposed,
        onProgress: _progressChanged,
      );
      if (!mounted || _disposed) {
        await session.close();
        return;
      }
      _session = session;
      _controller = HexEditorController(
        HexDocument(session.source),
        readOnly: !session.canSave,
      )..addListener(_changed);
      setState(() {
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = error.toString();
        });
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<bool> _save() {
    if (_activeSave != null) {
      _saveAgain = true;
      return _activeSave!;
    }
    final future = _saveLoop();
    _activeSave = future;
    return future.whenComplete(() => _activeSave = null);
  }

  Future<bool> _saveLoop() async {
    final controller = _controller, session = _session;
    if (controller == null || session == null) return false;
    if (!session.canSave) {
      setState(
        () => _error = 'This storage cannot perform a verified staged write. The original has not been changed.',
      );
      return false;
    }
    setState(() {
      _saving = true;
      _cancelled = false;
      _error = null;
      _progress = 0;
    });
    try {
      do {
        _saveAgain = false;
        await controller.idle;
        final snapshot = controller.document.snapshot;
        if (!controller.isDirty) break;
        await session.save(
          snapshot,
          cancelled: () => _cancelled,
          onProgress: (done, total) => _progressChanged(done, total),
        );
        // Only the revision actually written becomes clean. Newer edits stay dirty.
        controller.markSaved(snapshot);
      } while (_saveAgain && !_cancelled && !_disposed);
      return !controller.isDirty;
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveCopy() async {
    if (_saving || _controller == null || _session == null) return;
    final input = TextEditingController(text: '${widget.file.name}.edited');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save a separate copy'),
        content: TextField(
          controller: input,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'New file name (same folder)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, input.text),
            child: const Text('Save copy'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => input.dispose());
    if (name == null || !mounted) return;
    setState(() {
      _saving = true;
      _cancelled = false;
      _error = null;
    });
    try {
      await _controller!.idle;
      await _session!.saveCopy(
        _controller!.document.snapshot,
        name,
        cancelled: () => _cancelled,
      );
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Copy saved. Edits to the original are still unsaved.',
            ),
          ),
        );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _close() async {
    if (_closing || _saving) return;
    _closing = true;
    try {
      if (_loading) _cancelled = true;
      await _controller?.idle;
      if (!mounted) return;
      if (_controller?.isDirty ?? false) {
        final action = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Unsaved binary changes'),
            content: const Text(
              'Save your changes, discard them, or keep editing?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'cancel'),
                child: const Text('Keep editing'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'discard'),
                child: const Text('Discard'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, 'save'),
                child: const Text('Save'),
              ),
            ],
          ),
        );
        if (action == null || action == 'cancel') return;
        if (action == 'save' && !await _save()) return;
      }
      if (!mounted) return;
      setState(() => _canPop = true);
      // Let PopScope observe the new permission before popping.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    } finally {
      _closing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_close());
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            tooltip: 'Close hex editor',
            icon: const Icon(Icons.close),
            onPressed: _saving ? null : () => unawaited(_close()),
          ),
          title: Text(
            '${widget.file.name} — Hex${controller?.isDirty == true ? ' *' : ''}',
          ),
          actions: [
            IconButton(
              tooltip: 'Save a separate copy',
              icon: const Icon(Icons.save_as_outlined),
              onPressed: controller == null || _saving
                  ? null
                  : () => unawaited(_saveCopy()),
            ),
            IconButton(
              tooltip: 'Save original (Ctrl/Cmd+S)',
              icon: const Icon(Icons.save_outlined),
              onPressed: controller == null || _saving || !controller.isDirty
                  ? null
                  : () => unawaited(_save()),
            ),
          ],
        ),
        body: Column(
          children: [
            if (_error != null)
              Material(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(_error!),
                ),
              ),
            if (_loading || _saving)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    LinearProgressIndicator(
                      value: _total != null && _total! > 0
                          ? (_progress / _total!).clamp(0.0, 1.0)
                          : null,
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _loading
                                ? 'Preparing an immutable editing copy… $_progress bytes'
                                : 'Verifying and saving… $_progress bytes',
                          ),
                        ),
                        TextButton(
                          onPressed: () => setState(() => _cancelled = true),
                          child: const Text('Cancel before commit'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            if (controller != null)
              Expanded(
                child: HexEditor(
                  controller: controller,
                  saving: _saving,
                  onSave: () {
                    if (!_saving)
                      unawaited(_save());
                    else
                      _saveAgain = true;
                  },
                ),
              )
            else if (!_loading)
              const Expanded(
                child: Center(
                  child: Text('The original file has not been modified.'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelled = true;
    final controller = _controller, session = _session;
    controller?.removeListener(_changed);
    controller?.cancelSearch();
    // Keep the immutable source alive until queued editing and any write end.
    unawaited(() async {
      await controller?.idle;
      controller?.dispose();
      await session?.close();
    }());
    super.dispose();
  }
}
