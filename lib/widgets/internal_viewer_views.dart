// lib/widgets/internal_viewer_views.dart
//
// Render-mode widgets used by the F3 internal viewer dialog. Each widget is
// parameterised so it renders pure data (lines/bytes) with optional search
// highlights, and stays independent of dialog state.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

import '../services/file_bytes_loader.dart';
import '../services/internal_viewer_service.dart';
import '../services/viewer_search_service.dart';
import '../services/viewer_text_decoder.dart';
import '../l10n/commander_strings.dart';

/// Monospace text style helper shared by the line-mode views.
TextStyle monoTextStyle(double fontSize, Color color) {
  return TextStyle(
    fontFamily: 'AppMono',
    fontFamilyFallback: const [
      'Menlo',
      'Consolas',
      'DejaVu Sans Mono',
      'monospace',
    ],
    fontFeatures: const [FontFeature.tabularFigures()],
    fontSize: fontSize,
    height: 1.5,
    letterSpacing: 0,
    color: color,
    fontWeight: FontWeight.w400,
  );
}

// ---------------------------------------------------------------------------
// In-memory plain-text / safe-byte line list
// ---------------------------------------------------------------------------

/// Vertically virtualized list of monospace lines with line numbers.
/// Uniform rows ([itemExtent]) make scroll-jump math exact.
class MonoLineListView extends StatelessWidget {
  final List<String> lines;
  final double fontScale;
  final ScrollController? controller;

  /// Row index of the active search match (highlighted), or null.
  final int? activeMatchLine;

  /// (start, end) of the match inside the active line, or null.
  final (int, int)? activeMatchLocal;

  const MonoLineListView({
    super.key,
    required this.lines,
    required this.fontScale,
    this.controller,
    this.activeMatchLine,
    this.activeMatchLocal,
  });

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty || (lines.length == 1 && lines.first.isEmpty)) {
      return const Center(child: Text('(empty file)'));
    }

    final theme = Theme.of(context);
    final fontSize = 13.0 * fontScale;
    final rowExtent = fontSize * 1.5;
    final style = monoTextStyle(fontSize, theme.colorScheme.onSurface);
    final dimStyle = style.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontSize: fontSize * 0.85,
      height: 1.2,
    );

    return ListView.builder(
      controller: controller,
      itemCount: lines.length,
      itemExtent: rowExtent,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      itemBuilder: (context, i) {
        final line = lines[i];
        final isMatchRow = activeMatchLine == i && activeMatchLocal != null;

        InlineSpan lineSpan;
        if (isMatchRow) {
          final (s, e) = activeMatchLocal!;
          final cs = s.clamp(0, line.length);
          final ce = e.clamp(cs, line.length);
          final matchStyle = style.copyWith(
            backgroundColor: theme.colorScheme.tertiaryContainer.withValues(
              alpha: 0.9,
            ),
          );
          lineSpan = TextSpan(
            children: [
              TextSpan(text: line.substring(0, cs)),
              TextSpan(text: line.substring(cs, ce), style: matchStyle),
              TextSpan(text: line.substring(ce)),
            ],
          );
        } else {
          lineSpan = TextSpan(text: line);
        }

        return Row(
          children: [
            Text('${i + 1}'.padLeft(6), style: dimStyle),
            const SizedBox(width: 8),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text.rich(
                  lineSpan,
                  style: style,
                  softWrap: false,
                  maxLines: 1,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Streaming safe-byte view (arbitrarily large local files)
// ---------------------------------------------------------------------------

/// One text window's byte budget. Paging and goto rebase the window anywhere in
/// the file; this is a memory bound, not a limit on which bytes can be viewed.
const int kMaxIndexedBytes = 4 * 1024 * 1024;
const int kMaxLineRenderBytes = 8 * 1024;

/// Line-indexed view over a [ViewBytesSource]: lines are discovered by scans
/// ([kMaxIndexedBytes] cap) and rendered either as decoded text ([rawText])
/// or as safe ASCII/binary ([binaryMode]). Column one shows the byte offset
/// of each line like the hex view, which keeps huge files orientable.
class StreamingSafeView extends StatefulWidget {
  final ViewBytesSource source;
  final bool binaryMode;
  final bool rawText;
  final String encoding;
  final double fontScale;
  final ScrollController? controller;

  /// Active byte-search match run (absolute offsets), or null.
  final int? matchStart;
  final int? matchEnd;

  /// When this byte offset changes (non-null) the view jumps to the line
  /// containing it — used by goto/match navigation from the dialog.
  final int? scrollToByte;

  /// Distinguishes repeated explicit jumps from unrelated parent rebuilds.
  final int scrollRequest;

  const StreamingSafeView({
    super.key,
    required this.source,
    required this.fontScale,
    this.controller,
    this.binaryMode = false,
    this.rawText = false,
    this.encoding = 'utf8',
    this.matchStart,
    this.matchEnd,
    this.scrollToByte,
    this.scrollRequest = 0,
  });

  @override
  State<StreamingSafeView> createState() => _StreamingSafeViewState();
}

class _StreamingSafeViewState extends State<StreamingSafeView> {
  final List<int> _lineOffsets = [0];
  int _windowStart = 0;
  int _windowEnd = 0;
  int _indexedBytes = 0;
  int? _pendingTarget;
  bool _windowDone = false;
  String? _error;
  static const int _indexChunk = 128 * 1024;
  static const int _maximumLines = 200000;

  int get _unit => widget.rawText ? viewerCodeUnitBytes(widget.encoding) : 1;
  double get _rowExtent => 13.0 * widget.fontScale * 1.5;
  int get _offsetDigits => (widget.source.size > 0 ? widget.source.size - 1 : 0)
      .toRadixString(16)
      .length
      .clamp(8, 16);

  @override
  void initState() {
    super.initState();
    _resetWindow(widget.scrollToByte ?? 0, center: widget.scrollToByte != null);
  }

  @override
  void didUpdateWidget(StreamingSafeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.source, widget.source) ||
        oldWidget.encoding != widget.encoding ||
        oldWidget.rawText != widget.rawText) {
      _resetWindow(
        widget.scrollToByte ?? 0,
        center: widget.scrollToByte != null,
      );
      return;
    }
    final target = widget.scrollToByte;
    if (target != null &&
        (target != oldWidget.scrollToByte ||
            widget.scrollRequest != oldWidget.scrollRequest)) {
      _jumpToByte(target);
    }
  }

  void _resetWindow(int requested, {bool center = false}) {
    final size = widget.source.size;
    final target = requested.clamp(0, size > 0 ? size - 1 : 0);
    var start = (target - (center ? 128 * 1024 : 0)).clamp(0, size);
    if (widget.rawText) {
      start = alignViewerTextOffset(widget.source, start, widget.encoding);
    }
    _windowStart = start;
    _windowEnd = (start + kMaxIndexedBytes).clamp(0, size);
    if (widget.rawText && _windowEnd < size) {
      _windowEnd = alignViewerTextOffset(
        widget.source,
        _windowEnd,
        widget.encoding,
      );
    }
    _indexedBytes = start;
    _lineOffsets
      ..clear()
      ..add(start);
    _windowDone = false;
    _error = null;
    _pendingTarget = target;
    WidgetsBinding.instance.addPostFrameCallback((_) => _indexMore());
  }

  int _lineIndexOfOffset(int byteOffset) {
    var lo = 0;
    var hi = _lineOffsets.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (_lineOffsets[mid] <= byteOffset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  void _jumpToByte(int requested) {
    final offset = requested.clamp(
      0,
      widget.source.size > 0 ? widget.source.size - 1 : 0,
    );
    if (offset < _windowStart || offset >= _windowEnd) {
      setState(() => _resetWindow(offset, center: true));
      return;
    }
    if (offset >= _indexedBytes && !_windowDone) {
      _pendingTarget = offset;
      return;
    }
    _pendingTarget = null;
    final controller = widget.controller;
    if (controller == null ||
        !controller.hasClients ||
        controller.positions.length != 1) {
      return;
    }
    final target = 4.0 + _lineIndexOfOffset(offset) * _rowExtent;
    controller.jumpTo(target.clamp(0.0, controller.position.maxScrollExtent));
  }

  bool _newline(List<int> bytes, int index) {
    if (_unit == 1) return bytes[index] == 10;
    if (index + _unit > bytes.length) return false;
    final big = widget.encoding.endsWith('be');
    for (var j = 0; j < _unit; j++) {
      if (bytes[index + j] != (j == (big ? _unit - 1 : 0) ? 10 : 0)) {
        return false;
      }
    }
    return true;
  }

  void _indexMore() {
    if (!mounted || _windowDone || _error != null) return;
    try {
      final end = (_indexedBytes + _indexChunk).clamp(0, _windowEnd);
      final bytes = widget.source.readSync(_indexedBytes, end - _indexedBytes);
      var consumed = bytes.length;
      for (var i = 0; i < bytes.length; i += _unit) {
        final next = _indexedBytes + i + _unit;
        final newline = _newline(bytes, i);
        final longLine = next - _lineOffsets.last >= kMaxLineRenderBytes;
        final boundary =
            !widget.rawText ||
            !longLine ||
            alignViewerTextOffset(widget.source, next, widget.encoding) == next;
        if (next <= end && (newline || (longLine && boundary))) {
          _lineOffsets.add(next);
          if (_lineOffsets.length >= _maximumLines) {
            consumed = i + _unit;
            _windowEnd = _indexedBytes + consumed;
            break;
          }
        }
      }
      _indexedBytes += consumed;
      _windowDone = _indexedBytes >= _windowEnd;
    } catch (error) {
      _error = '$error';
      _windowDone = true;
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _pendingTarget;
      if (target != null && (target < _indexedBytes || _windowDone)) {
        _jumpToByte(target);
      }
      if (!_windowDone) _indexMore();
    });
  }

  String _decode(List<int> bytes) => widget.rawText
      ? InternalViewerService.decodeTextForView(
          Uint8List.fromList(bytes),
          encoding: widget.encoding,
        ).text
      : InternalViewerService.renderSafeBytes(
          Uint8List.fromList(bytes),
          binaryMode: widget.binaryMode,
        );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = monoTextStyle(
      13 * widget.fontScale,
      theme.colorScheme.onSurface,
    );
    final dim = style.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontSize: style.fontSize! * .85,
    );
    return Column(
      children: [
        if (_windowStart > 0 || _windowEnd < widget.source.size)
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                onPressed: _windowStart == 0
                    ? null
                    : () => setState(
                        () => _resetWindow(
                          (_windowStart - kMaxIndexedBytes).clamp(
                            0,
                            widget.source.size,
                          ),
                        ),
                      ),
                child: Text(context.commanderTr("Previous text window")),
              ),
              Text(
                context.commanderTr("Bytes {0}–{1} of {2}", [
                  _windowStart,
                  _windowEnd,
                  widget.source.size,
                ]),
                style: dim,
              ),
              TextButton(
                onPressed: !_windowDone || _windowEnd >= widget.source.size
                    ? null
                    : () => setState(() => _resetWindow(_windowEnd)),
                child: Text(context.commanderTr("Next text window")),
              ),
            ],
          ),
        if (!_windowDone) const LinearProgressIndicator(),
        if (_error != null)
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        Expanded(
          child: ListView.builder(
            controller: widget.controller,
            itemCount: _lineOffsets.length,
            itemExtent: _rowExtent,
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            itemBuilder: (context, i) {
              final start = _lineOffsets[i];
              final end = i + 1 < _lineOffsets.length
                  ? _lineOffsets[i + 1]
                  : _indexedBytes;
              final bytes = widget.source.readSync(
                start,
                (end - start).clamp(0, kMaxLineRenderBytes + 4),
              );
              var text = _decode(bytes);
              if (text.endsWith('\n')) {
                text = text.substring(0, text.length - 1);
              }
              if (text.endsWith('\r')) {
                text = text.substring(0, text.length - 1);
              }
              InlineSpan span = TextSpan(text: text);
              final ms = widget.matchStart;
              final me = widget.matchEnd;
              if (ms != null &&
                  me != null &&
                  me > start &&
                  ms < start + bytes.length) {
                final byteStart = (ms - start).clamp(0, bytes.length);
                final byteEnd = (me - start).clamp(byteStart, bytes.length);
                final first = _decode(bytes.sublist(0, byteStart)).length
                    .clamp(0, text.length);
                final last = _decode(bytes.sublist(0, byteEnd)).length
                    .clamp(first, text.length);
                span = TextSpan(
                  children: [
                    TextSpan(text: text.substring(0, first)),
                    TextSpan(
                      text: text.substring(first, last),
                      style: style.copyWith(
                        backgroundColor: theme.colorScheme.tertiaryContainer
                            .withValues(alpha: .9),
                      ),
                    ),
                    TextSpan(text: text.substring(last)),
                  ],
                );
              }
              return Row(
                children: [
                  Text(
                    start
                        .toRadixString(16)
                        .toUpperCase()
                        .padLeft(_offsetDigits, '0'),
                    style: dim,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Text.rich(
                        span,
                        style: style,
                        softWrap: false,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// PDF page panel (pdfx)
// ---------------------------------------------------------------------------

class PdfPagePanel extends StatelessWidget {
  final PdfController controller;

  const PdfPagePanel({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Expanded(
          child: PdfView(
            controller: controller,
            scrollDirection: Axis.vertical,
            pageSnapping: false,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            border: Border(top: BorderSide(color: theme.dividerColor)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.first_page, size: 20),
                onPressed: () => controller.jumpToPage(1),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 20),
                onPressed: () {
                  final current = controller.page;
                  if (current > 1) {
                    controller.jumpToPage(current - 1);
                  }
                },
              ),
              PdfPageNumber(
                controller: controller,
                builder: (_, __, page, total) => Text(
                  '$page / $total',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, size: 20),
                onPressed: () {
                  final current = controller.page;
                  final pages = controller.pagesCount;
                  if (pages == null || current < pages) {
                    controller.jumpToPage(current + 1);
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.last_page, size: 20),
                onPressed: () {
                  final pages = controller.pagesCount;
                  if (pages != null && pages > 0) controller.jumpToPage(pages);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
