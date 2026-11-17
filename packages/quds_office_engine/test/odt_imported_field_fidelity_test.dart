import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _w = OfficeNamespaces.w;
const _textNs = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';

String _run(String xml, {String properties = ''}) =>
    '<w:r>$properties$xml</w:r>';

String _text(String text, {String properties = ''}) =>
    _run('<w:t xml:space="preserve">$text</w:t>', properties: properties);

String _boundary(String kind, {String attributes = '', String children = ''}) =>
    _run('<w:fldChar w:fldCharType="$kind"$attributes>$children</w:fldChar>');

String _instruction(String text, {String properties = ''}) => _run(
  '<w:instrText xml:space="preserve">$text</w:instrText>',
  properties: properties,
);

String _field(
  String instruction,
  String cache, {
  String beginAttributes = '',
  String beginChildren = '',
  String codeProperties = '',
}) =>
    _boundary('begin', attributes: beginAttributes, children: beginChildren) +
    _instruction(instruction, properties: codeProperties) +
    _boundary('separate') +
    _text(cache, properties: '<w:rPr><w:b/></w:rPr>') +
    _boundary('end');

WmlDocument _read(String field) {
  final package = OpcPackage.create(OpcPackageKind.word);
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="$_w" xmlns:extra="urn:field-test">'
        '<w:body><w:p>$field</w:p>'
        '<w:p>${_text('Following paragraph')}</w:p>'
        '<w:sectPr/></w:body></w:document>',
      );
  return WordDeserializer().read(package);
}

Iterable<XmlElement> _elements(XmlElement root, String name) sync* {
  if (root.namespaceUri == _textNs && root.localName == name) yield root;
  for (final child in root.childElements) {
    yield* _elements(child, name);
  }
}

String _visible(XmlNode node) {
  if (node is XmlText) return node.text;
  if (node is! XmlElement) return '';
  if (node.namespaceUri == _textNs) {
    switch (node.localName) {
      case 's':
        return ' ' * int.parse(node.getAttribute('c') ?? '1');
      case 'tab':
        return '\t';
      case 'line-break':
        return '\n';
    }
  }
  return node.children.map(_visible).join();
}

XmlElement _odt(WmlDocument document) {
  final package = OpcPackage.openBytes(OdtDocumentWriter.writeBytes(document));
  return XmlDocument.parse(package.getPart('/content.xml')!.readText()).root!;
}

String _nativeVisible(XmlElement node) {
  if (node.namespaceUri == _w && node.localName == 't') return node.text;
  return node.childElements.map(_nativeVisible).join();
}

void _expectCached(String packet, String cache, {bool reopen = true}) {
  var document = _read(packet);
  final cycles = reopen ? 2 : 1;
  for (var cycle = 0; cycle < cycles; cycle++) {
    final paragraph = document.paragraphs.first;
    expect(paragraph.text, cache);
    expect(paragraph.properties.fieldInstruction, isNull);
    expect(paragraph.properties.pageNumberField, isFalse);
    expect(paragraph.inlines.whereType<WmlFieldBoundary>(), isNotEmpty);
    final output = _odt(document);
    expect(_elements(output, 'page-number'), isEmpty);
    expect(_elements(output, 'page-count'), isEmpty);
    expect(_elements(output, 'p').map(_visible), [
      cache,
      'Following paragraph',
    ]);
    final saved = WordSerializer().write(document);
    final native = XmlDocument.parse(
      saved.getPart('/word/document.xml')!.readText(),
    ).root!;
    expect(_nativeVisible(native.firstChild('body')!.firstChild('p')!), cache);
    expect(paragraph.text, cache);
    if (cycle + 1 < cycles) document = WordDeserializer().read(saved);
  }
}

void main() {
  for (final locked in ['true', '1', 'on']) {
    test('imported locked PAGE ($locked) retains its numeric cache', () {
      _expectCached(
        _field(' PAGE ', '17', beginAttributes: ' w:fldLock="$locked"'),
        '17',
      );
    });
  }

  test('locked NUMPAGES retains its native boundary metadata on save', () {
    _expectCached(
      _field(' NUMPAGES ', '23', beginAttributes: ' w:fldLock="true"'),
      '23',
    );
  });

  test('an invalid field-lock value retains the authored cache', () {
    _expectCached(
      _field(' PAGE ', '17', beginAttributes: ' w:fldLock="unknown"'),
      '17',
    );
  });

  test('foreign boundary metadata retains its cache and boundary packet', () {
    _expectCached(
      _field(' PAGE ', '17', beginAttributes: ' extra:mode="fixed"'),
      '17',
    );
  });

  test('formatted instruction runs retain their cache and metadata', () {
    _expectCached(
      _field(' PAGE ', '17', codeProperties: '<w:rPr><w:i/></w:rPr>'),
      '17',
    );
  });

  test('form-data fields remain cached during DOCX-to-ODT export', () {
    _expectCached(_field(' PAGE ', '17', beginChildren: '<w:ffData/>'), '17');
  });

  test('a missing separator cannot erase a numeric PAGE cache', () {
    _expectCached(
      _boundary('begin') +
          _instruction(' PAGE ') +
          _text('17') +
          _boundary('end'),
      '17',
    );
  });

  test('duplicate separators retain all visible cached text', () {
    _expectCached(
      _boundary('begin') +
          _instruction(' PAGE ') +
          _boundary('separate') +
          _boundary('separate') +
          _text('17') +
          _boundary('end'),
      '17',
      reopen: false,
    );
  });

  test('an instruction after its separator retains the cache', () {
    _expectCached(
      _boundary('begin') +
          _boundary('separate') +
          _instruction(' PAGE ') +
          _text('17') +
          _boundary('end'),
      '17',
      reopen: false,
    );
  });

  test('text before its separator is not discarded as a PAGE result', () {
    _expectCached(
      _boundary('begin') +
          _instruction(' PAGE ') +
          _text('17') +
          _boundary('separate') +
          _text('18') +
          _boundary('end'),
      '1718',
      reopen: false,
    );
  });

  for (final example in [
    (r' PAGE \* ROMAN ', 'IV'),
    (r' PAGE \# "000" ', '017'),
    (r' PAGE \* Arabic ', '17'),
  ]) {
    test('unsupported imported PAGE switch retains ${example.$2}', () {
      _expectCached(_field(example.$1, example.$2), example.$2);
    });
  }

  test('an unterminated imported field keeps its cache and following text', () {
    _expectCached(
      _boundary('begin') +
          _instruction(' PAGE ') +
          _boundary('separate') +
          _text('17'),
      '17',
      reopen: false,
    );
  });

  test('nested imported fields keep both visible caches', () {
    _expectCached(
      _boundary('begin') +
          _instruction(' PAGE ') +
          _boundary('separate') +
          _text('17 of ') +
          _field(' NUMPAGES ', '23') +
          _boundary('end'),
      '17 of 23',
    );
  });

  for (final instruction in [' PAGE ', r' PAGE \* MERGEFORMAT ']) {
    test('complete supported instruction $instruction remains a live PAGE', () {
      final document = _read(_field(instruction, '17'));
      final paragraph = document.paragraphs.first;
      expect(paragraph.properties.fieldInstruction, instruction);
      expect(paragraph.properties.pageNumberField, isTrue);
      expect(paragraph.inlines.whereType<WmlFieldBoundary>(), isEmpty);
      expect(_elements(_odt(document), 'page-number'), hasLength(1));
    });
  }

  test(
    'fragmented complete PAGE instructions still use the paragraph model',
    () {
      final document = _read(
        _boundary('begin') +
            _instruction(' PA') +
            _instruction('GE ') +
            _boundary('separate') +
            _text('17') +
            _boundary('end'),
      );
      expect(document.paragraphs.first.properties.fieldInstruction, ' PAGE ');
      expect(document.paragraphs.first.properties.pageNumberField, isTrue);
      expect(_elements(_odt(document), 'page-number'), hasLength(1));
    },
  );

  test(
    'ordinary complete DATE keeps the established paragraph field model',
    () {
      final document = _read(_field(r' DATE \@ "d.M.yyyy" ', '17.11.2026'));
      final paragraph = document.paragraphs.first;
      expect(paragraph.properties.fieldInstruction, r' DATE \@ "d.M.yyyy" ');
      expect(paragraph.inlines.whereType<WmlFieldBoundary>(), isEmpty);
      expect(paragraph.text, '17.11.2026');
      expect(_elements(_odt(document), 'p').map(_visible), [
        '17.11.2026',
        'Following paragraph',
      ]);
    },
  );
}
