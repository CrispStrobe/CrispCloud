import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:madedit2_hex/madedit2_hex.dart';

import '../l10n/hex_editor_strings.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/captured_file_target.dart';
import '../services/file_operation_backend.dart';
import '../services/hex_edit_session.dart';

/// Captures the exact listed source before opening a full-screen byte editor.
Future<void> showHexEditorDialog(
  BuildContext context,
  WidgetRef ref,
  FileItem file,
  PanelSide side, {
  PanelFileOrigin? origin,
}) async {
  if (file.isFolder) return;
  final captured =
      origin ?? ref.read(panelProvider(side)).originForOperation(file);
  if (captured == null || !captured.isCurrent) {
    throw const FileTargetConflict(
      'The original storage is unavailable. Refresh or reopen the file.',
    );
  }
  try {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            HexEditorDialog(file: file, side: side, origin: captured),
      ),
    );
  } finally {
    try {
      ref.read(panelProvider(side)).restoreCursorAndFocus(file);
    } catch (_) {
      // The panel may have closed while the editor was open.
    }
  }
}

/// Native Flutter hex editing with explicit saves and captured-source identity.
/// The optional session is an embedding/test seam and is owned by this dialog.
class HexEditorDialog extends ConsumerStatefulWidget {
  const HexEditorDialog({
    super.key,
    required this.file,
    required this.side,
    this.origin,
    this.sessionOverride,
  });

  final FileItem file;
  final PanelSide side;
  final PanelFileOrigin? origin;
  final HexEditSession? sessionOverride;

  @override
  ConsumerState<HexEditorDialog> createState() => _HexEditorDialogState();
}

class _HexEditorDialogState extends ConsumerState<HexEditorDialog> {
  HexEditSession? _session;
  HexEditorController? _controller;
  PanelFileOrigin? _origin;
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  bool _loading = true;
  bool _allowPop = false;
  bool _closing = false;
  bool _showSearch = false;
  bool _textSearch = false;
  int _bytesPerRow = 16;
  double _fontSize = 13;
  int _received = 0;
  int? _total;
  DateTime _lastProgress = DateTime.fromMillisecondsSinceEpoch(0);
  String? _error;
  String? _searchError;
  String? _notice;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      var session = widget.sessionOverride;
      if (session == null) {
        _origin =
            widget.origin ??
            ref
                .read(panelProvider(widget.side))
                .originForOperation(widget.file);
        final origin = _origin;
        if (origin == null || !origin.isCurrent) {
          throw const FileTargetConflict(
            'The original storage is unavailable. Refresh or reopen the file.',
          );
        }
        final backend = fileOperationBackend(
          source: origin.source,
          local: ref.read(localFileServiceProvider),
          // A route closing does not invalidate a write already in progress.
          // Source disconnection still invalidates every guarded operation.
          isCurrent: () => origin.isCurrent,
        );
        session = await HexEditSession.open(
          backend: backend,
          file: widget.file,
          isCancelled: () => !mounted || _allowPop,
          onProgress: (received, total) {
            if (!mounted) return;
            final now = DateTime.now();
            if (received != total &&
                now.difference(_lastProgress).inMilliseconds < 100)
              return;
            _lastProgress = now;
            setState(() {
              _received = received;
              _total = total;
            });
          },
        );
      }
      if (!mounted || _allowPop) {
        await session.close();
        return;
      }
      _session = session;
      _controller = HexEditorController(session.document);
      _controller!.addListener(_documentChanged);
      session.addListener(_sessionChanged);
      setState(() => _loading = false);
    } catch (error) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = '$error';
        });
    }
  }

  void _documentChanged() {
    _session?.documentChanged();
    if (mounted) setState(() {});
  }

  void _sessionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.removeListener(_documentChanged);
    _controller?.dispose();
    _session?.removeListener(_sessionChanged);
    final session = _session;
    if (session != null) unawaited(session.close());
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<bool> _save() async {
    final session = _session;
    final controller = _controller;
    if (session == null || controller == null || session.isSaving) return false;
    try {
      await controller.settled;
      if (!mounted) return false;
      setState(() {
        _error = null;
        _notice = null;
      });
      final result = await session.save();
      if (!mounted) return false;
      controller.refresh();
      if (!result.isSuccess) {
        setState(
          () => _error = '${context.hexTr('Save failed')}: ${result.error}',
        );
        return false;
      }
      final savedFile = session.savedFile;
      final origin = _origin;
      if (savedFile != null && origin != null) {
        for (final side in PanelSide.values) {
          try {
            ref.read(panelProvider(side)).applyFileListChanges({
              session.path: savedFile,
            }, origin: origin);
          } catch (_) {
            // A closed panel must not turn a committed save into a failure.
          }
        }
      }
      setState(
        () => _notice = context.hexTr(
          session.isDirty ? 'Saved; newer edits remain unsaved.' : 'Saved',
        ),
      );
      return !session.isDirty;
    } catch (error) {
      if (mounted)
        setState(() => _error = '${context.hexTr('Save failed')}: $error');
      return false;
    }
  }

  Future<void> _run(Future<void> Function() command) async {
    try {
      await command();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  void _toggleSearch() {
    setState(() => _showSearch = !_showSearch);
    if (_showSearch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
    }
  }

  Future<void> _find({bool forward = true}) async {
    final controller = _controller;
    if (controller == null) return;
    try {
      final query = _searchController.text;
      final Uint8List pattern;
      if (_textSearch) {
        pattern = Uint8List.fromList(utf8.encode(query));
      } else {
        pattern = parseHexEditorBytes(query);
      }
      if (pattern.isEmpty) return;
      setState(() => _searchError = null);
      final result = await controller.find(pattern, forward: forward);
      if (mounted && result == null) {
        setState(() => _searchError = context.hexTr('No match found'));
      }
    } on FormatException {
      if (mounted)
        setState(
          () => _searchError = context.hexTr(
            'Enter complete hexadecimal byte pairs.',
          ),
        );
    } catch (error) {
      if (mounted) setState(() => _searchError = '$error');
    }
  }

  Future<void> _goto() async {
    final controller = _controller;
    if (controller == null) return;
    final input = TextEditingController(
      text: '0x${controller.caretOffset.toRadixString(16).toUpperCase()}',
    );
    String? error;
    final offset = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          void submit() {
            final value = parseHexEditorOffset(input.text, controller.length);
            if (value == null) {
              setDialogState(
                () => error = context.hexTr('Enter an offset within the file.'),
              );
              return;
            }
            Navigator.pop(dialogContext, value);
          }

          return AlertDialog(
            title: Text(context.hexTr('Go to offset')),
            content: SizedBox(
              width: 350,
              child: TextField(
                controller: input,
                autofocus: true,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: context.hexTr('Decimal or 0x hexadecimal'),
                  errorText: error,
                ),
                onSubmitted: (_) => submit(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(context.hexTr('Cancel')),
              ),
              FilledButton(
                onPressed: submit,
                child: Text(context.hexTr('Go to offset')),
              ),
            ],
          );
        },
      ),
    );
    // The route may animate out after showDialog completes; dispose the text
    // controller after its final frame rather than while the field unmounts.
    WidgetsBinding.instance.addPostFrameCallback((_) => input.dispose());
    if (offset != null && mounted) controller.goToOffset(offset);
  }

  Future<void> _requestClose() async {
    if (_closing || _session?.isSaving == true) return;
    _closing = true;
    try {
      await _controller?.settled;
      if (!mounted) return;
      if (_session?.isDirty == true) {
        final choice = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(context.hexTr('Save changes to this binary file?')),
            content: Text(
              context.hexTr(
                'Your edits are kept until you save or discard them.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, 'cancel'),
                child: Text(context.hexTr('Cancel')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, 'discard'),
                child: Text(context.hexTr('Discard')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, 'save'),
                child: Text(context.hexTr('Save')),
              ),
            ],
          ),
        );
        if (choice == null || choice == 'cancel') return;
        if (choice == 'save' && !await _save()) return;
      }
      if (!mounted) return;
      setState(() => _allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    } finally {
      _closing = false;
    }
  }

  Widget _command(String label, IconData icon, VoidCallback? command) =>
      IconButton(
        tooltip: context.hexTr(label),
        icon: Icon(icon, size: 20),
        onPressed: command,
      );

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final session = _session;
    final ready = controller != null && session != null;
    final canWrite = ready && session.isCurrent;
    final color = Theme.of(context).colorScheme;
    return PopScope<void>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_requestClose());
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
              unawaited(_save()),
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
              unawaited(_save()),
          const SingleActivator(LogicalKeyboardKey.keyF, control: true):
              _toggleSearch,
          const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
              _toggleSearch,
          const SingleActivator(LogicalKeyboardKey.keyG, control: true): () =>
              unawaited(_goto()),
          const SingleActivator(LogicalKeyboardKey.keyG, meta: true): () =>
              unawaited(_goto()),
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (_showSearch) {
              setState(() => _showSearch = false);
            } else {
              unawaited(_requestClose());
            }
          },
        },
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            leading: IconButton(
              tooltip: context.hexTr('Close'),
              icon: const Icon(Icons.close),
              onPressed: session?.isSaving == true
                  ? null
                  : () => unawaited(_requestClose()),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${session?.isDirty == true ? '● ' : ''}${widget.file.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  context.hexTr('Hex editor'),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
            actions: [
              if (session?.isSaving == true)
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      semanticsLabel: context.hexTr('Saving…'),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: FilledButton.icon(
                  key: const ValueKey('hex-save'),
                  onPressed: canWrite && !session.isSaving && session.isDirty
                      ? () => unawaited(_save())
                      : null,
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: Text(
                    context.hexTr(
                      session?.isSaving == true ? 'Saving…' : 'Save',
                    ),
                  ),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              if (ready)
                Material(
                  color: color.surfaceContainerLow,
                  child: SizedBox(
                    height: 46,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          const SizedBox(width: 8),
                          _command(
                            'Undo',
                            Icons.undo,
                            canWrite && controller.canUndo
                                ? () => unawaited(_run(controller.undo))
                                : null,
                          ),
                          _command(
                            'Redo',
                            Icons.redo,
                            canWrite && controller.canRedo
                                ? () => unawaited(_run(controller.redo))
                                : null,
                          ),
                          _command(
                            'Copy',
                            Icons.copy_outlined,
                            controller.hasSelection
                                ? () => unawaited(_run(controller.copy))
                                : null,
                          ),
                          _command(
                            'Paste',
                            Icons.paste_outlined,
                            canWrite
                                ? () => unawaited(_run(controller.paste))
                                : null,
                          ),
                          const SizedBox(width: 8),
                          _command('Find bytes', Icons.search, _toggleSearch),
                          _command(
                            'Go to offset',
                            Icons.my_location,
                            () => unawaited(_goto()),
                          ),
                          const SizedBox(width: 12),
                          Tooltip(
                            message: context.hexTr(
                              controller.insertMode
                                  ? 'Insert bytes'
                                  : 'Overwrite bytes',
                            ),
                            child: FilterChip(
                              label: Text(
                                context.hexTr(
                                  controller.insertMode
                                      ? 'Insert'
                                      : 'Overwrite',
                                ),
                              ),
                              selected: controller.insertMode,
                              onSelected: canWrite
                                  ? (value) => controller.insertMode = value
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Tooltip(
                            message: context.hexTr('Bytes per row'),
                            child: DropdownButton<int>(
                              value: _bytesPerRow,
                              items: [
                                for (final count in [8, 16, 32])
                                  DropdownMenuItem(
                                    value: count,
                                    child: Text('$count'),
                                  ),
                              ],
                              onChanged: (value) {
                                if (value != null)
                                  setState(() => _bytesPerRow = value);
                              },
                            ),
                          ),
                          _command(
                            'Zoom out',
                            Icons.text_decrease,
                            _fontSize > 10
                                ? () => setState(() => _fontSize--)
                                : null,
                          ),
                          _command(
                            'Zoom in',
                            Icons.text_increase,
                            _fontSize < 24
                                ? () => setState(() => _fontSize++)
                                : null,
                          ),
                          const SizedBox(width: 8),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_showSearch && ready) _searchBar(),
              if (_error != null && ready) _message(_error!, error: true),
              if (_notice != null) _message(_notice!),
              if (ready && !session.isCurrent)
                _message(context.hexTr('Storage unavailable'), error: true),
              Expanded(
                child: _loading
                    ? _preparing()
                    : !ready
                    ? _loadError()
                    : Directionality(
                        textDirection: TextDirection.ltr,
                        child: HexEditor(
                          controller: controller,
                          readOnly: !session.isCurrent,
                          bytesPerRow: _bytesPerRow,
                          fontSize: _fontSize,
                          requestSave: () => unawaited(_save()),
                          requestSearch: _toggleSearch,
                          requestGoTo: () => unawaited(_goto()),
                          labels: HexEditorLabels(
                            editor: context.hexTr('Hex editor'),
                            offset: context.hexTr('Offset'),
                            text: context.hexTr('Text'),
                            copy: context.hexTr('Copy'),
                            cut: context.hexTr('Cut'),
                            paste: context.hexTr('Paste'),
                            selectAll: context.hexTr('Select all'),
                            enterBytes: context.hexTr('Enter bytes…'),
                            hexInput: context.hexTr('Hex bytes'),
                            textInput: context.hexTr('Byte text (Latin-1)'),
                            apply: context.hexTr('Apply'),
                            cancel: context.hexTr('Cancel'),
                            retry: context.hexTr('Retry'),
                            scroll: context.hexTr('Scroll bytes'),
                            loading: context.hexTr('Loading bytes'),
                          ),
                          onError: (error, stack) {
                            if (mounted) setState(() => _error = '$error');
                          },
                        ),
                      ),
              ),
              if (ready)
                Material(
                  color: color.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 20,
                        runSpacing: 6,
                        children: [
                          Text(
                            '${controller.length} ${context.hexTr('bytes')}',
                          ),
                          Text(
                            '${context.hexTr('Offset')}: 0x${controller.caretOffset.toRadixString(16).toUpperCase()} (${controller.caretOffset})',
                          ),
                          Text(
                            '${context.hexTr('Selection')}: ${controller.selectionLength} ${context.hexTr('bytes')}',
                          ),
                          Text(
                            context.hexTr(
                              session.isDirty ? 'Modified' : 'Saved',
                            ),
                          ),
                          if (kIsWeb)
                            Text(
                              context.hexTr(
                                'Browser editing is limited to 64 MiB.',
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchBar() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Row(
      children: [
        DropdownButton<bool>(
          value: _textSearch,
          items: [
            DropdownMenuItem(
              value: false,
              child: Text(context.hexTr('Hex bytes')),
            ),
            DropdownMenuItem(
              value: true,
              child: Text(context.hexTr('UTF-8 text')),
            ),
          ],
          onChanged: (value) => setState(() {
            _textSearch = value ?? false;
            _searchError = null;
          }),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            key: const ValueKey('hex-find-query'),
            controller: _searchController,
            focusNode: _searchFocus,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              isDense: true,
              labelText: context.hexTr('Find bytes'),
              errorText: _searchError,
            ),
            onSubmitted: (_) => unawaited(_find()),
          ),
        ),
        if (_controller?.isSearching == true)
          const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else ...[
          _command(
            'Find previous',
            Icons.keyboard_arrow_up,
            () => unawaited(_find(forward: false)),
          ),
          _command(
            'Find next',
            Icons.keyboard_arrow_down,
            () => unawaited(_find()),
          ),
        ],
        _command(
          'Close',
          Icons.close,
          () => setState(() => _showSearch = false),
        ),
      ],
    ),
  );

  Widget _preparing() => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.hexTr('Preparing editable copy…'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 20),
            LinearProgressIndicator(
              value: _total != null && _total! > 0
                  ? (_received / _total!).clamp(0, 1)
                  : null,
            ),
            const SizedBox(height: 10),
            Text(
              '$_received ${context.hexTr('bytes')}${_total != null ? ' / $_total' : ''}',
            ),
            const SizedBox(height: 16),
            Text(
              context.hexTr(
                'Preparing a stable copy keeps undo available after saving.',
              ),
              textAlign: TextAlign.center,
            ),
            if (kIsWeb)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  context.hexTr('Browser editing is limited to 64 MiB.'),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _loadError() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 36),
          const SizedBox(height: 12),
          Text(
            context.hexTr('Cannot open hex editor'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          SelectableText(_error ?? '', textAlign: TextAlign.center),
        ],
      ),
    ),
  );

  Widget _message(String message, {bool error = false}) => Material(
    color: error
        ? Theme.of(context).colorScheme.errorContainer
        : Theme.of(context).colorScheme.secondaryContainer,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(
            error ? Icons.error_outline : Icons.check_circle_outline,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(child: SelectableText(message)),
          IconButton(
            tooltip: context.hexTr('Close'),
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() {
              if (error) {
                _error = null;
              } else {
                _notice = null;
              }
            }),
          ),
        ],
      ),
    ),
  );
}

/// Parses complete byte pairs, allowing whitespace between pairs or a compact
/// hexadecimal string. A trailing nibble is rejected instead of truncated.
Uint8List parseHexEditorBytes(String input) {
  final compact = input.replaceAll(RegExp(r'\s+'), '');
  if (compact.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(compact)) {
    throw const FormatException('Enter complete hexadecimal byte pairs.');
  }
  return Uint8List.fromList([
    for (var i = 0; i < compact.length; i += 2)
      int.parse(compact.substring(i, i + 2), radix: 16),
  ]);
}

/// Decimal by default; an explicit 0x prefix selects hexadecimal. EOF is a
/// valid caret position because the editor supports appending bytes.
int? parseHexEditorOffset(String input, int length) {
  final value = input.trim();
  final hex = value.toLowerCase().startsWith('0x');
  final digits = hex ? value.substring(2) : value;
  if (!(hex ? RegExp(r'^[0-9a-fA-F]+$') : RegExp(r'^\d+$')).hasMatch(digits))
    return null;
  final offset = int.tryParse(digits, radix: hex ? 16 : 10);
  return offset != null && offset >= 0 && offset <= length ? offset : null;
}
