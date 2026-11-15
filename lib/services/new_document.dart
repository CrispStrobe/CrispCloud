import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as image;
import 'package:pdf_document/pdf_document.dart' show PdfBlankDocument;
import 'package:quds_office_engine/quds_office_engine.dart';

import '../models/file_item.dart';
import 'file_operation_service.dart';
import 'file_integrity_service.dart';

enum NewDocumentKind {
  text('Text / code', 'txt'),
  markdown('Markdown', 'md'),
  csv('CSV table', 'csv'),
  word('Word document', 'docx'),
  spreadsheet('Spreadsheet', 'xlsx'),
  presentation('Presentation', 'pptx'),
  pdf('PDF', 'pdf'),
  picture('Image', 'png'),
  ebook('EPUB book', 'epub');

  const NewDocumentKind(this.label, this.extension);
  final String label, extension;
}

Future<Uint8List> newDocumentBytes(
  NewDocumentKind kind, {
  String title = 'Untitled',
}) async {
  switch (kind) {
    case NewDocumentKind.text:
    case NewDocumentKind.csv:
      return Uint8List(0);
    case NewDocumentKind.markdown:
      return Uint8List.fromList(utf8.encode('# $title\n\n'));
    case NewDocumentKind.word:
      return OfficeIsolateSave.word(WmlDocument.empty());
    case NewDocumentKind.spreadsheet:
      return OfficeIsolateSave.workbook(SmlWorkbook(), recalculate: false);
    case NewDocumentKind.presentation:
      return OfficeIsolateSave.presentation(PmlPresentation());
    case NewDocumentKind.pdf:
      return PdfBlankDocument.create();
    case NewDocumentKind.picture:
      final canvas = image.Image(width: 1024, height: 768);
      image.fill(canvas, color: image.ColorRgb8(255, 255, 255));
      return Uint8List.fromList(image.encodePng(canvas));
    case NewDocumentKind.ebook:
      String xml(String text) => text
          .replaceAll('&', '&amp;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;')
          .replaceAll('"', '&quot;')
          .replaceAll("'", '&apos;');
      final book = Archive();
      final mime = ArchiveFile.string('mimetype', 'application/epub+zip')
        ..compression = CompressionType.none;
      book.addFile(mime);
      book.addFile(
        ArchiveFile.string(
          'META-INF/container.xml',
          '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="EPUB/book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',
        ),
      );
      book.addFile(
        ArchiveFile.string(
          'EPUB/book.opf',
          '<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">urn:crispcloud:book:${DateTime.now().microsecondsSinceEpoch}</dc:identifier><dc:title>${xml(title)}</dc:title><dc:language>en</dc:language><meta property="dcterms:modified">${DateTime.now().toUtc().toIso8601String().split('.').first}Z</meta></metadata><manifest><item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/></manifest><spine><itemref idref="chapter"/></spine></package>',
        ),
      );
      book.addFile(
        ArchiveFile.string(
          'EPUB/chapter.xhtml',
          '<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>${xml(title)}</title></head><body><h1>${xml(title)}</h1><p> </p></body></html>',
        ),
      );
      book.addFile(
        ArchiveFile.string(
          'EPUB/nav.xhtml',
          '<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Contents</title></head><body><nav epub:type="toc"><ol><li><a href="chapter.xhtml">${xml(title)}</a></li></ol></nav></body></html>',
        ),
      );
      return Uint8List.fromList(ZipEncoder().encode(book));
  }
}

String validateNewDocumentName(String name, NewDocumentKind kind) {
  final stem = name.split('.').first.toUpperCase();
  if (name.trim() != name ||
      name.isEmpty ||
      name == '.' ||
      name == '..' ||
      name.endsWith('.') ||
      utf8.encode(name).length > 240 ||
      RegExp(r'[<>:"/\\|?*\x00-\x1f\x7f]').hasMatch(name) ||
      const {'CON', 'PRN', 'AUX', 'NUL'}.contains(stem) ||
      RegExp(r'^(COM|LPT)[1-9]$').hasMatch(stem)) {
    throw const FormatException(
      'Choose a simple filename without path separators.',
    );
  }
  if (kind == NewDocumentKind.text) {
    return name.contains('.') ? name : '$name.txt';
  }
  if (!name.toLowerCase().endsWith('.${kind.extension}')) {
    if (name.contains('.')) {
      throw FormatException(
        'Use the .${kind.extension} extension for this editor.',
      );
    }
    return '$name.${kind.extension}';
  }
  return name;
}

Future<FileItem> createNewDocument({
  required FileOperationBackend backend,
  required String directory,
  required String name,
  required NewDocumentKind kind,
  Uint8List? content,
}) async {
  final valid = validateNewDocumentName(name, kind);
  checkIntegrityCurrent(backend, null);
  if (!backend.paths.isAbsolute(directory)) {
    throw StateError('Reopen the destination folder first.');
  }
  final output = backend.paths.join(directory, valid);
  if (!backend.samePath(backend.paths.dirname(output), directory)) {
    throw StateError('The destination changed.');
  }
  final listed = await backend.list(directory);
  checkIntegrityCurrent(backend, null);
  if (listed.any(
    (f) => backend.samePath(
      f.path ?? backend.paths.join(directory, f.name),
      output,
    ),
  )) {
    throw StateError('A file already exists: $valid');
  }
  final bytes =
      content ??
      await newDocumentBytes(
        kind,
        title: backend.paths.basenameWithoutExtension(valid),
      );
  await writeIntegrityBytes(backend, output, bytes, replace: false);
  final saved = await backend.stat(output);
  checkIntegrityCurrent(backend, null);
  if (saved == null || saved.isFolder || saved.isSymlink == true) {
    throw StateError('The new document could not be verified.');
  }
  return saved.copyWith(path: output);
}
