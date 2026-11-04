import 'pml_presentation.dart';

/// Align selected shapes to a shared edge or center.
enum PmlAlignAxis { left, center, right, top, middle, bottom }

/// Align / distribute / section helpers for a deck.
abstract final class PmlArrange {
  /// align API.
  static void align(List<PmlShape> shapes, PmlAlignAxis axis) {
    if (shapes.length < 2) {
      return;
    }
    switch (axis) {
      case PmlAlignAxis.left:
        final int edge = shapes
            .map((PmlShape s) => s.transform.x)
            .reduce((int a, int b) => a < b ? a : b);
        for (final PmlShape shape in shapes) {
          shape.transform = PmlTransform(
            x: edge,
            y: shape.transform.y,
            cx: shape.transform.cx,
            cy: shape.transform.cy,
            rot: shape.transform.rot,
          );
        }
      case PmlAlignAxis.right:
        final int edge = shapes
            .map((PmlShape s) => s.transform.x + s.transform.cx)
            .reduce((int a, int b) => a > b ? a : b);
        for (final PmlShape shape in shapes) {
          shape.transform = PmlTransform(
            x: edge - shape.transform.cx,
            y: shape.transform.y,
            cx: shape.transform.cx,
            cy: shape.transform.cy,
            rot: shape.transform.rot,
          );
        }
      case PmlAlignAxis.center:
        final int minX = shapes
            .map((PmlShape s) => s.transform.x)
            .reduce((int a, int b) => a < b ? a : b);
        final int maxX = shapes
            .map((PmlShape s) => s.transform.x + s.transform.cx)
            .reduce((int a, int b) => a > b ? a : b);
        final int mid = (minX + maxX) ~/ 2;
        for (final PmlShape shape in shapes) {
          shape.transform = PmlTransform(
            x: mid - shape.transform.cx ~/ 2,
            y: shape.transform.y,
            cx: shape.transform.cx,
            cy: shape.transform.cy,
            rot: shape.transform.rot,
          );
        }
      case PmlAlignAxis.top:
        final int edge = shapes
            .map((PmlShape s) => s.transform.y)
            .reduce((int a, int b) => a < b ? a : b);
        for (final PmlShape shape in shapes) {
          shape.transform = PmlTransform(
            x: shape.transform.x,
            y: edge,
            cx: shape.transform.cx,
            cy: shape.transform.cy,
            rot: shape.transform.rot,
          );
        }
      case PmlAlignAxis.bottom:
        final int edge = shapes
            .map((PmlShape s) => s.transform.y + s.transform.cy)
            .reduce((int a, int b) => a > b ? a : b);
        for (final PmlShape shape in shapes) {
          shape.transform = PmlTransform(
            x: shape.transform.x,
            y: edge - shape.transform.cy,
            cx: shape.transform.cx,
            cy: shape.transform.cy,
            rot: shape.transform.rot,
          );
        }
      case PmlAlignAxis.middle:
        final int minY = shapes
            .map((PmlShape s) => s.transform.y)
            .reduce((int a, int b) => a < b ? a : b);
        final int maxY = shapes
            .map((PmlShape s) => s.transform.y + s.transform.cy)
            .reduce((int a, int b) => a > b ? a : b);
        final int mid = (minY + maxY) ~/ 2;
        for (final PmlShape shape in shapes) {
          shape.transform = PmlTransform(
            x: shape.transform.x,
            y: mid - shape.transform.cy ~/ 2,
            cx: shape.transform.cx,
            cy: shape.transform.cy,
            rot: shape.transform.rot,
          );
        }
    }
  }

  /// distribute API.
  static void distribute(List<PmlShape> shapes, {required bool horizontal}) {
    if (shapes.length < 3) {
      return;
    }
    final List<PmlShape> ordered = List<PmlShape>.from(shapes)
      ..sort(
        (PmlShape a, PmlShape b) => horizontal
            ? a.transform.x.compareTo(b.transform.x)
            : a.transform.y.compareTo(b.transform.y),
      );
    final PmlShape first = ordered.first;
    final PmlShape last = ordered.last;
    if (horizontal) {
      final int span =
          (last.transform.x + last.transform.cx) - first.transform.x;
      var used = 0;
      for (final PmlShape shape in ordered) {
        used += shape.transform.cx;
      }
      final int gap = ((span - used) / (ordered.length - 1)).round();
      var cursor = first.transform.x;
      for (final PmlShape shape in ordered) {
        shape.transform = PmlTransform(
          x: cursor,
          y: shape.transform.y,
          cx: shape.transform.cx,
          cy: shape.transform.cy,
          rot: shape.transform.rot,
        );
        cursor += shape.transform.cx + gap;
      }
    } else {
      final int span =
          (last.transform.y + last.transform.cy) - first.transform.y;
      var used = 0;
      for (final PmlShape shape in ordered) {
        used += shape.transform.cy;
      }
      final int gap = ((span - used) / (ordered.length - 1)).round();
      var cursor = first.transform.y;
      for (final PmlShape shape in ordered) {
        shape.transform = PmlTransform(
          x: shape.transform.x,
          y: cursor,
          cx: shape.transform.cx,
          cy: shape.transform.cy,
          rot: shape.transform.rot,
        );
        cursor += shape.transform.cy + gap;
      }
    }
  }

  /// group API.
  static int group(List<PmlShape> shapes) {
    var id = 1;
    for (final PmlShape shape in shapes) {
      final int? existing = shape.groupId;
      if (existing != null && existing >= id) {
        id = existing + 1;
      }
    }
    for (final PmlShape shape in shapes) {
      shape.groupId = id;
    }
    return id;
  }

  /// ungroup API.
  static void ungroup(List<PmlShape> shapes) {
    for (final PmlShape shape in shapes) {
      shape.groupId = null;
    }
  }

  /// mates API.
  static List<PmlShape> mates(List<PmlShape> all, PmlShape shape) {
    final int? id = shape.groupId;
    if (id == null) {
      return <PmlShape>[shape];
    }
    return <PmlShape>[
      for (final PmlShape item in all)
        if (item.groupId == id) item,
    ];
  }
}

/// Named slide sections in the sorter.
abstract final class PmlSections {
  /// add API.
  static PmlSection add(
    PmlPresentation presentation, {
    required String name,
    required int startIndex,
  }) {
    final PmlSection section = PmlSection(
      name: name,
      startIndex: startIndex.clamp(0, presentation.slides.length),
    );
    presentation.sections.add(section);
    presentation.sections.sort(
      (PmlSection a, PmlSection b) => a.startIndex.compareTo(b.startIndex),
    );
    return section;
  }

  /// nameOf API.
  static String? nameOf(PmlPresentation presentation, int slideIndex) {
    PmlSection? current;
    for (final PmlSection section in presentation.sections) {
      if (section.startIndex <= slideIndex) {
        current = section;
      }
    }
    return current?.name;
  }

  /// remove API.
  static bool remove(PmlPresentation presentation, String name) {
    final int index = presentation.sections.indexWhere(
      (PmlSection s) => s.name == name,
    );
    if (index < 0) {
      return false;
    }
    presentation.sections.removeAt(index);
    return true;
  }
}
