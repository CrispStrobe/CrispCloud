// Adapted from https://github.com/madedit/madedit2/blob/main/lib/editor/piece_tree.dart
// Copyright (c) 2026 madedit. Distributed under the MIT license; see LICENSE.
// CrispCloud changes: generic immutable buffers, byte-only aggregates, bounded
// range collection, range validation, and removal of all newline/index logic.

/// An immutable reference to bytes in a buffer owned by the document layer.
class PieceRef<T> {
  const PieceRef(this.buffer, this.start, this.length);

  final T buffer;
  final int start;
  final int length;
}

class _Node<T> {
  _Node(this.buffer, this.start, this.length);

  T buffer;
  int start;
  int length;
  _Node<T>? left;
  _Node<T>? right;
  _Node<T>? parent;
  int height = 1;
  int subBytes = 0;
}

/// An augmented AVL tree of byte ranges; this layer never reads any bytes.
class PieceTree<T> {
  PieceTree.empty();

  PieceTree.original(T buffer, int length) {
    RangeError.checkNotNegative(length, 'length');
    if (length > 0) {
      _root = _Node<T>(buffer, 0, length);
      _pull(_root!);
    }
  }

  _Node<T>? _root;

  int get length => _sb(_root);

  static int _h<T>(_Node<T>? node) => node?.height ?? 0;
  static int _sb<T>(_Node<T>? node) => node?.subBytes ?? 0;
  static int _bf<T>(_Node<T> node) => _h(node.left) - _h(node.right);

  static void _pull<T>(_Node<T> node) {
    node.subBytes = node.length + _sb(node.left) + _sb(node.right);
    final leftHeight = _h(node.left), rightHeight = _h(node.right);
    node.height = 1 + (leftHeight > rightHeight ? leftHeight : rightHeight);
  }

  _Node<T> _rotateLeft(_Node<T> x) {
    final y = x.right!;
    x.right = y.left;
    y.left?.parent = x;
    y.parent = x.parent;
    if (x.parent == null) {
      _root = y;
    } else if (x == x.parent!.left) {
      x.parent!.left = y;
    } else {
      x.parent!.right = y;
    }
    y.left = x;
    x.parent = y;
    _pull(x);
    _pull(y);
    return y;
  }

  _Node<T> _rotateRight(_Node<T> x) {
    final y = x.left!;
    x.left = y.right;
    y.right?.parent = x;
    y.parent = x.parent;
    if (x.parent == null) {
      _root = y;
    } else if (x == x.parent!.left) {
      x.parent!.left = y;
    } else {
      x.parent!.right = y;
    }
    y.right = x;
    x.parent = y;
    _pull(x);
    _pull(y);
    return y;
  }

  void _rebalanceUp(_Node<T>? from) {
    var node = from;
    while (node != null) {
      _pull(node);
      final balance = _bf(node);
      if (balance > 1) {
        if (_bf(node.left!) < 0) _rotateLeft(node.left!);
        node = _rotateRight(node);
      } else if (balance < -1) {
        if (_bf(node.right!) > 0) _rotateRight(node.right!);
        node = _rotateLeft(node);
      }
      node = node.parent;
    }
  }

  static _Node<T> _leftmost<T>(_Node<T> node) {
    var current = node;
    while (current.left != null) {
      current = current.left!;
    }
    return current;
  }

  static _Node<T> _rightmost<T>(_Node<T> node) {
    var current = node;
    while (current.right != null) {
      current = current.right!;
    }
    return current;
  }

  static _Node<T>? _successor<T>(_Node<T> node) {
    if (node.right != null) return _leftmost(node.right!);
    var current = node;
    while (current.parent != null && current == current.parent!.right) {
      current = current.parent!;
    }
    return current.parent;
  }

  (_Node<T>?, int) _descend(int offset) {
    var node = _root;
    var remaining = offset;
    while (node != null) {
      final leftBytes = _sb(node.left);
      if (remaining < leftBytes) {
        node = node.left;
      } else {
        final within = remaining - leftBytes;
        if (within < node.length) return (node, within);
        remaining = within - node.length;
        node = node.right;
      }
    }
    return (null, 0);
  }

  /// Copies only descriptors, never buffer contents.
  List<PieceRef<T>> piecesInRange(int offset, int count) {
    _checkRange(offset, count);
    final pieces = <PieceRef<T>>[];
    if (count == 0) return pieces;
    var (node, within) = _descend(offset);
    var remaining = count;
    while (node != null && remaining > 0) {
      final available = node.length - within;
      final take = available < remaining ? available : remaining;
      pieces.add(PieceRef<T>(node.buffer, node.start + within, take));
      remaining -= take;
      within = 0;
      node = _successor(node);
    }
    return pieces;
  }

  List<PieceRef<T>> get pieces => piecesInRange(0, length);

  /// Replaces a range and returns descriptors for the removed bytes.
  List<PieceRef<T>> replace(int offset, int count, List<PieceRef<T>> inserted) {
    _checkRange(offset, count);
    for (final piece in inserted) {
      RangeError.checkNotNegative(piece.start, 'piece.start');
      if (piece.length <= 0) {
        throw ArgumentError.value(piece.length, 'piece.length', 'must be > 0');
      }
    }
    _splitAt(offset);
    _splitAt(offset + count);
    final removed = <PieceRef<T>>[];
    var remaining = count;
    while (remaining > 0) {
      final (node, _) = _descend(offset);
      final found = node!;
      removed.add(PieceRef<T>(found.buffer, found.start, found.length));
      remaining -= found.length;
      _remove(found);
    }
    var cursor = offset;
    for (final piece in inserted) {
      _insertPieceAt(cursor, piece);
      cursor += piece.length;
    }
    return removed;
  }

  void _checkRange(int offset, int count) {
    RangeError.checkValueInInterval(offset, 0, length, 'offset');
    RangeError.checkValueInInterval(count, 0, length - offset, 'count');
  }

  void _splitAt(int offset) {
    final (node, within) = _descend(offset);
    if (node == null || within == 0) return;
    final right = _Node<T>(
      node.buffer,
      node.start + within,
      node.length - within,
    );
    node.length = within;
    _insertAfter(node, right);
  }

  void _insertPieceAt(int offset, PieceRef<T> piece) {
    final fresh = _Node<T>(piece.buffer, piece.start, piece.length);
    if (_root == null) {
      _root = fresh;
      _pull(fresh);
      return;
    }
    final (node, _) = _descend(offset);
    if (node == null) {
      _insertAfter(_rightmost(_root!), fresh);
    } else {
      _insertBefore(node, fresh);
    }
  }

  void _insertAfter(_Node<T> node, _Node<T> fresh) {
    if (node.right == null) {
      node.right = fresh;
      fresh.parent = node;
    } else {
      final next = _leftmost(node.right!);
      next.left = fresh;
      fresh.parent = next;
    }
    _rebalanceUp(fresh);
  }

  void _insertBefore(_Node<T> node, _Node<T> fresh) {
    if (node.left == null) {
      node.left = fresh;
      fresh.parent = node;
    } else {
      final previous = _rightmost(node.left!);
      previous.right = fresh;
      fresh.parent = previous;
    }
    _rebalanceUp(fresh);
  }

  void _remove(_Node<T> node) {
    final removed = node.left == null || node.right == null
        ? node
        : _leftmost(node.right!);
    final child = removed.left ?? removed.right;
    final parent = removed.parent;
    if (child != null) child.parent = parent;
    if (parent == null) {
      _root = child;
    } else if (removed == parent.left) {
      parent.left = child;
    } else {
      parent.right = child;
    }
    if (!identical(removed, node)) {
      node.buffer = removed.buffer;
      node.start = removed.start;
      node.length = removed.length;
    }
    _rebalanceUp(parent);
  }

  void clear() => _root = null;

  /// Checks structural invariants without reading underlying bytes.
  String? validate() {
    String? error;
    void check(_Node<T>? node) {
      if (node == null || error != null) return;
      if (node.left != null && !identical(node.left!.parent, node)) {
        error = 'left.parent mismatch';
      }
      if (node.right != null && !identical(node.right!.parent, node)) {
        error = 'right.parent mismatch';
      }
      check(node.left);
      check(node.right);
      final expectedBytes = node.length + _sb(node.left) + _sb(node.right);
      if (node.subBytes != expectedBytes) error ??= 'byte aggregate mismatch';
      final leftHeight = _h(node.left), rightHeight = _h(node.right);
      final expectedHeight =
          1 + (leftHeight > rightHeight ? leftHeight : rightHeight);
      if (node.height != expectedHeight) error ??= 'height mismatch';
      if ((leftHeight - rightHeight).abs() > 1) error ??= 'AVL unbalanced';
      if (node.length <= 0) error ??= 'non-positive piece length';
      if (node.start < 0) error ??= 'negative buffer offset';
    }

    check(_root);
    if (_root?.parent != null) error ??= 'root.parent is not null';
    return error;
  }
}
