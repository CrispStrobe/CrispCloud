import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const String invoiceXml = r'''<?xml version="1.0" encoding="UTF-8"?>
<QudsReport name="AdvancedInvoice" isRtl="true" pageSize="A4" orientation="Portrait" defaultFont="Cairo">
    <Settings>
        <Margins top="20mm" bottom="20mm" left="15mm" right="15mm"/>
        <Colors primary="#1F4E78" secondary="#595959" text="#000000" background="#FFFFFF"/>
    </Settings>
    <Variables>
        <Var name="CompanyName" value="شركة القدس للتقنية المتقدمة"/>
        <Var name="TaxNumber" value="TRN-987654321"/>
    </Variables>
    <Bands>
        <ReportHeader height="45mm">
            <Element type="Text" x="10mm" y="10mm" width="110mm" height="15mm" fontSize="20" bold="true" color="primary">
                {{Variables.CompanyName}}
            </Element>
            <Element type="Text" x="130mm" y="10mm" width="70mm" height="8mm" alignment="right" fontSize="10">
                التاريخ: {{System.CurrentDate}} ({{System.CurrentTime}})
            </Element>
            <Element type="Text" x="130mm" y="18mm" width="70mm" height="8mm" alignment="right" fontSize="10" color="secondary">
                الرقم الضريبي: {{Variables.TaxNumber}}
            </Element>
            <Element type="Shape" kind="Line" x1="10mm" y1="40mm" x2="200mm" y2="40mm" strokeWidth="0.5" color="primary"/>
        </ReportHeader>
        <PageHeader height="10mm">
            <Element type="Text" x="10mm" y="2mm" width="100mm" height="6mm" fontSize="9" color="secondary">
                فاتورة مبيعات رسمية - مرجع: {{Data.invoiceNo}}
            </Element>
        </PageHeader>
        <Detail dataSet="items" rowHeight="8mm">
            <Table x="10mm" y="5mm" width="190mm" showGrid="true" borderColor="#D3D3D3">
                <Columns>
                    <Column width="25mm" header="الرمز" align="center"/>
                    <Column width="95mm" header="وصف الصنف" align="right"/>
                    <Column width="20mm" header="الكمية" align="center"/>
                    <Column width="25mm" header="السعر الفردي" align="left"/>
                    <Column width="25mm" header="الإجمالي" align="left"/>
                </Columns>
                <RowTemplate>
                    <Cell field="item.code"/>
                    <Cell field="item.description"/>
                    <Cell field="item.qty"/>
                    <Cell field="item.price" format="currency:LYD"/>
                    <Cell field="item.total" format="currency:LYD" bold="true"/>
                </RowTemplate>
            </Table>
        </Detail>
        <GroupFooter height="20mm">
            <Element type="Text" x="130mm" y="5mm" width="40mm" height="8mm" bold="true" alignment="right">
                المجموع الفرعي:
            </Element>
            <Element type="Text" x="170mm" y="5mm" width="30mm" height="8mm" alignment="left">
                {{SUM(items.total)}}
            </Element>
        </GroupFooter>
        <PageFooter height="12mm">
            <Element type="Shape" kind="Line" x1="10mm" y1="2mm" x2="200mm" y2="2mm" strokeWidth="0.3" color="secondary"/>
            <Element type="Text" x="10mm" y="4mm" width="100mm" height="6mm" fontSize="8" color="secondary">
                تم الاستخراج بواسطة نظام Quds Office Suite
            </Element>
            <Element type="Text" x="150mm" y="4mm" width="50mm" height="6mm" alignment="right" fontSize="9" bold="true">
                الصفحة {{System.PageNumber}} من {{System.TotalPages}}
            </Element>
        </PageFooter>
        <ReportSummary height="35mm">
            <Element type="Text" x="10mm" y="5mm" width="190mm" height="8mm" bold="true">
                المبلغ بالحروف: {{TAFQEET(SUM(items.total), 'LYD')}}
            </Element>
            <Element type="Text" x="140mm" y="20mm" width="60mm" height="8mm" alignment="center">
                توقيع المسؤول / ....................
            </Element>
        </ReportSummary>
    </Bands>
</QudsReport>
''';

Map<String, Object?> invoiceData(int count) => <String, Object?>{
  'invoiceNo': 'INV-2026-001',
  'items': <Map<String, Object?>>[
    for (int i = 0; i < count; i++)
      <String, Object?>{
        'code': 'P${(i + 1).toString().padLeft(2, '0')}',
        'description': 'تطوير حزمة Dart رقم ${i + 1}',
        'qty': 1 + i % 3,
        'price': 500,
        'total': 500 * (1 + i % 3),
      },
  ],
};

ReportFontRegistry loadFonts() {
  final ReportFontRegistry fonts = ReportFontRegistry();
  final File regular = File(
    '../quds_office_editor/fonts/NotoNaskhArabic-Regular.ttf',
  );
  final File bold = File(
    '../quds_office_editor/fonts/NotoNaskhArabic-Bold.ttf',
  );
  if (regular.existsSync()) {
    fonts.registerBytes(
      'Noto Naskh Arabic',
      regular.readAsBytesSync(),
      bold: bold.existsSync() ? bold.readAsBytesSync() : null,
    );
  }
  final File latin = File(
    '../quds_office_editor/fonts/LiberationSans-Regular.ttf',
  );
  if (latin.existsSync()) {
    fonts.registerBytes('Liberation Sans', latin.readAsBytesSync());
  }
  return fonts;
}

final DateTime fixedNow = DateTime(2026, 10, 10, 9, 30);

QudsReportEngine invoiceEngine() => QudsReportEngine.fromXml(
  invoiceXml,
  fonts: loadFonts(),
  clock: () => fixedNow,
  userName: 'tester',
);

List<String> pageTexts(ReportPageLayout page) => <String>[
  for (final ReportPrimitive p in page.primitives)
    if (p is ReportTextPrimitive) p.text,
];

String partText(Uint8List zip, String uri) =>
    utf8.decode(OpcPackage.openBytes(zip).getPart(uri)!.bytesView);

void main() {
  group('Arabic Tafqeet', () {
    test('whole and fractional dinars', () {
      expect(ArabicTafqeet.amount(500, 'LYD'), 'فقط خمسمائة دينار ليبي لا غير');
      expect(
        ArabicTafqeet.amount(1250.5, 'LYD'),
        'فقط ألف ومائتان وخمسون ديناراً ليبياً وخمسمائة درهم لا غير',
      );
    });

    test('counted nouns follow dual and plural forms', () {
      expect(ArabicTafqeet.amount(2, 'LYD'), contains('ديناران'));
      expect(ArabicTafqeet.amount(3, 'LYD'), contains('دنانير'));
      expect(ArabicTafqeet.amount(11, 'LYD'), contains('ديناراً'));
      expect(ArabicTafqeet.amount(1000000, 'LYD'), contains('مليون'));
    });
  });

  group('English words', () {
    test('amounts with sub-units and singulars', () {
      expect(
        EnglishWords.amount(1250.5, 'LYD'),
        'One thousand two hundred fifty Libyan dinars and five hundred '
        'dirhams only',
      );
      expect(EnglishWords.amount(1, 'USD'), 'One US dollar only');
      expect(
        EnglishWords.amount(21.01, 'USD'),
        'Twenty-one US dollars and one cent only',
      );
      expect(EnglishWords.number(1000115), 'one million one hundred fifteen');
      expect(EnglishWords.amount(5, 'LYD', only: false), 'Five Libyan dinars');
      expect(() => EnglishWords.amount(1, 'XXX'), throwsA(isA<Exception>()));
    });

    test('AMOUNTWORDS, words: and dateAr: formats', () {
      final QudsExpressionEngine engine = QudsExpressionEngine();
      final ReportScope scope = ReportScope(
        data: const ReportRecord(<String, ReportValue>{}),
        variables: const ReportRecord(<String, ReportValue>{}),
        system: ReportSystemInfo(
          now: fixedNow,
          pageNumber: 1,
          totalPages: 1,
          userName: 'u',
        ),
      );
      expect(
        engine.interpolate("{{AMOUNTWORDS(42, 'EUR')}}", scope),
        'Forty-two euros only',
      );
      expect(
        engine.interpolate("{{AMOUNTWORDS(500, 'LYD', 'ar')}}", scope),
        'فقط خمسمائة دينار ليبي لا غير',
      );
      const ReportFormatter f = ReportFormatter();
      expect(f.format(ReportNumber(42), 'words:EUR'), 'Forty-two euros only');
      expect(
        f.format(
          ReportDate(DateTime(2026, 10, 12, 15)),
          'dateAr:EEEE d MMMM yyyy hh a',
        ),
        'الاثنين 12 أكتوبر 2026 03 م',
      );
    });
  });

  group('Expression engine', () {
    final QudsExpressionEngine engine = QudsExpressionEngine();
    final ReportRecord data = ReportValue.from(invoiceData(3)) as ReportRecord;
    final List<ReportValue> rows = (data.field('items')! as ReportList).items;
    final ReportScope scope = ReportScope(
      data: data,
      variables: const ReportRecord(<String, ReportValue>{
        'CompanyName': ReportText('Quds'),
      }),
      system: ReportSystemInfo(
        now: fixedNow,
        pageNumber: 2,
        totalPages: 5,
        userName: 'u',
      ),
    );

    test('inline arithmetic on the current row', () {
      final ReportScope rowScope = scope.copyWith(row: rows[1], rowIndex: 1);
      expect(
        engine.evaluateSource('item.price * item.qty', rowScope).asNumber,
        1000,
      );
      expect(
        engine.interpolate('{{ item.price * item.qty }}', rowScope),
        '1000',
      );
    });

    test('aggregates over a data set and row-relative aggregates', () {
      expect(engine.evaluateSource('SUM(items.total)', scope).asNumber, 3000);
      expect(engine.evaluateSource('COUNT(items)', scope).asNumber, 3);
      expect(engine.evaluateSource('MAX(items.total)', scope).asNumber, 1500);
      expect(engine.evaluateSource('AVG(items.total)', scope).asNumber, 1000);
      final ReportScope group = scope.copyWith(
        aggregateRows: rows.sublist(0, 2),
      );
      expect(engine.evaluateSource('SUM(item.total)', group).asNumber, 1500);
    });

    test('system values, variables, and formats', () {
      expect(
        engine.interpolate(
          '{{System.PageNumber}}/{{System.TotalPages}}',
          scope,
        ),
        '2/5',
      );
      expect(engine.interpolate('{{Variables.CompanyName}}', scope), 'Quds');
      expect(engine.interpolate('{{System.CurrentDate}}', scope), '2026/10/10');
      expect(
        engine.interpolate('{{ 1250.5 | currency:LYD }}', scope),
        '1,250.500 د.ل',
      );
      expect(
        engine.interpolate("{{TAFQEET(SUM(items.total), 'LYD')}}", scope),
        'فقط ثلاثة آلاف دينار ليبي لا غير',
      );
    });

    test('logic and null-safe arithmetic', () {
      expect(
        engine.interpolate(
          "{{ IF(SUM(items.total) > 2000, 'big', 'small') }}",
          scope,
        ),
        'big',
      );
      expect(engine.evaluateSource('10 / 0', scope).isNull, isTrue);
      expect(engine.evaluateSource("missing ?? 'x'", scope).displayText, 'x');
    });

    test('unknown functions are rejected', () {
      expect(
        () => engine.evaluateSource('NOPE(1)', scope),
        throwsA(isA<ReportExpressionException>()),
      );
    });
  });

  group('Template XML', () {
    test('parses the invoice template', () {
      final ReportParseResult result = QudsReportXmlParser().parse(invoiceXml);
      expect(result.hasErrors, isFalse, reason: result.diagnostics.join('\n'));
      final ReportTemplate t = result.template;
      expect(t.isRtl, isTrue);
      expect(t.bands.map((ReportBand b) => b.kind), <ReportBandKind>[
        ReportBandKind.reportHeader,
        ReportBandKind.pageHeader,
        ReportBandKind.detail,
        ReportBandKind.groupFooter,
        ReportBandKind.pageFooter,
        ReportBandKind.reportSummary,
      ]);
      expect(t.margins.left, closeTo(15 * 72 / 25.4, 0.01));
      final ReportTableElement table = t.detail!.elements
          .whereType<ReportTableElement>()
          .single;
      expect(table.columns.length, 5);
      expect(table.cells[3].format, 'currency:LYD');
      expect(table.cells[4].bold, isTrue);
      final ReportShapeElement line = t
          .band(ReportBandKind.reportHeader)!
          .elements
          .whereType<ReportShapeElement>()
          .single;
      expect(line.kind, ReportShapeKind.line);
      expect(line.width, closeTo(190 * 72 / 25.4, 0.01));
      expect(t.resolveColor('primary', ReportColor.black).hex, '1F4E78');
    });

    test('round-trips through the writer', () {
      final ReportTemplate first = QudsReportXmlParser()
          .parse(invoiceXml)
          .templateOrThrow;
      final String xml = const QudsReportXmlWriter().write(first);
      final ReportTemplate second = QudsReportXmlParser()
          .parse(xml)
          .templateOrThrow;
      expect(second.bands.length, first.bands.length);
      for (int i = 0; i < first.bands.length; i++) {
        expect(second.bands[i].kind, first.bands[i].kind);
        expect(second.bands[i].elements.length, first.bands[i].elements.length);
      }
      final ReportTableElement table = second.detail!.elements
          .whereType<ReportTableElement>()
          .single;
      expect(table.cells.map((ReportTableCell c) => c.field), <String>[
        'item.code',
        'item.description',
        'item.qty',
        'item.price',
        'item.total',
      ]);
    });

    test('mirrorRtl defaults on and round-trips when disabled', () {
      final QudsReportXmlParser parser = QudsReportXmlParser();
      expect(parser.parse(invoiceXml).templateOrThrow.mirrored, isTrue);
      final ReportTemplate flat = parser
          .parse(
            invoiceXml.replaceFirst(
              'isRtl="true"',
              'isRtl="true" mirrorRtl="false"',
            ),
          )
          .templateOrThrow;
      expect(flat.mirrored, isFalse);
      final String xml = const QudsReportXmlWriter().write(flat);
      expect(xml, contains('mirrorRtl="false"'));
      expect(parser.parse(xml).templateOrThrow.mirrored, isFalse);
    });

    test('mock data covers every binding and previews cleanly', () {
      final ReportTemplate t = QudsReportXmlParser()
          .parse(invoiceXml)
          .templateOrThrow;
      expect(ReportMockData.datasets(t), <String>['items']);
      expect(
        ReportMockData.rowFields(t),
        containsAll(<String>['code', 'description', 'qty', 'price', 'total']),
      );
      final Map<String, Object?> data = ReportMockData.infer(t, rows: 6);
      expect(data['invoiceNo'], 'INV-2026-001');
      final List<Object?> rows = data['items']! as List<Object?>;
      expect(rows, hasLength(6));
      final Map<String, Object?> second = rows[1]! as Map<String, Object?>;
      expect(
        second['total'],
        (second['qty']! as num) * (second['price']! as num),
      );
      final ReportDocumentLayout layout = QudsReportEngine(
        t,
        fonts: loadFonts(),
      ).layout(data);
      expect(layout.pages, isNotEmpty);
      expect(layout.warnings, isEmpty);
    });

    test('reports structural errors', () {
      final ReportParseResult r = QudsReportXmlParser().parse(
        '<QudsReport><Bands><GroupFooter height="10mm"/></Bands></QudsReport>',
      );
      expect(r.hasErrors, isTrue);
      expect(() => r.templateOrThrow, throwsA(isA<ReportTemplateException>()));
    });

    test('validate flags unknown functions', () {
      final QudsReportEngine engine = QudsReportEngine.fromXml(
        invoiceXml.replaceFirst(
          '{{SUM(items.total)}}',
          '{{TOTALIZE(items.total)}}',
        ),
      );
      final List<ReportDiagnostic> issues = engine.validate();
      expect(issues, hasLength(1));
      expect(issues.single.message, contains('TOTALIZE'));
      expect(invoiceEngine().validate(), isEmpty);
    });

    test('diagnostic paths parse to the spot they point at', () {
      const String xml = '''
<QudsReport>
  <Variables>
    <Variable name="rate" type="number" value="abc"/>
  </Variables>
  <DataSchema>
    <Table name="items"><Column name="net" expression="price *"/></Table>
  </DataSchema>
  <Bands>
    <Detail height="10mm" dataSet="items" filter="qty &gt;">
      <Text x="0" y="0" width="20mm" height="5mm" text="ok"/>
      <Text name="total" x="0" y="0" width="20mm" height="5mm"
            text="{{BOGUS(1)}}" visibleWhen="qty &gt;"/>
      <Table x="0" y="0" width="40mm">
        <Columns><Column header="A" width="20mm"/></Columns>
        <RowTemplate><Cell text="{{ (1 }}"/></RowTemplate>
      </Table>
    </Detail>
  </Bands>
</QudsReport>''';
      final ReportParseResult parsed = QudsReportXmlParser().parse(xml);
      final List<ReportDiagnostic> all = <ReportDiagnostic>[
        ...parsed.diagnostics,
        ...QudsReportEngine(parsed.template).validate(),
      ];
      ReportDiagnosticTarget at(String text) => all
          .firstWhere((ReportDiagnostic d) => d.message.contains(text))
          .target;

      final ReportDiagnosticTarget fn = at('BOGUS');
      expect(fn.place, ReportDiagnosticPlace.element);
      expect(fn.band, ReportBandKind.detail);
      expect(fn.element, 1);
      expect(fn.attribute, isNull);

      final List<ReportDiagnosticTarget> visible = all
          .map((ReportDiagnostic d) => d.target)
          .where((ReportDiagnosticTarget t) => t.attribute == 'visibleWhen')
          .toList();
      expect(visible, isNotEmpty);
      expect(
        visible.map((ReportDiagnosticTarget t) => t.key).toSet(),
        hasLength(1),
      );
      expect(visible.first.element, 1);

      final ReportDiagnosticTarget filter = all
          .map((ReportDiagnostic d) => d.target)
          .firstWhere((ReportDiagnosticTarget t) => t.attribute == 'filter');
      expect(filter.place, ReportDiagnosticPlace.band);

      final ReportDiagnosticTarget cell = all
          .map((ReportDiagnostic d) => d.target)
          .firstWhere((ReportDiagnosticTarget t) => t.part == 'Cell');
      expect(cell.element, 2);
      expect(cell.partIndex, 0);

      final ReportDiagnosticTarget rate = at('is not a number');
      expect(rate.place, ReportDiagnosticPlace.variable);
      expect(rate.name, 'rate');

      final List<ReportDiagnosticTarget> net = all
          .map((ReportDiagnostic d) => d.target)
          .where(
            (ReportDiagnosticTarget t) =>
                t.place == ReportDiagnosticPlace.dataColumn,
          )
          .toList();
      expect(net, isNotEmpty);
      expect(
        net.every((ReportDiagnosticTarget t) => t.name == 'items'),
        isTrue,
      );
      expect(
        net.every((ReportDiagnosticTarget t) => t.column == 'net'),
        isTrue,
      );

      expect(ReportDiagnosticTarget.parse('Settings/Margins').name, 'Margins');
      expect(
        ReportDiagnosticTarget.parse('').place,
        ReportDiagnosticPlace.file,
      );
      expect(
        ReportDiagnosticTarget.parse(
          'Bands/Detail/Chart "c"[4]/Series[1]@value',
        ),
        isA<ReportDiagnosticTarget>()
            .having((ReportDiagnosticTarget t) => t.element, 'element', 4)
            .having((ReportDiagnosticTarget t) => t.part, 'part', 'Series')
            .having((ReportDiagnosticTarget t) => t.partIndex, 'index', 1)
            .having((ReportDiagnosticTarget t) => t.attribute, 'attr', 'value'),
      );
      expect(
        ReportDiagnosticTarget.parse(
          'Bands/Detail/Table[0] (Table)/Footer/Cell[2]',
        ).part,
        'FooterCell',
      );

      ReportDiagnosticKind kind(String text) =>
          all.firstWhere((ReportDiagnostic d) => d.message.contains(text)).kind;
      expect(kind('BOGUS'), ReportDiagnosticKind.unknownFunction);
      expect(kind('is not a number'), ReportDiagnosticKind.invalidValue);
      expect(
        const ReportDiagnostic(
          ReportDiagnosticSeverity.warning,
          'Bands/Detail/Text[0]',
          'Extends past the page edge',
        ).kind,
        ReportDiagnosticKind.layout,
      );
      expect(
        const ReportDiagnostic(
          ReportDiagnosticSeverity.error,
          'Bands/Detail@filter',
          'ReportExpressionException: Unexpected end',
        ).summary,
        'Unexpected end',
      );
    });
  });

  group('Pagination', () {
    test('short invoice fits one page with header, footer, and summary', () {
      final ReportDocumentLayout layout = invoiceEngine().layout(
        invoiceData(3),
      );
      expect(layout.pages, hasLength(1));
      final List<String> texts = pageTexts(layout.pages.single);
      expect(texts, contains('شركة القدس للتقنية المتقدمة'));
      expect(texts, contains('التاريخ: 2026/10/10 (09:30)'));
      expect(texts, contains('فاتورة مبيعات رسمية - مرجع: INV-2026-001'));
      expect(texts, contains('الصفحة 1 من 1'));
      expect(texts, contains('1,500.000 د.ل'));
      expect(texts, contains('3000'));
      expect(
        texts,
        contains('المبلغ بالحروف: فقط ثلاثة آلاف دينار ليبي لا غير'),
      );
      expect(layout.warnings, isEmpty);
    });

    test('long invoice breaks pages and repeats headers', () {
      final ReportDocumentLayout layout = invoiceEngine().layout(
        invoiceData(80),
      );
      final int n = layout.pages.length;
      expect(n, greaterThan(2));
      final ReportTemplate t = layout.template;
      final double bodyBottom = t.pageHeight - t.margins.bottom;
      for (final ReportPageLayout page in layout.pages) {
        final List<String> texts = pageTexts(page);
        expect(texts, contains('فاتورة مبيعات رسمية - مرجع: INV-2026-001'));
        expect(texts, contains('الصفحة ${page.pageNumber} من $n'));
        expect(texts.where((String s) => s == 'الرمز'), hasLength(1));
        expect(
          texts.contains('شركة القدس للتقنية المتقدمة'),
          page.pageNumber == 1,
        );
        for (final ReportPrimitive p in page.primitives) {
          expect(p.bounds.bottom, lessThanOrEqualTo(bodyBottom + 0.5));
          expect(p.bounds.top, greaterThanOrEqualTo(t.margins.top - 0.5));
        }
      }
      final Set<String> codes = <String>{
        for (final ReportPageLayout page in layout.pages)
          for (final String s in pageTexts(page))
            if (RegExp(r'^P\d\d$').hasMatch(s)) s,
      };
      expect(codes, hasLength(80));
      final List<String> last = pageTexts(layout.pages.last);
      expect(
        last.any((String s) => s.startsWith('المبلغ بالحروف: فقط')),
        isTrue,
      );
    });

    test('rows stay ordered and table rows never overlap', () {
      final ReportDocumentLayout layout = invoiceEngine().layout(
        invoiceData(40),
      );
      final List<String> order = <String>[];
      for (final ReportPageLayout page in layout.pages) {
        final List<ReportTextPrimitive> codes = <ReportTextPrimitive>[
          for (final ReportPrimitive p in page.primitives)
            if (p is ReportTextPrimitive && RegExp(r'^P\d\d$').hasMatch(p.text))
              p,
        ];
        for (int i = 1; i < codes.length; i++) {
          expect(
            codes[i].bounds.top,
            greaterThanOrEqualTo(codes[i - 1].bounds.bottom - 0.01),
          );
        }
        order.addAll(codes.map((ReportTextPrimitive p) => p.text));
      }
      expect(order, <String>[
        for (int i = 1; i <= 40; i++) 'P${i.toString().padLeft(2, '0')}',
      ]);
    });

    test('grouping, sorting, and filtering with subtotals', () {
      const String xml = '''
<QudsReport name="Groups" pageSize="A5">
  <Bands>
    <GroupHeader height="8mm" groupBy="item.cat">
      <Text x="10mm" y="1mm" width="100mm" height="6mm">Group {{Group.Key}} ({{Group.Count}})</Text>
    </GroupHeader>
    <Detail dataSet="rows" rowHeight="6mm" sortBy="item.amount desc" filter="item.amount > 0">
      <Text x="10mm" y="0" width="60mm" height="6mm">{{item.name}}</Text>
    </Detail>
    <GroupFooter height="8mm">
      <Text x="10mm" y="1mm" width="100mm" height="6mm">Subtotal {{SUM(item.amount)}}</Text>
    </GroupFooter>
    <ReportSummary height="8mm">
      <Text x="10mm" y="1mm" width="100mm" height="6mm">Total {{SUM(rows.amount)}}</Text>
    </ReportSummary>
  </Bands>
</QudsReport>''';
      final ReportDocumentLayout layout = QudsReportEngine.fromXml(xml).layout(
        <String, Object?>{
          'rows': <Map<String, Object?>>[
            <String, Object?>{'name': 'a', 'cat': 'X', 'amount': 5},
            <String, Object?>{'name': 'b', 'cat': 'Y', 'amount': 7},
            <String, Object?>{'name': 'c', 'cat': 'X', 'amount': 9},
            <String, Object?>{'name': 'd', 'cat': 'Y', 'amount': 0},
          ],
        },
      );
      expect(pageTexts(layout.pages.single), <String>[
        'Group X (2)',
        'c',
        'a',
        'Subtotal 14',
        'Group Y (1)',
        'b',
        'Subtotal 7',
        'Total 21',
      ]);
    });

    test('a free-form detail row can take its own page', () {
      String xml({required bool before, required bool after}) =>
          '''
<QudsReport name="Cards" pageSize="A5">
  <Bands>
    <Detail dataSet="students" height="12mm"${before ? ' newPageBefore="true"' : ''}${after ? ' newPageAfter="true"' : ''}>
      <Text x="10mm" y="1mm" width="80mm" height="8mm">{{item.name}}</Text>
    </Detail>
  </Bands>
</QudsReport>''';
      final Map<String, Object?> data = <String, Object?>{
        'students': <Map<String, Object?>>[
          <String, Object?>{'name': 'Sara'},
          <String, Object?>{'name': 'Yousef'},
          <String, Object?>{'name': 'Layla'},
        ],
      };
      ReportDocumentLayout lay(String source) =>
          QudsReportEngine.fromXml(source).layout(data);

      final ReportDocumentLayout shared = lay(xml(before: false, after: false));
      expect(shared.pages, hasLength(1));
      expect(pageTexts(shared.pages.single), <String>[
        'Sara',
        'Yousef',
        'Layla',
      ]);

      for (final ReportDocumentLayout layout in <ReportDocumentLayout>[
        lay(xml(before: true, after: false)),
        lay(xml(before: false, after: true)),
      ]) {
        expect(layout.pages, hasLength(3));
        expect(pageTexts(layout.pages[0]), <String>['Sara']);
        expect(pageTexts(layout.pages[1]), <String>['Yousef']);
        expect(pageTexts(layout.pages[2]), <String>['Layla']);
      }
    });

    test('RTL templates mirror element x from the right edge', () {
      ReportTextPrimitive company(String xml) {
        final ReportDocumentLayout layout = QudsReportEngine.fromXml(
          xml,
          clock: () => fixedNow,
        ).layout(invoiceData(1));
        return layout.pages.first.primitives
            .whereType<ReportTextPrimitive>()
            .firstWhere((ReportTextPrimitive p) => p.text.startsWith('شركة'));
      }

      const double mm = 72 / 25.4;
      final ReportTextPrimitive mirrored = company(invoiceXml);
      expect(mirrored.bounds.left, closeTo((210 - 10 - 110) * mm, 0.5));
      final ReportTextPrimitive literal = company(
        invoiceXml.replaceFirst(
          'isRtl="true"',
          'isRtl="true" mirrorRtl="false"',
        ),
      );
      expect(literal.bounds.left, closeTo(10 * mm, 0.5));
    });

    test('can-grow text pushes later elements down', () {
      const String xml = '''
<QudsReport name="Grow" pageSize="A4">
  <Bands>
    <ReportHeader height="20mm">
      <Text x="20mm" y="0" width="40mm" height="6mm">{{Data.long}}</Text>
      <Text x="20mm" y="8mm" width="40mm" height="6mm">after</Text>
    </ReportHeader>
  </Bands>
</QudsReport>''';
      final ReportDocumentLayout layout = QudsReportEngine.fromXml(xml).layout(
        <String, Object?>{'long': List<String>.filled(40, 'word').join(' ')},
      );
      final List<ReportTextPrimitive> texts = layout.pages.single.primitives
          .whereType<ReportTextPrimitive>()
          .toList();
      final ReportTextPrimitive grown = texts.first;
      final ReportTextPrimitive after = texts.last;
      expect(grown.shaped.lines.length, greaterThan(1));
      expect(
        after.bounds.top,
        greaterThanOrEqualTo(grown.bounds.bottom + 2 * 72 / 25.4 - 0.5),
      );
    });
  });

  group('Exports', () {
    test('PDF embeds fonts and extracts Arabic text', () async {
      final Uint8List pdf = await invoiceEngine().exportToPdf(invoiceData(5));
      expect(ascii.decode(pdf.sublist(0, 5)), '%PDF-');
      expect(latin1.decode(pdf), contains('/FontFile2'));
      final String text = ArabicShaper.foldPresentation(
        PdfExtract.pageText(PdfFile.open(pdf), 0),
      );
      expect(text, contains('INV-2026-001'));
      // Extraction yields RTL runs in visual (painted) order.
      final String company = String.fromCharCodes(
        'شركة القدس'.runes.toList().reversed,
      );
      expect(text, contains(company));
      expect(text, contains('P01'));
    });

    test('Excel keeps numbers typed and the sheet right-to-left', () async {
      final Uint8List xlsx = await invoiceEngine().exportToExcel(
        invoiceData(4),
      );
      final List<List<String>> grid = XlsxGridReader.readSheet(xlsx);
      final int header = grid.indexWhere(
        (List<String> r) => r.contains('الرمز'),
      );
      expect(header, greaterThanOrEqualTo(0));
      expect(grid[header + 1].first, 'P01');
      expect(grid[header + 1][4], '500');
      final String sheet = partText(xlsx, '/xl/worksheets/sheet1.xml');
      expect(sheet, contains('rightToLeft="1"'));
      expect(sheet, contains('<v>1500</v>'));
      final String styles = partText(xlsx, '/xl/styles.xml');
      expect(styles, contains('د.ل'));
      expect(styles, contains('readingOrder="2"'));
      final List<String> flat = <String>[
        for (final List<String> r in grid) ...r,
      ];
      expect(flat, contains('شركة القدس للتقنية المتقدمة'));
    });

    test('Word has a repeating table header and live page fields', () async {
      final Uint8List docx = await invoiceEngine().exportToWord(invoiceData(4));
      final String doc = partText(docx, '/word/document.xml');
      expect(doc, contains('<w:tblHeader/>'));
      expect(doc, contains('<w:bidiVisual/>'));
      expect(doc, contains('شركة القدس للتقنية المتقدمة'));
      expect(doc, contains('1,500.000 د.ل'));
      for (final String part in <String>[
        '/word/document.xml',
        '/word/header1.xml',
        '/word/footer1.xml',
      ]) {
        for (final RegExpMatch cell in RegExp(
          '<w:tc>.*?</w:tc>',
          dotAll: true,
        ).allMatches(partText(docx, part))) {
          expect(cell.group(0), isNot(contains('<w:ind ')), reason: part);
        }
      }
      final String footer = partText(docx, '/word/footer1.xml');
      expect(footer, contains(' PAGE '));
      expect(footer, contains(' NUMPAGES '));
      expect(partText(docx, '/word/header1.xml'), contains('INV-2026-001'));
      final List<List<List<String>>> tables = DocxPlainReader.read(docx).tables;
      expect(
        tables.any(
          (List<List<String>> t) => t.isNotEmpty && t.first.contains('الرمز'),
        ),
        isTrue,
      );
    });
  });

  group('Charts', () {
    const String chartXml = '''
<QudsReport name="Charts" pageSize="A4" defaultFont="Liberation Sans">
  <Bands>
    <ReportHeader height="90mm">
      <Chart name="bars" x="10mm" y="0" width="120mm" height="60mm" chartType="bar" title="Sales {{Data.year}}" dataSet="Data.sales" category="Row.region" sortBy="value" sortOrder="desc" limit="3" showValues="true" valueFormat="n0">
        <Series name="Amount" value="Row.amount" color="#1F4E79"/>
        <Series name="Count" value="Row.amount"/>
      </Chart>
      <Chart name="pie" x="135mm" y="0" width="60mm" height="60mm" chartType="pie" showValues="true">
        <Point label="A" value="30" color="#FF0000"/>
        <Point label="B" value="10 + 10"/>
        <Point label="C" value="Data.extra"/>
      </Chart>
    </ReportHeader>
    <Detail dataSet="sales" height="6mm">
      <Text x="10mm" y="0" width="60mm" height="6mm">{{item.region}}</Text>
    </Detail>
  </Bands>
</QudsReport>''';

    Map<String, Object?> chartData() => <String, Object?>{
      'year': 2026,
      'extra': 50,
      'sales': <Map<String, Object?>>[
        <String, Object?>{'region': 'North', 'amount': 10},
        <String, Object?>{'region': 'South', 'amount': 40},
        <String, Object?>{'region': 'North', 'amount': 25},
        <String, Object?>{'region': 'East', 'amount': 5},
        <String, Object?>{'region': 'West', 'amount': 20},
      ],
    };

    QudsReportEngine chartEngine(String xml) => QudsReportEngine.fromXml(
      xml,
      fonts: loadFonts(),
      clock: () => fixedNow,
    );

    ReportFlowChart flowChart(ReportDocumentLayout layout, String id) {
      for (final ReportFlowEntry e in layout.flow) {
        if (e is ReportFlowBand) {
          for (final ReportFlowItem i in e.items) {
            if (i is ReportFlowChart && i.elementId == id) {
              return i;
            }
          }
        }
      }
      throw StateError('no chart $id');
    }

    String idOf(QudsReportEngine e, String name) => e.template.bands
        .expand((ReportBand b) => b.elements)
        .firstWhere((ReportElement el) => el.name == name)
        .id;

    test('parses series and points and round-trips through the writer', () {
      final QudsReportEngine engine = chartEngine(chartXml);
      expect(
        engine.diagnostics.where(
          (ReportDiagnostic d) => d.severity == ReportDiagnosticSeverity.error,
        ),
        isEmpty,
      );
      final ReportChartElement bars =
          engine.template.bands.first.elements.first as ReportChartElement;
      expect(bars.chartType, ReportChartType.bar);
      expect(bars.series.map((ReportChartSeries s) => s.name), <String>[
        'Amount',
        'Count',
      ]);
      expect(bars.sortBy, ReportChartSort.value);
      expect(bars.descending, isTrue);
      expect(bars.limit, 3);
      final QudsReportEngine again = chartEngine(engine.toXml());
      final ReportChartElement pie =
          again.template.bands.first.elements[1] as ReportChartElement;
      expect(pie.chartType, ReportChartType.pie);
      expect(pie.points.map((ReportChartPoint p) => p.value), <String>[
        '30',
        '10 + 10',
        'Data.extra',
      ]);
      expect(pie.points.first.color, '#FF0000');
      expect(again.toXml(), engine.toXml());
    });

    test('aggregates rows by category, sorts, and limits', () {
      final QudsReportEngine engine = chartEngine(chartXml);
      final ReportDocumentLayout layout = engine.layout(chartData());
      final ReportChartData bars = flowChart(layout, idOf(engine, 'bars')).data;
      expect(bars.title, 'Sales 2026');
      expect(bars.categories, <String>['South', 'North', 'West']);
      expect(bars.series.first.values, <double>[40, 35, 20]);
      final ReportChartData pie = flowChart(layout, idOf(engine, 'pie')).data;
      expect(pie.categories, <String>['A', 'B', 'C']);
      expect(pie.series.single.values, <double>[30, 20, 50]);
      expect(pie.pointColors.first, const ReportColor(0xFFFF0000));
    });

    test('average, count, and last aggregates', () {
      String xml(String aggregate) => chartXml.replaceFirst(
        'sortBy="value" sortOrder="desc" limit="3"',
        'aggregate="$aggregate"',
      );
      List<double> values(String aggregate) {
        final QudsReportEngine engine = chartEngine(xml(aggregate));
        return flowChart(
          engine.layout(chartData()),
          idOf(engine, 'bars'),
        ).data.series.first.values;
      }

      expect(values('avg'), <double>[17.5, 40, 5, 20]);
      expect(values('count'), <double>[2, 1, 1, 1]);
      expect(values('last'), <double>[25, 40, 5, 20]);
    });

    test('draws bars, wedges, and mirrored RTL plots', () {
      final QudsReportEngine engine = chartEngine(chartXml);
      final ReportPageLayout page = engine.layout(chartData()).pages.first;
      final String barsId = idOf(engine, 'bars');
      final String pieId = idOf(engine, 'pie');
      final List<ReportRectPrimitive> bars = <ReportRectPrimitive>[
        for (final ReportPrimitive p in page.primitives)
          if (p is ReportRectPrimitive &&
              p.elementId == barsId &&
              p.fill == const ReportColor(0xFF1F4E79) &&
              p.bounds.width > 10)
            p,
      ];
      expect(bars, hasLength(3));
      expect(bars.first.bounds.height, greaterThan(bars.last.bounds.height));
      final List<ReportPathPrimitive> wedges = <ReportPathPrimitive>[
        for (final ReportPrimitive p in page.primitives)
          if (p is ReportPathPrimitive && p.elementId == pieId) p,
      ];
      expect(wedges, hasLength(3));
      expect(wedges.every((ReportPathPrimitive w) => w.closed), isTrue);
      expect(
        page.primitives.whereType<ReportTextPrimitive>().map(
          (ReportTextPrimitive t) => t.text,
        ),
        containsAll(<String>['Sales 2026', '50%', '40']),
      );

      final QudsReportEngine rtl = chartEngine(
        chartXml.replaceFirst('name="Charts"', 'name="Charts" isRtl="true"'),
      );
      final String rtlBars = idOf(rtl, 'bars');
      final List<ReportRectPrimitive> mirrored = <ReportRectPrimitive>[
        for (final ReportPrimitive p
            in rtl.layout(chartData()).pages.first.primitives)
          if (p is ReportRectPrimitive &&
              p.elementId == rtlBars &&
              p.fill == const ReportColor(0xFF1F4E79) &&
              p.bounds.width > 10)
            p,
      ];
      expect(
        mirrored.first.bounds.left,
        greaterThan(mirrored.last.bounds.left),
      );
    });

    test('a chart crossing the page bottom moves to the next page whole', () {
      final String xml = chartXml
          .replaceFirst(
            '<ReportHeader height="90mm">',
            '<ReportHeader height="260mm">',
          )
          .replaceAll('y="0" width="120mm"', 'y="230mm" width="120mm"');
      final QudsReportEngine engine = chartEngine(xml);
      final ReportDocumentLayout layout = engine.layout(chartData());
      final String barsId = idOf(engine, 'bars');
      final List<int> pagesWithBars = <int>[
        for (final ReportPageLayout page in layout.pages)
          if (page.primitives.any((ReportPrimitive p) => p.elementId == barsId))
            page.pageNumber,
      ];
      expect(pagesWithBars, <int>[2]);
    });

    test('a chart below one that crosses the page does not overlap it', () {
      final String xml = chartXml
          .replaceFirst(
            '<ReportHeader height="90mm">',
            '<ReportHeader height="320mm">',
          )
          .replaceFirst(
            'name="bars" x="10mm" y="0" width="120mm" height="60mm"',
            'name="bars" x="10mm" y="230mm" width="90mm" height="40mm"',
          )
          .replaceFirst(
            'name="pie" x="135mm" y="0" width="60mm" height="60mm"',
            'name="pie" x="10mm" y="274mm" width="90mm" height="40mm"',
          );
      final QudsReportEngine engine = chartEngine(xml);
      final ReportDocumentLayout layout = engine.layout(chartData());
      ({double top, double bottom}) span(String name) {
        final String id = idOf(engine, name);
        var top = double.infinity;
        var bottom = -double.infinity;
        var page = 0;
        for (final ReportPageLayout p in layout.pages) {
          for (final ReportPrimitive prim in p.primitives) {
            if (prim.elementId != id) {
              continue;
            }
            if (page == 0) {
              page = p.pageNumber;
            }
            expect(p.pageNumber, page, reason: name);
            if (prim.bounds.top < top) {
              top = prim.bounds.top;
            }
            if (prim.bounds.bottom > bottom) {
              bottom = prim.bounds.bottom;
            }
          }
        }
        expect(page, 2, reason: name);
        return (top: top, bottom: bottom);
      }

      final ({double top, double bottom}) upper = span('bars');
      final ({double top, double bottom}) lower = span('pie');
      expect(lower.top, greaterThanOrEqualTo(upper.bottom - 0.5));
    });

    test('draws scatter, waterfall, gauge, and extruded charts', () {
      const String xml = '''
<QudsReport name="Charts" pageSize="A4">
  <Bands>
    <ReportHeader height="220mm">
      <Chart name="dots" x="10mm" y="4mm" width="80mm" height="40mm" chartType="scatter" showValues="true">
        <Point label="A" x="1" value="4" size="2"/>
        <Point label="B" x="3" value="9" size="6"/>
        <Point label="C" x="5" value="2" size="3"/>
      </Chart>
      <Chart name="steps" x="100mm" y="4mm" width="80mm" height="40mm" chartType="waterfall" lastIsTotal="true" increaseColor="#166534" decreaseColor="#991B1B" totalColor="#1E3A8A">
        <Point label="Open" value="40"/>
        <Point label="In" value="15"/>
        <Point label="Out" value="-8"/>
        <Point label="Close" value="47" total="true"/>
      </Chart>
      <Chart name="dial" x="10mm" y="50mm" width="50mm" height="36mm" chartType="gauge" axisMin="0" axisMax="100" target="80" bands="3" hole="0.62">
        <Point label="Score" value="64"/>
      </Chart>
      <Chart name="solid" x="70mm" y="50mm" width="50mm" height="36mm" chartType="extrudedBar" depth="16" skew="28">
        <Point label="Q1" value="12"/>
        <Point label="Q2" value="18"/>
        <Point label="Q3" value="9"/>
      </Chart>
      <Chart name="mix" x="130mm" y="50mm" width="60mm" height="36mm" chartType="combo" dataSet="Data.months" category="Row.m">
        <Series name="Revenue" value="Row.revenue" style="column"/>
        <Series name="Margin" value="Row.margin" style="line" secondary="true"/>
      </Chart>
    </ReportHeader>
  </Bands>
</QudsReport>''';
      final QudsReportEngine engine = chartEngine(xml);
      expect(
        engine.diagnostics.where(
          (ReportDiagnostic d) => d.severity == ReportDiagnosticSeverity.error,
        ),
        isEmpty,
      );
      final ReportChartElement dots =
          engine.template.bands.first.elements.first as ReportChartElement;
      expect(dots.chartType, ReportChartType.scatter);
      expect(dots.points.first.x, '1');
      expect(engine.toXml(), contains('chartType="waterfall"'));
      expect(engine.toXml(), contains('secondary="true"'));
      final ReportDocumentLayout layout = engine.layout(<String, Object?>{
        'months': <Map<String, Object?>>[
          <String, Object?>{'m': 'Jan', 'revenue': 20, 'margin': 4},
          <String, Object?>{'m': 'Feb', 'revenue': 28, 'margin': 7},
          <String, Object?>{'m': 'Mar', 'revenue': 18, 'margin': 3},
        ],
      });
      int painted(String name) {
        final String id = idOf(engine, name);
        return layout.pages.first.primitives
            .where((ReportPrimitive p) => p.elementId == id)
            .length;
      }

      expect(painted('dots'), greaterThan(3));
      expect(painted('steps'), greaterThan(3));
      expect(painted('dial'), greaterThan(2));
      expect(painted('solid'), greaterThan(3));
      expect(painted('mix'), greaterThan(3));
      expect(
        flowChart(layout, idOf(engine, 'dots')).data.toDrawingml(),
        contains('scatterChart'),
      );
      expect(
        flowChart(layout, idOf(engine, 'solid')).data.toDrawingml(),
        contains('bar3DChart'),
      );
    });

    test('exports vector PDF paths and native Word / Excel charts', () async {
      final QudsReportEngine engine = chartEngine(chartXml);
      final Uint8List pdf = await engine.exportToPdf(chartData());
      expect(ascii.decode(pdf.sublist(0, 5)), '%PDF-');

      final Uint8List docx = await engine.exportToWord(chartData());
      final String doc = partText(docx, '/word/document.xml');
      expect(doc, contains('drawingml/2006/chart'));
      final String wordChart = partText(docx, '/word/charts/chart1.xml');
      expect(wordChart, contains('<c:barChart>'));
      expect(wordChart, contains('South'));
      expect(
        partText(docx, '/word/charts/chart2.xml'),
        contains('<c:pieChart>'),
      );

      final Uint8List xlsx = await engine.exportToExcel(chartData());
      final String sheet = partText(xlsx, '/xl/worksheets/sheet1.xml');
      expect(sheet, contains('<drawing r:id="rIdDrawing1"/>'));
      expect(
        partText(xlsx, '/xl/drawings/drawing1.xml'),
        contains('r:id="rIdChart2"'),
      );
      expect(partText(xlsx, '/xl/charts/chart1.xml'), contains('<c:barChart>'));
      final List<List<String>> grid = XlsxGridReader.readSheet(xlsx);
      final int header = grid.indexWhere(
        (List<String> r) => r.contains('Amount'),
      );
      expect(header, greaterThanOrEqualTo(0));
      expect(grid[header + 1], containsAllInOrder(<String>['South', '40']));
    });

    test('colors the world atlas by country code and labels wide regions', () {
      const String xml = '''
<QudsReport name="Map" pageSize="A4" defaultFont="Liberation Sans">
  <Bands>
    <ReportHeader height="120mm">
      <Chart name="map" x="10mm" y="0" width="180mm" height="110mm" chartType="map" dataSet="Data.rows" category="Row.code" valueFormat="n0" showValues="true">
        <Series name="Amount" value="Row.amount"/>
      </Chart>
    </ReportHeader>
  </Bands>
</QudsReport>''';
      final ReportShapeFeature? libya = WorldCountries.layer.find('LY');
      expect(libya, isNotNull);
      expect(WorldCountries.layer.find('LBY'), same(libya));
      expect(WorldCountries.layer.find('Libya'), same(libya));
      expect(WorldCountries.layer.find('ليبيا'), same(libya));
      expect(WorldCountries.layer.find('FR'), isNotNull);

      final QudsReportEngine engine = chartEngine(xml);
      expect(
        engine.template.bands.first.elements.first,
        isA<ReportChartElement>(),
      );
      final ReportChartElement chart =
          engine.template.bands.first.elements.first as ReportChartElement;
      expect(chart.chartType, ReportChartType.shapeMap);
      expect(chart.shape, 'world');
      expect(chartEngineRoundTrip(engine), engine.toXml());

      final ReportPageLayout page = engine
          .layout(<String, Object?>{
            'rows': <Map<String, Object?>>[
              <String, Object?>{'code': 'US', 'amount': 10},
              <String, Object?>{'code': 'CN', 'amount': 90},
              <String, Object?>{'code': 'Libya', 'amount': 1},
              <String, Object?>{'code': 'LY', 'amount': 40},
            ],
          })
          .pages
          .first;
      final String id = chart.id;
      final List<ReportPathPrimitive> regions = <ReportPathPrimitive>[
        for (final ReportPrimitive p in page.primitives)
          if (p is ReportPathPrimitive && p.elementId == id && p.fill != null)
            p,
      ];
      expect(regions.length, greaterThan(100));
      const ReportColor low = ReportColor(0xFFDEEBF7);
      const ReportColor high = ReportColor(0xFF08306B);
      const ReportColor empty = ReportColor(0xFFE4E4E4);
      expect(
        regions.where((ReportPathPrimitive p) => p.fill == low),
        isNotEmpty,
      );
      expect(
        regions.where((ReportPathPrimitive p) => p.fill == high),
        isNotEmpty,
      );
      expect(
        regions.where((ReportPathPrimitive p) => p.fill == empty),
        isNotEmpty,
      );
      final Iterable<String> labels = page.primitives
          .whereType<ReportTextPrimitive>()
          .where((ReportTextPrimitive t) => t.elementId == id)
          .map((ReportTextPrimitive t) => t.text);
      expect(labels, containsAll(<String>['10', '90']));
      expect(
        labels.any(
          (String t) => t == 'US' || t.contains('United States') || t == 'USA',
        ),
        isTrue,
      );
      expect(labels.any((String t) => t == 'CN' || t == 'China'), isTrue);
    });

    test('keeps a district boundary smooth and refuses projected metres', () {
      final ReportShapeLayer layer = ReportShapeLayer.parse(
        Uint8List.fromList(
          utf8.encode(
            '{"type":"FeatureCollection","features":[{"type":"Feature",'
            '"properties":{"code":"A"},"geometry":{"type":"Polygon",'
            '"coordinates":[[[35.2,31.5],[35.200001,31.500001],'
            '[35.21,31.51],[35.2,31.5]]]}}]}',
          ),
        ),
        keyField: 'code',
      );
      final ReportShapeRing ring = ReportShapeLayer.decode(
        layer.encode(),
      ).features.single.rings.single;
      expect((ring.lonLat[2] - 35.200001).abs(), lessThan(0.000002));
      expect((ring.lonLat[3] - 31.500001).abs(), lessThan(0.000002));
      expect(
        () => ReportShapeLayer.read(
          _polygonShapefile(<List<(double, double)>>[
            <(double, double)>[
              (200000, 600000),
              (200100, 600000),
              (200100, 600100),
              (200000, 600000),
            ],
          ]),
        ),
        throwsA(isA<ReportShapeException>()),
      );
    });

    test('paints each region from a color column joined by its key', () {
      const String xml = '''
<QudsReport name="Zones" pageSize="A4" defaultFont="Liberation Sans">
  <Bands>
    <ReportHeader height="80mm">
      <Chart name="zones" x="10mm" y="0" width="160mm" height="70mm" chartType="shapeMap" shape="zones" dataSet="Data.rows" category="Row.code" regionColor="Row.color">
        <Series name="Amount" value="Row.n"/>
      </Chart>
    </ReportHeader>
  </Bands>
</QudsReport>''';
      final Uint8List qmap = ReportShapeLayer.parse(
        Uint8List.fromList(
          utf8.encode('''
{"type":"FeatureCollection","features":[
  {"type":"Feature","properties":{"code":"W","NAME":"West"},
   "geometry":{"type":"Polygon","coordinates":[[[0,0],[20,0],[20,15],[0,0]]]}},
  {"type":"Feature","properties":{"code":"E","NAME":"East"},
   "geometry":{"type":"Polygon","coordinates":[[[40,0],[70,0],[70,25],[40,0]]]}}
]}'''),
        ),
        keyField: 'code',
      ).encode();
      final QudsReportEngine engine = QudsReportEngine.fromXml(
        xml,
        fonts: loadFonts(),
        shapes: <String, Uint8List>{'zones': qmap},
      );
      expect(chartEngineRoundTrip(engine), engine.toXml());
      final ReportPageLayout page = engine
          .layout(<String, Object?>{
            'rows': <Map<String, Object?>>[
              <String, Object?>{'code': 'W', 'n': 5, 'color': '#C0392B'},
              <String, Object?>{'code': 'E', 'n': 50, 'color': 'green'},
            ],
          })
          .pages
          .first;
      final Set<int> fills = <int>{
        for (final ReportPathPrimitive p
            in page.primitives.whereType<ReportPathPrimitive>())
          if (p.elementId == idOf(engine, 'zones') &&
              p.fill != null &&
              p.fill!.argb != 0xFFE7F1F8)
            p.fill!.argb,
      };
      expect(fills, containsAll(<int>[0xFFC0392B, 0xFF008000]));
      expect(fills, isNot(contains(0xFFDEEBF7)));
    });

    test('draws the chosen attribute and keeps every column', () {
      final ReportShapeLayer layer = ReportShapeLayer.parse(
        Uint8List.fromList(
          utf8.encode('''
{"type":"FeatureCollection","features":[
  {"type":"Feature","properties":{"code":"W","NAME":"West","title":"Ramallah"},
   "geometry":{"type":"Polygon","coordinates":[[[0,0],[20,0],[20,15],[0,0]]]}},
  {"type":"Feature","properties":{"code":"E","NAME":"East","title":"Nablus"},
   "geometry":{"type":"Polygon","coordinates":[[[40,0],[70,0],[70,25],[40,0]]]}}
]}'''),
        ),
        keyField: 'code',
      );
      final ReportShapeLayer stored = ReportShapeLayer.decode(layer.encode());
      expect(stored.fields, <String>['code', 'NAME', 'title']);
      expect(stored.features.first.valueOf('title'), 'Ramallah');
      const String xml = '''
<QudsReport name="Zones" pageSize="A4" defaultFont="Liberation Sans">
  <Bands>
    <ReportHeader height="80mm">
      <Chart name="zones" x="10mm" y="0" width="160mm" height="70mm" chartType="shapeMap" shape="zones" dataSet="Data.rows" category="Row.code" labelField="title" showLegend="false">
        <Series name="Amount" value="Row.n"/>
      </Chart>
    </ReportHeader>
  </Bands>
</QudsReport>''';
      final QudsReportEngine engine = QudsReportEngine.fromXml(
        xml,
        fonts: loadFonts(),
        shapes: <String, Uint8List>{'zones': stored.encode()},
      );
      expect(chartEngineRoundTrip(engine), engine.toXml());
      expect(engine.toXml(), contains('labelField="title"'));
      final ReportPageLayout page = engine
          .layout(<String, Object?>{
            'rows': <Map<String, Object?>>[
              <String, Object?>{'code': 'W', 'n': 5},
              <String, Object?>{'code': 'E', 'n': 50},
            ],
          })
          .pages
          .first;
      final Iterable<String> labels = page.primitives
          .whereType<ReportTextPrimitive>()
          .map((ReportTextPrimitive t) => t.text);
      expect(labels, containsAll(<String>['Ramallah', 'Nablus']));
      expect(labels, isNot(contains('West')));
    });

    test('a label formula joins text and a chosen field is not the key', () {
      final QudsExpressionEngine expressions = QudsExpressionEngine();
      final ReportScope scope = ReportScope(
        data: ReportRecord.empty,
        variables: ReportRecord.empty,
        system: ReportSystemInfo(now: DateTime.utc(2020)),
        row: ReportValue.from(<String, Object?>{
          'name': 'رام الله',
          'code': '18',
        }),
      );
      expect(
        expressions.interpolate('{{CONCAT(Row.name, "\\n", Row.code)}}', scope),
        'رام الله\n18',
      );
      expect(
        expressions.interpolate('{{Row.name & " " & Row.code}}', scope),
        'رام الله 18',
      );
      expect(
        expressions.interpolate('{{Row.name + " " + Row.code}}', scope),
        'رام الله 18',
      );

      final ReportShapeLayer layer = ReportShapeLayer.parse(
        Uint8List.fromList(
          utf8.encode('''
{"type":"FeatureCollection","features":[
  {"type":"Feature","properties":{"code":"W","title":"Short"},
   "geometry":{"type":"Polygon","coordinates":[[[0,0],[30,0],[30,15],[0,0]]]}},
  {"type":"Feature","properties":{"code":"99","title":"AVeryLongNeighborhoodNameThatCannotFitInside"},
   "geometry":{"type":"Polygon","coordinates":[[[32,0],[40,0],[40,8],[32,0]]]}}
]}'''),
        ),
        keyField: 'code',
      );
      const String xml = '''
<QudsReport name="Zones" pageSize="A4" defaultFont="Liberation Sans">
  <Bands>
    <ReportHeader height="80mm">
      <Chart name="zones" x="10mm" y="0" width="160mm" height="70mm" chartType="shapeMap" shape="zones" dataSet="Data.rows" category="Row.code" labelField="{{CONCAT(Row.title, '\\n', 'حي')}}" showLegend="false" showValues="false">
        <Series name="Amount" value="Row.n"/>
      </Chart>
    </ReportHeader>
  </Bands>
</QudsReport>''';
      final QudsReportEngine engine = QudsReportEngine.fromXml(
        xml,
        fonts: loadFonts(),
        shapes: <String, Uint8List>{'zones': layer.encode()},
      );
      final Iterable<String> labels = engine
          .layout(<String, Object?>{
            'rows': <Map<String, Object?>>[
              <String, Object?>{'code': 'W', 'title': 'Short', 'n': 5},
              <String, Object?>{
                'code': '99',
                'title': 'AVeryLongNeighborhoodNameThatCannotFitInside',
                'n': 1,
              },
            ],
          })
          .pages
          .first
          .primitives
          .whereType<ReportTextPrimitive>()
          .map((ReportTextPrimitive t) => t.text);
      expect(labels, containsAll(<String>['Short', 'حي']));
      expect(labels, isNot(contains('99')));
      expect(
        labels,
        isNot(contains('AVeryLongNeighborhoodNameThatCannotFitInside')),
      );
    });

    test('a label formula reads map columns directly and through Row', () {
      expect(QudsExpressionEngine.isLabelFormula('title'), isFalse);
      expect(QudsExpressionEngine.isLabelFormula('name'), isFalse);
      expect(
        QudsExpressionEngine.isLabelFormula('CONCAT(name, "\\n", code)'),
        isTrue,
      );
      expect(QudsExpressionEngine.isLabelFormula('Row.name'), isTrue);
      expect(
        QudsExpressionEngine.isLabelFormula(
          '{{CONCAT(Row.name, "\\n", code)}}',
        ),
        isTrue,
      );

      final ReportShapeLayer layer = ReportShapeLayer.parse(
        Uint8List.fromList(
          utf8.encode('''
{"type":"FeatureCollection","features":[
  {"type":"Feature","properties":{"code":"18","name":"Ramallah"},
   "geometry":{"type":"Polygon","coordinates":[[[0,0],[30,0],[30,15],[0,0]]]}},
  {"type":"Feature","properties":{"code":"99","name":"Nablus"},
   "geometry":{"type":"Polygon","coordinates":[[[32,0],[62,0],[62,15],[32,0]]]}}
]}'''),
        ),
        keyField: 'code',
      );
      Iterable<String> draw(String labelField) {
        final String xml =
            '''
<QudsReport name="Zones" pageSize="A4" defaultFont="Liberation Sans">
  <Bands>
    <ReportHeader height="80mm">
      <Chart name="zones" x="10mm" y="0" width="160mm" height="70mm" chartType="shapeMap" shape="zones" dataSet="Data.rows" category="Row.code" labelField="$labelField" showLegend="false" showValues="false">
        <Series name="Amount" value="Row.n"/>
      </Chart>
    </ReportHeader>
  </Bands>
</QudsReport>''';
        return QudsReportEngine.fromXml(
              xml,
              fonts: loadFonts(),
              shapes: <String, Uint8List>{'zones': layer.encode()},
            )
            .layout(<String, Object?>{
              'rows': <Map<String, Object?>>[
                <String, Object?>{'code': '18', 'n': 5},
                <String, Object?>{'code': '99', 'n': 1},
              ],
            })
            .pages
            .first
            .primitives
            .whereType<ReportTextPrimitive>()
            .map((ReportTextPrimitive t) => t.text);
      }

      final Iterable<String> direct = draw("CONCAT(name, '\\n', code)");
      expect(direct, containsAll(<String>['Ramallah', '18', 'Nablus', '99']));
      final Iterable<String> throughRow = draw(
        "CONCAT(Row.name, ' - ', Row.code)",
      );
      expect(throughRow, containsAll(<String>['Ramallah - 18', 'Nablus - 99']));
    });

    test('a map label still draws shape columns when the data set differs', () {
      final ReportShapeLayer layer = ReportShapeLayer.parse(
        Uint8List.fromList(
          utf8.encode('''
{"type":"FeatureCollection","features":[
  {"type":"Feature","properties":{"Name":"Ramallah","SHAPE_Area":"12"},
   "geometry":{"type":"Polygon","coordinates":[[[0,0],[40,0],[40,20],[0,0]]]}},
  {"type":"Feature","properties":{"Name":"Nablus","SHAPE_Area":"9"},
   "geometry":{"type":"Polygon","coordinates":[[[42,0],[80,0],[80,20],[42,0]]]}}
]}'''),
        ),
        keyField: 'Name',
      );
      const String xml = '''
<QudsReport name="Zones" pageSize="A4" defaultFont="Liberation Sans">
  <Bands>
    <ReportHeader height="80mm">
      <Chart name="zones" x="10mm" y="0" width="160mm" height="70mm" chartType="shapeMap" shape="zones" dataSet="Data.items" category="Item.name" labelField="{{Concat(Name, '\\n', SHAPE_Area)}}" showLegend="false" showValues="false">
        <Series name="Qty" value="Item.qty"/>
      </Chart>
    </ReportHeader>
  </Bands>
</QudsReport>''';
      final Iterable<String> labels =
          QudsReportEngine.fromXml(
                xml,
                fonts: loadFonts(),
                shapes: <String, Uint8List>{'zones': layer.encode()},
              )
              .layout(<String, Object?>{
                'items': <Map<String, Object?>>[
                  <String, Object?>{'name': 'Pen', 'qty': 2},
                ],
              })
              .pages
              .first
              .primitives
              .whereType<ReportTextPrimitive>()
              .map((ReportTextPrimitive t) => t.text);
      expect(labels, containsAll(<String>['Ramallah', '12', 'Nablus', '9']));
      expect(labels, isNot(contains('Pen')));
    });

    test('a calculated map column is drawn as the region label', () {
      final ReportShapeLayer layer = ReportShapeLayer.parse(
        Uint8List.fromList(
          utf8.encode('''
{"type":"FeatureCollection","features":[
  {"type":"Feature","properties":{"Name":"Ramallah","SHAPE_Area":"12"},
   "geometry":{"type":"Polygon","coordinates":[[[0,0],[40,0],[40,20],[0,0]]]}},
  {"type":"Feature","properties":{"Name":"Nablus","SHAPE_Area":"9"},
   "geometry":{"type":"Polygon","coordinates":[[[42,0],[80,0],[80,20],[42,0]]]}}
]}'''),
        ),
        keyField: 'Name',
      );
      const String xml = '''
<QudsReport name="Zones" pageSize="A4" defaultFont="Liberation Sans">
  <DataSchema>
    <Table name="districts">
      <Column name="lbl" type="text" expression="Name &amp; ' ' &amp; SHAPE_Area"/>
    </Table>
  </DataSchema>
  <Bands>
    <ReportHeader height="80mm">
      <Chart name="zones" x="10mm" y="0" width="160mm" height="70mm" chartType="shapeMap" shape="zones" dataSet="Data.items" category="Item.name" labelField="lbl" showLegend="false" showValues="false">
        <Series name="Qty" value="Item.qty"/>
      </Chart>
    </ReportHeader>
  </Bands>
</QudsReport>''';
      final Iterable<String> labels =
          QudsReportEngine.fromXml(
                xml,
                fonts: loadFonts(),
                shapes: <String, Uint8List>{'zones': layer.encode()},
              )
              .layout(<String, Object?>{
                'items': <Map<String, Object?>>[
                  <String, Object?>{'name': 'Pen', 'qty': 2},
                ],
              })
              .pages
              .first
              .primitives
              .whereType<ReportTextPrimitive>()
              .map((ReportTextPrimitive t) => t.text);
      expect(labels, containsAll(<String>['Ramallah 12', 'Nablus 9']));
      expect(labels, isNot(contains('Ramallah')));
      expect(labels, isNot(contains('Pen')));
    });

    test('a map font is shared by the title, the legend, and the labels', () {
      final ReportShapeLayer layer = ReportShapeLayer.parse(
        Uint8List.fromList(
          utf8.encode('''
{"type":"FeatureCollection","features":[
  {"type":"Feature","properties":{"Name":"Ramallah","code":"W"},
   "geometry":{"type":"Polygon","coordinates":[[[0,0],[40,0],[40,20],[0,0]]]}},
  {"type":"Feature","properties":{"Name":"Nablus","code":"E"},
   "geometry":{"type":"Polygon","coordinates":[[[42,0],[80,0],[80,20],[42,0]]]}}
]}'''),
        ),
        keyField: 'code',
        nameField: 'Name',
      );
      const String xml = '''
<QudsReport name="Zones" pageSize="A4" defaultFont="Liberation Sans">
  <Bands>
    <ReportHeader height="80mm">
      <Chart name="zones" x="10mm" y="0" width="160mm" height="70mm" chartType="shapeMap" shape="zones" dataSet="Data.rows" category="Row.code" labelField="Name" title="Map" fontSize="16" fontFamily="Liberation Serif" bold="true" italic="true" color="#112233" showValues="false">
        <Series name="Qty" value="Row.n"/>
      </Chart>
    </ReportHeader>
  </Bands>
</QudsReport>''';
      final List<ReportTextPrimitive> texts =
          QudsReportEngine.fromXml(
                xml,
                fonts: loadFonts(),
                shapes: <String, Uint8List>{'zones': layer.encode()},
              )
              .layout(<String, Object?>{
                'rows': <Map<String, Object?>>[
                  <String, Object?>{'code': 'W', 'n': 5},
                  <String, Object?>{'code': 'E', 'n': 9},
                ],
              })
              .pages
              .first
              .primitives
              .whereType<ReportTextPrimitive>()
              .toList();
      expect(
        texts.map((ReportTextPrimitive t) => t.text),
        containsAll(<String>['Map', 'Ramallah', 'Nablus', '5', '9']),
      );
      for (final ReportTextPrimitive text in texts) {
        expect(text.font.family, 'Liberation Serif');
        expect(text.font.size, 16);
        expect(text.font.bold, isTrue);
        expect(text.font.italic, isTrue);
        expect(text.color.argb, 0xFF112233);
      }
    });

    test('title, labels, and the legend each keep their own font', () {
      final ReportShapeLayer layer = ReportShapeLayer.parse(
        Uint8List.fromList(
          utf8.encode('''
{"type":"FeatureCollection","features":[
  {"type":"Feature","properties":{"Name":"Ramallah","code":"W"},
   "geometry":{"type":"Polygon","coordinates":[[[0,0],[40,0],[40,20],[0,0]]]}},
  {"type":"Feature","properties":{"Name":"Nablus","code":"E"},
   "geometry":{"type":"Polygon","coordinates":[[[42,0],[80,0],[80,20],[42,0]]]}}
]}'''),
        ),
        keyField: 'code',
      );
      const String xml = '''
<QudsReport name="Zones" pageSize="A4" defaultFont="Liberation Sans">
  <Bands>
    <ReportHeader height="80mm">
      <Chart name="zones" x="10mm" y="0" width="160mm" height="70mm" chartType="shapeMap" shape="zones" dataSet="Data.rows" category="Row.code" labelField="Name" title="Map" titleSize="18" titleBold="true" titleColor="#112233" labelSize="11" labelItalic="true" labelColor="#334455" legendSize="8" legendColor="#667788" showValues="false">
        <Series name="Qty" value="Row.n"/>
      </Chart>
    </ReportHeader>
  </Bands>
</QudsReport>''';
      final List<ReportTextPrimitive> texts =
          QudsReportEngine.fromXml(
                xml,
                fonts: loadFonts(),
                shapes: <String, Uint8List>{'zones': layer.encode()},
              )
              .layout(<String, Object?>{
                'rows': <Map<String, Object?>>[
                  <String, Object?>{'code': 'W', 'n': 5},
                  <String, Object?>{'code': 'E', 'n': 9},
                ],
              })
              .pages
              .first
              .primitives
              .whereType<ReportTextPrimitive>()
              .toList();
      ReportTextPrimitive text(String value) =>
          texts.firstWhere((ReportTextPrimitive t) => t.text == value);
      expect(text('Map').font.size, 18);
      expect(text('Map').font.bold, isTrue);
      expect(text('Map').color.argb, 0xFF112233);
      expect(text('Ramallah').font.size, 11);
      expect(text('Ramallah').font.italic, isTrue);
      expect(text('Ramallah').color.argb, 0xFF334455);
      expect(text('5').font.size, 8);
      expect(text('5').color.argb, 0xFF667788);
      expect(text('9').font.size, 8);
    });

    test(
      'imports a shapefile and GeoJSON and stores the layer in the package',
      () {
        final Uint8List shp = _polygonShapefile(<List<(double, double)>>[
          <(double, double)>[(0, 0), (30, 0), (30, 20), (0, 20), (0, 0)],
          <(double, double)>[(10, 5), (10, 12), (18, 12), (18, 5), (10, 5)],
        ]);
        final Uint8List dbf = _dbf('ISO_A2', 'ZZ');
        final ReportShapeLayer fromShp = ReportShapeLayer.parseShapefile(
          shp,
          attributes: dbf,
        );
        expect(fromShp.features.single.key, 'ZZ');
        expect(fromShp.features.single.rings, hasLength(2));
        expect(
          fromShp.features.single.rings.where((ReportShapeRing r) => r.hole),
          hasLength(1),
        );
        final ReportShapeLayer round = ReportShapeLayer.decode(
          fromShp.encode(),
        );
        expect(round.find('zz')?.key, 'ZZ');
        expect(round.features.single.rings[1].hole, isTrue);

        final ReportShapeLayer fromJson = ReportShapeLayer.parse(
          Uint8List.fromList(
            utf8.encode('''
{"type":"FeatureCollection","features":[
  {"type":"Feature","properties":{"NAME":"West","code":"W"},
   "geometry":{"type":"Polygon","coordinates":[[[0,0],[20,0],[20,15],[0,0]]]}},
  {"type":"Feature","properties":{"NAME":"East","code":"E"},
   "geometry":{"type":"Polygon","coordinates":[[[40,0],[70,0],[70,25],[40,0]]]}}
]}'''),
          ),
          keyField: 'code',
        );
        expect(fromJson.find('West')?.key, 'W');
        expect(fromJson.find('E')?.label, 'East');

        const String xml = '''
<QudsReport name="Zones" pageSize="A4" defaultFont="Liberation Sans">
  <Bands>
    <ReportHeader height="80mm">
      <Chart name="zones" x="10mm" y="0" width="160mm" height="70mm" chartType="shapeMap" shape="zones" dataSet="Data.rows" category="Row.code" valueFormat="n0">
        <Series name="Amount" value="Row.n"/>
      </Chart>
    </ReportHeader>
  </Bands>
</QudsReport>''';
        final Uint8List qmap = fromJson.encode();
        final QudsReportEngine engine = QudsReportEngine.fromXml(
          xml,
          fonts: loadFonts(),
          shapes: <String, Uint8List>{'zones': qmap},
        );
        final ReportPageLayout page = engine
            .layout(<String, Object?>{
              'rows': <Map<String, Object?>>[
                <String, Object?>{'code': 'W', 'n': 5},
                <String, Object?>{'code': 'East', 'n': 50},
              ],
            })
            .pages
            .first;
        final String id = idOf(engine, 'zones');
        final Set<int> fills = <int>{
          for (final ReportPathPrimitive p
              in page.primitives.whereType<ReportPathPrimitive>())
            if (p.elementId == id &&
                p.fill != null &&
                p.fill!.argb != 0xFFE7F1F8)
              p.fill!.argb,
        };
        expect(fills, containsAll(<int>[0xFFDEEBF7, 0xFF08306B]));
        expect(
          page.primitives.whereType<ReportTextPrimitive>().map(
            (ReportTextPrimitive t) => t.text,
          ),
          containsAll(<String>['West', 'East']),
        );

        final Uint8List packed = ReportPackage(
          xml: xml,
          shapes: <String, Uint8List>{'zones': qmap},
        ).encode();
        final ReportPackage back = ReportPackage.decode(packed);
        expect(back.shapes.keys, <String>['zones']);
        expect(
          ReportShapeLayer.decode(back.shapes['zones']!).find('W')?.label,
          'West',
        );
        final QudsReportEngine opened = QudsReportEngine.fromPackage(
          packed,
          fonts: loadFonts(),
        );
        expect(
          flowChart(
            opened.layout(<String, Object?>{
              'rows': <Map<String, Object?>>[
                <String, Object?>{'code': 'W', 'n': 5},
              ],
            }),
            idOf(opened, 'zones'),
          ).data.shapes?.features,
          hasLength(2),
        );
      },
    );
  });

  group('Ready-made templates', () {
    for (final ReportTemplateInfo info in ReportTemplates.all) {
      test('${info.id} parses, validates, and exports', () async {
        final QudsReportEngine engine = QudsReportEngine.fromPackage(
          info.package().encode(),
          fonts: loadFonts(),
          clock: () => fixedNow,
        );
        final List<ReportDiagnostic> errors = <ReportDiagnostic>[
          for (final ReportDiagnostic d in <ReportDiagnostic>[
            ...engine.diagnostics,
            ...engine.validate(),
          ])
            if (d.severity == ReportDiagnosticSeverity.error) d,
        ];
        expect(errors, isEmpty);
        expect(engine.template.isRtl, info.rtl);
        final Map<String, Object?> data = info.sampleData();
        final ReportDocumentLayout layout = engine.layout(data);
        expect(layout.warnings, isEmpty);
        final List<String> texts = <String>[
          for (final ReportPageLayout p in layout.pages) ...pageTexts(p),
        ];
        expect(texts.where((String t) => t.contains('#ERR')), isEmpty);
        expect(
          ascii.decode((await engine.exportToPdf(data)).sublist(0, 5)),
          '%PDF-',
        );
        expect(await engine.exportToExcel(data), isNotEmpty);
        expect(await engine.exportToWord(data), isNotEmpty);
        expect(chartEngineRoundTrip(engine), engine.toXml());
      });
    }
  });

  group('Class certificates', () {
    test('each student is a page in preview and in Word', () async {
      final ReportTemplateInfo info = ReportTemplates.byId(
        'class_certificate_ar',
      )!;
      final QudsReportEngine engine = QudsReportEngine.fromPackage(
        info.package().encode(),
        fonts: loadFonts(),
        clock: () => fixedNow,
      );
      final Map<String, Object?> data = info.sampleData();
      final List<Object?> students = data['students']! as List<Object?>;
      final ReportDocumentLayout layout = engine.layout(data);
      expect(layout.pages, hasLength(students.length));
      expect(layout.warnings, isEmpty);
      expect(students.length, greaterThan(1));
      for (int i = 0; i < students.length; i++) {
        final String name =
            (students[i]! as Map<String, Object?>)['name']! as String;
        final List<String> texts = pageTexts(layout.pages[i]);
        expect(texts, contains(name));
        expect(texts, contains('صفحة ${i + 1} من ${students.length}'));
        for (int j = 0; j < students.length; j++) {
          if (i == j) {
            continue;
          }
          final String other =
              (students[j]! as Map<String, Object?>)['name']! as String;
          expect(texts, isNot(contains(other)));
        }
      }
      final String word = partText(
        await engine.exportToWord(data),
        '/word/document.xml',
      );
      expect('w:type="page"'.allMatches(word), hasLength(students.length - 1));
      final ReportTemplateInfo english = ReportTemplates.byId(
        'class_certificate_en',
      )!;
      final ReportDocumentLayout en = QudsReportEngine.fromPackage(
        english.package().encode(),
        fonts: loadFonts(),
        clock: () => fixedNow,
      ).layout(english.sampleData());
      expect(en.pages, hasLength(students.length));
      expect(pageTexts(en.pages.first), contains('Sara Ahmed Al-Mansouri'));
      expect(pageTexts(en.pages.last), contains('Kareem Saleh Al-Zlitni'));
    });
  });

  group('Template catalog', () {
    bool isPng(Uint8List b) =>
        b.length > 8 &&
        b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4E &&
        b[3] == 0x47;

    test('every family has one Arabic and one English version', () {
      final Set<String> ids = <String>{
        for (final ReportTemplateInfo t in ReportTemplates.all) t.id,
      };
      expect(ids, hasLength(ReportTemplates.all.length));
      expect(ReportTemplates.families, hasLength(11));
      for (final String family in ReportTemplates.families) {
        final List<ReportTemplateInfo> v = ReportTemplates.variants(family);
        expect(
          v.map((ReportTemplateInfo t) => t.language).toSet(),
          ReportTemplateLanguage.values.toSet(),
          reason: family,
        );
        expect(v, hasLength(2), reason: family);
        final ReportTemplateInfo ar = ReportTemplates.find(
          family,
          ReportTemplateLanguage.arabic,
        )!;
        final ReportTemplateInfo en = ReportTemplates.counterpart(ar)!;
        expect(en.language, ReportTemplateLanguage.english);
        expect(ReportTemplates.counterpart(en), same(ar));
        expect(ar.rtl, isTrue);
        expect(en.rtl, isFalse);
        expect(ar.category, en.category);
        expect(ar.familyTitle, en.familyTitle);
        expect(ar.familyTitleFor(arabic: true), en.familyTitleAr);
        expect(ar.familyTitle, isNot(contains('(')));
        expect(
          ar.sampleData().keys.toSet(),
          en.sampleData().keys.toSet(),
          reason: family,
        );
      }
    });

    test('categories cover the catalog and have bilingual titles', () {
      final int total = ReportTemplateCategory.values.fold(
        0,
        (int sum, ReportTemplateCategory c) =>
            sum + ReportTemplates.inCategory(c).length,
      );
      expect(total, ReportTemplates.all.length);
      expect(
        ReportTemplateCategory.hr.titleFor(arabic: true),
        'الموارد البشرية',
      );
      expect(ReportTemplateCategory.sales.titleFor(arabic: false), 'Sales');
      expect(ReportTemplates.byId('invoice_en')!.family, 'commercial_invoice');
    });

    test('the chart gallery draws every type and a country map', () {
      final ReportTemplateInfo info = ReportTemplates.byId('chart_gallery_en')!;
      final QudsReportEngine engine = QudsReportEngine.fromXml(
        info.xml,
        fonts: loadFonts(),
        clock: () => fixedNow,
      );
      expect(
        engine.diagnostics.where(
          (ReportDiagnostic d) => d.severity == ReportDiagnosticSeverity.error,
        ),
        isEmpty,
      );
      final List<ReportChartElement> charts = engine.template.bands
          .expand((ReportBand b) => b.elements)
          .whereType<ReportChartElement>()
          .toList();
      expect(
        charts.map((ReportChartElement c) => c.chartType).toSet(),
        ReportChartType.values.toSet(),
      );
      final ReportChartElement map = charts.firstWhere(
        (ReportChartElement c) => c.name == 'worldMap',
      );
      expect(map.dataSet, 'Data.countries');
      expect(map.category, 'Row.code');
      expect(map.series.single.value, 'Row.revenue');
      final ReportDocumentLayout layout = engine.layout(info.sampleData());
      expect(layout.pages, isNotEmpty);
      final Set<int> fills = <int>{
        for (final ReportPageLayout page in layout.pages)
          for (final ReportPathPrimitive p
              in page.primitives.whereType<ReportPathPrimitive>())
            if (p.elementId == map.id &&
                p.fill != null &&
                p.fill!.argb != 0xFFE4E4E4 &&
                p.fill!.argb != 0xFFE7F1F8)
              p.fill!.argb,
      };
      expect(fills, containsAll(<int>[0xFFDEEBF7, 0xFF08306B]));
      expect(
        layout.pages
            .expand((ReportPageLayout p) => p.primitives)
            .whereType<ReportTextPrimitive>()
            .map((ReportTextPrimitive t) => t.text),
        contains('LY'),
      );
      final Map<
        String,
        List<({int page, double l, double t, double r, double b})>
      >
      boxes =
          <
            String,
            List<({int page, double l, double t, double r, double b})>
          >{};
      for (final ReportPageLayout page in layout.pages) {
        final Map<String, ({double l, double t, double r, double b})> onPage =
            <String, ({double l, double t, double r, double b})>{};
        for (final ReportPrimitive p in page.primitives) {
          final String? id = p.elementId;
          if (id == null || !charts.any((ReportChartElement c) => c.id == id)) {
            continue;
          }
          final ({double l, double t, double r, double b})? have = onPage[id];
          final ReportRect b = p.bounds;
          onPage[id] = have == null
              ? (l: b.left, t: b.top, r: b.right, b: b.bottom)
              : (
                  l: have.l < b.left ? have.l : b.left,
                  t: have.t < b.top ? have.t : b.top,
                  r: have.r > b.right ? have.r : b.right,
                  b: have.b > b.bottom ? have.b : b.bottom,
                );
        }
        for (final MapEntry<String, ({double l, double t, double r, double b})>
            e
            in onPage.entries) {
          boxes.putIfAbsent(e.key, () => []).add((
            page: page.pageNumber,
            l: e.value.l,
            t: e.value.t,
            r: e.value.r,
            b: e.value.b,
          ));
        }
      }
      final List<({int page, double l, double t, double r, double b})>
      placed = <({int page, double l, double t, double r, double b})>[
        for (final List<({int page, double l, double t, double r, double b})>
            list
            in boxes.values)
          ...list,
      ];
      for (int i = 0; i < placed.length; i++) {
        for (int j = i + 1; j < placed.length; j++) {
          final ({int page, double l, double t, double r, double b}) a =
              placed[i];
          final ({int page, double l, double t, double r, double b}) b =
              placed[j];
          if (a.page != b.page) {
            continue;
          }
          final bool overlaps =
              a.l < b.r - 1 && b.l < a.r - 1 && a.t < b.b - 1 && b.t < a.b - 1;
          expect(overlaps, isFalse, reason: 'page ${a.page}');
        }
      }
    });

    test('tokens are filled and XML stays well-formed', () {
      for (final ReportTemplateInfo t in ReportTemplates.all) {
        expect(t.xml, isNot(contains('[[')), reason: t.id);
        expect(QudsReportXmlParser().parse(t.xml).template, isNotNull);
      }
      expect(
        ReportTemplates.byId('sales_invoice_ar')!.xml,
        contains('فاتورة مبيعات'),
      );
      expect(
        ReportTemplates.byId('sales_invoice_en')!.xml,
        contains('TAX INVOICE'),
      );
    });

    test('templates carry pre-saved PNG images for every source', () {
      final RegExp source = RegExp(r'<Image[^>]*\bsource="([^"{]+)"');
      var withImages = 0;
      for (final ReportTemplateInfo t in ReportTemplates.all) {
        final Map<String, Uint8List> images = t.images();
        if (images.isNotEmpty) {
          withImages++;
        }
        for (final Uint8List png in images.values) {
          expect(isPng(png), isTrue, reason: t.id);
        }
        for (final RegExpMatch m in source.allMatches(t.xml)) {
          expect(images, contains(m.group(1)), reason: '${t.id} ${m[1]}');
        }
        final ReportPackage pkg = ReportPackage.decode(t.package().encode());
        expect(pkg.images.keys.toSet(), images.keys.toSet());
      }
      expect(withImages, greaterThanOrEqualTo(10));
      final ReportTemplateInfo catalog = ReportTemplates.byId(
        'product_catalog_en',
      )!;
      final Map<String, Uint8List> photos = catalog.images();
      final List<Object?> items =
          catalog.sampleData()['items']! as List<Object?>;
      for (final Object? item in items) {
        final String key = (item! as Map<String, Object?>)['photo']! as String;
        expect(photos, contains(key));
      }
    });

    test('built-in art is deterministic transparent PNG', () {
      final Uint8List a = ReportTemplateArt.logo(size: 64);
      expect(isPng(a), isTrue);
      expect(ReportTemplateArt.logo(size: 64), a);
      expect(
        ReportImageFormat.sniff(ReportTemplateArt.stamp(size: 64)),
        ReportImageFormat.png,
      );
      for (final ReportProductArt kind in ReportProductArt.values) {
        expect(
          isPng(ReportTemplateArt.product(kind, width: 48, height: 36)),
          isTrue,
        );
      }
    });
  });

  group('Layout order', () {
    test('elements at the same top paint in document order', () {
      final QudsReportEngine engine = QudsReportEngine.fromXml('''
<QudsReport name="Z">
  <Bands>
    <ReportHeader height="20mm">
      <Text x="0mm" y="5mm" width="30mm" height="8mm">label</Text>
      <Shape kind="Rectangle" x="40mm" y="5mm" width="40mm" height="8mm" fill="#EEEEEE"/>
      <Text x="40mm" y="5mm" width="40mm" height="8mm">value</Text>
      <Shape kind="Rectangle" x="90mm" y="5mm" width="40mm" height="8mm" fill="#DDDDDD"/>
      <Text x="90mm" y="5mm" width="40mm" height="8mm">more</Text>
    </ReportHeader>
  </Bands>
</QudsReport>''', fonts: loadFonts());
      final List<String> order = <String>[
        for (final ReportPrimitive p
            in engine.layout(const <String, Object?>{}).pages.first.primitives)
          if (p is ReportTextPrimitive)
            p.text
          else if (p is ReportRectPrimitive)
            'rect',
      ];
      expect(order, <String>['label', 'rect', 'value', 'rect', 'more']);
    });
  });

  group('Deflate', () {
    test('long runs use overlapping matches and round-trip', () {
      final Uint8List zeros = Uint8List(200000);
      final Uint8List packed = RawDeflate.deflate(zeros, level: 9);
      expect(packed.length, lessThan(2000));
      expect(RawDeflate.inflate(packed), zeros);
      final Uint8List mixed = Uint8List.fromList(<int>[
        for (int i = 0; i < 50000; i++) (i * 7 + (i ~/ 300)) & 0xFF,
      ]);
      expect(RawDeflate.inflate(RawDeflate.deflate(mixed)), mixed);
    });
  });

  group('Completion', () {
    final ReportTemplate t = QudsReportXmlParser().parse('''
<QudsReport name="C">
  <Variables><Variable name="title" value="Sales"/></Variables>
  <Bands><Detail dataSet="items" height="8mm"/></Bands>
</QudsReport>''').templateOrThrow;
    final ReportCompleter c = ReportCompleter(
      template: t,
      band: t.band(ReportBandKind.detail),
      data: <String, Object?>{
        'customer': 'Ali',
        'seller': <String, Object?>{'name': 'Quds', 'phone': '091'},
        'items': <Object?>[
          <String, Object?>{'name': 'Pen', 'qty': 2, 'price': 5.5},
        ],
      },
    );
    List<String> inserts(ReportCompletionResult? r) => <String>[
      for (final ReportCompletionItem i in r!.items) i.insert,
    ];

    test('roots after {{ and nothing outside bindings', () {
      final ReportCompletionResult? r = c.complete('Hi {{', 5);
      expect(
        inserts(r),
        containsAll(<String>['item', 'Data', 'System', 'Variables', 'SUM()']),
      );
      expect(c.complete('{{a}} b', 7), isNull);
      expect(c.complete('plain', 3), isNull);
      expect(c.complete('{{item.qty * ', 13), isNull);
      expect(c.complete('{{item.qty * ', 13, force: true), isNotNull);
    });

    test('fields come from rows and records of the data', () {
      final ReportCompletionResult? r = c.complete('{{item.q', 8);
      expect(inserts(r).first, 'qty');
      expect(r!.start, 7);
      expect(inserts(c.complete('{{Data.seller.', 14)), <String>[
        'name',
        'phone',
      ]);
      expect(inserts(c.complete('{{items.', 8)), contains('price'));
      expect(inserts(c.complete('{{System.Pa', 11)).first, 'PageNumber');
      expect(inserts(c.complete('{{Variables.', 12)), <String>['title']);
      expect(
        inserts(c.complete('item.', 5, expression: true)),
        contains('qty'),
      );
    });

    test('schema columns complete even when the data lacks them', () {
      final ReportTemplate schema = QudsReportXmlParser().parse('''
<QudsReport name="S">
  <DataSchema>
    <Table name="items">
      <Column name="qty" type="number"/>
      <Column name="calc1" type="number" expression="qty * 2"/>
    </Table>
    <Table name="returns"><Column name="reason"/></Table>
  </DataSchema>
  <Bands><Detail dataSet="items" height="8mm"/></Bands>
</QudsReport>''').templateOrThrow;
      final ReportCompleter s = ReportCompleter(
        template: schema,
        band: schema.band(ReportBandKind.detail),
        data: <String, Object?>{
          'items': <Object?>[
            <String, Object?>{'qty': 3},
          ],
        },
      );
      final ReportCompletionResult item = s.complete('{{item.', 7)!;
      expect(inserts(item), <String>['qty', 'calc1']);
      expect(item.items.last.detail, '= qty * 2');
      expect(inserts(s.complete('{{SUM(items.', 12)), <String>[
        'qty',
        'calc1',
        'count',
      ]);
      expect(inserts(s.complete('{{Data.returns.', 15)), <String>['reason']);

      final ReportCompleter formula = ReportCompleter(
        template: schema,
        band: schema.band(ReportBandKind.detail),
        data: <String, Object?>{
          'items': <Object?>[
            <String, Object?>{'qty': 3},
          ],
        },
        rowTable: 'items',
      );
      expect(inserts(formula.complete('q', 1, expression: true)).first, 'qty');
      expect(
        inserts(formula.complete('', 0, expression: true, force: true)),
        containsAll(<String>['qty', 'calc1']),
      );
    });

    test('a map label completes the map columns, not the report records', () {
      final ReportCompleter map = ReportCompleter(
        template: t,
        band: t.band(ReportBandKind.detail),
        data: <String, Object?>{
          'customer': 'Ali',
          'seller': <String, Object?>{'name': 'Quds'},
          'items': <Object?>[
            <String, Object?>{'name': 'Pen', 'qty': 2},
          ],
          'districts': <Object?>[
            <String, Object?>{'name': 'Ramallah', 'code': '18'},
          ],
        },
        rowTable: 'districts',
        rowSource: 'districts',
        rowFieldsOnly: true,
      );
      final List<String> roots = inserts(
        map.complete('CONCAT(', 7, expression: true),
      );
      expect(roots, containsAll(<String>['name', 'code', 'Row', 'CONCAT()']));
      expect(roots, isNot(contains('seller')));
      expect(roots, isNot(contains('customer')));
      expect(roots, isNot(contains('item')));
      expect(roots.indexOf('name'), lessThan(roots.indexOf('Data')));
      expect(
        inserts(map.complete('Row.', 4, expression: true)),
        containsAll(<String>['name', 'code']),
      );
      expect(
        inserts(map.complete('row.', 4, expression: true)),
        containsAll(<String>['name', 'code']),
      );
    });

    test('functions insert parentheses with the caret inside', () {
      const String text = '{{SU';
      final ReportCompletionResult r = c.complete(text, 4)!;
      final ReportCompletionItem sum = r.items.first;
      expect(sum.insert, 'SUM()');
      final (String out, int caret) = r.apply(text, sum);
      expect(out, '{{SUM()');
      expect(caret, 6);
    });

    test('formats after | and currencies inside TAFQEET', () {
      expect(
        inserts(c.complete('{{item.price | cur', 18)),
        containsAll(<String>['currency:LYD', 'currencyCode:USD']),
      );
      expect(
        inserts(c.complete('{{x | currency:E', 16)),
        contains('currency:EGP'),
      );
      expect(inserts(c.complete("{{TAFQEET(1, 'L", 15)), contains('LYD'));
      expect(c.complete("{{UPPER('L", 10), isNull);
      expect(c.complete('{{a || b', 8), isNull);
    });
  });

  group('Template variables', () {
    const String xml = r'''<QudsReport name="Vars">
  <Variables>
    <Var name="company" value="Quds Co"/>
    <Var name="rate" type="number" value="0.15" format="percent" description="VAT rate"/>
    <Var name="showNotes" type="boolean" value="yes"/>
    <Var name="issued" type="date" value="2026-03-05" format="date:dd/MM/yyyy"/>
    <Var name="regions" type="list" value="North; South; 30"/>
    <Var name="total" type="expression" value="SUM(Data.items.amount)"/>
    <Var name="tax" type="expression" value="Variables.total * Variables.rate"/>
    <Var name="greeting" value="Hello {{Data.customer}}"/>
  </Variables>
  <Bands>
    <ReportHeader height="60mm">
      <Text x="0" y="0" width="150mm" height="6mm">{{Variables.company}}|{{Variables.rate | percent}}|{{IF(Variables.showNotes, 'notes', 'none')}}</Text>
      <Text x="0" y="8mm" width="150mm" height="6mm">{{Variables.issued | date:dd/MM/yyyy}}|{{COUNT(Variables.regions)}}|{{Variables.tax | n2}}</Text>
      <Text x="0" y="16mm" width="150mm" height="6mm">{{Variables.greeting}}|{{YEAR(Variables.issued)}}</Text>
    </ReportHeader>
  </Bands>
</QudsReport>''';
    final Map<String, Object?> data = <String, Object?>{
      'customer': 'Ali',
      'items': <Object?>[
        <String, Object?>{'amount': 100},
        <String, Object?>{'amount': 300},
      ],
    };

    test('typed values evaluate in order and round-trip', () {
      final QudsReportEngine engine = QudsReportEngine.fromXml(
        xml,
        fonts: loadFonts(),
      );
      expect(engine.validate(), isEmpty);
      final List<ReportVariable> vars = engine.template.variables;
      expect(vars.map((ReportVariable v) => v.type), <ReportVariableType>[
        ReportVariableType.text,
        ReportVariableType.number,
        ReportVariableType.boolean,
        ReportVariableType.date,
        ReportVariableType.list,
        ReportVariableType.expression,
        ReportVariableType.expression,
        ReportVariableType.text,
      ]);
      expect(vars[1].placeholder, '{{Variables.rate | percent}}');
      expect(vars[1].description, 'VAT rate');
      expect(vars[4].listItems, <String>['North', 'South', '30']);
      final List<String> texts = pageTexts(engine.layout(data).pages.first);
      expect(texts, contains('Quds Co|15%|notes'));
      expect(texts, contains('05/03/2026|3|60.00'));
      expect(texts, contains('Hello Ali|2026'));
      final String again = QudsReportEngine.fromXml(engine.toXml()).toXml();
      expect(again, engine.toXml());
      expect(engine.toXml(), contains('type="expression"'));
    });

    test('host values override and invalid literals are reported', () {
      final QudsReportEngine engine = QudsReportEngine.fromXml(
        xml,
        fonts: loadFonts(),
        variables: <String, Object?>{'company': 'Host Ltd', 'rate': 0.2},
      );
      final List<String> texts = pageTexts(engine.layout(data).pages.first);
      expect(texts, contains('Host Ltd|20%|notes'));
      expect(texts, contains('05/03/2026|3|80.00'));

      final ReportParseResult bad = QudsReportXmlParser().parse(
        '<QudsReport><Variables>'
        '<Var name="n" type="number" value="abc"/>'
        '<Var name="d" type="date" value="31-31-2026"/>'
        '<Var name="x" type="weird" value="1"/>'
        '</Variables><Bands><Detail height="5mm"/></Bands></QudsReport>',
      );
      final List<String> messages = <String>[
        for (final ReportDiagnostic d in bad.diagnostics) d.toString(),
      ];
      expect(
        messages.where((String m) => m.contains('not a number')),
        hasLength(1),
      );
      expect(
        messages.where((String m) => m.contains('not a valid date')),
        hasLength(1),
      );
      expect(
        messages.where((String m) => m.contains('Unknown variable type')),
        hasLength(1),
      );
    });

    test('item aggregates sum the detail data set', () {
      const String rows = r'''<QudsReport name="Rows">
  <Variables>
    <Var name="sumText" value="{{SUM(item.amount)}}"/>
    <Var name="sumExpr" type="expression" value="SUM(item.amount)"/>
    <Var name="count" type="expression" value="COUNT()"/>
    <Var name="plain" type="expression" value="SUM(items.amount)"/>
  </Variables>
  <Bands>
    <ReportHeader height="10mm">
      <Text x="0" y="0" width="150mm" height="6mm">{{Variables.sumText}}|{{Variables.sumExpr}}|{{Variables.count}}|{{Variables.plain}}</Text>
    </ReportHeader>
    <Detail height="6mm" dataSet="items">
      <Text x="0" y="0" width="40mm" height="6mm">{{item.amount}}</Text>
    </Detail>
  </Bands>
</QudsReport>''';
      final QudsReportEngine engine = QudsReportEngine.fromXml(
        rows,
        fonts: loadFonts(),
      );
      expect(
        pageTexts(engine.layout(data).pages.first),
        contains('400|400|2|400'),
      );
    });

    test('dotted names group variables into folders', () {
      const String grouped = r'''<QudsReport name="Groups">
  <Variables>
    <Var name="stats.sum" type="expression" value="SUM(item.amount)"/>
    <Var name="stats.avg" type="expression" value="Variables.stats.sum / COUNT()"/>
    <Var name="stats.label.title" value="Totals"/>
    <Var name="company" value="Quds"/>
  </Variables>
  <Bands>
    <ReportHeader height="10mm">
      <Text x="0" y="0" width="150mm" height="6mm">{{Variables.stats.label.title}}|{{Variables.stats.sum}}|{{Variables.stats.avg}}|{{Variables.company}}</Text>
    </ReportHeader>
    <Detail height="6mm" dataSet="items">
      <Text x="0" y="0" width="40mm" height="6mm">{{item.amount}}</Text>
    </Detail>
  </Bands>
</QudsReport>''';
      final QudsReportEngine engine = QudsReportEngine.fromXml(
        grouped,
        fonts: loadFonts(),
      );
      expect(engine.validate(), isEmpty);
      expect(
        pageTexts(engine.layout(data).pages.first),
        contains('Totals|400|200|Quds'),
      );
      final ReportVariable avg = engine.template.variables[1];
      expect(avg.folder, 'stats');
      expect(avg.leaf, 'avg');
      expect(ReportVariable.isValidName('stats.sum'), isTrue);
      expect(ReportVariable.isValidName('stats..sum'), isFalse);
      expect(ReportVariable.isValidName('.sum'), isFalse);

      final ReportCompleter completer = ReportCompleter(
        template: engine.template,
      );
      List<String> labels(String text) => <String>[
        for (final ReportCompletionItem i
            in completer.complete(text, text.length)!.items)
          i.label,
      ];
      expect(labels('{{Variables.'), <String>['stats', 'company']);
      expect(labels('{{Variables.stats.'), <String>['label', 'sum', 'avg']);
      expect(labels('{{Variables.stats.label.'), <String>['title']);

      final ReportParseResult clash = QudsReportXmlParser().parse(
        '<QudsReport><Variables>'
        '<Var name="stats" value="1"/><Var name="stats.sum" value="2"/>'
        '</Variables><Bands><Detail height="5mm"/></Bands></QudsReport>',
      );
      expect(
        clash.diagnostics.map((ReportDiagnostic d) => d.message),
        contains(contains('clash')),
      );
    });

    test('a broken expression still yields a readable template', () {
      final ReportParseResult broken = QudsReportXmlParser().parse(
        '<QudsReport><Variables>'
        '<Var name="itemsSum" value="{{sum(item.calc1}}"/>'
        '</Variables><Bands><Detail height="5mm"/></Bands></QudsReport>',
      );
      expect(broken.readable, isTrue);
      expect(broken.diagnostics.where((ReportDiagnostic d) => d.isError), [
        isA<ReportDiagnostic>().having(
          (ReportDiagnostic d) => d.path,
          'path',
          contains('itemsSum'),
        ),
      ]);
      expect(broken.template.variables.single.value, '{{sum(item.calc1}}');
      expect(
        () => broken.templateOrThrow,
        throwsA(isA<ReportTemplateException>()),
      );

      for (final String bad in <String>[
        '<QudsReport><Bands></QudsReport>',
        '',
        '<Other/>',
      ]) {
        final ReportParseResult r = QudsReportXmlParser().parse(bad);
        expect(r.readable, isFalse, reason: bad);
        expect(
          r.diagnostics.where((ReportDiagnostic d) => d.isError),
          isNotEmpty,
        );
      }
    });
  });

  group('Report package', () {
    const String layout =
        '<QudsReport name="Logo"><Bands><ReportHeader height="30mm">'
        '<Element type="Image" source="logo" x="0" y="0" width="20mm" '
        'height="10mm"/></ReportHeader></Bands></QudsReport>';
    final Uint8List logo = PngBytes.rgb(
      width: 4,
      height: 2,
      plot: (int x, int y, List<int> rgb) => rgb[0] = 200,
    );

    int imageCount(QudsReportEngine engine) => <ReportPrimitive>[
      for (final ReportPageLayout page
          in engine.layout(const <String, Object?>{}).pages)
        ...page.primitives,
    ].whereType<ReportImagePrimitive>().length;

    test('round-trips layout and embedded images through a ZIP', () {
      final Uint8List bytes = ReportPackage(
        xml: layout,
        images: <String, Uint8List>{'logo': logo},
      ).encode();
      expect(ReportPackage.isPackage(bytes), isTrue);
      expect(
        ascii.decode(bytes.sublist(30, 38)),
        'mimetype',
        reason: 'mimetype is the first, stored entry',
      );

      final ReportPackage back = ReportPackage.decode(bytes);
      expect(back.xml, layout);
      expect(back.images.keys, <String>['logo']);
      expect(back.images['logo'], logo);

      final QudsReportEngine engine = QudsReportEngine.fromPackage(bytes);
      expect(engine.images['logo'], logo);
      expect(imageCount(engine), 1);
      expect(ReportPackage.decode(engine.toPackage()).images['logo'], logo);
    });

    test('opens legacy plain-XML files and lets host images win', () {
      final Uint8List legacy = Uint8List.fromList(<int>[
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode(layout),
      ]);
      expect(ReportPackage.isPackage(legacy), isFalse);
      final ReportPackage package = ReportPackage.decode(legacy);
      expect(package.xml, layout);
      expect(package.images, isEmpty);
      expect(imageCount(QudsReportEngine.fromPackage(legacy)), 0);

      final Uint8List other = PngBytes.rgb(
        width: 1,
        height: 1,
        plot: (int x, int y, List<int> rgb) {},
      );
      final QudsReportEngine engine = QudsReportEngine.fromPackage(
        ReportPackage(
          xml: layout,
          images: <String, Uint8List>{'logo': logo},
        ).encode(),
        images: <String, Uint8List>{'logo': other},
      );
      expect(engine.images['logo'], other);
    });

    test('rejects damaged packages and bad images', () {
      final Uint8List good = ReportPackage(xml: layout).encode();
      expect(
        () => ReportPackage.decode(Uint8List.sublistView(good, 0, 40)),
        throwsA(isA<ReportPackageException>()),
      );
      expect(
        () => ReportPackage(
          xml: layout,
          images: <String, Uint8List>{
            'logo': Uint8List.fromList(<int>[1, 2]),
          },
        ).encode(),
        throwsA(isA<ReportPackageException>()),
      );
      expect(
        () => ReportPackage(
          xml: layout,
          images: <String, Uint8List>{'bad/name': logo},
        ).encode(),
        throwsA(isA<ReportPackageException>()),
      );
      expect(
        () => ReportPackage.decode(Uint8List.fromList(<int>[0xC3, 0x28])),
        throwsA(isA<ReportPackageException>()),
      );
    });

    test('inspects TrueType files and refuses unusable ones', () {
      const String dir = '../quds_office_editor/fonts';
      final ReportFontFileInfo regular = ReportFontFile.inspect(
        File('$dir/LiberationSerif-Regular.ttf').readAsBytesSync(),
      );
      expect(regular.family, 'Liberation Serif');
      expect(regular.weight, 400);
      expect(regular.bold || regular.italic, isFalse);
      expect(
        regular.scripts,
        containsAll(<ReportScript>[ReportScript.latin, ReportScript.cyrillic]),
      );
      expect(regular.scripts, isNot(contains(ReportScript.arabic)));
      expect(ReportScript.previewText(regular.scripts), 'The quick brown fox');
      final ReportFontFileInfo naskh = ReportFontFile.inspect(
        File('$dir/NotoNaskhArabic-Regular.ttf').readAsBytesSync(),
      );
      expect(naskh.scripts, contains(ReportScript.arabic));
      expect(ReportScript.primary(naskh.scripts), ReportScript.arabic);
      expect(ReportScript.previewText(naskh.scripts), 'أبجد هوز حطي كلمن');
      expect(
        ReportScript.previewText(<ReportScript>{
          ReportScript.latin,
          ReportScript.arabic,
        }),
        contains('أبجد'),
      );
      final ReportFontFileInfo bold = ReportFontFile.inspect(
        File('$dir/LiberationSerif-Bold.ttf').readAsBytesSync(),
      );
      expect(bold.bold, isTrue);
      expect(bold.style, 'Bold');
      final ReportFontFileInfo italic = ReportFontFile.inspect(
        File('$dir/LiberationSerif-Italic.ttf').readAsBytesSync(),
      );
      expect(italic.italic, isTrue);
      expect(
        ReportFontFile.inspect(
          File('$dir/NotoNaskhArabic-Regular.ttf').readAsBytesSync(),
        ).family,
        'Noto Naskh Arabic',
      );

      Matcher refuses(String text) => throwsA(
        isA<ReportFontException>().having(
          (ReportFontException e) => e.message,
          'message',
          contains(text),
        ),
      );
      final Uint8List otf = Uint8List(64)..setAll(0, ascii.encode('OTTO'));
      expect(() => ReportFontFile.inspect(otf), refuses('.otf'));
      final Uint8List ttc = Uint8List(64)..setAll(0, ascii.encode('ttcf'));
      expect(() => ReportFontFile.inspect(ttc), refuses('.ttc'));

      final Uint8List restricted = Uint8List.fromList(
        File('$dir/LiberationSerif-Regular.ttf').readAsBytesSync(),
      );
      final ByteData view = ByteData.sublistView(restricted);
      final int tables = view.getUint16(4);
      for (int i = 0; i < tables; i++) {
        final int at = 12 + i * 16;
        if (ascii.decode(restricted.sublist(at, at + 4)) == 'OS/2') {
          view.setUint16(view.getUint32(at + 8) + 8, 0x0002);
        }
      }
      expect(() => ReportFontFile.inspect(restricted), refuses('license'));
    });

    test('embeds fonts so exports draw with the designed faces', () {
      const String dir = '../quds_office_editor/fonts';
      final Uint8List serif = File(
        '$dir/LiberationSerif-Regular.ttf',
      ).readAsBytesSync();
      final Uint8List serifBold = File(
        '$dir/LiberationSerif-Bold.ttf',
      ).readAsBytesSync();
      const String xml =
          '<QudsReport name="F" defaultFont="Liberation Serif"><Bands>'
          '<ReportHeader height="20mm"><Element type="Text" x="0" y="0" '
          'width="80mm" height="8mm" bold="true">Hello</Element>'
          '</ReportHeader></Bands></QudsReport>';
      final Uint8List bytes = ReportPackage(
        xml: xml,
        fonts: <String, ReportFontFiles>{
          'Liberation Serif': ReportFontFiles(regular: serif, bold: serifBold),
        },
      ).encode();
      final ReportPackage back = ReportPackage.decode(bytes);
      expect(back.fonts.keys, <String>['Liberation Serif']);
      expect(back.fonts['Liberation Serif']!.regular, serif);
      expect(back.fonts['Liberation Serif']!.bold, serifBold);

      final QudsReportEngine engine = QudsReportEngine.fromPackage(bytes);
      expect(engine.fonts.has('Liberation Serif'), isTrue);
      final ReportTextPrimitive hello = engine
          .layout(const <String, Object?>{})
          .pages
          .first
          .primitives
          .whereType<ReportTextPrimitive>()
          .single;
      expect(hello.font.bold, isTrue);
      expect(
        engine.fonts
            .faceFor(hello.font.family, 'H'.codeUnitAt(0), bold: true)!
            .bytes,
        serifBold,
      );
      expect(
        ReportPackage.decode(
          engine.toPackage(),
        ).fonts['Liberation Serif']!.bold,
        serifBold,
      );

      final ReportFontRegistry host = ReportFontRegistry()
        ..registerBytes(
          'Liberation Sans',
          File('$dir/LiberationSans-Regular.ttf').readAsBytesSync(),
        );
      final QudsReportEngine hosted = QudsReportEngine.fromPackage(
        bytes,
        fonts: host,
      );
      expect(
        hosted.fonts.families.map((ReportFontFamily f) => f.name),
        <String>['Liberation Sans', 'Liberation Serif'],
      );
      expect(host.families, hasLength(1), reason: 'host registry untouched');

      expect(
        () => ReportPackage(
          xml: xml,
          fonts: <String, ReportFontFiles>{
            'a/b': ReportFontFiles(regular: serif),
          },
        ).encode(),
        throwsA(isA<ReportPackageException>()),
      );
      expect(
        () => ReportPackage(
          xml: xml,
          fonts: <String, ReportFontFiles>{
            'Bad': ReportFontFiles(regular: Uint8List(40)),
          },
        ).encode(),
        throwsA(isA<ReportPackageException>()),
      );
    });

    test('derives unique keys from file names', () {
      expect(ReportPackage.keyFor('/tmp/Company Logo.PNG'), 'Company_Logo');
      expect(ReportPackage.keyFor('شعار.jpg'), 'شعار');
      expect(ReportPackage.keyFor('...png'), 'image');
      expect(
        ReportPackage.keyFor('logo.png', taken: <String>['Logo', 'logo2']),
        'logo3',
      );
      expect(ReportPackage.isValidKey('stamp-1'), isTrue);
      expect(ReportPackage.isValidKey('a.b'), isFalse);
    });
  });

  group('Report data', () {
    const String xml = r'''<QudsReport name="Orders">
  <DataSchema>
    <Field name="customer.name" description="Billed customer"/>
    <Field name="issued" type="date"/>
    <Table name="items" description="Order lines">
      <Column name="code"/>
      <Column name="qty" type="number"/>
      <Column name="price" type="number" format="n2"/>
      <Column name="total" type="number" expression="qty * price" format="n2"/>
      <Column name="label" expression="item.code + ' x' + item.qty"/>
    </Table>
  </DataSchema>
  <Bands>
    <ReportHeader height="20mm">
      <Text name="title" x="0" y="0" width="120mm" height="8mm">Orders</Text>
      <Text name="customer" x="0" y="10mm" width="120mm" height="8mm">{{Data.customer.name}}|{{YEAR(Data.issued)}}</Text>
    </ReportHeader>
    <Detail dataSet="items" height="8mm">
      <Text name="line" x="0" y="0" width="120mm" height="6mm">{{item.label}}={{item.total}}</Text>
    </Detail>
    <ReportSummary height="40mm">
      <Text name="sum" x="0" y="0" width="120mm" height="6mm">{{SUM(items.total)}}</Text>
      <Table name="extras" x="0" y="8mm" width="120mm">
        <Columns><Column header="Name"/></Columns>
        <RowTemplate><Cell field="item.name"/></RowTemplate>
      </Table>
      <Barcode name="code" x="0" y="20mm" width="30mm" height="10mm" data="X"/>
      <Image name="logo" x="40mm" y="20mm" width="20mm" height="10mm" source=""/>
    </ReportSummary>
  </Bands>
</QudsReport>''';

    test('schema round-trips through XML', () {
      final QudsReportEngine engine = QudsReportEngine.fromXml(xml);
      expect(
        engine.diagnostics.where(
          (ReportDiagnostic d) => d.path.startsWith('DataSchema'),
        ),
        isEmpty,
      );
      expect(
        QudsReportXmlParser()
            .parse(
              '<QudsReport><DataSchema><Table name="t">'
              '<Column name="c" type="weird" expression="1 +"/>'
              '<Column name="c"/></Table><Field/></DataSchema>'
              '<Bands><Detail height="5mm"/></Bands></QudsReport>',
            )
            .diagnostics
            .map((ReportDiagnostic d) => d.message),
        containsAll(<Matcher>[
          contains('Unknown data type'),
          contains('Duplicate column'),
          contains('Field needs a name'),
        ]),
      );
      final ReportDataSchema s = engine.template.dataSchema;
      expect(s.fields.map((ReportDataField f) => f.name), <String>[
        'customer.name',
        'issued',
      ]);
      expect(s.field('Data.issued')!.type, ReportDataType.date);
      final ReportDataTable items = s.table('items')!;
      expect(items.description, 'Order lines');
      expect(items.column('TOTAL')!.isCalculated, isTrue);
      expect(items.column('price')!.format, 'n2');
      final String out = engine.toXml();
      expect(out, contains('<DataSchema>'));
      expect(out, contains('expression="qty * price"'));
      expect(QudsReportEngine.fromXml(out).toXml(), out);
      expect(
        engine.template.copy().dataSchema.tables.single.columns,
        hasLength(5),
      );
    });

    test('calculated columns and types apply at export', () {
      final QudsReportEngine engine = QudsReportEngine.fromXml(
        xml,
        fonts: loadFonts(),
      );
      final Map<String, Object?> data = <String, Object?>{
        'customer': <String, Object?>{'name': 'Northwind'},
        'issued': '2026-10-12',
        'items': <Object?>[
          <String, Object?>{'code': 'A', 'qty': '2', 'price': '10.5'},
          <String, Object?>{'code': 'B', 'qty': 3, 'price': 4},
        ],
      };
      final ReportRecord prepared = engine.prepare(data);
      final ReportList rows = prepared.field('items')! as ReportList;
      final ReportRecord first = rows.items.first as ReportRecord;
      expect(first.field('qty'), isA<ReportNumber>());
      expect(first.field('total')!.asNumber, 21);
      expect(first.field('label')!.displayText, 'A x2');
      expect(prepared.field('issued'), isA<ReportDate>());
      final List<String> texts = pageTexts(engine.layout(data).pages.first);
      expect(texts, contains('Northwind|2026'));
      expect(texts, contains('A x2=21'));
      expect(texts, contains('B x3=12'));
      expect(texts, contains('33'));
    });

    test('variables see calculated columns', () {
      final QudsReportEngine engine = QudsReportEngine.fromXml(
        xml
            .replaceFirst(
              '<DataSchema>',
              '<Variables><Variable name="grand" type="expression" '
                  'value="SUM(items.total) * 2"/></Variables><DataSchema>',
            )
            .replaceFirst(
              '{{SUM(items.total)}}',
              '{{SUM(items.total)}}/{{Variables.grand}}',
            ),
        fonts: loadFonts(),
      );
      final List<String> texts = pageTexts(
        engine
            .layout(<String, Object?>{
              'items': <Object?>[
                <String, Object?>{'code': 'A', 'qty': 2, 'price': 10.5},
                <String, Object?>{'code': 'B', 'qty': 3, 'price': 4},
              ],
            })
            .pages
            .first,
      );
      expect(texts, contains('33/66'));
    });

    test('host data feeds the report and elements are set by name', () {
      final QudsReportEngine engine = QudsReportEngine.fromXml(
        xml,
        fonts: loadFonts(),
      );
      expect(engine.elementNames, <String>[
        'title',
        'customer',
        'line',
        'sum',
        'extras',
        'code',
        'logo',
      ]);
      engine.data
        ..set('customer.name', 'Contoso')
        ..set('Data.issued', DateTime(2025))
        ..setTable('items', <Map<String, Object?>>[
          <String, Object?>{'code': 'Z', 'qty': 1, 'price': 7},
        ]);
      engine
        ..setText('TITLE', 'Fed {{1 + 1}}')
        ..setTableRows('extras', <Map<String, Object?>>[
          <String, Object?>{'name': 'first extra'},
          <String, Object?>{'name': 'second extra'},
        ])
        ..setBarcode('code', 'QX-1')
        ..setImage(
          'logo',
          PngBytes.rgb(
            width: 2,
            height: 2,
            plot: (int x, int y, List<int> rgb) => rgb[1] = 90,
          ),
        );
      engine.elementAs<ReportTextElement>('sum').style.bold = true;
      expect(engine.elementAs<ReportTableElement>('extras').dataSet, 'extras');
      expect(engine.data.rows('extras'), hasLength(2));

      List<ReportPrimitive> primitives() => <ReportPrimitive>[
        for (final ReportPageLayout page
            in engine.layout(const <String, Object?>{}).pages)
          ...page.primitives,
      ];
      final List<String> texts = <String>[
        for (final ReportPrimitive p in primitives())
          if (p is ReportTextPrimitive) p.text,
      ];
      expect(texts, containsAll(<String>['Fed 2', 'Contoso|2025', 'Z x1=7']));
      expect(texts, containsAll(<String>['first extra', 'second extra']));
      expect(primitives().whereType<ReportImagePrimitive>(), hasLength(1));

      final List<String> passed = pageTexts(
        engine
            .layout(<String, Object?>{
              'customer': <String, Object?>{'name': 'Passed wins'},
            })
            .pages
            .first,
      );
      expect(passed, contains('Passed wins|2025'));

      engine.setText('title', 'Literal {{x}}', literal: true);
      engine.setVisible('customer', false);
      final List<String> hidden = pageTexts(
        engine.layout(const <String, Object?>{}).pages.first,
      );
      expect(hidden, contains('Literal {{x}}'));
      expect(hidden.where((String t) => t.startsWith('Contoso')), isEmpty);

      expect(
        () => engine.setText('missing', 'x'),
        throwsA(isA<ReportElementException>()),
      );
      expect(
        () => engine.setText('extras', 'x'),
        throwsA(isA<ReportElementException>()),
      );
      expect(engine.exportSync(ReportExportFormat.pdf), isNotEmpty);
    });

    test('chart points are fed by name', () {
      final QudsReportEngine engine = QudsReportEngine.fromXml(
        '<QudsReport><Bands><ReportHeader height="80mm">'
        '<Chart name="sales" x="0" y="0" width="100mm" height="60mm" '
        'dataSet="rows" category="item.k"><Series value="SUM(item.v)"/>'
        '</Chart></ReportHeader></Bands></QudsReport>',
      );
      engine.setChartPoints('sales', <String, num>{'North': 3, 'South': 5});
      final ReportChartElement chart = engine.elementAs<ReportChartElement>(
        'sales',
      );
      expect(chart.dataSet, isNull);
      expect(chart.series, isEmpty);
      expect(chart.points.map((ReportChartPoint p) => p.value), <String>[
        '3',
        '5',
      ]);
    });

    test('names are unique, generated, and duplicates are reported', () {
      final QudsReportEngine engine = QudsReportEngine.fromXml(
        '<QudsReport><Bands><ReportHeader height="20mm">'
        '<Text name="a" x="0" y="0" width="10mm" height="5mm">1</Text>'
        '<Text name="A" x="0" y="0" width="10mm" height="5mm">2</Text>'
        '<Text x="0" y="0" width="10mm" height="5mm">3</Text>'
        '<Shape kind="Rect" x="0" y="0" width="10mm" height="5mm"/>'
        '</ReportHeader></Bands></QudsReport>',
      );
      expect(engine.template.duplicateElementNames, <String>{'a'});
      expect(
        engine.validate().map((ReportDiagnostic d) => d.message),
        contains('Element name "a" is used more than once'),
      );
      final List<ReportElement> renamed = engine.template.assignElementNames();
      expect(renamed, hasLength(3));
      expect(engine.elementNames, <String>['a', 'text1', 'text2', 'shape1']);
      expect(engine.template.uniqueElementName('text7'), 'text3');
      expect(ReportTemplate.isValidElementName('total_2'), isTrue);
      expect(ReportTemplate.isValidElementName('2total'), isFalse);
      expect(ReportTemplate.isValidElementName('a b'), isFalse);
    });

    test('ReportData builds, merges, and converts JSON', () {
      final ReportData d = ReportData()
        ..set('a.b.c', 1)
        ..addRow('rows', <String, Object?>{'x': 1})
        ..addRow('rows', <String, Object?>{'x': 2});
      expect(d.get('Data.a.b.c'), 1);
      expect(d.rows('rows'), hasLength(2));
      d.merge(<String, Object?>{
        'a': <String, Object?>{
          'b': <String, Object?>{'d': 2},
        },
      });
      expect(d.get('a.b.c'), 1);
      expect(d.get('a.b.d'), 2);
      expect(d.remove('a.b.c'), isTrue);
      expect(d.remove('nope.x'), isFalse);
      final ReportData back = ReportData.fromJson(
        ReportData(<String, Object?>{
          'when': DateTime.utc(2026, 1, 2),
          ...d.toMap(),
        }).toJson(),
      );
      expect(back.get('when'), '2026-01-02T00:00:00.000Z');
      expect(back.rows('rows').last['x'], 2);
      expect(
        () => ReportData.fromJson('[1]'),
        throwsA(isA<ReportDataException>()),
      );
      expect(
        () => ReportData.fromJson('{'),
        throwsA(isA<ReportDataException>()),
      );
      expect(
        ReportDataType.infer(<Object?>[1, null, 2.5]),
        ReportDataType.number,
      );
      expect(ReportDataType.infer(<Object?>[1, 'x']), ReportDataType.text);
      expect(ReportDataType.number.coerce('1,250.5'), 1250.5);
      expect(ReportDataType.boolean.coerce('Yes'), isTrue);
      expect(ReportDataType.date.coerce('nope'), 'nope');
    });

    test('CSV parses quotes, delimiters, and typed columns', () {
      const String csv =
          '\uFEFFcode;name;qty;paid;when\r\n'
          'A;"Big; ""red"" box";2;true;2026-01-05\r\n'
          'B;"two\nlines";1,5;false;\n';
      final List<Map<String, Object?>> rows = ReportCsv.rows(csv);
      expect(rows, hasLength(2));
      expect(rows[0]['name'], 'Big; "red" box');
      expect(rows[0]['paid'], isTrue);
      expect(rows[0]['when'], DateTime(2026, 1, 5));
      expect(rows[1]['name'], 'two\nlines');
      expect(rows[1]['when'], isNull);
      expect(rows[0]['qty'], 2);
      expect(rows[1]['qty'], 15);
      final String out = ReportCsv.write(rows);
      expect(ReportCsv.rows(out)[0]['name'], 'Big; "red" box');
      expect(() => ReportCsv.rows(''), throwsA(isA<ReportDataException>()));
      expect(
        () => ReportCsv.parse('a,"b'),
        throwsA(isA<ReportDataException>()),
      );
    });

    test('sample data travels in the package', () {
      final QudsReportEngine engine = QudsReportEngine.fromXml(xml)
        ..sampleData = <String, Object?>{
          'customer': <String, Object?>{'name': 'Sample'},
          'items': <Object?>[
            <String, Object?>{'code': 'S', 'qty': 1, 'price': 2},
          ],
        };
      final Uint8List bytes = engine.toPackage();
      final ReportPackage package = ReportPackage.decode(bytes);
      expect(package.sampleData!['customer'], <String, Object?>{
        'name': 'Sample',
      });
      final QudsReportEngine opened = QudsReportEngine.fromPackage(bytes);
      expect(opened.sampleData, package.sampleData);
      expect(opened.template.dataSchema.tables.single.name, 'items');
      expect(
        ReportPackage.decode(ReportPackage(xml: xml).encode()).sampleData,
        isNull,
      );
    });

    test('template manifests travel in the package', () {
      const ReportTemplateManifest manifest = ReportTemplateManifest(
        id: 'branch_invoice',
        title: 'Branch invoice',
        titleAr: 'فاتورة الفرع',
        description: 'Invoice for branches',
        category: ReportTemplateCategory.finance,
        language: ReportTemplateLanguage.arabic,
        order: 5,
      );
      final Uint8List bytes = ReportPackage(
        xml: xml,
        sampleData: <String, Object?>{'n': 1},
        template: manifest,
      ).encode();
      final ReportTemplateInfo info = ReportTemplateInfo.decode(bytes);
      expect(info.id, 'branch_invoice');
      expect(info.family, 'branch_invoice');
      expect(info.titleAr, 'فاتورة الفرع');
      expect(info.familyTitle, 'Branch invoice');
      expect(info.descriptionAr, 'Invoice for branches');
      expect(info.category, ReportTemplateCategory.finance);
      expect(info.rtl, isTrue);
      expect(info.order, 5);
      expect(info.xml, xml);
      expect(info.sampleData(), <String, Object?>{'n': 1});
      expect(info.package().template!.title, 'Branch invoice');
      expect(info.manifest.encode(), manifest.encode());
      expect(
        ReportPackage.decode(ReportPackage(xml: xml).encode()).template,
        isNull,
      );

      for (final String bad in <String>[
        '[]',
        '{"title": "x"}',
        '{"id": "a b", "title": "x"}',
        '{"id": "a"}',
        '{"id": "a", "title": "x", "category": "toys"}',
        '{"id": "a", "title": "x", "language": "fr"}',
        '{"id": "a", "title": "x", "order": "1"}',
      ]) {
        expect(
          () => ReportTemplateManifest.decode(bad),
          throwsFormatException,
          reason: bad,
        );
      }
      final ZipWriter zip = ZipWriter()
        ..addFile('mimetype', ascii.encode(ReportPackage.mimeType), store: true)
        ..addFile(ReportPackage.layoutEntry, utf8.encode(xml))
        ..addFile(ReportTemplateManifest.entry, utf8.encode('{"id": "x"}'));
      expect(
        () => ReportPackage.decode(zip.close()),
        throwsA(isA<ReportPackageException>()),
      );
      expect(
        () => ReportTemplateInfo.decode(ReportPackage(xml: xml).encode()),
        throwsA(isA<ReportPackageException>()),
      );
    });

    test('templates sort by category, order, family, Arabic first', () {
      ReportTemplateInfo t(
        String id,
        ReportTemplateCategory c, {
        int order = 0,
        bool ar = false,
      }) => ReportTemplateInfo.fromPackage(
        ReportPackage(
          xml: xml,
          template: ReportTemplateManifest(
            id: id,
            title: id.split('_').first,
            category: c,
            order: order,
            language: ar
                ? ReportTemplateLanguage.arabic
                : ReportTemplateLanguage.english,
          ),
        ),
      );
      final List<ReportTemplateInfo> list = <ReportTemplateInfo>[
        t('zeta_en', ReportTemplateCategory.hr),
        t('beta_en', ReportTemplateCategory.sales, order: 20),
        t('alpha_en', ReportTemplateCategory.sales, order: 20),
        t('alpha_ar', ReportTemplateCategory.sales, order: 20, ar: true),
        t('first_en', ReportTemplateCategory.sales, order: 10),
      ]..sort(ReportTemplateInfo.compare);
      expect(list.map((ReportTemplateInfo i) => i.id), <String>[
        'first_en',
        'alpha_ar',
        'alpha_en',
        'beta_en',
        'zeta_en',
      ]);
    });

    test('prompt variables round-trip and two sections print in order', () {
      const String xml = '''
<QudsReport>
  <Variables>
    <Var name="branch" value="Tripoli" prompt="true" required="true"/>
  </Variables>
  <Bands>
    <Detail height="8mm" dataSet="items">
      <Text x="0" y="0" width="80mm" height="6mm">{{item.name}}</Text>
    </Detail>
    <Section dataSet="payments">
      <Detail height="8mm">
        <Text x="0" y="0" width="80mm" height="6mm">pay {{item.ref}}</Text>
      </Detail>
    </Section>
  </Bands>
</QudsReport>''';
      final QudsReportEngine engine = QudsReportEngine.fromXml(xml);
      expect(engine.template.variables.single.prompt, isTrue);
      expect(engine.template.variables.single.required, isTrue);
      expect(engine.template.sections, hasLength(2));
      expect(engine.template.sections[1].detail!.dataSet, 'payments');
      final String again = QudsReportEngine.fromXml(engine.toXml()).toXml();
      expect(again, engine.toXml());
      final ReportDocumentLayout layout = engine.layout(<String, Object?>{
        'items': <Object?>[
          <String, Object?>{'name': 'Oil'},
        ],
        'payments': <Object?>[
          <String, Object?>{'ref': 'P1'},
        ],
      });
      final List<String> texts = pageTexts(layout.pages.first);
      expect(texts.first, 'Oil');
      expect(texts, contains('pay P1'));
    });

    test('crosstab pivots months and a subreport prints its child', () {
      const String child = '''
<QudsReport>
  <Bands>
    <Detail height="8mm" dataSet="items">
      <Text x="0" y="0" width="40mm" height="6mm">{{item.sku}}</Text>
    </Detail>
  </Bands>
</QudsReport>''';
      const String xml = '''
<QudsReport>
  <Bands>
    <Detail height="40mm">
      <Crosstab x="0" y="0" width="80mm" height="30mm" dataSet="sales" rowField="item.branch" columnField="item.month" valueField="item.amount"/>
      <Subreport x="0" y="32mm" width="80mm" height="20mm" template="lines" dataSet="lines"/>
    </Detail>
  </Bands>
</QudsReport>''';
      final QudsReportEngine engine = QudsReportEngine.fromXml(xml)
        ..template.subreports['lines'] = child;
      final ReportDocumentLayout layout = engine.layout(<String, Object?>{
        'sales': <Object?>[
          <String, Object?>{'branch': 'East', 'month': 'Jan', 'amount': 10},
          <String, Object?>{'branch': 'East', 'month': 'Feb', 'amount': 5},
          <String, Object?>{'branch': 'West', 'month': 'Jan', 'amount': 7},
        ],
        'lines': <Object?>[
          <String, Object?>{'sku': 'A1'},
        ],
      });
      final List<String> texts = pageTexts(layout.pages.first);
      expect(texts, containsAll(<String>['East', 'West', 'Jan', 'Feb', '10', '5', '7', 'A1']));
      final Uint8List packed = ReportPackage(
        xml: engine.toXml(),
        subreports: engine.template.subreports,
      ).encode();
      final ReportPackage back = ReportPackage.decode(packed);
      expect(back.subreports['lines'], contains('sku'));
    });

    test('rich runs keep their text and a PDF link', () {
      const String xml = '''
<QudsReport>
  <Bands>
    <Detail height="12mm">
      <Text x="0" y="0" width="120mm" height="8mm">
        <Run bold="true">Hello </Run>
        <Run fontSize="16" link="https://quds.example">world</Run>
      </Text>
    </Detail>
  </Bands>
</QudsReport>''';
      final QudsReportEngine engine = QudsReportEngine.fromXml(xml);
      final ReportTextElement text =
          engine.template.detail!.elements.first as ReportTextElement;
      expect(text.runs, hasLength(2));
      expect(text.runs[1].link, 'https://quds.example');
      final List<String> texts = pageTexts(engine.layout(const <String, Object?>{}).pages.first);
      expect(texts, containsAll(<String>['Hello', 'world']));
      final Uint8List pdf = engine.exportToPdfSync(const <String, Object?>{});
      expect(utf8.decode(pdf, allowMalformed: true), contains('https://quds.example'));
      final Uint8List docx = engine.exportToWordSync(const <String, Object?>{});
      expect(partText(docx, '/word/document.xml'), contains('w:hyperlink'));
      expect(partText(docx, '/word/document.xml'), contains('<w:b/>'));
    });
  });
}

String chartEngineRoundTrip(QudsReportEngine engine) =>
    QudsReportEngine.fromXml(engine.toXml()).toXml();

/// One polygon shapefile. The first ring is the exterior; a later ring wound
/// the other way is a hole.
Uint8List _polygonShapefile(List<List<(double, double)>> parts) {
  final List<(double, double)> points = <(double, double)>[
    for (final List<(double, double)> part in parts) ...part,
  ];
  var xmin = points.first.$1;
  var xmax = xmin;
  var ymin = points.first.$2;
  var ymax = ymin;
  for (final (double, double) p in points) {
    if (p.$1 < xmin) {
      xmin = p.$1;
    }
    if (p.$1 > xmax) {
      xmax = p.$1;
    }
    if (p.$2 < ymin) {
      ymin = p.$2;
    }
    if (p.$2 > ymax) {
      ymax = p.$2;
    }
  }
  final int content = 4 + 32 + 4 + 4 + parts.length * 4 + points.length * 16;
  final Uint8List bytes = Uint8List(100 + 8 + content);
  final ByteData d = ByteData.sublistView(bytes);
  d.setInt32(0, 9994, Endian.big);
  d.setInt32(24, bytes.length ~/ 2, Endian.big);
  d.setInt32(28, 1000, Endian.little);
  d.setInt32(32, 5, Endian.little);
  d.setFloat64(36, xmin, Endian.little);
  d.setFloat64(44, ymin, Endian.little);
  d.setFloat64(52, xmax, Endian.little);
  d.setFloat64(60, ymax, Endian.little);
  d.setInt32(100, 1, Endian.big);
  d.setInt32(104, content ~/ 2, Endian.big);
  var o = 108;
  d.setInt32(o, 5, Endian.little);
  o += 4;
  for (final double v in <double>[xmin, ymin, xmax, ymax]) {
    d.setFloat64(o, v, Endian.little);
    o += 8;
  }
  d.setInt32(o, parts.length, Endian.little);
  o += 4;
  d.setInt32(o, points.length, Endian.little);
  o += 4;
  var cursor = 0;
  for (final List<(double, double)> part in parts) {
    d.setInt32(o, cursor, Endian.little);
    o += 4;
    cursor += part.length;
  }
  for (final (double, double) p in points) {
    d.setFloat64(o, p.$1, Endian.little);
    o += 8;
    d.setFloat64(o, p.$2, Endian.little);
    o += 8;
  }
  return bytes;
}

Uint8List _dbf(String field, String value) {
  final Uint8List bytes = Uint8List(76);
  final ByteData d = ByteData.sublistView(bytes);
  bytes[0] = 0x03;
  d.setUint32(4, 1, Endian.little);
  d.setUint16(8, 65, Endian.little);
  d.setUint16(10, 11, Endian.little);
  final List<int> name = latin1.encode(field);
  bytes.setRange(32, 32 + name.length, name);
  bytes[43] = 0x43;
  bytes[48] = 10;
  bytes[64] = 0x0D;
  bytes[65] = 0x20;
  final List<int> cell = latin1.encode(value.padRight(10));
  bytes.setRange(66, 76, cell);
  return bytes;
}
