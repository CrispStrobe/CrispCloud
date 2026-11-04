import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  test('finds and replaces across Word workbook and slides', () {
    final WmlDocument word = WmlDocument.empty(text: 'Hello Quds Office');
    final List<OfficeFindHit> wordHits = OfficeFind.inWord(
      word,
      const OfficeFindOptions(query: 'quds', matchCase: false),
    );
    expect(wordHits, hasLength(1));
    expect(
      OfficeFind.replaceWord(
        word,
        const OfficeFindOptions(query: 'Quds', replaceWith: 'قدس'),
      ),
      1,
    );
    expect(word.paragraphs.first.text, contains('قدس'));

    final SmlWorkbook book = SmlWorkbook();
    book.firstSheet.cellA1('A1').value = 'Alpha';
    book.firstSheet.cellA1('B1').value = 'alpha-beta';
    expect(
      OfficeFind.inWorkbook(
        book,
        const OfficeFindOptions(query: 'alpha', matchCase: false),
      ),
      hasLength(2),
    );
    expect(
      OfficeFind.replaceWorkbook(
        book,
        const OfficeFindOptions(query: 'Alpha', replaceWith: 'β'),
      ),
      2,
    );

    final PmlPresentation deck = PmlPresentation();
    deck.slides.first.shapes.add(
      PmlShape(id: 2, name: 'Title', text: 'Kickoff deck'),
    );
    deck.slides.first.notes = 'Speaker kickoff';
    expect(
      OfficeFind.inPresentation(
        deck,
        const OfficeFindOptions(query: 'kickoff', matchCase: false),
      ),
      hasLength(2),
    );
    expect(
      OfficeFind.inWord(
        WmlDocument.empty(text: 'catalog catalogue'),
        const OfficeFindOptions(query: 'cat*', wildcards: true),
      ),
      hasLength(2),
    );
  });

  test('counts words and writes document properties', () {
    final WmlDocument word = WmlDocument.empty(text: 'One two three');
    word.properties
      ..title = 'Brief'
      ..creator = 'Quds';
    expect(OfficeTextStats.ofWord(word).words, 3);
    final OpcPackage package = WordSerializer().write(word);
    final OfficeDocumentProperties props =
        OfficeDocumentProperties.fromPackage(package);
    expect(props.title, 'Brief');
    expect(props.creator, 'Quds');
  });

  test('applies styles footnotes revisions and captions', () {
    final WmlDocument document = WmlDocument.empty(text: 'Body');
    final WmlParagraph para = document.paragraphs.first;
    WordStyles.apply(para, 'Heading1');
    expect(WordStyles.ofParagraph(para).id, 'Heading1');
    expect(para.properties.headingLevel, 1);
    WordLists.applyLevel(para, numbered: true, level: 1);
    expect(para.properties.numId, 2);
    WordNotes.insert(document, para, endnote: false, text: 'A note');
    expect(document.footnotes, hasLength(1));
    expect(
      para.inlines.whereType<WmlRun>().any((WmlRun r) => r.noteRefId == 1),
      isTrue,
    );
    expect(para.text, contains('1'));
    WordRevisions.record(
      document,
      kind: WmlRevisionKind.insert,
      paragraphIndex: 0,
      start: 0,
      end: 4,
      text: 'Body',
    );
    expect(document.trackRevisions, isTrue);
    expect(document.revisions, hasLength(1));
    WordRevisions.rejectAll(document);
    expect(document.revisions, isEmpty);
    final WmlParagraph caption = WordCaptions.create(
      document,
      label: 'Figure',
      text: 'Map',
    );
    document.sections.first.blocks.add(caption);
    expect(caption.properties.styleId, 'Caption');
    expect(caption.text, contains('Figure 1'));
  });

  test('aligns slides and names a section', () {
    final PmlPresentation deck = PmlPresentation();
    final PmlSlide slide = deck.slides.first;
    slide.shapes.addAll(<PmlShape>[
      PmlShape(
        id: 2,
        name: 'A',
        transform: const PmlTransform(x: 0, y: 0, cx: 100, cy: 100),
      ),
      PmlShape(
        id: 3,
        name: 'B',
        transform: const PmlTransform(x: 400, y: 50, cx: 100, cy: 100),
      ),
    ]);
    PmlArrange.align(slide.shapes, PmlAlignAxis.left);
    expect(slide.shapes[0].transform.x, 0);
    expect(slide.shapes[1].transform.x, 0);
    PmlSections.add(deck, name: 'Intro', startIndex: 0);
    expect(PmlSections.nameOf(deck, 0), 'Intro');
  });

  test('evaluates live fields and round-trips a watermark', () {
    final WmlDocument document = WmlDocument.empty(text: 'Hello');
    document.sections.first.header.add(
      WmlParagraph(properties: WmlParagraphProps(pageNumberField: true)),
    );
    WordFields.stamp(document.paragraphs.first, WmlFieldKind.date);
    expect(
      WordFields.kindOf(document.paragraphs.first.properties.fieldInstruction),
      WmlFieldKind.date,
    );
    WordFields.update(document, pageCount: 3, now: DateTime.utc(2026, 9, 7));
    expect(document.paragraphs.first.text, '2026-09-07');
    document.watermark = 'DRAFT';
    final OpcPackage package = WordSerializer().write(document);
    final WmlDocument opened = WordDeserializer().read(package);
    expect(opened.watermark, 'DRAFT');
    expect(
      WordFields.kindOf(opened.paragraphs.first.properties.fieldInstruction),
      WmlFieldKind.date,
    );
  });

  test('prints a word document to PDF bytes', () {
    final Uint8List pdf = OfficePrint.word(
      WmlDocument.empty(text: 'Print me'),
      settings: const OfficePrintSettings(title: 'Print me'),
    );
    expect(pdf.length, greaterThan(100));
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
  });

  test('round-trips first headers notes styles and slide sections', () {
    final WmlDocument document = WmlDocument.empty(text: 'Body');
    document.sections.first
      ..differentFirstPage = true
      ..differentOddEven = true
      ..lineNumbers = true
      ..firstHeader.add(
        WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'First')]),
      )
      ..evenHeader.add(
        WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'Even')]),
      )
      ..header.add(WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'Default')]));
    WordNotes.insert(document, document.paragraphs.first, endnote: false, text: 'Foot');
    WordStyles.extras.add(
      const WmlStyle(id: 'Custom', name: 'Custom', nameAr: 'مخصص'),
    );
    document.watermark = 'CONFIDENTIAL';
    final WmlDocument opened = WordDeserializer().read(
      WordSerializer().write(document),
    );
    expect(opened.sections.first.firstHeader.first.text, 'First');
    expect(opened.sections.first.evenHeader.first.text, 'Even');
    expect(opened.footnotes, isNotEmpty);
    expect(WordStyles.byId('Custom'), isNotNull);
    expect(opened.watermark, 'CONFIDENTIAL');
    WordStyles.extras.clear();

    final PmlPresentation deck = PmlPresentation();
    PmlSections.add(deck, name: 'Intro', startIndex: 0);
    final PmlPresentation slideOpened = SlideDeserializer().read(
      SlideSerializer().write(deck),
    );
    expect(slideOpened.sections.single.name, 'Intro');
  });

  test('merges mail compares documents and builds citations', () {
    final WmlDocument letter = WmlDocument.empty(text: 'Hello «Name»');
    WordMailMerge.merge(letter, <String, String>{'Name': 'Ada'});
    expect(letter.paragraphs.first.text, 'Hello Ada');
    final WmlDocument original = WmlDocument.empty(text: 'Hello');
    final WmlDocument revised = WmlDocument.empty(text: 'Hello world');
    WordCompare.compare(original, revised);
    expect(revised.revisions, isNotEmpty);
    final WmlDocument shorter = WmlDocument.empty(text: 'Keep');
    shorter.sections.first.blocks.add(
      WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'Gone')]),
    );
    final WmlDocument kept = WmlDocument.empty(text: 'Keep');
    WordCompare.compare(shorter, kept);
    expect(
      kept.revisions.any((WmlRevision r) => r.kind == WmlRevisionKind.delete),
      isTrue,
    );
    WordCitations.insert(
      letter,
      letter.paragraphs.first,
      WmlCitation(tag: 's', author: 'Smith', title: 'Paper', year: '2020'),
    );
    expect(letter.citations, hasLength(1));
    expect(
      WordFields.kindOf(letter.paragraphs.first.properties.fieldInstruction),
      WmlFieldKind.citation,
    );
    expect(WordCitations.bibliography(letter).text, contains('Smith'));
    WordCitations.markIndex(letter, letter.paragraphs.first, 'Ada');
    final WmlParagraph index = WordCitations.index(letter);
    expect(index.text, contains('Ada'));
    expect(
      WordFields.kindOf(index.properties.fieldInstruction),
      WmlFieldKind.indexList,
    );
  });

  test('lays out drop caps line numbers and footnotes', () {
    final WmlDocument document = WmlDocument.empty(
      text: 'Dropcap paragraph with enough words to wrap.',
    );
    document.paragraphs.first.properties
      ..dropCapLines = 2
      ..shadingFill = 'FFF2CC'
      ..borderColor = '2E75B6';
    document.sections.first.lineNumbers = true;
    WordNotes.insert(
      document,
      document.paragraphs.first,
      endnote: false,
      text: 'Note body',
    );
    document.endnotes.add(WmlNote(id: 1, endnote: true)..text = 'End');
    final LaidOutDocument laid = WordLayoutEngine(font: null).layout(document);
    expect(laid.pages, isNotEmpty);
    expect(
      laid.pages.first.frames.any(
        (LaidOutBox b) => b.kind == LaidOutBoxKind.paragraphShade,
      ),
      isTrue,
    );
    expect(
      laid.pages.first.frames.any(
        (LaidOutBox b) => b.kind == LaidOutBoxKind.lineNumber,
      ),
      isTrue,
    );
    expect(laid.pages.first.notes, isNotEmpty);
  });

  test('clamps Word print preview to a page range', () {
    final WmlDocument document = WmlDocument.empty(text: 'One');
    document.sections.first.blocks.add(
      WmlParagraph(
        properties: WmlParagraphProps(pageBreakBefore: true),
        inlines: <WmlInline>[WmlRun(text: 'Two')],
      ),
    );
    final List<LaidOutPage> preview = OfficePrint.wordPreview(
      document,
      settings: const OfficePrintSettings(pageFrom: 2, pageTo: 2),
    );
    expect(preview, hasLength(1));
    expect(preview.single.index, 1);
  });

  test('round-trips footnote refs revisions styles and VML watermark', () {
    WordStyles.extras.clear();
    final WmlDocument document = WmlDocument.empty(text: 'Hello');
    final WmlParagraph para = document.paragraphs.first;
    WordNotes.insert(document, para, endnote: false, text: 'Cite me');
    WordRevisions.record(
      document,
      kind: WmlRevisionKind.insert,
      paragraphIndex: 0,
      start: 0,
      end: 5,
      text: 'Hello',
    );
    document.watermark = 'CONFIDENTIAL';
    document.sections.first.differentFirstPage = true;
    final OpcPackage package = WordSerializer().write(document);
    final String docXml = package.getPart('/word/document.xml')!.readText();
    expect(docXml, contains('footnoteReference'));
    expect(docXml, contains('<w:ins'));
    expect(package.getPart('/word/watermark.xml'), isNull);
    final String styles = package.getPart('/word/styles.xml')!.readText();
    expect(styles, contains('<w:pPr'));
    expect(styles, contains('<w:rPr'));
    var headerXml = '';
    for (final PackagePart part in package.parts) {
      if (part.uri.contains('/word/header')) {
        headerXml = part.readText();
        break;
      }
    }
    expect(headerXml, contains('textpath'));
    expect(headerXml, contains('CONFIDENTIAL'));
    final WmlDocument opened = WordDeserializer().read(package);
    expect(opened.watermark, 'CONFIDENTIAL');
    expect(
      opened.paragraphs.first.inlines.whereType<WmlRun>().any(
        (WmlRun r) => r.noteRefId == 1,
      ),
      isTrue,
    );
    expect(opened.revisions, isNotEmpty);
    expect(opened.footnotes.single.text, 'Cite me');
    WordStyles.extras.clear();
  });

  test('writes slide groups and speaker notes parts', () {
    final PmlPresentation deck = PmlPresentation();
    deck.slides.first.shapes.addAll(<PmlShape>[
      PmlShape(id: 2, name: 'A', text: 'A', groupId: 9),
      PmlShape(id: 3, name: 'B', text: 'B', groupId: 9),
    ]);
    deck.slides.first.notes = 'Say hello';
    final OpcPackage package = SlideSerializer().write(deck);
    final String xml = package.getPart('/ppt/slides/slide1.xml')!.readText();
    expect(xml, contains('grpSp'));
    expect(package.getPart('/ppt/notesSlides/notesSlide1.xml'), isNotNull);
    final PmlPresentation opened = SlideDeserializer().read(package);
    expect(opened.slides.first.notes, contains('Say hello'));
    expect(
      opened.slides.first.shapes.every((PmlShape s) => s.groupId != null),
      isTrue,
    );
  });

  test('goal seek power query sparklines mail merge and citations xml', () {
    final SmlWorkbook book = SmlWorkbook();
    final SmlWorksheet sheet = book.firstSheet;
    sheet.cellA1('A1').value = 1;
    sheet.cellA1('B1').formula = '=A1*2';
    FormulaEvaluator.recalculate(book);
    expect(
      SmlSolver.goalSeek(
        workbook: book,
        sheet: sheet,
        target: SmlCellRef.parse('B1'),
        changing: SmlCellRef.parse('A1'),
        goal: 10,
      ),
      isTrue,
    );
    expect(sheet.cellA1('B1').asNumber, closeTo(10, 0.01));
    final SmlRange loaded = SmlPowerQuery.fromCsv(sheet, 'X,Y\n1,2\n3,4');
    expect(sheet.cellA1('A1').asString, 'X');
    expect(loaded.maxRow, 2);
    sheet.sparklines.add(
      SmlSparkline(
        source: SmlRange.parse('A2:B2'),
        anchor: SmlCellRef.parse('C2'),
      ),
    );
    sheet.pivots.add(
      SmlPivotTable(source: SmlRange.parse('A1:B3'), rowField: 0, dataField: 1),
    );
    final OpcPackage xlsx = SheetSerializer().write(book);
    expect(xlsx.getPart('/xl/sparklines1.xml'), isNotNull);
    expect(xlsx.getPart('/xl/pivotCache/pivotCacheDefinition1.xml'), isNotNull);
    expect(xlsx.getPart('/xl/pivotTables/pivotTable1.xml'), isNotNull);
    final SmlWorkbook openedBook = SheetDeserializer().read(xlsx);
    expect(openedBook.firstSheet.pivots, isNotEmpty);
    expect(openedBook.firstSheet.sparklines, isNotEmpty);

    final WmlDocument word = WmlDocument.empty(text: 'Dear «Name»,');
    WordMailMerge.preview(word, <Map<String, String>>[
      <String, String>{'Name': 'Ada'},
      <String, String>{'Name': 'Omar'},
    ], 1);
    expect(word.paragraphs.first.text, contains('Omar'));
    word.citations.add(
      WmlCitation(tag: 'A', author: 'Ada', title: 'Notes', year: '2026'),
    );
    word.restrictMode = WmlRestrictMode.comments;
    final OpcPackage docx = WordSerializer().write(word);
    expect(docx.getPart('/customXml/sources.xml')!.readText(), contains('Ada'));
    expect(docx.getPart('/customXml/item1.xml')!.readText(), contains('Ada'));
    final WmlDocument opened = WordDeserializer().read(docx);
    expect(opened.citations, isNotEmpty);
  });

  test('evaluates hyperlink filename author title and merge fields', () {
    final WmlDocument document = WmlDocument.empty(text: 'x');
    document
      ..sourceFileName = 'brief.docx'
      ..sourceByteLength = 2048
      ..properties.title = 'Brief'
      ..properties.creator = 'Quds'
      ..mailMergeRecords.add(<String, String>{'City': 'Nablus'});

    WordFields.stamp(
      document.paragraphs.first,
      WmlFieldKind.hyperlink,
      argument: 'https://example.com',
      result: 'Example',
    );
    expect(
      WordFields.kindOf(document.paragraphs.first.properties.fieldInstruction),
      WmlFieldKind.hyperlink,
    );
    expect(document.paragraphs.first.text, 'Example');
    expect(
      document.paragraphs.first.inlines.whereType<WmlRun>().first.hyperlink?.url,
      'https://example.com',
    );

    final WmlParagraph meta = WmlParagraph();
    document.sections.first.blocks.add(meta);
    WordFields.stamp(meta, WmlFieldKind.filename);
    WordFields.update(document);
    expect(meta.text, 'brief.docx');

    final WmlParagraph size = WmlParagraph();
    document.sections.first.blocks.add(size);
    WordFields.stamp(size, WmlFieldKind.filesize);
    WordFields.update(document);
    expect(size.text, '2.0 KB');

    final WmlParagraph author = WmlParagraph();
    document.sections.first.blocks.add(author);
    WordFields.stamp(author, WmlFieldKind.author);
    WordFields.update(document);
    expect(author.text, 'Quds');

    final WmlParagraph title = WmlParagraph();
    document.sections.first.blocks.add(title);
    WordFields.stamp(title, WmlFieldKind.title);
    WordFields.update(document);
    expect(title.text, 'Brief');

    final WmlParagraph merge = WmlParagraph();
    document.sections.first.blocks.add(merge);
    WordFields.stamp(merge, WmlFieldKind.mergeField, argument: 'City');
    WordFields.update(document);
    expect(merge.text, 'Nablus');
  });

  test('resolves multilevel list labels and restart', () {
    final WmlDocument document = WmlDocument.empty(text: 'A');
    final WmlParagraph a = document.paragraphs.first;
    final WmlParagraph b = WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'B')]);
    final WmlParagraph c = WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'C')]);
    final WmlParagraph d = WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'D')]);
    document.sections.first.blocks.addAll(<WmlBlock>[b, c, d]);
    WordLists.applyLevel(a, numbered: true, level: 0);
    WordLists.applyLevel(b, numbered: true, level: 1);
    WordLists.applyLevel(c, numbered: true, level: 0);
    WordLists.applyLevel(d, numbered: true, level: 0);
    WordLists.restart(d, at: 5);
    WordLists.resolveLabels(document.paragraphs);
    expect(a.properties.listLabel, '1. ');
    expect(b.properties.listLabel, '1.1 ');
    expect(c.properties.listLabel, '2. ');
    expect(d.properties.listLabel, '5. ');
  });

  test('resolves basedOn styles into document styles.xml round-trip', () {
    final WmlDocument document = WmlDocument.empty(text: 'Styled');
    document.styles.addAll(<WmlStyle>[
      const WmlStyle(
        id: 'BaseBody',
        name: 'Base Body',
        nameAr: 'أساس',
        fontSizePoints: 14,
        font: 'Calibri',
        color: '333333',
      ),
      const WmlStyle(
        id: 'ChildBody',
        name: 'Child Body',
        nameAr: 'فرع',
        basedOn: 'BaseBody',
        bold: true,
        fontSizePoints: 11,
      ),
    ]);
    WordStyles.apply(document.paragraphs.first, 'ChildBody', document: document);
    final WmlStyle resolved = WordStyles.resolve(
      'ChildBody',
      document: document,
    );
    expect(resolved.bold, isTrue);
    expect(resolved.font, 'Calibri');
    expect(resolved.color, '333333');
    expect(resolved.fontSizePoints, 11);

    final WmlDocument opened = WordDeserializer().read(
      WordSerializer().write(document),
    );
    expect(
      opened.styles.any((WmlStyle s) => s.id == 'ChildBody' && s.basedOn == 'BaseBody'),
      isTrue,
    );
    expect(
      WordStyles.resolve('ChildBody', document: opened).font,
      'Calibri',
    );
  });
}
