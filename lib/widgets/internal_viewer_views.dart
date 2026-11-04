// lib/widgets/internal_viewer_views.dart
//
// Render-mode widgets used by the F3 internal viewer dialog. Each widget is
// parameterised so it renders pure data (lines/bytes) with optional search
// highlights, and stays independent of dialog state.


import 'package:flutter/material.dart';

import '../l10n/page_navigation_strings.dart';
import 'package:pdfx/pdfx.dart';

import '../l10n/app_localizations.dart';
import '../services/file_bytes_loader.dart';
import '../services/internal_viewer_service.dart';

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
      return Center(child: Text(AppLocalizations.of(context)?.emptyFile ?? 'Empty file'));
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
            backgroundColor:
                theme.colorScheme.tertiaryContainer.withValues(alpha: 0.9),
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

/// Bytes scanned for line offsets (cap keeps UI responsive). Beyond the cap,
/// remaining bytes require the Hex mode.
const int kMaxIndexedBytes = 64 * 1024 * 1024;
const int kMaxLineRenderBytes = 8 * 1024;

/// Line-indexed view over a [ViewBytesSource]: lines are discovered by scans
/// ([kMaxIndexedBytes] cap) and rendered either as decoded text ([rawText])
/// or as safe ASCII/binary ([binaryMode]). Column one shows the byte offset
/// of each line like the hex view, which keeps huge files orientable.
class StreamingSafeView extends StatefulWidget {
  final ViewBytesSource source;
  final bool binaryMode;
  final bool rawText;
  final double fontScale;
  final ScrollController? controller;

  /// Active byte-search match run (absolute offsets), or null.
  final int? matchStart;
  final int? matchEnd;

  /// When this byte offset changes (non-null) the view jumps to the line
  /// containing it — used by goto/match navigation from the dialog.
  final int? scrollToByte;

  const StreamingSafeView({
    super.key,
    required this.source,
    required this.fontScale,
    this.controller,
    this.binaryMode = false,
    this.rawText = false,
    this.matchStart,
    this.matchEnd,
    this.scrollToByte,
  });

  @override
  State<StreamingSafeView> createState() => _StreamingSafeViewState();
}

class _StreamingSafeViewState extends State<StreamingSafeView> {
  final List<int> _lineOffsets = [0];
  int _indexedBytes = 0;
  bool _fullyIndexed = false;
  int? _lastHandledScrollTo;

  /// Bytes indexed per frame; keeps a 64 MB scan from freezing the UI.
  static const int _indexChunk = 2 * 1024 * 1024;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _indexMore());
  }

  @override
  void didUpdateWidget(StreamingSafeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.source, widget.source)) {
      _lineOffsets
        ..clear()
        ..add(0);
      _indexedBytes = 0;
      _fullyIndexed = false;
      _lastHandledScrollTo = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _indexMore());
      return;
    }
    final target = widget.scrollToByte;
    if (target != null && target != _lastHandledScrollTo) {
      _jumpToByte(target);
    }
  }

  void _jumpToByte(int byteOffset) {
    _lastHandledScrollTo = byteOffset;
    final line = _lineIndexOfOffset(byteOffset);
    final controller = widget.controller;
    if (controller == null || !controller.hasClients) return;
    final positions = controller.positions;
    if (positions.length != 1) return;
    final position = positions.first;
    final target = 4.0 + line * _rowExtent;
    position.jumpTo(target.clamp(0.0, position.maxScrollExtent));
  }

  double get _fontSize => 13.0 * widget.fontScale;
  double get _rowExtent => _fontSize * 1.5;

  /// Offset column width: 8 digits up to 4 GiB, wider beyond that.
  int get _offsetDigits {
    final maxOffset = widget.source.size <= 0 ? 0 : widget.source.size - 1;
    final digits = maxOffset.toRadixString(16).length;
    return digits < 8 ? 8 : digits;
  }

  int _lineIndexOfOffset(int byteOffset) {
    // Binary search: last line whose start <= byteOffset.
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

  void _indexMore() {
    if (!mounted) return;
    final size = widget.source.size;
    final cap = size < kMaxIndexedBytes ? size : kMaxIndexedBytes;
    if (_indexedBytes < cap) {
      final end = (_indexedBytes + _indexChunk) > cap
          ? cap
          : _indexedBytes + _indexChunk;
      if (end > _indexedBytes) {
        final chunk =
            widget.source.readSync(_indexedBytes, end - _indexedBytes);
        for (var i = 0; i < chunk.length; i++) {
          if (chunk[i] == 0x0A) {
            _lineOffsets.add(_indexedBytes + i + 1);
          }
        }
        _indexedBytes = end;
      }
    }
    _fullyIndexed = _indexedBytes >= size;
    if (mounted) setState(() {});
    if (!_fullyIndexed && _indexedBytes < cap) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _indexMore());
    }
  }

  String _renderLine(int line) {
    final start = _lineOffsets[line];
    final lineEnd = line + 1 < _lineOffsets.length
        ? _lineOffsets[line + 1]
        : widget.source.size;
    var readEnd = (start + kMaxLineRenderBytes) < lineEnd
        ? start + kMaxLineRenderBytes
        : lineEnd;
    if (readEnd < start) readEnd = start;
    final truncated = readEnd < lineEnd;
    final bytes = widget.source.readSync(start, readEnd - start);
    var text = widget.rawText
        ? InternalViewerService.decodeTextForView(bytes).text
        : InternalViewerService.renderSafeBytes(
            bytes,
            binaryMode: widget.binaryMode,
          );
    // The slice includes the terminating LF (so CRLF collapses correctly);
    // strip it for single-row rendering.
    if (text.endsWith('\n')) text = text.substring(0, text.length - 1);
    if (text.endsWith('\r')) text = text.substring(0, text.length - 1);
    return truncated ? '$text…' : text;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fontSize = 13.0 * widget.fontScale;
    final rowExtent = fontSize * 1.5;
    final style = monoTextStyle(fontSize, theme.colorScheme.onSurface);
    final dimStyle = style.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontSize: fontSize * 0.85,
      height: 1.2,
    );

    final pendingRows = _fullyIndexed ? 0 : 1;
    final rows = _lineOffsets.length + pendingRows;

    return ListView.builder(
      controller: widget.controller,
      itemCount: rows,
      itemExtent: rowExtent,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      itemBuilder: (context, i) {
        if (i >= _lineOffsets.length) {
          final msg = widget.source.size > kMaxIndexedBytes
              ? '(indexed to ${kMaxIndexedBytes ~/ (1024 * 1024)} MB — use Hex mode for deeper offsets)'
              : '(loading…)';
          return Row(
            children: [
              Text('…', style: dimStyle),
              const SizedBox(width: 8),
              Expanded(child: Text(msg, style: dimStyle, maxLines: 1)),
            ],
          );
        }
        final lineStart = _lineOffsets[i];
        final text = _renderLine(i);

        InlineSpan span = TextSpan(text: text);
        final ms = widget.matchStart;
        final me = widget.matchEnd;
        if (ms != null &&
            me != null &&
            me > lineStart &&
            ms < lineStart + text.length) {
          final s = (ms - lineStart).clamp(0, text.length);
          final e = (me - lineStart).clamp(s, text.length);
          if (e > s) {
            span = TextSpan(children: [
              TextSpan(text: text.substring(0, s)),
              TextSpan(
                text: text.substring(s, e),
                style: style.copyWith(
                  backgroundColor: theme.colorScheme.tertiaryContainer
                      .withValues(alpha: 0.9),
                ),
              ),
              TextSpan(text: text.substring(e)),
            ]);
          }
        }

        return Row(
          children: [
            Text(
              lineStart
                  .toRadixString(16)
                  .toUpperCase()
                  .padLeft(_offsetDigits, '0'),
              style: dimStyle,
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
                tooltip: PageNavigationStrings(context).text('first'),
                icon: const Icon(Icons.first_page, size: 20),
                onPressed: () => controller.jumpToPage(1),
              ),
              IconButton(
                tooltip: PageNavigationStrings(context).text('previous'),
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
                tooltip: PageNavigationStrings(context).text('next'),
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
                tooltip: PageNavigationStrings(context).text('last'),
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
