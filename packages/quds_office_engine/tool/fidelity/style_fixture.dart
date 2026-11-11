import 'dart:convert';
import 'dart:io';
import 'package:quds_office_engine/quds_office_engine.dart';

/// Authored style cascade. No Word serializer is used to create the input.
OpcPackage styleFixture() {
  final p = OpcPackage.create(OpcPackageKind.word);
  p.getPart('/word/document.xml')!.writeText('''
<w:document xmlns:w="${OfficeNamespaces.w}"><w:body>
<w:p><w:pPr><w:pStyle w:val="Child"/></w:pPr><w:r><w:t>Inherited paragraph</w:t></w:r></w:p>
<w:p><w:pPr><w:pStyle w:val="Child"/><w:spacing w:before="0"/></w:pPr><w:r><w:rPr><w:rStyle w:val="Accent"/></w:rPr><w:t>Character style</w:t></w:r><w:r><w:rPr><w:rStyle w:val="Accent"/><w:b w:val="0"/><w:color w:val="000000"/><w:sz w:val="22"/></w:rPr><w:t> direct override</w:t></w:r></w:p>
<w:p><w:r><w:t>Document defaults</w:t></w:r></w:p>
<w:p><w:pPr><w:pStyle w:val="CycleA"/></w:pPr><w:r><w:t>Cyclic source terminates</w:t></w:r></w:p>
<w:tbl><w:tblPr><w:tblStyle w:val="Regional"/><w:tblLook w:firstRow="1"/></w:tblPr><w:tblGrid><w:gridCol w:w="4000"/></w:tblGrid><w:tr><w:tc><w:p><w:r><w:t>Table header</w:t></w:r></w:p></w:tc></w:tr><w:tr><w:tc><w:p><w:r><w:t>Table body</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
<w:sectPr/></w:body></w:document>''');
  p.createPart(
    '/word/styles.xml',
    OfficeContentTypes.wordStyles,
    utf8.encode('''
<w:styles xmlns:w="${OfficeNamespaces.w}">
<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:asciiTheme="minorHAnsi"/><w:sz w:val="24"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="100"/></w:pPr></w:pPrDefault></w:docDefaults>
<w:style w:type="paragraph" w:styleId="Base"><w:name w:val="Base"/><w:pPr><w:spacing w:before="240"/></w:pPr><w:rPr><w:b/><w:color w:val="225588" w:themeColor="accent1"/><w:sz w:val="28"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Child"><w:name w:val="Child"/><w:basedOn w:val="Base"/><w:pPr><w:spacing w:after="60"/></w:pPr></w:style>
<w:style w:type="character" w:styleId="AccentBase"><w:name w:val="Accent base"/><w:rPr><w:i/></w:rPr></w:style>
<w:style w:type="character" w:styleId="Accent"><w:name w:val="Accent"/><w:basedOn w:val="AccentBase"/><w:rPr><w:color w:val="AA3300"/><w:sz w:val="32"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="CycleA"><w:basedOn w:val="CycleB"/></w:style><w:style w:type="paragraph" w:styleId="CycleB"><w:basedOn w:val="CycleA"/></w:style>
<w:style w:type="table" w:styleId="Regional"><w:name w:val="Regional"/><w:rPr><w:color w:val="334455"/></w:rPr><w:tblStylePr w:type="firstRow"><w:rPr><w:b/><w:color w:val="FFFFFF"/></w:rPr><w:tcPr><w:shd w:val="clear" w:fill="225588"/></w:tcPr></w:tblStylePr></w:style>
</w:styles>'''),
  );
  final native = OpcPackage.openBytes(
    File('test/fixtures/fidelity/native.pptx').readAsBytesSync(),
  );
  String theme = native.getPart('/ppt/theme/theme1.xml')!.readText();
  theme = theme.replaceAll('4F81BD', '225588');
  p.createPart(
    '/word/theme/theme1.xml',
    OfficeContentTypes.theme,
    utf8.encode(theme),
  );
  p.relationshipsFor('/word/document.xml')
    ..add(type: RelationshipTypes.styles, target: 'styles.xml')
    ..add(type: RelationshipTypes.theme, target: 'theme/theme1.xml');
  return p;
}
