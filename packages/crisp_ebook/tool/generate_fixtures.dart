import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crisp_ebook/crisp_ebook.dart';

/// Small deterministic-content fixtures for manual readers / EPUBCheck. This
/// tool writes only to the explicitly supplied directory (or .dart_tool).
void main(List<String> arguments) {
  final directory = Directory(
    arguments.isEmpty ? '.dart_tool/epub_fixtures' : arguments.single,
  )..createSync(recursive: true);
  final book = EpubDocument.create(
    title: 'CrispCloud EPUB fixture',
    authors: ['CrispCloud'],
    language: 'en',
  );
  book.addChapter(
    title: 'Second chapter',
    text: 'A paragraph with an ampersand & a Unicode word: Bücher.',
  );
  final fresh = book.toBytes();
  File('${directory.path}/new-book.epub').writeAsBytesSync(fresh);

  final input = ZipDecoder().decodeBytes(fresh, verify: true);
  final archive = Archive();
  for (final entry in input.files) {
    final oldName = entry.name;
    final newName = oldName == 'EPUB/package.opf'
        ? 'Nested/Publication/content.opf'
        : oldName.startsWith('EPUB/')
        ? oldName.replaceFirst('EPUB/', 'Nested/Publication/')
        : oldName;
    var bytes = entry.readBytes()!;
    if (oldName == 'META-INF/container.xml') {
      bytes = Uint8List.fromList(
        utf8.encode(
          utf8
              .decode(bytes)
              .replaceFirst(
                'EPUB/package.opf',
                'Nested/Publication/content.opf',
              ),
        ),
      );
    }
    archive.addFile(
      newName == 'mimetype'
          ? ArchiveFile.noCompress(newName, bytes.length, bytes)
          : ArchiveFile.bytes(newName, bytes),
    );
  }
  archive.addFile(
    ArchiveFile.string('META-INF/crisp-extra.json', '{"preserve":true}'),
  );
  final unusual = ZipEncoder().encodeBytes(archive);
  File('${directory.path}/nonstandard-path.epub').writeAsBytesSync(unusual);
  final opened = EpubDocument.open(unusual);
  if (!_equal(unusual, opened.toBytes()))
    throw StateError('No-op bytes changed');
  final originalResources = {
    for (final r in opened.resources) r.path: opened.readBytes(r.path),
  };
  opened.updateMetadata(title: 'Edited package-preserving fixture');
  final edited = opened.toBytes();
  final reopened = EpubDocument.open(edited);
  for (final entry in originalResources.entries) {
    if (entry.key != opened.packagePath &&
        !_equal(entry.value, reopened.readBytes(entry.key))) {
      throw StateError('Unchanged resource changed: ${entry.key}');
    }
  }
  File('${directory.path}/edited-copy.epub').writeAsBytesSync(edited);

  final styledSource = EpubDocument.open(fresh);
  final chapterPath = styledSource.chapters.first.path;
  styledSource.updateText(chapterPath, '''<?xml version="1.0" encoding="UTF-8"?>
<x:html xmlns:x="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="en" lang="en">
<x:head><x:title>Formatting-preserving corrections</x:title></x:head>
<x:body><x:section epub:type="chapter"><x:h1>Formatting-preserving corrections</x:h1>
<x:p id="formatted" class="publisher-style">A <x:em xml:lang="de"><x:strong>mispelled</x:strong></x:em> word;
<x:a href="#destination" id="original-link">lable</x:a> and <x:span class="keep-inline">Bucher 🐦</x:span><x:br id="original-break"/>A second line.</x:p>
<x:p id="destination">The original link destination remains intact.</x:p>
</x:section></x:body></x:html>''');
  final formatted = EpubDocument.open(styledSource.toBytes());
  final formattedResources = {
    for (final resource in formatted.resources)
      resource.path: formatted.readBytes(resource.path),
  };
  final paragraph = formatted
      .readStructuredProse(chapterPath)
      .firstWhere((block) => block.id == 'formatted');
  final replacements = {
    'mispelled': 'misspelled',
    'lable': 'label',
    'Bucher 🐦': 'Bücher 🐦',
  };
  formatted.updateStructuredProseBlock(paragraph, {
    for (final segment in paragraph.segments)
      if (replacements.containsKey(segment.text))
        segment.index: replacements[segment.text]!,
  });
  final corrected = EpubDocument.open(formatted.toBytes());
  for (final entry in formattedResources.entries) {
    if (entry.key != formatted.packagePath &&
        entry.key != chapterPath &&
        !_equal(entry.value, corrected.readBytes(entry.key))) {
      throw StateError(
        'Structured correction changed another resource: ${entry.key}',
      );
    }
  }
  final correctedSource = corrected.readText(chapterPath);
  for (final expected in [
    '<x:em xml:lang="de"><x:strong>misspelled</x:strong></x:em>',
    '<x:a href="#destination" id="original-link">label</x:a>',
    '<x:span class="keep-inline">Bücher 🐦</x:span>',
    '<x:br id="original-break"/>',
  ]) {
    if (!correctedSource.contains(expected)) {
      throw StateError(
        'Structured correction did not preserve expected markup: $expected',
      );
    }
  }
  File(
    '${directory.path}/formatted-text-edit.epub',
  ).writeAsBytesSync(corrected.toBytes());
  stdout.writeln(
    'Generated four EPUB fixtures; exact no-op, resource and inline-markup preservation verified.',
  );
}

bool _equal(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
