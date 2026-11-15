import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/services/office_document_service.dart';

/// Live smoke test over the ODF files actually present on this machine.
///
/// CI runners have no such files, so the test passes without touching anything
/// when the directories are empty. No file name or content is committed.
void main() {
  final home = Platform.environment['HOME'] ?? '';
  final roots = <Directory>[
    Directory('$home/Downloads'),
    Directory('$home/Documents'),
  ];
  final files = <File>[];
  for (final root in roots) {
    if (!root.existsSync()) continue;
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.path.toLowerCase();
      if (!(name.endsWith('.odt') ||
          name.endsWith('.ods') ||
          name.endsWith('.odp'))) {
        continue;
      }
      if (name.split('/').last.startsWith(r'~$')) continue;
      files.add(entity);
      if (files.length >= 40) break;
    }
    if (files.length >= 40) break;
  }

  test('local ODF corpus parses into typed previews', () async {
    if (files.isEmpty) return;
    for (final file in files) {
      final bytes = await file.readAsBytes();
      final document = await parseOfficeDocument(bytes, file.path);
      expect(
        document.plainText.trim(),
        isNotEmpty,
        reason: 'no text extracted from ${file.path}',
      );
      if (file.path.toLowerCase().endsWith('.ods')) {
        expect(document.csv, isNotNull, reason: 'ODS without table');
      }
      if (file.path.toLowerCase().endsWith('.odp')) {
        expect(
          document.deck != null || document.markdown.contains('## '),
          isTrue,
          reason: 'ODP without slides',
        );
      }
    }
  });
}
