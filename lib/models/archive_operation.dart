import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/archive_creation_service.dart';
import '../services/file_operation_service.dart';
import 'operation_progress.dart';

/// A detachable observer of a queue-owned archive job. Closing a view does not
/// dispose this handle, cancel its control, or release its storage reservation.
class ArchiveOperationHandle<T> extends ChangeNotifier {
  ArchiveOperationHandle({
    required this.id,
    required this.operation,
    required this.control,
  });

  final String id;
  final OperationProgress operation;
  final FileOperationControl control;
  final Completer<void> _completion = Completer<void>();
  ArchiveCreationProgress? creationProgress;
  T? result;
  Object? error;
  Object? publicationWarning;
  bool get isSettled => _completion.isCompleted;

  /// Always resolves, including failure/cancellation; inspect [error]. Detached
  /// jobs must never create an unhandled asynchronous error in a closed view.
  Future<void> get completion => _completion.future;

  void update() {
    if (!isSettled) notifyListeners();
  }

  void settle({T? result, Object? error, Object? publicationWarning}) {
    if (isSettled) return;
    this.result = result;
    this.error = error;
    this.publicationWarning = publicationWarning;
    _completion.complete();
    notifyListeners();
  }
}
