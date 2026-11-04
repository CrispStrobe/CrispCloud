// lib/widgets/hex_viewer.dart
//
// Virtualized hex dump widget for the F3 internal viewer.
// Renders offset + hex + ASCII columns over a [ViewBytesSource] which can be
// fully in-memory (web/remote/small files) or lazily streamed from a local
// file via RandomAccessFile windows, so multi-GB files stay viewable.
//
// Rows are uniformly sized (monospace + itemExtent), which makes byte ↔ pixel
// math exact: goto-offset and match navigation jump straight to a row.

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/file_bytes_loader.dart';

/// Base hex font size before zoom scaling.
const double kHexBaseFontSize = 13.0;

/// Uniform row height for hex rows at a given zoom scale. Kept here so the
/// dialog can compute scroll offsets without reaching into the widget.
double hexRowExtent(double fontScale) => kHexBaseFontSize * fontScale * 1.6 + 6;

/// Characters per hex row: offset(8) + gap(2) + hex(n*3-1) + gap(2) + ascii(n).
int hexRowCharCount(int bytesPerLine, {int offsetDigits = 8}) =>
    offsetDigits + 2 + (bytesPerLine * 3 - 1) + 2 + bytesPerLine;

/// Human-readable multi-base description of a byte value for the status bar.
String byteStatusText(int value, int offset) {
  final hex = value.toRadixString(16).toUpperCase().padLeft(2, '0');
  final bin = value.toRadixString(2).padLeft(8, '0');
  final glyph =
      (value >= 0x20 && value < 0x7F) ? String.fromCharCode(value) : '·';
  return '0x${offset.toRadixString(16).toUpperCase().padLeft(8, '0')}'
      ' · 0x$hex · $value · $bin · "$glyph"';
}

class HexViewer extends StatefulWidget {
  final ViewBytesSource source;

  /// Bytes displayed per row (16 canonical; 8 or 32 also supported).
  final int bytesPerLine;

  /// Font zoom multiplier (1.0 = [kHexBaseFontSize]).
  final double fontScale;

  /// Absolute byte offset of the user-selected byte, or null.
  final int? selectedByte;

  /// Byte run of the active search match (highlights covered bytes).
  final int? highlightRangeStart;
  final int? highlightRangeEnd;

  /// Tap feedback: absolute byte offset of the tapped byte.
  final void Function(int byteOffset)? onByteTapped;

  /// Optional shared vertical controller (enables goto-offset navigation).
  final ScrollController? controller;

  const HexViewer({
    super.key,
    required this.source,
    required this.bytesPerLine,
    this.fontScale = 1.0,
    this.selectedByte,
    this.highlightRangeStart,
    this.highlightRangeEnd,
    this.onByteTapped,
    this.controller,
  });

  @override
  State<HexViewer> createState() => _HexViewerState();
}

class _HexViewerState extends State<HexViewer> {
  static const _listPadding = EdgeInsets.symmetric(vertical: 4, horizontal: 8);

  double _charWidth = 9.0;
  String? _charWidthFp;

  double get _fontSize => kHexBaseFontSize * widget.fontScale;
  double get _rowExtent => hexRowExtent(widget.fontScale);

  /// Offset column width: 8 digits up to 4 GiB, wider beyond that.
  int get _offsetDigits {
    final maxOffset = widget.source.size <= 0 ? 0 : widget.source.size - 1;
    final digits = maxOffset.toRadixString(16).length;
    return digits < 8 ? 8 : digits;
  }

  int get _offsetChars => _offsetDigits + 2; // offset + two spaces

  int get _lineCount => widget.source.size == 0
      ? 1
      : (widget.source.size / widget.bytesPerLine).ceil();

  int get _bpl => widget.bytesPerLine;

  TextStyle _monoStyle(BuildContext context) {
    final theme = Theme.of(context);
    return TextStyle(
      fontSize: _fontSize,
      height: _rowExtent / _fontSize, // fills itemExtent exactly
      letterSpacing: 0,
      fontFamily: 'AppMono',
      fontFamilyFallback: const [
        'Menlo',
        'Consolas',
        'DejaVu Sans Mono',
        'monospace',
      ],
      fontFeatures: const [FontFeature.tabularFigures()],
      color: theme.colorScheme.onSurface,
      fontWeight: FontWeight.w400,
    );
  }

  void _measureChars(BuildContext context) {
    final fp = '${widget.fontScale}@$_bpl@$_offsetDigits';
    if (_charWidthFp == fp) return;
    final tp = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: 'F' * hexRowCharCount(_bpl, offsetDigits: _offsetDigits),
        style: _monoStyle(context),
      )
      ..layout(maxWidth: double.infinity);
    _charWidth = tp.width / hexRowCharCount(_bpl, offsetDigits: _offsetDigits);
    _charWidthFp = fp;
  }

  /// Byte index (0..bpl-1) for a tap at row-local [x] (already including the
  /// horizontal list padding), or null when the tap is outside the hex/ASCII
  /// column area.
  int? _byteIndexAtX(double x, BuildContext _) {
    final charIdx = (x / _charWidth).floor() - _offsetChars;
    if (charIdx < 0) return null;
    final hexLen = _bpl * 3 - 1;
    if (charIdx < hexLen) {
      return (charIdx ~/ 3).clamp(0, _bpl - 1);
    }
    final asciiBand = charIdx - hexLen - 2; // gap of 2 columns
    if (asciiBand >= 0 && asciiBand < _bpl) return asciiBand;
    return null;
  }

  // ---- Highlight casts -----------------------------------------------------

  TextStyle? _decoStyleFor(int byteIndex, int rowStart) {
    final sel = widget.selectedByte;
    final hs = widget.highlightRangeStart;
    final he = widget.highlightRangeEnd;
    final abs = rowStart + byteIndex;

    final isSel = sel != null && sel >= rowStart && sel < rowStart + _bpl
        ? sel == abs
        : false;
    final inMatch = hs != null && he != null && abs >= hs && abs < he;

    if (!isSel && !inMatch) return null;
    final theme = Theme.of(context);
    if (isSel) {
      return TextStyle(
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.35));
    }
    return TextStyle(
        backgroundColor:
            theme.colorScheme.tertiaryContainer.withValues(alpha: 0.7));
  }

  @override
  Widget build(BuildContext context) {
    _measureChars(context);

    if (widget.source.size == 0) {
      return const Center(child: Text('(empty file)'));
    }

    final theme = Theme.of(context);
    final baseStyle = _monoStyle(context);
    final dimStyle = baseStyle.copyWith(
        color: theme.colorScheme.onSurfaceVariant, fontSize: _fontSize * 0.9);
    final rowWidth =
        hexRowCharCount(_bpl, offsetDigits: _offsetDigits) * _charWidth + 32;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: rowWidth,
        child: ListView.builder(
          controller: widget.controller,
          itemCount: _lineCount,
          itemExtent: _rowExtent,
          padding: _listPadding,
          itemBuilder: (context, line) {
            final rowStart = line * _bpl;
            final bytes = widget.source.readSync(rowStart, _bpl);

            final offsetText = rowStart
                .toRadixString(16)
                .toUpperCase()
                .padLeft(_offsetDigits, '0');

            // Hex column chars and ASCII column chars (padded for alignment).
            final hexChildren = <TextSpan>[];
            final asciiChildren = <TextSpan>[];
            for (var i = 0; i < _bpl; i++) {
              if (i < bytes.length) {
                final hx =
                    bytes[i].toRadixString(16).toUpperCase().padLeft(2, '0');
                final asciiCh = (bytes[i] >= 0x20 && bytes[i] < 0x7F)
                    ? String.fromCharCode(bytes[i])
                    : '.';
                final deco = _decoStyleFor(i, rowStart);
                if (i > 0) hexChildren.add(const TextSpan(text: ' '));
                if (deco == null) {
                  hexChildren.add(TextSpan(text: hx));
                  asciiChildren.add(TextSpan(text: asciiCh));
                } else {
                  hexChildren.add(TextSpan(text: hx, style: deco));
                  asciiChildren.add(TextSpan(text: asciiCh, style: deco));
                }
              } else {
                if (i > 0) hexChildren.add(const TextSpan(text: ' '));
                hexChildren.add(const TextSpan(text: '  '));
                asciiChildren.add(const TextSpan(text: ' '));
              }
            }

            final children = <InlineSpan>[
              TextSpan(text: offsetText, style: dimStyle),
              const TextSpan(text: '  '),
              ...hexChildren,
              const TextSpan(text: '  '),
              ...asciiChildren,
            ];

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                final byteIdx =
                    _byteIndexAtX(details.localPosition.dx, context);
                if (byteIdx != null) {
                  widget.onByteTapped?.call(rowStart + byteIdx);
                }
              },
              child: RichText(
                text: TextSpan(style: baseStyle, children: children),
                softWrap: false,
                maxLines: 1,
                overflow: TextOverflow.visible,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Computes the byte covered by a hex pair at [i] over the row's byte range.
/// (Pure helper kept next to the viewer for widget tests.)
int hexPairByteAt(Uint8List bytes, int i) => i < bytes.length ? bytes[i] : 0;
