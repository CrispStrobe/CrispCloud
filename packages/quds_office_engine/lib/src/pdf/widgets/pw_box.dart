/// Box-model widgets: padding, align, decoration, shapes.
library;

import '../../pdf/pdf_canvas.dart';
import '../../pdf/pdf_document.dart';
import 'pw_core.dart';
import 'pw_text.dart';
import 'pw_types.dart';

/// Same constructor as Flutter [Padding].
class Padding extends Widget {
  /// Padding API.
  const Padding({required this.padding, required this.child});

  /// padding API.
  final EdgeInsetsGeometry padding;

  /// child API.
  final Widget child;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    final EdgeInsets pad = padding.resolve(context.textDirection);
    final PwBox box = child.layout(context, constraints.deflate(pad));
    return ProxyBox(
      PwSize(
        constraints.constrainWidth(box.size.width + pad.horizontal),
        constraints.constrainHeight(box.size.height + pad.vertical),
      ),
      child: box,
      childOffset: PwOffset(pad.left, pad.top),
    );
  }
}

/// Same constructor as Flutter [Align].
class Align extends Widget {
  /// Align API.
  const Align({
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
    final PwBox box = child.layout(context, constraints.loosen());
    final double w = widthFactor != null
        ? box.size.width * widthFactor!
        : constraints.hasBoundedWidth
        ? constraints.maxWidth
        : box.size.width;
    final double h = heightFactor != null
        ? box.size.height * heightFactor!
        : constraints.hasBoundedHeight
        ? constraints.maxHeight
        : box.size.height;
    final PwSize size = constraints.constrain(PwSize(w, h));
    final Alignment resolved = alignment.resolve(context.textDirection);
    return ProxyBox(
      size,
      child: box,
      childOffset: resolved.alongOffset(size, box.size),
    );
  }
}

/// Same constructor as Flutter [Center].
class Center extends Align {
  /// Center API.
  const Center({required super.child, super.widthFactor, super.heightFactor})
    : super(alignment: Alignment.center);
}

/// Same constructors as Flutter [SizedBox].
class SizedBox extends Widget {
  /// SizedBox API.
  const SizedBox({this.width, this.height, this.child});

  /// expand API.
  const SizedBox.expand({this.child})
    : width = double.infinity,
      height = double.infinity;

  /// shrink API.
  const SizedBox.shrink({this.child}) : width = 0, height = 0;

  /// square API.
  const SizedBox.square({required double dimension, this.child})
    : width = dimension,
      height = dimension;

  /// width API.
  final double? width;

  /// height API.
  final double? height;

  /// child API.
  final Widget? child;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    final BoxConstraints tight = constraints.tighten(width: width, height: height);
    final Widget? kid = child;
    if (kid == null) {
      return EmptyBox(
        PwSize(tight.constrainWidth(0), tight.constrainHeight(0)),
      );
    }
    final PwBox box = kid.layout(context, tight);
    return ProxyBox(
      PwSize(tight.constrainWidth(box.size.width), tight.constrainHeight(box.size.height)),
      child: box,
    );
  }
}

/// Same constructor as Flutter [ConstrainedBox].
class ConstrainedBox extends Widget {
  /// ConstrainedBox API.
  const ConstrainedBox({required this.constraints, required this.child});

  /// constraints API.
  final BoxConstraints constraints;

  /// child API.
  final Widget child;

  @override
  PwBox layout(Context context, BoxConstraints incoming) {
    return child.layout(
      context,
      BoxConstraints(
        minWidth: constraints.minWidth.clamp(incoming.minWidth, incoming.maxWidth),
        maxWidth: constraints.maxWidth.clamp(incoming.minWidth, incoming.maxWidth),
        minHeight: constraints.minHeight.clamp(
          incoming.minHeight,
          incoming.maxHeight,
        ),
        maxHeight: constraints.maxHeight.clamp(
          incoming.minHeight,
          incoming.maxHeight,
        ),
      ),
    );
  }
}

/// Same constructor as Flutter [DecoratedBox].
class DecoratedBox extends Widget {
  /// DecoratedBox API.
  const DecoratedBox({required this.decoration, required this.child});

  /// decoration API.
  final BoxDecoration decoration;

  /// child API.
  final Widget child;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    final PwBox box = child.layout(context, constraints);
    return ProxyBox(box.size, child: box, decoration: decoration);
  }
}

/// Color + padding + alignment + constraints.
class Container extends Widget {
  /// Container API.
  const Container({
    this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.alignment,
    this.decoration,
    this.color,
    this.constraints,
  });

  /// child API.
  final Widget? child;

  /// width API.
  final double? width;

  /// height API.
  final double? height;

  /// padding API.
  final EdgeInsetsGeometry? padding;

  /// margin API.
  final EdgeInsetsGeometry? margin;

  /// alignment API.
  final AlignmentGeometry? alignment;

  /// decoration API.
  final BoxDecoration? decoration;

  /// color API.
  final String? color;

  /// Extra constraints (e.g. `minHeight` for table cells), like package:pdf.
  final BoxConstraints? constraints;

  @override
  PwBox layout(Context context, BoxConstraints incoming) {
    final EdgeInsets outer = (margin ?? EdgeInsets.zero).resolve(
      context.textDirection,
    );
    final EdgeInsets pad = (padding ?? EdgeInsets.zero).resolve(
      context.textDirection,
    );
    BoxConstraints inner = incoming.deflate(outer);
    final BoxConstraints? extra = constraints;
    if (extra != null) {
      inner = BoxConstraints(
        minWidth: extra.minWidth.clamp(inner.minWidth, inner.maxWidth),
        maxWidth: extra.maxWidth.clamp(inner.minWidth, inner.maxWidth),
        minHeight: extra.minHeight.clamp(inner.minHeight, inner.maxHeight),
        maxHeight: extra.maxHeight.clamp(inner.minHeight, inner.maxHeight),
      );
    }
    inner = inner.tighten(width: width, height: height);
    final BoxConstraints padded = inner.deflate(pad);
    final Widget? kid = child;
    PwBox? childBox;
    if (kid != null) {
      childBox = kid.layout(context, padded.loosen());
    }
    final PwSize childSize = childBox?.size ?? PwSize.zero;
    final double contentW = childSize.width + pad.horizontal;
    final double contentH = childSize.height + pad.vertical;
    final bool hasFill = color != null || decoration != null;
    // Match Flutter / package:pdf: alignment (or a painted fill) expands to the
    // parent's max width. Height expands only when the parent tightens it
    // (table cells) or sets a minHeight — never to an unbounded page leftover.
    final bool expandW =
        inner.hasBoundedWidth && (alignment != null || hasFill || kid == null);
    final bool heightTight =
        inner.hasBoundedHeight && (inner.maxHeight - inner.minHeight) < 1e-9;
    final bool expandH = heightTight || inner.minHeight > contentH;
    final double w = width ?? (expandW ? inner.maxWidth : contentW);
    final double h = height ??
        (expandH
            ? inner.constrainHeight(
                contentH < inner.minHeight ? inner.minHeight : contentH,
              )
            : contentH);
    final PwSize boxSize = inner.constrain(PwSize(w, h));
    final PwOffset childOff;
    if (childBox != null) {
      final PwSize padBox = PwSize(
        (boxSize.width - pad.horizontal).clamp(0, boxSize.width),
        (boxSize.height - pad.vertical).clamp(0, boxSize.height),
      );
      final Alignment resolved =
          alignment?.resolve(context.textDirection) ?? _startTop(context);
      final PwOffset aligned = resolved.alongOffset(
        padBox,
        childSize,
      );
      childOff = PwOffset(pad.left + aligned.dx, pad.top + aligned.dy);
    } else {
      childOff = PwOffset(pad.left, pad.top);
    }
    return ProxyBox(
      PwSize(
        incoming.constrainWidth(boxSize.width + outer.horizontal),
        incoming.constrainHeight(boxSize.height + outer.vertical),
      ),
      child: childBox,
      childOffset: PwOffset(outer.left + childOff.dx, outer.top + childOff.dy),
      decoration: decoration ?? (color == null ? null : BoxDecoration(color: color)),
    );
  }
}

/// Start edge of a box: right in RTL, left in LTR.
Alignment _startTop(Context context) {
  return context.textDirection == TextDirection.rtl
      ? Alignment.topRight
      : Alignment.topLeft;
}

/// Documented opacity. The writer has no ExtGState yet, so the child paints as-is.
class Opacity extends Widget {
  /// Opacity API.
  const Opacity({required this.opacity, required this.child});

  /// opacity API.
  final double opacity;

  /// child API.
  final Widget child;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    return child.layout(context, constraints);
  }
}

/// Scales [child] to [fit] the incoming box.
class FittedBox extends Widget {
  /// FittedBox API.
  const FittedBox({
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    required this.child,
  });

  /// fit API.
  final BoxFit fit;

  /// alignment API.
  final AlignmentGeometry alignment;

  /// child API.
  final Widget child;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    final PwBox box = child.layout(
      context,
      const BoxConstraints(),
    );
    final PwSize dest = PwSize(
      constraints.hasBoundedWidth ? constraints.maxWidth : box.size.width,
      constraints.hasBoundedHeight ? constraints.maxHeight : box.size.height,
    );
    return _FittedBox(constraints.constrain(dest), box, fit, alignment);
  }
}

class _FittedBox extends PwBox {
  _FittedBox(super.size, this.child, this.fit, this.alignment);

  final PwBox child;
  final BoxFit fit;
  final AlignmentGeometry alignment;

  @override
  void paint(Context context, PwOffset offset) {
    final double sw = child.size.width <= 0 ? 1 : child.size.width;
    final double sh = child.size.height <= 0 ? 1 : child.size.height;
    final double sx = size.width / sw;
    final double sy = size.height / sh;
    final double scale = switch (fit) {
      BoxFit.fill => 1,
      BoxFit.fitWidth => sx,
      BoxFit.fitHeight => sy,
      BoxFit.cover => sx > sy ? sx : sy,
      BoxFit.none => 1,
      BoxFit.scaleDown => (sx < 1 || sy < 1)
          ? (sx < sy ? sx : sy)
          : 1,
      BoxFit.contain => sx < sy ? sx : sy,
    };
    final PwSize drawn = fit == BoxFit.fill
        ? size
        : PwSize(sw * scale, sh * scale);
    final Alignment resolved = alignment.resolve(context.textDirection);
    final PwOffset aligned = resolved.alongOffset(size, drawn);
    final PdfCanvas? canvas = context.canvas;
    if (canvas == null) {
      child.paint(context, offset);
      return;
    }
    canvas.save();
    canvas.clipRect(offset.dx, offset.dy, size.width, size.height);
    if (fit == BoxFit.fill) {
      canvas.translateScale(offset.dx, offset.dy, 1);
      // Stretch via cm: scale x and y independently.
      canvas.endText();
      // translateScale is uniform; paint at origin after a manual cm.
    }
    child.paint(
      context,
      offset.translate(aligned.dx, aligned.dy),
    );
    canvas.restore();
  }
}

/// Same constructor as Flutter [AspectRatio].
class AspectRatio extends Widget {
  /// AspectRatio API.
  const AspectRatio({required this.aspectRatio, required this.child});

  /// aspectRatio API.
  final double aspectRatio;

  /// child API.
  final Widget child;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    var w = constraints.maxWidth;
    var h = w / aspectRatio;
    if (h > constraints.maxHeight) {
      h = constraints.maxHeight;
      w = h * aspectRatio;
    }
    final PwSize size = constraints.constrain(PwSize(w, h));
    final PwBox box = child.layout(context, BoxConstraints.tight(size));
    return ProxyBox(size, child: box);
  }
}

/// Horizontal rule.
class Divider extends Widget {
  /// Divider API.
  const Divider({
    this.height,
    this.thickness,
    this.color,
    this.indent = 0,
    this.endIndent = 0,
  });

  /// height API.
  final double? height;

  /// thickness API.
  final double? thickness;

  /// color API.
  final String? color;

  /// indent API.
  final double indent;

  /// endIndent API.
  final double endIndent;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    final double h = height ?? 12;
    final double w = constraints.hasBoundedWidth ? constraints.maxWidth : 200;
    final double t = thickness ?? 0.8;
    final String c = color ?? 'B0BEC5';
    return _DividerBox(PwSize(w, h), t, c, indent, endIndent);
  }
}

class _DividerBox extends PwBox {
  _DividerBox(super.size, this.thickness, this.color, this.indent, this.endIndent);

  final double thickness;
  final String color;
  final double indent;
  final double endIndent;

  @override
  void paint(Context context, PwOffset offset) {
    final PdfCanvas? canvas = context.canvas;
    if (canvas == null) {
      return;
    }
    canvas.endText();
    canvas.setStrokeColor(color);
    canvas.setLineWidth(thickness);
    final double y = offset.dy + size.height / 2;
    canvas.moveTo(offset.dx + indent, y);
    canvas.lineTo(offset.dx + size.width - endIndent, y);
    canvas.stroke();
  }
}

/// Vertical rule. [width] is the slot; the stroke sits in the middle.
class VerticalDivider extends Widget {
  /// VerticalDivider API.
  const VerticalDivider({
    this.width,
    this.thickness,
    this.color,
    this.indent = 0,
    this.endIndent = 0,
  });

  /// width API.
  final double? width;

  /// thickness API.
  final double? thickness;

  /// color API.
  final String? color;

  /// indent API.
  final double indent;

  /// endIndent API.
  final double endIndent;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    final double w = width ?? 16;
    final double h = constraints.hasBoundedHeight ? constraints.maxHeight : 24;
    final double t = thickness ?? 0.8;
    final String c = color ?? 'B0BEC5';
    return _VerticalDividerBox(
      PwSize(w, h),
      t,
      c,
      indent,
      endIndent,
    );
  }
}

class _VerticalDividerBox extends PwBox {
  _VerticalDividerBox(
    super.size,
    this.thickness,
    this.color,
    this.indent,
    this.endIndent,
  );

  final double thickness;
  final String color;
  final double indent;
  final double endIndent;

  @override
  void paint(Context context, PwOffset offset) {
    final PdfCanvas? canvas = context.canvas;
    if (canvas == null) {
      return;
    }
    canvas.endText();
    canvas.setStrokeColor(color);
    canvas.setLineWidth(thickness);
    final double x = offset.dx + size.width / 2;
    canvas.moveTo(x, offset.dy + indent);
    canvas.lineTo(x, offset.dy + size.height - endIndent);
    canvas.stroke();
  }
}

/// Filled / stroked oval.
class Circle extends Widget {
  /// Circle API.
  const Circle({
    this.fillColor,
    this.strokeColor,
    this.width = 40,
    this.height = 40,
  });

  /// fillColor API.
  final String? fillColor;

  /// strokeColor API.
  final String? strokeColor;

  /// width API.
  final double width;

  /// height API.
  final double height;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    return _ShapeBox(
      constraints.constrain(PwSize(width, height)),
      fillColor,
      strokeColor,
      circle: true,
    );
  }
}

/// Filled / stroked rectangle.
class Rectangle extends Widget {
  /// Rectangle API.
  const Rectangle({
    this.fillColor,
    this.strokeColor,
    this.width = 80,
    this.height = 40,
  });

  /// fillColor API.
  final String? fillColor;

  /// strokeColor API.
  final String? strokeColor;

  /// width API.
  final double width;

  /// height API.
  final double height;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    return _ShapeBox(
      constraints.constrain(PwSize(width, height)),
      fillColor,
      strokeColor,
      circle: false,
    );
  }
}

class _ShapeBox extends PwBox {
  _ShapeBox(super.size, this.fill, this.stroke, {required this.circle});

  final String? fill;
  final String? stroke;
  final bool circle;

  @override
  void paint(Context context, PwOffset offset) {
    final PdfCanvas? canvas = context.canvas;
    if (canvas == null) {
      return;
    }
    canvas.endText();
    if (circle) {
      if (fill != null) {
        canvas.setFillColor(fill!);
        canvas.ellipse(offset.dx, offset.dy, size.width, size.height);
        canvas.fill();
      }
      if (stroke != null) {
        canvas.setStrokeColor(stroke!);
        canvas.setLineWidth(1);
        canvas.ellipse(offset.dx, offset.dy, size.width, size.height);
        canvas.stroke();
      }
      return;
    }
    if (fill != null) {
      canvas.fillRect(offset.dx, offset.dy, size.width, size.height, fill!);
    }
    if (stroke != null) {
      canvas.strokeRect(offset.dx, offset.dy, size.width, size.height, stroke!);
    }
  }
}

/// Empty bordered box.
class Placeholder extends Widget {
  /// Placeholder API.
  const Placeholder({
    this.fallbackWidth = 400,
    this.fallbackHeight = 80,
    this.color = '455A64',
  });

  /// fallbackWidth API.
  final double fallbackWidth;

  /// fallbackHeight API.
  final double fallbackHeight;

  /// color API.
  final String color;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    return _PlaceholderBox(
      constraints.constrain(PwSize(fallbackWidth, fallbackHeight)),
      color,
    );
  }
}

class _PlaceholderBox extends PwBox {
  _PlaceholderBox(super.size, this.color);

  final String color;

  @override
  void paint(Context context, PwOffset offset) {
    final PdfCanvas? canvas = context.canvas;
    if (canvas == null) {
      return;
    }
    canvas.endText();
    canvas.setStrokeColor(color);
    canvas.setLineWidth(0.8);
    canvas.setDash(const <double>[3, 3]);
    canvas.rect(offset.dx, offset.dy, size.width, size.height);
    canvas.stroke();
    canvas.moveTo(offset.dx, offset.dy);
    canvas.lineTo(offset.dx + size.width, offset.dy + size.height);
    canvas.moveTo(offset.dx + size.width, offset.dy);
    canvas.lineTo(offset.dx, offset.dy + size.height);
    canvas.stroke();
    canvas.resetDash();
  }
}

/// Checkbox mark (drawn; not an AcroForm field unless [acroForm] is set).
class Checkbox extends Widget {
  /// Checkbox API.
  const Checkbox({
    this.value = false,
    this.name = '',
    this.tristate = false,
    this.size = 12,
    this.acroForm = false,
  });

  /// value API.
  final bool value;

  /// name API.
  final String name;

  /// tristate API.
  final bool tristate;

  /// size API.
  final double size;

  /// When true, [Document.save] writes a real `/Btn` field.
  final bool acroForm;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    return _CheckboxBox(PwSize(size, size), value, name, acroForm);
  }
}

class _CheckboxBox extends PwBox {
  _CheckboxBox(super.size, this.value, this.name, this.acroForm);

  final bool value;
  final String name;
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
        ),
      );
    }
    final PdfCanvas? canvas = context.canvas;
    if (canvas == null) {
      return;
    }
    canvas.endText();
    canvas.setStrokeColor('37474F');
    canvas.setLineWidth(0.9);
    canvas.roundedRect(offset.dx, offset.dy, size.width, size.height, 1.5);
    canvas.stroke();
    if (value) {
      canvas.setStrokeColor('1B5E20');
      canvas.setLineWidth(1.4);
      canvas.moveTo(offset.dx + 2, offset.dy + size.height * 0.55);
      canvas.lineTo(offset.dx + size.width * 0.4, offset.dy + size.height - 2);
      canvas.lineTo(offset.dx + size.width - 2, offset.dy + 2.5);
      canvas.stroke();
    }
  }
}

/// Underlined value (form-like, not an AcroForm field unless [acroForm]).
class TextField extends Widget {
  /// TextField API.
  const TextField({
    this.name = '',
    this.value = '',
    this.maxLength,
    this.width = 160,
    this.acroForm = false,
  });

  /// name API.
  final String name;

  /// value API.
  final String value;

  /// maxLength API.
  final int? maxLength;

  /// width API.
  final double width;

  /// When true, [Document.save] writes a real `/Tx` field.
  final bool acroForm;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    return _TextFieldBox(
      Container(
        width: width,
        padding: const EdgeInsets.only(bottom: 2),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: '78909C', width: 0.8)),
        ),
        child: Text(value.isEmpty ? name : value),
      ).layout(context, constraints),
      name: name,
      value: value,
      acroForm: acroForm,
      width: width,
    );
  }
}

class _TextFieldBox extends PwBox {
  _TextFieldBox(
    PwBox inner, {
    required this.name,
    required this.value,
    required this.acroForm,
    required this.width,
  }) : _inner = inner,
       super(inner.size);

  final PwBox _inner;
  final String name;
  final String value;
  final bool acroForm;
  final double width;

  @override
  void paint(Context context, PwOffset offset) {
    if (acroForm) {
      context.registerAcroField(
        PdfAcroField(
          name: name,
          type: 'Tx',
          x: offset.dx,
          y: offset.dy,
          width: width < 1 ? size.width : width,
          height: size.height < 12 ? 16 : size.height,
          pageIndex: context.pageNumber - 1,
          value: value,
        ),
      );
    }
    _inner.paint(context, offset);
  }
}

/// Combo box. Drawn label, real `/Ch` field when [acroForm] is set.
class ChoiceField extends Widget {
  /// ChoiceField API.
  const ChoiceField({
    required this.name,
    this.value = '',
    this.options = const <String>[],
    this.width = 160,
    this.acroForm = true,
  });

  /// name API.
  final String name;

  /// value API.
  final String value;

  /// options API.
  final List<String> options;

  /// width API.
  final double width;

  /// acroForm API.
  final bool acroForm;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    return _ChoiceBox(
      Container(
        width: width,
        padding: const EdgeInsets.only(bottom: 2),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: '78909C', width: 0.8)),
        ),
        child: Text(value.isEmpty ? name : value),
      ).layout(context, constraints),
      name: name,
      value: value,
      options: options,
      acroForm: acroForm,
      width: width,
    );
  }
}

class _ChoiceBox extends PwBox {
  _ChoiceBox(
    PwBox inner, {
    required this.name,
    required this.value,
    required this.options,
    required this.acroForm,
    required this.width,
  }) : _inner = inner,
       super(inner.size);

  final PwBox _inner;
  final String name;
  final String value;
  final List<String> options;
  final bool acroForm;
  final double width;

  @override
  void paint(Context context, PwOffset offset) {
    if (acroForm) {
      context.registerAcroField(
        PdfAcroField(
          name: name,
          type: 'Ch',
          x: offset.dx,
          y: offset.dy,
          width: width < 1 ? size.width : width,
          height: size.height < 12 ? 16 : size.height,
          pageIndex: context.pageNumber - 1,
          value: value,
          options: options,
        ),
      );
    }
    _inner.paint(context, offset);
  }
}
