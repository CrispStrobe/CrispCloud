/// Flutter twins that were not in the first widget set.
///
/// Paint-only transforms, clips, fractional sizing, and slot layouts.
/// None of these is a document template.
library;

import 'dart:math' as math;

import '../../pdf/pdf_canvas.dart';
import '../../pdf/pdf_document.dart';
import 'pw_box.dart';
import 'pw_core.dart';
import 'pw_layout.dart';
import 'pw_style.dart';
import 'pw_text.dart';
import 'pw_types.dart';

/// Rotates, scales, or shifts [child] at paint time. Layout size is unchanged.
class Transform extends Widget {
  /// Transform API.
  const Transform.rotate({
    required this.angle,
    this.alignment = Alignment.center,
    required this.child,
  }) : scaleX = 1,
       scaleY = 1,
       translation = PwOffset.zero;

  /// scale API.
  const Transform.scale({
    double scale = 1,
    double? scaleX,
    double? scaleY,
    this.alignment = Alignment.center,
    required this.child,
  }) : angle = 0,
       scaleX = scaleX ?? scale,
       scaleY = scaleY ?? scale,
       translation = PwOffset.zero;

  /// translate API.
  const Transform.translate({
    required PwOffset offset,
    required this.child,
  }) : angle = 0,
       scaleX = 1,
       scaleY = 1,
       alignment = Alignment.center,
       translation = offset;

  /// Radians. Positive is clockwise in the page's top-left space.
  final double angle;

  /// scaleX API.
  final double scaleX;

  /// scaleY API.
  final double scaleY;

  /// translation API.
  final PwOffset translation;

  /// alignment API.
  final AlignmentGeometry alignment;

  /// child API.
  final Widget child;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    return _TransformBox(
      child.layout(context, constraints),
      angle,
      scaleX,
      scaleY,
      translation,
      alignment,
    );
  }
}

class _TransformBox extends PwBox {
  _TransformBox(
    this.child,
    this.angle,
    this.scaleX,
    this.scaleY,
    this.translation,
    this.alignment,
  ) : super(child.size);

  final PwBox child;
  final double angle;
  final double scaleX;
  final double scaleY;
  final PwOffset translation;
  final AlignmentGeometry alignment;

  @override
  double? get baseline => child.baseline;

  @override
  void paint(Context context, PwOffset offset) {
    final PdfCanvas? canvas = context.canvas;
    if (canvas == null) {
      child.paint(context, offset.translate(translation.dx, translation.dy));
      return;
    }
    final Alignment resolved = alignment.resolve(context.textDirection);
    final double cx =
        offset.dx + (resolved.x + 1) / 2 * size.width + translation.dx;
    final double cy =
        offset.dy + (resolved.y + 1) / 2 * size.height + translation.dy;
    canvas.save();
    if (translation.dx != 0 || translation.dy != 0) {
      canvas.translate(translation.dx, translation.dy);
    }
    if (angle != 0) {
      canvas.rotateAround(cx, cy, angle * 180 / math.pi);
    }
    if (scaleX != 1 || scaleY != 1) {
      canvas.scaleAround(cx, cy, scaleX, scaleY);
    }
    child.paint(context, offset);
    canvas.restore();
  }

  @override
  void noteDestination(Context context, PwOffset offset) {
    child.noteDestination(context, offset);
  }
}

/// Quarter-turn rotation that swaps width and height when the turn is odd.
class RotatedBox extends Widget {
  /// RotatedBox API.
  const RotatedBox({required this.quarterTurns, required this.child});

  /// Clockwise quarter turns.
  final int quarterTurns;

  /// child API.
  final Widget child;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    final int turns = quarterTurns % 4;
    final bool swap = turns == 1 || turns == 3;
    final BoxConstraints childCs = swap
        ? BoxConstraints(
            minWidth: constraints.minHeight,
            maxWidth: constraints.maxHeight,
            minHeight: constraints.minWidth,
            maxHeight: constraints.maxWidth,
          )
        : constraints;
    final PwBox box = child.layout(context, childCs);
    final PwSize size = swap
        ? PwSize(box.size.height, box.size.width)
        : box.size;
    return _RotatedBox(size, box, turns);
  }
}

class _RotatedBox extends PwBox {
  _RotatedBox(super.size, this.child, this.turns);

  final PwBox child;
  final int turns;

  @override
  void paint(Context context, PwOffset offset) {
    final PdfCanvas? canvas = context.canvas;
    if (canvas == null || turns == 0) {
      child.paint(context, offset);
      return;
    }
    final double cx = offset.dx + size.width / 2;
    final double cy = offset.dy + size.height / 2;
    final PwOffset origin = PwOffset(
      cx - child.size.width / 2,
      cy - child.size.height / 2,
    );
    canvas.save();
    canvas.rotateAround(cx, cy, turns * 90);
    child.paint(context, origin);
    canvas.restore();
  }

  @override
  void noteDestination(Context context, PwOffset offset) {
    child.noteDestination(context, offset);
  }
}

/// Clips [child] to its layout rectangle.
class ClipRect extends Widget {
  /// ClipRect API.
  const ClipRect({required this.child});

  /// child API.
  final Widget child;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    return _ClipBox(child.layout(context, constraints), _ClipKind.rect);
  }
}

/// Clips [child] to a rounded rectangle.
class ClipRRect extends Widget {
  /// ClipRRect API.
  const ClipRRect({this.borderRadius = 0, required this.child});

  /// borderRadius API.
  final double borderRadius;

  /// child API.
  final Widget child;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    return _ClipBox(
      child.layout(context, constraints),
      _ClipKind.round,
      radius: borderRadius,
    );
  }
}

/// Clips [child] to the oval inscribed in its box.
class ClipOval extends Widget {
  /// ClipOval API.
  const ClipOval({required this.child});

  /// child API.
  final Widget child;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    return _ClipBox(child.layout(context, constraints), _ClipKind.oval);
  }
}

/// One recorded path command, in the child's local space.
sealed class PwPathOp {
  /// PwPathOp API.
  const PwPathOp();
}

/// moveTo API.
class PwMoveTo extends PwPathOp {
  /// PwMoveTo API.
  const PwMoveTo(this.x, this.y);

  /// x API.
  final double x;

  /// y API.
  final double y;
}

/// lineTo API.
class PwLineTo extends PwPathOp {
  /// PwLineTo API.
  const PwLineTo(this.x, this.y);

  /// x API.
  final double x;

  /// y API.
  final double y;
}

/// close API.
class PwClosePath extends PwPathOp {
  /// PwClosePath API.
  const PwClosePath();
}

/// Path the caller fills in local coordinates. [ClipPath] clips to it.
class PwPath {
  /// PwPath API.
  PwPath();

  /// ops API.
  final List<PwPathOp> ops = <PwPathOp>[];

  /// moveTo API.
  void moveTo(double x, double y) => ops.add(PwMoveTo(x, y));

  /// lineTo API.
  void lineTo(double x, double y) => ops.add(PwLineTo(x, y));

  /// close API.
  void close() => ops.add(const PwClosePath());

  /// addRect API.
  void addRect(double x, double y, double w, double h) {
    moveTo(x, y);
    lineTo(x + w, y);
    lineTo(x + w, y + h);
    lineTo(x, y + h);
    close();
  }

  /// addOval API.
  void addOval(double x, double y, double w, double h) {
    ops.add(_PwOval(x, y, w, h));
  }
}

class _PwOval extends PwPathOp {
  const _PwOval(this.x, this.y, this.w, this.h);

  final double x;
  final double y;
  final double w;
  final double h;
}

/// Builds the clip path in the child's local coordinates.
typedef PwClipper = void Function(PwPath path, PwSize size);

/// Clips [child] to [clipper].
class ClipPath extends Widget {
  /// ClipPath API.
  const ClipPath({required this.clipper, required this.child});

  /// clipper API.
  final PwClipper clipper;

  /// child API.
  final Widget child;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    final PwBox box = child.layout(context, constraints);
    return _ClipBox(box, _ClipKind.path, clipper: clipper);
  }
}

enum _ClipKind { rect, round, oval, path }

class _ClipBox extends PwBox {
  _ClipBox(this.child, this.kind, {this.radius = 0, this.clipper})
    : super(child.size);

  final PwBox child;
  final _ClipKind kind;
  final double radius;
  final PwClipper? clipper;

  @override
  double? get baseline => child.baseline;

  @override
  void paint(Context context, PwOffset offset) {
    final PdfCanvas? canvas = context.canvas;
    if (canvas == null) {
      child.paint(context, offset);
      return;
    }
    canvas.save();
    switch (kind) {
      case _ClipKind.rect:
        canvas.clipRect(offset.dx, offset.dy, size.width, size.height);
      case _ClipKind.round:
        canvas.roundedRect(
          offset.dx,
          offset.dy,
          size.width,
          size.height,
          radius,
        );
        canvas.clip();
      case _ClipKind.oval:
        canvas.ellipse(offset.dx, offset.dy, size.width, size.height);
        canvas.clip();
      case _ClipKind.path:
        final PwPath path = PwPath();
        clipper?.call(path, size);
        _emitPath(canvas, path, offset);
        canvas.clip();
    }
    child.paint(context, offset);
    canvas.restore();
  }

  @override
  void noteDestination(Context context, PwOffset offset) {
    child.noteDestination(context, offset);
  }
}

void _emitPath(PdfCanvas canvas, PwPath path, PwOffset offset) {
  for (final PwPathOp op in path.ops) {
    switch (op) {
      case PwMoveTo(:final double x, :final double y):
        canvas.moveTo(offset.dx + x, offset.dy + y);
      case PwLineTo(:final double x, :final double y):
        canvas.lineTo(offset.dx + x, offset.dy + y);
      case PwClosePath():
        canvas.closePath();
      case _PwOval(:final double x, :final double y, :final double w, :final double h):
        canvas.ellipse(offset.dx + x, offset.dy + y, w, h);
    }
  }
}

/// Sizes itself to a fraction of the incoming max constraint.
class FractionallySizedBox extends Widget {
  /// FractionallySizedBox API.
  const FractionallySizedBox({
    this.alignment = Alignment.center,
    this.widthFactor,
    this.heightFactor,
    required this.child,
  });

  /// alignment API.
  final AlignmentGeometry alignment;

  /// widthFactor API.
  final double? widthFactor;

  /// heightFactor API.
  final double? heightFactor;

  /// child API.
  final Widget child;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    final double? width = widthFactor == null || !constraints.hasBoundedWidth
        ? null
        : constraints.maxWidth * widthFactor!;
    final double? height =
        heightFactor == null || !constraints.hasBoundedHeight
        ? null
        : constraints.maxHeight * heightFactor!;
    final PwBox box = child.layout(
      context,
      BoxConstraints(
        minWidth: width ?? 0,
        maxWidth: width ?? constraints.maxWidth,
        minHeight: height ?? 0,
        maxHeight: height ?? constraints.maxHeight,
      ),
    );
    final PwSize size = constraints.constrain(
      PwSize(width ?? box.size.width, height ?? box.size.height),
    );
    return ProxyBox(
      size,
      child: box,
      childOffset: alignment
          .resolve(context.textDirection)
          .alongOffset(size, box.size),
    );
  }
}

/// Shifts [child] so its baseline sits [baseline] points from the top.
class Baseline extends Widget {
  /// Baseline API.
  const Baseline({required this.baseline, required this.child});

  /// baseline API.
  final double baseline;

  /// child API.
  final Widget child;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    final PwBox box = child.layout(context, constraints.loosen());
    final double childBase = box.baseline ?? box.size.height;
    final double dy = (baseline - childBase).clamp(0, double.infinity);
    return ProxyBox(
      constraints.constrain(PwSize(box.size.width, dy + box.size.height)),
      child: box,
      childOffset: PwOffset(0, dy),
      baselineOverride: dy + childBase,
    );
  }
}

/// Second pass gives [child] a tight height equal to its loose height.
///
/// A [Row] with [CrossAxisAlignment.stretch] then shares that height.
class IntrinsicHeight extends Widget {
  /// IntrinsicHeight API.
  const IntrinsicHeight({required this.child});

  /// child API.
  final Widget child;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    final PwBox probe = child.layout(
      context.copyWith(measuring: true),
      BoxConstraints(
        minWidth: constraints.minWidth,
        maxWidth: constraints.maxWidth,
      ),
    );
    return child.layout(
      context,
      BoxConstraints(
        minWidth: constraints.minWidth,
        maxWidth: constraints.maxWidth,
        minHeight: probe.size.height,
        maxHeight: probe.size.height,
      ),
    );
  }
}

/// Lets [child] ignore the incoming max and paint outside this box.
class OverflowBox extends Widget {
  /// OverflowBox API.
  const OverflowBox({
    this.alignment = Alignment.center,
    this.minWidth,
    this.maxWidth,
    this.minHeight,
    this.maxHeight,
    required this.child,
  });

  /// alignment API.
  final AlignmentGeometry alignment;

  /// minWidth API.
  final double? minWidth;

  /// maxWidth API.
  final double? maxWidth;

  /// minHeight API.
  final double? minHeight;

  /// maxHeight API.
  final double? maxHeight;

  /// child API.
  final Widget child;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    final PwBox box = child.layout(
      context,
      BoxConstraints(
        minWidth: minWidth ?? 0,
        maxWidth: maxWidth ?? double.infinity,
        minHeight: minHeight ?? 0,
        maxHeight: maxHeight ?? double.infinity,
      ),
    );
    final double w = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : box.size.width;
    final double h = constraints.hasBoundedHeight
        ? constraints.maxHeight
        : box.size.height;
    final PwSize size = constraints.constrain(PwSize(w, h));
    return ProxyBox(
      size,
      child: box,
      childOffset: alignment
          .resolve(context.textDirection)
          .alongOffset(size, box.size),
    );
  }
}

/// Caps an unbounded axis. A bounded axis is left alone.
class LimitedBox extends Widget {
  /// LimitedBox API.
  const LimitedBox({
    this.maxWidth = double.infinity,
    this.maxHeight = double.infinity,
    required this.child,
  });

  /// maxWidth API.
  final double maxWidth;

  /// maxHeight API.
  final double maxHeight;

  /// child API.
  final Widget child;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    final double maxW = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : math.min(constraints.maxWidth, maxWidth);
    final double maxH = constraints.hasBoundedHeight
        ? constraints.maxHeight
        : math.min(constraints.maxHeight, maxHeight);
    return child.layout(
      context,
      BoxConstraints(
        minWidth: constraints.minWidth.clamp(0, maxW),
        maxWidth: maxW,
        minHeight: constraints.minHeight.clamp(0, maxH),
        maxHeight: maxH,
      ),
    );
  }
}

/// Draws behind and in front of [child]. Coordinates are local to the box.
typedef PdfCustomPainter = void Function(PdfCanvas canvas, PwSize size);

/// Custom paint. [size] is used only when [child] is null.
class CustomPaint extends Widget {
  /// CustomPaint API.
  const CustomPaint({
    this.painter,
    this.foregroundPainter,
    this.child,
    this.size,
  });

  /// painter API.
  final PdfCustomPainter? painter;

  /// foregroundPainter API.
  final PdfCustomPainter? foregroundPainter;

  /// child API.
  final Widget? child;

  /// size API.
  final PwSize? size;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    final Widget? kid = child;
    final PwBox? box = kid?.layout(context, constraints);
    final PwSize raw = box?.size ?? size ?? PwSize.zero;
    final bool fillWidth =
        size == null && kid == null && constraints.hasBoundedWidth;
    final bool fillHeight =
        size == null && kid == null && constraints.hasBoundedHeight;
    final PwSize painted = constraints.constrain(
      PwSize(
        fillWidth ? constraints.maxWidth : raw.width,
        fillHeight ? constraints.maxHeight : raw.height,
      ),
    );
    return _CustomPaintBox(painted, box, painter, foregroundPainter);
  }
}

class _CustomPaintBox extends PwBox {
  _CustomPaintBox(
    super.size,
    this.child,
    this.painter,
    this.foregroundPainter,
  );

  final PwBox? child;
  final PdfCustomPainter? painter;
  final PdfCustomPainter? foregroundPainter;

  @override
  void paint(Context context, PwOffset offset) {
    final PdfCanvas? canvas = context.canvas;
    if (canvas != null && painter != null) {
      canvas.save();
      canvas.translate(offset.dx, offset.dy);
      painter!(canvas, size);
      canvas.restore();
    }
    child?.paint(context, offset);
    if (canvas != null && foregroundPainter != null) {
      canvas.save();
      canvas.translate(offset.dx, offset.dy);
      foregroundPainter!(canvas, size);
      canvas.restore();
    }
  }

  @override
  void noteDestination(Context context, PwOffset offset) {
    child?.noteDestination(context, offset);
  }
}

/// Tags a child so [CustomMultiChildLayout] can lay it out by [id].
class LayoutId extends Widget {
  /// LayoutId API.
  const LayoutId({required this.id, required this.child});

  /// id API.
  final Object id;

  /// child API.
  final Widget child;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    return child.layout(context, constraints);
  }
}

/// Host passed to [CustomMultiChildLayout.performLayout].
class MultiChildLayoutHost {
  /// MultiChildLayoutHost API.
  MultiChildLayoutHost(this.constraints, this._context, this._children);

  /// constraints API.
  final BoxConstraints constraints;

  final Context _context;
  final Map<Object, Widget> _children;

  /// boxes API.
  final Map<Object, PwBox> boxes = <Object, PwBox>{};

  /// offsets API.
  final Map<Object, PwOffset> offsets = <Object, PwOffset>{};

  /// layoutChild API.
  PwSize layoutChild(Object id, BoxConstraints constraints) {
    final Widget? child = _children[id];
    if (child == null) {
      return PwSize.zero;
    }
    final PwBox box = child.layout(_context, constraints);
    boxes[id] = box;
    offsets.putIfAbsent(id, () => PwOffset.zero);
    return box.size;
  }

  /// positionChild API.
  void positionChild(Object id, PwOffset offset) {
    offsets[id] = offset;
  }
}

/// Arranges [LayoutId] children by a function, not a fixed flex rule.
class CustomMultiChildLayout extends Widget {
  /// CustomMultiChildLayout API.
  const CustomMultiChildLayout({
    required this.children,
    required this.performLayout,
    this.size,
  });

  /// children API.
  final List<LayoutId> children;

  /// performLayout API.
  final void Function(MultiChildLayoutHost host) performLayout;

  /// size API. Null uses the incoming max when bounded, else the children.
  final PwSize Function(BoxConstraints constraints)? size;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    final MultiChildLayoutHost host = MultiChildLayoutHost(constraints, context, {
      for (final LayoutId child in children) child.id: child.child,
    });
    performLayout(host);
    final PwSize raw = size?.call(constraints) ?? _span(host, constraints);
    return GroupBox(constraints.constrain(raw), <(PwBox, PwOffset)>[
      for (final LayoutId child in children)
        if (host.boxes[child.id] != null)
          (
            host.boxes[child.id]!,
            host.offsets[child.id] ?? PwOffset.zero,
          ),
    ]);
  }

  PwSize _span(MultiChildLayoutHost host, BoxConstraints constraints) {
    if (constraints.hasBoundedWidth && constraints.hasBoundedHeight) {
      return PwSize(constraints.maxWidth, constraints.maxHeight);
    }
    var w = 0.0;
    var h = 0.0;
    for (final MapEntry<Object, PwBox> entry in host.boxes.entries) {
      final PwOffset off = host.offsets[entry.key] ?? PwOffset.zero;
      w = math.max(w, off.dx + entry.value.size.width);
      h = math.max(h, off.dy + entry.value.size.height);
    }
    return PwSize(
      constraints.hasBoundedWidth ? constraints.maxWidth : w,
      constraints.hasBoundedHeight ? constraints.maxHeight : h,
    );
  }
}

/// Drawn radio mark. Not an AcroForm field unless [acroForm] is set.
class Radio extends Widget {
  /// Radio API.
  const Radio({
    this.value = false,
    this.size = 12,
    this.activeColor = '1B5E20',
    this.name = '',
    this.exportValue = 'Yes',
    this.acroForm = false,
  });

  /// value API.
  final bool value;

  /// size API.
  final double size;

  /// activeColor API.
  final String activeColor;

  /// AcroForm field name.
  final String name;

  /// Export value when selected.
  final String exportValue;

  /// When true, [Document.save] writes a real `/Btn` radio.
  final bool acroForm;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    return _RadioBox(PwSize(size, size), value, activeColor, name, exportValue, acroForm);
  }
}

class _RadioBox extends PwBox {
  _RadioBox(
    super.size,
    this.value,
    this.activeColor,
    this.name,
    this.exportValue,
    this.acroForm,
  );

  final bool value;
  final String activeColor;
  final String name;
  final String exportValue;
  final bool acroForm;

  @override
  void paint(Context context, PwOffset offset) {
    if (acroForm) {
      context.registerAcroField(
        PdfAcroField(
          name: name,
          type: 'Btn',
          x: offset.dx,
          y: offset.dy,
          width: size.width,
          height: size.height,
          pageIndex: context.pageNumber - 1,
          checked: value,
          exportOn: exportValue,
          radio: true,
        ),
      );
    }
    final PdfCanvas? canvas = context.canvas;
    if (canvas == null) {
      return;
    }
    canvas.endText();
    canvas.setStrokeColor(value ? activeColor : '37474F');
    canvas.setLineWidth(0.9);
    canvas.ellipse(offset.dx, offset.dy, size.width, size.height);
    canvas.stroke();
    if (value) {
      final double inset = size.width * 0.28;
      canvas.setFillColor(activeColor);
      canvas.ellipse(
        offset.dx + inset,
        offset.dy + inset,
        size.width - inset * 2,
        size.height - inset * 2,
      );
      canvas.fill();
    }
  }
}

/// Drawn switch. The thumb sits at the start edge when off.
class Switch extends Widget {
  /// Switch API.
  const Switch({
    this.value = false,
    this.width = 28,
    this.height = 16,
    this.activeColor = '1B5E20',
  });

  /// value API.
  final bool value;

  /// width API.
  final double width;

  /// height API.
  final double height;

  /// activeColor API.
  final String activeColor;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    return _SwitchBox(
      PwSize(width, height),
      value,
      activeColor,
      context.textDirection == TextDirection.rtl,
    );
  }
}

class _SwitchBox extends PwBox {
  _SwitchBox(super.size, this.value, this.activeColor, this.rtl);

  final bool value;
  final String activeColor;
  final bool rtl;

  @override
  void paint(Context context, PwOffset offset) {
    final PdfCanvas? canvas = context.canvas;
    if (canvas == null) {
      return;
    }
    canvas.endText();
    canvas.setFillColor(value ? activeColor : 'CFD8DC');
    canvas.roundedRect(
      offset.dx,
      offset.dy,
      size.width,
      size.height,
      size.height / 2,
    );
    canvas.fill();
    final double d = size.height - 4;
    final bool onStart = value == rtl;
    final double x = onStart ? offset.dx + 2 : offset.dx + size.width - d - 2;
    canvas.setFillColor('FFFFFF');
    canvas.ellipse(x, offset.dy + 2, d, d);
    canvas.fill();
  }
}

/// One glyph from the document face, centered in a square of [size].
class Icon extends Widget {
  /// Icon API.
  const Icon(this.codePoint, {this.size = 16, this.color});

  /// codePoint API.
  final int codePoint;

  /// size API.
  final double size;

  /// color API.
  final String? color;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    final PwBox glyph = Text(
      String.fromCharCode(codePoint),
      style: TextStyle(fontSize: size * 0.85, color: color, height: 1),
    ).layout(
      context,
      BoxConstraints(maxWidth: size * 2, maxHeight: size * 2),
    );
    final PwSize box = constraints.constrain(PwSize(size, size));
    return ProxyBox(
      box,
      child: glyph,
      childOffset: Alignment.center.alongOffset(box, glyph.size),
    );
  }
}

/// Leading, title, subtitle, and trailing. Slots, not a document.
class ListTile extends Widget {
  /// ListTile API.
  const ListTile({
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.contentPadding,
  });

  /// leading API.
  final Widget? leading;

  /// title API.
  final Widget title;

  /// subtitle API.
  final Widget? subtitle;

  /// trailing API.
  final Widget? trailing;

  /// contentPadding API.
  final EdgeInsetsGeometry? contentPadding;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    final Widget? lead = leading;
    final Widget? sub = subtitle;
    final Widget? trail = trailing;
    return Padding(
      padding:
          contentPadding ??
          const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          ?lead,
          if (lead != null) const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                title,
                ?sub,
              ],
            ),
          ),
          if (trail != null) const SizedBox(width: 10),
          ?trail,
        ],
      ),
    ).layout(context, constraints);
  }
}
