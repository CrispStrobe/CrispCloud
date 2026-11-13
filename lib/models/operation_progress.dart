import 'package:crisp_storage/crisp_storage.dart' show TransferOperation;

// models/operation_progress.dart
import 'dart:async';

import '../services/log_service.dart';
import '../utils/formatters.dart' show formatBytes;

enum OperationType { upload, download, copy, move, delete, archive }

enum OperationStatus { inProgress, waitingForDecision, completed, failed }

/// App-authored transfer failures that can be presented in the UI locale.
enum TransferErrorCode { cancelled, allFilesFailed, someFilesFailed }

class OperationProgress implements TransferOperation {
  static const _log = Log('OperationProgress');

  final String id;
  final OperationType type;
  final String sourcePath;
  final String targetPath;
  final String fileName;
  int totalBytes;
  int currentBytes;
  OperationStatus status;
  String? errorMessage;
  TransferErrorCode? errorCode;
  Map<String, Object> errorArguments = const {};

  /// Ephemeral foreground details; recovery remains owned by the journal.
  String? currentFilePath;
  String? phaseLabel;

  // Batch support
  final String? batchId;
  final List<FileProgress>? files;

  // Cancellation support
  final Completer<void> _cancellationCompleter = Completer<void>();
  bool _isCancelled = false;

  // Pause/Resume support
  Completer<void>? _pauseCompleter;
  bool _isPaused = false;

  // Speed tracking
  final DateTime? _transferStartTime;
  final DateTime Function() _now;
  DateTime? _lastSpeedUpdate;
  int _lastSpeedBytes = 0;
  double _currentSpeed = 0; // bytes per second

  OperationProgress({
    required this.id,
    required this.type,
    required this.sourcePath,
    required this.targetPath,
    required this.fileName,
    this.totalBytes = 0,
    this.currentBytes = 0,
    this.status = OperationStatus.inProgress,
    this.errorMessage,
    this.batchId,
    this.files,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       _transferStartTime = (now ?? DateTime.now)();

  double get progress => totalBytes > 0
      ? (currentBytes / totalBytes).clamp(0.0, 1.0).toDouble()
      : 0;

  bool get isComplete =>
      status == OperationStatus.completed || status == OperationStatus.failed;

  bool get isWaitingForDecision => status == OperationStatus.waitingForDecision;

  /// Waiting conflicts release the scheduler worker and have no active I/O.
  bool get isActive => status == OperationStatus.inProgress && !_isCancelled;

  // Compatibility getters
  String? get error => errorMessage;
  int get transferredBytes => currentBytes;

  // Cancellation support
  @override
  bool get isCancelled => _isCancelled;
  @override
  Future<void> get cancellationFuture => _cancellationCompleter.future;

  // Pause/Resume getters
  @override
  bool get isPaused => _isPaused;
  @override
  Future<void>? get pauseFuture => _pauseCompleter?.future;

  @override
  void cancel() {
    if (!_isCancelled && !isComplete) {
      _isCancelled = true;
      status = OperationStatus.failed;
      errorMessage = 'Cancelled by user';
      errorCode = TransferErrorCode.cancelled;
      errorArguments = const {};
      if (!_cancellationCompleter.isCompleted) {
        _cancellationCompleter.complete();
      }
      // If paused, resume to allow cancellation to complete
      if (_isPaused) {
        resume();
      }
      _log.debug('Operation cancelled: $fileName');
    }
  }

  // Pause operation
  void pause() {
    if (!_isPaused && isActive) {
      _isPaused = true;
      _pauseCompleter = Completer<void>();
      _resetSpeedWindow();
      _log.debug('Operation paused: $fileName');
    }
  }

  // Resume operation
  void resume() {
    if (_isPaused) {
      _isPaused = false;
      if (_pauseCompleter != null && !_pauseCompleter!.isCompleted) {
        _pauseCompleter!.complete();
      }
      _pauseCompleter = null;
      _resetSpeedWindow();
      _log.debug('Operation resumed: $fileName');
    }
  }

  // Batch operation helpers
  bool get isBatch => files != null && files!.isNotEmpty;

  int get completedFiles {
    if (files == null) return 0;
    return files!.where((f) => f.isComplete).length;
  }

  int get totalFiles {
    if (files == null) return 0;
    return files!.length;
  }

  int get failedFiles {
    if (files == null) return 0;
    return files!.where((f) => f.error != null).length;
  }

  /// Skipped and filtered rows are resolved work, not copied files.
  int get skippedFiles => files?.where((file) => file.isSkipped).length ?? 0;

  int get processedFiles =>
      files?.where((file) => file.isProcessed).length ?? 0;

  void complete() {
    status = OperationStatus.completed;
    errorMessage = null;
    errorCode = null;
    errorArguments = const {};
    currentBytes = totalBytes;

    // Mark all files as complete if this is a batch
    if (files != null) {
      for (final file in files!) {
        if (!file.isComplete && file.error == null) {
          file.isComplete = true;
        }
      }
    }
  }

  /// Only a verified publication result may override a late Stop request.
  /// The cancellation future remains signalled so no further I/O can start.
  void completePublished() {
    _isCancelled = false;
    resume();
    complete();
  }

  void fail(
    String error, {
    TransferErrorCode? code,
    Map<String, Object> arguments = const {},
  }) {
    status = OperationStatus.failed;
    errorMessage = error;
    errorCode = code;
    errorArguments = Map.unmodifiable(arguments);
  }

  void waitForDecision() {
    resume();
    status = OperationStatus.waitingForDecision;
    errorMessage = null;
    errorCode = null;
    errorArguments = const {};
    _currentSpeed = 0;
    _lastSpeedUpdate = null;
    _lastSpeedBytes = currentBytes;
  }

  /// Current transfer speed in bytes per second.
  double get currentSpeed => isActive && !_isPaused ? _currentSpeed : 0;

  /// Average speed since transfer started.
  double get averageSpeed {
    if (_transferStartTime == null) return 0;
    final elapsed = _now().difference(_transferStartTime).inMilliseconds;
    if (elapsed <= 0) return 0;
    return currentBytes / (elapsed / 1000);
  }

  /// Estimated time remaining in seconds.
  double get estimatedSecondsRemaining {
    if (currentSpeed <= 0 || totalBytes <= 0) return 0;
    final remaining = (totalBytes - currentBytes).clamp(0, totalBytes);
    return remaining / currentSpeed;
  }

  void _resetSpeedWindow() {
    _currentSpeed = 0;
    _lastSpeedUpdate = null;
    _lastSpeedBytes = currentBytes;
  }

  void updateProgress(int bytes) {
    // A restarted partial stream may begin at a lower offset. Start a new
    // sampling window instead of showing negative throughput or ETA.
    bytes = bytes < 0 ? 0 : bytes;
    if (bytes < currentBytes) _resetSpeedWindow();
    final now = _now();
    // Calculate instantaneous speed (smoothed over 1-second windows)
    if (_lastSpeedUpdate != null) {
      final elapsed = now.difference(_lastSpeedUpdate!).inMilliseconds;
      if (elapsed >= 500) {
        final bytesDelta = bytes - _lastSpeedBytes;
        _currentSpeed = bytesDelta / (elapsed / 1000);
        _lastSpeedBytes = bytes;
        _lastSpeedUpdate = now;
      }
    } else {
      _lastSpeedUpdate = now;
      _lastSpeedBytes = bytes;
    }
    currentBytes = bytes;
  }

  // Update progress for a specific file in batch
  void updateFileProgress(String filePath, {bool? complete, String? error}) {
    if (files == null) return;

    final fileIndex = files!.indexWhere((f) => f.path == filePath);
    if (fileIndex == -1) return;

    if (complete != null) {
      files![fileIndex].isComplete = complete;
    }

    if (error != null) {
      files![fileIndex].error = error;
    }

    // Recalculate overall progress based on completed files
    if (files!.isNotEmpty) {
      final completedBytes = files!
          .where((f) => f.isComplete)
          .fold<int>(0, (sum, f) => sum + f.size);
      currentBytes = completedBytes;
    }
  }

  String get displayName {
    switch (type) {
      case OperationType.upload:
        return isBatch ? 'Upload: $totalFiles files' : 'Upload: $fileName';
      case OperationType.download:
        return isBatch ? 'Download: $totalFiles files' : 'Download: $fileName';
      case OperationType.copy:
        return isBatch ? 'Copy: $totalFiles files' : 'Copy: $fileName';
      case OperationType.move:
        return isBatch ? 'Move: $totalFiles files' : 'Move: $fileName';
      case OperationType.delete:
        return isBatch ? 'Delete: $totalFiles files' : 'Delete: $fileName';
      case OperationType.archive:
        return 'Archive: $fileName';
    }
  }

  // Get summary string for batch operations
  String get batchSummary {
    if (!isBatch) return displayName;

    if (status == OperationStatus.failed) {
      return '$displayName - $failedFiles failed';
    }

    if (status == OperationStatus.completed) {
      return '$displayName - All complete';
    }

    if (isWaitingForDecision) {
      return '$displayName - Waiting for a conflict decision';
    }

    return '$displayName - $completedFiles/$totalFiles complete';
  }
}

// Track individual files in a batch
class FileProgress {
  final String name;
  final String path;
  final int size;
  bool isComplete;
  String? error;

  /// Original failure, retained for localized presentation and diagnostics.
  Object? errorCause;

  /// Human-readable terminal state for filtered, skipped, or cancelled rows.
  String? statusLabel;

  bool get isSkipped => statusLabel == 'skipped' || statusLabel == 'filtered';

  bool get isProcessed =>
      isComplete || isSkipped || error != null || statusLabel == 'cancelled';

  FileProgress({
    required this.name,
    required this.path,
    required this.size,
    this.isComplete = false,
    this.error,
    this.statusLabel,
  });

  // Helper to check if file has error
  bool get hasError => error != null;

  // Helper to get status icon
  String get statusIcon {
    if (error != null) return '❌';
    if (isComplete) return '✅';
    return '⏳';
  }

  @override
  String toString() {
    return '$statusIcon $name (${formatBytes(size)})${error != null ? ' - $error' : ''}';
  }
}
