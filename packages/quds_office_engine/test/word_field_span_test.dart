import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

// Complex fields that do not wrap a whole paragraph used to be read as a
// paragraph-level field: the instruction(s) were concatenated and on save the
// *entire paragraph* became the field result (a cross-reference inside a
// sentence, two hyperlinks in one paragraph, form fields, nested fields).
const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

String _r(String inner) => '<w:r>$inner</w:r>';
String _t(String text) => _r('<w:t xml:space="preserve">$text</w:t>');
String _fld(String type, [String inner = '']) => inner.isEmpty
    ? _r('<w:fldChar w:fldCharType="$type"/>')
    : _r('<w:fldChar w:fldCharType="$type">$inner</w:fldChar>');
String _instr(String text) =>
    _r('<w:instrText xml:space="preserve">$text</w:instrText>');
String _field(String instruction, String result, {String ffData = ''}) =>
    _fld('begin', ffData) +
    _instr(instruction) +
    _fld('separate') +
    _t(result) +
    _fld('end');

WmlDocument _read(String paragraphs) {
  final package = OpcPackage.create(OpcPackageKind.word);
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="$_w"><w:body>$paragraphs<w:sectPr/></w:body></w:document>',
      );
  return WordDeserializer().read(package);
}

String _xml(WmlDocument doc) =>
    WordSerializer().write(doc).getPart('/word/document.xml')!.readText();

Future<WmlDocument> _cycle(WmlDocument doc) async =>
    WordDeserializer().readBytes(await OfficeIsolateSave.word(doc));

void main() {
  test('non-text content before a field stays outside its result', () async {
    var doc = _read(
      '<w:p>'
      '<w:r><w:pict xmlns:v="urn:schemas-microsoft-com:vml">'
      '<v:rect id="outside-field" style="width:10pt;height:10pt"/>'
      '</w:pict></w:r>${_field(' DATE ', 'Today')}</w:p>',
    );
    for (var cycle = 0; cycle < 3; cycle++) {
      expect(doc.paragraphs.single.properties.fieldInstruction, isNull);
      final xml = _xml(doc);
      expect(
        xml.indexOf('outside-field'),
        lessThan(xml.indexOf('fldCharType="begin"')),
      );
      doc = await _cycle(doc);
    }
  });

  test('a cross-reference inside a sentence stays inside the sentence', () async {
    var doc = _read(
      '<w:p>${_t('See page ')}${_field(' PAGEREF _Ref1 \\h ', '5')}${_t(' for details.')}</w:p>',
    );
    for (var cycle = 0; cycle < 3; cycle++) {
      final p = doc.paragraphs.single;
      expect(p.text, 'See page 5 for details.');
      expect(p.properties.fieldInstruction, isNull);
      final xml = _xml(doc);
      // Text before and after stays outside the field.
      expect(
        xml.indexOf('See page'),
        lessThan(xml.indexOf('fldCharType="begin"')),
      );
      expect(
        xml.indexOf('fldCharType="end"'),
        lessThan(xml.indexOf('for details')),
      );
      expect('PAGEREF'.allMatches(xml), hasLength(1));
      doc = await _cycle(doc);
    }
  });

  test('two hyperlinks in one paragraph stay two fields', () async {
    var doc = _read(
      '<w:p>${_field(' HYPERLINK "https://a.example" ', 'A')}${_t(' and ')}'
      '${_field(' HYPERLINK "https://b.example" ', 'B')}</w:p>',
    );
    doc = await _cycle(doc);
    final xml = _xml(doc);
    expect(doc.paragraphs.single.text, 'A and B');
    expect('fldCharType="begin"'.allMatches(xml), hasLength(2));
    expect(xml, contains('HYPERLINK "https://a.example"'));
    expect(xml, contains('HYPERLINK "https://b.example"'));
  });

  test('form fields keep their ffData', () async {
    const ffData =
        '<w:ffData><w:name w:val="Check1"/><w:enabled/><w:calcOnExit w:val="0"/>'
        '<w:checkBox><w:sizeAuto/><w:default w:val="1"/></w:checkBox></w:ffData>';
    var doc = _read(
      '<w:p>${_t('Agreed: ')}${_fld('begin', ffData)}${_instr(' FORMCHECKBOX ')}${_fld('end')}</w:p>',
    );
    doc = await _cycle(doc);
    final xml = _xml(doc);
    expect(xml, contains('<w:name w:val="Check1"/>'));
    expect(xml, contains('<w:default w:val="1"/>'));
    expect(xml, contains('FORMCHECKBOX'));
    expect(doc.paragraphs.single.text, 'Agreed: ');
  });

  test('nested fields keep their structure', () async {
    var doc = _read(
      '<w:p>${_t('Dear ')}${_fld('begin')}${_instr(' IF ')}'
      '${_field(' MERGEFIELD Gender ', 'f')}${_instr(' = "f" "Madam" "Sir" ')}'
      '${_fld('separate')}${_t('Madam')}${_fld('end')}</w:p>',
    );
    doc = await _cycle(doc);
    final xml = _xml(doc);
    expect(doc.paragraphs.single.text, 'Dear fMadam');
    expect('fldCharType="begin"'.allMatches(xml), hasLength(2));
    expect('fldCharType="end"'.allMatches(xml), hasLength(2));
    expect(xml.indexOf(' IF '), lessThan(xml.indexOf('MERGEFIELD')));
  });

  test('a field wrapping the whole paragraph keeps the paragraph model', () {
    final doc = _read(
      '<w:p>${_field(' DATE \\@ "d.M.yyyy" ', '1.1.2026')}</w:p>',
    );
    final p = doc.paragraphs.single;
    expect(p.properties.fieldInstruction?.trim(), 'DATE \\@ "d.M.yyyy"');
    expect(p.inlines.whereType<WmlFieldBoundary>(), isEmpty);
  });

  test(
    'a field broken by an edit degrades to text, never to a corrupt package',
    () async {
      final doc = _read(
        '<w:p>${_t('See page ')}${_field(' PAGEREF _Ref1 \\h ', '5')}${_t(' for details.')}</w:p>',
      );
      final p = doc.paragraphs.single;
      p.inlines.removeWhere(
        (i) => i is WmlFieldBoundary && i.kind == WmlFieldBoundaryKind.end,
      );
      final xml = _xml(doc);
      expect(xml, isNot(contains('fldChar')));
      expect(xml, isNot(contains('instrText')));
      final reopened = await _cycle(doc);
      expect(reopened.paragraphs.single.text, 'See page 5 for details.');
    },
  );
}
