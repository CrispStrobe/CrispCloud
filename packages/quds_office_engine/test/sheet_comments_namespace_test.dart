import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

// ISO/IEC 29500-1, 18.7.5 (comment text) and A.2 (CT_Rst): comment
// text is a rich-string container, with plain text in an x:t child.
// https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.spreadsheet.commenttext
SmlWorkbook _workbook(String text) {
  final sheet = SmlWorksheet(name: 'Notes', sheetId: 1);
  sheet.cellA1('A1').value = 'reviewed';
  sheet.comments.addAll([
    SmlComment(ref: SmlCellRef.parse('A1'), text: text, author: 'Alice & Co'),
    SmlComment(ref: SmlCellRef.parse('B2'), text: 'second', author: 'Bob'),
    SmlComment(
      ref: SmlCellRef.parse('C3'),
      text: 'again',
      author: 'Alice & Co',
    ),
  ]);
  return SmlWorkbook(sheets: [sheet]);
}

Iterable<XmlElement> _elements(XmlElement element) sync* {
  yield element;
  for (final child in element.childElements) {
    yield* _elements(child);
  }
}

const _relocatedComments = '/xl/annotations/note42.xml';

OpcPackage _relocatedPackage({bool keepLegacyDecoy = false}) {
  final package = SheetSerializer().write(_workbook('legacy decoy'));
  // Independently authored valid source avoids relying on the serializer's
  // output shape for import and relationship coverage.
  package.createPart(
    _relocatedComments,
    OfficeContentTypes.sheetComments,
    utf8.encode(
      '<comments xmlns="${OfficeNamespaces.x}">'
      '<authors><author>Original</author></authors>'
      '<commentList><comment ref="A1" authorId="0">'
      '<text><t xml:space="preserve"> authored note </t></text>'
      '</comment></commentList></comments>',
    ),
  );
  final rels = package.relationshipsFor('/xl/worksheets/sheet1.xml');
  final original = rels.firstByType(RelationshipTypes.comments)!;
  rels.removeById(original.id);
  rels.add(
    id: original.id,
    type: RelationshipTypes.comments,
    target: '../annotations/note42.xml',
  );
  if (!keepLegacyDecoy) package.deletePart('/xl/comments1.xml');
  return OpcPackage.openBytes(package.save());
}

void main() {
  test('import and edit follow the authored comments relationship', () {
    final source = _relocatedPackage();
    var book = SheetDeserializer().read(source);
    expect(book.firstSheet.comments, hasLength(1));
    expect(book.firstSheet.comments.single.text, ' authored note ');
    expect(book.firstSheet.comments.single.author, 'Original');
    book.firstSheet.comments.single
      ..text = ' changed & reviewed '
      ..author = 'Reviewer';

    for (var cycle = 1; cycle <= 3; cycle++) {
      final package = OpcPackage.openBytes(
        SheetSerializer().write(book).save(),
      );
      final rels = package.relationshipsFor('/xl/worksheets/sheet1.xml');
      final commentsRel = rels.firstByType(RelationshipTypes.comments)!;
      expect(rels.resolve(commentsRel), _relocatedComments);
      expect(package.getPart('/xl/comments1.xml'), isNull);
      expect(package.getPart(_relocatedComments), isNotNull);
      book = SheetDeserializer().read(package);
      expect(book.firstSheet.comments, hasLength(1));
      expect(book.firstSheet.comments.single.text, ' changed & reviewed ');
      expect(book.firstSheet.comments.single.author, 'Reviewer');
    }
  });

  test('authored comments relationship takes priority over legacy naming', () {
    final book = SheetDeserializer().read(
      _relocatedPackage(keepLegacyDecoy: true),
    );
    expect(book.firstSheet.comments, hasLength(1));
    expect(book.firstSheet.comments.single.text, ' authored note ');
  });

  for (final shared in [false, true]) {
    test(
      'clearing ${shared ? 'shared ' : ''}relocated comments cannot expose a legacy decoy',
      () {
        var source = _relocatedPackage(keepLegacyDecoy: true);
        if (shared) {
          final setup = SheetDeserializer().read(source);
          setup.sheets.add(SmlWorksheet(name: 'Other', sheetId: 2));
          source = SheetSerializer().write(setup);
          source
              .relationshipsFor('/xl/worksheets/sheet2.xml')
              .add(
                type: RelationshipTypes.comments,
                target: '../annotations/note42.xml',
              );
        }
        final decoyBytes = source.getPart('/xl/comments1.xml')!.readBytes();
        var book = SheetDeserializer().readBytes(source.save());
        expect(book.firstSheet.comments.single.text, ' authored note ');
        book.firstSheet.comments.clear();
        for (var cycle = 1; cycle <= 3; cycle++) {
          final saved = OpcPackage.openBytes(
            SheetSerializer().write(book).save(),
          );
          expect(
            saved.getPart('/xl/comments1.xml')!.readBytes(),
            orderedEquals(decoyBytes),
            reason: 'unrelated decoy bytes survive save $cycle',
          );
          book = SheetDeserializer().read(saved);
          expect(
            book.firstSheet.comments,
            isEmpty,
            reason: 'deleted comments stay deleted on reopen $cycle',
          );
          final rels = saved.relationshipsFor('/xl/worksheets/sheet1.xml');
          final link = rels.firstByType(RelationshipTypes.comments)!;
          final emptyPart = saved.getPart(rels.resolve(link))!;
          expect(emptyPart.uri, isNot('/xl/comments1.xml'));
          expect(emptyPart.contentType, OfficeContentTypes.sheetComments);
          final root = XmlDocument.parse(emptyPart.readText()).root!;
          expect(root.localName, 'comments');
          expect(root.namespaceUri, OfficeNamespaces.x);
          expect(root.childElements.map((child) => child.localName), [
            'authors',
            'commentList',
          ]);
          for (final child in root.childElements) {
            expect(child.namespaceUri, OfficeNamespaces.x);
            expect(child.childElements, isEmpty);
          }
          if (shared) {
            expect(book.sheets[1].comments.single.text, ' authored note ');
            expect(book.sheets[1].comments.single.author, 'Original');
            final otherRels = saved.relationshipsFor(
              '/xl/worksheets/sheet2.xml',
            );
            final otherLink = otherRels.firstByType(
              RelationshipTypes.comments,
            )!;
            expect(otherRels.resolve(otherLink), _relocatedComments);
            expect(emptyPart.uri, isNot(_relocatedComments));
          }
        }
      },
    );
  }

  test('legacy fixed-name comments remain readable without a relationship', () {
    final package = SheetSerializer().write(_workbook('legacy fallback'));
    final rels = package.relationshipsFor('/xl/worksheets/sheet1.xml');
    rels.removeById(rels.firstByType(RelationshipTypes.comments)!.id);
    final book = SheetDeserializer().readBytes(package.save());
    expect(book.firstSheet.comments.first.text, 'legacy fallback');
  });

  test('new comments resolve from a worksheet in a nested directory', () {
    final book = _workbook('nested sheet');
    const sheetUri = '/xl/sheets/north/data.xml';
    book.firstSheet.sourcePartUri = sheetUri;
    final package = OpcPackage.openBytes(SheetSerializer().write(book).save());
    final rels = package.relationshipsFor(sheetUri);
    final comments = rels.firstByType(RelationshipTypes.comments)!;
    expect(rels.resolve(comments), '/xl/comments1.xml');
    expect(package.getPart(rels.resolve(comments)), isNotNull);
    expect(
      SheetDeserializer().read(package).firstSheet.comments.first.text,
      'nested sheet',
    );
  });

  for (final invalid in ['external', 'missing', 'wrong type', 'wrong root']) {
    test('invalid $invalid comments target cannot alter package bytes', () {
      final book = _workbook('keep me');
      final package = SheetSerializer().write(book);
      final rels = package.relationshipsFor('/xl/worksheets/sheet1.xml');
      final original = rels.firstByType(RelationshipTypes.comments)!;
      rels.removeById(original.id);
      var target = '../annotations/missing.xml';
      var mode = RelationshipTargetMode.internal;
      if (invalid == 'external') {
        target = 'https://example.invalid/comments.xml';
        mode = RelationshipTargetMode.external;
      } else if (invalid == 'wrong type') {
        target = '../styles.xml';
      } else if (invalid == 'wrong root') {
        target = '../annotations/wrong-root.xml';
        package.createPart(
          '/xl/annotations/wrong-root.xml',
          OfficeContentTypes.sheetComments,
          utf8.encode('<unrelated xmlns="${OfficeNamespaces.x}"/>'),
        );
      }
      rels.add(
        id: original.id,
        type: RelationshipTypes.comments,
        target: target,
        targetMode: mode,
      );
      final before = package.save();
      expect(() => SheetDeserializer().read(package), throwsFormatException);
      expect(package.save(), orderedEquals(before));
      expect(() => SheetSerializer().write(book), throwsFormatException);
      expect(package.save(), orderedEquals(before));
      book.firstSheet.comments.clear();
      expect(() => SheetSerializer().write(book), throwsFormatException);
      expect(package.save(), orderedEquals(before));
    });
  }

  test('a non-comment part at the legacy filename is not overwritten', () {
    final package = SheetSerializer().write(_workbook('unused'));
    final rels = package.relationshipsFor('/xl/worksheets/sheet1.xml');
    rels.removeById(rels.firstByType(RelationshipTypes.comments)!.id);
    package.deletePart('/xl/comments1.xml');
    final retained = utf8.encode('<unrelated>retain me</unrelated>');
    package.createPart('/xl/comments1.xml', 'application/xml', retained);
    final book = SheetDeserializer().read(package);
    expect(book.firstSheet.comments, isEmpty);
    book.firstSheet.comments.add(
      SmlComment(ref: SmlCellRef.parse('A1'), text: 'new note'),
    );
    final saved = OpcPackage.openBytes(SheetSerializer().write(book).save());
    expect(saved.getPart('/xl/comments1.xml')!.readBytes(), retained);
    final savedRels = saved.relationshipsFor('/xl/worksheets/sheet1.xml');
    final savedLink = savedRels.firstByType(RelationshipTypes.comments)!;
    expect(savedRels.resolve(savedLink), isNot('/xl/comments1.xml'));
    expect(
      SheetDeserializer().read(saved).firstSheet.comments.single.text,
      'new note',
    );
  });

  for (final clearFirst in [false, true]) {
    test(
      'shared comments remain owned when one sheet ${clearFirst ? 'clears' : 'edits'}',
      () {
        final first = _workbook('shared original').firstSheet;
        final second = SmlWorksheet(name: 'Other', sheetId: 2);
        second.cellA1('A1').value = 'other sheet';
        final package = SheetSerializer().write(
          SmlWorkbook(sheets: [first, second]),
        );
        package
            .relationshipsFor('/xl/worksheets/sheet2.xml')
            .add(type: RelationshipTypes.comments, target: '../comments1.xml');
        final book = SheetDeserializer().readBytes(package.save());
        if (clearFirst) {
          book.sheets.first.comments.clear();
        } else {
          book.sheets.first.comments.first.text = 'changed only first';
        }
        final saved = OpcPackage.openBytes(
          SheetSerializer().write(book).save(),
        );
        final reopened = SheetDeserializer().read(saved);
        expect(reopened.sheets[1].comments.first.text, 'shared original');
        if (clearFirst) {
          expect(reopened.sheets.first.comments, isEmpty);
        } else {
          expect(
            reopened.sheets.first.comments.first.text,
            'changed only first',
          );
        }
      },
    );
  }

  for (final relocated in [false, true]) {
    test(
      'clearing ${relocated ? 'relocated' : 'standard'} comments removes them',
      () {
        final package = relocated
            ? _relocatedPackage()
            : SheetSerializer().write(_workbook('remove me'));
        final sourceUri = relocated ? _relocatedComments : '/xl/comments1.xml';
        var book = SheetDeserializer().read(package);
        book.firstSheet.comments.clear();
        for (var cycle = 1; cycle <= 2; cycle++) {
          final saved = OpcPackage.openBytes(
            SheetSerializer().write(book).save(),
          );
          expect(
            saved
                .relationshipsFor('/xl/worksheets/sheet1.xml')
                .firstByType(RelationshipTypes.comments),
            isNull,
          );
          expect(saved.getPart(sourceUri), isNull);
          expect(saved.getPart('/xl/comments1.xml'), isNull);
          book = SheetDeserializer().read(saved);
          expect(book.firstSheet.comments, isEmpty);
        }
      },
    );
  }

  test('every comment element belongs to the SpreadsheetML namespace', () {
    final package = SheetSerializer().write(_workbook('reviewed'));
    final root = XmlDocument.parse(
      package.getPart('/xl/comments1.xml')!.readText(),
    ).root!;
    expect(root.localName, 'comments');
    for (final element in _elements(root)) {
      expect(
        element.namespaceUri,
        OfficeNamespaces.x,
        reason: 'namespace of ${element.localName}',
      );
    }
  });

  const cases = <String, String>{
    'ordinary text': 'plain comment',
    'leading whitespace': ' leading',
    'trailing whitespace': 'trailing ',
    'multiline and tabs': ' \tline one\nline two \t ',
    'empty text': '',
    'escaped XML and Unicode': 'A&B <tag> "quote" — café 🙂',
  };
  for (final entry in cases.entries) {
    test('CT_Rst preserves ${entry.key} through three XLSX saves', () {
      var book = _workbook(entry.value);
      for (var cycle = 1; cycle <= 3; cycle++) {
        final bytes = SheetSerializer().write(book).save();
        final package = OpcPackage.openBytes(bytes);
        final root = XmlDocument.parse(
          package.getPart('/xl/comments1.xml')!.readText(),
        ).root!;
        final authors = root.firstChild('authors')!.childElements.toList();
        expect(authors.map((author) => author.text), ['Alice & Co', 'Bob']);
        final comments = root.firstChild('commentList')!.childElements.toList();
        expect(comments.map((comment) => comment.getAttribute('authorId')), [
          '0',
          '1',
          '0',
        ]);
        final text = comments.first.firstChild('text')!;
        expect(text.childElements.map((element) => element.localName), [
          't',
        ], reason: 'plain comment text uses CT_Rst/x:t on save $cycle');
        expect(text.children.whereType<XmlText>(), isEmpty);
        final runText = text.firstChild('t')!;
        expect(runText.namespaceUri, OfficeNamespaces.x);
        expect(runText.text, entry.value);
        if (entry.value.trim() != entry.value) {
          expect(
            runText.getAttribute('space', namespaceUri: OfficeNamespaces.xml),
            'preserve',
            reason: 'edge whitespace is significant in comment text',
          );
        }
        book = SheetDeserializer().read(package);
        expect(book.firstSheet.comments.map((comment) => comment.text), [
          entry.value,
          'second',
          'again',
        ]);
        expect(book.firstSheet.comments.map((comment) => comment.author), [
          'Alice & Co',
          'Bob',
          'Alice & Co',
        ]);
      }
    });
  }
}
