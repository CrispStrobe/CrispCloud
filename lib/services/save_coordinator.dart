// lib/services/save_coordinator.dart
//
// Revision-aware save state for document editors.
//
// The previous editor captured the text, awaited the upload, and then always
// cleared the modified flag. Typing during the upload therefore marked newer
// edits as saved even though they were not part of the uploaded bytes.
//
// The coordinator fixes that in two ways:
//   * every save records the document revision it wrote;
//   * the document only becomes clean when the current revision still matches.
//
// Saves are serialized. A save requested while another one is running is
// queued and performed after the active write finishes.

import 'dart:async';

import 'package:flutter/foundation.dart';

/// A document value captured together with the revision it belongs to.
class SaveSnapshot<T> {
  const SaveSnapshot({required this.revision, required this.value});

  final int revision;
  final T value;
}

enum EditorSaveStatus {
  /// The write completed. The document may still be dirty if it changed while
  /// the write was in flight.
  saved,

  /// Another write failed.
  failed,
}

class EditorSaveResult {
  const EditorSaveResult._({
    required this.status,
    required this.savedRevision,
    required this.currentRevision,
    this.error,
    this.stackTrace,
  });

  final EditorSaveStatus status;
  final int savedRevision;
  final int currentRevision;
  final Object? error;
  final StackTrace? stackTrace;

  bool get isSuccess => status == EditorSaveStatus.saved;
  bool get isDirty => currentRevision != savedRevision;
}

class _PendingSave<T> {
  const _PendingSave({required this.snapshot, required this.write});

  final SaveSnapshot<T> Function() snapshot;
  final Future<void> Function(SaveSnapshot<T> snapshot) write;
}

/// Tracks document revisions and serializes save operations.
class SaveCoordinator<T> extends ChangeNotifier {
  int _revision = 0;
  int _savedRevision = 0;
  bool _saving = false;
  _PendingSave<T>? _pendingSave;
  bool _disposed = false;
  Object? _lastError;
  StackTrace? _lastStackTrace;
  Future<EditorSaveResult>? _activeSave;
  final List<Completer<EditorSaveResult>> _queuedRequests =
      <Completer<EditorSaveResult>>[];

  /// Current document revision. Starts at zero and increments on every change.
  int get revision => _revision;

  /// Revision that was last written successfully.
  int get savedRevision => _savedRevision;

  /// True when the current revision differs from the last saved revision.
  bool get isDirty => _revision != _savedRevision;

  bool get isSaving => _saving;

  /// True when a save request arrived while another write was in flight.
  bool get hasPendingSave => _pendingSave != null;

  Object? get lastError => _lastError;
  StackTrace? get lastStackTrace => _lastStackTrace;

  /// Completes when the currently active save chain is idle.
  Future<void> get idle => _activeSave ?? Future<void>.value();

  /// Record an edit. Only call this when the document text actually changed.
  void markChanged() {
    _revision++;
    _notify();
  }

  /// Reset to a freshly loaded document.
  void markLoaded() {
    _revision = 0;
    _savedRevision = 0;
    _pendingSave = null;
    _lastError = null;
    _lastStackTrace = null;
    _notify();
  }

  /// Request a write of the current document.
  ///
  /// [snapshot] is evaluated immediately before each individual write, so a
  /// queued save captures the newest text instead of replaying the stale one.
  Future<EditorSaveResult> save({
    required SaveSnapshot<T> Function() snapshot,
    required Future<void> Function(SaveSnapshot<T> snapshot) write,
  }) {
    if (_saving) {
      // Only the newest queued request matters: it has the newest text and is
      // the one the user is waiting for.
      _pendingSave = _PendingSave<T>(snapshot: snapshot, write: write);
      final completer = Completer<EditorSaveResult>();
      _queuedRequests.add(completer);
      _notify();
      return completer.future;
    }
    final future = _drain(snapshot: snapshot, write: write);
    _activeSave = future;
    return future;
  }

  Future<EditorSaveResult> _drain({
    required SaveSnapshot<T> Function() snapshot,
    required Future<void> Function(SaveSnapshot<T> snapshot) write,
  }) async {
    _saving = true;
    var nextSnapshot = snapshot;
    var nextWrite = write;
    _notify();
    EditorSaveResult result = EditorSaveResult._(
      status: EditorSaveStatus.saved,
      savedRevision: _savedRevision,
      currentRevision: _revision,
    );
    try {
      while (true) {
        final SaveSnapshot<T> current;
        try {
          current = nextSnapshot();
        } catch (error, stackTrace) {
          return _failQueued(error, stackTrace);
        }
        try {
          await nextWrite(current);
        } catch (error, stackTrace) {
          return _failQueued(error, stackTrace);
        }

        if (current.revision > _savedRevision) {
          _savedRevision = current.revision;
        }
        _lastError = null;
        _lastStackTrace = null;
        result = EditorSaveResult._(
          status: EditorSaveStatus.saved,
          savedRevision: _savedRevision,
          currentRevision: _revision,
        );

        // A request that arrived during this write is waiting for the *next*
        // write, not for the one that just finished. Use its own snapshot and
        // write callbacks so it captures the newest text.
        final pending = _pendingSave;
        if (pending != null) {
          _pendingSave = null;
          nextSnapshot = pending.snapshot;
          nextWrite = pending.write;
          _notify();
          continue;
        }

        final queued = List<Completer<EditorSaveResult>>.of(_queuedRequests);
        _queuedRequests.clear();
        for (final completer in queued) {
          completer.complete(result);
        }
        _notify();
        break;
      }
      return result;
    } finally {
      _saving = false;
      _pendingSave = null;
      _notify();
    }
  }

  EditorSaveResult _failQueued(Object error, StackTrace stackTrace) {
    _lastError = error;
    _lastStackTrace = stackTrace;
    _pendingSave = null;
    final result = EditorSaveResult._(
      status: EditorSaveStatus.failed,
      savedRevision: _savedRevision,
      currentRevision: _revision,
      error: error,
      stackTrace: stackTrace,
    );
    final queued = List<Completer<EditorSaveResult>>.of(_queuedRequests);
    _queuedRequests.clear();
    for (final completer in queued) {
      completer.complete(result);
    }
    _notify();
    return result;
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final completer in _queuedRequests) {
      if (!completer.isCompleted) {
        completer.complete(
          EditorSaveResult._(
            status: EditorSaveStatus.failed,
            savedRevision: _savedRevision,
            currentRevision: _revision,
            error: StateError('Editor closed before the save completed.'),
          ),
        );
      }
    }
    _queuedRequests.clear();
    _pendingSave = null;
    super.dispose();
  }
}
