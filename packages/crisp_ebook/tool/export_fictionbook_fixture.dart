import 'dart:convert';
import 'dart:io';

import 'fictionbook_fixture.dart';
import 'package:crisp_ebook/crisp_ebook.dart';

void main(List<String> arguments) {
  final directory = Directory(
    arguments.isEmpty ? 'build/fictionbook' : arguments.single,
  )..createSync(recursive: true);
  final book = fictionBookFixture();
  final options = FictionBookExportOptions(
    createdAt: DateTime.utc(2026, 11, 12),
  );
  for (final zipped in [false, true]) {
    final result = book.exportFictionBook(zipped: zipped, options: options);
    File(
      '${directory.path}/fixture.${result.extension}',
    ).writeAsBytesSync(result.bytes);
  }
  File('${directory.path}/source.epub').writeAsBytesSync(book.toBytes());
  File('${directory.path}/expected.json').writeAsStringSync(
    jsonEncode({
      'title': book.title,
      'authors': book.authors,
      'language': book.language,
      'image': base64Encode(fictionBookFixtureImage),
    }),
  );
  stdout.writeln('Created FB2/FBZ fixtures in ${directory.path}');
}
