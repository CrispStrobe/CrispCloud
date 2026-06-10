// lib/services/log_service.dart
//
// Structured logging service wrapping dart:developer and package:logging.
//
// Usage:
//   final log = Log('AppState');
//   log.info('Connected to provider', {'provider': 'Filen'});
//   log.error('Upload failed', error, stackTrace);
//
// Log output is written via debugPrint (which routes to dart:developer on
// Flutter) and optionally collected in-memory for export/bug-reports.

import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';

enum LogLevel {
  trace,
  debug,
  info,
  warn,
  error,
}

class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String logger;
  final String message;
  final Map<String, dynamic>? data;
  final Object? error;
  final StackTrace? stackTrace;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.logger,
    required this.message,
    this.data,
    this.error,
    this.stackTrace,
  });

  @override
  String toString() {
    final prefix = '${_levelIcon(level)} [$logger]';
    final dataSuffix = data != null && data!.isNotEmpty ? ' $data' : '';
    final errorSuffix = error != null ? '\n  Error: $error' : '';
    return '$prefix $message$dataSuffix$errorSuffix';
  }

  static String _levelIcon(LogLevel level) {
    switch (level) {
      case LogLevel.trace:
        return '🔍';
      case LogLevel.debug:
        return '🐛';
      case LogLevel.info:
        return 'ℹ️';
      case LogLevel.warn:
        return '⚠️';
      case LogLevel.error:
        return '❌';
    }
  }
}

/// Global log configuration.
class LogConfig {
  /// Minimum level to output. Messages below this level are silently dropped.
  static LogLevel minLevel = kDebugMode ? LogLevel.debug : LogLevel.info;

  /// Maximum number of entries to keep in the in-memory ring buffer.
  /// Set to 0 to disable in-memory collection.
  static int maxBufferSize = 1000;

  /// In-memory ring buffer of recent log entries (for export / bug reports).
  static final _buffer = Queue<LogEntry>();

  /// Live stream of log entries for the log viewer.
  static final _streamController = StreamController<LogEntry>.broadcast();
  static Stream<LogEntry> get stream => _streamController.stream;

  static List<LogEntry> get entries => _buffer.toList();

  static void clear() {
    _buffer.clear();
  }

  static void _add(LogEntry entry) {
    if (maxBufferSize <= 0) return;
    if (_buffer.length >= maxBufferSize) {
      _buffer.removeFirst();
    }
    _buffer.add(entry);
    _streamController.add(entry);
  }

  /// Export all buffered entries as a plain-text string (for sharing).
  static String export() {
    final sb = StringBuffer();
    sb.writeln('=== CrispCloud Log Export ===');
    sb.writeln('Exported: ${DateTime.now().toIso8601String()}');
    sb.writeln('Entries: ${_buffer.length}');
    sb.writeln('');
    for (final entry in _buffer) {
      sb.writeln(
          '${entry.timestamp.toIso8601String()} '
          '${entry.level.name.toUpperCase().padRight(5)} '
          '[${entry.logger}] ${entry.message}');
      if (entry.data != null && entry.data!.isNotEmpty) {
        sb.writeln('  Data: ${entry.data}');
      }
      if (entry.error != null) {
        sb.writeln('  Error: ${entry.error}');
      }
      if (entry.stackTrace != null) {
        sb.writeln('  Stack: ${entry.stackTrace}');
      }
    }
    return sb.toString();
  }
}

/// A named logger. Create one per class/service.
///
/// ```dart
/// class AppState {
///   final _log = Log('AppState');
///   void doStuff() => _log.info('did stuff');
/// }
/// ```
class Log {
  final String name;

  const Log(this.name);

  void trace(String message, [Map<String, dynamic>? data]) =>
      _emit(LogLevel.trace, message, data: data);

  void debug(String message, [Map<String, dynamic>? data]) =>
      _emit(LogLevel.debug, message, data: data);

  void info(String message, [Map<String, dynamic>? data]) =>
      _emit(LogLevel.info, message, data: data);

  void warn(String message, [Object? error, StackTrace? stackTrace]) =>
      _emit(LogLevel.warn, message, error: error, stackTrace: stackTrace);

  void error(String message, [Object? error, StackTrace? stackTrace]) =>
      _emit(LogLevel.error, message, error: error, stackTrace: stackTrace);

  void _emit(
    LogLevel level,
    String message, {
    Map<String, dynamic>? data,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (level.index < LogConfig.minLevel.index) return;

    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      logger: name,
      message: message,
      data: data,
      error: error,
      stackTrace: stackTrace,
    );

    LogConfig._add(entry);
    debugPrint(entry.toString());
  }
}
