// lib/widgets/file_editor_dialog.dart
//
// Built-in text/code editor for remote (and local) files.
// Downloads the file, presents it in an editable text area with line numbers,
// and re-uploads on save. Warns on unsaved changes.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../l10n/app_localizations.dart';

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

/// Detect a language from file extension for syntax highlighting.
String? _detectLanguage(String filename) {
  final ext = filename.contains('.') ? filename.split('.').last.toLowerCase() : '';
  const map = {
    'dart': 'dart', 'js': 'javascript', 'ts': 'typescript',
    'jsx': 'javascript', 'tsx': 'typescript',
    'py': 'python', 'rs': 'rust', 'go': 'go', 'java': 'java',
    'json': 'json', 'yaml': 'yaml', 'yml': 'yaml', 'xml': 'xml',
    'html': 'html', 'css': 'css', 'sh': 'bash', 'bash': 'bash',
    'md': 'markdown', 'sql': 'sql', 'cpp': 'cpp', 'c': 'c',
    'h': 'cpp', 'hpp': 'cpp', 'kt': 'kotlin', 'swift': 'swift',
    'php': 'php', 'rb': 'ruby', 'lua': 'lua', 'r': 'r',
    'toml': 'toml', 'ini': 'ini',
  };
  return map[ext];
}

/// Keywords for common languages, used for basic syntax highlighting.
const _languageKeywords = <String, List<String>>{
  'dart': ['import', 'export', 'class', 'extends', 'implements', 'mixin', 'enum', 'abstract', 'final', 'const', 'var', 'late', 'static', 'void', 'return', 'if', 'else', 'for', 'while', 'do', 'switch', 'case', 'break', 'continue', 'try', 'catch', 'throw', 'async', 'await', 'Future', 'Stream', 'dynamic', 'int', 'double', 'String', 'bool', 'List', 'Map', 'Set', 'null', 'true', 'false', 'this', 'super', 'new', 'with', 'as', 'is', 'in', 'get', 'set', 'required', 'override'],
  'javascript': ['import', 'export', 'from', 'class', 'extends', 'function', 'const', 'let', 'var', 'return', 'if', 'else', 'for', 'while', 'do', 'switch', 'case', 'break', 'continue', 'try', 'catch', 'throw', 'async', 'await', 'new', 'this', 'super', 'null', 'undefined', 'true', 'false', 'typeof', 'instanceof', 'in', 'of', 'default', 'yield'],
  'typescript': ['import', 'export', 'from', 'class', 'extends', 'implements', 'interface', 'type', 'enum', 'function', 'const', 'let', 'var', 'return', 'if', 'else', 'for', 'while', 'do', 'switch', 'case', 'break', 'continue', 'try', 'catch', 'throw', 'async', 'await', 'new', 'this', 'super', 'null', 'undefined', 'true', 'false', 'typeof', 'instanceof', 'as', 'readonly', 'abstract', 'private', 'protected', 'public'],
  'python': ['import', 'from', 'class', 'def', 'return', 'if', 'elif', 'else', 'for', 'while', 'break', 'continue', 'try', 'except', 'finally', 'raise', 'with', 'as', 'in', 'not', 'and', 'or', 'is', 'None', 'True', 'False', 'lambda', 'yield', 'async', 'await', 'pass', 'self', 'global', 'nonlocal'],
  'go': ['package', 'import', 'func', 'var', 'const', 'type', 'struct', 'interface', 'return', 'if', 'else', 'for', 'range', 'switch', 'case', 'break', 'continue', 'defer', 'go', 'select', 'chan', 'map', 'nil', 'true', 'false', 'make', 'new', 'len', 'append', 'error', 'string', 'int', 'bool', 'byte'],
  'rust': ['use', 'mod', 'pub', 'fn', 'struct', 'enum', 'impl', 'trait', 'let', 'mut', 'const', 'static', 'return', 'if', 'else', 'for', 'while', 'loop', 'match', 'break', 'continue', 'async', 'await', 'move', 'self', 'Self', 'super', 'true', 'false', 'Some', 'None', 'Ok', 'Err', 'unsafe', 'where', 'type', 'as', 'in', 'ref'],
  'java': ['import', 'package', 'class', 'extends', 'implements', 'interface', 'enum', 'abstract', 'final', 'static', 'void', 'return', 'if', 'else', 'for', 'while', 'do', 'switch', 'case', 'break', 'continue', 'try', 'catch', 'throw', 'throws', 'new', 'this', 'super', 'null', 'true', 'false', 'public', 'private', 'protected', 'int', 'long', 'double', 'float', 'boolean', 'String', 'synchronized'],
};

/// A TextEditingController that applies basic syntax highlighting.
class _HighlightingController extends TextEditingController {
  final String? language;
  late final Set<String> _keywords;
  bool highlightEnabled;

  _HighlightingController({this.language, this.highlightEnabled = true}) {
    _keywords = (_languageKeywords[language] ?? []).toSet();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (!highlightEnabled || language == null || _keywords.isEmpty) {
      return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    }

    // Performance guard: skip highlighting for large files
    if (text.length > 500000) {
      return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final keywordColor = isDark ? const Color(0xFF569CD6) : const Color(0xFF0000FF);
    final stringColor = isDark ? const Color(0xFFCE9178) : const Color(0xFFA31515);
    final commentColor = isDark ? const Color(0xFF6A9955) : const Color(0xFF008000);
    final numberColor = isDark ? const Color(0xFFB5CEA8) : const Color(0xFF098658);

    final spans = <TextSpan>[];
    final lines = text.split('\n');

    for (var lineIdx = 0; lineIdx < lines.length; lineIdx++) {
      if (lineIdx > 0) spans.add(TextSpan(text: '\n', style: style));

      final line = lines[lineIdx];
      var i = 0;

      while (i < line.length) {
        // Comment (// or #)
        if ((i < line.length - 1 && line[i] == '/' && line[i + 1] == '/') ||
            (line[i] == '#' && (language == 'python' || language == 'bash' || language == 'ruby'))) {
          spans.add(TextSpan(text: line.substring(i), style: style?.copyWith(color: commentColor)));
          i = line.length;
          continue;
        }

        // String literal
        if (line[i] == '"' || line[i] == "'") {
          final quote = line[i];
          var end = i + 1;
          while (end < line.length && line[end] != quote) {
            if (line[end] == '\\') end++; // Skip escaped char
            end++;
          }
          if (end < line.length) end++; // Include closing quote
          spans.add(TextSpan(text: line.substring(i, end), style: style?.copyWith(color: stringColor)));
          i = end;
          continue;
        }

        // Number literal
        if (RegExp(r'[0-9]').hasMatch(line[i]) &&
            (i == 0 || !RegExp(r'[a-zA-Z_]').hasMatch(line[i - 1]))) {
          var end = i;
          while (end < line.length && RegExp(r'[0-9.xXa-fA-F]').hasMatch(line[end])) {
            end++;
          }
          spans.add(TextSpan(text: line.substring(i, end), style: style?.copyWith(color: numberColor)));
          i = end;
          continue;
        }

        // Word (potential keyword)
        if (RegExp(r'[a-zA-Z_]').hasMatch(line[i])) {
          var end = i;
          while (end < line.length && RegExp(r'[a-zA-Z0-9_]').hasMatch(line[end])) {
            end++;
          }
          final word = line.substring(i, end);
          if (_keywords.contains(word)) {
            spans.add(TextSpan(text: word, style: style?.copyWith(color: keywordColor, fontWeight: FontWeight.bold)));
          } else {
            spans.add(TextSpan(text: word, style: style));
          }
          i = end;
          continue;
        }

        // Other character
        spans.add(TextSpan(text: line[i], style: style));
        i++;
      }
    }

    return TextSpan(children: spans, style: style);
  }
}

class _FileEditorPageState extends ConsumerState<_FileEditorPage> {
  late final _HighlightingController _controller;
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  bool _loading = true;
  bool _saving = false;
  bool _modified = false;
  bool _conflictDetected = false;
  bool _highlightEnabled = true;
  String? _error;
  String? _language;
  Uint8List? _originalBytes;
  int _lineCount = 1;
  Timer? _autoSaveTimer;
  DateTime? _loadedAt;

  static const _autoSaveDelay = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    _language = _detectLanguage(widget.file.name);
    _controller = _HighlightingController(
      language: _language,
      highlightEnabled: _highlightEnabled,
    );
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
    debugPrint('[Editor] loadFile: ${widget.file.name} side=${widget.side.name} web=$kIsWeb');
    try {
      final client = ref.read(authProvider).client;
      Uint8List bytes;

      if (widget.side == PanelSide.local && widget.file.path != null) {
        if (kIsWeb) {
          bytes = await ref.read(localFileServiceProvider).readFile(
            widget.file.path!, fileItem: widget.file,
          );
        } else {
          bytes = await File(widget.file.path!).readAsBytes();
        }
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
    debugPrint('[Editor] saveFile: ${widget.file.name} side=${widget.side.name} web=$kIsWeb');
    setState(() => _saving = true);
    try {
      // Save a local snapshot before overwriting
      await _saveLocalSnapshot();

      final client = ref.read(authProvider).client;
      final bytes = Uint8List.fromList(utf8.encode(_controller.text));

      if (widget.side == PanelSide.local && widget.file.path != null) {
        if (kIsWeb) {
          await ref.read(localFileServiceProvider).saveFile(widget.file.path!, bytes);
        } else {
          await File(widget.file.path!).writeAsBytes(bytes);
        }
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
        title: Text(AppLocalizations.of(context)!.unsavedChanges),
        content: const Text(
            'You have unsaved changes. Discard them?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(AppLocalizations.of(context)!.cancel)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(AppLocalizations.of(context)!.discard)),
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

    return PopScope(
      canPop: !_modified,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard()) {
          if (!context.mounted) return;
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: AppLocalizations.of(context)!.close,
            onPressed: () async {
              if (await _confirmDiscard()) {
                if (!context.mounted) return;
                Navigator.of(context).pop();
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
            // Syntax highlighting toggle
            if (_language != null)
              IconButton(
                icon: Icon(
                  _highlightEnabled ? Icons.code : Icons.code_off,
                  size: 20,
                ),
                tooltip: _highlightEnabled ? 'Disable Highlighting' : 'Enable Highlighting',
                onPressed: () {
                  setState(() {
                    _highlightEnabled = !_highlightEnabled;
                    _controller.highlightEnabled = _highlightEnabled;
                  });
                },
              ),
            // File info
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Text(
                  '${_language?.toUpperCase() ?? ext}  |  $_lineCount lines',
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
                  child: Text(AppLocalizations.of(context)!.reload),
                ),
                TextButton(
                  onPressed: () => setState(() => _conflictDetected = false),
                  child: Text(AppLocalizations.of(context)!.cancel),
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
