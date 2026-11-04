/// Flex, wrap, stack, grid, and inherited-direction widgets.
library;

import 'pw_box.dart';
import 'pw_core.dart';
import 'pw_style.dart';
import 'pw_text.dart';
import 'pw_types.dart';

/// Flex child of [Row] / [Column].
class Flexible extends Widget {
  /// Flexible API.
  const Flexible({this.flex = 1, this.fit = FlexFit.loose, required this.child});

  /// flex API.
  final int flex;

  /// fit API.
  final FlexFit fit;

  /// child API.
  final Widget child;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    return child.layout(context, constraints);
  }
}

/// Same constructor as Flutter [Expanded].
class Expanded extends Flexible {
  /// Expanded API.
  const Expanded({super.flex, required super.child}) : super(fit: FlexFit.tight);
}

/// Same constructor as Flutter [Spacer].
class Spacer extends Flexible {
  /// Spacer API.
  const Spacer({super.flex})
    : super(child: const SizedBox.shrink(), fit: FlexFit.tight);
}

/// How much space a [Flex] should occupy on its main axis.
enum MainAxisSize { min, max }

/// Row or column from [direction].
class Flex extends Widget {
  /// Flex API.
  const Flex({
    required this.direction,
    this.children = const <Widget>[],
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.mainAxisSize = MainAxisSize.max,
  });

  /// direction API.
  final Axis direction;

  /// children API.
  final List<Widget> children;

  /// mainAxisAlignment API.
  final MainAxisAlignment mainAxisAlignment;

  /// crossAxisAlignment API.
  final CrossAxisAlignment crossAxisAlignment;

  /// mainAxisSize API.
  final MainAxisSize mainAxisSize;

  /// Vertical columns flow as separate MultiPage children so a nested [Table] can span.
  @override
  List<Widget>? get flowChildren {
    if (direction != Axis.vertical) {
      return null;
    }
    for (final Widget child in children) {
      if (child is Flexible) {
        return null;
      }
    }
    return children;
  }

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    final bool horiz = direction == Axis.horizontal;
    final double maxMain = horiz ? constraints.maxWidth : constraints.maxHeight;
    final double maxCross = horiz ? constraints.maxHeight : constraints.maxWidth;
    final bool mainBounded = horiz
        ? constraints.hasBoundedWidth
        : constraints.hasBoundedHeight;
    final List<PwBox?> boxes = List<PwBox?>.filled(children.length, null);
    var allocated = 0.0;
    var totalFlex = 0;
    for (int i = 0; i < children.length; i++) {
      final Widget raw = children[i];
      final int flex = raw is Flexible ? raw.flex : 0;
      if (flex > 0) {
        totalFlex += flex;
        continue;
      }
      final Widget inner = raw is Flexible ? raw.child : raw;
      final BoxConstraints childCs = horiz
          ? BoxConstraints(
              maxWidth: mainBounded ? (maxMain - allocated).clamp(0, maxMain) : double.infinity,
              maxHeight: maxCross,
              minHeight: crossAxisAlignment == CrossAxisAlignment.stretch
                  ? (maxCross.isFinite ? maxCross : 0)
                  : 0,
            )
          : BoxConstraints(
              maxWidth: maxCross,
              minWidth: crossAxisAlignment == CrossAxisAlignment.stretch
                  ? (maxCross.isFinite ? maxCross : 0)
                  : 0,
              maxHeight: mainBounded
                  ? (maxMain - allocated).clamp(0, maxMain)
                  : double.infinity,
            );
      final PwBox box = inner.layout(context, childCs);
      boxes[i] = box;
      allocated += horiz ? box.size.width : box.size.height;
    }
    final double flexSpace = mainBounded
        ? (maxMain - allocated).clamp(0, maxMain)
        : 0;
    for (int i = 0; i < children.length; i++) {
      if (boxes[i] != null) {
        continue;
      }
      final Widget raw = children[i];
      final int flex = raw is Flexible ? raw.flex : 1;
      final FlexFit fit = raw is Flexible ? raw.fit : FlexFit.loose;
      final Widget inner = raw is Flexible ? raw.child : raw;
      final double share = totalFlex <= 0 ? 0 : flexSpace * flex / totalFlex;
      final BoxConstraints childCs = horiz
          ? BoxConstraints(
              minWidth: fit == FlexFit.tight ? share : 0,
              maxWidth: share,
              maxHeight: maxCross,
              minHeight: crossAxisAlignment == CrossAxisAlignment.stretch &&
                      maxCross.isFinite
                  ? maxCross
                  : 0,
            )
          : BoxConstraints(
              minHeight: fit == FlexFit.tight ? share : 0,
              maxHeight: share,
              maxWidth: maxCross,
              minWidth: crossAxisAlignment == CrossAxisAlignment.stretch &&
                      maxCross.isFinite
                  ? maxCross
                  : 0,
            );
      final PwBox box = inner.layout(context, childCs);
      boxes[i] = box;
      allocated += horiz ? box.size.width : box.size.height;
    }
    var cross = 0.0;
    for (final PwBox? box in boxes) {
      if (box == null) {
        continue;
      }
      final double c = horiz ? box.size.height : box.size.width;
      if (c > cross) {
        cross = c;
      }
    }
    if (crossAxisAlignment == CrossAxisAlignment.stretch && maxCross.isFinite) {
      cross = maxCross;
    }
    final double main = mainAxisSize == MainAxisSize.max &&
            mainBounded &&
            allocated < maxMain
        ? maxMain
        : allocated;
    final PwSize size = constraints.constrain(
      horiz ? PwSize(main, cross) : PwSize(cross, main),
    );
    final List<(PwBox, PwOffset)> placed = <(PwBox, PwOffset)>[];
    final List<double> mains = <double>[
      for (final PwBox? box in boxes)
        box == null ? 0 : (horiz ? box.size.width : box.size.height),
    ];
    var cursor = 0.0;
    var gap = 0.0;
    final double leftover = (main - allocated).clamp(0, double.infinity);
    final bool reverseMain =
        horiz && context.textDirection == TextDirection.rtl;
    switch (mainAxisAlignment) {
      case MainAxisAlignment.start:
        cursor = reverseMain ? leftover : 0;
      case MainAxisAlignment.end:
        cursor = reverseMain ? 0 : leftover;
      case MainAxisAlignment.center:
        cursor = leftover / 2;
      case MainAxisAlignment.spaceBetween:
        gap = boxes.length > 1 ? leftover / (boxes.length - 1) : 0;
      case MainAxisAlignment.spaceAround:
        gap = boxes.isEmpty ? 0 : leftover / boxes.length;
        cursor = gap / 2;
      case MainAxisAlignment.spaceEvenly:
        gap = leftover / (boxes.length + 1);
        cursor = gap;
    }
    final List<int> order = <int>[
      for (int i = 0; i < boxes.length; i++)
        reverseMain ? boxes.length - 1 - i : i,
    ];
    for (final int i in order) {
      final PwBox box = boxes[i]!;
      final double crossOff = switch (crossAxisAlignment) {
        CrossAxisAlignment.start => _crossStart(
          horiz: horiz,
          rtl: context.textDirection == TextDirection.rtl,
          size: size,
          box: box,
        ),
        CrossAxisAlignment.end => _crossEnd(
          horiz: horiz,
          rtl: context.textDirection == TextDirection.rtl,
          size: size,
          box: box,
        ),
        CrossAxisAlignment.center => horiz
            ? (size.height - box.size.height) / 2
            : (size.width - box.size.width) / 2,
        CrossAxisAlignment.stretch => 0,
      };
      placed.add((
        box,
        horiz ? PwOffset(cursor, crossOff) : PwOffset(crossOff, cursor),
      ));
      cursor += mains[i] + gap;
    }
    return GroupBox(size, placed);
  }
}

double _crossStart({
  required bool horiz,
  required bool rtl,
  required PwSize size,
  required PwBox box,
}) {
  if (horiz || !rtl) {
    return 0;
  }
  return size.width - box.size.width;
}

double _crossEnd({
  required bool horiz,
  required bool rtl,
  required PwSize size,
  required PwBox box,
}) {
  if (horiz) {
    return size.height - box.size.height;
  }
  if (rtl) {
    return 0;
  }
  return size.width - box.size.width;
}

/// Horizontal flex.
class Row extends Flex {
  /// Row API.
  const Row({
    super.children,
    super.mainAxisAlignment,
    super.crossAxisAlignment = CrossAxisAlignment.center,
    super.mainAxisSize,
  }) : super(direction: Axis.horizontal);
}

/// Vertical flex.
class Column extends Flex {
  /// Column API.
  const Column({
    super.children,
    super.mainAxisAlignment,
    super.crossAxisAlignment = CrossAxisAlignment.start,
    super.mainAxisSize,
  }) : super(direction: Axis.vertical);
}

/// Flow children onto the next line when they overflow.
class Wrap extends Widget {
  /// Wrap API.
  const Wrap({
    this.children = const <Widget>[],
    this.spacing = 6,
    this.runSpacing = 6,
    this.alignment = WrapAlignment.start,
  });

  /// children API.
  final List<Widget> children;

  /// spacing API.
  final double spacing;

  /// runSpacing API.
  final double runSpacing;

  /// alignment API.
  final WrapAlignment alignment;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    final double maxW = constraints.hasBoundedWidth ? constraints.maxWidth : 400;
    final List<List<(PwBox, double)>> runs = <List<(PwBox, double)>>[];
    var run = <(PwBox, double)>[];
    var x = 0.0;
    var rowH = 0.0;
    void pushRun() {
      if (run.isEmpty) {
        return;
      }
      runs.add(run);
      run = <(PwBox, double)>[];
      x = 0;
      rowH = 0;
    }

    for (final Widget child in children) {
      final PwBox box = child.layout(
        context,
        BoxConstraints(maxWidth: maxW, maxHeight: constraints.maxHeight),
      );
      if (x > 0 && x + box.size.width > maxW) {
        pushRun();
      }
      run.add((box, x));
      x += box.size.width + spacing;
      if (box.size.height > rowH) {
        rowH = box.size.height;
      }
    }
    pushRun();

    final List<(PwBox, PwOffset)> placed = <(PwBox, PwOffset)>[];
    var y = 0.0;
    var maxUsedW = 0.0;
    for (int r = 0; r < runs.length; r++) {
      final List<(PwBox, double)> line = runs[r];
      var lineW = 0.0;
      var lineH = 0.0;
      for (final (PwBox box, double _) in line) {
        lineW += box.size.width;
        if (box.size.height > lineH) {
          lineH = box.size.height;
        }
      }
      if (line.length > 1) {
        lineW += spacing * (line.length - 1);
      }
      final double slack = (maxW - lineW).clamp(0, double.infinity);
      final double shift = switch (alignment) {
        WrapAlignment.end => slack,
        WrapAlignment.center => slack / 2,
        WrapAlignment.start => 0,
      };
      for (final (PwBox box, double localX) in line) {
        placed.add((box, PwOffset(localX + shift, y)));
      }
      if (lineW + shift > maxUsedW) {
        maxUsedW = lineW + shift;
      }
      y += lineH;
      if (r < runs.length - 1) {
        y += runSpacing;
      }
    }
    return GroupBox(
      constraints.constrain(PwSize(maxUsedW.clamp(0, maxW), y)),
      placed,
    );
  }
}

/// How a [Wrap] run is packed.
enum WrapAlignment { start, end, center }

/// Stack of children. [Positioned] pins a child.
class Stack extends Widget {
  /// Stack API.
  const Stack({
    this.children = const <Widget>[],
    this.alignment = Alignment.topLeft,
    this.fit = StackFit.loose,
  });

  /// children API.
  final List<Widget> children;

  /// alignment API.
  final AlignmentGeometry alignment;

  /// fit API.
  final StackFit fit;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    final List<(PwBox, PwOffset, Positioned?, double?, double?)> laid =
        <(PwBox, PwOffset, Positioned?, double?, double?)>[];
    var w = 0.0;
    var h = 0.0;
    final PwSize stackSizeHint = constraints.constrain(
      PwSize(
        constraints.hasBoundedWidth ? constraints.maxWidth : 0,
        constraints.hasBoundedHeight ? constraints.maxHeight : 0,
      ),
    );
    for (final Widget child in children) {
      final Positioned? pos = child is Positioned ? child : null;
      final ({double? left, double? right}) pin = pos == null
          ? (left: null, right: null)
          : pos.horizontal(context.textDirection);
      final Widget inner = pos?.child ?? child;
      BoxConstraints childCs = constraints.loosen();
      if (pos != null) {
        double? tw = pos.width;
        double? th = pos.height;
        if (tw == null && pin.left != null && pin.right != null) {
          tw = (stackSizeHint.width - pin.left! - pin.right!).clamp(
            0,
            double.infinity,
          );
        }
        if (th == null && pos.top != null && pos.bottom != null) {
          th = (stackSizeHint.height - pos.top! - pos.bottom!).clamp(
            0,
            double.infinity,
          );
        }
        if (tw != null || th != null) {
          childCs = BoxConstraints.tightFor(width: tw, height: th);
        }
      }
      final PwBox box = inner.layout(context, childCs);
      if (box.size.width > w) {
        w = box.size.width;
      }
      if (box.size.height > h) {
        h = box.size.height;
      }
      laid.add((box, PwOffset.zero, pos, pin.left, pin.right));
    }
    if (fit == StackFit.expand && constraints.hasBoundedWidth) {
      w = constraints.maxWidth;
    }
    if (fit == StackFit.expand && constraints.hasBoundedHeight) {
      h = constraints.maxHeight;
    }
    // Grow stack to fit positioned right/bottom pins.
    for (final (PwBox box, PwOffset _, Positioned? pos, double? left, double? right)
        in laid) {
      if (pos == null) {
        continue;
      }
      if (left != null) {
        final double need = left + box.size.width + (right ?? 0);
        if (need > w) {
          w = need;
        }
      }
      if (pos.top != null) {
        final double need = pos.top! + box.size.height + (pos.bottom ?? 0);
        if (need > h) {
          h = need;
        }
      }
    }
    final PwSize size = constraints.constrain(PwSize(w, h));
    final List<(PwBox, PwOffset)> placed = <(PwBox, PwOffset)>[];
    for (final (PwBox box, PwOffset _, Positioned? pos, double? left, double? right)
        in laid) {
      if (pos != null) {
        final double dx =
            left ??
            (right != null ? size.width - box.size.width - right : 0.0);
        final double dy =
            pos.top ??
            (pos.bottom != null
                ? size.height - box.size.height - pos.bottom!
                : 0.0);
        placed.add((box, PwOffset(dx, dy)));
      } else {
        placed.add((
          box,
          alignment.resolve(context.textDirection).alongOffset(size, box.size),
        ));
      }
    }
    return GroupBox(size, placed);
  }
}

/// How a [Stack] sizes itself.
enum StackFit { loose, expand, passthrough }

/// Absolutely positioned [Stack] child.
class Positioned extends Widget {
  /// Positioned API.
  const Positioned({
    this.left,
    this.top,
    this.right,
    this.bottom,
    this.width,
    this.height,
    required this.child,
  }) : start = null,
       end = null,
       directional = false;

  /// Pin with [start]/[end], resolved from [Context.textDirection].
  const Positioned.directional({
    this.start,
    this.top,
    this.end,
    this.bottom,
    this.width,
    this.height,
    required this.child,
  }) : left = null,
       right = null,
       directional = true;

  /// fill API.
  const Positioned.fill({required this.child})
    : left = 0,
      top = 0,
      right = 0,
      bottom = 0,
      width = null,
      height = null,
      start = null,
      end = null,
      directional = false;

  /// left API.
  final double? left;

  /// top API.
  final double? top;

  /// right API.
  final double? right;

  /// bottom API.
  final double? bottom;

  /// width API.
  final double? width;

  /// height API.
  final double? height;

  /// start API. Leading edge when [directional] is true.
  final double? start;

  /// end API. Trailing edge when [directional] is true.
  final double? end;

  /// True when [start]/[end] replace [left]/[right].
  final bool directional;

  /// child API.
  final Widget child;

  /// Physical left/right for [direction].
  ({double? left, double? right}) horizontal(TextDirection direction) {
    if (!directional) {
      return (left: left, right: right);
    }
    final bool rtl = direction == TextDirection.rtl;
    return (left: rtl ? end : start, right: rtl ? start : end);
  }

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    return child.layout(
      context,
      constraints.tighten(width: width, height: height),
    );
  }
}

/// Non-scrolling column (PDF has no viewport). Same children as Flutter [ListView].
class ListView extends Widget {
  /// ListView API.
  const ListView({this.children = const <Widget>[], this.itemExtent});

  /// builder API.
  factory ListView.builder({
    required int itemCount,
    required Widget Function(Context context, int index) itemBuilder,
    double? itemExtent,
  }) {
    return _ListViewBuilder(itemCount, itemBuilder, itemExtent);
  }

  /// children API.
  final List<Widget> children;

  /// itemExtent API.
  final double? itemExtent;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    if (itemExtent != null) {
      return Column(
        children: <Widget>[
          for (final Widget child in children)
            SizedBox(height: itemExtent, child: child),
        ],
      ).layout(context, constraints);
    }
    return Column(children: children).layout(context, constraints);
  }
}

class _ListViewBuilder extends ListView {
  _ListViewBuilder(this.itemCount, this.itemBuilder, double? itemExtent)
    : super(itemExtent: itemExtent);

  final int itemCount;
  final Widget Function(Context context, int index) itemBuilder;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    return Column(
      children: <Widget>[
        for (int i = 0; i < itemCount; i++) itemBuilder(context, i),
      ],
    ).layout(context, constraints);
  }
}

/// Fixed-count grid.
class GridView extends Widget {
  /// GridView API.
  const GridView({
    this.crossAxisCount = 2,
    this.children = const <Widget>[],
    this.childAspectRatio = 1,
    this.crossAxisSpacing = 8,
    this.mainAxisSpacing = 8,
  });

  /// count API.
  factory GridView.count({
    required int crossAxisCount,
    required List<Widget> children,
    double childAspectRatio = 1,
    double crossAxisSpacing = 8,
    double mainAxisSpacing = 8,
  }) {
    return GridView(
      crossAxisCount: crossAxisCount,
      children: children,
      childAspectRatio: childAspectRatio,
      crossAxisSpacing: crossAxisSpacing,
      mainAxisSpacing: mainAxisSpacing,
    );
  }

  /// crossAxisCount API.
  final int crossAxisCount;

  /// children API.
  final List<Widget> children;

  /// childAspectRatio API.
  final double childAspectRatio;

  /// crossAxisSpacing API.
  final double crossAxisSpacing;

  /// mainAxisSpacing API.
  final double mainAxisSpacing;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    final int cols = crossAxisCount < 1 ? 1 : crossAxisCount;
    final double maxW = constraints.hasBoundedWidth ? constraints.maxWidth : 400;
    final double cellW =
        (maxW - crossAxisSpacing * (cols - 1)).clamp(1, maxW) / cols;
    final double cellH = cellW / childAspectRatio;
    final List<(PwBox, PwOffset)> placed = <(PwBox, PwOffset)>[];
    for (int i = 0; i < children.length; i++) {
      final int col = i % cols;
      final int row = i ~/ cols;
      final PwBox box = children[i].layout(
        context,
        BoxConstraints.tight(PwSize(cellW, cellH)),
      );
      placed.add((
        box,
        PwOffset(
          col * (cellW + crossAxisSpacing),
          row * (cellH + mainAxisSpacing),
        ),
      ));
    }
    final int rows = children.isEmpty ? 0 : ((children.length + cols - 1) ~/ cols);
    final double h = rows == 0
        ? 0
        : rows * cellH + (rows - 1) * mainAxisSpacing;
    return GroupBox(constraints.constrain(PwSize(maxW, h)), placed);
  }
}

/// Rebuilds [builder] at layout time.
class Builder extends Widget {
  /// Builder API.
  const Builder({required this.builder});

  /// builder API.
  final WidgetBuilder builder;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    return builder(context).layout(context, constraints);
  }
}

/// Overrides reading direction.
class Directionality extends Widget {
  /// Directionality API.
  const Directionality({required this.textDirection, required this.child});

  /// textDirection API.
  final TextDirection textDirection;

  /// child API.
  final Widget child;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    return child.layout(
      context.copyWith(textDirection: textDirection),
      constraints,
    );
  }
}

/// Overrides [ThemeData] for [child].
class Theme extends Widget {
  /// Theme API.
  const Theme({required this.data, required this.child});

  /// data API.
  final ThemeData data;

  /// child API.
  final Widget child;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    return child.layout(context.copyWith(theme: data), constraints);
  }
}

/// Keep-together hint. MultiPage already avoids splitting a single box.
class Inseparable extends Widget {
  /// Inseparable API.
  const Inseparable({required this.child, this.canSpan = false});

  /// child API.
  final Widget child;

  /// canSpan API.
  final bool canSpan;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    return child.layout(context, constraints);
  }
}

/// Bookmark on the first produced box.
class Anchor extends Widget {
  /// Anchor API.
  const Anchor({required this.name, this.child});

  /// name API.
  final String name;

  /// child API.
  final Widget? child;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    context.registerAnchor(name);
    final Widget? kid = child;
    if (kid == null) {
      return EmptyBox();
    }
    return kid.layout(context, constraints);
  }
}

/// Page footer row: leading · title · trailing.
class Footer extends Widget {
  /// Footer API.
  const Footer({this.leading, this.title, this.trailing});

  /// leading API.
  final Widget? leading;

  /// title API.
  final Widget? title;

  /// trailing API.
  final Widget? trailing;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: <Widget>[
          leading ?? const SizedBox.shrink(),
          const Spacer(),
          title ??
              Text(
                '${context.pageNumber} / ${context.pagesCount}',
                style: const TextStyle(fontSize: 9, color: '607D8B'),
              ),
          const Spacer(),
          trailing ?? const SizedBox.shrink(),
        ],
      ),
    ).layout(context, constraints);
  }
}
