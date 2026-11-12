import 'dart:convert';
import 'dart:io';

import 'package:crisp_ebook/crisp_ebook.dart';

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

/// Completes the independent FB2 -> Foliate -> EPUB editor -> FB2 chain.
void main(List<String> args) {
  require(args.length == 1, 'usage: import_fictionbook_fixture.dart DIRECTORY');
  final directory = Directory(args.single);
  final payload = jsonDecode(
    File('${directory.path}/imported.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final imported = EpubDocument.fromPublication(payload);
  require(
    !imported.validate().any((issue) => issue.isError),
    'The independently normalized FictionBook failed core validation.',
  );
  final document = EpubDocument.open(imported.toBytes());
  const before = 'A corrected destination — 東京.';
  const after = 'Edited after FictionBook import — 東京.';
  var replacements = 0;
  for (final chapter in document.chapters) {
    final text = document.readText(chapter.path);
    if (!text.contains(before)) continue;
    replacements += before.allMatches(text).length;
    document.updateText(chapter.path, text.replaceAll(before, after));
  }
  require(replacements == 1, 'Expected exactly one editable destination.');
  require(document.dirty, 'Editing the normalized publication had no effect.');
  final result = document.exportFictionBook(
    options: FictionBookExportOptions(createdAt: DateTime.utc(2026, 11, 12)),
  );
  File('${directory.path}/roundtrip.fb2').writeAsBytesSync(result.bytes);
  stdout.writeln(
    'Imported FictionBook, reopened EPUB, edited Unicode prose, and exported FB2.',
  );
}
