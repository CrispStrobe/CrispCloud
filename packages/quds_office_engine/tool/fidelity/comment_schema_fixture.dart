import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';

/// Emit actual XLSX bytes for an independent comments reader/schema check.
void main(List<String> args) {
  if (args.length != 1) {
    throw ArgumentError('Usage: comment_schema_fixture.dart OUTPUT_DIRECTORY');
  }
  final output = Directory(args.single)..createSync(recursive: true);
  const texts = [
    'plain comment',
    ' leading',
    'trailing ',
    ' \tline one\nline two \t ',
    '',
    'A&B <tag> "quote" — café 🙂',
  ];
  final sheet = SmlWorksheet(name: 'Notes', sheetId: 1);
  final expected = <Map<String, String>>[];
  for (var index = 0; index < texts.length; index++) {
    final reference = 'A${index + 1}';
    final author = index.isEven ? 'Alice & Co' : 'Bob';
    sheet.cellA1(reference).value = 'reviewed ${index + 1}';
    sheet.comments.add(
      SmlComment(
        ref: SmlCellRef.parse(reference),
        text: texts[index],
        author: author,
      ),
    );
    expected.add({'cell': reference, 'text': texts[index], 'author': author});
  }
  var book = SmlWorkbook(sheets: [sheet]);
  for (var cycle = 1; cycle <= 3; cycle++) {
    final bytes = SheetSerializer().write(book).save();
    File('${output.path}/comments-cycle-$cycle.xlsx').writeAsBytesSync(bytes);
    book = SheetDeserializer().readBytes(bytes);
  }
  File('${output.path}/expected-comments.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(expected)}\n',
  );
  stdout.writeln('Wrote three XLSX packages with six comments each.');
}
