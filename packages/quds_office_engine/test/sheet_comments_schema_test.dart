import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

/// CT_Comments requires `<authors>` and `<commentList>`, and a comment's
/// author is an *index* into the author table. Writing a bare `<comment>`
/// list with an `author` name attribute produces a part that strict consumers
/// (openpyxl, the Open XML SDK) reject, even when Excel still opens it.
void main() {
  test('cell comments keep a valid author table and relationship', () {
    var book = SmlWorkbook(
      sheets: [
        SmlWorksheet(name: 'Notes', sheetId: 1),
      ],
    );
    final sheet = book.firstSheet;
    sheet.cellA1('A1').value = 'reviewed';
    sheet.comments.addAll([
      SmlComment(ref: SmlCellRef.parse('A1'), text: 'first', author: 'Alice'),
      SmlComment(ref: SmlCellRef.parse('B2'), text: 'second', author: 'Bob'),
      SmlComment(ref: SmlCellRef.parse('C3'), text: 'again', author: 'Alice'),
    ]);

    var package = SheetSerializer().write(book);
    for (var cycle = 1; cycle <= 2; cycle++) {
      final comments = package.getPart('/xl/worksheets/comments-part.xml') ??
          package.getPart('/xl/comments1.xml');
      expect(comments, isNotNull);
      expect(comments!.contentType, OfficeContentTypes.sheetComments);

      final xml = XmlDocument.parse(comments.readText());
      final authors = xml.root!.firstChild('authors')!;
      expect(
        authors.childElements.map((element) => element.text).toList(),
        ['Alice', 'Bob'],
      );
      final listed = xml.root!.firstChild('commentList')!;
      final commentsXml = listed.childElements.toList();
      expect(commentsXml, hasLength(3));
      expect(commentsXml[0].getAttribute('authorId'), '0');
      expect(commentsXml[1].getAttribute('authorId'), '1');
      expect(commentsXml[2].getAttribute('authorId'), '0');
      expect(commentsXml.first.getAttribute('author'), isNull);

      final worksheet = package.getPart('/xl/worksheets/sheet1.xml')!;
      final rels = package.relationshipsFor(worksheet.uri);
      expect(rels.firstByType(RelationshipTypes.comments), isNotNull);

      book = SheetDeserializer().read(package);
      expect(book.firstSheet.comments.map((c) => c.author), ['Alice', 'Bob', 'Alice']);
      expect(book.firstSheet.comments.map((c) => c.text), ['first', 'second', 'again']);
      package = SheetSerializer().write(book);
    }
  });

  test('reading the legacy author-name attribute still works', () {
    var book = SmlWorkbook(
      sheets: [
        SmlWorksheet(name: 'Sheet1', sheetId: 1),
      ],
    );
    final sheet = book.firstSheet;
    sheet.comments.add(SmlComment(ref: SmlCellRef.parse('A1'), text: 'x'));

    final package = SheetSerializer().write(book);
    final comments = package.getPart('/xl/comments1.xml')!;
    final repaired = comments
        .readText()
        .replaceFirst(RegExp(r'<authors>.*?</authors>', dotAll: true), '')
        .replaceAll(RegExp(r'authorId="\d+"'), 'author="Legacy"')
        .replaceAll('<commentList>', '')
        .replaceAll('</commentList>', '');
    comments.writeText(repaired);

    final reopened = SheetDeserializer().read(package);
    expect(reopened.firstSheet.comments.single.author, 'Legacy');
  });
}
