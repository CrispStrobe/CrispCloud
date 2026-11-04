import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:quds_office_engine/pdf_file.dart';

import 'paint_pdf_display_list.dart';
import 'pdf_font_faces.dart';
import 'pdf_page_rotation.dart';
import 'pdf_raster.dart';

/// Live thumbnail of one PDF page (same display list as the canvas).
class PdfPageThumb extends LeafRenderObjectWidget {
  /// PdfPageThumb API.
  const PdfPageThumb({
    super.key,
    required this.list,
    this.selected = false,
    this.annots = const <PdfAnnot>[],
  });

  /// list API.
  final PdfDisplayList list;

  /// selected API.
  final bool selected;

  /// annots API.
  final List<PdfAnnot> annots;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderPdfPageThumb(list: list, selected: selected, annots: annots);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderPdfPageThumb renderObject,
  ) {
    renderObject
      ..list = list
      ..selected = selected
      ..annots = annots;
  }
}

/// Class RenderPdfPageThumb.
class RenderPdfPageThumb extends RenderBox {
  /// RenderPdfPageThumb API.
  RenderPdfPageThumb({
    required this._list,
    required this._selected,
    required this._annots,
  });

  PdfDisplayList _list;
  bool _selected;
  List<PdfAnnot> _annots;
  final Map<int, ui.Image> _images = <int, ui.Image>{};
  final Set<int> _decoding = <int>{};

  /// list API.
  set list(PdfDisplayList value) {
    if (identical(_list, value)) {
      return;
    }
    _list = value;
    markNeedsLayout();
    markNeedsPaint();
  }

  /// selected API.
  set selected(bool value) {
    if (_selected == value) {
      return;
    }
    _selected = value;
    markNeedsPaint();
  }

  /// annots API.
  set annots(List<PdfAnnot> value) {
    _annots = value;
    markNeedsPaint();
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void performLayout() {
    final double maxW = constraints.maxWidth;
    final double pageW = _list.page.width <= 0 ? 595 : _list.page.width;
    final double pageH = _list.page.height <= 0 ? 842 : _list.page.height;
    final double w = maxW.isFinite && maxW > 0 ? maxW : 160;
    final double h = w * pageH / pageW;
    size = constraints.constrain(Size(w, h));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    for (final PdfPaintOp op in _list.ops) {
      if (op is PdfDrawText && op.fontBytes != null) {
        PdfFontFaces.ensure(op.fontBytes!, markNeedsPaint);
      }
      if (op is PdfDrawImage && !op.placeholder && op.bytes.isNotEmpty) {
        final int key = identityHashCode(op.bytes);
        if (!_images.containsKey(key) && _decoding.add(key)) {
          PdfRaster.decode(op, (ui.Image image) {
            _images[key] = image;
            _decoding.remove(key);
            markNeedsPaint();
          });
        }
      }
    }
    final Canvas canvas = context.canvas;
    final double scale =
        size.width / (_list.page.width <= 0 ? 595 : _list.page.width);
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFFFFFFF),
    );
    canvas.clipRect(Offset.zero & size);
    canvas.scale(scale);
    canvas.save();
    applyPdfPageRotation(canvas, _list.page);
    PaintPdfDisplayList.paint(
      canvas,
      _list,
      decodeImage: (Uint8List bytes, bool _) =>
          _images[identityHashCode(bytes)],
    );
    for (final PdfAnnot annot in _annots) {
      canvas.drawRect(
        Rect.fromLTWH(
          annot.rect.x,
          annot.rect.y,
          annot.rect.width,
          annot.rect.height,
        ),
        Paint()..color = Color(annot.color).withValues(alpha: 0.28),
      );
    }
    canvas.restore();
    canvas.restore();
    canvas.drawRect(
      offset & size,
      Paint()
        ..color = _selected ? const Color(0xFFC0392B) : const Color(0xFFB0B8C4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _selected ? 2.4 : 1,
    );
  }

  @override
  void dispose() {
    for (final ui.Image image in _images.values) {
      image.dispose();
    }
    _images.clear();
    super.dispose();
  }
}
