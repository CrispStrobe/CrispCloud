// test/batch_rename_logic_test.dart
//
// Extended batch rename edge cases and action history undo edge cases
// that are not covered in batch_rename_test.dart or action_history_test.dart.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/services/action_history_service.dart';

// Re-define the batch rename helpers (same as batch_rename_test.dart)
// to test edge cases.

String applyFindReplace(String name, String find, String replace, {bool useRegex = false}) {
  if (find.isEmpty) return name;
  if (useRegex) {
    return name.replaceAllMapped(RegExp(find), (m) {
      return replace.replaceAllMapped(RegExp(r'\$(\d+)'), (ref) {
        final groupIndex = int.parse(ref.group(1)!);
        return m.group(groupIndex) ?? '';
      });
    });
  }
  return name.replaceAll(find, replace);
}

String applyNumbering(String name, int index, {int start = 1}) {
  final num = (start + index).toString().padLeft(3, '0');
  final dot = name.lastIndexOf('.');
  if (dot > 0) {
    final ext = name.substring(dot);
    final base = name.substring(0, dot);
    return '${base}_$num$ext';
  }
  return '${name}_$num';
}

String applyPrefixSuffix(String name, String prefix, String suffix) {
  final dot = name.lastIndexOf('.');
  if (dot > 0 && suffix.isNotEmpty) {
    final ext = name.substring(dot);
    final base = name.substring(0, dot);
    return '$prefix$base$suffix$ext';
  }
  return '$prefix$name$suffix';
}

String applyExtension(String name, String newExt) {
  if (newExt.isEmpty) return name;
  final dot = name.lastIndexOf('.');
  if (dot > 0) {
    return '${name.substring(0, dot)}.$newExt';
  }
  return '$name.$newExt';
}

void main() {
  // ---------------------------------------------------------------------------
  // Batch rename edge cases
  // ---------------------------------------------------------------------------
  group('Batch rename edge cases', () {
    test('find/replace with unicode characters', () {
      expect(applyFindReplace('dokument_uberblick.txt', 'uberblick', '\u00FCberblick'), 'dokument_\u00FCberblick.txt');
    });

    test('find/replace preserves emoji in filename', () {
      expect(applyFindReplace('my_file_\u{1F600}.txt', '\u{1F600}', 'smile'), 'my_file_smile.txt');
    });

    test('numbering with very large index', () {
      final result = applyNumbering('file.txt', 9999, start: 1);
      expect(result, 'file_10000.txt');
    });

    test('numbering with zero start', () {
      expect(applyNumbering('file.txt', 0, start: 0), 'file_000.txt');
      expect(applyNumbering('file.txt', 1, start: 0), 'file_001.txt');
    });

    test('prefix/suffix with empty name', () {
      expect(applyPrefixSuffix('', 'pre_', '_suf'), 'pre__suf');
    });

    test('extension change with dotfile', () {
      // .gitignore has lastIndexOf('.') == 0, which is not > 0, so it appends
      expect(applyExtension('.gitignore', 'bak'), '.gitignore.bak');
    });

    test('find/replace with regex special characters (literal)', () {
      // Without regex, special chars are literal
      expect(applyFindReplace('file(1).txt', '(1)', '[1]'), 'file[1].txt');
    });

    test('find/replace with regex dot matches everything', () {
      expect(applyFindReplace('abc.txt', '.', 'X', useRegex: true), 'XXXXXXX');
    });

    test('prefix on file with no extension', () {
      expect(applyPrefixSuffix('LICENSE', 'OLD_', ''), 'OLD_LICENSE');
    });

    test('suffix on file with no extension is appended directly', () {
      // When dot is not > 0, suffix is appended after name
      expect(applyPrefixSuffix('Makefile', '', '_old'), 'Makefile_old');
    });

    test('very long filename with numbering', () {
      final longName = 'a' * 200 + '.txt';
      final result = applyNumbering(longName, 0);
      expect(result.endsWith('_001.txt'), true);
      expect(result.length, 208); // 200 + '_001' + '.txt'
    });
  });

  // ---------------------------------------------------------------------------
  // ActionHistoryService undo edge cases
  // ---------------------------------------------------------------------------
  group('ActionHistoryService undo edge cases', () {
    late ActionHistoryService svc;

    setUp(() {
      svc = ActionHistoryService();
    });

    test('undo rename without newPath returns failure', () async {
      svc.recordNew(
        type: ActionType.rename,
        originalPath: '/dir/old.txt',
        provider: 'filen',
      );
      final ctx = UndoContext(
        remoteRename: (path, name) async {},
      );
      final result = await svc.undo(svc.history.first.id, ctx);
      expect(result.success, false);
      expect(result.message, contains('new path unknown'));
    });

    test('undo move without newPath returns failure', () async {
      svc.recordNew(
        type: ActionType.move,
        originalPath: '/src/file.txt',
        provider: 'filen',
      );
      final ctx = UndoContext(
        remoteMove: (path, dir) async {},
      );
      final result = await svc.undo(svc.history.first.id, ctx);
      expect(result.success, false);
      expect(result.message, contains('destination unknown'));
    });

    test('undo delete without restoreFromTrash callback fails', () async {
      svc.recordNew(
        type: ActionType.delete,
        originalPath: '/remote/file.txt',
        provider: 'filen',
      );
      final result = await svc.undo(svc.history.first.id, const UndoContext());
      expect(result.success, false);
      expect(result.message, contains('trash'));
    });

    test('undo createFolder remote without remoteDelete callback fails', () async {
      svc.recordNew(
        type: ActionType.createFolder,
        originalPath: '/remote/newfolder',
        provider: 's3',
      );
      final result = await svc.undo(svc.history.first.id, const UndoContext());
      expect(result.success, false);
      expect(result.message, contains('no remote delete'));
    });

    test('undo copy remote without remoteDelete callback fails', () async {
      svc.recordNew(
        type: ActionType.copy,
        originalPath: '/remote/copy.txt',
        newPath: '/remote/orig.txt',
        provider: 'gdrive',
      );
      final result = await svc.undo(svc.history.first.id, const UndoContext());
      expect(result.success, false);
      expect(result.message, contains('no remote delete'));
    });

    test('undo rename remote without remoteRename callback fails', () async {
      svc.recordNew(
        type: ActionType.rename,
        originalPath: '/dir/old.txt',
        newPath: '/dir/new.txt',
        provider: 'gdrive',
      );
      final result = await svc.undo(svc.history.first.id, const UndoContext());
      expect(result.success, false);
      expect(result.message, contains('no remote rename'));
    });

    test('undo move remote without remoteMove callback fails', () async {
      svc.recordNew(
        type: ActionType.move,
        originalPath: '/src/file.txt',
        newPath: '/dst/file.txt',
        provider: 'onedrive',
      );
      final result = await svc.undo(svc.history.first.id, const UndoContext());
      expect(result.success, false);
      expect(result.message, contains('no remote move'));
    });

    test('successful undo removes action from history', () async {
      final dir = await Directory.systemTemp.createTemp('crisp_undo_edge_');
      try {
        svc.recordNew(
          type: ActionType.createFolder,
          originalPath: dir.path,
          provider: 'local',
        );
        expect(svc.history.length, 1);
        final result = await svc.undo(svc.history.first.id, const UndoContext());
        expect(result.success, true);
        expect(svc.history, isEmpty);
      } finally {
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    });

    test('undo local rename where source is gone throws and returns failure', () async {
      svc.recordNew(
        type: ActionType.rename,
        originalPath: '/tmp/nonexistent_old.txt',
        newPath: '/tmp/nonexistent_new.txt',
        provider: 'local',
      );
      final result = await svc.undo(svc.history.first.id, const UndoContext());
      expect(result.success, false);
      expect(result.message, contains('failed'));
    });

    test('record with metadata preserves it', () {
      svc.recordNew(
        type: ActionType.rename,
        originalPath: '/a',
        newPath: '/b',
        provider: 'local',
        metadata: {'reason': 'batch rename', 'count': 5},
      );
      final action = svc.history.first;
      expect(action.metadata['reason'], 'batch rename');
      expect(action.metadata['count'], 5);
    });
  });

  // ---------------------------------------------------------------------------
  // UndoResult
  // ---------------------------------------------------------------------------
  group('UndoResult', () {
    test('success creates result with success=true', () {
      const r = UndoResult.success('done');
      expect(r.success, true);
      expect(r.message, 'done');
    });

    test('failure creates result with success=false', () {
      const r = UndoResult.failure('oops');
      expect(r.success, false);
      expect(r.message, 'oops');
    });
  });
}
