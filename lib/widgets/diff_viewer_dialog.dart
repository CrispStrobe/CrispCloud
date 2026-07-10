// lib/widgets/diff_viewer_dialog.dart
//
// Side-by-side file comparison viewer.
// Compares two text files (local vs remote, or two selected files).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/log_service.dart';

/// Show a diff dialog comparing two raw text strings.
/// Used for version diff where content is already loaded.
void showDiffViewerFromContent(
  BuildContext context, {
  required String leftContent,
  required String rightContent,
  String leftLabel = 'Left',
  String rightLabel = 'Right',
}) {
  showDialog(
    context: context,
    builder: (_) => _ContentDiffDialog(
      leftContent: leftContent,
      rightContent: rightContent,
      leftLabel: leftLabel,
      rightLabel: rightLabel,
    ),
  );
}

void showDiffViewerDialog(BuildContext context, WidgetRef ref, FileItem leftFile, FileItem rightFile, {PanelSide leftSide = PanelSide.local, PanelSide rightSide = PanelSide.remote}) {
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

  List<String> _leftLines = [];
  List<String> _rightLines = [];
  List<DiffLine> _diffResult = [];
  bool _loading = true;
  String? _error;

  final _leftScrollController = ScrollController();
  final _rightScrollController = ScrollController();
  final bool _syncScroll = true;

  @override
  void initState() {
    super.initState();
    _leftScrollController.addListener(_onLeftScroll);
    _loadFiles();
  }

  void _onLeftScroll() {
    if (_syncScroll && _rightScrollController.hasClients) {
      _rightScrollController.jumpTo(_leftScrollController.offset);
    }
  }

  Future<String> _loadFileContent(FileItem file, PanelSide side) async {
    if (side == PanelSide.local && file.path != null) {
      return await File(file.path!).readAsString();
    } else {
      final auth = ref.read(authProvider);
      final path = file.path ?? '/${file.name}';
      final bytes = await auth.client.downloadFileBytes(path);
      return String.fromCharCodes(bytes);
    }
  }

  Future<void> _loadFiles() async {
    try {
      final leftContent = await _loadFileContent(widget.leftFile, widget.leftSide);
      final rightContent = await _loadFileContent(widget.rightFile, widget.rightSide);

      _leftLines = leftContent.split('\n');
      _rightLines = rightContent.split('\n');
      _diffResult = _computeDiff(_leftLines, _rightLines);

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      _log.error('Failed to load files for diff', e);
      if (mounted) {
        setState(() {
          _error = 'Failed to load files: $e';
          _loading = false;
        });
      }
    }
  }

  /// Simple line-by-line diff using the Longest Common Subsequence approach.
  List<DiffLine> _computeDiff(List<String> left, List<String> right) {
    final result = <DiffLine>[];

    // LCS table
    final m = left.length;
    final n = right.length;
    final lcs = List.generate(m + 1, (_) => List.filled(n + 1, 0));

    for (int i = 1; i <= m; i++) {
      for (int j = 1; j <= n; j++) {
        if (left[i - 1] == right[j - 1]) {
          lcs[i][j] = lcs[i - 1][j - 1] + 1;
        } else {
          lcs[i][j] = lcs[i - 1][j] > lcs[i][j - 1] ? lcs[i - 1][j] : lcs[i][j - 1];
        }
      }
    }

    // Backtrack to produce diff
    int i = m, j = n;
    final stack = <DiffLine>[];

    while (i > 0 || j > 0) {
      if (i > 0 && j > 0 && left[i - 1] == right[j - 1]) {
        stack.add(DiffLine(type: DiffType.equal, leftLine: i, rightLine: j, text: left[i - 1]));
        i--;
        j--;
      } else if (j > 0 && (i == 0 || lcs[i][j - 1] >= lcs[i - 1][j])) {
        stack.add(DiffLine(type: DiffType.added, rightLine: j, text: right[j - 1]));
        j--;
      } else {
        stack.add(DiffLine(type: DiffType.removed, leftLine: i, text: left[i - 1]));
        i--;
      }
    }

    result.addAll(stack.reversed);
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final changes = _diffResult.where((d) => d.type != DiffType.equal).length;

    return Dialog(
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.85,
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.compare_arrows, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Diff: ${widget.leftFile.name} vs ${widget.rightFile.name}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!_loading && _error == null)
                    Text(
                      '$changes ${changes == 1 ? 'change' : 'changes'}',
                      style: TextStyle(color: theme.colorScheme.primary, fontSize: 12),
                    ),
                  const SizedBox(width: 16),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Body
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)))
                      : _diffResult.isEmpty
                          ? const Center(child: Text('Files are identical'))
                          : _buildDiffView(theme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiffView(ThemeData theme) {
    final addedColor = Colors.green.withValues(alpha: 0.15);
    final removedColor = Colors.red.withValues(alpha: 0.15);

    return Row(
      children: [
        // Left file header
        Expanded(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                child: Row(
                  children: [
                    const Icon(Icons.description, size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${widget.leftSide == PanelSide.local ? 'Local' : 'Remote'}: ${widget.leftFile.name}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: _leftScrollController,
                  itemCount: _diffResult.length,
                  itemExtent: 20,
                  itemBuilder: (_, index) {
                    final d = _diffResult[index];
                    if (d.type == DiffType.added) {
                      return Container(height: 20, color: addedColor);
                    }
                    return Container(
                      height: 20,
                      color: d.type == DiffType.removed ? removedColor : null,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 40,
                            child: Text(
                              d.leftLine?.toString() ?? '',
                              style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant, fontFamily: 'monospace'),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              d.text,
                              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
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
        ),

        Container(width: 1, color: theme.dividerColor),

        // Right file
        Expanded(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                child: Row(
                  children: [
                    const Icon(Icons.description, size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${widget.rightSide == PanelSide.local ? 'Local' : 'Remote'}: ${widget.rightFile.name}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: _rightScrollController,
                  itemCount: _diffResult.length,
                  itemExtent: 20,
                  itemBuilder: (_, index) {
                    final d = _diffResult[index];
                    if (d.type == DiffType.removed) {
                      return Container(height: 20, color: removedColor);
                    }
                    return Container(
                      height: 20,
                      color: d.type == DiffType.added ? addedColor : null,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 40,
                            child: Text(
                              d.rightLine?.toString() ?? '',
                              style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant, fontFamily: 'monospace'),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              d.text,
                              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
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
        ),
      ],
    );
  }

  @override
  void dispose() {
    _leftScrollController.dispose();
    _rightScrollController.dispose();
    super.dispose();
  }
}

enum DiffType { equal, added, removed }

class DiffLine {
  final DiffType type;
  final int? leftLine;
  final int? rightLine;
  final String text;

  DiffLine({required this.type, this.leftLine, this.rightLine, required this.text});
}

/// Compute LCS diff (standalone, reusable outside the dialog state).
List<DiffLine> computeLcsDiff(List<String> left, List<String> right) {
  final m = left.length;
  final n = right.length;
  final lcs = List.generate(m + 1, (_) => List.filled(n + 1, 0));

  for (int i = 1; i <= m; i++) {
    for (int j = 1; j <= n; j++) {
      if (left[i - 1] == right[j - 1]) {
        lcs[i][j] = lcs[i - 1][j - 1] + 1;
      } else {
        lcs[i][j] = lcs[i - 1][j] > lcs[i][j - 1] ? lcs[i - 1][j] : lcs[i][j - 1];
      }
    }
  }

  int i = m, j = n;
  final stack = <DiffLine>[];
  while (i > 0 || j > 0) {
    if (i > 0 && j > 0 && left[i - 1] == right[j - 1]) {
      stack.add(DiffLine(type: DiffType.equal, leftLine: i, rightLine: j, text: left[i - 1]));
      i--; j--;
    } else if (j > 0 && (i == 0 || lcs[i][j - 1] >= lcs[i - 1][j])) {
      stack.add(DiffLine(type: DiffType.added, rightLine: j, text: right[j - 1]));
      j--;
    } else {
      stack.add(DiffLine(type: DiffType.removed, leftLine: i, text: left[i - 1]));
      i--;
    }
  }
  return stack.reversed.toList();
}

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
                  Text('Version Diff', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  Text('+$added', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Text('-$removed', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 16),
                  IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            Expanded(
              child: diffResult.isEmpty
                  ? const Center(child: Text('Files are identical'))
                  : Row(
                      children: [
                        _buildPane(theme, leftLabel, diffResult, true, addedColor, removedColor),
                        Container(width: 1, color: theme.dividerColor),
                        _buildPane(theme, rightLabel, diffResult, false, addedColor, removedColor),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPane(ThemeData theme, String label, List<DiffLine> diff, bool isLeft, Color addedColor, Color removedColor) {
    return Expanded(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            child: Row(
              children: [
                const Icon(Icons.description, size: 14),
                const SizedBox(width: 6),
                Expanded(child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
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
                if (isLeft && d.type == DiffType.added) return Container(height: 20, color: addedColor);
                if (!isLeft && d.type == DiffType.removed) return Container(height: 20, color: removedColor);

                return Container(
                  height: 20,
                  color: d.type == DiffType.removed ? removedColor : d.type == DiffType.added ? addedColor : null,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 40,
                        child: Text(
                          (isLeft ? d.leftLine : d.rightLine)?.toString() ?? '',
                          style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant, fontFamily: 'monospace'),
                        ),
                      ),
                      Expanded(
                        child: Text(d.text, style: const TextStyle(fontSize: 12, fontFamily: 'monospace'), overflow: TextOverflow.clip, maxLines: 1),
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
