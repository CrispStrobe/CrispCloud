// lib/widgets/diff_viewer_dialog.dart
//
// Side-by-side file comparison viewer.
// Compares two text files (local vs remote, or two selected files).

import 'package:flutter/material.dart';

import '../l10n/provider_operation_strings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/commander_strings.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/log_service.dart';
import '../services/file_comparison_service.dart';
import '../services/file_operation_backend.dart';
import '../services/file_operation_service.dart';
export '../services/file_comparison_service.dart' show DiffLine, DiffType;

/// Show a diff dialog comparing two raw text strings.
/// Used for version diff where content is already loaded.
void showDiffViewerFromContent(
  BuildContext context, {
  required String leftContent,
  required String rightContent,
  String? leftLabel,
  String? rightLabel,
}) {
  showDialog(
    context: context,
    builder: (_) => _ContentDiffDialog(
      leftContent: leftContent,
      rightContent: rightContent,
      leftLabel: leftLabel ?? DiffViewerStrings(context).text('left'),
      rightLabel: rightLabel ?? DiffViewerStrings(context).text('right'),
    ),
  );
}

void showDiffViewerDialog(
  BuildContext context,
  WidgetRef ref,
  FileItem leftFile,
  FileItem rightFile, {
  PanelSide leftSide = PanelSide.local,
  PanelSide rightSide = PanelSide.remote,
}) {
  showDialog(
    context: context,
    builder: (_) => _DiffViewerDialog(
      leftFile: leftFile,
      rightFile: rightFile,
      leftSide: leftSide,
      rightSide: rightSide,
    ),
  );
}

class _DiffViewerDialog extends ConsumerStatefulWidget {
  final FileItem leftFile;
  final FileItem rightFile;
  final PanelSide leftSide;
  final PanelSide rightSide;

  const _DiffViewerDialog({
    required this.leftFile,
    required this.rightFile,
    required this.leftSide,
    required this.rightSide,
  });

  @override
  ConsumerState<_DiffViewerDialog> createState() => _DiffViewerDialogState();
}

class _DiffViewerDialogState extends ConsumerState<_DiffViewerDialog> {
  static const _log = Log('DiffViewer');
  final _scroll = ScrollController();
  final _merged = TextEditingController();
  FileOperationBackend? _leftSource;
  FileOperationBackend? _rightSource;
  PanelFileOrigin? _leftOrigin;
  PanelFileOrigin? _writeOrigin;
  bool _swapped = false;
  FileItem get _leftFile => _swapped ? widget.rightFile : widget.leftFile;
  FileItem get _rightFile => _swapped ? widget.leftFile : widget.rightFile;
  PanelSide get _leftSide => _swapped ? widget.rightSide : widget.leftSide;
  PanelSide get _rightSide => _swapped ? widget.leftSide : widget.rightSide;
  MergeDocumentSession? _leftDocument;
  MergeDocumentSession? _rightDocument;
  BinaryComparison? _binaryResult;
  List<DiffLine> _rows = [];
  List<DiffHunk> _hunks = [];
  int _hunkIndex = 0;
  bool _loading = true;
  bool _binary = false;
  bool _edit = false;
  bool _ignoreWhitespace = false;
  bool _ignoreCase = false;
  bool _dirty = false;
  bool _cancel = false;
  String? _error;
  int _comparedBytes = 0;

  @override
  void initState() {
    super.initState();
    _binary =
        (_leftFile.size ?? 0) > MergeDocumentSession.maxTextBytes ||
        (_rightFile.size ?? 0) > MergeDocumentSession.maxTextBytes;
    _loadFiles();
  }

  FileOperationBackend _source(FileItem file, PanelSide side) {
    final origin = ref.read(panelProvider(side)).captureOperationOrigin([file]);
    return fileOperationBackend(
      source: origin.source,
      local: ref.read(localFileServiceProvider),
      isCurrent: () => mounted && origin.isCurrent,
    );
  }

  Future<void> _loadFiles() async {
    setState(() {
      _loading = true;
      _cancel = false;
      _error = null;
      _comparedBytes = 0;
    });
    try {
      _leftOrigin ??= ref
          .read(panelProvider(_leftSide))
          .originForOperation(_leftFile);
      _leftSource ??= _source(_leftFile, _leftSide);
      _rightSource ??= _source(_rightFile, _rightSide);
      _writeOrigin ??= ref
          .read(panelProvider(_rightSide))
          .originForOperation(_rightFile);
      if (_binary) {
        _binaryResult = await compareBinaryFiles(
          _leftSource!,
          _leftFile,
          _rightSource!,
          _rightFile,
          isCancelled: () =>
              _cancel || !_leftSource!.isCurrent || !_rightSource!.isCurrent,
          onProgress: (bytes) {
            if (mounted) setState(() => _comparedBytes = bytes);
          },
        );
      } else {
        _leftDocument = await MergeDocumentSession.open(
          _leftSource!,
          _leftFile,
        );
        _rightDocument = await MergeDocumentSession.open(
          _rightSource!,
          _rightFile,
        );
        _merged.text = _rightDocument!.document.text;
        _dirty = false;
        _recompute();
      }
    } catch (error) {
      _log.warn('Comparison failed', error);
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _recompute() {
    _rows = compareTextLines(
      _leftDocument!.document.text.split('\n'),
      _merged.text.split('\n'),
      ignoreWhitespace: _ignoreWhitespace,
      ignoreCase: _ignoreCase,
    );
    _hunks = differenceHunks(_rows);
    _hunkIndex = _hunks.isEmpty ? 0 : _hunkIndex.clamp(0, _hunks.length - 1);
  }

  void _jump(int delta) {
    if (_hunks.isEmpty) return;
    setState(
      () => _hunkIndex = (_hunkIndex + delta).clamp(0, _hunks.length - 1),
    );
    if (_scroll.hasClients) {
      _scroll.jumpTo(
        (_hunks[_hunkIndex].firstRow * 24.0).clamp(
          0,
          _scroll.position.maxScrollExtent,
        ),
      );
    }
  }

  void _useLeftHunk() {
    if (_hunks.isEmpty) return;
    setState(() {
      _merged.text = mergeHunk(
        _leftDocument!.document.text,
        _merged.text,
        _hunks[_hunkIndex],
      );
      _dirty = true;
      _recompute();
    });
  }

  Future<void> _save() async {
    if (_writeOrigin?.isCurrent != true) {
      setState(
        () => _error = 'The original file source is no longer available. Reopen it before saving.',
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _rightDocument!.save(_merged.text);
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _recompute();
      });
      await ref.read(panelProvider(_rightSide)).refresh();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _close() async {
    if (_loading) {
      setState(() => _cancel = true);
      return;
    }
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(context.commanderTr("Discard unsaved merge?")),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.commanderTr("Keep editing")),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.commanderTr("Discard")),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_loading && !_dirty,
    child: Dialog(
      child: SizedBox(
        width: MediaQuery.sizeOf(context).width * .9,
        height: MediaQuery.sizeOf(context).height * .85,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.compare_arrows),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_leftFile.name} ↔ ${_rightFile.name}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: _close,
                    tooltip: _loading
                        ? context.commanderTr("Stop comparison")
                        : context.commanderTr("Close"),
                    icon: Icon(_loading ? Icons.stop : Icons.close),
                  ),
                ],
              ),
            ),
            if (_dirty) Text(context.commanderTr("Unsaved merge")),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .35,
              ),
              child: SingleChildScrollView(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    IconButton(
                      tooltip: context.commanderTr(
                        "Swap files and merge target",
                      ),
                      onPressed:
                          _loading ||
                              _dirty ||
                              _leftSource == null ||
                              _rightSource == null
                          ? null
                          : () {
                              setState(() {
                                _swapped = !_swapped;
                                final previousLeftSource = _leftSource;
                                _leftSource = _rightSource;
                                _rightSource = previousLeftSource;
                                final previousLeftOrigin = _leftOrigin;
                                _leftOrigin = _writeOrigin;
                                _writeOrigin = previousLeftOrigin;
                                _leftDocument = null;
                                _rightDocument = null;
                                _rows = [];
                                _hunks = [];
                              });
                              _loadFiles();
                            },
                      icon: const Icon(Icons.swap_horiz),
                    ),
                    FilterChip(
                      label: Text(context.commanderTr("Binary")),
                      selected: _binary,
                      onSelected: _loading || _dirty
                          ? null
                          : (value) {
                              setState(() => _binary = value);
                              _loadFiles();
                            },
                    ),
                    if (!_binary) ...[
                      FilterChip(
                        label: Text(context.commanderTr("Ignore whitespace")),
                        selected: _ignoreWhitespace,
                        onSelected: _loading || _leftDocument == null
                            ? null
                            : (value) => setState(() {
                                _ignoreWhitespace = value;
                                _recompute();
                              }),
                      ),
                      FilterChip(
                        label: Text(context.commanderTr("Ignore case")),
                        selected: _ignoreCase,
                        onSelected: _loading || _leftDocument == null
                            ? null
                            : (value) => setState(() {
                                _ignoreCase = value;
                                _recompute();
                              }),
                      ),
                      IconButton(
                        onPressed: _hunks.isEmpty ? null : () => _jump(-1),
                        tooltip: context.commanderTr("Previous difference"),
                        icon: const Icon(Icons.arrow_upward),
                      ),
                      Text(
                        _hunks.isEmpty
                            ? context.commanderTr("No differences")
                            : context.commanderTr("{0} / {1} blocks", [
                                _hunkIndex + 1,
                                _hunks.length,
                              ]),
                      ),
                      IconButton(
                        onPressed: _hunks.isEmpty ? null : () => _jump(1),
                        tooltip: context.commanderTr("Next difference"),
                        icon: const Icon(Icons.arrow_downward),
                      ),
                      TextButton.icon(
                        onPressed: _loading || _hunks.isEmpty
                            ? null
                            : _useLeftHunk,
                        icon: const Icon(Icons.arrow_forward),
                        label: Text(context.commanderTr("Use left block")),
                      ),
                      FilterChip(
                        label: Text(
                          context.commanderTr("Edit merged right file"),
                        ),
                        selected: _edit,
                        onSelected: _loading
                            ? null
                            : (value) => setState(() {
                                _edit = value;
                                if (!value) _recompute();
                              }),
                      ),
                      FilledButton(
                        onPressed:
                            _loading ||
                                !_dirty ||
                                _writeOrigin?.isCurrent != true
                            ? null
                            : _save,
                        child: Text(context.commanderTr("Save merge to right")),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_loading) ...[
              const LinearProgressIndicator(),
              if (_binary)
                Text(
                  context.commanderTr("Compared {0} bytes", [_comparedBytes]),
                ),
            ],
            Expanded(
              child: _loading
                  ? const SizedBox.shrink()
                  : _binary
                  ? _binaryView()
                  : _textView(),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _binaryView() {
    final result = _binaryResult;
    if (result == null) {
      return Center(child: Text(context.commanderTr("No comparison result.")));
    }
    return Center(
      child: SelectableText(
        result.equal
            ? context.commanderTr(
                "Files are byte-for-byte identical ({0} bytes).",
                [result.leftBytes],
              )
            : context.commanderTr(
                "Files differ in {0} byte positions.\nFirst difference: byte {1} (0x{2}).\nLeft: {3} bytes • Right: {4} bytes.\nComparison streams both files without loading the entire contents.",
                [
                  result.differingBytes,
                  result.firstDifference,
                  result.firstDifference!.toRadixString(16),
                  result.leftBytes,
                  result.rightBytes,
                ],
              ),
      ),
    );
  }

  Widget _textView() {
    if (_rightDocument == null) return const SizedBox.shrink();
    if (_edit) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: TextField(
          controller: _merged,
          expands: true,
          maxLines: null,
          minLines: null,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: context.commanderTr("Merged right • {0} • {1}", [
              _rightDocument!.document.encoding.label,
              _rightDocument!.document.lineEnding.label,
            ]),
          ),
          onChanged: (_) => setState(() {
            _dirty = true;
            _recompute();
          }),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      itemExtent: 24,
      itemCount: _rows.length,
      itemBuilder: (context, index) {
        final row = _rows[index];
        Widget cell(bool left) {
          final absent = left
              ? row.type == DiffType.added
              : row.type == DiffType.removed;
          return Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              color: row.type == DiffType.equal
                  ? null
                  : (left ? Colors.red : Colors.green).withValues(alpha: .12),
              child: Text(
                absent
                    ? ''
                    : '${left ? row.leftLine : row.rightLine}  ${left ? row.text : row.rightText ?? row.text}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          );
        }

        return Row(
          children: [cell(true), const VerticalDivider(width: 1), cell(false)],
        );
      },
    );
  }

  @override
  void dispose() {
    _cancel = true;
    _scroll.dispose();
    _merged.dispose();
    super.dispose();
  }
}

/// Compatibility API for version comparisons; implementation is memory-bounded.
List<DiffLine> computeLcsDiff(List<String> left, List<String> right) =>
    compareTextLines(left, right);

/// Diff viewer for pre-loaded content (used by version diff).
class _ContentDiffDialog extends StatelessWidget {
  final String leftContent;
  final String rightContent;
  final String leftLabel;
  final String rightLabel;

  const _ContentDiffDialog({
    required this.leftContent,
    required this.rightContent,
    required this.leftLabel,
    required this.rightLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final leftLines = leftContent.split('\n');
    final rightLines = rightContent.split('\n');
    final diffResult = computeLcsDiff(leftLines, rightLines);

    final added = diffResult.where((d) => d.type == DiffType.added).length;
    final removed = diffResult.where((d) => d.type == DiffType.removed).length;
    final addedColor = Colors.green.withValues(alpha: 0.15);
    final removedColor = Colors.red.withValues(alpha: 0.15);

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: theme.colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  const Icon(Icons.compare, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    context.commanderTr("Version Diff"),
                    style: theme.textTheme.titleMedium,
                  ),
                  const Spacer(),
                  Text(
                    '+$added',
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '-$removed',
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: diffResult.isEmpty
                  ? Center(
                      child: Text(context.commanderTr("Files are identical")),
                    )
                  : Row(
                      children: [
                        _buildPane(
                          theme,
                          leftLabel,
                          diffResult,
                          true,
                          addedColor,
                          removedColor,
                        ),
                        Container(width: 1, color: theme.dividerColor),
                        _buildPane(
                          theme,
                          rightLabel,
                          diffResult,
                          false,
                          addedColor,
                          removedColor,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPane(
    ThemeData theme,
    String label,
    List<DiffLine> diff,
    bool isLeft,
    Color addedColor,
    Color removedColor,
  ) {
    return Expanded(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.5,
            ),
            child: Row(
              children: [
                const Icon(Icons.description, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: diff.length,
              itemExtent: 20,
              itemBuilder: (_, index) {
                final d = diff[index];
                // Skip lines not visible on this side
                if (isLeft && d.type == DiffType.added) {
                  return Container(height: 20, color: addedColor);
                }
                if (!isLeft && d.type == DiffType.removed) {
                  return Container(height: 20, color: removedColor);
                }

                return Container(
                  height: 20,
                  color: d.type == DiffType.removed
                      ? removedColor
                      : d.type == DiffType.added
                      ? addedColor
                      : null,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 40,
                        child: Text(
                          (isLeft ? d.leftLine : d.rightLine)?.toString() ?? '',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          d.text,
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                          overflow: TextOverflow.clip,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
