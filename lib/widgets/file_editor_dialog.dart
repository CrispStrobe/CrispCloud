// lib/widgets/file_editor_dialog.dart
//
// Built-in text/code editor for remote (and local) files.
// Downloads the file, presents it in an editable text area with line numbers,
// and re-uploads on save. Warns on unsaved changes.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../utils/formatters.dart';

/// Opens a full-screen editor dialog for the given file.
void showFileEditorDialog(
    BuildContext context, WidgetRef ref, FileItem file, PanelSide side) {
  Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _FileEditorPage(file: file, side: side),
  ));
}

class _FileEditorPage extends ConsumerStatefulWidget {
  final FileItem file;
  final PanelSide side;

  const _FileEditorPage({required this.file, required this.side});

  @override
  ConsumerState<_FileEditorPage> createState() => _FileEditorPageState();
}

class _FileEditorPageState extends ConsumerState<_FileEditorPage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  bool _loading = true;
  bool _saving = false;
  bool _modified = false;
  bool _conflictDetected = false;
  String? _error;
  Uint8List? _originalBytes;
  int _lineCount = 1;
  Timer? _autoSaveTimer;
  DateTime? _loadedAt;

  static const _autoSaveDelay = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    _loadFile();
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final nowModified = _controller.text !=
        (_originalBytes != null
            ? _tryDecode(_originalBytes!)
            : '');
    if (nowModified != _modified) {
      setState(() => _modified = nowModified);
    }
    final newLineCount = '\n'.allMatches(_controller.text).length + 1;
    if (newLineCount != _lineCount) {
      setState(() => _lineCount = newLineCount);
    }

    // Reset auto-save timer on each change
    if (nowModified) {
      _autoSaveTimer?.cancel();
      _autoSaveTimer = Timer(_autoSaveDelay, () {
        if (_modified && !_saving && mounted) {
          _autoSave();
        }
      });
    }
  }

  Future<void> _autoSave() async {
    // Check for conflicts before auto-saving
    if (await _checkForConflict()) {
      setState(() => _conflictDetected = true);
      return;
    }
    await _saveFile();
  }

  /// Check if the remote file was modified since we loaded it.
  Future<bool> _checkForConflict() async {
    if (_loadedAt == null || widget.side == PanelSide.local) return false;
    try {
      final client = ref.read(authProvider).client;
      final remotePath = widget.file.path ?? '/${widget.file.name}';
      final info = await client.resolvePath(remotePath);
      if (info == null) return false;

      final rawDate = info['modificationTime'] ?? info['lastModified'];
      if (rawDate == null) return false;

      DateTime? remoteModified;
      if (rawDate is int) {
        remoteModified = DateTime.fromMillisecondsSinceEpoch(rawDate);
      } else {
        remoteModified = DateTime.tryParse(rawDate.toString());
      }

      if (remoteModified != null && remoteModified.isAfter(_loadedAt!)) {
        return true; // File was modified on server since we loaded it
      }
    } catch (_) {
      // Can't check — proceed without conflict detection
    }
    return false;
  }

  String _tryDecode(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return String.fromCharCodes(bytes);
    }
  }

  Future<void> _loadFile() async {
    try {
      final client = ref.read(authProvider).client;
      Uint8List bytes;

      if (widget.side == PanelSide.local && widget.file.path != null && !kIsWeb) {
        bytes = await File(widget.file.path!).readAsBytes();
      } else {
        final remotePath = widget.file.path ?? '/${widget.file.name}';
        bytes = await client.downloadFileBytes(remotePath);
      }

      if (!mounted) return;

      final text = _tryDecode(bytes);
      _originalBytes = bytes;
      _controller.text = text;
      _lineCount = '\n'.allMatches(text).length + 1;

      setState(() {
        _loading = false;
        _modified = false;
        _loadedAt = DateTime.now();
      });

      _focusNode.requestFocus();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load file: $e';
        _loading = false;
      });
    }
  }

  /// Save a local snapshot before overwriting (version backup).
  Future<void> _saveLocalSnapshot() async {
    if (kIsWeb || _originalBytes == null) return;
    try {
      final snapshotDir = Directory(p.join(
        Directory.systemTemp.path, 'crispcloud_snapshots',
      ));
      if (!await snapshotDir.exists()) await snapshotDir.create(recursive: true);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final name = widget.file.name;
      final snapshotPath = p.join(snapshotDir.path, '${timestamp}_$name');
      await File(snapshotPath).writeAsBytes(_originalBytes!);
    } catch (_) {
      // Snapshot is best-effort, don't fail the save
    }
  }

  Future<void> _saveFile() async {
    setState(() => _saving = true);
    try {
      // Save a local snapshot before overwriting
      await _saveLocalSnapshot();

      final client = ref.read(authProvider).client;
      final bytes = Uint8List.fromList(utf8.encode(_controller.text));

      if (widget.side == PanelSide.local && widget.file.path != null && !kIsWeb) {
        await File(widget.file.path!).writeAsBytes(bytes);
      } else {
        final remotePath = widget.file.path ?? '/${widget.file.name}';
        final fileName = p.basename(remotePath);
        final targetDir = p.posix.dirname(remotePath);
        await client.uploadFile(bytes, fileName, targetDir);
      }

      _originalBytes = bytes;

      if (!mounted) return;
      setState(() {
        _saving = false;
        _modified = false;
      });

      // Refresh the panel to show updated file
      ref.read(panelProvider(widget.side)).refreshFiles();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved ${widget.file.name}')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save failed: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_modified) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved Changes'),
        content: const Text(
            'You have unsaved changes. Discard them?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Discard')),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ext = widget.file.name.contains('.')
        ? widget.file.name.split('.').last.toUpperCase()
        : 'TXT';

    // ignore: deprecated_member_use
    return WillPopScope(
      onWillPop: () async {
        if (!_modified) return true;
        return await _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () async {
              if (await _confirmDiscard()) {
                if (mounted) Navigator.of(context).pop();
              }
            },
          ),
          title: Row(
            children: [
              Text(widget.file.name,
                  style: const TextStyle(fontSize: 14)),
              if (_modified) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('Modified',
                      style: TextStyle(
                          fontSize: 10,
                          color: theme.colorScheme.onPrimary)),
                ),
              ],
            ],
          ),
          actions: [
            // File info
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Text(
                  '$ext  |  $_lineCount lines',
                  style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ),
            // Save button
            _saving
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child:
                            CircularProgressIndicator(strokeWidth: 2)),
                  )
                : IconButton(
                    icon: Icon(Icons.save,
                        color: _modified
                            ? theme.colorScheme.primary
                            : null),
                    tooltip: 'Save (Ctrl+S)',
                    onPressed: _modified ? _saveFile : null,
                  ),
          ],
        ),
        body: Column(children: [
          if (_conflictDetected)
            MaterialBanner(
              content: const Text(
                'This file was modified on the server since you opened it. '
                'Saving will overwrite the remote version.',
              ),
              leading: const Icon(Icons.warning, color: Colors.orange),
              actions: [
                TextButton(
                  onPressed: () {
                    setState(() => _conflictDetected = false);
                    _saveFile();
                  },
                  child: const Text('Save Anyway'),
                ),
                TextButton(
                  onPressed: () {
                    setState(() => _conflictDetected = false);
                    _loadFile();
                  },
                  child: const Text('Reload'),
                ),
                TextButton(
                  onPressed: () => setState(() => _conflictDetected = false),
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          Expanded(child: KeyboardListener(
          focusNode: FocusNode(),
          onKeyEvent: (event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.keyS &&
                (HardwareKeyboard.instance.isControlPressed ||
                    HardwareKeyboard.instance.isMetaPressed)) {
              if (_modified) _saveFile();
            }
          },
          child: _buildBody(theme),
        )),
      ]),
    ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
        ),
      );
    }

    return Row(
      children: [
        // Line numbers gutter
        Container(
          width: 48,
          color: theme.colorScheme.surfaceContainerHighest,
          child: ListView.builder(
            controller: _scrollController,
            itemCount: _lineCount,
            itemExtent: 20,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                '${i + 1}',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.4,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
        Container(width: 1, color: theme.dividerColor),
        // Editor area
        Expanded(
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            maxLines: null,
            expands: true,
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(8),
            ),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
