import 'dart:typed_data';

import 'package:quds_office_engine/pdf_templates.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  const TemplateParty seller = TemplateParty(
    name: 'North Dock',
    lines: <String>['Warehouse 4'],
  );
  const TemplateParty buyer = TemplateParty(name: 'River Clinic');
  const MoneyTotals totals = MoneyTotals(
    subtotal: '100',
    tax: '15',
    total: '115',
  );

  test('catalog covers every category and names a class', () {
    expect(TemplateCatalog.all.length, greaterThan(100));
    expect(TemplateCatalog.core, hasLength(17));
    final Set<String> ids = <String>{};
    for (final TemplateCategory category in TemplateCategory.values) {
      final List<TemplateRef> group = TemplateCatalog.inCategory(category);
      expect(group, isNotEmpty, reason: category.name);
      for (final TemplateRef ref in group) {
        expect(ids.add(ref.id), isTrue, reason: ref.id);
        expect(ref.className, endsWith('Template'));
        expect(ref.nameEn, isNotEmpty);
        expect(ref.nameAr, isNotEmpty);
      }
    }
  });

  test('invoice save extracts the caller strings', () {
    final Uint8List bytes = InvoiceTemplate(
      seller: seller,
      buyer: buyer,
      lines: const <TradeLine>[
        TradeLine(
          description: 'Field kit',
          quantity: '2',
          unit: '50',
          amount: '100',
        ),
      ],
      totals: totals,
      number: 'INV-14',
      labels: const TradeLabels(document: 'Invoice'),
    ).save();
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    final PdfFile file = PdfFile.open(bytes);
    final String text = PdfExtract.pageText(file, 0);
    expect(text, contains('North Dock'));
    expect(text, contains('Invoice'));
    expect(text, contains('Field kit'));
  });

  test('suite demo joins an English page and an Arabic page', () {
    final Uint8List english = TemplateSuite.demo(
      'commerce.purchase-order',
      arabic: false,
    );
    final Uint8List arabic = TemplateSuite.demo(
      'commerce.purchase-order',
      arabic: true,
    );
    final Uint8List both = joinTemplateFiles(<Uint8List>[english, arabic]);
    expect(PdfFile.open(both).pageCount, 2);
    expect(PdfExtract.pageText(PdfFile.open(both), 0), contains('Purchase order'));
  });

  test('rtl invoice save does not throw', () {
    final Uint8List bytes = InvoiceTemplate(
      direction: TextDirection.rtl,
      seller: seller,
      buyer: buyer,
      lines: const <TradeLine>[
        TradeLine(description: 'Kit', quantity: '1', unit: '10', amount: '10'),
      ],
      totals: const MoneyTotals(subtotal: '10', total: '10'),
      labels: const TradeLabels(document: 'Bill', from: 'From', to: 'To'),
    ).save();
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(PdfFile.open(bytes).pageCount, greaterThan(0));
  });

  test('every suite template saves in both directions', () {
    for (final String id in TemplateSuite.ids) {
      final Uint8List english = TemplateSuite.demo(id, arabic: false);
      final Uint8List arabic = TemplateSuite.demo(id, arabic: true);
      expect(String.fromCharCodes(english.take(5)), '%PDF-', reason: id);
      expect(String.fromCharCodes(arabic.take(5)), '%PDF-', reason: id);
    }
  });

  test('each template kind saves a readable file', () {
    final List<Uint8List> files = <Uint8List>[
      QuoteTemplate(
        seller: seller,
        buyer: buyer,
        totals: totals,
        lines: const <TradeLine>[TradeLine(description: 'Scope', amount: '100')],
      ).save(),
      ReceiptTemplate(
        seller: seller,
        buyer: buyer,
        totals: totals,
        lines: const <TradeLine>[TradeLine(description: 'Paid', amount: '115')],
      ).save(),
      DeliveryNoteTemplate(
        sender: seller,
        receiver: buyer,
        lines: const <TradeLine>[
          TradeLine(description: 'Crate', quantity: '4', detail: '4'),
        ],
      ).save(),
      StatementTemplate(
        issuer: seller,
        account: buyer,
        opening: '0',
        closing: '40',
        lines: const <StatementLine>[
          StatementLine(date: '01 Sep', detail: 'Fee', debit: '40', balance: '40'),
        ],
      ).save(),
      ExpenseTemplate(
        claimant: seller,
        total: '12',
        lines: const <ExpenseLine>[
          ExpenseLine(date: '02 Sep', category: 'Travel', amount: '12'),
        ],
      ).save(),
      PayslipTemplate(
        employer: seller,
        employee: buyer,
        net: '80',
        earnings: const <PayLine>[PayLine(label: 'Base', amount: '90')],
        deductions: const <PayLine>[PayLine(label: 'Tax', amount: '10')],
      ).save(),
      LetterTemplate(
        sender: seller,
        recipient: buyer,
        subject: 'Access window',
        paragraphs: const <String>['The gate opens at dawn.'],
      ).save(),
      CertificateTemplate(
        issuer: seller,
        recipient: 'Lina Haddad',
        award: 'Field lead',
        body: 'Awarded for the river clinic rotation.',
        signs: const <SignSlot>[SignSlot(role: 'Director')],
      ).save(),
      AgendaTemplate(
        host: seller,
        when: '14 Sep',
        items: const <AgendaItem>[
          AgendaItem(time: '09:00', title: 'Open', owner: 'Host'),
        ],
      ).save(),
      MinutesTemplate(
        host: seller,
        attendees: const <String>['Host', 'Clinic'],
        decisions: const <Decision>[Decision(text: 'Ship the kits.')],
        actions: const <ActionItem>[
          ActionItem(task: 'Confirm count', owner: 'Host', due: 'Friday'),
        ],
      ).save(),
      ChecklistTemplate(
        owner: seller,
        groups: const <CheckGroup>[
          CheckGroup(
            title: 'Gate',
            items: <CheckItem>[CheckItem(label: 'Locks', mark: CheckMark.done)],
          ),
        ],
      ).save(),
      InspectionTemplate(
        inspector: seller,
        site: 'Dock 2',
        items: const <CheckItem>[
          CheckItem(label: 'Ramp', mark: CheckMark.pass),
          CheckItem(label: 'Light', mark: CheckMark.fail, note: 'Out'),
        ],
      ).save(),
      MemoTemplate(
        from: seller,
        to: buyer,
        subject: 'Dock hours',
        sections: const <TemplateSection>[
          TemplateSection(heading: 'Change', body: 'Close at 18:00.'),
        ],
      ).save(),
      BriefingTemplate(
        author: seller,
        title: 'Week 37',
        summary: 'Kits moved on time.',
        metrics: const <BriefMetric>[BriefMetric(label: 'On time', value: '12')],
        chart: const <ChartPoint>[ChartPoint(label: 'Mon', value: 4)],
        next: const <String>['Recount Friday.'],
      ).save(),
      KpiSheetTemplate(
        owner: seller,
        period: 'Q3',
        metrics: const <KpiMetric>[KpiMetric(label: 'NPS', value: '72', delta: '+4')],
        chart: const <ChartPoint>[ChartPoint(label: 'Q3', value: 72)],
      ).save(),
      ListingTemplate(
        owner: seller,
        filter: 'Open',
        columns: const <String>['Id', 'Status'],
        rows: const <List<String>>[
          <String>['14', 'Open'],
        ],
      ).save(),
    ];
    for (final Uint8List bytes in files) {
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(PdfFile.open(bytes).pageCount, greaterThan(0));
    }
  });
}
