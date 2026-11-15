import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/fidelity/office_steps.dart' as cli;

// A picture inside a line of text used to be pulled out of its paragraph
// and written as a paragraph of its own after the text.
const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

String _picture(String rid, int id, {int cx = 190500, int cy = 190500}) =>
    '<w:r><w:drawing><wp:inline xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing">'
    '<wp:extent cx="$cx" cy="$cy"/><wp:docPr id="$id" name="Picture $id"/>'
    '<a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
    '<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
    '<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
    '<pic:nvPicPr><pic:cNvPr id="$id" name="p$id"/><pic:cNvPicPr/></pic:nvPicPr>'
    '<pic:blipFill><a:blip xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" r:embed="$rid"/>'
    '<a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
    '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
    '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic>'
    '</a:graphicData></a:graphic></wp:inline></w:drawing></w:r>';

OpcPackage _package({bool withHeader = false}) {
  final package = OpcPackage.create(OpcPackageKind.word);
  package.createPart('/word/media/icon.png', 'image/png', _png);
  package
      .relationshipsFor('/word/document.xml')
      .add(id: 'rId9', type: RelationshipTypes.image, target: 'media/icon.png');
  if (withHeader) {
    package
        .createPart('/word/header1.xml', OfficeContentTypes.wordHeader)
        .writeText(
          '<w:hdr xmlns:w="$_w" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
          '<w:p><w:r><w:t xml:space="preserve">Confidential </w:t></w:r>'
          '${_picture('rIdH', 7)}'
          '<w:r><w:t xml:space="preserve"> draft</w:t></w:r></w:p></w:hdr>',
        );
    package
        .relationshipsFor('/word/header1.xml')
        .add(
          id: 'rIdH',
          type: RelationshipTypes.image,
          target: 'media/icon.png',
        );
    package
        .relationshipsFor('/word/document.xml')
        .add(
          id: 'rIdHdr',
          type: RelationshipTypes.header,
          target: 'header1.xml',
        );
  }
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="$_w" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><w:body>'
        '<w:p><w:r><w:t xml:space="preserve">Click </w:t></w:r>${_picture('rId9', 1)}'
        '<w:r><w:t xml:space="preserve"> to continue.</w:t></w:r></w:p>'
        '<w:p>${_picture('rId9', 2, cx: 952500, cy: 952500)}</w:p>'
        '<w:sectPr>${withHeader ? '<w:headerReference w:type="default" r:id="rIdHdr"/>' : ''}</w:sectPr>'
        '</w:body></w:document>',
      );
  return package;
}

String _xml(WmlDocument doc) =>
    WordSerializer().write(doc).getPart('/word/document.xml')!.readText();

void main() {
  test('a picture inside a sentence stays inside it', () async {
    var doc = WordDeserializer().read(_package());
    for (var cycle = 0; cycle < 3; cycle++) {
      final first = doc.paragraphs.first;
      expect(first.text, 'Click ￼ to continue.', reason: '$cycle');
      final run = first.inlines.whereType<WmlRun>().singleWhere(
        (r) => r.inlineVisual != null,
      );
      expect(run.isAtomic, isTrue);
      expect(run.inlineVisual!.visual.width, closeTo(15, 0.5));
      final xml = _xml(doc);
      final paragraphs = RegExp(r'<w:p[ >].*?</w:p>').allMatches(xml).toList();
      final sentence = paragraphs.firstWhere(
        (m) => m[0]!.contains('Click'),
      )[0]!;
      expect(sentence, contains('<w:drawing>'));
      expect(
        sentence.indexOf('Click'),
        lessThan(sentence.indexOf('<w:drawing>')),
      );
      expect(
        sentence.indexOf('<w:drawing>'),
        lessThan(sentence.indexOf('to continue')),
      );
      expect(xml, isNot(contains('￼')));
      doc = WordDeserializer().readBytes(await OfficeIsolateSave.word(doc));
    }
  });

  test('a picture-only paragraph keeps its block representation', () {
    final doc = WordDeserializer().read(_package());
    expect(doc.sections.single.blocks.whereType<WmlVisual>(), hasLength(1));
    expect(doc.inlineVisuals, hasLength(1));
    expect(doc.visuals, hasLength(2));
  });

  test('image steps reach inline pictures', () {
    final doc = WordDeserializer().read(_package());
    final inline = doc.inlineVisuals.single;
    final index = doc.visuals.toList().indexOf(inline);
    cli.applyStep(doc, {
      'op': 'imageSize',
      'image': index,
      'width': 30,
      'height': 30,
    });
    expect(inline.visual.width, 30);
    expect(_xml(doc), contains('cx="381000"'));
  });

  test('a header picture stays inline and keeps its media', () async {
    final doc = WordDeserializer().read(_package(withHeader: true));
    final section = doc.sections.single;
    expect(section.header.single.text, 'Confidential ￼ draft');
    expect(section.headerVisuals, isEmpty);

    final saved = WordSerializer().write(doc);
    final rels = saved.relationshipsFor('/word/document.xml');
    final headerUri = rels.resolve(
      rels.items.singleWhere((rel) => rel.type == RelationshipTypes.header),
    );
    final header = saved.getPart(headerUri)!.readText();
    expect(header, contains('<w:drawing>'));
    expect(header, isNot(contains('￼')));
    final headerRels = saved.relationshipsFor(headerUri);
    final imageUri = headerRels.resolve(
      headerRels.items.singleWhere(
        (rel) => rel.type == RelationshipTypes.image,
      ),
    );
    expect(saved.getPart(imageUri)!.readBytes(), _png);

    final reopened = WordDeserializer().read(saved);
    expect(reopened.sections.single.header.single.text, 'Confidential ￼ draft');
  });

  group('layout', () {
    LaidOutPage page(WmlDocument doc) =>
        WordLayoutEngine(font: null).layout(doc).pages.first;

    test('the picture sits on the baseline inside its line', () {
      final doc = WordDeserializer().read(_package());
      final first = page(doc);
      final line = first.lines.firstWhere(
        (l) => l.glyphs.any((g) => g.glyph.codePoint == 0xFFFC),
      );
      final placeholder = line.glyphs.firstWhere(
        (g) => g.glyph.codePoint == 0xFFFC,
      );
      final box = first.frames.firstWhere(
        (b) => identical(b.visual, doc.inlineVisuals.single.visual),
      );
      expect(box.x, closeTo(placeholder.x, 0.01));
      expect(box.y + box.height, closeTo(placeholder.y, 0.01));
      expect(box.width, closeTo(15, 0.5));
      // Text after the picture starts after it.
      final after = line.glyphs[line.glyphs.indexOf(placeholder) + 1];
      expect(after.x, greaterThanOrEqualTo(box.x + box.width - 0.01));
      // The picture-only paragraph is still a block visual below the line.
      final block = first.frames.firstWhere(
        (b) => !identical(b.visual, doc.inlineVisuals.single.visual),
      );
      expect(block.y, greaterThan(line.y + line.height - 0.01));
    });

    test('a picture taller than the text grows its line', () {
      final small = WordDeserializer().read(_package());
      final tall = WordDeserializer().read(_package());
      tall.inlineVisuals.single.visual
        ..width = 60
        ..height = 60;
      double heightOf(WmlDocument doc) => page(doc).lines
          .firstWhere((l) => l.glyphs.any((g) => g.glyph.codePoint == 0xFFFC))
          .height;
      expect(heightOf(tall), greaterThan(heightOf(small) + 40));
    });
  });
}
