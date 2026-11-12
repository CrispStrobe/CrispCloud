import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// A transient, source-bound directory snapshot. Credentials are never stored.
class BrowsingLocation {
  const BrowsingLocation({
    required this.path,
    required this.paths,
    required this.tabId,
    required this.storage,
    required this.session,
    required this.isCurrent,
    this.navigationRevision = 0,
    this.loading = false,
    this.verified = true,
    this.locked = false,
    this.handle,
  });

  final String path;
  final p.Context paths;
  final String tabId;
  final Object storage;
  final Object session;
  final bool Function() isCurrent;

  /// Changes as soon as navigation is requested, before any asynchronous work.
  final int navigationRevision;
  final bool loading;
  final bool verified;
  final bool locked;
  final Object? handle;

  bool sameSource(BrowsingLocation other) =>
      storage == other.storage &&
      identical(session, other.session) &&
      tabId == other.tabId;

  bool samePath(BrowsingLocation other) =>
      paths.equals(paths.normalize(path), paths.normalize(other.path));
}

abstract class BrowsingPane extends ChangeNotifier {
  /// Null for archives, collections and other non-directory views.
  BrowsingLocation? get location;

  /// Check the captured source without changing its visible location.
  Future<bool> containsDirectory(String path, BrowsingLocation captured);

  /// Must reject a changed source, tab or navigation before opening [path].
  Future<void> navigate(
    String path,
    BrowsingLocation captured, {
    required bool Function() canContinue,
  });
}

enum BrowsingLinkIssue {
  unavailable,
  locked,
  outsideRoots,
  missingFolder,
  changed,
  failed,
}

/// Mirrors navigation below two explicitly chosen roots. This only browses:
/// it never creates folders, synchronizes contents or writes either source.
class SynchronizedBrowsingService extends ChangeNotifier {
  SynchronizedBrowsingService(this.left, this.right) {
    left.addListener(_scheduleObservation);
    right.addListener(_scheduleObservation);
  }

  final BrowsingPane left;
  final BrowsingPane right;
  List<BrowsingLocation>? _roots;
  List<BrowsingLocation>? _last;
  _PendingNavigation? _pending;
  int _generation = 0;
  bool _scheduled = false;
  bool _disposed = false;

  BrowsingLinkIssue? issue;
  String? issuePath;
  bool get enabled => _roots != null;
  bool get busy => _pending != null;
  String? get leftRoot => _roots?.first.path;
  String? get rightRoot => _roots?.last.path;

  bool start() {
    final locations = [left.location, right.location];
    if (locations.any(
      (value) =>
          value == null ||
          value.loading ||
          !value.verified ||
          !value.isCurrent(),
    )) {
      _stop(BrowsingLinkIssue.unavailable);
      return false;
    }
    final roots = locations.cast<BrowsingLocation>();
    if (roots.any((value) => value.locked)) {
      _stop(BrowsingLinkIssue.locked);
      return false;
    }
    if (roots.any((value) => !value.paths.isAbsolute(value.path))) {
      _stop(BrowsingLinkIssue.unavailable);
      return false;
    }
    _generation++;
    _roots = roots;
    _last = List.of(roots);
    _pending = null;
    issue = null;
    issuePath = null;
    notifyListeners();
    return true;
  }

  void stop() => _stop(null);

  void dismissIssue() {
    issue = null;
    issuePath = null;
    notifyListeners();
  }

  void _stop(BrowsingLinkIssue? reason, {String? path}) {
    _generation++;
    _roots = null;
    _last = null;
    _pending = null;
    issue = reason;
    issuePath = path;
    if (!_disposed) notifyListeners();
  }

  void _scheduleObservation() {
    if (_disposed || !enabled || _scheduled) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      if (!_disposed && enabled) _observe();
    });
  }

  void _observe() {
    final roots = _roots!;
    final current = [left.location, right.location];
    for (var index = 0; index < 2; index++) {
      final next = current[index];
      if (next == null ||
          !roots[index].isCurrent() ||
          !next.isCurrent() ||
          !roots[index].sameSource(next)) {
        _stop(BrowsingLinkIssue.changed);
        return;
      }
      if (next.locked) {
        _stop(BrowsingLinkIssue.locked);
        return;
      }
      if (!next.loading && !next.verified) {
        _stop(BrowsingLinkIssue.unavailable);
        return;
      }
      if (!_inside(roots[index], next.path)) {
        _stop(BrowsingLinkIssue.outsideRoots, path: next.path);
        return;
      }
    }

    final locations = current.cast<BrowsingLocation>();
    final pending = _pending;
    if (pending != null) {
      final source = locations[pending.sourceIndex];
      final target = locations[1 - pending.sourceIndex];
      // A newer user navigation owns its pane; an older async check must not
      // redirect it. The target may be loading the one mirrored location.
      if (source.navigationRevision != pending.source.navigationRevision ||
          !source.samePath(pending.source) ||
          (!target.samePath(pending.target) &&
              !target.paths.equals(target.path, pending.targetPath))) {
        _stop(BrowsingLinkIssue.changed);
      }
      return;
    }

    final changed = <int>[
      for (var index = 0; index < 2; index++)
        if (!locations[index].loading &&
            !_last![index].samePath(locations[index]))
          index,
    ];
    if (changed.isEmpty) return;
    if (changed.length != 1 || locations.any((value) => value.loading)) {
      _stop(BrowsingLinkIssue.changed);
      return;
    }
    final sourceIndex = changed.single;
    final targetIndex = 1 - sourceIndex;
    final source = locations[sourceIndex];
    final target = locations[targetIndex];
    final targetPath = mapBrowsingPath(
      roots[sourceIndex],
      source.path,
      roots[targetIndex],
    );
    if (targetPath == null) {
      _stop(BrowsingLinkIssue.outsideRoots, path: source.path);
      return;
    }
    _last![sourceIndex] = source;
    if (target.paths.equals(target.path, targetPath)) return;
    final request = _PendingNavigation(
      sourceIndex,
      source,
      target,
      targetPath,
      _generation,
    );
    _pending = request;
    notifyListeners();
    unawaited(_mirror(request));
  }

  bool _requestCurrent(_PendingNavigation request) {
    if (_disposed ||
        !enabled ||
        request.generation != _generation ||
        !identical(_pending, request)) {
      return false;
    }
    final locations = [left.location, right.location];
    final source = locations[request.sourceIndex];
    final target = locations[1 - request.sourceIndex];
    return source != null &&
        target != null &&
        request.source.isCurrent() &&
        request.target.isCurrent() &&
        source.isCurrent() &&
        target.isCurrent() &&
        source.sameSource(request.source) &&
        target.sameSource(request.target) &&
        source.samePath(request.source) &&
        target.samePath(request.target) &&
        source.navigationRevision == request.source.navigationRevision &&
        target.navigationRevision == request.target.navigationRevision &&
        source.verified &&
        target.verified &&
        !source.loading &&
        !target.loading &&
        !source.locked &&
        !target.locked;
  }

  /// The destination owns its new navigation revision once dispatched. Its
  /// controller checks that revision; this guard keeps the link and source
  /// current while permitting the destination's own path/loading transition.
  bool _navigationMayContinue(_PendingNavigation request) {
    if (_disposed ||
        !enabled ||
        request.generation != _generation ||
        !identical(_pending, request)) {
      return false;
    }
    final source = (request.sourceIndex == 0 ? left : right).location;
    final target = (request.sourceIndex == 0 ? right : left).location;
    return source != null &&
        target != null &&
        request.source.isCurrent() &&
        request.target.isCurrent() &&
        source.isCurrent() &&
        target.isCurrent() &&
        source.sameSource(request.source) &&
        target.sameSource(request.target) &&
        source.samePath(request.source) &&
        source.navigationRevision == request.source.navigationRevision &&
        (target.samePath(request.target) ||
            target.paths.equals(target.path, request.targetPath)) &&
        source.verified &&
        !source.loading &&
        !source.locked &&
        !target.locked;
  }

  Future<void> _mirror(_PendingNavigation request) async {
    final destination = request.sourceIndex == 0 ? right : left;
    try {
      final exists = await destination.containsDirectory(
        request.targetPath,
        request.target,
      );
      if (!_requestCurrent(request)) {
        if (identical(_pending, request)) _stop(BrowsingLinkIssue.changed);
        return;
      }
      if (!exists) {
        _stop(BrowsingLinkIssue.missingFolder, path: request.targetPath);
        return;
      }
      await destination.navigate(
        request.targetPath,
        request.target,
        canContinue: () => _navigationMayContinue(request),
      );
      if (_disposed || !identical(_pending, request)) return;
      final actual = destination.location;
      if (actual == null ||
          !actual.verified ||
          actual.loading ||
          !actual.isCurrent() ||
          !actual.sameSource(request.target) ||
          !actual.paths.equals(actual.path, request.targetPath)) {
        _stop(BrowsingLinkIssue.failed, path: request.targetPath);
        return;
      }
      _last![1 - request.sourceIndex] = actual;
      _pending = null;
      notifyListeners();
    } catch (_) {
      if (!_disposed && identical(_pending, request)) {
        _stop(BrowsingLinkIssue.failed, path: request.targetPath);
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    left.removeListener(_scheduleObservation);
    right.removeListener(_scheduleObservation);
    super.dispose();
  }
}

bool _inside(BrowsingLocation root, String path) {
  final normalized = root.paths.normalize(path);
  final base = root.paths.normalize(root.path);
  return root.paths.equals(base, normalized) ||
      root.paths.isWithin(base, normalized);
}

/// Preserve components across local/remote path styles without allowing a
/// filename from one filesystem to become an absolute path in another.
String? mapBrowsingPath(
  BrowsingLocation sourceRoot,
  String sourcePath,
  BrowsingLocation targetRoot,
) {
  if (!_inside(sourceRoot, sourcePath)) return null;
  final relative = sourceRoot.paths.relative(sourcePath, from: sourceRoot.path);
  final parts = relative == '.' ? <String>[] : sourceRoot.paths.split(relative);
  for (final part in parts) {
    if (part.isEmpty ||
        part == '.' ||
        part == '..' ||
        part.contains('\u0000') ||
        targetRoot.paths.isAbsolute(part) ||
        part.contains('/')) {
      return null;
    }
    if (targetRoot.paths.style == p.Style.windows &&
        (RegExp(r'[<>:"\\|?*]').hasMatch(part) ||
            part.endsWith('.') ||
            part.endsWith(' '))) {
      return null;
    }
  }
  final mapped = targetRoot.paths.normalize(
    targetRoot.paths.joinAll([targetRoot.path, ...parts]),
  );
  return _inside(targetRoot, mapped) ? mapped : null;
}

class _PendingNavigation {
  const _PendingNavigation(
    this.sourceIndex,
    this.source,
    this.target,
    this.targetPath,
    this.generation,
  );
  final int sourceIndex;
  final BrowsingLocation source;
  final BrowsingLocation target;
  final String targetPath;
  final int generation;
}
