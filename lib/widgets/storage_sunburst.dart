import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../models/storage_analysis.dart';
import '../utils/formatters.dart';
import '../utils/storage_sunburst_layout.dart';
import 'storage_treemap.dart';

/// Interactive folder rings sharing the analyzer's selection and navigation.
///
/// Angular span compares known bytes; each outward ring adds one folder level.
/// The accessible folder and largest-file lists remain the full alternative to
/// the bounded drawing, including empty and unknown-size entries.
class StorageSunburst extends StatefulWidget {
  const StorageSunburst({
    super.key,
    required this.root,
    this.selected,
    required this.onSelected,
    required this.onOpenFolder,
    this.onOpenParent,
    this.onInspectGroup,
    required this.aggregateLabel,
    required this.shareLabel,
    required this.centerLabel,
    required this.emptyLabel,
  });

  final StorageNode root;
  final StorageNode? selected;
  final ValueChanged<StorageNode> onSelected;
  final ValueChanged<StorageNode> onOpenFolder;
  final VoidCallback? onOpenParent;
  final ValueChanged<StorageNode>? onInspectGroup;
  final String Function(int count) aggregateLabel;
  final String Function(String percent) shareLabel;
  final String centerLabel;
  final String emptyLabel;

  @override
  State<StorageSunburst> createState() => _StorageSunburstState();
}

class _StorageSunburstState extends State<StorageSunburst> {
  StorageSunburstLayout? _layout;
  StorageNode? _layoutRoot;
  Size? _layoutSize;
  StorageSunburstSegment? _hovered;
  Offset _hoverPosition = Offset.zero;
  Offset? _doubleTapPosition;

  void _ensureLayout(Size size) {
    if (identical(_layoutRoot, widget.root) && _layoutSize == size) return;
    _layout = layoutStorageSunburst(widget.root, size);
    _layoutRoot = widget.root;
    _layoutSize = size;
    _hovered = null;
    _doubleTapPosition = null;
  }

  void _select(StorageSunburstSegment segment) {
    if (segment.isAggregate && widget.onInspectGroup != null) {
      widget.onInspectGroup!(segment.node);
    } else {
      widget.onSelected(segment.node);
    }
  }

  void _openAt(Offset? position) {
    if (position == null) return;
    final segment = _layout?.hitTest(position);
    if (segment == null) return;
    if (segment.isAggregate && widget.onInspectGroup != null) {
      widget.onInspectGroup!(segment.node);
    } else if (segment.node.isFolder) {
      widget.onOpenFolder(segment.node);
    }
  }

  String _description(StorageSunburstSegment segment) {
    final title = segment.isAggregate
        ? '${widget.aggregateLabel(segment.aggregateCount)}\n${segment.node.path}'
        : segment.node.path;
    final percent = widget.root.bytes <= 0
        ? '0.0'
        : (segment.bytes / widget.root.bytes * 100)
              .clamp(0, 100)
              .toStringAsFixed(1);
    return '$title\n${formatBytes(segment.bytes)} · ${widget.shareLabel(percent)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(
          constraints.hasBoundedWidth ? constraints.maxWidth : 400,
          constraints.hasBoundedHeight ? constraints.maxHeight : 400,
        );
        _ensureLayout(size);
        final layout = _layout!;
        if (layout.segments.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(widget.emptyLabel, textAlign: TextAlign.center),
            ),
          );
        }
        final hover = _hovered;
        return MouseRegion(
          cursor: hover == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          onHover: (event) {
            final segment = layout.hitTest(event.localPosition);
            if (!identical(segment, _hovered)) {
              setState(() {
                _hovered = segment;
                _hoverPosition = event.localPosition;
              });
            }
          },
          onExit: (_) {
            if (_hovered != null) setState(() => _hovered = null);
          },
          child: SizedBox.fromSize(
            size: size,
            child: ClipRect(
              child: Stack(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    excludeFromSemantics: true,
                    onTapUp: (details) {
                      final segment = layout.hitTest(details.localPosition);
                      if (segment != null) _select(segment);
                    },
                    onDoubleTapDown: (details) =>
                        _doubleTapPosition = details.localPosition,
                    onDoubleTap: () => _openAt(_doubleTapPosition),
                    onLongPressStart: (details) =>
                        _openAt(details.localPosition),
                    child: RepaintBoundary(
                      child: CustomPaint(
                        size: size,
                        painter: _SunburstPainter(
                          layout: layout,
                          selected: widget.selected,
                          hovered: hover,
                          colors: theme.colorScheme,
                          textStyle:
                              theme.textTheme.bodySmall ?? const TextStyle(),
                          fontSize: MediaQuery.textScalerOf(context).scale(11),
                          direction: Directionality.of(context),
                          aggregateLabel: widget.aggregateLabel,
                          description: _description,
                          onSelected: _select,
                          onOpenFolder: widget.onOpenFolder,
                        ),
                      ),
                    ),
                  ),
                  _centerButton(layout, theme),
                  if (hover != null && size.width >= 160 && size.height >= 100)
                    _hoverCard(hover, size, theme.colorScheme),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _centerButton(StorageSunburstLayout layout, ThemeData theme) {
    final diameter = math.max(0.0, layout.holeRadius * 2 - 8);
    final sizeText =
        '${formatBytes(widget.root.bytes)}${widget.root.isComplete ? '' : ' + ?'}';
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.4;
    return Positioned(
      left: layout.center.dx - diameter / 2,
      top: layout.center.dy - diameter / 2,
      width: diameter,
      height: diameter,
      child: Tooltip(
        message: widget.centerLabel,
        child: Semantics(
          button: true,
          label: '${widget.centerLabel}\n${widget.root.path}\n$sizeText',
          excludeSemantics: true,
          onTap: widget.onOpenParent ?? () => widget.onSelected(widget.root),
          child: Material(
            color: theme.colorScheme.surfaceContainerLow,
            shape: CircleBorder(
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap:
                  widget.onOpenParent ?? () => widget.onSelected(widget.root),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (diameter >= 42)
                      Icon(
                        widget.onOpenParent == null
                            ? Icons.folder_outlined
                            : Icons.arrow_upward,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                    if (diameter >= 100 && !largeText) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.root.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium,
                      ),
                      Text(
                        sizeText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _hoverCard(
    StorageSunburstSegment segment,
    Size size,
    ColorScheme colors,
  ) {
    final width = math.min(320.0, size.width - 16);
    return Positioned(
      left: (_hoverPosition.dx + 14)
          .clamp(8.0, size.width - width - 8)
          .toDouble(),
      top: (_hoverPosition.dy + 18)
          .clamp(8.0, math.max(8.0, size.height - 100))
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
                _description(segment),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.onInverseSurface, fontSize: 12),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SunburstPainter extends CustomPainter {
  _SunburstPainter({
    required this.layout,
    required this.selected,
    required this.hovered,
    required this.colors,
    required this.textStyle,
    required this.fontSize,
    required this.direction,
    required this.aggregateLabel,
    required this.description,
    required this.onSelected,
    required this.onOpenFolder,
  });

  final StorageSunburstLayout layout;
  final StorageNode? selected;
  final StorageSunburstSegment? hovered;
  final ColorScheme colors;
  final TextStyle textStyle;
  final double fontSize;
  final TextDirection direction;
  final String Function(int) aggregateLabel;
  final String Function(StorageSunburstSegment) description;
  final ValueChanged<StorageSunburstSegment> onSelected;
  final ValueChanged<StorageNode> onOpenFolder;

  bool _selected(StorageSunburstSegment segment) =>
      !segment.isAggregate && identical(segment.node, selected);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final segment in layout.segments) {
      final path = segment.path(layout.center);
      final color = segment.isAggregate
          ? colors.surfaceContainerHighest
          : segment.node.isFolder
          ? Color.lerp(
              colors.surfaceContainerHighest,
              colors.primary,
              0.18 + segment.depth * 0.06,
            )!
          : storageExtensionColor(
              segment.node.item.extension,
              brightness: colors.brightness,
            );
      canvas.drawPath(path, Paint()..color = color);
      if (segment.isAggregate) {
        canvas.save();
        canvas.clipPath(path);
        final hatch = Paint()
          ..color = colors.outlineVariant
          ..strokeWidth = 1;
        final bounds = path.getBounds();
        for (var x = bounds.left - bounds.height; x < bounds.right; x += 9) {
          canvas.drawLine(
            Offset(x, bounds.bottom),
            Offset(x + bounds.height, bounds.top),
            hatch,
          );
        }
        canvas.restore();
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = colors.surface
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3,
      );
      final foreground = segment.isAggregate || segment.node.isFolder
          ? colors.onSurface
          : color.computeLuminance() > 0.18
          ? const Color(0xff101b25)
          : Colors.white;
      _label(canvas, segment, path, foreground);
    }
    for (final segment in layout.segments) {
      if (!_selected(segment) && !identical(segment, hovered)) continue;
      final path = segment.path(
        layout.center,
        outerLimit: _selected(segment) && segment.isExpanded
            ? layout.radius
            : null,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = colors.surface
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = _selected(segment) ? colors.onSurface : colors.outline
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4,
      );
    }
    canvas.restore();
  }

  void _label(
    Canvas canvas,
    StorageSunburstSegment segment,
    Path path,
    Color color,
  ) {
    final middleRadius = (segment.innerRadius + segment.outerRadius) / 2;
    final width =
        2 * math.sin(math.min(math.pi, segment.sweepAngle) / 2) * middleRadius -
        14;
    if (width < 40 ||
        segment.outerRadius - segment.innerRadius < fontSize + 10) {
      return;
    }
    final label = TextPainter(
      text: TextSpan(
        text: segment.isAggregate
            ? aggregateLabel(segment.aggregateCount)
            : segment.node.name,
        style: textStyle.copyWith(
          color: color,
          fontSize: fontSize,
          fontWeight: segment.node.isFolder ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      textDirection: direction,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: width);
    var rotation = segment.middleAngle + math.pi / 2;
    if (math.cos(rotation) < 0) rotation += math.pi;
    final midpoint = segment.middlePoint(layout.center);
    canvas.save();
    canvas.clipPath(path);
    canvas.translate(midpoint.dx, midpoint.dy);
    canvas.rotate(rotation);
    label.paint(canvas, Offset(-label.width / 2, -label.height / 2));
    canvas.restore();
    label.dispose();
  }

  @override
  SemanticsBuilderCallback get semanticsBuilder =>
      (_) => [
        for (final segment in layout.segments)
          CustomPainterSemantics(
            rect: Rect.fromCenter(
              center: segment.middlePoint(layout.center),
              width: math.min(
                32,
                math.max(1, segment.sweepAngle * segment.innerRadius),
              ),
              height: math.min(32, segment.outerRadius - segment.innerRadius),
            ),
            properties: SemanticsProperties(
              label: description(segment),
              textDirection: direction,
              button: true,
              selected: _selected(segment),
              onTap: () => onSelected(segment),
              onLongPress: !segment.isAggregate && segment.node.isFolder
                  ? () => onOpenFolder(segment.node)
                  : null,
            ),
          ),
      ];

  @override
  bool shouldRepaint(_SunburstPainter oldDelegate) =>
      !identical(oldDelegate.layout, layout) ||
      !identical(oldDelegate.selected, selected) ||
      !identical(oldDelegate.hovered, hovered) ||
      oldDelegate.colors != colors ||
      oldDelegate.textStyle != textStyle ||
      oldDelegate.fontSize != fontSize ||
      oldDelegate.direction != direction ||
      oldDelegate.aggregateLabel != aggregateLabel;

  @override
  bool shouldRebuildSemantics(_SunburstPainter oldDelegate) =>
      shouldRepaint(oldDelegate) ||
      oldDelegate.description != description ||
      oldDelegate.onSelected != onSelected ||
      oldDelegate.onOpenFolder != onOpenFolder;
}
