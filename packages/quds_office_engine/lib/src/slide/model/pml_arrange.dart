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

  /// Equalize gaps along one axis while keeping the first and last positions.
  ///
  /// Every cumulative gap is rounded once to an EMU. Rounding one gap and then
  /// repeatedly adding it would move the final endpoint and drift on retries.
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
    final int origin = horizontal ? first.transform.x : first.transform.y;
    final int end = horizontal
        ? last.transform.x + last.transform.cx
        : last.transform.y + last.transform.cy;
    final int used = ordered.fold<int>(
      0,
      (sum, shape) =>
          sum + (horizontal ? shape.transform.cx : shape.transform.cy),
    );
    final int space = end - origin - used;
    var cursor = origin;
    for (int index = 0; index < ordered.length; index++) {
      final PmlShape shape = ordered[index];
      final int position =
          cursor + _roundedRatio(space * index, ordered.length - 1);
      shape.transform = PmlTransform(
        x: horizontal ? position : shape.transform.x,
        y: horizontal ? shape.transform.y : position,
        cx: shape.transform.cx,
        cy: shape.transform.cy,
        rot: shape.transform.rot,
      );
      cursor += horizontal ? shape.transform.cx : shape.transform.cy;
    }
  }

  static int _roundedRatio(int numerator, int denominator) {
    final int magnitude = numerator.abs();
    final int rounded =
        magnitude ~/ denominator +
        ((magnitude % denominator) * 2 >= denominator ? 1 : 0);
    return numerator < 0 ? -rounded : rounded;
  }

  /// Group shapes with an identity unused by the supplied drawing scope.
  ///
  /// When grouping a selection, pass the full slide in [allShapes]. The flat
  /// model requires each group to occupy a consecutive run in drawing order;
  /// unsupported changes reject before mutating any membership.
  static int group(List<PmlShape> shapes, {List<PmlShape>? allShapes}) {
    final List<PmlShape> scope = allShapes ?? shapes;
    final int? existing = shapes.isEmpty ? null : shapes.first.groupId;
    if (existing != null &&
        shapes.every((shape) => shape.groupId == existing) &&
        scope.where((shape) => shape.groupId == existing).length ==
            shapes.length) {
      _setGroup(shapes, scope, existing);
      return existing;
    }
    var id = 1;
    for (final PmlShape shape in scope) {
      final int? existing = shape.groupId;
      if (existing != null && existing >= id) {
        id = existing + 1;
      }
    }
    _setGroup(shapes, scope, id);
    return id;
  }

  /// Remove group membership, rejecting splits when [allShapes] is supplied.
  static void ungroup(List<PmlShape> shapes, {List<PmlShape>? allShapes}) {
    _setGroup(shapes, allShapes ?? shapes, null);
  }

  static void _setGroup(List<PmlShape> shapes, List<PmlShape> scope, int? id) {
    final Set<PmlShape> selection = Set<PmlShape>.identity()..addAll(shapes);
    if (selection.length != shapes.length || !selection.every(scope.contains)) {
      throw ArgumentError(
        'Group members must be unique shapes in the drawing scope.',
      );
    }
    _validateGroupKeys([
      for (final shape in scope) selection.contains(shape) ? id : shape.groupId,
    ]);
    for (final PmlShape shape in shapes) {
      shape.groupId = id;
    }
  }

  /// Validate the flat grouping model before serializing or editing it.
  ///
  /// Splitting a group into multiple native groups would silently change its
  /// membership; joining it would change drawing order. Neither is implicit.
  static void validateGrouping(List<PmlShape> shapes) =>
      _validateGroupKeys(shapes.map((shape) => shape.groupId));

  static void _validateGroupKeys(Iterable<int?> keys) {
    final Set<int> closed = <int>{};
    int? current;
    for (final int? id in keys) {
      if (id == current) {
        continue;
      }
      if (id != null && closed.contains(id)) {
        throw StateError(
          'A flat slide group must be consecutive in drawing order.',
        );
      }
      if (current != null) {
        closed.add(current);
      }
      current = id;
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
  /// Validate a consecutive section partition before changing any deck state.
  static void validate(PmlPresentation presentation) {
    if (presentation.sectionSource?.issue case final String issue) {
      throw StateError('Cannot reorder native presentation sections: $issue');
    }
    final Set<int> slideIds = <int>{};
    for (final PmlSlide slide in presentation.slides) {
      if (!slideIds.add(slide.id)) {
        throw StateError('Slide IDs must be unique before reordering.');
      }
      if (presentation.sections.isNotEmpty &&
          slide.sourcePartUri != null &&
          !slide.sourcePartUri!.startsWith('/')) {
        throw StateError(
          'Section-aware reorder requires internal slide parts.',
        );
      }
    }
    var previous = 0;
    final Set<String> ids = <String>{};
    for (final PmlSection section in presentation.sections) {
      if (section.startIndex < previous ||
          section.startIndex > presentation.slides.length) {
        throw StateError('Section boundaries must be ordered and in range.');
      }
      previous = section.startIndex;
      if (section.id case final String id) {
        if (!RegExp(
          r'^\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}$',
        ).hasMatch(id)) {
          throw StateError('Native section identity must be a GUID.');
        }
        if (!ids.add(id.toUpperCase())) {
          throw StateError('Native section GUIDs must be unique.');
        }
      }
    }
  }

  /// Plan an atomic move using the original destination slide's section.
  ///
  /// [to] is the final index after removal/insertion. Every unaffected slide
  /// keeps its section; empty sections and section order are retained.
  static PmlSlideReorder planReorder(
    PmlPresentation presentation,
    int from,
    int to,
  ) {
    RangeError.checkValidIndex(from, presentation.slides, 'from');
    RangeError.checkValidIndex(to, presentation.slides, 'to');
    validate(presentation);
    final List<PmlSlide> before = List<PmlSlide>.of(presentation.slides);
    final List<PmlSection> sections = List<PmlSection>.of(
      presentation.sections,
    );
    final List<int> starts = [
      for (final section in sections) section.startIndex,
    ];
    final List<int> owners = List<int>.filled(
      before.length,
      -1,
      growable: true,
    );
    for (int index = 0; index < sections.length; index++) {
      final int end = index + 1 < sections.length
          ? starts[index + 1]
          : before.length;
      for (int slide = starts[index]; slide < end; slide++) {
        owners[slide] = index;
      }
    }
    final int destination = owners[to];
    final List<PmlSlide> after = List<PmlSlide>.of(before);
    after.insert(to, after.removeAt(from));
    owners.removeAt(from);
    owners.insert(to, destination);
    final List<int> counts = List<int>.filled(sections.length, 0);
    var prefix = 0;
    for (final int owner in owners) {
      if (owner < 0) {
        prefix++;
      } else {
        counts[owner]++;
      }
    }
    final List<int> nextStarts = <int>[];
    var at = prefix;
    for (final int count in counts) {
      nextStarts.add(at);
      at += count;
    }
    return PmlSlideReorder._(
      presentation,
      before,
      after,
      sections,
      starts,
      nextStarts,
    );
  }

  /// Reorder one slide with the same membership contract as [planReorder].
  static void reorderSlide(PmlPresentation presentation, int from, int to) =>
      planReorder(presentation, from, to).apply();

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

/// An atomic, reversible slide move and its section-boundary changes.
class PmlSlideReorder {
  PmlSlideReorder._(
    this._presentation,
    this._before,
    this._after,
    this._sections,
    this._beforeStarts,
    this._afterStarts,
  );

  final PmlPresentation _presentation;
  final List<PmlSlide> _before;
  final List<PmlSlide> _after;
  final List<PmlSection> _sections;
  final List<int> _beforeStarts;
  final List<int> _afterStarts;

  /// Apply the move, or reapply it after [undo].
  void apply() => _restore(_before, _beforeStarts, _after, _afterStarts);

  /// Restore the exact prior slide identities and section boundaries.
  void undo() => _restore(_after, _afterStarts, _before, _beforeStarts);

  void _restore(
    List<PmlSlide> expected,
    List<int> expectedStarts,
    List<PmlSlide> target,
    List<int> starts,
  ) {
    PmlSections.validate(_presentation);
    if (_presentation.slides.length != expected.length ||
        _presentation.sections.length != _sections.length) {
      throw StateError(
        'Presentation changed after the slide move was planned.',
      );
    }
    for (int i = 0; i < expected.length; i++) {
      if (!identical(_presentation.slides[i], expected[i])) {
        throw StateError('Slide order changed after the move was planned.');
      }
    }
    for (int i = 0; i < _sections.length; i++) {
      if (!identical(_presentation.sections[i], _sections[i]) ||
          _sections[i].startIndex != expectedStarts[i]) {
        throw StateError(
          'Section boundaries changed after the move was planned.',
        );
      }
    }
    _presentation.slides
      ..clear()
      ..addAll(target);
    for (int i = 0; i < _sections.length; i++) {
      _sections[i].startIndex = starts[i];
    }
  }
}
