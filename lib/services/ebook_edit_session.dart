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
  }) : _savedState = _document.dirty ? -1 : 0;

  EpubDocument _document;
  final bool copyOnly;
  final int maxHistoryEntries;
  final int maxHistoryBytes;
  final _undo = <_EbookCheckpoint>[];
  final _redo = <_EbookCheckpoint>[];
  int _nextState = 0;
  int _state = 0;
  int _savedState;
  bool _saving = false;
  bool _disposed = false;

  EpubDocument get document => _document;
  int get stateId => _state;
  bool get isDirty => _state != _savedState;
  bool get isSaving => _saving;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void mutate(void Function(EpubDocument document) action) {
    _assertOpen();
    final before = _checkpoint();
    final revision = _document.revision;
    try {
      action(_document);
    } catch (_) {
      // Composite edits either all succeed or restore their starting package.
      _document = before.document;
      rethrow;
    }
    if (_document.revision == revision) return;
    _undo.add(before);
    _trimHistory(_undo);
    _redo.clear();
    _state = ++_nextState;
    _notify();
  }

  void undo() {
    _assertOpen();
    if (_undo.isEmpty) return;
    _redo.add(_checkpoint());
    _restore(_undo.removeLast());
  }

  void redo() {
    _assertOpen();
    if (_redo.isEmpty) return;
    _undo.add(_checkpoint());
    _trimHistory(_undo);
    _restore(_redo.removeLast());
  }

  Uint8List exportBytes() {
    _assertOpen();
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
    _assertOpen();
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
    _notify();
  }

  void _assertOpen() {
    if (_disposed) throw StateError('The ebook edit session is closed.');
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
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
