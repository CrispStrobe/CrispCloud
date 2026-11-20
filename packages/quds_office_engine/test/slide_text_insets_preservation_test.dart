import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/automation/operations/slide_steps.dart';
import 'package:test/test.dart';

const _slideUri = '/ppt/slides/slide1.xml';
const _layoutUri = '/ppt/slideLayouts/reviewLayout.xml';
const _foreign = 'urn:insets:review';
const _ns =
    'xmlns:p="${OfficeNamespaces.p}" xmlns:d="${OfficeNamespaces.a}" '
    'xmlns:r="${OfficeNamespaces.r}" xmlns:x="$_foreign"';

String _shapeXml({
  String attributes = '',
  String children = '',
  bool placeholder = false,
  int height = 100,
}) =>
    '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Inset review"/>'
    '<p:cNvSpPr txBox="1"/><p:nvPr>'
    '${placeholder ? '<p:ph type="body" idx="4"/>' : ''}'
    '</p:nvPr></p:nvSpPr><p:spPr>'
    '<d:xfrm><d:off x="127000" y="127000"/>'
    '<d:ext cx="3810000" cy="${height * 12700}"/></d:xfrm>'
    '<d:noFill/></p:spPr><p:txBody>'
    '<d:bodyPr $attributes>$children</d:bodyPr><d:lstStyle/>'
    '<d:p><d:r><d:rPr sz="2000"/><d:t>Retained text</d:t></d:r>'
    '<d:endParaRPr lang="de-DE"/></d:p></p:txBody></p:sp>';

String _part(String name, String shape) =>
    '<p:$name $_ns><p:cSld name="Inset review"><p:spTree>'
    '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/>'
    '</p:nvGrpSpPr><p:grpSpPr/>$shape</p:spTree></p:cSld></p:$name>';

OpcPackage _package({
  String attributes = '',
  String children = '',
  bool placeholder = false,
  int height = 100,
}) {
  final package = OpcPackage.openBytes(
    SlideSerializer().writeBytes(
      PmlPresentation(
        slides: <PmlSlide>[
          PmlSlide(
            id: 256,
            shapes: <PmlShape>[PmlShape(id: 2, name: 'Inset review')],
          ),
        ],
      ),
    ),
  );
  package
      .getPart(_slideUri)!
      .writeText(
        _part(
          'sld',
          _shapeXml(
            attributes: attributes,
            children: children,
            placeholder: placeholder,
            height: height,
          ),
        ),
      );
  return package;
}

PmlShape _shape(PmlPresentation deck) => deck.slides.single.shapes.single;

XmlElement _nativeShape(Uint8List bytes) =>
    XmlDocument.parse(
          OpcPackage.openBytes(bytes).getPart(_slideUri)!.readText(),
        ).root!
        .firstChild('cSld', namespaceUri: OfficeNamespaces.p)!
        .firstChild('spTree', namespaceUri: OfficeNamespaces.p)!
        .firstChild('sp', namespaceUri: OfficeNamespaces.p)!;

XmlElement _body(Uint8List bytes) =>
    _nativeShape(bytes).firstChild('txBody', namespaceUri: OfficeNamespaces.p)!;

XmlElement _properties(Uint8List bytes) =>
    _body(bytes).firstChild('bodyPr', namespaceUri: OfficeNamespaces.a)!;

String _xml(XmlElement element) =>
    XmlDocument(root: element.copy()).toXmlString(declaration: false);

List<PdfDrawText> _pdfText(PmlPresentation deck) => PdfFile.open(
  OfficePdfExport.presentation(deck),
).displayList(0).ops.whereType<PdfDrawText>().toList();

void _set(PmlPresentation deck, Map<String, Object?> values) => applySlideStep(
  deck,
  <String, Object?>{'op': 'shapeTextFrame', 'slide': 0, 'shape': 0, ...values},
);

void main() {
  test('margin-only edits keep unsaved independently styled rich runs', () {
    final shape = PmlShape(
      id: 2,
      name: 'Authored rich runs',
      text: 'AB',
      fontSizePt: 20,
      richText: <PmlTextParagraph>[
        PmlTextParagraph(
          align: PmlTextAlign.right,
          runs: <PmlTextRun>[
            PmlTextRun(text: 'A', fontSizePt: 40, bold: true, color: 'FF0000'),
            PmlTextRun(
              text: 'B',
              fontSizePt: 10,
              italic: true,
              color: '0000FF',
            ),
          ],
        ),
      ],
    );
    final deck = PmlPresentation(
      slides: <PmlSlide>[
        PmlSlide(id: 256, shapes: <PmlShape>[shape]),
      ],
    );
    _set(deck, <String, Object?>{'marginLeft': 0, 'marginRight': 12});
    final resolved = shape.resolvedRichText.single;
    expect(resolved.align, PmlTextAlign.right);
    expect(resolved.runs.map((r) => r.text), <String>['A', 'B']);
    expect(resolved.runs.map((r) => r.fontSizePt), <double>[40, 10]);
    expect(resolved.runs.map((r) => r.color), <String>['FF0000', '0000FF']);
    expect(resolved.runs.first.bold, isTrue);
    expect(resolved.runs.last.italic, isTrue);
    expect(shape.richText.single.runs, hasLength(2));
    expect(shape.copy().resolvedRichText.single.runs, hasLength(2));
  });

  test(
    'negative and unprojectable native margins remain opaque on another-side write',
    () {
      var deck = SlideDeserializer().read(
        _package(
          attributes:
              'lIns="-12700" tIns="000" rIns="not-an-integer" bIns="2147483648"',
        ),
      );
      expect(_shape(deck).textInsets.left, -1);
      _set(deck, <String, Object?>{'marginTop': 1.25});
      for (var cycle = 0; cycle < 3; cycle++) {
        final bytes = SlideSerializer().writeBytes(deck);
        final properties = _properties(bytes);
        expect(properties.getAttribute('lIns', namespaceUri: ''), '-12700');
        expect(
          properties.getAttribute('rIns', namespaceUri: ''),
          'not-an-integer',
        );
        expect(properties.getAttribute('bIns', namespaceUri: ''), '2147483648');
        expect(properties.getAttribute('tIns', namespaceUri: ''), '15875');
        deck = SlideDeserializer().readBytes(bytes);
        expect(_shape(deck).textInsets.left, -1);
        expect(_shape(deck).textInsets.top, 1.25);
      }
    },
  );

  test(
    'a placeholder override keeps unassigned sides absent and its layout source exact',
    () {
      final package = _package(placeholder: true);
      final layout = _part(
        'sldLayout',
        _shapeXml(
          placeholder: true,
          attributes: 'lIns="254000" tIns="127000" rIns="381000" bIns="190500"',
        ),
      );
      package.createPart(
        _layoutUri,
        OfficeContentTypes.slideLayout,
        utf8.encode(layout),
      );
      final relationships = package.relationshipsFor(_slideUri);
      for (final relationship in relationships.items.toList()) {
        if (relationship.type == RelationshipTypes.slideLayout) {
          relationships.removeById(relationship.id);
        }
      }
      relationships.add(
        type: RelationshipTypes.slideLayout,
        target: '../slideLayouts/reviewLayout.xml',
      );
      var deck = SlideDeserializer().read(package);
      _set(deck, <String, Object?>{'marginLeft': 7.2});
      for (var cycle = 0; cycle < 3; cycle++) {
        final bytes = SlideSerializer().writeBytes(deck);
        final saved = OpcPackage.openBytes(bytes);
        expect(saved.getPart(_layoutUri)!.readText(), layout);
        final properties = _properties(bytes);
        expect(properties.getAttribute('lIns', namespaceUri: ''), '91440');
        for (final name in <String>['tIns', 'rIns', 'bIns']) {
          expect(properties.getAttribute(name, namespaceUri: ''), isNull);
        }
        final binding = _nativeShape(bytes)
            .firstChild('nvSpPr', namespaceUri: OfficeNamespaces.p)!
            .firstChild('nvPr', namespaceUri: OfficeNamespaces.p)!
            .firstChild('ph', namespaceUri: OfficeNamespaces.p)!;
        expect(binding.getAttribute('type'), 'body');
        expect(binding.getAttribute('idx'), '4');
        expect(
          saved
              .relationshipsFor(_slideUri)
              .firstByType(RelationshipTypes.slideLayout)!
              .target,
          '../slideLayouts/reviewLayout.xml',
        );
        deck = SlideDeserializer().read(saved);
      }
      // Deliberately no live inherited-value assertion: that projection is outside
      // direct bodyPr support. The native inheritance chain remains intact.
    },
  );

  for (final height in <int>[0, 3, 7]) {
    test(
      'height $height autofit text remains visible after margin edits and reopening',
      () {
        var deck = SlideDeserializer().read(
          _package(height: height, children: '<d:spAutoFit/>'),
        );
        _set(deck, <String, Object?>{'marginLeft': 16, 'marginTop': 5});
        for (var cycle = 0; cycle < 3; cycle++) {
          final text = _pdfText(deck);
          expect(text.map((op) => op.text).join(), 'Retained text');
          expect(text.every((op) => op.x.isFinite && op.y.isFinite), isTrue);
          final bytes = SlideSerializer().writeBytes(deck);
          expect(
            _properties(
              bytes,
            ).firstChild('spAutoFit', namespaceUri: OfficeNamespaces.a),
            isNotNull,
          );
          deck = SlideDeserializer().readBytes(bytes);
        }
      },
    );
  }

  test(
    'direct native insets win over foreign and extension bodyPr lookalikes',
    () {
      final package = _package(
        attributes: 'lIns="127000" tIns="63500" x:lIns="foreign" anchor="ctr"',
        children:
            '<x:bodyPr lIns="9" anchor="b"/>'
            '<d:extLst><d:ext uri="unrelated">'
            '<d:bodyPr lIns="1" tIns="2" anchor="b"/>'
            '<x:bodyPr lIns="8"/></d:ext></d:extLst>',
      );
      final original = package.save();
      final sourceExtension = _xml(
        _properties(
          original,
        ).firstChild('extLst', namespaceUri: OfficeNamespaces.a)!,
      );
      var deck = SlideDeserializer().readBytes(original);
      expect(_shape(deck).textInsets.left, 10);
      expect(_shape(deck).textInsets.top, 5);
      expect(_shape(deck).textAnchor, PmlTextAnchor.center);
      _set(deck, <String, Object?>{'marginRight': 2});
      for (var cycle = 0; cycle < 3; cycle++) {
        final bytes = SlideSerializer().writeBytes(deck);
        final properties = _properties(bytes);
        expect(properties.getAttribute('lIns', namespaceUri: ''), '127000');
        expect(
          properties.getAttribute('lIns', namespaceUri: _foreign),
          'foreign',
        );
        expect(properties.getAttribute('rIns', namespaceUri: ''), '25400');
        expect(
          _xml(
            properties.firstChild('extLst', namespaceUri: OfficeNamespaces.a)!,
          ),
          sourceExtension,
        );
        expect(
          properties
              .firstChild('bodyPr', namespaceUri: _foreign)
              ?.getAttribute('lIns'),
          '9',
        );
        deck = SlideDeserializer().readBytes(bytes);
        expect(_shape(deck).textInsets.left, 10);
        expect(_shape(deck).textInsets.top, 5);
        expect(_shape(deck).textAnchor, PmlTextAnchor.center);
      }
    },
  );

  for (final emu in <int>[1, 2147483647]) {
    test(
      'integer EMU $emu survives native write and repeated saves exactly',
      () {
        var deck = SlideDeserializer().read(_package());
        _set(deck, <String, Object?>{'marginBottom': emu / 12700});
        for (var cycle = 0; cycle < 3; cycle++) {
          final bytes = SlideSerializer().writeBytes(deck);
          expect(
            _properties(bytes).getAttribute('bIns', namespaceUri: ''),
            '$emu',
          );
          deck = SlideDeserializer().readBytes(bytes);
          expect(_shape(deck).textInsets.bottom, emu / 12700);
        }
      },
    );
  }
}
