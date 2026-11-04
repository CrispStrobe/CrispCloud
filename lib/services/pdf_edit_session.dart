import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier;

/// What the storage layer actually did with a save request.
///
/// A browser download is only a handoff to the browser. Neither it nor saving a
/// separate copy establishes that the original document has been updated.
enum PdfSaveOutcome { savedOriginal, savedCopy, downloadedCopy }

class PdfSaveInProgressException implements Exception {
  const PdfSaveInProgressException();

  @override
  String toString() => 'A PDF save is already in progress.';
}

typedef PdfSaveWriter = Future<PdfSaveOutcome> Function(Uint8List bytes);

/// Host-owned save state, independent of the PDF renderer and cloud provider.
///
/// The editor can reuse an incremental buffer or reuse a revision length after
/// undo followed by a new edit. We therefore own immutable byte snapshots and
/// compare their content rather than equating buffer identity/length with a
/// revision. A successful upload marks only its captured snapshot as saved:
/// edits made while it is running stay dirty.
class PdfEditSession extends ChangeNotifier {
  PdfEditSession({required Uint8List initialBytes})
    : _bytes = _copy(initialBytes),
      _currentDigest = _digest(initialBytes),
      _savedDigest = _digest(initialBytes);

  Uint8List _bytes;
  String _currentDigest;
  String _savedDigest;
  bool _isSaving = false;
  bool _disposed = false;
  Object? _lastError;
  PdfSaveOutcome? _lastSaveOutcome;

  Uint8List get bytes => _bytes;
  bool get isDirty => _currentDigest != _savedDigest;
  bool get isSaving => _isSaving;
  Object? get lastError => _lastError;
  PdfSaveOutcome? get lastSaveOutcome => _lastSaveOutcome;

  void updateBytes(Uint8List bytes) {
    _assertOpen();
    final digest = _digest(bytes);
    if (digest == _currentDigest) return;
    _bytes = _copy(bytes);
    _currentDigest = digest;
    _lastError = null;
    _notify();
  }

  /// Save exactly the revision current when this method is called.
  ///
  /// Callers must await this future and present failures themselves: the PDF
  /// widget's void onSave callback cannot await a remote write. Concurrent save
  /// requests fail explicitly rather than overlapping writes or silently
  /// treating a Save As request as an already-running Save.
  Future<PdfSaveOutcome> save(PdfSaveWriter writer) async {
    _assertOpen();
    if (_isSaving) throw const PdfSaveInProgressException();
    final snapshot = _copy(_bytes);
    final snapshotDigest = _currentDigest;
    _isSaving = true;
    _lastError = null;
    _lastSaveOutcome = null;
    _notify();
    try {
      final outcome = await writer(snapshot);
      if (outcome == PdfSaveOutcome.savedOriginal) {
        _savedDigest = snapshotDigest;
      }
      _lastSaveOutcome = outcome;
      return outcome;
    } catch (error) {
      _lastError = error;
      rethrow;
    } finally {
      _isSaving = false;
      _notify();
    }
  }

  void _assertOpen() {
    if (_disposed) throw StateError('The PDF edit session is closed.');
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  static Uint8List _copy(Uint8List bytes) =>
      Uint8List.fromList(bytes).asUnmodifiableView();

  static String _digest(Uint8List bytes) => sha256.convert(bytes).toString();
}
