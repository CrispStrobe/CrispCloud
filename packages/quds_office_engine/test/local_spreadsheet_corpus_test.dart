import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

/// Live smoke test over legacy spreadsheets on this machine.
///
/// CI runners have no such files; the test passes without reading anything
/// when the directories are empty. No file name or content is committed.
void main() {
  final home = Platform.environment['HOME'] ?? '';
  final roots = <Directory>[
    Directory('$home/Downloads'),
    Directory('$home/Documents'),
  ];

  List<File> filesWith(String extension) {
    final files = <File>[];
    for (final root in roots) {
      if (!root.existsSync()) continue;
      for (final entity in root.listSync(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.path.toLowerCase();
        if (!name.endsWith(extension)) continue;
        if (name.split('/').last.startsWith('~\$')) continue;
        files.add(entity);
        if (files.length >= 30) return files;
      }
    }
    return files;
  }

  test('local ODS corpus imports', () {
    final files = filesWith('.ods');
    for (final file in files) {
      final book = OdsSheetReader.readBytes(file.readAsBytesSync());
      expect(book.sheets, isNotEmpty, reason: file.path);
      expect(
        book.sheets.any((sheet) => sheet.allCells.isNotEmpty),
        isTrue,
        reason: 'empty ODS ${file.path}',
      );
    }
  });

  test('local XLS corpus imports', () {
    final files = filesWith('.xls');
    for (final file in files) {
      final book = LegacySheetReader.readBytes(file.readAsBytesSync());
      expect(book.sheets, isNotEmpty, reason: file.path);
    }
  });
}
