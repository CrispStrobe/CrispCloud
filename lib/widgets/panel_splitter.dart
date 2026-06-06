// lib/widgets/panel_splitter.dart
//
// Draggable splitter between two panels. Supports horizontal and vertical
// orientations. Stores the split ratio (0.0–1.0) for the left/top panel.

import 'package:flutter/material.dart';

class PanelSplitter extends StatefulWidget {
  final Widget first;
  final Widget second;
  final Widget? third; // Optional third pane (e.g., preview)
  final double thirdWidth; // Fixed width for third pane
  final double initialRatio;
  final double minRatio;
  final double maxRatio;
  final ValueChanged<double>? onRatioChanged;
  final Axis axis;

  const PanelSplitter({
    super.key,
    required this.first,
    required this.second,
    this.third,
    this.thirdWidth = 280,
    this.initialRatio = 0.5,
    this.minRatio = 0.2,
    this.maxRatio = 0.8,
    this.onRatioChanged,
    this.axis = Axis.horizontal,
  });

  @override
  State<PanelSplitter> createState() => _PanelSplitterState();
}

class _PanelSplitterState extends State<PanelSplitter> {
  late double _ratio;
  static const _handleWidth = 6.0;

  @override
  void initState() {
    super.initState();
    _ratio = widget.initialRatio;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isHorizontal = widget.axis == Axis.horizontal;
        final totalSize = isHorizontal ? constraints.maxWidth : constraints.maxHeight;
        final thirdSize = widget.third != null ? widget.thirdWidth + 1 : 0; // +1 for divider
        final availableSize = totalSize - thirdSize - _handleWidth;

        final firstSize = (availableSize * _ratio).clamp(
          availableSize * widget.minRatio,
          availableSize * widget.maxRatio,
        );
        final secondSize = availableSize - firstSize;

        final children = <Widget>[
          SizedBox(
            width: isHorizontal ? firstSize : null,
            height: isHorizontal ? null : firstSize,
            child: widget.first,
          ),
          // Draggable handle
          MouseRegion(
            cursor: isHorizontal
                ? SystemMouseCursors.resizeColumn
                : SystemMouseCursors.resizeRow,
            child: GestureDetector(
              onPanUpdate: (details) {
                setState(() {
                  final delta = isHorizontal ? details.delta.dx : details.delta.dy;
                  final newFirst = firstSize + delta;
                  _ratio = (newFirst / availableSize).clamp(widget.minRatio, widget.maxRatio);
                  widget.onRatioChanged?.call(_ratio);
                });
              },
              // Double-tap to reset to 50/50
              onDoubleTap: () {
                setState(() {
                  _ratio = 0.5;
                  widget.onRatioChanged?.call(_ratio);
                });
              },
              child: Container(
                width: isHorizontal ? _handleWidth : null,
                height: isHorizontal ? null : _handleWidth,
                color: Theme.of(context).dividerColor,
                child: Center(
                  child: Container(
                    width: isHorizontal ? 2 : 24,
                    height: isHorizontal ? 24 : 2,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: isHorizontal ? secondSize : null,
            height: isHorizontal ? null : secondSize,
            child: widget.second,
          ),
          if (widget.third != null) ...[
            Container(
              width: isHorizontal ? 1 : null,
              height: isHorizontal ? null : 1,
              color: Theme.of(context).dividerColor,
            ),
            SizedBox(
              width: isHorizontal ? widget.thirdWidth : null,
              height: isHorizontal ? null : widget.thirdWidth,
              child: widget.third,
            ),
          ],
        ];

        return isHorizontal
            ? Row(children: children)
            : Column(children: children);
      },
    );
  }
}
