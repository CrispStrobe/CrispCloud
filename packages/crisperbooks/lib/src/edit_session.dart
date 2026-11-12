import 'dart:async';

import 'package:crisp_ebook/crisp_ebook.dart';
import 'package:flutter/foundation.dart';

enum EbookSaveOutcome { savedOriginal, savedCopy, downloadedCopy }

typedef EbookSaveWriter = Future<EbookSaveOutcome> Function(Uint8List bytes);

/// A history entry is a package snapshot, not a reconstructed book. State IDs
/// let undo return to a saved revision without treating a later branch as saved.
class EbookEditSession extends ChangeNotifier {
  EbookEditSession(
    this._document, {
    this.copyOnly = false,
    this.maxHistoryEntries = 24,
    this.maxHistoryBytes = 128 * 1024 * 1024,
  }) : _savedState = _document.dirty ? -1 : 0,
       _stateRevision = _document.revision {
    RangeError.checkNotNegative(maxHistoryEntries, 'maxHistoryEntries');
    RangeError.checkNotNegative(maxHistoryBytes, 'maxHistoryBytes');
  }

  EpubDocument _document;
  final bool copyOnly;
  final int maxHistoryEntries;
  final int maxHistoryBytes;
  final _undo = <_EbookCheckpoint>[];
  final _redo = <_EbookCheckpoint>[];
  int _nextState = 0;
  int _state = 0;
  int _savedState;
  int _stateRevision;
  bool _saving = false;
  bool _mutating = false;
  bool _disposed = false;

  /// The current book for rendering and inspection. Make changes through
  /// [mutate] to preserve undo history and listener notifications. Direct edits
  /// are still treated as unsaved, but do not acquire their own undo entry.
  EpubDocument get document => _document;
  int get stateId {
    _observeExternalMutation();
    return _state;
  }

  bool get isDirty =>
      _state != _savedState || _document.revision != _stateRevision;
  bool get isSaving => _saving;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _document.revision == _stateRevision && _redo.isNotEmpty;

  /// Apply one synchronous edit or composite edit as a single undo step.
  /// Reentrant session commands are rejected so a failed composite operation
  /// cannot leave its history or saved-state identity partially committed.
  void mutate(void Function(EpubDocument document) action) {
    _assertCommandAllowed();
    _observeExternalMutation();
    final before = _checkpoint();
    final revision = _document.revision;
    _mutating = true;
    try {
      // Dart permits an async function where a void callback is expected. Keep
      // its actual result so it cannot silently commit a partial transaction.
      final result = Function.apply(action, [_document]);
      if (result is Future) {
        // The callback now owns only the discarded document after rollback.
        // Consume its eventual failure; the caller receives this synchronous
        // contract error and can await its work before starting a new edit.
        result.ignore();
        throw ArgumentError(
          'Ebook edits must be synchronous. Await external work before mutate.',
        );
      }
    } catch (_) {
      // Composite edits either all succeed or restore their starting package.
      _document = before.document;
      rethrow;
    } finally {
      _mutating = false;
    }
    if (_document.revision == revision) return;
    _undo.add(before);
    _trimHistory(_undo);
    _redo.clear();
    _state = ++_nextState;
    _stateRevision = _document.revision;
    _notify();
  }

  void undo() {
    _assertCommandAllowed();
    _observeExternalMutation();
    if (_undo.isEmpty) return;
    _redo.add(_checkpoint());
    _restore(_undo.removeLast());
  }

  void redo() {
    _assertCommandAllowed();
    _observeExternalMutation();
    if (_redo.isEmpty) return;
    _undo.add(_checkpoint());
    _trimHistory(_undo);
    _restore(_redo.removeLast());
  }

  Uint8List exportBytes() {
    _assertCommandAllowed();
    _observeExternalMutation();
    final errors = _document
        .validate()
        .where((issue) => issue.isError)
        .toList();
    if (errors.isNotEmpty) {
      throw EpubException(
        'validation',
        errors.take(8).map((issue) => issue.toString()).join('\n'),
      );
    }
    return Uint8List.fromList(_document.toBytes()).asUnmodifiableView();
  }

  /// Save completion acknowledges only the immutable revision submitted.
  /// Copies and browser handoffs never acknowledge an update to the original.
  Future<EbookSaveOutcome> save(EbookSaveWriter writer) async {
    _assertCommandAllowed();
    _observeExternalMutation();
    if (_saving) throw StateError('An ebook save is already in progress.');
    final bytes = exportBytes();
    final state = _state;
    final revision = _document.revision;
    final submitted = _document;
    _saving = true;
    _notify();
    try {
      final outcome = await writer(bytes);
      if (outcome == EbookSaveOutcome.savedOriginal && !copyOnly) {
        _savedState = state;
        if (identical(submitted, _document)) {
          _document.markSaved(revision: revision);
        }
      }
      return outcome;
    } finally {
      _saving = false;
      _notify();
    }
  }

  _EbookCheckpoint _checkpoint() => _EbookCheckpoint(
    _document.snapshot(),
    _state,
    _document.resources.fold<int>(0, (sum, resource) => sum + resource.size),
  );

  void _trimHistory(List<_EbookCheckpoint> history) {
    var size = history.fold<int>(0, (sum, entry) => sum + entry.size);
    while (history.isNotEmpty &&
        (history.length > maxHistoryEntries || size > maxHistoryBytes)) {
      size -= history.removeAt(0).size;
    }
  }

  void _restore(_EbookCheckpoint entry) {
    _document = entry.document;
    _state = entry.state;
    _stateRevision = _document.revision;
    _notify();
  }

  void _observeExternalMutation() {
    if (_disposed || _mutating || _document.revision == _stateRevision) return;
    // EpubDocument is intentionally a mutable public API. A caller that writes
    // directly must not make a delayed save acknowledge those newer bytes or
    // reuse the identity of an abandoned redo branch.
    _state = ++_nextState;
    _stateRevision = _document.revision;
    _redo.clear();
  }

  void _assertCommandAllowed() {
    if (_disposed) throw StateError('The ebook edit session is closed.');
    if (_mutating) {
      throw StateError('An ebook mutation is already in progress.');
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_mutating) {
      throw StateError('Cannot close an ebook session during a mutation.');
    }
    _disposed = true;
    _undo.clear();
    _redo.clear();
    super.dispose();
  }
}

class _EbookCheckpoint {
  const _EbookCheckpoint(this.document, this.state, this.size);
  final EpubDocument document;
  final int state;
  final int size;
}
