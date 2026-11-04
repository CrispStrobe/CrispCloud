/// Classified index of report templates.
library;

part 'suite_index.dart';

/// Domain a template belongs to.
enum TemplateCategory {
  /// Sales papers: invoice, quote, receipt, delivery.
  commerce,

  /// Money papers: statement, expense, payslip.
  finance,

  /// People papers: letter, certificate.
  people,

  /// Running the work: agenda, minutes, checklist, inspection.
  operations,

  /// Prose: memo, briefing.
  narrative,

  /// Numbers: KPI sheet, listing.
  data,

  /// School papers: report card, transcript, register.
  education,

  /// Property papers: rent, lease, unit handover.
  property,

  /// Movement of goods: waybill, pick list, transfer.
  logistics,

  /// Program papers: grant, distribution, volunteers.
  programs,
}

/// One entry in [TemplateCatalog]. [className] is the type to construct.
class TemplateRef {
  /// TemplateRef API.
  const TemplateRef({
    required this.id,
    required this.category,
    required this.className,
    required this.nameEn,
    required this.nameAr,
    required this.blurbEn,
    required this.blurbAr,
  });

  /// id API.
  final String id;

  /// category API.
  final TemplateCategory category;

  /// className API.
  final String className;

  /// nameEn API.
  final String nameEn;

  /// nameAr API.
  final String nameAr;

  /// blurbEn API.
  final String blurbEn;

  /// blurbAr API.
  final String blurbAr;

  /// name API.
  String name(bool arabic) => arabic ? nameAr : nameEn;

  /// blurb API.
  String blurb(bool arabic) => arabic ? blurbAr : blurbEn;
}

/// The template index. Construct the class named on each [TemplateRef].
abstract final class TemplateCatalog {
  /// invoice API.
  static const TemplateRef invoice = TemplateRef(
    id: 'commerce.invoice',
    category: TemplateCategory.commerce,
    className: 'InvoiceTemplate',
    nameEn: 'Invoice',
    nameAr: 'فاتورة',
    blurbEn: 'Seller, buyer, lines, totals.',
    blurbAr: 'بائع ومشترٍ وبنود ومجاميع.',
  );

  /// quote API.
  static const TemplateRef quote = TemplateRef(
    id: 'commerce.quote',
    category: TemplateCategory.commerce,
    className: 'QuoteTemplate',
    nameEn: 'Quote',
    nameAr: 'عرض سعر',
    blurbEn: 'Estimate with a validity date.',
    blurbAr: 'تقدير مع تاريخ صلاحية.',
  );

  /// receipt API.
  static const TemplateRef receipt = TemplateRef(
    id: 'commerce.receipt',
    category: TemplateCategory.commerce,
    className: 'ReceiptTemplate',
    nameEn: 'Receipt',
    nameAr: 'إيصال',
    blurbEn: 'Payment received, short lines.',
    blurbAr: 'دفعة مستلمة وبنود قصيرة.',
  );

  /// delivery API.
  static const TemplateRef delivery = TemplateRef(
    id: 'commerce.delivery',
    category: TemplateCategory.commerce,
    className: 'DeliveryNoteTemplate',
    nameEn: 'Delivery note',
    nameAr: 'إذن تسليم',
    blurbEn: 'Ordered versus shipped. No money.',
    blurbAr: 'المطلوب مقابل المشحون. بلا مبالغ.',
  );

  /// statement API.
  static const TemplateRef statement = TemplateRef(
    id: 'finance.statement',
    category: TemplateCategory.finance,
    className: 'StatementTemplate',
    nameEn: 'Statement',
    nameAr: 'كشف حساب',
    blurbEn: 'Opening, movements, closing.',
    blurbAr: 'افتتاحي وحركات وإغلاق.',
  );

  /// expense API.
  static const TemplateRef expense = TemplateRef(
    id: 'finance.expense',
    category: TemplateCategory.finance,
    className: 'ExpenseTemplate',
    nameEn: 'Expense claim',
    nameAr: 'مطالبة مصروف',
    blurbEn: 'Claimant, lines, approval.',
    blurbAr: 'مطالب وبنود واعتماد.',
  );

  /// payslip API.
  static const TemplateRef payslip = TemplateRef(
    id: 'finance.payslip',
    category: TemplateCategory.finance,
    className: 'PayslipTemplate',
    nameEn: 'Payslip',
    nameAr: 'قسيمة راتب',
    blurbEn: 'Earnings, deductions, net.',
    blurbAr: 'استحقاقات وخصومات وصافٍ.',
  );

  /// letter API.
  static const TemplateRef letter = TemplateRef(
    id: 'people.letter',
    category: TemplateCategory.people,
    className: 'LetterTemplate',
    nameEn: 'Letter',
    nameAr: 'رسالة',
    blurbEn: 'Addressee, subject, paragraphs, sign-off.',
    blurbAr: 'مرسل إليه وموضوع وفقرات وتوقيع.',
  );

  /// certificate API.
  static const TemplateRef certificate = TemplateRef(
    id: 'people.certificate',
    category: TemplateCategory.people,
    className: 'CertificateTemplate',
    nameEn: 'Certificate',
    nameAr: 'شهادة',
    blurbEn: 'Landscape award with two sign slots.',
    blurbAr: 'شهادة أفقية بفتحتي توقيع.',
  );

  /// agenda API.
  static const TemplateRef agenda = TemplateRef(
    id: 'operations.agenda',
    category: TemplateCategory.operations,
    className: 'AgendaTemplate',
    nameEn: 'Agenda',
    nameAr: 'جدول أعمال',
    blurbEn: 'When, where, timed items.',
    blurbAr: 'متى وأين وبنود موقوتة.',
  );

  /// minutes API.
  static const TemplateRef minutes = TemplateRef(
    id: 'operations.minutes',
    category: TemplateCategory.operations,
    className: 'MinutesTemplate',
    nameEn: 'Minutes',
    nameAr: 'محضر',
    blurbEn: 'Attendees, decisions, actions.',
    blurbAr: 'حضور وقرارات ومهام.',
  );

  /// checklist API.
  static const TemplateRef checklist = TemplateRef(
    id: 'operations.checklist',
    category: TemplateCategory.operations,
    className: 'ChecklistTemplate',
    nameEn: 'Checklist',
    nameAr: 'قائمة تحقق',
    blurbEn: 'Grouped items with a mark word you supply.',
    blurbAr: 'مجموعات وعلامة تكتبها أنت.',
  );

  /// inspection API.
  static const TemplateRef inspection = TemplateRef(
    id: 'operations.inspection',
    category: TemplateCategory.operations,
    className: 'InspectionTemplate',
    nameEn: 'Inspection',
    nameAr: 'تفتيش',
    blurbEn: 'Site sheet. Pass and fail counts are derived.',
    blurbAr: 'كشف موقع. أعداد النجاح والفشل محسوبة.',
  );

  /// memo API.
  static const TemplateRef memo = TemplateRef(
    id: 'narrative.memo',
    category: TemplateCategory.narrative,
    className: 'MemoTemplate',
    nameEn: 'Memo',
    nameAr: 'مذكرة',
    blurbEn: 'To, from, subject, sections.',
    blurbAr: 'إلى ومن وموضوع ومقاطع.',
  );

  /// briefing API.
  static const TemplateRef briefing = TemplateRef(
    id: 'narrative.briefing',
    category: TemplateCategory.narrative,
    className: 'BriefingTemplate',
    nameEn: 'Briefing',
    nameAr: 'إحاطة',
    blurbEn: 'Summary, metrics, optional chart, next steps.',
    blurbAr: 'ملخص ومؤشرات ورسم اختياري وخطوات.',
  );

  /// kpi API.
  static const TemplateRef kpi = TemplateRef(
    id: 'data.kpi',
    category: TemplateCategory.data,
    className: 'KpiSheetTemplate',
    nameEn: 'KPI sheet',
    nameAr: 'ورقة مؤشرات',
    blurbEn: 'Metric cards and an optional chart.',
    blurbAr: 'بطاقات مؤشرات ورسم اختياري.',
  );

  /// listing API.
  static const TemplateRef listing = TemplateRef(
    id: 'data.listing',
    category: TemplateCategory.data,
    className: 'ListingTemplate',
    nameEn: 'Listing',
    nameAr: 'كشف سجلات',
    blurbEn: 'Filter line and a typed table.',
    blurbAr: 'سطر تصفية وجدول بنوع محدد.',
  );

  /// Core papers. The suite index adds the rest.
  static const List<TemplateRef> core = <TemplateRef>[
    invoice,
    quote,
    receipt,
    delivery,
    statement,
    expense,
    payslip,
    letter,
    certificate,
    agenda,
    minutes,
    checklist,
    inspection,
    memo,
    briefing,
    kpi,
    listing,
  ];

  /// all API.
  static List<TemplateRef> get all => <TemplateRef>[
        ...core,
        ...suiteRefs,
      ];

  /// inCategory API.
  static List<TemplateRef> inCategory(TemplateCategory category) {
    return <TemplateRef>[
      for (final TemplateRef ref in all)
        if (ref.category == category) ref,
    ];
  }
}
