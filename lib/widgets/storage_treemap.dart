import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../models/storage_analysis.dart';
import '../utils/formatters.dart';
import '../utils/storage_treemap_layout.dart';

/// Stable extension colors shared by the treemap and its file-type legend.
///
/// This deliberately avoids String.hashCode, whose value need not be stable
/// between platforms or application runs.
Color storageExtensionColor(
  String extension, {
  Brightness brightness = Brightness.light,
}) {
  final normalized = extension.toLowerCase().replaceFirst(RegExp(r'^\.'), '');
  if (normalized.isEmpty) {
    return brightness == Brightness.dark
        ? const Color(0xff64778b)
        : const Color(0xff8a9caf);
  }
  var hash = 0;
  for (final code in normalized.codeUnits) {
    hash = (hash * 31 + code) & 0x7fffffff;
  }
  return HSLColor.fromAHSL(
    1,
    (hash * 137.508) % 360,
    0.57,
    brightness == Brightness.dark ? 0.42 : 0.58,
  ).toColor();
}

/// A bounded, interactive view of known file sizes within [root].
///
/// Click/tap selects; double-click or long-press a folder drills into it.
/// Every tile also exposes semantic selection and folder-opening actions.
/// The surrounding analyzer supplies a keyboard-accessible folder table,
/// including zero-byte and unknown-size items that cannot have map area.
class StorageTreemap extends StatefulWidget {
  const StorageTreemap({
    super.key,
    required this.root,
    this.selected,
    required this.onSelected,
    required this.onOpenFolder,
    this.aggregateLabel,
    this.emptyLabel = '',
  });

  final StorageNode root;
  final StorageNode? selected;
  final ValueChanged<StorageNode> onSelected;
  final ValueChanged<StorageNode> onOpenFolder;
  final String Function(int count)? aggregateLabel;
  final String emptyLabel;

  @override
  State<StorageTreemap> createState() => _StorageTreemapState();
}

class _StorageTreemapState extends State<StorageTreemap> {
  List<StorageTreemapTile> _tiles = const [];
  StorageNode? _layoutRoot;
  Size? _layoutSize;
  double? _headerHeight;
  StorageTreemapTile? _hovered;
  Offset _hoverPosition = Offset.zero;
  Offset? _doubleTapPosition;

  @override
  void didUpdateWidget(StorageTreemap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.root, widget.root)) {
      _layoutRoot = null;
      _hovered = null;
      _doubleTapPosition = null;
    }
  }

  void _ensureLayout(Size size, double headerHeight) {
    if (identical(_layoutRoot, widget.root) &&
        _layoutSize == size &&
        _headerHeight == headerHeight) {
      return;
    }
    _tiles = layoutStorageTreemap(
      widget.root,
      size,
      folderHeaderHeight: headerHeight,
    );
    _layoutRoot = widget.root;
    _layoutSize = size;
    _headerHeight = headerHeight;
    _hovered = null;
  }

  StorageTreemapTile? _hitTest(Offset position) {
    // Children are painted after parents, so the deepest visible tile wins.
    for (final tile in _tiles.reversed) {
      if (tile.rect.contains(position)) return tile;
    }
    return null;
  }

  void _selectAt(Offset position) {
    final tile = _hitTest(position);
    if (tile != null) widget.onSelected(tile.node);
  }

  void _openAt(Offset? position) {
    if (position == null) return;
    final tile = _hitTest(position);
    if (tile != null && tile.node.isFolder) {
      widget.onOpenFolder(tile.node);
    }
  }

  String _aggregateName(int count) =>
      widget.aggregateLabel?.call(count) ?? '$count …';

  String _tileDescription(StorageTreemapTile tile) {
    final prefix = tile.isAggregate
        ? '${_aggregateName(tile.aggregateCount)}\n'
        : '';
    return '$prefix${tile.node.path}\n${formatBytes(tile.bytes)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textDirection = Directionality.of(context);
    final fontSize = MediaQuery.textScalerOf(context).scale(11);
    final headerHeight = math.max(22.0, fontSize * 1.5 + 6);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(
          constraints.hasBoundedWidth ? constraints.maxWidth : 400,
          constraints.hasBoundedHeight ? constraints.maxHeight : 300,
        );
        _ensureLayout(size, headerHeight);
        if (_tiles.isEmpty) {
          return SizedBox.fromSize(
            size: size,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(widget.emptyLabel, textAlign: TextAlign.center),
              ),
            ),
          );
        }
        final hover = _hovered;
        return MouseRegion(
          cursor: hover != null
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onHover: (event) {
            final tile = _hitTest(event.localPosition);
            if (!identical(tile, _hovered)) {
              setState(() {
                _hovered = tile;
                _hoverPosition = event.localPosition;
              });
            }
          },
          onExit: (_) {
            if (_hovered != null) setState(() => _hovered = null);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTapDown: (details) => _selectAt(details.localPosition),
            onDoubleTapDown: (details) {
              _doubleTapPosition = details.localPosition;
            },
            onDoubleTap: () => _openAt(_doubleTapPosition),
            onLongPressStart: (details) => _openAt(details.localPosition),
            child: SizedBox.fromSize(
              size: size,
              child: ClipRect(
                child: Stack(
                  children: [
                    RepaintBoundary(
                      child: CustomPaint(
                        size: size,
                        painter: _TreemapPainter(
                          tiles: _tiles,
                          selected: widget.selected,
                          hovered: hover,
                          colors: theme.colorScheme,
                          textDirection: textDirection,
                          fontSize: fontSize,
                          aggregateName:
                              widget.aggregateLabel ?? _aggregateName,
                          description: _tileDescription,
                          onSelected: widget.onSelected,
                          onOpenFolder: widget.onOpenFolder,
                        ),
                      ),
                    ),
                    if (hover != null && size.width >= 100 && size.height >= 80)
                      _hoverCard(context, hover, size),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _hoverCard(BuildContext context, StorageTreemapTile tile, Size size) {
    final colors = Theme.of(context).colorScheme;
    final width = math.min(310.0, size.width - 16);
    return Positioned(
      left: (_hoverPosition.dx + 12)
          .clamp(8.0, size.width - width - 8)
          .toDouble(),
      top: (_hoverPosition.dy + 18)
          .clamp(8.0, math.max(8.0, size.height - 94))
          .toDouble(),
      width: width,
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: Material(
            elevation: 4,
            color: colors.inverseSurface,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text(
                _tileDescription(tile),
                style: TextStyle(color: colors.onInverseSurface, fontSize: 12),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TreemapPainter extends CustomPainter {
  _TreemapPainter({
    required this.tiles,
    required this.selected,
    required this.hovered,
    required this.colors,
    required this.textDirection,
    required this.fontSize,
    required this.aggregateName,
    required this.description,
    required this.onSelected,
    required this.onOpenFolder,
  });

  final List<StorageTreemapTile> tiles;
  final StorageNode? selected;
  final StorageTreemapTile? hovered;
  final ColorScheme colors;
  final TextDirection textDirection;
  final double fontSize;
  final String Function(int) aggregateName;
  final String Function(StorageTreemapTile) description;
  final ValueChanged<StorageNode> onSelected;
  final ValueChanged<StorageNode> onOpenFolder;

  bool _isSelected(StorageTreemapTile tile) =>
      selected != null &&
      !tile.isAggregate &&
      (identical(tile.node, selected) || tile.node.path == selected!.path);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = colors.surface);
    for (final tile in tiles) {
      final rect = tile.rect.deflate(0.6);
      if (rect.isEmpty) continue;
      final color = tile.isAggregate
          ? colors.surfaceContainerHighest
          : tile.node.isFolder
          ? Color.lerp(colors.surfaceContainerHighest, colors.primary, 0.12)!
          : storageExtensionColor(
              tile.node.item.extension,
              brightness: colors.brightness,
            );
      canvas.drawRect(rect, Paint()..color = color);
      if (tile.isAggregate) {
        _paintAggregatePattern(canvas, rect);
      }
      final foreground = tile.node.isFolder || tile.isAggregate
          ? colors.onSurface
          : color.computeLuminance() > 0.18
          ? const Color(0xff101b25)
          : Colors.white;
      _paintLabel(canvas, tile, rect, foreground);
    }

    // Paint outlines last so the selected folder also encloses its children.
    for (final tile in tiles) {
      if (!_isSelected(tile) && !identical(tile, hovered)) continue;
      final rect = tile.rect.deflate(1.5);
      if (rect.isEmpty) continue;
      canvas.drawRect(
        rect,
        Paint()
          ..color = _isSelected(tile) ? colors.onSurface : colors.outline
          ..style = PaintingStyle.stroke
          ..strokeWidth = _isSelected(tile) ? 3 : 2,
      );
      if (_isSelected(tile) && rect.shortestSide > 9) {
        canvas.drawRect(
          rect.deflate(2),
          Paint()
            ..color = colors.surface
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
    }
    canvas.restore();
  }

  void _paintAggregatePattern(Canvas canvas, Rect rect) {
    canvas.save();
    canvas.clipRect(rect);
    final paint = Paint()
      ..color = colors.outlineVariant
      ..strokeWidth = 1;
    for (var x = rect.left - rect.height; x < rect.right; x += 10) {
      canvas.drawLine(
        Offset(x, rect.bottom),
        Offset(x + rect.height, rect.top),
        paint,
      );
    }
    canvas.restore();
  }

  void _paintLabel(
    Canvas canvas,
    StorageTreemapTile tile,
    Rect rect,
    Color color,
  ) {
    final labelRect = tile.isExpanded
        ? Rect.fromLTRB(rect.left, rect.top, rect.right, tile.contentRect!.top)
        : rect;
    if (labelRect.width < 42 || labelRect.height < fontSize + 6) return;
    final prefix = tile.node.isFolder && !tile.isAggregate
        ? (tile.isExpanded ? '▾ ' : '▸ ')
        : '';
    final name = tile.isAggregate
        ? aggregateName(tile.aggregateCount)
        : '$prefix${tile.node.name}';
    final label = TextPainter(
      text: TextSpan(
        text: name,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: tile.node.isFolder ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      textDirection: textDirection,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(0.0, labelRect.width - 12));
    canvas.save();
    canvas.clipRect(labelRect);
    label.paint(canvas, labelRect.topLeft + const Offset(6, 4));
    if (!tile.isExpanded && labelRect.height >= fontSize * 2.6 + 8) {
      final bytes = TextPainter(
        text: TextSpan(
          text: formatBytes(tile.bytes),
          style: TextStyle(color: color, fontSize: fontSize * 0.9),
        ),
        textDirection: textDirection,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: math.max(0.0, labelRect.width - 12));
      bytes.paint(canvas, labelRect.topLeft + Offset(6, fontSize * 1.4 + 6));
      bytes.dispose();
    }
    canvas.restore();
    label.dispose();
  }

  @override
  SemanticsBuilderCallback get semanticsBuilder =>
      (size) => [
        for (final tile in tiles)
          if (tile.rect.width >= 20 && tile.rect.height >= 20)
            CustomPainterSemantics(
              rect: tile.isExpanded
                  ? Rect.fromLTRB(
                      tile.rect.left,
                      tile.rect.top,
                      tile.rect.right,
                      tile.contentRect!.top,
                    )
                  : tile.rect,
              properties: SemanticsProperties(
                label: description(tile),
                textDirection: textDirection,
                button: true,
                selected: _isSelected(tile),
                onTap: () => onSelected(tile.node),
                onLongPress: tile.node.isFolder
                    ? () => onOpenFolder(tile.node)
                    : null,
              ),
            ),
      ];

  @override
  bool shouldRepaint(_TreemapPainter oldDelegate) =>
      !identical(oldDelegate.tiles, tiles) ||
      oldDelegate.selected != selected ||
      !identical(oldDelegate.hovered, hovered) ||
      oldDelegate.colors != colors ||
      oldDelegate.textDirection != textDirection ||
      oldDelegate.fontSize != fontSize ||
      oldDelegate.aggregateName != aggregateName;

  @override
  bool shouldRebuildSemantics(_TreemapPainter oldDelegate) =>
      shouldRepaint(oldDelegate) ||
      oldDelegate.onSelected != onSelected ||
      oldDelegate.onOpenFolder != onOpenFolder;
}
