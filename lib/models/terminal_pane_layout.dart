/// The axis along which the two children of a terminal split are placed.
enum TerminalSplitAxis { horizontal, vertical }

/// Immutable topology for the visible panes in a terminal workspace.
///
/// Runtime leaves use stable session IDs; saved arrangements map those IDs to
/// tab indexes. Hidden tabs are deliberately not part of this tree. Every
/// operation preserves leaf uniqueness and the eight-pane limit.
sealed class TerminalPaneLayout {
  const TerminalPaneLayout();

  static const maximumLeaves = 8;
  static const minimumFraction = 0.2;
  static const maximumFraction = 0.8;

  List<int> get leafIds;

  bool contains(int id) => leafIds.contains(id);

  /// Splits an existing leaf, preserving it as the first child.
  /// An absent leaf leaves the layout unchanged.
  TerminalPaneLayout splitLeaf(int id, int newId, TerminalSplitAxis axis) {
    if (!contains(id)) return this;
    if (contains(newId)) {
      throw const FormatException('Duplicate terminal pane ID');
    }
    return _replace(
      id,
      TerminalPaneSplit(
        axis: axis,
        first: TerminalPaneLeaf(id),
        second: TerminalPaneLeaf(newId),
      ),
    );
  }

  /// Replaces a visible leaf with a currently hidden terminal.
  TerminalPaneLayout replaceLeaf(int oldId, int newId) {
    if (!contains(oldId) || oldId == newId) return this;
    if (contains(newId)) {
      throw const FormatException('Duplicate terminal pane ID');
    }
    return _replace(oldId, TerminalPaneLeaf(newId));
  }

  TerminalPaneLayout _replace(int id, TerminalPaneLayout replacement) {
    return switch (this) {
      TerminalPaneLeaf(id: final leafId) => leafId == id ? replacement : this,
      TerminalPaneSplit(
        :final axis,
        :final fraction,
        :final first,
        :final second,
      ) =>
        TerminalPaneSplit(
          axis: axis,
          fraction: fraction,
          first: first._replace(id, replacement),
          second: second._replace(id, replacement),
        ),
    };
  }

  /// Removes a leaf and collapses its parent to the surviving sibling.
  /// Removing the only leaf returns null; an absent leaf leaves the tree intact.
  TerminalPaneLayout? removeLeaf(int id) {
    if (!contains(id)) return this;
    return switch (this) {
      TerminalPaneLeaf() => null,
      TerminalPaneSplit(
        :final axis,
        :final fraction,
        :final first,
        :final second,
      ) =>
        _remainingSplit(
          axis,
          fraction,
          first.removeLeaf(id),
          second.removeLeaf(id),
        ),
    };
  }

  static TerminalPaneLayout? _remainingSplit(
    TerminalSplitAxis axis,
    double fraction,
    TerminalPaneLayout? first,
    TerminalPaneLayout? second,
  ) {
    if (first == null) return second;
    if (second == null) return first;
    return TerminalPaneSplit(
      axis: axis,
      fraction: fraction,
      first: first,
      second: second,
    );
  }

  /// Gives each branch equal space without changing topology or leaf order.
  TerminalPaneLayout balance() => switch (this) {
    TerminalPaneLeaf() => this,
    TerminalPaneSplit(:final axis, :final first, :final second) =>
      TerminalPaneSplit(
        axis: axis,
        first: first.balance(),
        second: second.balance(),
      ),
  };

  /// Converts runtime IDs to persisted tab indexes, or back again.
  TerminalPaneLayout mapIds(int Function(int id) map) => switch (this) {
    TerminalPaneLeaf(:final id) => TerminalPaneLeaf(map(id)),
    TerminalPaneSplit(
      :final axis,
      :final fraction,
      :final first,
      :final second,
    ) =>
      TerminalPaneSplit(
        axis: axis,
        fraction: fraction,
        first: first.mapIds(map),
        second: second.mapIds(map),
      ),
  };

  /// Locates a branch using '' for the root and '0'/'1' for its children.
  /// A path that reaches a leaf or no longer exists returns null.
  TerminalPaneSplit? splitAt(String path) {
    _validatePath(path);
    TerminalPaneLayout node = this;
    for (final direction in path.codeUnits) {
      if (node is! TerminalPaneSplit) return null;
      node = direction == 48 ? node.first : node.second;
    }
    return node is TerminalPaneSplit ? node : null;
  }

  /// Changes only the fraction of the branch at [path].
  /// A stale path that no longer names a split leaves the tree unchanged.
  TerminalPaneLayout withSplitFraction(String path, double fraction) {
    _validatePath(path);
    _validateFraction(fraction);
    if (splitAt(path) == null) return this;
    return _withSplitFraction(path, fraction);
  }

  TerminalPaneLayout _withSplitFraction(String path, double fraction) {
    final node = this;
    if (node is! TerminalPaneSplit) return this;
    if (path.isEmpty) {
      return TerminalPaneSplit(
        axis: node.axis,
        fraction: fraction,
        first: node.first,
        second: node.second,
      );
    }
    return TerminalPaneSplit(
      axis: node.axis,
      fraction: node.fraction,
      first: path.startsWith('0')
          ? node.first._withSplitFraction(path.substring(1), fraction)
          : node.first,
      second: path.startsWith('1')
          ? node.second._withSplitFraction(path.substring(1), fraction)
          : node.second,
    );
  }

  static void _validatePath(String path) {
    if (path.length >= maximumLeaves ||
        path.codeUnits.any((unit) => unit != 48 && unit != 49)) {
      throw const FormatException('Invalid terminal split path');
    }
  }

  static void _validateFraction(double fraction) {
    if (!fraction.isFinite ||
        fraction < minimumFraction ||
        fraction > maximumFraction) {
      throw const FormatException('Invalid terminal split proportion');
    }
  }

  Map<String, Object?> toJson();

  factory TerminalPaneLayout.fromJson(Map<String, dynamic> value) =>
      _decode(value, 0);

  static TerminalPaneLayout _decode(Object? value, int depth) {
    // Check before traversing children: a hostile saved tree cannot recurse
    // indefinitely or allocate an unbounded intermediate layout.
    if (depth >= maximumLeaves || value is! Map<String, dynamic>) {
      throw const FormatException('Invalid terminal pane layout');
    }
    switch (value['kind']) {
      case 'leaf':
        final id = value['id'];
        if (id is! int) {
          throw const FormatException('Invalid terminal pane ID');
        }
        return TerminalPaneLeaf(id);
      case 'split':
        final axis = switch (value['axis']) {
          'horizontal' => TerminalSplitAxis.horizontal,
          'vertical' => TerminalSplitAxis.vertical,
          _ => throw const FormatException('Unknown terminal split direction'),
        };
        final fraction = value['fraction'];
        if (fraction is! num) {
          throw const FormatException('Invalid terminal split proportion');
        }
        return TerminalPaneSplit(
          axis: axis,
          fraction: fraction.toDouble(),
          first: _decode(value['first'], depth + 1),
          second: _decode(value['second'], depth + 1),
        );
      default:
        throw const FormatException('Unknown terminal pane layout kind');
    }
  }
}

final class TerminalPaneLeaf extends TerminalPaneLayout {
  TerminalPaneLeaf(this.id) : leafIds = List.unmodifiable([id]) {
    if (id < 0) throw const FormatException('Invalid terminal pane ID');
  }

  final int id;
  @override
  final List<int> leafIds;

  @override
  Map<String, Object?> toJson() => {'kind': 'leaf', 'id': id};

  @override
  bool operator ==(Object other) => other is TerminalPaneLeaf && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

final class TerminalPaneSplit extends TerminalPaneLayout {
  TerminalPaneSplit({
    required this.axis,
    this.fraction = 0.5,
    required this.first,
    required this.second,
  }) : leafIds = List.unmodifiable([...first.leafIds, ...second.leafIds]) {
    TerminalPaneLayout._validateFraction(fraction);
    if (leafIds.length > TerminalPaneLayout.maximumLeaves ||
        leafIds.toSet().length != leafIds.length) {
      throw const FormatException(
        'Invalid terminal pane count or duplicate ID',
      );
    }
  }

  final TerminalSplitAxis axis;
  final double fraction;
  final TerminalPaneLayout first;
  final TerminalPaneLayout second;
  @override
  final List<int> leafIds;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'split',
    'axis': axis.name,
    'fraction': fraction,
    'first': first.toJson(),
    'second': second.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is TerminalPaneSplit &&
      other.axis == axis &&
      other.fraction == fraction &&
      other.first == first &&
      other.second == second;

  @override
  int get hashCode => Object.hash(axis, fraction, first, second);
}
