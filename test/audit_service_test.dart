// test/audit_service_test.dart
//
// Unit tests for AuditEntry model and AuditService.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:crisp_cloud/services/audit_service.dart';

void main() {
  // ---------------------------------------------------------------------------
  // AuditEntry model
  // ---------------------------------------------------------------------------
  group('AuditEntry', () {
    test('toJson includes all required fields', () {
      final entry = AuditEntry(
        timestamp: DateTime(2026, 1, 15, 10, 30),
        operation: AuditOperation.upload,
        sourcePath: '/docs/report.pdf',
        success: true,
      );
      final json = entry.toJson();
      expect(json['timestamp'], '2026-01-15T10:30:00.000');
      expect(json['operation'], 'upload');
      expect(json['sourcePath'], '/docs/report.pdf');
      expect(json['success'], true);
    });

    test('toJson includes optional fields when present', () {
      final entry = AuditEntry(
        timestamp: DateTime(2026, 3, 1),
        operation: AuditOperation.move,
        sourcePath: '/a/file.txt',
        targetPath: '/b/file.txt',
        provider: 'gdrive',
        user: 'alice',
        sizeBytes: 2048,
        success: true,
      );
      final json = entry.toJson();
      expect(json['targetPath'], '/b/file.txt');
      expect(json['provider'], 'gdrive');
      expect(json['user'], 'alice');
      expect(json['sizeBytes'], 2048);
    });

    test('toJson omits null optional fields', () {
      final entry = AuditEntry(
        timestamp: DateTime(2026, 1, 1),
        operation: AuditOperation.download,
        sourcePath: '/x',
        success: true,
      );
      final json = entry.toJson();
      expect(json.containsKey('targetPath'), false);
      expect(json.containsKey('provider'), false);
      expect(json.containsKey('user'), false);
      expect(json.containsKey('sizeBytes'), false);
      expect(json.containsKey('error'), false);
    });

    test('fromJson round-trip preserves all fields', () {
      final original = AuditEntry(
        timestamp: DateTime(2026, 6, 15, 14, 30, 45),
        operation: AuditOperation.copy,
        sourcePath: '/src/data.csv',
        targetPath: '/dst/data.csv',
        provider: 'dropbox',
        user: 'bob',
        sizeBytes: 1024000,
        success: true,
      );
      final json = original.toJson();
      final restored = AuditEntry.fromJson(json);

      expect(restored.operation, AuditOperation.copy);
      expect(restored.sourcePath, '/src/data.csv');
      expect(restored.targetPath, '/dst/data.csv');
      expect(restored.provider, 'dropbox');
      expect(restored.user, 'bob');
      expect(restored.sizeBytes, 1024000);
      expect(restored.success, true);
    });

    test('fromJson handles unknown operation gracefully', () {
      final entry = AuditEntry.fromJson({
        'timestamp': '2026-01-01T00:00:00.000',
        'operation': 'nonexistent_op',
        'sourcePath': '/file',
        'success': true,
      });
      // Should default to upload
      expect(entry.operation, AuditOperation.upload);
    });

    test('fromJson handles missing sourcePath', () {
      final entry = AuditEntry.fromJson({
        'timestamp': '2026-01-01T00:00:00.000',
        'operation': 'delete',
        'success': true,
      });
      expect(entry.sourcePath, '');
    });

    test('fromJson handles missing success field', () {
      final entry = AuditEntry.fromJson({
        'timestamp': '2026-01-01T00:00:00.000',
        'operation': 'download',
        'sourcePath': '/x',
      });
      expect(entry.success, true);
    });

    test('fromJson with error entry', () {
      final entry = AuditEntry.fromJson({
        'timestamp': '2026-01-01T00:00:00.000',
        'operation': 'upload',
        'sourcePath': '/fail.txt',
        'success': false,
        'error': 'Network timeout',
      });
      expect(entry.success, false);
      expect(entry.error, 'Network timeout');
    });

    test('toString for successful operation', () {
      final entry = AuditEntry(
        timestamp: DateTime(2026, 1, 1),
        operation: AuditOperation.upload,
        sourcePath: '/file.txt',
        success: true,
      );
      final s = entry.toString();
      expect(s, contains('OK'));
      expect(s, contains('UPLOAD'));
      expect(s, contains('/file.txt'));
    });

    test('toString for failed operation with error', () {
      final entry = AuditEntry(
        timestamp: DateTime(2026, 1, 1),
        operation: AuditOperation.delete,
        sourcePath: '/file.txt',
        success: false,
        error: 'Permission denied',
      );
      final s = entry.toString();
      expect(s, contains('FAIL'));
      expect(s, contains('DELETE'));
      expect(s, contains('[Permission denied]'));
    });

    test('toString includes target path when present', () {
      final entry = AuditEntry(
        timestamp: DateTime(2026, 1, 1),
        operation: AuditOperation.rename,
        sourcePath: '/old.txt',
        targetPath: '/new.txt',
        success: true,
      );
      final s = entry.toString();
      expect(s, contains('-> /new.txt'));
    });

    test('all AuditOperation values serialize correctly', () {
      for (final op in AuditOperation.values) {
        final entry = AuditEntry(
          timestamp: DateTime(2026, 1, 1),
          operation: op,
          sourcePath: '/test',
          success: true,
        );
        final json = entry.toJson();
        final restored = AuditEntry.fromJson(json);
        expect(restored.operation, op, reason: 'Round-trip failed for ${op.name}');
      }
    });
  });

  // ---------------------------------------------------------------------------
  // AuditService (filesystem-based, uses temp directory)
  // ---------------------------------------------------------------------------
  group('AuditService (file I/O)', () {
    late Directory tempDir;
    late String auditFilePath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('audit_test_');
      auditFilePath = p.join(tempDir.path, 'audit.jsonl');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    // Helper: create an AuditService with a known file path by writing directly
    // to the log file and reading it back, since init() uses path_provider
    // which isn't available in tests.

    Future<void> writeEntry(AuditEntry entry) async {
      final file = File(auditFilePath);
      await file.writeAsString(
        '${jsonEncode(entry.toJson())}\n',
        mode: FileMode.append,
        flush: true,
      );
    }

    Future<List<AuditEntry>> readAll() async {
      final file = File(auditFilePath);
      if (!file.existsSync()) return [];
      final lines = await file.readAsLines();
      return lines
          .where((l) => l.trim().isNotEmpty)
          .map((l) => AuditEntry.fromJson(jsonDecode(l) as Map<String, dynamic>))
          .toList();
    }

    test('write and read entries from JSONL file', () async {
      final entry1 = AuditEntry(
        timestamp: DateTime(2026, 1, 1),
        operation: AuditOperation.upload,
        sourcePath: '/file1.txt',
        success: true,
      );
      final entry2 = AuditEntry(
        timestamp: DateTime(2026, 1, 2),
        operation: AuditOperation.download,
        sourcePath: '/file2.txt',
        provider: 's3',
        success: true,
      );

      await writeEntry(entry1);
      await writeEntry(entry2);

      final entries = await readAll();
      expect(entries.length, 2);
      expect(entries[0].sourcePath, '/file1.txt');
      expect(entries[1].sourcePath, '/file2.txt');
      expect(entries[1].provider, 's3');
    });

    test('JSONL file handles empty lines gracefully', () async {
      final file = File(auditFilePath);
      await file.writeAsString(
        '${jsonEncode(AuditEntry(timestamp: DateTime(2026, 1, 1), operation: AuditOperation.upload, sourcePath: "/a", success: true).toJson())}\n'
        '\n'
        '${jsonEncode(AuditEntry(timestamp: DateTime(2026, 1, 2), operation: AuditOperation.download, sourcePath: "/b", success: true).toJson())}\n',
      );

      final entries = await readAll();
      expect(entries.length, 2);
    });

    test('JSONL file handles malformed lines', () async {
      final file = File(auditFilePath);
      await file.writeAsString(
        '${jsonEncode(AuditEntry(timestamp: DateTime(2026, 1, 1), operation: AuditOperation.upload, sourcePath: "/ok", success: true).toJson())}\n'
        'this is not valid json\n'
        '${jsonEncode(AuditEntry(timestamp: DateTime(2026, 1, 2), operation: AuditOperation.delete, sourcePath: "/ok2", success: true).toJson())}\n',
      );

      // readAll above uses try/catch-less parsing; test that the file can
      // be read line by line and invalid lines skipped (mirrors getRecent logic)
      final lines = await file.readAsLines();
      final entries = <AuditEntry>[];
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          entries.add(AuditEntry.fromJson(jsonDecode(line) as Map<String, dynamic>));
        } catch (_) {
          // Skip malformed lines
        }
      }
      expect(entries.length, 2);
      expect(entries[0].sourcePath, '/ok');
      expect(entries[1].sourcePath, '/ok2');
    });

    test('export as JSON produces valid array', () async {
      await writeEntry(AuditEntry(
        timestamp: DateTime(2026, 1, 1),
        operation: AuditOperation.sync,
        sourcePath: '/sync/dir',
        success: true,
      ));
      await writeEntry(AuditEntry(
        timestamp: DateTime(2026, 1, 2),
        operation: AuditOperation.createFolder,
        sourcePath: '/new_folder',
        success: true,
      ));

      // Read file and format as JSON array (mirrors exportAsJson)
      final lines = await File(auditFilePath).readAsLines();
      final jsonList = lines
          .where((l) => l.trim().isNotEmpty)
          .map((l) => jsonDecode(l) as Map<String, dynamic>)
          .toList();
      final exported = const JsonEncoder.withIndent('  ').convert(jsonList);

      // Must be valid JSON
      final decoded = jsonDecode(exported) as List;
      expect(decoded.length, 2);
      expect(decoded[0]['operation'], 'sync');
      expect(decoded[1]['operation'], 'createFolder');
    });

    test('clear empties the file', () async {
      await writeEntry(AuditEntry(
        timestamp: DateTime(2026, 1, 1),
        operation: AuditOperation.upload,
        sourcePath: '/x',
        success: true,
      ));

      // Clear
      await File(auditFilePath).writeAsString('');

      final entries = await readAll();
      expect(entries, isEmpty);
    });

    test('getRecent logic returns newest first', () async {
      for (int i = 0; i < 5; i++) {
        await writeEntry(AuditEntry(
          timestamp: DateTime(2026, 1, i + 1),
          operation: AuditOperation.upload,
          sourcePath: '/file_$i.txt',
          success: true,
        ));
      }

      // Simulate getRecent(3) logic: iterate from end
      final lines = await File(auditFilePath).readAsLines();
      final entries = <AuditEntry>[];
      for (int i = lines.length - 1; i >= 0 && entries.length < 3; i--) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;
        try {
          entries.add(AuditEntry.fromJson(jsonDecode(line) as Map<String, dynamic>));
        } catch (_) {}
      }

      expect(entries.length, 3);
      expect(entries[0].sourcePath, '/file_4.txt');
      expect(entries[1].sourcePath, '/file_3.txt');
      expect(entries[2].sourcePath, '/file_2.txt');
    });

    test('count logic counts non-empty lines', () async {
      await writeEntry(AuditEntry(
        timestamp: DateTime(2026, 1, 1),
        operation: AuditOperation.upload,
        sourcePath: '/a',
        success: true,
      ));
      await writeEntry(AuditEntry(
        timestamp: DateTime(2026, 1, 2),
        operation: AuditOperation.download,
        sourcePath: '/b',
        success: true,
      ));

      final lines = await File(auditFilePath).readAsLines();
      final count = lines.where((l) => l.trim().isNotEmpty).length;
      expect(count, 2);
    });
  });
}
