import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/automation/operations/slide_steps.dart';
import 'package:test/test.dart';

const _part = '/ppt/slides/slide1.xml';
const _foreign = 'urn:margin:foreign';

Uint8List _bytes({
  String attributes = '',
  String body = '',
  bool empty = false,
}) {
  final package = OpcPackage.openBytes(
    SlideSerializer().writeBytes(
      PmlPresentation(
        slides: [
          PmlSlide(id: 256, shapes: [PmlShape(id: 2, name: 'Title')]),
        ],
      ),
    ),
  );
  package.getPart(_part)!.writeText('''
<p:sld xmlns:p="${OfficeNamespaces.p}" xmlns:a="${OfficeNamespaces.a}"
 xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
 xmlns:x="$_foreign">
<p:cSld><p:spTree>
 <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>
 <p:sp><p:nvSpPr><p:cNvPr id="2" name="Title"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>
 <p:spPr><a:xfrm><a:off x="381000" y="508000"/><a:ext cx="3810000" cy="2540000"/></a:xfrm><a:noFill/></p:spPr>
 <p:txBody><a:bodyPr x:lIns="foreign-left" x:bIns="foreign-bottom" $attributes>$body</a:bodyPr>
 <a:lstStyle/>
 <a:p><a:pPr algn="l"/><a:r><a:rPr sz="2000" b="1"><a:hlinkClick r:id="rIdKeep"/></a:rPr><a:t>${empty ? '' : 'Margin text'}</a:t></a:r>
 <a:fld id="{11111111-1111-1111-1111-111111111111}" type="slidenum"><a:rPr sz="2000"/><a:t>${empty ? '' : '1'}</a:t></a:fld>
 <a:endParaRPr lang="en-US"/></a:p></p:txBody>
 </p:sp></p:spTree></p:cSld></p:sld>
''');
  return package.save();
}

OfficeMacro _plan(String body) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-powerpoint',
    format: OfficeMacroFormat.pptx,
    source:
        '''
Sub Main()
Dim frame As TextFrame
Set frame = ActivePresentation.Slides(1).Shapes("Title").TextFrame
$body
End Sub
''',
  ),
);

PmlPresentation _read(Uint8List bytes) => SlideDeserializer().readBytes(bytes);
PmlShape _shape(PmlPresentation deck) => deck.slides.single.shapes.single;
XmlElement _body(Uint8List bytes) =>
    XmlDocument.parse(OpcPackage.openBytes(bytes).getPart(_part)!.readText())
        .root!
        .firstChild('cSld', namespaceUri: OfficeNamespaces.p)!
        .firstChild('spTree', namespaceUri: OfficeNamespaces.p)!
        .firstChild('sp', namespaceUri: OfficeNamespaces.p)!
        .firstChild('txBody', namespaceUri: OfficeNamespaces.p)!;
XmlElement _properties(Uint8List bytes) =>
    _body(bytes).firstChild('bodyPr', namespaceUri: OfficeNamespaces.a)!;
String _xml(XmlElement element) =>
    XmlDocument(root: element.copy()).toXmlString(declaration: false);
List<double> _insets(PmlShape shape) => [
  for (final side in PmlTextInsetSide.values) shape.textInsets[side],
];

void main() {
  test(
    'import projects only direct native inset attributes and preserves opaque neighbors',
    () {
      final bytes = _bytes(
        attributes:
            'lIns="114300" tIns="57150" rIns="228600" bIns="76200" anchor="ctr"',
        body:
            '<x:bodyPr lIns="1"/><a:extLst><a:ext uri="nested"><a:bodyPr lIns="2"/></a:ext></a:extLst>',
      );
      var deck = _read(bytes);
      expect(_insets(_shape(deck)), [9, 4.5, 18, 6]);
      expect(_shape(deck).textAnchor, PmlTextAnchor.center);
      for (var i = 0; i < 2; i++) {
        final saved = SlideSerializer().writeBytes(deck);
        expect(_xml(_properties(saved)), _xml(_properties(bytes)));
        deck = _read(saved);
        expect(_insets(_shape(deck)), [9, 4.5, 18, 6]);
      }
    },
  );

  test(
    'partial margin writes preserve other margins, rich XML, autofit and namespaces',
    () async {
      final input = _bytes(
        attributes:
            'lIns="114300" tIns="57150" rIns="228600" bIns="76200" anchor="ctr" vert="vert270" wrap="none"',
        body:
            '<a:normAutofit fontScale="80000" lnSpcReduction="12000"/><a:extLst><a:ext uri="keep"><x:data value="keep"/></a:ext></a:extLst>',
      );
      final originalParagraph = _xml(
        _body(input).firstChild('p', namespaceUri: OfficeNamespaces.a)!,
      );
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.pptx);
      final plan = _plan('frame.MarginLeft = 0\nframe.MarginBottom = 12.5');
      await session.validate(plan);
      expect(session.bytes, input);
      expect(session.revision, 0);
      await session.run(plan);
      var bytes = session.bytes;
      for (var i = 0; i < 3; i++) {
        final shape = _shape(_read(bytes));
        expect(_insets(shape), [0, 4.5, 18, 12.5]);
        expect(shape.textAnchor, PmlTextAnchor.center);
        expect(shape.textScale, 0.8);
        expect(shape.lineSpacingReduction, 0.12);
        final props = _properties(bytes);
        expect(props.getAttribute('lIns', namespaceUri: ''), '0');
        expect(props.getAttribute('bIns', namespaceUri: ''), '158750');
        expect(
          props.getAttribute('lIns', namespaceUri: _foreign),
          'foreign-left',
        );
        expect(
          props.getAttribute('bIns', namespaceUri: _foreign),
          'foreign-bottom',
        );
        expect(props.getAttribute('vert', namespaceUri: ''), 'vert270');
        expect(props.getAttribute('wrap', namespaceUri: ''), 'none');
        expect(
          _xml(_body(bytes).firstChild('p', namespaceUri: OfficeNamespaces.a)!),
          originalParagraph,
        );
        expect(_xml(props), contains('value="keep"'));
        bytes = SlideSerializer().writeBytes(_read(bytes));
      }
      expect(session.revision, 1);
    },
  );

  test(
    'same-value writes are explicit and omitted defaults stay omitted',
    () async {
      final session = OfficeMacroSession(
        _bytes(),
        format: OfficeMacroFormat.pptx,
      );
      await session.run(_plan('frame.MarginLeft = 7.2\nframe.MarginTop = 3.6'));
      final props = _properties(session.bytes);
      expect(props.getAttribute('lIns', namespaceUri: ''), '91440');
      expect(props.getAttribute('tIns', namespaceUri: ''), '45720');
      expect(props.getAttribute('rIns', namespaceUri: ''), isNull);
      expect(props.getAttribute('bIns', namespaceUri: ''), isNull);
    },
  );

  test(
    'margin intent and live values survive independent copies of an empty shape',
    () {
      final shape = PmlShape(id: 2, name: 'Empty');
      final deck = PmlPresentation(
        slides: [
          PmlSlide(id: 256, shapes: [shape]),
        ],
      );
      applySlideStep(deck, {
        'op': 'shapeTextFrame',
        'slide': 0,
        'shape': 0,
        'marginLeft': 0,
        'marginTop': 0,
        'marginRight': 0,
        'marginBottom': 0,
      });
      final copy = shape.copy();
      copy.textInsetOverrides.clear();
      expect(shape.textInsetOverrides, hasLength(4));
      var reopened = _read(SlideSerializer().writeBytes(deck));
      reopened = _read(SlideSerializer().writeBytes(reopened));
      expect(_shape(reopened).text, '');
      expect(_insets(_shape(reopened)), [0, 0, 0, 0]);
      expect(
        _body(
          SlideSerializer().writeBytes(reopened),
        ).childrenNamed('p', namespaceUri: OfficeNamespaces.a),
        hasLength(1),
      );
    },
  );

  test(
    'combined native call validates all margins before mutating the model',
    () {
      final deck = _read(_bytes());
      expect(
        () => applySlideStep(deck, {
          'op': 'shapeTextFrame',
          'slide': 0,
          'shape': 0,
          'anchor': 'bottom',
          'marginLeft': 1,
          'marginBottom': 0.00001,
        }),
        throwsArgumentError,
      );
      expect(_insets(_shape(deck)), [7.2, 3.6, 7.2, 3.6]);
      expect(_shape(deck).textAnchor, PmlTextAnchor.top);
      expect(_shape(deck).textInsetOverrides, isEmpty);
    },
  );

  for (final fields in <Map<String, Object?>>[
    {},
    {'marginLeft': -1},
    {'marginTop': double.nan},
    {'marginRight': double.infinity},
    {'marginBottom': 2147483648 / 12700},
    {'marginLeft': '1'},
    {'marginLeft': true},
  ]) {
    test('invalid native frame request is refused: $fields', () {
      expect(
        () => applySlideStep(_read(_bytes()), {
          'op': 'shapeTextFrame',
          'slide': 0,
          'shape': 0,
          ...fields,
        }),
        throwsArgumentError,
      );
    });
  }

  test(
    'a later missing shape rolls back margins and text atomically',
    () async {
      final input = _bytes();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.pptx);
      final plan = _plan('''
frame.MarginLeft = 20
frame.TextRange.Text = "Changed"
ActivePresentation.Slides(1).Shapes("Missing").TextFrame.MarginTop = 1
''');
      await expectLater(
        session.run(plan),
        throwsA(isA<OfficeMacroException>()),
      );
      expect(session.bytes, input);
      expect(session.revision, 0);
    },
  );

  test('margin writes obey native tool permission', () async {
    final input = _bytes();
    final session = OfficeMacroSession(
      input,
      format: OfficeMacroFormat.pptx,
      policy: OfficeMacroPolicy(allowedTools: {'pptx.shapeText'}),
    );
    await expectLater(
      session.run(_plan('frame.MarginLeft = 1')),
      throwsA(isA<OfficeMacroException>()),
    );
    expect(session.bytes, input);
    expect(session.revision, 0);
  });

  test(
    'PDF placement follows live margins and asymmetric middle/bottom anchors',
    () {
      List<PdfDrawText> text(PmlPresentation deck) => PdfFile.open(
        OfficePdfExport.presentation(deck),
      ).displayList(0).ops.whereType<PdfDrawText>().toList();
      final deck = _read(
        _bytes(attributes: 'lIns="0" tIns="0" rIns="0" bIns="0"'),
      );
      final initial = text(deck).first;
      applySlideStep(deck, {
        'op': 'shapeTextFrame',
        'slide': 0,
        'shape': 0,
        'marginLeft': 20,
        'marginTop': 10,
        'marginRight': 5,
        'marginBottom': 30,
      });
      final top = text(deck).first;
      expect(top.x - initial.x, closeTo(20, 0.001));
      expect((top.y - initial.y).abs(), closeTo(10, 0.001));
      applySlideStep(deck, {
        'op': 'shapeTextFrame',
        'slide': 0,
        'shape': 0,
        'anchor': 'bottom',
      });
      final bottom = text(deck).first;
      applySlideStep(deck, {
        'op': 'shapeTextFrame',
        'slide': 0,
        'shape': 0,
        'anchor': 'center',
      });
      final middle = text(deck).first;
      expect(middle.x, closeTo(top.x, 0.001));
      expect(middle.y, closeTo((top.y + bottom.y) / 2, 0.001));
      final reopened = text(_read(SlideSerializer().writeBytes(deck))).first;
      expect(reopened.x, closeTo(middle.x, 0.001));
      expect(reopened.y, closeTo(middle.y, 0.001));
    },
  );

  test(
    'consumed content rectangle retains overflow without nonfinite PDF coordinates',
    () {
      final deck = _read(_bytes());
      applySlideStep(deck, {
        'op': 'shapeTextFrame',
        'slide': 0,
        'shape': 0,
        'marginLeft': 300,
      });
      expect(_shape(deck).textInsets.contentWidth(300), 0);
      final text = PdfFile.open(
        OfficePdfExport.presentation(deck),
      ).displayList(0).ops.whereType<PdfDrawText>();
      expect(text, isNotEmpty);
      expect(text.every((run) => run.x.isFinite && run.y.isFinite), isTrue);
    },
  );
}
