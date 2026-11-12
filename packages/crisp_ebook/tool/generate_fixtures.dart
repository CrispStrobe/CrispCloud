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
  stdout.writeln(
    'Generated three EPUB fixtures; exact no-op and resource preservation verified.',
  );
}

bool _equal(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
