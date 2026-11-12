import 'dart:async';

enum QuickOpenKind { favorite, source, device, workspace, renamePreset }

enum QuickOpenUnavailable {
  unboundFavorite,
  sourceUnavailable,
  collectionUnavailable,
  localAccessUnavailable,
  noSelection,
  selectionUnavailable,
  savedItemsUnavailable,
  changed,
}

class QuickOpenException implements Exception {
  const QuickOpenException(this.reason);
  final QuickOpenUnavailable reason;
}

/// One captured action. Names are display text; [id] distinguishes same-named
/// favorites, accounts and workspaces. Executable targets never use a label as
/// a storage lookup key.
class QuickOpenEntry {
  const QuickOpenEntry({
    required this.id,
    required this.name,
    required this.kind,
    required this.detail,
    required this.open,
    this.unavailable,
  });

  final String id;
  final String name;
  final QuickOpenKind kind;
  final String detail;
  final QuickOpenUnavailable? unavailable;
  final Future<void> Function(QuickOpenRun run) open;
  bool get enabled => unavailable == null;
}

class QuickOpenRun {
  const QuickOpenRun(this.isCurrent);
  final bool Function() isCurrent;

  void check() {
    if (!isCurrent()) {
      throw const QuickOpenException(QuickOpenUnavailable.changed);
    }
  }
}

/// A later Quick Open action supersedes an earlier asynchronous action. Each
/// binding also verifies its original pane, selection and storage authority.
class QuickOpenService {
  int _revision = 0;
  bool _disposed = false;

  Future<void> open(
    QuickOpenEntry entry, {
    required bool Function() isCurrent,
  }) async {
    if (!entry.enabled) throw QuickOpenException(entry.unavailable!);
    final revision = ++_revision;
    final run = QuickOpenRun(
      () => !_disposed && revision == _revision && isCurrent(),
    );
    run.check();
    await entry.open(run);
  }

  void dispose() {
    _disposed = true;
    _revision++;
  }
}
