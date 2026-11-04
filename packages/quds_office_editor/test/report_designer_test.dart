import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show MaterialApp, Theme, ThemeData;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const double mm = 72 / 25.4;

const String sampleXml = r'''<?xml version="1.0" encoding="UTF-8"?>
<QudsReport name="Sample" pageSize="A4" mirrorRtl="true">
    <Settings>
        <Margins top="10mm" bottom="10mm" left="10mm" right="10mm"/>
    </Settings>
    <Bands>
        <ReportHeader height="30mm">
            <Element type="Text" name="title" x="20mm" y="5mm" width="60mm" height="10mm">Hello {{Data.customer}}</Element>
            <Element type="Text" name="sub" x="100mm" y="12mm" width="40mm" height="8mm">Sub</Element>
            <Element type="Shape" kind="Rectangle" name="box" x="150mm" y="2mm" width="30mm" height="20mm"/>
        </ReportHeader>
        <Detail dataSet="items" height="8mm">
            <Element type="Text" name="line" x="10mm" y="1mm" width="80mm" height="6mm">{{item.name}} {{item.qty}}</Element>
        </Detail>
        <ReportSummary height="12mm">
            <Element type="Text" x="10mm" y="2mm" width="80mm" height="8mm">{{SUM(items.qty)}}</Element>
        </ReportSummary>
    </Bands>
</QudsReport>
''';

ReportElement byName(ReportDesignerController c, String name) => c
    .template
    .allElements
    .map(((ReportBand, ReportElement) p) => p.$2)
    .firstWhere((ReportElement e) => e.name == name);

ReportDesignerController sample({bool rtl = false}) {
  final String xml = rtl
      ? sampleXml.replaceFirst('pageSize="A4"', 'pageSize="A4" isRtl="true"')
      : sampleXml;
  return ReportDesignerController.fromXml(
    xml,
    clock: () => DateTime(2026, 10, 10, 9, 30),
  );
}

class FakeDeviceFonts implements ReportDeviceFonts {
  FakeDeviceFonts(this.byFamily);

  final Map<String, ReportFontFiles> byFamily;
  var listed = 0;

  @override
  Future<List<String>> families() async {
    listed++;
    return byFamily.keys.toList()..sort();
  }

  @override
  Future<ReportFontFiles?> load(String family) async => byFamily[family];
}

Uint8List fontFile(String name) => File('fonts/$name').readAsBytesSync();

Future<void> settle() async {
  for (int i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// The ready-made `.qrep` files of `templates/`, in menu order.
List<ReportTemplateInfo> fileTemplates() => ReportTemplateLibrary.sorted(
  Directory('templates')
      .listSync()
      .whereType<File>()
      .where((File f) => f.path.endsWith('.qrep'))
      .map((File f) => ReportTemplateInfo.decode(f.readAsBytesSync())),
);

ReportTemplateInfo fileTemplate(String id) =>
    fileTemplates().firstWhere((ReportTemplateInfo t) => t.id == id);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReportDesignerController', () {
    test('nudge records one undo step and redo re-applies it', () {
      final ReportDesignerController c = sample();
      final ReportElement title = byName(c, 'title');
      c.select(title.id);
      final double x0 = title.x;
      c.nudge(5 * mm, 0);
      expect(title.x, closeTo(x0 + 5 * mm, 0.01));
      expect(c.canUndo, isTrue);
      c.undo();
      expect(byName(c, 'title').x, closeTo(x0, 0.01));
      expect(c.canRedo, isTrue);
      c.redo();
      expect(byName(c, 'title').x, closeTo(x0 + 5 * mm, 0.01));
      expect(c.selection, <String>[title.id]);
      c.dispose();
    });

    test('a saved template with a broken variable opens with diagnostics', () {
      final String broken = sampleXml.replaceFirst(
        '<Bands>',
        '<Variables><Var name="itemsSum" value="{{sum(item.qty}}"/></Variables>'
            '<Bands>',
      );
      final ReportDesignerController c = ReportDesignerController.fromXml(
        broken,
      );
      expect(c.template.variables.single.value, '{{sum(item.qty}}');
      expect(
        c.loadDiagnostics
            .where((ReportDiagnostic d) => d.isError)
            .map((ReportDiagnostic d) => d.path),
        <Matcher>[contains('itemsSum')],
      );
      expect(c.toXml(), contains('{{sum(item.qty}}'));
      expect(c.validate().where((ReportDiagnostic d) => d.isError), isNotEmpty);

      c.loadXml(sampleXml);
      expect(
        c.loadDiagnostics.where((ReportDiagnostic d) => d.isError),
        isEmpty,
      );
      c.loadXml(broken);
      expect(c.loadDiagnostics, isNotEmpty);
      c.replaceTemplate(ReportTemplate());
      expect(c.loadDiagnostics, isEmpty);

      expect(
        () => c.loadXml('<QudsReport><Bands></QudsReport>'),
        throwsA(isA<ReportTemplateException>()),
      );
      expect(
        () => ReportDesignerController.fromXml('<Other/>'),
        throwsA(isA<ReportTemplateException>()),
      );
      c.dispose();
    });

    test('problems are live and reveal takes the user to each one', () {
      final String broken = sampleXml
          .replaceFirst(
            '<Bands>',
            '<Variables><Var name="itemsSum" value="{{sum(item.qty}}"/>'
                '</Variables>'
                '<DataSchema><Table name="items">'
                '<Column name="net" expression="qty *"/></Table></DataSchema>'
                '<Bands>',
          )
          .replaceFirst(
            'name="sub" x="100mm" y="12mm" width="40mm" height="8mm">Sub<',
            'name="sub" x="100mm" y="12mm" width="140mm" height="8mm">'
                '{{BOGUS(1)}}<',
          )
          .replaceFirst('</ReportHeader>', '<Foo/></ReportHeader>');
      final ReportDesignerController c = ReportDesignerController.fromXml(
        broken,
      );
      final List<ReportDiagnostic> problems = c.problems;
      expect(problems.first.isError, isTrue);
      expect(
        problems.skipWhile((ReportDiagnostic d) => d.isError),
        everyElement(
          isA<ReportDiagnostic>().having(
            (ReportDiagnostic d) => d.isError,
            'error',
            false,
          ),
        ),
      );
      ReportDiagnostic find(bool Function(ReportDiagnostic d) test) =>
          c.problems.firstWhere(test);

      final ReportDiagnostic edge = find(
        (ReportDiagnostic d) => d.message == 'Extends past the page edge',
      );
      expect(edge.kind, ReportDiagnosticKind.layout);
      final ReportDiagnostic foo = find(
        (ReportDiagnostic d) => d.message.contains('<Foo>'),
      );
      expect(c.isFromFile(foo), isTrue);
      expect(c.isFromFile(edge), isFalse);
      expect(
        problems.where(
          (ReportDiagnostic d) =>
              d.target.place == ReportDiagnosticPlace.variable && d.isError,
        ),
        hasLength(1),
      );

      final ReportElement sub = byName(c, 'sub');
      final int serial = c.revealSerial;
      expect(
        c.revealDiagnostic(
          find((ReportDiagnostic d) => d.message.contains('BOGUS')),
        ),
        isTrue,
      );
      expect(c.selection, <String>[sub.id]);
      expect(c.revealSerial, serial + 1);
      expect(c.revealElement, sub.id);
      expect(c.highlightProperty, 'text');
      expect(c.activeProblem?.message, contains('BOGUS'));

      c.revealDiagnostic(
        find(
          (ReportDiagnostic d) =>
              d.target.place == ReportDiagnosticPlace.variable,
        ),
      );
      expect(c.selection, isEmpty);
      expect(c.inspectorPage, ReportInspectorPage.variables);
      expect(c.selectedVariablePath, 'itemsSum');
      expect(c.highlightProperty, 'var.0.value');
      c.addVariable(
        name: 'rate',
        type: ReportVariableType.number,
        value: '5 percent',
      );
      expect(
        c.problems.where(
          (ReportDiagnostic d) => d.message.contains('is not a number'),
        ),
        hasLength(1),
      );
      c.undo();
      c.setProperty('var.0.value', '{{SUM(items.qty)}}');
      expect(c.highlightProperty, isNull);
      expect(
        c.problems.where(
          (ReportDiagnostic d) =>
              d.target.place == ReportDiagnosticPlace.variable,
        ),
        isEmpty,
      );

      c.revealDiagnostic(
        find(
          (ReportDiagnostic d) =>
              d.target.place == ReportDiagnosticPlace.dataColumn,
        ),
      );
      expect(c.mode, ReportDesignMode.data);
      expect(c.dataTable.name, 'items');
      expect(c.dataTable.columns[c.dataColumn].name, 'net');
      expect(c.highlightProperty, 'data.col.expression');

      c.revealDiagnostic(edge);
      expect(c.mode, ReportDesignMode.design);
      expect(c.selection, <String>[sub.id]);
      c.setProperty('width', '40');
      expect(
        c.problems.any(
          (ReportDiagnostic d) => d.message == 'Extends past the page edge',
        ),
        isFalse,
      );
      c.clearLoadDiagnostics();
      expect(
        c.problems.any((ReportDiagnostic d) => d.message.contains('<Foo>')),
        isFalse,
      );
      c.dispose();
    });

    test('the ready-made templates have no problems', () {
      for (final ReportTemplateInfo t in fileTemplates()) {
        final ReportDesignerController c = ReportDesignerController()
          ..loadTemplate(t);
        expect(c.problems, isEmpty, reason: t.id);
        c.dispose();
      }
    });

    test('align and size tools use the primary element', () {
      final ReportDesignerController c = sample();
      final ReportElement title = byName(c, 'title');
      final ReportElement sub = byName(c, 'sub');
      final ReportElement box = byName(c, 'box');
      c.selectIds(<String>[title.id, sub.id]);
      c.align(ReportAlignAction.left);
      expect(sub.x, closeTo(title.x, 0.01));
      c.align(ReportAlignAction.sameWidth);
      expect(sub.width, closeTo(title.width, 0.01));
      c.align(ReportAlignAction.top);
      expect(sub.y, closeTo(title.y, 0.01));

      c.selectIds(<String>[box.id, title.id, sub.id]);
      title.x = 10 * mm;
      sub.x = 50 * mm;
      box.x = 150 * mm;
      title.width = sub.width = box.width = 20 * mm;
      c.align(ReportAlignAction.distributeX);
      expect(sub.x, closeTo(80 * mm, 0.05));

      c.select(null);
      c.select(box.id);
      c.align(ReportAlignAction.right);
      expect(
        box.x + box.width,
        closeTo(c.template.pageWidth - c.template.margins.right, 0.05),
      );
      c.dispose();
    });

    test('setProperty applies valid values and ignores invalid ones', () {
      final ReportDesignerController c = sample();
      final ReportTextElement title = byName(c, 'title') as ReportTextElement;
      c.select(title.id);
      c.setProperty('width', '50mm');
      expect(title.width, closeTo(50 * mm, 0.01));
      c.setProperty('bold', 'true');
      expect(title.style.bold, isTrue);
      final int revision = c.revision;
      c.setProperty('width', 'not a length');
      expect(c.revision, revision);
      expect(title.width, closeTo(50 * mm, 0.01));
      final List<ReportProperty> props = c.properties;
      expect(props.map((ReportProperty p) => p.key), contains('text'));
      expect(c.inspectorTitle, isNotEmpty);
      c.dispose();
    });

    test('addElement uses default sizes for clicks and undo removes it', () {
      final ReportDesignerController c = sample();
      final int before = c.template.allElements.length;
      final ReportElement? e = c.addElement(
        ReportDesignTool.text,
        ReportBandKind.detail,
        const ReportRect(30 * mm, 0, 0, 0),
      );
      expect(e, isA<ReportTextElement>());
      expect(e!.width, closeTo(40 * mm, 0.01));
      expect(c.selection, <String>[e.id]);
      expect(c.template.allElements.length, before + 1);
      c.undo();
      expect(c.template.allElements.length, before);
      c.dispose();
    });

    test('mirrored RTL templates edit in physical coordinates', () {
      final ReportDesignerController c = sample(rtl: true);
      expect(c.template.mirrored, isTrue);
      final ReportElement title = byName(c, 'title');
      final ReportRect r = c.physicalRect(title);
      expect(
        r.left,
        closeTo(c.template.pageWidth - title.x - title.width, 0.01),
      );
      c.select(title.id);
      c.nudge(10 * mm, 0);
      expect(title.x, closeTo(20 * mm - 10 * mm, 0.01));
      c.beginGesture();
      c.gestureSetRects(<String, ReportRect>{
        title.id: ReportRect(100 * mm, r.top, r.width, r.height),
      });
      c.endGesture();
      expect(
        title.x,
        closeTo(c.template.pageWidth - 100 * mm - title.width, 0.01),
      );
      c.undo();
      expect(byName(c, 'title').x, closeTo(10 * mm, 0.01));
      c.dispose();
    });

    test('copy and paste clone elements with fresh ids', () {
      final ReportDesignerController c = sample();
      final ReportElement title = byName(c, 'title');
      c.select(title.id);
      c.copySelection();
      expect(c.canPaste, isTrue);
      c.paste();
      expect(c.selection, hasLength(1));
      expect(c.selection.single, isNot(title.id));
      expect(c.primary!.name, 'title1');
      expect(c.template.duplicateElementNames, isEmpty);
      c.deleteSelection();
      expect(c.selection, isEmpty);
      c.dispose();
    });

    test('bands can be added and removed', () {
      final ReportDesignerController c = sample();
      expect(c.template.band(ReportBandKind.pageFooter), isNull);
      c.addBand(ReportBandKind.pageFooter);
      expect(c.template.band(ReportBandKind.pageFooter), isNotNull);
      expect(c.selectedBand, ReportBandKind.pageFooter);
      c.removeBand(ReportBandKind.pageFooter);
      expect(c.template.band(ReportBandKind.pageFooter), isNull);
      c.dispose();
    });

    test('XML round-trips and the live preview uses inferred data', () async {
      final ReportDesignerController c = sample();
      final int count = c.template.allElements.length;
      c.loadXml(c.toXml());
      expect(c.template.allElements.length, count);
      expect(c.mockData['customer'], isNotNull);
      expect(c.mockData['items'], isA<List<Object?>>());
      final ReportDocumentLayout? layout = c.previewLayout;
      expect(c.previewError, isNull);
      expect(layout, isNotNull);
      expect(layout!.pages, isNotEmpty);
      final Uint8List pdf = await c.export(ReportExportFormat.pdf);
      expect(String.fromCharCodes(pdf.sublist(0, 5)), '%PDF-');
      c.dispose();
    });

    test('charts are added, edited, previewed, and round-tripped', () {
      final ReportDesignerController c = sample();
      final ReportElement? e = c.addElement(
        ReportDesignTool.chart,
        ReportBandKind.reportSummary,
        const ReportRect(20 * mm, 0, 0, 0),
      );
      expect(e, isA<ReportChartElement>());
      final ReportChartElement chart = e! as ReportChartElement;
      expect(chart.width, closeTo(90 * mm, 0.01));
      expect(chart.series, hasLength(1));
      expect(
        c.properties.map((ReportProperty p) => p.key),
        containsAll(<String>['chartType', 'category', 'series.0.value']),
      );

      c.setProperty('dataSet', 'Data.items');
      c.setProperty('category', 'Row.name');
      c.setProperty('series.0.value', 'Row.qty');
      c.setProperty('seriesCount', '2');
      expect(chart.series, hasLength(2));
      c.setProperty('series.1.color', '#FF0000');
      expect(chart.series[1].color, '#FF0000');
      c.setProperty('chartType', 'nonsense');
      expect(chart.chartType, ReportChartType.bar);
      c.setProperty('chartType', 'donut');
      expect(chart.chartType, ReportChartType.donut);
      c.setProperty('limit', '3');
      expect(chart.limit, 3);

      final ReportDocumentLayout? layout = c.previewLayout;
      expect(c.previewError, isNull);
      final List<ReportPrimitive> prims = <ReportPrimitive>[
        for (final ReportPageLayout page in layout!.pages)
          for (final ReportPrimitive p in page.primitives)
            if (p.elementId == chart.id) p,
      ];
      expect(prims.whereType<ReportPathPrimitive>(), isNotEmpty);

      c.setProperty('seriesCount', '0');
      expect(chart.series, isEmpty);
      expect(chart.points, hasLength(3));
      c.setProperty('pointCount', '5');
      c.setProperty('point.4.value', '75');
      expect(chart.points[4].value, '75');

      c.loadXml(c.toXml());
      final ReportChartElement back = c.template.allElements
          .map(((ReportBand, ReportElement) p) => p.$2)
          .whereType<ReportChartElement>()
          .single;
      expect(back.chartType, ReportChartType.donut);
      expect(back.points, hasLength(5));
      expect(back.points[4].value, '75');
      c.dispose();
    });

    test('a shape map embeds its file and binds the value table', () async {
      final ReportDesignerController c = ReportDesignerController();
      c.loadXml(
        '<QudsReport name="Map" pageSize="A4"><Bands>'
        '<ReportHeader height="90mm"/></Bands></QudsReport>',
      );
      expect(c.addDataTable('regions'), isTrue);
      expect(
        c.addDataColumn(
          name: 'code',
          type: ReportDataType.text,
          table: 'regions',
        ),
        'code',
      );
      expect(
        c.addDataColumn(
          name: 'amount',
          type: ReportDataType.number,
          table: 'regions',
        ),
        'amount',
      );
      expect(c.addDataRow(table: 'regions'), isTrue);
      expect(c.addDataRow(table: 'regions'), isTrue);
      expect(c.setDataCell(0, 0, 'W', table: 'regions'), isTrue);
      expect(c.setDataCell(0, 1, '5', table: 'regions'), isTrue);
      expect(c.setDataCell(1, 0, 'E', table: 'regions'), isTrue);
      expect(c.setDataCell(1, 1, '50', table: 'regions'), isTrue);

      final ReportElement? added = c.addElement(
        ReportDesignTool.chart,
        ReportBandKind.reportHeader,
        const ReportRect(10 * mm, 0, 0, 0),
      );
      final ReportChartElement chart = added! as ReportChartElement;
      c.setProperty('dataSet', 'Data.regions');
      c.setProperty('chartType', 'shapeMap');
      expect(chart.shape, 'world');
      expect(chart.category, 'Row.code');
      expect(chart.series.single.value, 'Row.amount');

      c.shapePicker = () async => (
        name: 'districts.geojson',
        bytes: Uint8List.fromList(
          utf8.encode('''
{"type":"FeatureCollection","features":[
  {"type":"Feature","properties":{"code":"W","NAME":"West"},
   "geometry":{"type":"Polygon","coordinates":[[[0,0],[30,0],[30,20],[0,0]]]}},
  {"type":"Feature","properties":{"code":"E","NAME":"East"},
   "geometry":{"type":"Polygon","coordinates":[[[40,0],[70,0],[70,25],[40,0]]]}}
]}'''),
        ),
        attributes: null,
      );
      expect(await c.importShape(), 'districts');
      expect(chart.shape, 'districts');
      expect(chart.shapeKey, 'code');
      expect(chart.category, 'Row.code');
      expect(chart.series.single.value, 'Row.amount');
      expect(c.shapes.containsKey('districts'), isTrue);

      final ReportDesignerController back = ReportDesignerController();
      back.loadPackage(c.toPackage());
      final ReportChartElement loaded = back.template.allElements
          .map(((ReportBand, ReportElement) p) => p.$2)
          .whereType<ReportChartElement>()
          .single;
      expect(loaded.shape, 'districts');
      expect(loaded.shapeKey, 'code');
      expect(loaded.category, 'Row.code');
      expect(loaded.series.single.value, 'Row.amount');
      expect(
        ReportShapeLayer.decode(back.shapes['districts']!).find('W')?.label,
        'West',
      );

      final ReportDocumentLayout? layout = back.previewLayout;
      expect(back.previewError, isNull);
      final Set<int> fills = <int>{
        for (final ReportPathPrimitive p
            in layout!.pages.first.primitives.whereType<ReportPathPrimitive>())
          if (p.elementId == loaded.id &&
              p.fill != null &&
              p.fill!.argb != 0xFFE7F1F8)
            p.fill!.argb,
      };
      expect(fills, containsAll(<int>[0xFFDEEBF7, 0xFF08306B]));
      c.dispose();
      back.dispose();
    });

    test('a map is its own tool and its file can be removed', () async {
      final ReportDesignerController c = ReportDesignerController();
      c.loadXml(
        '<QudsReport name="Map" pageSize="A4"><Bands>'
        '<ReportHeader height="90mm"/></Bands></QudsReport>',
      );
      expect(c.addDataTable('regions'), isTrue);
      expect(
        c.addDataColumn(
          name: 'code',
          type: ReportDataType.text,
          table: 'regions',
        ),
        'code',
      );
      expect(
        c.addDataColumn(
          name: 'color',
          type: ReportDataType.text,
          table: 'regions',
        ),
        'color',
      );
      final ReportElement? chart = c.addElement(
        ReportDesignTool.chart,
        ReportBandKind.reportHeader,
        const ReportRect(10 * mm, 0, 0, 0),
      );
      expect(
        c.properties
            .firstWhere((ReportProperty p) => p.key == 'chartType')
            .options,
        isNot(contains('shapeMap')),
      );
      final ReportElement? added = c.addElement(
        ReportDesignTool.map,
        ReportBandKind.reportHeader,
        const ReportRect(20 * mm, 0, 0, 0),
      );
      final ReportChartElement map = added! as ReportChartElement;
      expect(map.chartType, ReportChartType.shapeMap);
      expect(chart, isA<ReportChartElement>());
      final Iterable<String> keys = c.properties.map(
        (ReportProperty p) => p.key,
      );
      expect(keys, isNot(contains('chartType')));
      expect(keys, contains('regionColor'));
      c.setProperty('dataSet', 'Data.regions');
      expect(map.category, 'Row.code');
      expect(map.regionColor, 'Row.color');
      ReportProperty field(String key) =>
          c.properties.firstWhere((ReportProperty p) => p.key == key);
      expect(field('dataSet').kind, ReportPropertyKind.choice);
      expect(field('dataSet').options, contains('Data.regions'));
      expect(field('category').kind, ReportPropertyKind.choice);
      expect(field('category').options, contains('Row.code'));
      expect(field('regionColor').options, contains(''));
      expect(field('regionColor').options, contains('Row.color'));
      expect(field('title.fontFamily').nest, 'title');
      expect(field('labels.fontSize').nest, 'labels');
      expect(field('legend.color').nest, 'legend');
      c.toggleFormatBox('title');
      expect(c.formatBox, 'title');
      c.setProperty('title.fontFamily', 'Liberation Serif');
      c.setProperty('title.fontSize', '18');
      c.setProperty('title.bold', 'true');
      c.setProperty('title.color', '#112233');
      c.setProperty('labels.fontSize', '11');
      c.setProperty('labels.italic', 'true');
      c.setProperty('legend.fontSize', '8');
      c.setProperty('legend.color', '#445566');
      expect(map.titleStyle.fontFamily, 'Liberation Serif');
      expect(map.titleStyle.fontSize, 18);
      expect(map.titleStyle.bold, isTrue);
      expect(map.titleStyle.color, '#112233');
      expect(map.labelStyle.fontSize, 11);
      expect(map.labelStyle.italic, isTrue);
      expect(map.legendStyle.fontSize, 8);
      expect(map.legendStyle.color, '#445566');
      c.toggleFormatBox('title');
      expect(c.formatBox, isNull);

      c.shapePicker = () async => (
        name: 'districts.geojson',
        bytes: Uint8List.fromList(
          utf8.encode(
            '{"type":"FeatureCollection","features":[{"type":"Feature",'
            '"properties":{"code":"W","title":"Ramallah"},"geometry":{"type":"Polygon",'
            '"coordinates":[[[35.2,31.5],[35.3,31.5],[35.3,31.6],[35.2,31.5]]]}}]}',
          ),
        ),
        attributes: null,
      );
      expect(await c.importShape(), 'districts');
      expect(c.shapes.containsKey('districts'), isTrue);
      expect(field('shapeKey').kind, ReportPropertyKind.choice);
      expect(field('shapeKey').options, containsAll(<String>['code', 'title']));
      expect(map.labelField, 'title');
      expect(field('labelField').kind, ReportPropertyKind.expression);
      expect(
        field('labelField').presets,
        containsAll(<String>['code', 'title']),
      );
      expect(field('labelField').presets, isNot(contains('{{item.code}}')));
      expect(field('labelField').presets, isNot(contains('color')));
      expect(c.addDataColumn(expression: 'code'), 'calc1');
      expect(c.addConstantColumn(value: 'حي'), 'constant1');
      c.cancelPropertyEdit();
      expect(
        field('labelField').presets,
        containsAll(<String>['calc1', 'constant1']),
      );
      c.beginPropertyEdit('labelField');
      c.propertyEditor.replaceRange(
        0,
        c.propertyEditor.formulaBar.length,
        'CONCAT(',
      );
      final ReportCompletionResult? suggestions = c.completion;
      expect(suggestions, isNotNull);
      final List<String> inserts = <String>[
        for (final ReportCompletionItem i in suggestions!.items) i.insert,
      ];
      expect(inserts, containsAll(<String>['code', 'title', 'Row']));
      expect(inserts, isNot(contains('item')));
      expect(inserts.indexOf('code'), lessThan(inserts.indexOf('Data')));
      c.cancelPropertyEdit();
      c.setProperty('labelField', '{{CONCAT(Row.title, "\\n", Row.code)}}');
      expect(map.labelField, '{{CONCAT(Row.title, "\\n", Row.code)}}');
      c.setProperty('labelField', 'title');
      c.setProperty('showLabels', 'false');
      expect(
        c.properties.map((ReportProperty p) => p.key),
        isNot(contains('labelField')),
      );
      c.setProperty('showLabels', 'true');
      expect(
        c.properties.map((ReportProperty p) => p.key),
        contains('shape.remove'),
      );
      c.setProperty('shape.remove', 'Remove map file');
      expect(c.shapes.containsKey('districts'), isFalse);
      expect(map.shape, 'world');
      c.undo();
      expect(c.shapes.containsKey('districts'), isTrue);
      final ReportChartElement restored = c.template.allElements
          .map(((ReportBand, ReportElement) pair) => pair.$2)
          .whereType<ReportChartElement>()
          .firstWhere((ReportChartElement e) => e.chartType.isShapeMap);
      expect(restored.shape, 'districts');
      c.dispose();
    });

    test('a map file opens as a data table', () async {
      final ReportDesignerController c = ReportDesignerController();
      c.loadXml(
        '<QudsReport name="Map" pageSize="A4"><Bands>'
        '<ReportHeader height="90mm"/></Bands></QudsReport>',
      );
      c.addElement(
        ReportDesignTool.map,
        ReportBandKind.reportHeader,
        const ReportRect(12 * mm, 0, 0, 0),
      );
      c.shapePicker = () async => (
        name: 'districts.geojson',
        bytes: Uint8List.fromList(
          utf8.encode(
            '{"type":"FeatureCollection","features":[{"type":"Feature",'
            '"properties":{"code":"W","title":"Ramallah","area":12},'
            '"geometry":{"type":"Polygon","coordinates":[[[35.2,31.5],'
            '[35.3,31.5],[35.3,31.6],[35.2,31.5]]]}}]}',
          ),
        ),
        attributes: null,
      );
      expect(await c.importShape(), 'districts');
      final ReportChartElement map = c.template.allElements
          .map(((ReportBand, ReportElement) pair) => pair.$2)
          .whereType<ReportChartElement>()
          .first;
      expect(map.dataSet, 'Data.districts');
      final ReportDataTableView table = c.dataTables.firstWhere(
        (ReportDataTableView t) => t.name == 'districts',
      );
      expect(table.description, 'Attributes of the map file');
      expect(
        table.columns.map((ReportDataColumnView c) => c.name),
        containsAll(<String>['code', 'title', 'area']),
      );
      final int title = table.columns.indexWhere(
        (ReportDataColumnView c) => c.name == 'title',
      );
      expect(table.rows.single[title].displayText, 'Ramallah');
      c.selectDataTable('districts');
      expect(c.setDataCell(0, title, 'بيتونيا'), isTrue);
      expect(
        ReportShapeLayer.decode(
          c.shapes['districts']!,
        ).features.single.valueOf('title'),
        'بيتونيا',
      );
      expect(c.addDataRow(), isFalse);
      expect(c.removeDataTable('districts'), isFalse);
      expect(
        c.addDataColumn(expression: 'code & "-" & title', table: 'districts'),
        'calc1',
      );
      final ReportDataTableView calculated = c.dataTables.firstWhere(
        (ReportDataTableView t) => t.name == 'districts',
      );
      final int calc = calculated.columns.indexWhere(
        (ReportDataColumnView c) => c.name == 'calc1',
      );
      expect(calculated.rows.single[calc].displayText, 'W-بيتونيا');
      expect(
        c.addConstantColumn(name: 'kind', value: 'حي', table: 'districts'),
        'kind',
      );
      final ReportDataTableView filled = c.dataTables.firstWhere(
        (ReportDataTableView t) => t.name == 'districts',
      );
      final int kind = filled.columns.indexWhere(
        (ReportDataColumnView c) => c.name == 'kind',
      );
      expect(filled.rows.single[kind].displayText, 'حي');
      c.undo();
      c.undo();
      c.undo();
      expect(
        ReportShapeLayer.decode(
          c.shapes['districts']!,
        ).features.single.valueOf('title'),
        'Ramallah',
      );
      c.dispose();
    });

    test('page fields, a total, a rounded box, and a signature insert', () {
      final ReportDesignerController c = ReportDesignerController();
      c.loadXml(
        '<QudsReport name="Invoice" pageSize="A4"><Bands>'
        '<ReportHeader height="80mm"/></Bands></QudsReport>',
      );
      ReportElement? placed(ReportDesignTool tool) => c.addElement(
        tool,
        ReportBandKind.reportHeader,
        const ReportRect(12 * mm, 4, 0, 0),
      );
      expect(
        (placed(ReportDesignTool.pageNumber)! as ReportTextElement).text,
        '{{System.PageNumber}}',
      );
      expect(
        (placed(ReportDesignTool.pages)! as ReportTextElement).text,
        '{{System.PageNumber}} / {{System.TotalPages}}',
      );
      expect(
        (placed(ReportDesignTool.date)! as ReportTextElement).text,
        '{{System.CurrentDate}}',
      );
      expect(
        (placed(ReportDesignTool.total)! as ReportTextElement).text,
        '{{SUM(Row.total)}}',
      );
      expect(
        (placed(ReportDesignTool.rounded)! as ReportShapeElement).kind,
        ReportShapeKind.roundedRectangle,
      );
      expect(placed(ReportDesignTool.signature), isA<ReportShapeElement>());
      expect(
        c.template.allElements
            .map(((ReportBand, ReportElement) pair) => pair.$2)
            .whereType<ReportTextElement>()
            .map((ReportTextElement e) => e.text),
        contains('Signature'),
      );
      c.dispose();
    });

    test('ready-made templates load with their sample data', () {
      for (final ReportTemplateInfo info in fileTemplates()) {
        final ReportDesignerController c = ReportDesignerController(
          clock: () => DateTime(2026, 10, 10, 9, 30),
        );
        c.loadTemplate(info);
        expect(c.hasHostData, isFalse, reason: info.id);
        expect(c.hasSampleData, isTrue, reason: info.id);
        expect(c.template.duplicateElementNames, isEmpty, reason: info.id);
        expect(c.template.isRtl, info.rtl, reason: info.id);
        expect(c.images.keys.toSet(), info.images().keys.toSet());
        final ReportDocumentLayout? layout = c.previewLayout;
        expect(c.previewError, isNull, reason: info.id);
        expect(layout!.pages, isNotEmpty, reason: info.id);
        c.dispose();
      }
    });

    test('template files match the built-in catalog they replace', () {
      final List<ReportTemplateInfo> files = fileTemplates();
      // ignore: deprecated_member_use
      final List<ReportTemplateInfo> catalog = ReportTemplates.all;
      expect(
        files.map((ReportTemplateInfo t) => t.id),
        catalog.map((ReportTemplateInfo t) => t.id),
      );
      for (int i = 0; i < files.length; i++) {
        final ReportTemplateInfo f = files[i];
        final ReportTemplateInfo c = catalog[i];
        expect(f.xml, c.xml, reason: f.id);
        expect(f.family, c.family, reason: f.id);
        expect(f.familyTitleAr, c.familyTitleAr, reason: f.id);
        expect(f.descriptionAr, c.descriptionAr, reason: f.id);
        expect(f.category, c.category, reason: f.id);
        expect(f.language, c.language, reason: f.id);
        expect(f.images().keys.toSet(), c.images().keys.toSet());
        for (final MapEntry<String, Uint8List> image in c.images().entries) {
          expect(f.images()[image.key], image.value, reason: f.id);
        }
        expect(f.package().template!.id, f.id);
      }
    });

    test('the library reads templates from an asset bundle', () async {
      final List<ReportTemplateInfo> all = await ReportTemplateLibrary.bundled(
        bundle: _DirectoryBundle('templates', ReportTemplateLibrary.folder),
      );
      expect(all, hasLength(22));
      expect(all.first.id, 'feature_showcase_ar');
      expect(all.last.category, ReportTemplateCategory.hr);
      expect(
        () => ReportTemplateInfo.fromPackage(ReportPackage(xml: sampleXml)),
        throwsA(isA<ReportPackageException>()),
      );
    });

    test('calculated columns complete with their computed values', () {
      final ReportDesignerController c = ReportDesignerController.fromXml(
        sampleXml.replaceFirst(
          '<Bands>',
          '<DataSchema><Table name="items"><Column name="qty" type="number"/>'
              '<Column name="calc1" type="number" expression="qty * 2"/>'
              '</Table></DataSchema><Bands>',
        ),
      );
      final ReportTextElement line = byName(c, 'line') as ReportTextElement;
      c.beginTextEdit(line.id);
      final InlineCellEditor ed = c.textEditor;
      ed.replaceRange(0, ed.formulaBar.length, '{{item.ca');
      final ReportCompletionItem first = c.completion!.items.first;
      expect(first.insert, 'calc1');
      final List<Object?> rows = c.mockData['items']! as List<Object?>;
      final num qty = (rows.first! as Map<String, Object?>)['qty']! as num;
      expect(
        first.detail,
        ReportUnits.trimNumber(qty.toDouble() * 2, decimals: 3),
      );
      c.cancelTextEdit();

      c.addVariable(type: ReportVariableType.expression, value: '0');
      c.inspectorPage = ReportInspectorPage.variables;
      c.beginPropertyEdit('var.0.value');
      c.propertyEditor.replaceRange(
        0,
        c.propertyEditor.formulaBar.length,
        'SUM(items.ca',
      );
      expect(c.completion!.items.first.insert, 'calc1');
      c.cancelPropertyEdit();
      c.dispose();
    });

    test('bindings complete from data, functions, and formats', () {
      final ReportDesignerController c = sample();
      final ReportTextElement title = byName(c, 'title') as ReportTextElement;
      c.beginTextEdit(title.id);
      final InlineCellEditor ed = c.textEditor;
      void type(String text) => ed.replaceRange(0, ed.formulaBar.length, text);

      type('Hi {{');
      expect(
        c.completion!.items.map((ReportCompletionItem i) => i.insert),
        containsAll(<String>['item', 'Data', 'SUM()']),
      );
      type('Hi {{Data.cu');
      expect(c.completion!.items.first.insert, 'customer');
      expect(c.acceptCompletion(), isTrue);
      expect(ed.formulaBar, 'Hi {{Data.customer');
      expect(c.completion, isNull);

      type('{{SU');
      c.acceptCompletion();
      expect(ed.formulaBar, '{{SUM()');
      expect(ed.caretIndex, 6);
      expect(c.completion, isNotNull);

      type('{{item.price | n');
      expect(c.completion!.items.first.insert, 'n0');
      c.moveCompletion(1);
      expect(c.completionIndex, 1);
      c.dismissCompletion();
      expect(c.completion, isNull);
      ed.replaceRange(ed.formulaBar.length, ed.formulaBar.length, '2');
      expect(c.completion, isNull);
      c.triggerCompletion();
      expect(c.completion, isNotNull);
      c.cancelTextEdit();
      expect(c.completion, isNull);

      c.select(title.id);
      c.beginPropertyEdit('visibleWhen');
      c.propertyEditor.replaceRange(
        0,
        c.propertyEditor.formulaBar.length,
        'item.',
      );
      expect(
        c.completion!.items.map((ReportCompletionItem i) => i.insert),
        containsAll(<String>['name', 'qty']),
      );
      c.cancelPropertyEdit();
      c.dispose();
    });

    test('template variables are typed, renamed, inserted, and previewed', () {
      final ReportDesignerController c = sample();
      c.select(null);
      final ReportVariable v = c.addVariable();
      expect(v.name, 'variable1');
      expect(
        c.properties.map((ReportProperty p) => p.key),
        isNot(contains('var.0.name')),
        reason: 'variables have their own inspector page',
      );
      c.inspectorPage = ReportInspectorPage.variables;
      expect(c.inspectorTitle, 'Variables');
      expect(
        c.properties.map((ReportProperty p) => p.key),
        containsAll(<String>[
          'var+',
          'var.0.name',
          'var.0.type',
          'var.0.value',
        ]),
      );
      c.setProperty('var.0.type', 'number');
      expect(v.type, ReportVariableType.number);

      c.select(byName(c, 'title').id);
      expect(c.inspectorPage, ReportInspectorPage.properties);
      c.inspectorPage = ReportInspectorPage.variables;
      c.setProperty('var.0.value', '42');
      expect(v.value, '42', reason: 'variable edits ignore the selection');
      expect(c.inspectorPage, ReportInspectorPage.variables);
      c.select(null);
      expect(
        c.inspectorPage,
        ReportInspectorPage.variables,
        reason: 'clearing the selection keeps the page',
      );
      c.setProperty('var.0.value', '0');
      expect(v.value, '0');
      c.setProperty('var.0.value', 'abc');
      expect(v.value, '0');
      c.setProperty('var.0.value', '1250.5');
      expect(v.value, '1250.5');
      c.setProperty('var.0.format', 'n2');
      expect(v.placeholder, '{{Variables.variable1 | n2}}');

      final ReportTextElement title = byName(c, 'title') as ReportTextElement;
      c.select(title.id);
      final ReportElement? box = c.insertVariable('variable1');
      expect(box, isA<ReportTextElement>());
      expect((box! as ReportTextElement).text, '{{Variables.variable1 | n2}}');
      expect(
        c.template.findElement(box.id)!.$1.kind,
        ReportBandKind.reportHeader,
      );

      c.beginTextEdit(title.id);
      c.textEditor.setCaret(0);
      c.insertVariable('variable1');
      expect(
        c.textEditor.formulaBar,
        startsWith('{{Variables.variable1 | n2}}Hello'),
      );
      c.commitTextEdit();

      c.select(null);
      c.setProperty('var.0.name', 'bad name');
      expect(c.template.variables.single.name, 'variable1');
      c.setProperty('var.0.name', 'amount');
      expect(c.template.variables.single.name, 'amount');
      final List<String> texts = <String>[
        for (final (ReportBand, ReportElement) be in c.template.allElements)
          if (be.$2 case final ReportTextElement t) t.text,
      ];
      expect(
        texts.where((String t) => t.contains('Variables.amount')),
        hasLength(2),
      );
      expect(texts.where((String t) => t.contains('variable1')), isEmpty);

      final List<String> preview = <String>[
        for (final ReportPageLayout page in c.previewLayout!.pages)
          for (final ReportPrimitive p in page.primitives)
            if (p case final ReportTextPrimitive t) t.text,
      ];
      expect(preview, contains('1,250.50'));

      c.undo();
      expect(c.template.variables.single.name, 'variable1');
      c.select(null);
      c.addVariable(type: ReportVariableType.boolean);
      c.setProperty('var.1.value', 'true');
      expect(c.template.variables[1].value, 'true');
      c.setProperty('var.1.remove', 'Remove');
      expect(c.template.variables, hasLength(1));
      expect(c.toXml(), contains('type="number"'));
      c.dispose();
    });

    test('inspector metadata drives steppers, presets, and pairs', () {
      final ReportDesignerController c = sample();
      final ReportTextElement title = byName(c, 'title') as ReportTextElement;
      c.select(title.id);
      ReportProperty prop(String key) =>
          c.properties.firstWhere((ReportProperty p) => p.key == key);

      expect(prop('x').pair && prop('y').pair, isTrue);
      expect(prop('width').pair && prop('height').pair, isTrue);
      expect(prop('bold').glyph, 'bold');
      expect(prop('italic').glyph, 'italic');
      expect(prop('format').presets, contains('n2'));
      expect(prop('fontFamily').presets, contains('Noto Naskh Arabic'));
      expect(prop('fontSize').presets, contains('12'));
      expect(prop('color').hint, 'none');
      expect(prop('x').isSteppable, isTrue);

      final String x = prop('x').value;
      expect(c.stepProperty('x', 1), isTrue);
      expect(
        ReportUnits.tryParse(prop('x').value, defaultUnit: c.template.unit),
        closeTo(
          ReportUnits.tryParse(x, defaultUnit: c.template.unit)! +
              c.template.unit.points,
          0.01,
        ),
      );
      expect(prop('x').value, endsWith(c.template.unit.suffix));

      c.setProperty('fontSize', '');
      expect(c.stepProperty('fontSize', 1), isTrue);
      expect(
        double.parse(prop('fontSize').value),
        c.template.defaultFontSize + 1,
      );
      expect(c.stepProperty('fontSize', 1, large: true), isTrue);
      expect(
        double.parse(prop('fontSize').value),
        c.template.defaultFontSize + 11,
      );

      c.setProperty('borderWidth', '0');
      expect(c.stepProperty('borderWidth', -1), isFalse);
      expect(c.stepProperty('borderWidth', 1), isTrue);
      expect(prop('borderWidth').value, '0.25');
      expect(c.steppedValue(prop('x'), 1, from: '10.5mm'), endsWith('mm'));

      c.select(null);
      c.addVariable();
      c.inspectorPage = ReportInspectorPage.variables;
      expect(prop('var.0.insert').pair && prop('var.0.remove').pair, isTrue);
      c.dispose();
    });

    test('property editing commits through the inline editor', () {
      final ReportDesignerController c = sample();
      final ReportTextElement title = byName(c, 'title') as ReportTextElement;
      c.select(title.id);
      c.beginPropertyEdit('text');
      expect(c.editingProperty, 'text');
      c.propertyEditor.replaceRange(
        0,
        c.propertyEditor.formulaBar.length,
        'Changed',
      );
      c.commitPropertyEdit();
      expect(c.editingProperty, isNull);
      expect(title.text, 'Changed');
      c.beginTextEdit(title.id);
      c.textEditor.replaceRange(0, 0, 'X');
      c.cancelTextEdit();
      expect(title.text, 'Changed');
      c.dispose();
    });
  });

  group('QudsReportDesigner', () {
    Future<ReportDesignerController> pumpDesigner(
      WidgetTester tester, {
      ReportDesignerController? controller,
      ReportDeviceFonts? deviceFonts,
    }) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final ReportDesignerController c = controller ?? sample();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: QudsReportDesigner(
            controller: c,
            loadBundledFonts: false,
            templates: const <ReportTemplateInfo>[],
            onExport: (ReportExportFormat f, Uint8List bytes) {},
            deviceFonts: deviceFonts,
          ),
        ),
      );
      await tester.pump();
      return c;
    }

    Offset elementCenter(
      WidgetTester tester,
      ReportDesignerController c,
      ReportElement e,
    ) {
      final Rect canvas = tester.getRect(find.byType(ReportDesignerCanvas));
      final ReportDesignLayout layout = ReportDesignLayout.of(c.template);
      final (ReportDesignSlot, ReportElement) f = layout.find(e.id)!;
      final Rect r = layout.elementRect(f.$1, f.$2);
      final double s = c.zoom;
      final double docW = layout.width * s;
      final double avail = canvas.width - RenderReportDesigner.ruler;
      final double ox = docW + 2 * RenderReportDesigner.pad < avail
          ? RenderReportDesigner.ruler + (avail - docW) / 2
          : RenderReportDesigner.ruler + RenderReportDesigner.pad;
      const double oy = RenderReportDesigner.ruler + RenderReportDesigner.pad;
      return canvas.topLeft + Offset(ox, oy) + r.center * s;
    }

    testWidgets('inspector paints sections and the color palette', (
      WidgetTester tester,
    ) async {
      final ReportDesignerController c = sample();
      await pumpDesigner(tester, controller: c);
      c.select((byName(c, 'title') as ReportTextElement).id);
      await tester.pump();
      final RenderReportInspector inspector = tester.renderObject(
        find.byType(ReportInspector),
      );
      inspector.openPalette('color');
      await tester.pump();
      expect(inspector.paletteKey, 'color');
      inspector.setCollapsed('Font', true);
      await tester.pump();
      expect(inspector.isCollapsed('Font'), isTrue);
      inspector.openPalette(null);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('inspector tabs switch pages and the splitter resizes it', (
      WidgetTester tester,
    ) async {
      final FakeDeviceFonts device = FakeDeviceFonts(<String, ReportFontFiles>{
        'Liberation Serif': ReportFontFiles(
          regular: fontFile('LiberationSerif-Regular.ttf'),
        ),
      });
      final ReportDesignerController c = await pumpDesigner(
        tester,
        deviceFonts: device,
      );
      expect(c.deviceFonts, same(device));
      c.addVariable();
      await tester.pump();
      final Finder inspector = find.byType(ReportInspector);
      Offset tab(int i) {
        final Offset o = tester.getTopLeft(inspector);
        final double w =
            (tester.getSize(inspector).width - 24) /
            ReportInspectorPage.values.length;
        return o +
            Offset(
              12 + w * (i + 0.5),
              RenderReportInspector.titleHeight +
                  RenderReportInspector.tabsHeight / 2,
            );
      }

      await tester.tapAt(tab(1));
      await tester.pump();
      expect(c.inspectorPage, ReportInspectorPage.variables);
      await tester.tapAt(tab(2));
      await tester.pump();
      expect(c.inspectorPage, ReportInspectorPage.images);
      await tester.tapAt(tab(3));
      await tester.pump();
      expect(c.inspectorPage, ReportInspectorPage.fonts);
      await tester.runAsync(settle);
      await tester.pump();
      expect(device.listed, 1);
      c.beginPropertyEdit('font.add');
      await tester.pump();
      expect(
        c.completion!.items.map((ReportCompletionItem i) => i.label),
        contains('Liberation Serif'),
      );
      c.cancelPropertyEdit();
      await tester.tapAt(tab(0));
      await tester.pump();
      expect(c.inspectorPage, ReportInspectorPage.properties);

      expect(tester.getSize(inspector).width, 300);
      final Offset edge =
          tester.getTopLeft(inspector) +
          Offset(-3, tester.getSize(inspector).height / 2);
      await tester.dragFrom(edge, const Offset(-120, 0));
      await tester.pump();
      expect(tester.getSize(inspector).width, closeTo(420, 1));
      await tester.dragFrom(
        tester.getTopLeft(inspector) + const Offset(-3, 200),
        const Offset(400, 0),
      );
      await tester.pump();
      expect(tester.getSize(inspector).width, 240, reason: 'minimum width');
      await tester.tapAt(tab(3));
      await tester.pump();
      expect(c.inspectorPage, ReportInspectorPage.fonts, reason: 'icon tabs');
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    });

    testWidgets('variables explorer, cards, font picker, and Arabic layout', (
      WidgetTester tester,
    ) async {
      final FakeDeviceFonts device = FakeDeviceFonts(<String, ReportFontFiles>{
        'Liberation Mono': ReportFontFiles(
          regular: fontFile('LiberationMono-Regular.ttf'),
        ),
      });
      final ReportDesignerController c = await pumpDesigner(
        tester,
        deviceFonts: device,
      );
      c
        ..addVariable(name: 'stats.sum', value: '1')
        ..addVariable(name: 'stats.avg', value: '2')
        ..addVariable(name: 'company', value: 'Quds');
      c.inspectorPage = ReportInspectorPage.variables;
      await tester.pump();
      final Finder inspector = find.byType(ReportInspector);
      final RenderReportInspector ro = tester.renderObject(inspector);
      Offset node(int i) =>
          tester.getTopLeft(inspector) +
          Offset(
            tester.getSize(inspector).width / 2,
            RenderReportInspector.titleHeight +
                RenderReportInspector.tabsHeight +
                6 +
                RenderReportInspector.groupHeight +
                4 +
                28 * (i + 0.5),
          );

      await tester.tapAt(node(3));
      await tester.pump();
      expect(c.selectedVariablePath, 'company', reason: 'folders list first');
      await tester.tapAt(node(0));
      await tester.pump();
      expect(c.selectedVariablePath, 'stats');
      expect(
        c.properties.map((ReportProperty p) => p.key),
        containsAll(<String>['vfolder.name', 'vfolder.add', 'vfolder.remove']),
      );
      ro.setFolderClosed('stats', true);
      await tester.pump();
      await tester.tapAt(node(1));
      await tester.pump();
      expect(c.selectedVariablePath, 'company', reason: 'stats is collapsed');

      c.strings = ReportDesignerStrings.arabic;
      await tester.pump();
      expect(c.strings.isRtl, isTrue);
      await tester.tapAt(node(0));
      await tester.pump();
      expect(c.selectedVariablePath, 'stats', reason: 'rows keep their order');

      c.addImage(
        'logo.png',
        PngBytes.rgb(width: 8, height: 4, plot: (int x, int y, List<int> p) {}),
      );
      final Uint8List red = PngBytes.rgb(
        width: 6,
        height: 6,
        plot: (int x, int y, List<int> p) => p[0] = 255,
      );
      c.imagePicker = () async => (name: 'red.png', bytes: red);
      c.inspectorPage = ReportInspectorPage.images;
      await tester.pump();
      final Offset thumb =
          tester.getTopLeft(inspector) +
          Offset(
            tester.getSize(inspector).width - 54,
            RenderReportInspector.titleHeight +
                RenderReportInspector.tabsHeight +
                6 +
                RenderReportInspector.groupHeight +
                2 +
                4 +
                8 +
                34,
          );
      await tester.tapAt(thumb);
      await tester.pump();
      expect(c.images['logo'], same(red), reason: 'the thumbnail replaces');
      expect(c.imageNames, <String>['logo']);
      c.undo();
      expect(c.images['logo'], isNot(same(red)));
      c.inspectorPage = ReportInspectorPage.fonts;
      await tester.runAsync(settle);
      await tester.pump();
      c.beginPropertyEdit('font.add');
      await tester.pump();
      expect(c.completion!.items.single.label, 'Liberation Mono');
      expect(c.acceptCompletion(), isTrue);
      await tester.runAsync(settle);
      await tester.pump();
      expect(c.embeddedFamilies, <String>['Liberation Mono']);
      expect(c.fontPreviewText('Liberation Mono'), isNotEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tap selects and drag moves an element as one undo step', (
      WidgetTester tester,
    ) async {
      final ReportDesignerController c = await pumpDesigner(tester);
      final ReportElement sub = byName(c, 'sub');
      final double x0 = sub.x;
      final Offset at = elementCenter(tester, c, sub);

      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 500));
      expect(c.selection, <String>[sub.id]);

      // Away from the tap so the press is not read as a double-click.
      final TestGesture g = await tester.startGesture(
        at + const Offset(10, 0),
        kind: PointerDeviceKind.mouse,
      );
      await g.moveBy(const Offset(20, 0));
      await g.moveBy(const Offset(40, 0));
      await g.up();
      await tester.pump();
      expect(sub.x, greaterThan(x0 + 50));
      expect(sub.x, lessThan(x0 + 70));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(byName(c, 'sub').x, closeTo(x0, 0.01));
    });

    testWidgets('keyboard nudges and deletes the selection', (
      WidgetTester tester,
    ) async {
      final ReportDesignerController c = await pumpDesigner(tester);
      final ReportElement box = byName(c, 'box');
      await tester.tapAt(elementCenter(tester, c, box));
      await tester.pump(const Duration(milliseconds: 500));
      final double x0 = box.x;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(box.x, closeTo(x0 + c.gridSize, 0.02));
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(c.template.findElement(box.id), isNull);
    });

    testWidgets('toolbar switches tools and the preview', (
      WidgetTester tester,
    ) async {
      final ReportDesignerController c = await pumpDesigner(tester);
      expect(find.byType(ReportToolbox), findsOneWidget);
      final Offset panel = tester.getTopLeft(find.byType(ReportToolbox));
      final RenderReportToolbox toolbox = tester.renderObject(
        find.byType(ReportToolbox),
      );
      await tester.tapAt(panel + toolbox.rectOf('tool.text')!.center);
      await tester.pump();
      expect(c.tool, ReportDesignTool.text);

      final TestGesture mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      addTearDown(mouse.removePointer);
      await mouse.addPointer();
      await mouse.moveTo(panel + toolbox.rectOf('tool.map')!.center);
      await tester.pump();
      expect(
        find.byWidgetPredicate(
          (Widget w) => w is ReportToolboxCard && w.title == 'Map',
        ),
        findsOneWidget,
      );
      await mouse.moveTo(Offset.zero);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(c.tool, ReportDesignTool.select);

      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pump();
      expect(c.mode, ReportDesignMode.preview);
      expect(find.byType(ReportPreviewSurface), findsOneWidget);
      expect(find.byType(ReportDesignerCanvas), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pump();
      expect(find.byType(ReportDesignerCanvas), findsOneWidget);
    });

    testWidgets('templates menu groups families and asks for a language', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final ReportDesignerController c = sample();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: QudsReportDesigner(
            controller: c,
            loadBundledFonts: false,
            templates: fileTemplates(),
            onExport: (ReportExportFormat f, Uint8List bytes) {},
          ),
        ),
      );
      await tester.pump();
      final Offset bar = tester.getTopLeft(find.byType(ReportToolbar));
      final RenderReportToolbar toolbar = tester.renderObject(
        find.byType(ReportToolbar),
      );
      await tester.tapAt(bar + toolbar.rectOf('templates')!.center);
      await tester.pump();
      expect(find.text('Human resources  ·  الموارد البشرية'), findsOneWidget);
      expect(find.text('Product catalog'), findsOneWidget);
      expect(find.text('كتالوج المنتجات'), findsOneWidget);
      await tester.tap(find.text('Certificate of appreciation'));
      await tester.pump();
      expect(find.text('English'), findsOneWidget);
      await tester.tap(find.text('العربية'));
      await tester.pump();
      expect(c.template.isRtl, isTrue);
      expect(c.images.keys, containsAll(<String>['logo', 'seal', 'stamp']));
      expect(c.template.name, 'شهادة شكر وتقدير');
      expect(tester.takeException(), isNull);
    });

    testWidgets('pinching with two fingers zooms the canvas and the preview', (
      WidgetTester tester,
    ) async {
      final ReportDesignerController c = await pumpDesigner(tester);
      final Offset center = tester.getCenter(find.byType(ReportDesignerCanvas));
      final double z0 = c.zoom;

      final TestPointer pad = TestPointer(1, PointerDeviceKind.trackpad);
      await tester.sendEventToBinding(pad.panZoomStart(center));
      await tester.sendEventToBinding(pad.panZoomUpdate(center, scale: 1.5));
      await tester.sendEventToBinding(pad.panZoomEnd());
      await tester.pump();
      expect(c.zoom, closeTo(z0 * 1.5, 1e-6));

      final double z1 = c.zoom;
      final TestGesture a = await tester.startGesture(
        center - const Offset(60, 0),
        pointer: 7,
        kind: PointerDeviceKind.touch,
      );
      final TestGesture b = await tester.startGesture(
        center + const Offset(60, 0),
        pointer: 8,
        kind: PointerDeviceKind.touch,
      );
      await a.moveTo(center - const Offset(30, 0));
      await b.moveTo(center + const Offset(30, 0));
      await a.up();
      await b.up();
      await tester.pump();
      expect(c.zoom, closeTo(z1 / 2, 1e-6));
      expect(c.selection, isEmpty);
      expect(c.canUndo, isFalse);

      c.togglePreview();
      await tester.pump();
      final Offset preview = tester.getCenter(
        find.byType(ReportPreviewSurface),
      );
      final double z2 = c.zoom;
      await tester.sendEventToBinding(pad.panZoomStart(preview));
      await tester.sendEventToBinding(pad.panZoomUpdate(preview, scale: 2));
      await tester.sendEventToBinding(pad.panZoomEnd());
      await tester.pump();
      expect(c.zoom, closeTo(z2 * 2, 1e-6));
      expect(tester.takeException(), isNull);
    });

    testWidgets('problems panel opens, takes the user to a problem, closes', (
      WidgetTester tester,
    ) async {
      final ReportDesignerController c = ReportDesignerController.fromXml(
        sampleXml.replaceFirst('>Sub<', '>{{BOGUS(1)}}<'),
      );
      await pumpDesigner(tester, controller: c);
      expect(find.byType(ReportProblemsPanel), findsNothing);
      c.problemsOpen = true;
      await tester.pump();
      final Rect panel = tester.getRect(find.byType(ReportProblemsPanel));
      expect(panel.height, greaterThan(100));
      final RenderReportProblems render = tester.renderObject(
        find.byType(ReportProblemsPanel),
      );
      final ReportDiagnostic first = c.problems.first;
      expect(render.kindLabel(first), 'Unknown function');
      expect(render.where(first), 'Report Header  ›  Text "sub"');

      await tester.tapAt(
        panel.topLeft +
            const Offset(200, RenderReportProblems.headerHeight + 20),
      );
      await tester.pump();
      expect(c.selection, <String>[byName(c, 'sub').id]);
      expect(c.activeProblem, same(first));
      expect(c.highlightProperty, 'text');
      expect(tester.takeException(), isNull);

      c.strings = ReportDesignerStrings.arabic;
      await tester.pump();
      expect(render.kindLabel(first), 'دالة غير معروفة');
      expect(tester.takeException(), isNull);
      c.strings = ReportDesignerStrings.english;
      await tester.pump();

      await tester.tapAt(panel.topRight + const Offset(-24, 16));
      await tester.pump();
      expect(c.problemsOpen, isFalse);
      expect(find.byType(ReportProblemsPanel), findsNothing);
    });

    testWidgets('print button and Ctrl+P hand the host a PDF', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final ReportDesignerController c = sample();
      addTearDown(c.dispose);
      final List<Uint8List> printed = <Uint8List>[];
      await tester.pumpWidget(
        MaterialApp(
          home: QudsReportDesigner(
            controller: c,
            loadBundledFonts: false,
            templates: const <ReportTemplateInfo>[],
            onPrint: (Uint8List pdf) async => printed.add(pdf),
          ),
        ),
      );
      await tester.pump();
      final Offset bar = tester.getTopLeft(find.byType(ReportToolbar));
      final RenderReportToolbar toolbar = tester.renderObject(
        find.byType(ReportToolbar),
      );
      expect(toolbar.rectOf('export'), isNull);
      await tester.tapAt(bar + toolbar.rectOf('print')!.center);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      expect(printed, hasLength(1));
      expect(String.fromCharCodes(printed.first.take(5)), '%PDF-');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      expect(printed, hasLength(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('creating with a tool adds an element where clicked', (
      WidgetTester tester,
    ) async {
      final ReportDesignerController c = await pumpDesigner(tester);
      final int before = c.template.allElements.length;
      c.tool = ReportDesignTool.rectangle;
      await tester.pump();
      final ReportElement line = byName(c, 'line');
      final Offset at = elementCenter(tester, c, line) + const Offset(0, 40);
      final TestGesture g = await tester.startGesture(
        at,
        kind: PointerDeviceKind.mouse,
      );
      await g.moveBy(const Offset(60, 30));
      await g.up();
      await tester.pump();
      expect(c.template.allElements.length, before + 1);
      final ReportElement created = c.primary!;
      expect(created, isA<ReportShapeElement>());
      expect(created.width, greaterThan(50));
      expect(c.tool, ReportDesignTool.select);
    });

    testWidgets('chart templates paint in design and preview', (
      WidgetTester tester,
    ) async {
      final ReportDesignerController c = ReportDesignerController(
        clock: () => DateTime(2026, 10, 10, 9, 30),
      )..loadTemplate(fileTemplate('sales_performance'));
      await pumpDesigner(tester, controller: c);
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pump();
      expect(find.byType(ReportPreviewSurface), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keyboard picks a suggestion while editing on the canvas', (
      WidgetTester tester,
    ) async {
      final ReportDesignerController c = await pumpDesigner(tester);
      final ReportTextElement title = byName(c, 'title') as ReportTextElement;
      title.style.color = '#FFFFFF';
      title.background = '#1F4E78';
      c.beginTextEdit(title.id);
      c.textEditor.replaceRange(0, c.textEditor.formulaBar.length, '{{Sys');
      await tester.pump();
      expect(c.completion, isNotNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(c.textEditor.formulaBar, '{{System');
      c.textEditor.replaceRange(8, 8, '.Page');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(c.textEditor.formulaBar, '{{System.PageNumber');
      expect(c.editingId, title.id);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(c.editingId, isNull);
      expect(tester.takeException(), isNull);
    });

    test('editor text keeps contrast on dark fills', () {
      expect(
        RenderReportDesigner.contrast(
          const Color(0xFFFFFFFF),
          const Color(0xFF1F4E78),
        ),
        greaterThan(4.5),
      );
      expect(
        RenderReportDesigner.contrast(
          const Color(0xFFFFFFFF),
          const Color(0xFFFFFFFF),
        ),
        closeTo(1, 1e-9),
      );
    });
  });

  group('Report package images', () {
    final Uint8List wide = PngBytes.rgb(
      width: 40,
      height: 10,
      plot: (int x, int y, List<int> rgb) => rgb[2] = 255,
    );

    test('saves and reopens embedded images with the layout', () {
      final ReportDesignerController c = ReportDesignerController.fromXml(
        sampleXml,
      );
      expect(c.addImage('Company Logo.png', wide), 'Company_Logo');
      expect(c.addImage('notes.txt', Uint8List.fromList(<int>[1, 2])), isNull);
      final ReportImageElement e = c.insertImage('Company_Logo')!;
      expect(e.source, 'Company_Logo');
      expect(e.width / e.height, closeTo(4, 0.01));

      final Uint8List bytes = c.toPackage();
      expect(ReportPackage.isPackage(bytes), isTrue);
      final ReportDesignerController back =
          ReportDesignerController.fromPackage(bytes);
      expect(back.imageNames, <String>['Company_Logo']);
      expect(back.images['Company_Logo'], wide);
      expect(
        back.template.bands
            .expand((ReportBand b) => b.elements)
            .whereType<ReportImageElement>()
            .single
            .source,
        'Company_Logo',
      );

      back.loadXml(sampleXml);
      expect(back.images, isEmpty, reason: 'images belong to the document');
      back.loadPackage(bytes);
      expect(back.imageNames, <String>['Company_Logo']);
    });

    test('rename, remove and import are undoable', () async {
      final ReportDesignerController c = ReportDesignerController.fromXml(
        sampleXml,
      );
      final String key = c.addImage('logo.png', wide)!;
      final ReportImageElement e = c.insertImage(key)!;
      final String id = e.id;
      ReportImageElement element() =>
          c.template.findElement(id)!.$2 as ReportImageElement;

      expect(c.renameImage(key, 'bad name'), isFalse);
      expect(c.renameImage(key, 'brand'), isTrue);
      expect(c.imageNames, <String>['brand']);
      expect(element().source, 'brand');
      c.undo();
      expect(c.imageNames, <String>['logo']);
      expect(element().source, 'logo');

      expect(c.removeImage('logo'), isTrue);
      expect(c.images, isEmpty);
      c.undo();
      expect(c.images['logo'], wide);

      c.select(id);
      expect(
        c.properties.map((ReportProperty p) => p.key),
        isNot(contains('source.import')),
      );
      c.imagePicker = () async => (name: 'stamp.png', bytes: wide);
      final ReportProperty source = c.properties.firstWhere(
        (ReportProperty p) => p.key == 'source',
      );
      expect(source.presets, <String>['logo']);
      c.setProperty('source.import', 'Import image…');
      await Future<void>.delayed(Duration.zero);
      expect(c.imageNames, <String>['logo', 'stamp']);
      expect(element().source, 'stamp');
      c.undo();
      expect(c.imageNames, <String>['logo']);
      expect(element().source, 'logo');
    });

    test(
      'replacing an image keeps its name and updates its elements',
      () async {
        final ReportDesignerController c = ReportDesignerController.fromXml(
          sampleXml,
        );
        final String key = c.addImage('logo.png', wide)!;
        final ReportImageElement e = c.insertImage(key)!;
        final Uint8List square = PngBytes.rgb(
          width: 12,
          height: 12,
          plot: (int x, int y, List<int> rgb) => rgb[0] = 255,
        );
        expect(c.replaceImage('missing', square), isFalse);
        expect(
          c.replaceImage(key, Uint8List.fromList(<int>[1, 2, 3])),
          isFalse,
        );
        expect(c.replaceImage(key, square), isTrue);
        expect(c.imageNames, <String>['logo']);
        expect(c.images['logo'], same(square));
        expect(
          (c.template.findElement(e.id)!.$2 as ReportImageElement).source,
          'logo',
        );
        c.undo();
        expect(c.images['logo'], same(wide));
        c.redo();
        expect(c.images['logo'], same(square));

        c.select(e.id);
        expect(
          c.properties.map((ReportProperty p) => p.key),
          isNot(contains('source.replace')),
        );
        c.imagePicker = () async => (name: 'new.png', bytes: wide);
        expect(
          c.properties.map((ReportProperty p) => p.key),
          contains('source.replace'),
        );
        c.setProperty('source.replace', 'Replace image…');
        await Future<void>.delayed(Duration.zero);
        expect(c.images['logo'], same(wide));
        expect(c.imageNames, <String>['logo']);

        c.select(null);
        c.inspectorPage = ReportInspectorPage.images;
        c.imagePicker = () async => (name: 'notes.txt', bytes: Uint8List(8));
        c.setProperty('img.0.replace', 'Replace image…');
        await Future<void>.delayed(Duration.zero);
        expect(c.images['logo'], same(wide));
        expect(c.notice, 'The chosen file is not a PNG or JPEG image');
        c.imagePicker = () async => (name: 'red.png', bytes: square);
        c.setProperty('img.0.replace', 'Replace image…');
        await Future<void>.delayed(Duration.zero);
        expect(c.images['logo'], same(square));
      },
    );

    test('report inspector lists embedded images', () {
      final ReportDesignerController c = ReportDesignerController.fromXml(
        sampleXml,
      )..imagePicker = () async => null;
      c.addImage('logo.png', wide);
      c.select(null);
      expect(
        c.properties.map((ReportProperty p) => p.key),
        isNot(contains('image+')),
      );
      c.inspectorPage = ReportInspectorPage.images;
      final List<ReportProperty> props = c.properties;
      final Map<String, ReportProperty> byKey = <String, ReportProperty>{
        for (final ReportProperty p in props) p.key: p,
      };
      expect(byKey['image+']!.kind, ReportPropertyKind.action);
      expect(byKey['img.0.name']!.value, 'logo');
      expect(byKey['img.0.insert']!.group, startsWith('logo · PNG 40×10, '));
      c.setProperty('img.0.name', 'brand');
      expect(c.imageNames, <String>['brand']);
      c.setProperty('img.0.insert', 'Insert into report');
      expect(c.selectedElements.single, isA<ReportImageElement>());
      expect(c.inspectorPage, ReportInspectorPage.properties);
      c.select(null);
      c.inspectorPage = ReportInspectorPage.images;
      c.setProperty('img.0.remove', 'Remove');
      expect(c.images, isEmpty);
    });
  });

  group('Report package fonts', () {
    List<ReportProperty> page(ReportDesignerController c) => c.properties;
    List<String> deviceRows(ReportDesignerController c) {
      c.beginPropertyEdit('font.add');
      final List<String> out = <String>[
        for (final ReportCompletionItem i
            in c.completion?.items ?? const <ReportCompletionItem>[])
          i.label,
      ];
      c.cancelPropertyEdit();
      return out;
    }

    ReportProperty prop(ReportDesignerController c, String key) =>
        page(c).firstWhere((ReportProperty p) => p.key == key);

    test('embeds faces, saves them in the package, and undoes', () {
      final ReportDesignerController c = ReportDesignerController.fromXml(
        sampleXml,
      );
      final Uint8List regular = fontFile('LiberationSerif-Regular.ttf');
      final Uint8List bold = fontFile('LiberationSerif-Bold.ttf');
      expect(c.addFont(regular), 'Liberation Serif');
      expect(c.addFont(bold), 'Liberation Serif');
      expect(c.embeddedFamilies, <String>['Liberation Serif']);
      expect(
        () => c.addFont(fontFile('LiberationSerif-Italic.ttf')),
        throwsA(isA<ReportFontException>()),
      );
      expect(c.fonts.isEmpty, isTrue, reason: 'host registry untouched');
      expect(c.effectiveFonts.has('Liberation Serif'), isTrue);
      expect(c.engine.fonts.has('Liberation Serif'), isTrue);
      expect(c.fontFamilies, contains('Liberation Serif'));

      c.setProperty('defaultFont', 'Liberation Serif');
      final ReportTextPrimitive text = c.previewLayout!.pages.first.primitives
          .whereType<ReportTextPrimitive>()
          .first;
      expect(
        c.effectiveFonts
            .faceFor(text.font.family, 0x48, bold: text.font.bold)!
            .bytes,
        text.font.bold ? bold : regular,
      );

      final ReportDesignerController back =
          ReportDesignerController.fromPackage(c.toPackage());
      expect(back.embeddedFamilies, <String>['Liberation Serif']);
      expect(back.embeddedFonts['Liberation Serif']!.bold, bold);
      expect(back.template.defaultFont, 'Liberation Serif');
      back.loadXml(sampleXml);
      expect(back.embeddedFonts, isEmpty, reason: 'fonts belong to the file');

      c.undo();
      c.undo();
      expect(c.embeddedFonts['Liberation Serif']!.bold, isNull);
      c.undo();
      expect(c.embeddedFonts, isEmpty);
      expect(c.effectiveFonts, same(c.fonts));
    });

    test('fonts page imports files and embeds installed fonts', () async {
      final FakeDeviceFonts device = FakeDeviceFonts(<String, ReportFontFiles>{
        'Liberation Serif': ReportFontFiles(
          regular: fontFile('LiberationSerif-Regular.ttf'),
          bold: fontFile('LiberationSerif-Bold.ttf'),
        ),
        'Liberation Mono': ReportFontFiles(
          regular: fontFile('LiberationMono-Regular.ttf'),
        ),
        'Broken': ReportFontFiles(regular: Uint8List(40)),
      });
      final ReportDesignerController c =
          ReportDesignerController.fromXml(sampleXml)
            ..deviceFonts = device
            ..fontPicker = () async => <({String name, Uint8List bytes})>[
              (name: 'a.ttf', bytes: fontFile('LiberationSans-Regular.ttf')),
              (name: 'b.ttf', bytes: fontFile('LiberationSans-Italic.ttf')),
            ];
      addTearDown(c.dispose);
      c.inspectorPage = ReportInspectorPage.fonts;
      expect(c.inspectorTitle, 'Fonts');
      expect(prop(c, 'font.none').kind, ReportPropertyKind.note);
      expect(prop(c, 'font.add').kind, ReportPropertyKind.text);
      expect(c.deviceFamilies, isNull, reason: 'still listing');
      await settle();
      expect(
        deviceRows(c),
        unorderedEquals(<String>[
          'Broken',
          'Liberation Mono',
          'Liberation Serif',
        ]),
      );

      c.beginPropertyEdit('font.add');
      final InlineCellEditor ed = c.propertyEditor;
      ed.replaceRange(0, ed.formulaBar.length, 'SERIF');
      expect(
        c.completion!.items.map((ReportCompletionItem i) => i.label),
        <String>['Liberation Serif'],
      );
      expect(c.acceptCompletion(0), isTrue);
      expect(c.editingProperty, isNull, reason: 'picking a font commits');
      await settle();
      expect(c.embeddedFamilies, <String>['Liberation Serif']);
      expect(c.notice, startsWith('Embedded Liberation Serif (Regular + Bold'));
      expect(
        deviceRows(c),
        isNot(contains('Liberation Serif')),
        reason: 'embedded families leave',
      );
      expect(prop(c, 'font.0.uses').value, 'No elements');
      c.setProperty('font.0.default', 'true');
      expect(c.template.defaultFont, 'Liberation Serif');
      expect(prop(c, 'font.0.default').value, 'true');

      c.setProperty('font.add', 'Broken');
      await settle();
      expect(c.notice, startsWith('Could not embed Broken'));
      expect(c.embeddedFamilies, <String>['Liberation Serif']);

      c.setProperty('font+', 'Import font file…');
      await settle();
      expect(c.embeddedFamilies, <String>[
        'Liberation Sans',
        'Liberation Serif',
      ]);
      expect(c.notice, contains('Embedded Liberation Sans'));
      expect(c.notice, contains('b.ttf: '));
      c.undo();
      expect(c.embeddedFamilies, <String>['Liberation Serif']);

      c.select(byName(c, 'title').id);
      c.setProperty('fontFamily', 'Liberation Mono');
      await settle();
      expect(c.embeddedFamilies, <String>[
        'Liberation Mono',
        'Liberation Serif',
      ]);
      c.select(null);
      c.inspectorPage = ReportInspectorPage.fonts;
      expect(prop(c, 'font.0.uses').value, '1');
      c.setProperty('font.0.remove', 'Remove');
      expect(c.embeddedFamilies, <String>['Liberation Serif']);
      expect(device.listed, 1, reason: 'the device list is read once');
    });
  });

  group('Element names', () {
    test('every element gets a unique name it keeps on rename', () {
      final ReportDesignerController c = sample();
      expect(c.template.duplicateElementNames, isEmpty);
      final List<String?> names = <String?>[
        for (final (ReportBand _, ReportElement e) in c.template.allElements)
          e.name,
      ];
      expect(names, <String>['title', 'sub', 'box', 'line', 'text1']);
      final ReportElement? added = c.addElement(
        ReportDesignTool.text,
        ReportBandKind.reportHeader,
        const ReportRect(10, 10, 0, 0),
      );
      expect(added!.name, 'text2');
      c.setProperty('name', 'title');
      expect(added.name, 'text2');
      expect(c.notice, contains('already named "title"'));
      c.setProperty('name', '2nd');
      expect(added.name, 'text2');
      expect(c.notice, contains('not a valid name'));
      c.setProperty('name', 'grandTotal');
      expect(added.name, 'grandTotal');
      c.setProperty('name', '');
      expect(added.name, 'text2');
      c.selectAll();
      c.setProperty('name', 'same');
      expect(c.notice, contains('single element'));
      expect(c.engine.element('grandTotal'), isNull);
      expect(c.engine.element('TITLE'), same(byName(c, 'title')));
      c.dispose();
    });
  });

  group('Report data explorer', () {
    int col(ReportDesignerController c, String name) => c.dataTable.columns
        .indexWhere((ReportDataColumnView v) => v.name == name);

    test('lists inferred tables and fields; edits create sample data', () {
      final ReportDesignerController c = sample();
      c.mode = ReportDesignMode.data;
      expect(c.dataTables.map((ReportDataTableView t) => t.title), <String>[
        'Fields',
        'items',
      ]);
      final ReportDataTableView items = c.dataTable;
      expect(items.name, 'items');
      expect(items.rows, hasLength(c.mockRows));
      expect(
        items.columns.map((ReportDataColumnView v) => v.name),
        containsAll(<String>['name', 'qty']),
      );
      expect(items.columns[col(c, 'qty')].type, ReportDataType.number);
      expect(c.hasSampleData, isFalse);
      final Map<String, Object?> inferred = c.mockData;

      expect(c.setDataCell(0, col(c, 'qty'), '7'), isTrue);
      expect(c.hasSampleData, isTrue);
      expect(c.dataTable.rows[0][col(c, 'qty')], const ReportNumber(7));
      expect(c.setDataCell(0, col(c, 'qty'), 'abc'), isFalse);
      expect(c.notice, contains('not a valid number'));
      c.undo();
      expect(c.hasSampleData, isFalse);
      expect(c.mockData, inferred);
      c.redo();
      expect(c.sampleData, isNotNull);

      c.selectDataTable('');
      expect(c.dataTable.isFields, isTrue);
      expect(
        c.dataTable.rows.map((List<ReportValue> r) => r.first.displayText),
        contains('customer'),
      );
      c.selectDataCell(0, 1);
      expect(c.canEditDataCell(0, 1), isTrue);
      expect(c.canEditDataCell(0, 0), isFalse);
      expect(c.beginCellEdit(0, 1, initial: 'A'), isTrue);
      expect(c.editingDataCell, (row: 0, column: 1));
      c.propertyEditor.replaceRange(1, 1, 'cme');
      c.commitPropertyEdit();
      expect(c.mockData['customer'], 'Acme');
      expect(c.inspectorTitle, 'Data: Fields');
      c.dispose();
    });

    test('rows, typed and calculated columns, and renames', () {
      final ReportDesignerController c = sample();
      c.mode = ReportDesignMode.data;
      final int rows = c.dataTable.rows.length;
      c.selectDataCell(1, -1);
      expect(c.addDataRow(), isTrue);
      expect(c.dataTable.rows, hasLength(rows + 1));
      expect(c.dataRow, 2);
      expect(c.removeDataRows(<int>[2]), isTrue);
      expect(c.dataTable.rows, hasLength(rows));

      expect(
        c.addDataColumn(name: 'price', type: ReportDataType.number),
        'price',
      );
      expect(c.dataColumn, col(c, 'price'));
      expect(c.inspectorTitle, 'Column: price');
      for (int r = 0; r < rows; r++) {
        c.setDataCell(r, col(c, 'price'), '${r + 1}.5');
      }
      expect(
        c.addDataColumn(
          name: 'total',
          type: ReportDataType.number,
          expression: 'qty * price',
        ),
        'total',
      );
      expect(c.addDataColumn(name: 'total'), isNull);
      expect(c.notice, contains('already exists'));
      final ReportDataTableView t = c.dataTable;
      final int q = col(c, 'qty');
      final int p = col(c, 'price');
      final int total = col(c, 'total');
      expect(t.columns[total].isCalculated, isTrue);
      expect(c.canEditDataCell(0, total), isFalse);
      c.selectDataCell(-1, total);
      c.beginPropertyEdit('data.col.expression');
      c.propertyEditor.replaceRange(
        0,
        c.propertyEditor.formulaBar.length,
        'pri',
      );
      expect(
        c.completion!.items.map((ReportCompletionItem i) => i.insert),
        contains('price'),
      );
      c.cancelPropertyEdit();
      expect(
        t.rows[0][total].asNumber,
        t.rows[0][q].asNumber! * t.rows[0][p].asNumber!,
      );
      c.selectDataCell(-1, total);
      c.setProperty('data.col.format', 'n2');
      expect(
        c.dataCellDisplay(c.dataTable.columns[total], const ReportNumber(3)),
        '3.00',
      );

      expect(c.renameDataColumn('qty', 'quantity'), isTrue);
      expect(
        (byName(c, 'line') as ReportTextElement).text,
        '{{item.name}} {{item.quantity}}',
      );
      expect(
        (byName(c, 'text1') as ReportTextElement).text,
        '{{SUM(items.quantity)}}',
      );
      expect(
        c.template.dataSchema.table('items')!.column('total')!.expression,
        'quantity * price',
      );
      expect(c.dataTable.rows[0][col(c, 'total')].asNumber, isNotNull);
      expect(c.previewError, isNull);

      expect(c.setDataColumnType('price', ReportDataType.text), isTrue);
      final List<Object?> raw = c.mockData['items']! as List<Object?>;
      expect((raw.first! as Map<String, Object?>)['price'], '1.5');
      expect(c.removeDataColumn('price'), isTrue);
      expect(col(c, 'price'), -1);

      final String xml = c.toXml();
      expect(xml, contains('<DataSchema>'));
      final ReportDesignerController back =
          ReportDesignerController.fromPackage(c.toPackage());
      expect(back.sampleData!['items'], isA<List<Object?>>());
      expect(
        back.template.dataSchema.table('items')!.column('total'),
        isNotNull,
      );
      expect(back.toXml(), xml);
      back.dispose();
      c.dispose();
    });

    test('fields, tables, imports and host data', () {
      final ReportDesignerController c = sample();
      c.mode = ReportDesignMode.data;
      expect(c.addDataField('invoice.no'), isTrue);
      expect(c.dataTable.isFields, isTrue);
      expect(c.addDataField('invoice.no'), isFalse);
      expect(c.setDataField('invoice.no', 'INV-1'), isTrue);
      expect(ReportData.valueAt(c.mockData, 'invoice.no'), 'INV-1');
      expect(c.renameDataField('customer', 'client'), isTrue);
      expect(
        (byName(c, 'title') as ReportTextElement).text,
        'Hello {{Data.client}}',
      );
      expect(c.setDataFieldType('invoice.no', ReportDataType.number), isTrue);

      expect(c.addDataTable('orders'), isTrue);
      expect(c.dataTable.name, 'orders');
      expect(c.addDataTable('orders'), isFalse);
      expect(c.addDataTable('bad name'), isFalse);
      expect(c.importDataText('orders.csv', 'id;amount\nA;10\nB;2,5'), isTrue);
      expect(c.dataTable.rows, hasLength(2));
      expect(c.dataTable.columns[1].type, ReportDataType.number);
      expect(c.removeDataTable('orders'), isTrue);
      expect(
        c.dataTables.any((ReportDataTableView t) => t.name == 'orders'),
        isFalse,
      );

      c.selectDataTable('');
      expect(c.importDataText('People List.csv', 'name,age\nAli,30\n'), isTrue);
      expect(c.dataTable.name, 'People_List');
      expect(
        c.importDataText(
          'data.json',
          '{"customer":"Z","when":"2026-03-04","items":[{"name":"Q","qty":3}]}',
        ),
        isTrue,
      );
      expect(c.mockData['customer'], 'Z');
      expect(c.mockData['when'], DateTime(2026, 3, 4));
      expect(c.importDataText('bad.json', '{'), isFalse);
      expect(c.notice, contains('Invalid JSON'));
      expect(c.importDataText('bad.json', '[1, 2]'), isFalse);

      c.mockData = <String, Object?>{
        'items': <Object?>[
          <String, Object?>{'name': 'Host', 'qty': 1},
        ],
      };
      expect(c.hasHostData, isTrue);
      expect(c.dataEditable, isFalse);
      c.selectDataTable('items');
      expect(c.dataTable.rows.single.first, const ReportText('Host'));
      expect(c.setDataCell(0, 0, 'x'), isFalse);
      expect(c.notice, contains('read-only'));
      expect(c.addDataColumn(name: 'double', expression: 'qty * 2'), 'double');
      expect(c.dataTable.rows.single[col(c, 'double')].asNumber, 2);
      expect(
        c.properties.map((ReportProperty p) => p.key),
        isNot(contains('data.row+')),
      );
      c.dispose();
    });

    testWidgets('designer shows the explorer and edits cells', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final ReportDesignerController c = sample();
      addTearDown(c.dispose);
      var picked = 0;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Overlay(
            initialEntries: <OverlayEntry>[
              OverlayEntry(
                builder: (BuildContext context) => QudsReportDesigner(
                  controller: c,
                  loadBundledFonts: false,
                  templates: const <ReportTemplateInfo>[],
                  onPickData: () async {
                    picked++;
                    return (name: 'rows.csv', text: 'name,qty\nPicked,4\n');
                  },
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(c.dataPicker, isNotNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.f6);
      await tester.pump();
      expect(c.mode, ReportDesignMode.data);
      final Finder explorer = find.byType(ReportDataExplorer);
      expect(explorer, findsOneWidget);
      final RenderReportDataExplorer ro = tester.renderObject(explorer);
      final Offset origin = tester.getTopLeft(explorer);

      final int name = col(c, 'name');
      await tester.tapAt(origin + ro.cellRect(0, name).center);
      await tester.pump();
      expect((c.dataRow, c.dataColumn), (0, name));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(c.dataRow, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.pump();
      expect(c.editingDataCell, (row: 1, column: name));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(c.editingDataCell, isNull);
      expect(c.dataRow, 2);
      expect(c.dataTable.rows[1][name].displayText, 'z');

      await tester.tapAt(origin + ro.cellRect(0, name).center);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(origin + ro.cellRect(0, name).center);
      await tester.pump();
      expect(c.editingDataCell, (row: 0, column: name));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(c.editingDataCell, isNull);

      await tester.tapAt(origin + ro.sidebarRect('')!.center);
      await tester.pump();
      expect(c.dataTable.isFields, isTrue);
      await tester.tapAt(origin + ro.sidebarRect('items')!.center);
      await tester.pump();

      await tester.tapAt(
        origin + ro.cellRect(0, name).center,
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();
      expect(find.text('Insert row above'), findsOneWidget);
      await tester.tap(find.text('Insert row above'));
      await tester.pump();
      expect(c.dataTable.rows.first[name], ReportNull.instance);

      c.setProperty('data.import', '');
      await tester.runAsync(settle);
      await tester.pump();
      expect(picked, 1);
      expect(c.dataTable.rows.single[name].displayText, 'Picked');

      tester.view.physicalSize = const Size(700, 600);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.f6);
      await tester.pump();
      expect(c.mode, ReportDesignMode.design);
    });

    testWidgets('the field tree shows a scrollbar and scrolls', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 520);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final ReportDesignerController c = sample();
      addTearDown(c.dispose);
      c.mode = ReportDesignMode.data;
      for (int i = 0; i < 24; i++) {
        expect(c.addDataColumn(name: 'col$i'), 'col$i');
      }
      c.selectDataCell(-1, -1);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Overlay(
            initialEntries: <OverlayEntry>[
              OverlayEntry(
                builder: (BuildContext context) => QudsReportDesigner(
                  controller: c,
                  loadBundledFonts: false,
                  templates: const <ReportTemplateInfo>[],
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      final Finder explorer = find.byType(ReportDataExplorer);
      final RenderReportDataExplorer ro = tester.renderObject(explorer);
      final Offset origin = tester.getTopLeft(explorer);
      expect(ro.sidebarScrollbar, isNotNull);
      final double before = ro.sidebarRect('items')!.top;
      final TestPointer mouse = TestPointer(1, PointerDeviceKind.mouse);
      final Offset at = origin + const Offset(30, 90);
      await tester.sendEventToBinding(mouse.hover(at));
      await tester.pump();
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 180)));
      await tester.pump();
      expect(ro.sidebarRect('items')!.top, lessThan(before - 40));

      final Rect thumb = ro.sidebarScrollbar!;
      final double scrolled = ro.sidebarRect('items')!.top;
      await tester.dragFrom(origin + thumb.center, const Offset(0, 36));
      await tester.pump();
      expect(ro.sidebarRect('items')!.top, lessThan(scrolled));
    });

    testWidgets('a long choice menu scrolls and filters as you type', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(800, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final List<String> picked = <String>[];
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(800, 480)),
          child: Theme(
            data: ThemeData.light(),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Overlay(
                initialEntries: <OverlayEntry>[
                  OverlayEntry(
                    builder: (BuildContext context) {
                      return GestureDetector(
                        key: const Key('open-menu'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          OfficeContextMenu.show(
                            context: context,
                            globalPosition: const Offset(24, 24),
                            filterHint: 'Type to search',
                            actions: <OfficeContextAction>[
                              const OfficeContextAction.caption('Label field'),
                              for (int i = 0; i < 40; i++)
                                OfficeContextAction(
                                  id: 'f$i',
                                  label: i == 37 ? 'lbl' : 'field$i',
                                ),
                            ],
                            onSelect: picked.add,
                          );
                        },
                        child: const SizedBox.expand(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open-menu')));
      await tester.pump();
      final Finder menu = find.byKey(const Key('office-context-menu'));
      expect(menu, findsOneWidget);
      final RenderBox box = tester.renderObject(menu);
      expect(box.size.height, lessThanOrEqualTo(480));
      expect(find.text('Type to search'), findsOneWidget);
      expect(find.text('lbl'), findsOneWidget);
      final TestPointer mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(tester.getCenter(menu)));
      await tester.pump();
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 240)));
      await tester.pump();
      final Transform scrolled = tester.widget<Transform>(
        find.descendant(of: menu, matching: find.byType(Transform)),
      );
      expect(scrolled.transform.getTranslation().y, lessThan(-40));

      await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
      await tester.pump();
      expect(find.text('field0'), findsNothing);
      expect(find.text('lbl'), findsWidgets);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(picked, <String>['f37']);
    });

    testWidgets('closing a choice menu and opening another does not throw', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(800, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      OverlayEntry? menu;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(800, 480)),
          child: Theme(
            data: ThemeData.light(),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Overlay(
                initialEntries: <OverlayEntry>[
                  OverlayEntry(
                    builder: (BuildContext context) {
                      return GestureDetector(
                        key: const Key('open-menu'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          menu = OfficeContextMenu.show(
                            context: context,
                            globalPosition: const Offset(24, 24),
                            actions: const <OfficeContextAction>[
                              OfficeContextAction(id: 'a', label: 'Alpha'),
                              OfficeContextAction(id: 'b', label: 'Beta'),
                            ],
                            onSelect: (_) {},
                          );
                        },
                        child: const SizedBox.expand(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open-menu')));
      await tester.pump();
      expect(find.text('Alpha'), findsOneWidget);
      OfficeContextMenu.dismiss(menu);
      expect(() => OfficeContextMenu.dismiss(menu), returnsNormally);
      await tester.tap(find.byKey(const Key('open-menu')));
      await tester.pump();
      expect(find.text('Beta'), findsOneWidget);
    });
  });
}

/// Serves the files of [dir] under the asset folder [prefix], with a matching
/// `AssetManifest.bin`.
class _DirectoryBundle extends CachingAssetBundle {
  _DirectoryBundle(this.dir, this.prefix);

  final String dir;
  final String prefix;

  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      final Map<String, List<Map<String, String>>> manifest =
          <String, List<Map<String, String>>>{
            for (final File f in Directory(dir).listSync().whereType<File>())
              '$prefix${f.uri.pathSegments.last}': <Map<String, String>>[
                <String, String>{'asset': '$prefix${f.uri.pathSegments.last}'},
              ],
          };
      return const StandardMessageCodec().encodeMessage(manifest)!;
    }
    final Uint8List bytes = File(
      '$dir/${key.substring(prefix.length)}',
    ).readAsBytesSync();
    return ByteData.sublistView(bytes);
  }
}
