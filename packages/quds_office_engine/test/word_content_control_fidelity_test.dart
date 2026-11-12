import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _customer =
    '<c:customer xmlns:c="urn:crispcloud:customer"><c:name>Original bound value</c:name></c:customer>';
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3e0AAAAASUVORK5CYII=',
);

String _controlXml(int id, String content) =>
    '<w:sdt><w:sdtPr><w:alias w:val="Aux control $id"/>'
    '<w:tag w:val="control-$id"/><w:id w:val="$id"/><w:richText/>'
    '</w:sdtPr><w:sdtEndPr><w:rPr><w:color w:val="112233"/></w:rPr>'
    '</w:sdtEndPr><w:sdtContent>$content</w:sdtContent></w:sdt>';

String _inlineStory(int id, String name) =>
    '<w:p><w:r><w:t xml:space="preserve">Before </w:t></w:r>'
    '${_controlXml(id, '<w:r><w:rPr><w:i/></w:rPr><w:t>$name</w:t></w:r>')}'
    '<w:r><w:t xml:space="preserve"> after</w:t></w:r></w:p>';

OpcPackage _source({String? body}) {
  final package = OpcPackage.create(OpcPackageKind.word);
  final rels = package.relationshipsFor('/word/document.xml');
  final references = StringBuffer();
  var id = 81;
  for (final kind in ['header', 'footer']) {
    for (final variant in ['default', 'first', 'even']) {
      final uri = '/word/${kind}_$variant.xml';
      final root = kind == 'header' ? 'hdr' : 'ftr';
      package.createPart(
        uri,
        kind == 'header'
            ? OfficeContentTypes.wordHeader
            : OfficeContentTypes.wordFooter,
        utf8.encode(
          '<w:$root xmlns:w="${OfficeNamespaces.w}">${_inlineStory(id++, '$kind-$variant')}</w:$root>',
        ),
      );
      final relationship = rels.add(
        type: kind == 'header'
            ? RelationshipTypes.header
            : RelationshipTypes.footer,
        target: uri.substring('/word/'.length),
      );
      references.write(
        '<w:${kind}Reference w:type="$variant" r:id="${relationship.id}"/>',
      );
    }
  }
  for (final endnote in [false, true]) {
    final kind = endnote ? 'endnote' : 'footnote';
    final control = endnote ? 92 : 91;
    final inline = endnote ? 89 : 88;
    final story = _controlXml(
      control,
      '<w:p><w:r><w:${kind}Ref/></w:r><w:r><w:t xml:space="preserve">${endnote ? 'Endnote' : 'Footnote'} </w:t></w:r>'
      '${_controlXml(inline, '<w:r><w:t>body</w:t></w:r>')}</w:p>',
    );
    package.createPart(
      '/word/${kind}s.xml',
      endnote
          ? OfficeContentTypes.wordEndnotes
          : OfficeContentTypes.wordFootnotes,
      utf8.encode(
        '<w:${kind}s xmlns:w="${OfficeNamespaces.w}"><w:$kind w:id="1">$story</w:$kind></w:${kind}s>',
      ),
    );
    rels.add(
      type: endnote ? RelationshipTypes.endnotes : RelationshipTypes.footnotes,
      target: '${kind}s.xml',
    );
  }
  package.createPart(
    '/word/comments.xml',
    OfficeContentTypes.wordComments,
    utf8.encode(
      '<w:comments xmlns:w="${OfficeNamespaces.w}"><w:comment w:id="7" w:author="Source author">${_inlineStory(87, 'Comment')}</w:comment></w:comments>',
    ),
  );
  rels.add(type: RelationshipTypes.comments, target: 'comments.xml');
  package.createPart('/word/media/control.png', 'image/png', _png);
  rels.add(
    id: 'controlImage',
    type: RelationshipTypes.image,
    target: 'media/control.png',
  );
  package.createPart(
    '/customXml/controlData.xml',
    'application/xml',
    utf8.encode(_customer),
  );
  rels.add(
    type: RelationshipTypes.customXml,
    target: '../customXml/controlData.xml',
  );
  package.createPart(
    '/customXml/controlProps.xml',
    'application/vnd.openxmlformats-officedocument.customXmlProperties+xml',
    utf8.encode(
      '<ds:datastoreItem xmlns:ds="http://schemas.openxmlformats.org/officeDocument/2006/customXml" ds:itemID="{00000000-0000-0000-0000-000000000071}"/>',
    ),
  );
  package
      .relationshipsFor('/customXml/controlData.xml')
      .add(
        type: '${OfficeNamespaces.r}/customXmlProps',
        target: 'controlProps.xml',
      );
  package.createPart(
    '/word/styles.xml',
    OfficeContentTypes.wordStyles,
    utf8.encode(
      '<w:styles xmlns:w="${OfficeNamespaces.w}">'
      '<w:style w:type="paragraph" w:styleId="RichBody"><w:name w:val="Rich Body"/><w:pPr><w:spacing w:after="120"/></w:pPr><w:rPr><w:color w:val="345678"/></w:rPr></w:style>'
      '<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="Heading 1"/><w:pPr><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/></w:rPr></w:style>'
      '</w:styles>',
    ),
  );
  rels.add(type: RelationshipTypes.styles, target: 'styles.xml');
  final xml = body == null
      ? File('test/fixtures/fidelity/content_controls.xml').readAsStringSync()
      : '<w:document xmlns:w="${OfficeNamespaces.w}" xmlns:r="${OfficeNamespaces.r}"><w:body>$body<w:sectPr/></w:body></w:document>';
  package
      .getPart('/word/document.xml')!
      .writeText(
        xml.replaceFirst(
          '<w:sectPr/>',
          '<w:sectPr>$references<w:titlePg/></w:sectPr>',
        ),
      );
  return package;
}

List<WmlParagraph> _allParagraphs(WmlDocument document) => [
  ...document.paragraphs,
  for (final section in document.sections) ...[
    ...section.header,
    ...section.firstHeader,
    ...section.evenHeader,
    ...section.footer,
    ...section.firstFooter,
    ...section.evenFooter,
  ],
  for (final note in [...document.footnotes, ...document.endnotes])
    ...note.allParagraphs,
  for (final comment in document.comments) ...comment.paragraphs,
];

Iterable<WmlContentControlBlock> _blocks(WmlDocument document) sync* {
  for (final section in document.sections) {
    yield* WordTree.descendants(
      section.blocks,
    ).whereType<WmlContentControlBlock>();
  }
  for (final note in [...document.footnotes, ...document.endnotes]) {
    yield* WordTree.descendants(
      note.blocks,
    ).whereType<WmlContentControlBlock>();
  }
}

WmlContentControlBlock _block(WmlDocument document, int id) =>
    _blocks(document).singleWhere((c) => c.control.id == '$id');
WmlParagraph _paragraph(WmlDocument document, String text) =>
    _allParagraphs(document).singleWhere((p) => p.text == text);

List<XmlElement> _all(XmlElement root, String name) => [
  for (final child in root.childElements) ...[
    if (child.namespaceUri == OfficeNamespaces.w && child.localName == name)
      child,
    ..._all(child, name),
  ],
];

bool _inFallback(XmlElement node) {
  for (
    XmlElement? parent = node.parent;
    parent != null;
    parent = parent.parent
  ) {
    if (parent.namespaceUri == OfficeNamespaces.mc &&
        parent.localName == 'Fallback') {
      return true;
    }
  }
  return false;
}

XmlElement _nativeControl(XmlElement root, int id) => _all(root, 'sdt')
    .where((node) => !_inFallback(node))
    .singleWhere(
      (c) =>
          c.firstChild('sdtPr')?.firstChild('id')?.getAttribute('val') == '$id',
    );

WmlParagraph _simpleInline({String content = 'XYZ'}) => WordDeserializer()
    .read(
      _source(
        body:
            '<w:p><w:r><w:t>ab</w:t></w:r>${_controlXml(101, content.isEmpty ? '' : '<w:r><w:t>$content</w:t></w:r>')}<w:r><w:t>cd</w:t></w:r></w:p>',
      ),
    )
    .paragraphs
    .single;

void _edit(WmlDocument document) {
  WmlRunEdit.replaceRange(
    _paragraph(document, 'Outside before'),
    14,
    14,
    ' edited',
  );
  final original = _paragraph(document, 'Block Alpha Beta');
  WmlRunEdit.replaceRange(original, 6, 11, 'Edited');
  WmlRunEdit.applyRange(original, 6, 12, (props) => props.bold = true);
  final halves = WmlClone.splitInlines(original, 12);
  final tail = WmlParagraph(
    properties: original.properties.copy(),
    inlines: halves.tail,
  );
  original.inlines
    ..clear()
    ..addAll(halves.head);
  final location = WordTree.locate(document, original)!;
  location.parent.insert(location.index + 1, tail);
  WmlRunEdit.replaceRange(
    _paragraph(document, 'Cell content'),
    0,
    4,
    'Edited cell',
  );
  final frameParagraph = _paragraph(document, 'Frame content');
  WmlRunEdit.replaceRange(
    frameParagraph,
    frameParagraph.text.length,
    frameParagraph.text.length,
    ' updated',
  );
  final frameOwner = WordTree.locate(document, frameParagraph)!;
  frameOwner.parent.add(WmlParagraph(inlines: [WmlRun(text: 'Frame second')]));
  final inline = _paragraph(document, 'Inline[Beta Inner tail]');
  WmlRunEdit.replaceRange(inline, 7, 11, 'Gamma');
  WmlRunEdit.replaceRange(inline, 13, 18, 'Core');
  final empty = WordContentControls.spans(
    inline,
  ).singleWhere((span) => span.control.id == '77');
  WmlRunEdit.replaceRange(inline, empty.start, empty.start, 'empty filled');
  for (final note in [...document.footnotes, ...document.endnotes]) {
    final p = note.allParagraphs.single;
    WmlRunEdit.replaceRange(p, p.text.length, p.text.length, ' edited');
  }
}

void _assertModel(WmlDocument document, {required bool edited}) {
  expect(_blocks(document).map((c) => c.control.id).toSet(), {
    '71',
    '72',
    '73',
    '74',
    '78',
    '91',
    '92',
  });
  final controls = <WmlContentControlData>{
    ..._blocks(document).map((c) => c.control),
    for (final p in _allParagraphs(document))
      ...WordContentControls.spans(p).map((s) => s.control),
  };
  expect(controls.map((c) => c.id).toSet(), {
    for (var id = 71; id <= 78; id++) '$id',
    for (var id = 81; id <= 89; id++) '$id',
    '91',
    '92',
  });
  expect(controls, hasLength(19));
  expect(document.sections.single.blocks.first, isA<WmlParagraph>());
  expect(
    document.sections.single.blocks.whereType<WmlContentControlBlock>().single,
    same(_block(document, 71)),
  );
  expect(
    document.visuals.single.visual.picture.altTitle,
    'Inside content control',
  );
  expect(document.equations, hasLength(1));
  expect(WordToc.tocs(document).single.entries.single.text, 'Nested heading');
  expect(_block(document, 78).blocks.single, isA<WmlToc>());
  final table = WordTree.descendants(
    _block(document, 71).blocks,
  ).whereType<WmlTable>().single;
  final cell = _paragraph(
    document,
    edited ? 'Edited cell content' : 'Cell content',
  );
  expect(WordTable.locationOfParagraph(document, cell)!.table, same(table));
  expect(
    WordTree.locate(document, cell)!.parent,
    same(_block(document, 73).blocks),
  );
  final first = _paragraph(
    document,
    edited ? 'Block Edited' : 'Block Alpha Beta',
  );
  expect(first.properties.styleId, 'RichBody');
  expect(first.properties.spacingAfter, 6);
  expect(first.inlines.whereType<WmlRun>().first.properties.color, '345678');
  if (edited) {
    expect(
      _block(
        document,
        71,
      ).blocks.take(2).cast<WmlParagraph>().map((p) => p.text),
      ['Block Edited', ' Beta'],
    );
    expect(first.inlines.whereType<WmlRun>().last.properties.bold, isTrue);
    expect(
      _block(document, 74).blocks.cast<WmlParagraph>().map((p) => p.text),
      ['Frame content updated', 'Frame second'],
    );
    final paragraph = _paragraph(
      document,
      'Inline[Gamma Core tailempty filled]',
    );
    final spans = WordContentControls.spans(paragraph);
    expect(
      paragraph.text.substring(
        spans.singleWhere((s) => s.control.id == '75').start,
        spans.singleWhere((s) => s.control.id == '75').end,
      ),
      'Gamma Core tail',
    );
    expect(
      paragraph.text.substring(
        spans.singleWhere((s) => s.control.id == '76').start,
        spans.singleWhere((s) => s.control.id == '76').end,
      ),
      'Core',
    );
    expect(
      paragraph.text.substring(
        spans.singleWhere((s) => s.control.id == '77').start,
        spans.singleWhere((s) => s.control.id == '77').end,
      ),
      'empty filled',
    );
  }
  for (final note in [...document.footnotes, ...document.endnotes]) {
    expect(note.hasReferenceMarkers, isTrue);
    expect(
      note.allParagraphs.single.inlines.whereType<WmlNoteMarker>(),
      hasLength(1),
    );
  }
}

void main() {
  for (final kind in ['drawing', 'equation']) {
    test('unsupported inline control $kind stops import without changing source', () {
      final rich = kind == 'drawing'
          ? '<w:r><w:drawing><wp:inline xmlns:wp="${OfficeNamespaces.wp}"><wp:extent cx="381000" cy="381000"/></wp:inline></w:drawing></w:r>'
          : '<m:oMath xmlns:m="${OfficeNamespaces.m}"><m:r><m:t>x+1</m:t></m:r></m:oMath>';
      final package = _source(body: '<w:p>${_controlXml(101, rich)}</w:p>');
      final before = {
        for (final part in package.parts)
          part.uri: List<int>.of(part.bytesView),
      };
      final reader = WordDeserializer();
      expect(
        () => reader.read(package),
        throwsA(
          isA<UnsupportedError>().having(
            (e) => e.message,
            'location and unsupported topology',
            contains(
              '/word/document.xml: inline control containing a drawing or equation',
            ),
          ),
        ),
      );
      expect({
        for (final part in package.parts)
          part.uri: List<int>.of(part.bytesView),
      }, before);
      expect(reader.read(_source()).paragraphs.first.text, 'Outside before');
    });
  }

  for (final kind in ['rows', 'cells']) {
    test('unsupported table $kind control is diagnosed before flattening', () {
      const cell =
          '<w:tc><w:p><w:r><w:t>Controlled cell</w:t></w:r></w:p></w:tc>';
      final content = kind == 'rows'
          ? _controlXml(101, '<w:tr>$cell</w:tr>')
          : '<w:tr>${_controlXml(101, cell)}</w:tr>';
      final package = _source(
        body:
            '<w:tbl><w:tblGrid><w:gridCol w:w="4000"/></w:tblGrid>$content</w:tbl>',
      );
      final before = package.getPart('/word/document.xml')!.readText();
      expect(
        () => WordDeserializer().read(package),
        throwsA(
          isA<UnsupportedError>().having(
            (e) => e.message,
            'location and unsupported topology',
            contains(
              '/word/document.xml: content control wrapping table $kind',
            ),
          ),
        ),
      );
      expect(package.getPart('/word/document.xml')!.readText(), before);
    });
  }

  for (final story in [
    'header_default',
    'header_first',
    'header_even',
    'footer_default',
    'footer_first',
    'footer_even',
    'comments',
  ]) {
    test(
      'unsupported $story multi-paragraph control fails with its source part',
      () {
        final package = _source();
        final root = story.startsWith('header')
            ? 'hdr'
            : story.startsWith('footer')
            ? 'ftr'
            : 'comments';
        var body = _controlXml(
          101,
          '<w:p><w:r><w:t>Controlled story text</w:t></w:r></w:p>'
          '<w:p><w:r><w:t>Second controlled paragraph</w:t></w:r></w:p>',
        );
        if (story == 'comments') body = '<w:comment w:id="7">$body</w:comment>';
        final uri = '/word/$story.xml';
        package
            .getPart(uri)!
            .writeText(
              '<w:$root xmlns:w="${OfficeNamespaces.w}">$body</w:$root>',
            );
        final before = {
          for (final part in package.parts)
            part.uri: List<int>.of(part.bytesView),
        };
        expect(
          () => WordDeserializer().read(package),
          throwsA(
            isA<UnsupportedError>().having(
              (e) => e.message,
              'location and unsupported topology',
              contains('$uri: block control in a paragraph-only'),
            ),
          ),
        );
        expect({
          for (final part in package.parts)
            part.uri: List<int>.of(part.bytesView),
        }, before);
      },
    );
  }

  test('frame child parsing honors selected compatibility branches', () {
    final package = _source();
    final source = XmlDocument.parse(
      package.getPart('/word/document.xml')!.readText(),
    );
    final body = source.root!.firstChild('body')!;
    final drawing = _all(body, 'drawing').first;
    final frame = drawing.parent!.parent!;
    final textbox = _all(frame, 'txbxContent').single;
    final control = textbox.children.singleWhere(
      (node) => node is XmlElement && node.localName == 'sdt',
    );
    final alternate = XmlElement(
      localName: 'AlternateContent',
      prefix: 'mc',
      namespaceUri: OfficeNamespaces.mc,
    )..setAttribute('mc', OfficeNamespaces.mc, prefix: 'xmlns');
    final choice = XmlElement(
      localName: 'Choice',
      prefix: 'mc',
      namespaceUri: OfficeNamespaces.mc,
    )..setAttribute('Requires', 'w');
    choice.addChild(control);
    alternate.addChild(choice);
    textbox.children
      ..clear()
      ..add(alternate);
    final section = body.firstChild('sectPr')!;
    body.children
      ..clear()
      ..addAll([frame, section]);
    package.getPart('/word/document.xml')!.writeText(source.toXmlString());
    final document = WordDeserializer().read(package);
    expect(document.paragraphs.map((p) => p.text), ['Frame content']);
    expect(
      WordTree.locate(document, document.paragraphs.single)!.parent,
      same(_block(document, 74).blocks),
    );
  });

  test(
    'native rich controls retain editable structure, style cascade and exact owners',
    () {
      final document = WordDeserializer().read(_source());
      _assertModel(document, edited: false);
      final clone =
          WmlClone.block(_block(document, 71)) as WmlContentControlBlock;
      expect(clone.control, same(_block(document, 71).control));
      final original = WordTree.paragraphs(_block(document, 71).blocks).first;
      final copied = WordTree.paragraphs(clone.blocks).first;
      WmlRunEdit.replaceRange(copied, 0, 5, 'Copy');
      expect(original.text, 'Block Alpha Beta');
      expect(copied.text, 'Copy Alpha Beta');
    },
  );

  test(
    'authored native source is retained before first import and three unchanged saves',
    () async {
      final source = _source().save();
      final input = File('build/fidelity-content-controls/source.docx');
      input.parent.createSync(recursive: true);
      input.writeAsBytesSync(source);
      var document = WordDeserializer().readBytes(source);
      for (var cycle = 1; cycle <= 3; cycle++) {
        _assertModel(document, edited: false);
        final bytes = await OfficeIsolateSave.word(document);
        File(
          'build/fidelity-content-controls/imported-$cycle.docx',
        ).writeAsBytesSync(bytes);
        document = WordDeserializer().readBytes(bytes);
        _assertModel(document, edited: false);
      }
    },
  );

  for (final isolate in [false, true]) {
    final mode = isolate ? 'isolate' : 'direct';
    test(
      '$mode preserves edited controls and rich children through three native saves',
      () async {
        var document = WordDeserializer().read(_source());
        _edit(document);
        for (var cycle = 1; cycle <= 3; cycle++) {
          _assertModel(document, edited: true);
          final bytes = isolate
              ? await OfficeIsolateSave.word(document)
              : WordSerializer().writeBytes(document);
          final output = File(
            'build/fidelity-content-controls/$mode-$cycle.docx',
          );
          output.parent.createSync(recursive: true);
          output.writeAsBytesSync(bytes);
          final package = OpcPackage.openBytes(bytes);
          expect(
            package.getPart('/customXml/controlData.xml')!.readText(),
            _customer,
          );
          final xml = XmlDocument.parse(
            package.getPart('/word/document.xml')!.readText(),
          ).root!;
          final outer = _nativeControl(xml, 71);
          final content = outer.firstChild('sdtContent')!;
          expect(content.childrenNamed('p').take(2).map((p) => p.text), [
            'Block Edited',
            ' Beta',
          ]);
          expect(content.firstChild('tbl'), isNotNull);
          expect(_all(content, 'drawing'), hasLength(2));
          expect(
            _nativeControl(
              xml,
              74,
            ).firstChild('sdtContent')!.childrenNamed('p').map((p) => p.text),
            ['Frame content updated', 'Frame second'],
          );
          expect(
            _nativeControl(xml, 75).firstChild('sdtContent')!.text,
            'Gamma Core tail',
          );
          expect(
            _nativeControl(xml, 76).firstChild('sdtContent')!.text,
            'Core',
          );
          expect(
            _nativeControl(xml, 77).firstChild('sdtContent')!.text,
            'empty filled',
          );
          expect(
            _all(
              _nativeControl(xml, 78),
              'instrText',
            ).where((n) => WordToc.isTocInstruction(n.text)),
            hasLength(1),
          );
          expect(
            outer
                .firstChild('sdtPr')!
                .firstChild('dataBinding')!
                .getAttribute('xpath'),
            '/c:customer/c:name',
          );
          expect(
            outer
                .firstChild('sdtEndPr')!
                .firstChild('rPr')!
                .firstChild('lang')!
                .getAttribute('val'),
            'en-GB',
          );
          document = WordDeserializer().read(package);
        }
        _assertModel(document, edited: true);
      },
    );
  }

  for (final at in [2, 5]) {
    test(
      'split at inline ${at == 2 ? 'start' : 'end'} keeps one complete pair',
      () {
        final p = _simpleInline();
        final slices = WmlClone.splitInlines(p, at);
        final left = WmlParagraph(inlines: slices.head);
        final right = WmlParagraph(inlines: slices.tail);
        expect(left.text + right.text, 'abXYZcd');
        expect(WordContentControls.spans(left), hasLength(at == 5 ? 1 : 0));
        expect(WordContentControls.spans(right), hasLength(at == 2 ? 1 : 0));
      },
    );
  }

  test('empty control receives typing and moves as one pair on split', () {
    final p = _simpleInline(content: '');
    final split = WmlClone.splitInlines(p, 2);
    expect(
      WordContentControls.spans(WmlParagraph(inlines: split.head)),
      isEmpty,
    );
    expect(
      WordContentControls.spans(WmlParagraph(inlines: split.tail)),
      hasLength(1),
    );
    WmlRunEdit.replaceRange(p, 2, 2, 'typed');
    expect(p.text, 'abtypedcd');
    final span = WordContentControls.spans(p).single;
    expect((span.start, span.end), (2, 7));
  });

  test(
    'inline boundary typing has explicit start-inside end-outside affinity',
    () {
      final atStart = _simpleInline();
      WmlRunEdit.insertRuns(atStart, 2, [WmlRun(text: '!')]);
      final first = WordContentControls.spans(atStart).single;
      expect(atStart.text.substring(first.start, first.end), '!XYZ');
      final atEnd = _simpleInline();
      WmlRunEdit.replaceRange(atEnd, 5, 5, '!');
      final second = WordContentControls.spans(atEnd).single;
      expect(atEnd.text.substring(second.start, second.end), 'XYZ');
      expect(atEnd.text, 'abXYZ!cd');
    },
  );

  test(
    'unsupported split and crossing text replacement fail before mutation',
    () {
      final p = _simpleInline();
      final before = List<WmlInline>.of(p.inlines);
      expect(() => WmlClone.splitInlines(p, 3), throwsUnsupportedError);
      expect(
        () => WmlRunEdit.replaceRange(p, 1, 4, 'bad'),
        throwsUnsupportedError,
      );
      expect(
        () => WmlRunEdit.replaceRange(p, 3, 6, ''),
        throwsUnsupportedError,
      );
      expect(
        () => WmlRunEdit.replaceRange(p, 0, 7, ''),
        throwsUnsupportedError,
      );
      expect(p.inlines, orderedEquals(before));
      expect(p.text, 'abXYZcd');
    },
  );

  test(
    'complete inline text replacement keeps metadata; format may cross boundaries',
    () {
      final p = _simpleInline();
      final control = WordContentControls.spans(p).single.control;
      WmlRunEdit.replaceRange(p, 2, 5, 'new');
      WmlRunEdit.applyRange(p, 0, 7, (props) => props.italic = true);
      expect(p.text, 'abnewcd');
      expect(WordContentControls.spans(p).single.control, same(control));
      expect(
        p.inlines.whereType<WmlRun>().every((r) => r.properties.italic),
        isTrue,
      );
    },
  );

  test(
    'complete copy retains wrapper and a partial copy reports unsupported',
    () {
      final p = _simpleInline();
      final sliced = WmlParagraph(inlines: WmlClone.sliceInlines(p, 2, 5));
      expect(sliced.text, 'XYZ');
      expect(WordContentControls.spans(sliced), hasLength(1));
      expect(() => WmlClone.sliceInlines(p, 3, 5), throwsUnsupportedError);
      expect(() => WmlClone.sliceInlines(p, 0, 3), throwsUnsupportedError);
    },
  );

  test(
    'malformed inline wrappers fail before direct or isolate package mutation',
    () async {
      final document = WordDeserializer().read(
        _source(
          body: '<w:p>${_controlXml(101, '<w:r><w:t>text</w:t></w:r>')}</w:p>',
        ),
      );
      final p = document.paragraphs.single;
      p.inlines.removeWhere((i) => i is WmlContentControlBoundary && !i.start);
      final before = document.package!
          .getPart('/word/document.xml')!
          .readText();
      expect(() => WordSerializer().write(document), throwsStateError);
      await expectLater(OfficeIsolateSave.word(document), throwsStateError);
      expect(
        document.package!.getPart('/word/document.xml')!.readText(),
        before,
      );
    },
  );

  test(
    'native-ID copy guards preserve the original document and package',
    () async {
      final document = WordDeserializer().read(
        _source(
          body: _controlXml(101, '<w:p><w:r><w:t>Original</w:t></w:r></w:p>'),
        ),
      );
      final block = document.sections.single.blocks.single;
      final copied = WmlClone.block(block);
      expect(
        () => WordContentControls.assertCanInsert(document, [copied]),
        throwsUnsupportedError,
      );
      expect(document.sections.single.blocks, [same(block)]);
      final before = document.package!
          .getPart('/word/document.xml')!
          .readText();
      document.sections.single.blocks.add(copied);
      expect(() => WordSerializer().write(document), throwsStateError);
      await expectLater(OfficeIsolateSave.word(document), throwsStateError);
      expect(
        document.package!.getPart('/word/document.xml')!.readText(),
        before,
      );
    },
  );

  test(
    'native-ID guard covers inline copies and reads authoritative shell IDs',
    () {
      final document = WordDeserializer().read(
        _source(
          body:
              '<w:p>${_controlXml(101, '<w:r><w:t>Original</w:t></w:r>')}</w:p>',
        ),
      );
      expect(
        () => WordContentControls.assertCanInsert(document, [
          WmlClone.paragraph(document.paragraphs.single),
        ]),
        throwsUnsupportedError,
      );
      final control = WordContentControls.spans(
        document.paragraphs.single,
      ).single.control;
      final stale = WmlContentControlData(
        xml: control.xml,
        sourcePartUri: control.sourcePartUri,
        relationships: control.relationships,
      );
      expect(stale.id, isNull);
      expect(
        () => WordContentControls.assertCanInsert(document, [
          WmlContentControlBlock(control: stale),
        ]),
        throwsUnsupportedError,
      );
      expect(
        () => WordContentControls.assertCanInsert(WmlDocument.empty(), [
          WmlClone.paragraph(document.paragraphs.single),
        ]),
        returnsNormally,
      );
    },
  );

  test(
    'transparent controls render the same editable content as an unwrapped tree',
    () {
      final controlled = WordDeserializer().read(_source());
      final flat = WordDeserializer().read(_source());
      void unwrap(List<WmlBlock> blocks) {
        final visible = WordTree.visibleBlocks(blocks).toList();
        blocks
          ..clear()
          ..addAll(visible);
        for (final block in blocks) {
          if (block is WmlParagraph) {
            block.inlines.removeWhere(
              (inline) => inline is WmlContentControlBoundary,
            );
          }
          for (final children in WordTree.childLists(block)) {
            unwrap(children);
          }
        }
      }

      for (final section in flat.sections) {
        unwrap(section.blocks);
      }
      final left = WordLayoutEngine(font: null).layout(controlled);
      final right = WordLayoutEngine(font: null).layout(flat);
      Object geometry(LaidOutDocument value) => [
        for (final page in value.pages)
          [
            for (final line in page.lines)
              [
                line.paragraphIndex,
                line.x,
                line.y,
                line.width,
                for (final glyph in line.glyphs)
                  [glyph.glyph.logicalIndex, glyph.glyph.codePoint],
              ],
          ],
      ];
      expect(geometry(left), geometry(right));
      final expected = controlled.paragraphs.toList();
      for (final text in [
        'Block Alpha Beta',
        'Cell content',
        'Frame content',
        'Inline[Beta Inner tail]',
      ]) {
        final index = expected.indexWhere((p) => p.text == text);
        expect(
          left.pages
              .expand((p) => p.lines)
              .any((l) => l.paragraphIndex == index),
          isTrue,
          reason: '$text remains visible and addressable',
        );
      }
    },
  );

  test('note pane edits transparent controls through their exact owners', () {
    final document = WordDeserializer().read(_source());
    final original = _block(document, 91);
    final note = document.footnotes.single;
    // The plain text pane intentionally excludes table and frame contents.
    final table = WmlTable(
      rows: [
        WmlTableRow(
          cells: [
            WmlTableCell(
              blocks: [
                WmlParagraph(inlines: [WmlRun(text: 'Table stays')]),
              ],
            ),
          ],
        ),
      ],
    );
    original.blocks.add(table);
    expect(WordNotes.editableText(note), 'Footnote body');
    expect(
      WordNotes.editableParagraphs(note).single,
      same(original.blocks.first),
    );
    WordNotes.editText(note, 'Footnote changed');
    expect(WordNotes.editableText(note), 'Footnote changed');
    expect(note.blocks.single, same(original));
    expect(original.blocks.last, same(table));
    final span = WordContentControls.spans(
      WordNotes.editableParagraphs(note).single,
    ).single;
    expect(span.control.id, '88');
    expect(
      WordNotes.editableParagraphs(
        note,
      ).single.text.substring(span.start, span.end),
      'changed',
    );
    expect(note.hasReferenceMarkers, isTrue);
  });

  test(
    'note line additions and removals retain surrounding block controls',
    () {
      final document = WordDeserializer().read(_source());
      final template = _block(document, 91);
      template.blocks
        ..clear()
        ..add(WmlParagraph(inlines: [WmlRun(text: 'First')]));
      final note = document.footnotes.single;
      WordNotes.editText(note, 'First edited\nSecond\nThird');
      expect(note.blocks.single, same(template));
      expect(template.blocks.cast<WmlParagraph>().map((p) => p.text), [
        'First edited',
        'Second',
        'Third',
      ]);
      WordNotes.editText(note, 'First edited');
      expect(template.blocks.single, isA<WmlParagraph>());
      template.blocks.clear();
      WordNotes.editText(note, 'Inside empty control');
      expect(note.blocks.single, same(template));
      expect(
        (template.blocks.single as WmlParagraph).text,
        'Inside empty control',
      );
    },
  );

  test(
    'later unsupported note edit cannot partly change an earlier paragraph',
    () {
      final document = WordDeserializer().read(_source());
      final note = document.footnotes.single;
      final block = _block(document, 91);
      block.blocks.insert(0, WmlParagraph(inlines: [WmlRun(text: 'First')]));
      final before = WordNotes.editableText(note);
      expect(
        () => WordNotes.editText(
          note,
          'Changed\nEntire replacement crosses boundary',
        ),
        throwsUnsupportedError,
      );
      expect(WordNotes.editableText(note), before);
      expect(
        () => WordNotes.editText(note, 'One line'),
        throwsUnsupportedError,
      );
      expect(WordNotes.editableText(note), before);
    },
  );
}
