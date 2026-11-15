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
  _writeCollisionFixtures(output);
  stdout.writeln(
    'Wrote three repeated-save and six orphan-collision XLSX packages.',
  );
}

void _writeCollisionFixtures(Directory output) {
  final cases = <Map<String, Object>>[];
  for (final malformed in [false, true]) {
    final original = SmlWorksheet(name: 'Original', sheetId: 1);
    original.cellA1('A1').value = 'Original value';
    original.comments.add(
      SmlComment(
        ref: SmlCellRef.parse('A1'),
        text: 'Original note',
        author: 'Original reviewer',
      ),
    );
    final source = SheetSerializer().write(SmlWorkbook(sheets: [original]));
    const orphanUri = '/xl/comments2.xml';
    final orphanBytes = utf8.encode(
      malformed
          ? '<unrelated xmlns="${OfficeNamespaces.x}"/>'
          : '<comments xmlns="${OfficeNamespaces.x}">'
                '<authors><author>Unrelated author</author></authors>'
                '<commentList><comment ref="A1" authorId="0">'
                '<text><t>Retain this unrelated part</t></text>'
                '</comment></commentList></comments>',
    );
    source.createPart(orphanUri, OfficeContentTypes.sheetComments, orphanBytes);
    final orphanRelationships = source.relationshipsFor(orphanUri)
      ..add(
        id: 'rIdAudit',
        type: 'urn:example:orphan-audit',
        target: 'https://example.test/orphan',
        targetMode: RelationshipTargetMode.external,
      );
    final orphanRelationshipsBytes = utf8.encode(orphanRelationships.toXml());
    var book = SheetDeserializer().readBytes(source.save());
    final added = SmlWorksheet(name: 'Added', sheetId: 2);
    added.cellA1('A1').value = 'New value';
    book.sheets.add(added);
    for (final phase in ['empty', 'added', 'cleared']) {
      final expected = <Map<String, String>>[];
      book.sheets[1].comments.clear();
      if (phase == 'added') {
        const note = ' added & reviewed \n café 🙂 ';
        book.sheets[1].comments.add(
          SmlComment(
            ref: SmlCellRef.parse('B2'),
            text: note,
            author: 'New reviewer',
          ),
        );
        expected.add({'cell': 'B2', 'text': note, 'author': 'New reviewer'});
      }
      final file = 'collision-${malformed ? 'malformed' : 'valid'}-$phase.xlsx';
      final bytes = SheetSerializer().write(book, recalculate: false).save();
      File('${output.path}/$file').writeAsBytesSync(bytes);
      cases.add({
        'file': file,
        'phase': phase,
        'sheet_name': 'Added',
        'orphan_part': 'xl/comments2.xml',
        'orphan_base64': base64Encode(orphanBytes),
        'orphan_content_type': OfficeContentTypes.sheetComments,
        'orphan_relationships_part': 'xl/_rels/comments2.xml.rels',
        'orphan_relationships_base64': base64Encode(orphanRelationshipsBytes),
        'comments': expected,
        'original_sheet_name': 'Original',
        'original_comments': [
          {
            'cell': 'A1',
            'text': 'Original note',
            'author': 'Original reviewer',
          },
        ],
      });
      book = SheetDeserializer().readBytes(bytes);
    }
  }
  File('${output.path}/collision-cases.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'schema_version': 1, 'cases': cases})}\n',
  );
}
