// models/operation_progress.dart
import 'dart:async';
import '../services/log_service.dart';
import '../utils/formatters.dart' show formatBytes;

enum OperationType {
  upload,
  download,
  copy,
  move,
  delete,
}

enum OperationStatus { 
  inProgress, 
  completed, 
  failed 
}

class OperationProgress {
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
  }) : _transferStartTime = DateTime.now();

  double get progress => totalBytes > 0 ? currentBytes / totalBytes : 0;
  
  bool get isComplete => status == OperationStatus.completed || status == OperationStatus.failed;

  // Compatibility getters
  String? get error => errorMessage;
  int get transferredBytes => currentBytes;

  // Cancellation support
  bool get isCancelled => _isCancelled;
  Future<void> get cancellationFuture => _cancellationCompleter.future;

  // Pause/Resume getters
  bool get isPaused => _isPaused;
  Future<void>? get pauseFuture => _pauseCompleter?.future;
  
  void cancel() {
    if (!_isCancelled && !isComplete) {
      _isCancelled = true;
      status = OperationStatus.failed;
      errorMessage = 'Cancelled by user';
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
    if (!_isPaused && !isComplete && !_isCancelled) {
      _isPaused = true;
      _pauseCompleter = Completer<void>();
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

  void complete() {
    status = OperationStatus.completed;
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

  void fail(String error) {
    status = OperationStatus.failed;
    errorMessage = error;
  }

  /// Current transfer speed in bytes per second.
  double get currentSpeed => _currentSpeed;

  /// Average speed since transfer started.
  double get averageSpeed {
    if (_transferStartTime == null) return 0;
    final elapsed = DateTime.now().difference(_transferStartTime!).inMilliseconds;
    if (elapsed <= 0) return 0;
    return currentBytes / (elapsed / 1000);
  }

  /// Estimated time remaining in seconds.
  double get estimatedSecondsRemaining {
    if (_currentSpeed <= 0 || totalBytes <= 0) return 0;
    final remaining = totalBytes - currentBytes;
    return remaining / _currentSpeed;
  }

  void updateProgress(int bytes) {
    final now = DateTime.now();
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
  
  FileProgress({
    required this.name,
    required this.path,
    required this.size,
    this.isComplete = false,
    this.error,
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