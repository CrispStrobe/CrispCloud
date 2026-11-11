import 'dart:io';
import 'package:quds_office_engine/quds_office_engine.dart';

/// Independently authored worksheet/slide XML, then repeated modify/save cycles.
Future<void> main(List<String> args) async {
  final Directory out = Directory(args.isEmpty ? 'build/fidelity' : args.single)
    ..createSync(recursive: true);
  final OpcPackage sheet = OpcPackage.create(OpcPackageKind.sheet);
  sheet.getPart('/xl/worksheets/sheet1.xml')!.writeText(
    '''
<worksheet xmlns="${OfficeNamespaces.x}"><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><sheetData>
<row r="1"><c r="A1" t="inlineStr"><is><t>Label</t></is></c><c r="B1"><v>2</v></c><c r="C1"><f>B1*3</f><v>6</v></c><c r="D1" t="b"><v>1</v></c></row>
</sheetData><mergeCells count="1"><mergeCell ref="A3:B3"/></mergeCells></worksheet>''',
  );
  final OpcPackage slide = OpcPackage.create(OpcPackageKind.slide);
  slide.getPart('/ppt/slides/slide1.xml')!.writeText('''
<p:sld xmlns:p="${OfficeNamespaces.p}" xmlns:a="${OfficeNamespaces.a}"><p:cSld><p:spTree>
<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>
<p:sp><p:nvSpPr><p:cNvPr id="2" name="Fixture"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="127000" y="254000"/><a:ext cx="2540000" cy="1270000"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr><p:txBody><a:bodyPr/><a:p><a:r><a:rPr sz="2400" b="1"/><a:t>Imported slide</a:t></a:r></a:p></p:txBody></p:sp>
</p:spTree></p:cSld></p:sld>''');
  for (final bool edited in <bool>[false, true]) {
    SmlWorkbook book = SheetDeserializer().readBytes(sheet.save());
    PmlPresentation deck = SlideDeserializer().readBytes(slide.save());
    if (edited) {
      book.sheets.first.cell(SmlCellRef.parse('B1')).value = 5;
      deck.slides.first.shapes.first.text = 'Edited slide';
      deck.slides.first.shapes.first.transform = const PmlTransform(
        x: 254000,
        y: 381000,
        cx: 3810000,
        cy: 1270000,
      );
    }
    FormulaEvaluator.recalculate(book);
    for (var cycle = 1; cycle <= 3; cycle++) {
      final String label = edited ? 'edited' : 'imported';
      final sheetBytes = await OfficeIsolateSave.workbook(book);
      final slideBytes = await OfficeIsolateSave.presentation(deck);
      File('${out.path}/sheet-$label-$cycle.xlsx').writeAsBytesSync(sheetBytes);
      File('${out.path}/slide-$label-$cycle.pptx').writeAsBytesSync(slideBytes);
      book = SheetDeserializer().readBytes(sheetBytes);
      deck = SlideDeserializer().readBytes(slideBytes);
    }
  }
  stdout.writeln('Wrote twelve XLSX/PPTX import/edit/reopen exports.');
}
