import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as raster;
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _office = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _text = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _draw = 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0';
const _svg = 'urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0';
const _style = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _table = 'urn:oasis:names:tc:opendocument:xmlns:table:1.0';
const _xlink = 'http://www.w3.org/1999/xlink';

final _png = Uint8List.fromList(
  raster.encodePng(raster.Image(width: 2, height: 3)),
);
final _jpeg = Uint8List.fromList(
  raster.encodeJpg(raster.Image(width: 4, height: 2)),
);

Uint8List _odt(
  String body, {
  String styles = '',
  Map<String, Uint8List>? files,
}) {
  final zip = ZipWriter()
    ..addFile(
      'mimetype',
      utf8.encode('application/vnd.oasis.opendocument.text'),
      store: true,
    )
    ..addFile(
      'content.xml',
      utf8.encode(
        '<office:document-content xmlns:office="$_office" xmlns:text="$_text" '
        'xmlns:draw="$_draw" xmlns:svg="$_svg" xmlns:style="$_style" '
        'xmlns:table="$_table" xmlns:xlink="$_xlink">'
        '<office:automatic-styles>$styles</office:automatic-styles>'
        '<office:body><office:text>$body</office:text></office:body>'
        '</office:document-content>',
      ),
    );
  for (final entry in (files ?? {'Pictures/image.png': _png}).entries) {
    zip.addFile(entry.key, entry.value);
  }
  return zip.close();
}

String _image({
  String href = 'Pictures/image.png',
  String anchor = 'as-char',
  String width = '24pt',
  String height = '36pt',
  String frameAttributes = '',
  String imageAttributes = '',
  String children = '',
}) =>
    '<draw:frame text:anchor-type="$anchor" draw:name="Object name" '
    'svg:width="$width" svg:height="$height" $frameAttributes>'
    '<draw:image xlink:href="$href" xlink:type="simple" $imageAttributes/>'
    '$children</draw:frame>';

String _citation(String id, String text) {
  final name = encodeXmlAttribute(
    'ZOTERO_ITEM CSL_CITATION ${jsonEncode({
      'citationID': id,
      'citationItems': [
        {
          'id': 1,
          'itemData': {'id': 1, 'type': 'book', 'title': 'Source'},
        },
      ],
      'properties': {'plainCitation': text},
    })} RND${id.padRight(10, '0')}',
  );
  return '<text:reference-mark-start text:name="$name"/>$text'
      '<text:reference-mark-end text:name="$name"/>';
}

List<WmlRun> _pictures(WmlDocument document) => [
  for (final paragraph in [
    ...document.paragraphs,
    for (final note in [...document.footnotes, ...document.endnotes])
      ...note.allParagraphs,
  ])
    ...paragraph.inlines.whereType<WmlRun>().where(
      (run) => run.inlineVisual != null,
    ),
];

void main() {
  test(
    'raw inline picture preserves bytes, extents, object name, alt and hyperlink',
    () async {
      var document = await OdtDocumentReader.readBytes(
        _odt(
          '<text:p>Before<text:a xlink:href="https://example.test/source" xlink:type="simple">'
          '${_image(children: '<svg:title>Title العربية 😀</svg:title><svg:desc>Alt &amp; description</svg:desc>')}'
          '</text:a>After</text:p>',
        ),
      );
      for (var cycle = 0; cycle < 3; cycle++) {
        expect(document.paragraphs.single.text, 'Before\uFFFCAfter');
        final picture = _pictures(document).single;
        expect(picture.text, '\uFFFC');
        expect(picture.hyperlink?.url, 'https://example.test/source');
        final visual = picture.inlineVisual!.visual;
        expect(visual.imageBytes, orderedEquals(_png));
        expect(visual.width, 24);
        expect(visual.height, 36);
        expect(visual.picture.altTitle, 'Title العربية 😀');
        expect(visual.picture.altDescription, 'Alt & description');
        if (cycle == 0) expect(visual.title, 'Object name');
        document = WordDeserializer().readBytes(
          WordSerializer().writeBytes(document),
        );
      }
    },
  );

  test('PNG and RGB JPEG use the same bounded raster path', () async {
    final document = await OdtDocumentReader.readBytes(
      _odt(
        '<text:p>${_image()}${_image(href: 'Pictures/second.jpg', width: '1in', height: '0.5in')}</text:p>',
        files: {'Pictures/image.png': _png, 'Pictures/second.jpg': _jpeg},
      ),
    );
    final pictures = _pictures(document);
    expect(pictures.length, 2);
    expect(pictures.last.inlineVisual!.visual.imageBytes, orderedEquals(_jpeg));
    expect(pictures.last.inlineVisual!.visual.width, 72);
    expect(pictures.last.inlineVisual!.visual.height, 36);
  });

  test(
    'identical citations around pictures retain exact rich offsets and packets',
    () async {
      final bytes = _odt(
        '<text:p>${_citation('before', '(X)')}${_image()}'
        '${_citation('after', '(X)')}<text:s/>${_image()}${_citation('last', '(X)')}</text:p>',
      );
      final inventory = await OdfZotero.inspect(bytes);
      expect(
        inventory.issues,
        isNotEmpty,
      ); // The inventory remains conservative.
      final document = await OdtDocumentReader.readBytes(bytes);
      expect(document.paragraphs.single.text, '(X)\uFFFC(X) \uFFFC(X)');
      expect(_pictures(document).length, 2);
      final fields = WordZotero.fields(document);
      expect(fields.map((field) => field.start), [0, 4, 9]);
      expect(fields.map((field) => field.end), [3, 7, 12]);
      expect(fields.map((field) => field.citation!.citationId), [
        'before',
        'after',
        'last',
      ]);
      expect(
        fields.every((field) => field.canEdit && field.cachedText == '(X)'),
        isTrue,
      );
    },
  );

  test(
    'empty citation boundaries touching a picture preserve source order',
    () async {
      final document = await OdtDocumentReader.readBytes(
        _odt(
          '<text:p>${_citation('before', '')}${_image()}${_citation('after', '')}</text:p>',
        ),
      );
      final fields = WordZotero.fields(document);
      expect(fields.map((field) => (field.start, field.end)), [(0, 0), (1, 1)]);
      expect(_pictures(document).single.text, '\uFFFC');
    },
  );

  test(
    'pictures in body table cells and authored notes remain independently owned',
    () async {
      final document = await OdtDocumentReader.readBytes(
        _odt(
          '<table:table><table:table-row><table:table-cell>'
          '<text:p>${_image()}${_citation('cell', '(C)')}</text:p>'
          '</table:table-cell></table:table-row></table:table>'
          '<text:p>Anchor<text:note text:id="n1" text:note-class="footnote">'
          '<text:note-citation>1</text:note-citation><text:note-body>'
          '<text:p>${_image()}${_citation('foot', '(F)')}</text:p>'
          '</text:note-body></text:note></text:p>'
          '<text:p>Anchor<text:note text:id="n2" text:note-class="endnote">'
          '<text:note-citation>1</text:note-citation><text:note-body>'
          '<text:p>${_image()}${_citation('end', '(E)')}</text:p>'
          '</text:note-body></text:note></text:p>',
        ),
      );
      expect(_pictures(document).length, 3);
      expect(
        WordZotero.fields(document).map((field) => field.citation!.citationId),
        ['cell', 'foot', 'end'],
      );
      expect(document.footnotes.single.paragraphs.single.text, '\uFFFC(F)');
      expect(document.endnotes.single.paragraphs.single.text, '\uFFFC(E)');
    },
  );

  test(
    'literal whitespace and Unicode retain field offsets across a picture',
    () async {
      final document = await OdtDocumentReader.readBytes(
        _odt(
          '<text:p>😀 العربية ${_image()} ${_citation('unicode', '(ع)')} tail</text:p>',
        ),
      );
      final field = WordZotero.fields(document).single;
      expect(field.paragraph.text.substring(field.start, field.end), '(ع)');
      expect(field.paragraph.text, '😀 العربية \uFFFC (ع) tail');
    },
  );

  test(
    'an inline picture inside a citation is refused even at its final text offset',
    () async {
      for (final content in ['${_image()}X', 'X${_image()}', _image()]) {
        await expectLater(
          OdtDocumentReader.readBytes(
            _odt('<text:p>${_citation('inside', content)}</text:p>'),
          ),
          throwsA(isA<FormatException>()),
        );
      }
    },
  );

  final invalidFrames = <String, String>{
    'floating anchor': _image(anchor: 'paragraph'),
    'missing raster': _image(href: 'Pictures/missing.png'),
    'external URL': _image(href: 'https://example.test/p.png'),
    'absolute package path': _image(href: '/Pictures/image.png'),
    'parent traversal': _image(href: 'Pictures/../Pictures/image.png'),
    'encoded parent traversal': _image(
      href: 'Pictures/%2e%2e/Pictures/image.png',
    ),
    'encoded slash': _image(href: 'Pictures%2fimage.png'),
    'backslash': _image(href: 'Pictures\\image.png'),
    'query': _image(href: 'Pictures/image.png?load=1'),
    'fragment': _image(href: 'Pictures/image.png#part'),
    'nonpicture package part': _image(href: 'content.xml'),
    'percent extent': _image(width: '100%'),
    'zero extent': _image(height: '0pt'),
    'overlarge extent': _image(width: '4001pt'),
    'nonfinite extent': _image(width: 'NaNpt'),
    'transformed frame': _image(frameAttributes: 'draw:transform="rotate(1)"'),
    'text box child': _image(
      children: '<draw:text-box><text:p>Hidden</text:p></draw:text-box>',
    ),
    'image alternative': _image(
      children: '<draw:image xlink:href="Pictures/image.png"/>',
    ),
    'event listeners': _image(children: '<office:event-listeners/>'),
    'nested alt markup': _image(
      children: '<svg:desc><text:span>Hidden</text:span></svg:desc>',
    ),
    'duplicate title': _image(
      children: '<svg:title>A</svg:title><svg:title>B</svg:title>',
    ),
    'image href behavior': _image(imageAttributes: 'xlink:show="new"'),
    'MIME mismatch': _image(imageAttributes: 'draw:mime-type="image/jpeg"'),
    'authored nonbreaking space in frame': _image(children: '&#160;'),
  };
  for (final entry in invalidFrames.entries) {
    test(
      'refuses ${entry.key} without publishing a partial document',
      () async {
        await expectLater(
          OdtDocumentReader.readBytes(
            _odt('<text:p>Before${entry.value}After</text:p>'),
          ),
          throwsA(anyOf(isA<UnsupportedError>(), isA<FormatException>())),
        );
      },
    );
  }

  test(
    'unrelated drawing observations remain refused after a valid picture',
    () async {
      await expectLater(
        OdtDocumentReader.readBytes(
          _odt(
            '<text:p>${_image()}<draw:object xlink:href="Object1"/></text:p>',
          ),
        ),
        throwsA(isA<UnsupportedError>()),
      );
    },
  );

  test(
    'valid picture cannot launder a picture in an ignored style story',
    () async {
      final bytes = _odt(
        '<text:p>${_image()}</text:p>',
        styles:
            '<style:style style:name="Unused" style:family="paragraph">'
            '<draw:frame text:anchor-type="as-char">'
            '<draw:image xlink:href="Pictures/image.png"/>'
            '</draw:frame></style:style>',
      );
      await expectLater(
        OdtDocumentReader.readBytes(bytes),
        throwsA(isA<UnsupportedError>()),
      );
    },
  );

  test('missing and cyclic graphic styles cannot be ignored', () async {
    final image = _image(frameAttributes: 'draw:style-name="G"');
    for (final styles in [
      '',
      '<style:style style:name="G" style:family="graphic" style:parent-style-name="G"/>',
    ]) {
      await expectLater(
        OdtDocumentReader.readBytes(
          _odt('<text:p>$image</text:p>', styles: styles),
        ),
        throwsA(isA<FormatException>()),
      );
    }
  });

  test('active graphic formatting is not silently flattened', () async {
    await expectLater(
      OdtDocumentReader.readBytes(
        _odt(
          '<text:p>${_image(frameAttributes: 'draw:style-name="G"')}</text:p>',
          styles:
              '<style:style style:name="G" style:family="graphic">'
              '<style:graphic-properties draw:opacity="50%"/></style:style>',
        ),
      ),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('embedded malformed raster and oversized data are refused', () async {
    for (final bytes in [
      Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
      Uint8List(4 * 1024 * 1024 + 1),
    ]) {
      await expectLater(
        OdtDocumentReader.readBytes(
          _odt(
            '<text:p>${_image()}</text:p>',
            files: {'Pictures/image.png': bytes},
          ),
        ),
        throwsA(anyOf(isA<FormatException>(), isA<ZipException>())),
      );
    }
  });

  test(
    'duplicate references count towards the document image budget',
    () async {
      await expectLater(
        OdtDocumentReader.readBytes(
          _odt('<text:p>${List.filled(33, _image()).join()}</text:p>'),
        ),
        throwsA(isA<FormatException>()),
      );
    },
  );

  WmlRun nativePicture() => WmlRun(
    text: '\uFFFC',
    inlineVisual: WmlVisual(
      visual: OfficeVisual(
        kind: OfficeVisualKind.picture,
        title: 'Object',
        imageBytes: Uint8List.fromList(_png),
        width: 24,
        height: 36,
        picture: PictureAdjust(
          altTitle: 'Title',
          altDescription: 'Description',
        ),
      ),
    ),
  );

  WmlDocument nativeDocument(WmlRun picture) => WmlDocument(
    sections: [
      WmlSection(
        blocks: [
          WmlParagraph(
            inlines: [
              WmlRun(text: 'Before'),
              picture,
              WmlRun(text: 'After'),
            ],
          ),
        ],
      ),
    ],
  );

  for (final mutation in <String, void Function(WmlRun)>{
    'mixed placeholder text': (run) => run.text = 'Before\uFFFC',
    'missing picture bytes': (run) =>
        run.inlineVisual!.visual.imageBytes = null,
    'floating wrapping': (run) =>
        run.inlineVisual!.visual.picture.wrap = PictureWrap.square,
    'rotation': (run) => run.inlineVisual!.visual.picture.rotationDeg = 90,
    'crop': (run) => run.inlineVisual!.visual.picture.cropLeft = 0.1,
    'aspect unlocking': (run) =>
        run.inlineVisual!.visual.picture.lockAspect = false,
    'transparency': (run) =>
        run.inlineVisual!.visual.picture.transparency = 0.5,
    'nonpicture kind': (run) =>
        run.inlineVisual!.visual.kind = OfficeVisualKind.chartBar,
    'unpaired alt title surrogate': (run) =>
        run.inlineVisual!.visual.picture.altTitle = String.fromCharCode(0xd800),
    'invalid XML alt description': (run) =>
        run.inlineVisual!.visual.picture.altDescription = '\u0000',
  }.entries) {
    test('explicit output refuses ${mutation.key} atomically', () {
      final run = nativePicture();
      mutation.value(run);
      final document = nativeDocument(run);
      final paragraph = document.paragraphs.single;
      final before = paragraph.text;
      final inlines = [...paragraph.inlines];
      final imageBytes = run.inlineVisual!.visual.imageBytes;
      final byteCopy = imageBytes == null ? null : [...imageBytes];
      expect(
        () => OdtDocumentWriter.writeEditableZoteroBytes(document),
        throwsA(anyOf(isA<UnsupportedError>(), isA<FormatException>())),
      );
      expect(document.paragraphs.single, same(paragraph));
      expect(paragraph.inlines, orderedEquals(inlines));
      expect(paragraph.text, before);
      expect(run.inlineVisual!.visual.imageBytes, same(imageBytes));
      if (byteCopy != null) expect(imageBytes, orderedEquals(byteCopy));
      expect(document.package, isNull);
    });
  }

  test('explicit output refuses shared picture owners', () {
    for (final shareWrapper in [false, true]) {
      final first = nativePicture();
      final second = WmlRun(
        text: '\uFFFC',
        inlineVisual: shareWrapper
            ? first.inlineVisual
            : WmlVisual(visual: first.inlineVisual!.visual),
      );
      final document = nativeDocument(first);
      document.paragraphs.single.inlines.add(second);
      expect(
        () => OdtDocumentWriter.writeEditableZoteroBytes(document),
        throwsA(isA<UnsupportedError>()),
      );
      expect(document.paragraphs.single.inlines.last, same(second));
    }
  });

  test('explicit output refuses unsupported picture story ownership', () {
    final picture = nativePicture();
    final document = WmlDocument(
      sections: [
        WmlSection(
          header: [
            WmlParagraph(inlines: [picture]),
          ],
        ),
      ],
    );
    expect(
      () => OdtDocumentWriter.writeEditableZoteroBytes(document),
      throwsA(isA<UnsupportedError>()),
    );
    expect(
      document.sections.single.header.single.inlines.single,
      same(picture),
    );
  });

  test(
    'ordinary output writes one object position and accessibility metadata',
    () async {
      final document = nativeDocument(nativePicture());
      final bytes = OdtDocumentWriter.writeBytes(document);
      final package = OpcPackage.openBytes(bytes);
      final content = package.getPart('/content.xml')!.readText();
      expect(content, isNot(contains('\uFFFC')));
      expect(content, contains('<svg:title>Title</svg:title>'));
      expect(content, contains('<svg:desc>Description</svg:desc>'));
      final reopened = await OdtDocumentReader.readBytes(bytes);
      expect(reopened.paragraphs.single.text, 'Before\uFFFCAfter');
      expect(
        _pictures(reopened).single.inlineVisual!.visual.picture.altDescription,
        'Description',
      );
    },
  );

  test(
    'native picture run character properties survive editable ODT output',
    () async {
      final picture = nativePicture();
      picture.properties
        ..fontSizeHalfPoints = 88
        ..bold = true
        ..italic = true
        ..vertAlign = WmlVertAlign.superscript
        ..color = '123456';
      final document = nativeDocument(picture);
      final reopened = await OdtDocumentReader.readBytes(
        OdtDocumentWriter.writeEditableZoteroBytes(document),
      );
      final properties = _pictures(reopened).single.properties;
      expect(properties.fontSizeHalfPoints, 88);
      expect(properties.bold, isTrue);
      expect(properties.italic, isTrue);
      expect(properties.vertAlign, WmlVertAlign.superscript);
      expect(properties.color, '123456');
    },
  );

  test(
    'equal picture titles produce distinct drawing identities across stories',
    () async {
      final first = nativePicture();
      final second = nativePicture();
      final third = nativePicture()..inlineVisual!.visual.title = 'Object 2';
      final unnamed = nativePicture()..inlineVisual!.visual.title = '';
      final document = nativeDocument(first);
      document.paragraphs.single.inlines.addAll([second, third, unnamed]);
      final header = nativePicture();
      document.sections.single.header.add(WmlParagraph(inlines: [header]));
      final package = OpcPackage.openBytes(
        OdtDocumentWriter.writeBytes(document),
      );
      final names = <String>[];
      for (final part in ['/content.xml', '/styles.xml']) {
        names.addAll(
          RegExp(r'draw:name="([^"]*)"')
              .allMatches(package.getPart(part)!.readText())
              .map((match) => match.group(1)!),
        );
      }
      expect(names.length, 5);
      expect(names.toSet().length, 5);
      expect(names, everyElement(isNotEmpty));
      expect(first.inlineVisual!.visual.title, 'Object');
      expect(second.inlineVisual!.visual.title, 'Object');
      expect(third.inlineVisual!.visual.title, 'Object 2');
      expect(unnamed.inlineVisual!.visual.title, isEmpty);
      expect(header.inlineVisual!.visual.title, 'Object');
      document.sections.single.header.clear();
      final reopened = await OdtDocumentReader.readBytes(
        OdtDocumentWriter.writeEditableZoteroBytes(document),
      );
      expect(_pictures(reopened).length, 4);
      expect(
        _pictures(
          reopened,
        ).map((run) => run.inlineVisual!.visual.picture.altTitle),
        everyElement('Title'),
      );
    },
  );
}
