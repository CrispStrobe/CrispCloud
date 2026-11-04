// lib/widgets/pptx_slide_viewer.dart
//
// Approximate PPTX slide rendering: positioned text boxes, filled shapes and
// pictures are laid out on the slide canvas using the deck's EMU geometry.
// This is not a pixel-perfect PowerPoint renderer (no animations, charts or
// SmartArt), but it shows the actual slide composition instead of flat text.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/slide_viewer_strings.dart';
import '../services/office_document_service.dart';

class PptxSlideViewer extends StatefulWidget {
  final SlideDeck deck;
  final double fontScale;

  const PptxSlideViewer({
    super.key,
    required this.deck,
    this.fontScale = 1.0,
  });

  @override
  State<PptxSlideViewer> createState() => _PptxSlideViewerState();
}

class _PptxSlideViewerState extends State<PptxSlideViewer> {
  int _index = 0;

  Color? _color(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final value = int.tryParse(hex.replaceAll('#', ''), radix: 16);
    if (value == null) return null;
    return Color(0xFF000000 | value);
  }

  @override
  Widget build(BuildContext context) {
    final deck = widget.deck;
    if (deck.slides.isEmpty) {
      return Center(child: Text(SlideViewerStrings(context).text('empty')));
    }
    final index = _index.clamp(0, deck.slides.length - 1);
    final slide = deck.slides[index];
    final theme = Theme.of(context);

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final aspect = deck.widthEmu / deck.heightEmu;
                var width = constraints.maxWidth;
                var height = width / aspect;
                if (height > constraints.maxHeight) {
                  height = constraints.maxHeight;
                  width = height * aspect;
                }
                final scale = width / deck.widthEmu;

                return Center(
                  child: Container(
                    width: width,
                    height: height,
                    decoration: BoxDecoration(
                      color: _color(slide.backgroundHex) ?? Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: Stack(
                      children: [
                        for (final shape in slide.shapes)
                          Positioned(
                            left: shape.x * scale,
                            top: shape.y * scale,
                            width: math.max(1.0, shape.width * scale),
                            height: math.max(1.0, shape.height * scale),
                            child: _shapeWidget(shape, scale),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
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
                tooltip: SlideViewerStrings(context).text('first'),
                icon: const Icon(Icons.first_page, size: 18),
                onPressed:
                    index > 0 ? () => setState(() => _index = 0) : null,
              ),
              IconButton(
                tooltip: SlideViewerStrings(context).text('previous'),
                icon: const Icon(Icons.chevron_left, size: 18),
                onPressed: index > 0
                    ? () => setState(() => _index = index - 1)
                    : null,
              ),
              Text(
                '${index + 1} / ${deck.slides.length}',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              IconButton(
                tooltip: SlideViewerStrings(context).text('next'),
                icon: const Icon(Icons.chevron_right, size: 18),
                onPressed: index < deck.slides.length - 1
                    ? () => setState(() => _index = index + 1)
                    : null,
              ),
              IconButton(
                tooltip: SlideViewerStrings(context).text('last'),
                icon: const Icon(Icons.last_page, size: 18),
                onPressed: index < deck.slides.length - 1
                    ? () => setState(() => _index = deck.slides.length - 1)
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _shapeWidget(SlideShape shape, double scale) {
    final image = shape.image;
    if (image != null) {
      return Image.memory(
        image,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    }
    return Container(
      color: _color(shape.fillColorHex),
      alignment: Alignment.topLeft,
      padding: EdgeInsets.all(math.max(1.0, 2 * widget.fontScale)),
      child: Text(
        shape.text ?? '',
        softWrap: true,
        overflow: TextOverflow.clip,
        style: TextStyle(
          // 1 pt = 12700 EMU.
          fontSize: (shape.fontSizePt * 12700 * scale)
              .clamp(3.0, 96.0)
              .toDouble(),
          fontWeight: shape.bold ? FontWeight.bold : FontWeight.normal,
          color: _color(shape.textColorHex) ?? Colors.black,
          height: 1.15,
        ),
      ),
    );
  }
}
