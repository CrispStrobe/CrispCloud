// lib/services/audit_service.dart
//
// Audit log service: records file operations to a JSON-lines file.
// Operations: upload, download, delete, rename, move, copy, createFolder, sync.
//
// Storage: <appSupportDir>/audit.jsonl (one JSON object per line)
// Methods: log(), getRecent(), exportAsJson(), clear()

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'log_service.dart';

enum AuditOperation {
  upload,
  download,
  delete,
  rename,
  move,
  copy,
  createFolder,
  sync,
}

class AuditEntry {
  final DateTime timestamp;
  final AuditOperation operation;
  final String sourcePath;
  final String? targetPath;
  final String? provider;
  final String? user;
  final int? sizeBytes;
  final bool success;
  final String? error;

  AuditEntry({
    required this.timestamp,
    required this.operation,
    required this.sourcePath,
    this.targetPath,
    this.provider,
    this.user,
    this.sizeBytes,
    required this.success,
    this.error,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'operation': operation.name,
        'sourcePath': sourcePath,
        if (targetPath != null) 'targetPath': targetPath,
        if (provider != null) 'provider': provider,
        if (user != null) 'user': user,
        if (sizeBytes != null) 'sizeBytes': sizeBytes,
        'success': success,
        if (error != null) 'error': error,
      };

  factory AuditEntry.fromJson(Map<String, dynamic> json) {
    AuditOperation op;
    try {
      op = AuditOperation.values.byName(json['operation'] as String);
    } catch (_) {
      op = AuditOperation.upload;
    }
    return AuditEntry(
      timestamp: DateTime.parse(json['timestamp'] as String),
      operation: op,
      sourcePath: json['sourcePath'] as String? ?? '',
      targetPath: json['targetPath'] as String?,
      provider: json['provider'] as String?,
      user: json['user'] as String?,
      sizeBytes: json['sizeBytes'] as int?,
      success: json['success'] as bool? ?? true,
      error: json['error'] as String?,
    );
  }

  @override
  String toString() {
    final ts = timestamp.toIso8601String();
    final status = success ? 'OK' : 'FAIL';
    final op = operation.name.toUpperCase();
    final extra = targetPath != null ? ' -> $targetPath' : '';
    final errStr = error != null ? ' [$error]' : '';
    return '$ts $status $op $sourcePath$extra$errStr';
  }
}

/// Service that appends audit entries to a JSON-lines file and reads them back.
class AuditService {
  static const _log = Log('AuditService');

  String? _logFilePath;

  /// Initialize: resolve the log file path. Safe to call multiple times.
  Future<void> init() async {
    if (kIsWeb) return; // No filesystem on web
    if (_logFilePath != null) return;
    final appDir = await getApplicationSupportDirectory();
    _logFilePath = p.join(appDir.path, 'audit.jsonl');
    _log.info('Audit log at $_logFilePath');
  }

  /// Append an audit entry to the log file.
  Future<void> log(AuditEntry entry) async {
    if (kIsWeb || _logFilePath == null) return;
    try {
      final file = File(_logFilePath!);
      final line = '${jsonEncode(entry.toJson())}\n';
      await file.writeAsString(line, mode: FileMode.append, flush: true);
    } catch (e) {
      _log.warn('Failed to write audit entry', e);
    }
  }

  /// Convenience: log a successful operation.
  Future<void> logSuccess({
    required AuditOperation operation,
    required String sourcePath,
    String? targetPath,
    String? provider,
    String? user,
    int? sizeBytes,
  }) =>
      log(AuditEntry(
        timestamp: DateTime.now(),
        operation: operation,
        sourcePath: sourcePath,
        targetPath: targetPath,
        provider: provider,
        user: user,
        sizeBytes: sizeBytes,
        success: true,
      ));

  /// Convenience: log a failed operation.
  Future<void> logError({
    required AuditOperation operation,
    required String sourcePath,
    String? targetPath,
    String? provider,
    String? user,
    required String error,
  }) =>
      log(AuditEntry(
        timestamp: DateTime.now(),
        operation: operation,
        sourcePath: sourcePath,
        targetPath: targetPath,
        provider: provider,
        user: user,
        success: false,
        error: error,
      ));

  /// Read and return the most recent [count] entries (newest first).
  Future<List<AuditEntry>> getRecent(int count) async {
    if (kIsWeb || _logFilePath == null) return [];
    final file = File(_logFilePath!);
    if (!await file.exists()) return [];

    try {
      final lines = await file.readAsLines();
      final entries = <AuditEntry>[];
      // Iterate from end to get most recent first without loading everything
      for (int i = lines.length - 1; i >= 0 && entries.length < count; i--) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;
        try {
          final json = jsonDecode(line) as Map<String, dynamic>;
          entries.add(AuditEntry.fromJson(json));
        } catch (_) {
          // Skip malformed lines
        }
      }
      return entries;
    } catch (e) {
      _log.warn('Failed to read audit log', e);
      return [];
    }
  }

  /// Export all entries as a formatted JSON array string.
  Future<String> exportAsJson() async {
    if (kIsWeb || _logFilePath == null) return '[]';
    final file = File(_logFilePath!);
    if (!await file.exists()) return '[]';

    try {
      final lines = await file.readAsLines();
      final entries = <Map<String, dynamic>>[];
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          entries.add(jsonDecode(line) as Map<String, dynamic>);
        } catch (_) {}
      }
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(entries);
    } catch (e) {
      _log.warn('Failed to export audit log', e);
      return '[]';
    }
  }

  /// Clear the entire audit log.
  Future<void> clear() async {
    if (kIsWeb || _logFilePath == null) return;
    try {
      final file = File(_logFilePath!);
      if (await file.exists()) {
        await file.writeAsString('');
      }
      _log.info('Audit log cleared');
    } catch (e) {
      _log.warn('Failed to clear audit log', e);
    }
  }

  /// Return the total number of entries in the log file.
  Future<int> count() async {
    if (kIsWeb || _logFilePath == null) return 0;
    final file = File(_logFilePath!);
    if (!await file.exists()) return 0;
    try {
      final lines = await file.readAsLines();
      return lines.where((l) => l.trim().isNotEmpty).length;
    } catch (_) {
      return 0;
    }
  }
}
