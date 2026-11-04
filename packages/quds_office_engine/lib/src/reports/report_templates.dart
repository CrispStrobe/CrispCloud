/// Report templates: catalog entries ([ReportTemplateInfo]) read from
/// template `.qrep` files, and the deprecated built-in [ReportTemplates].
///
/// Templates come in families: each family has an Arabic (right-to-left)
/// and an English (left-to-right) version, so both look the same. The
/// ready-made ones ship as `.qrep` files with `quds_office_editor`
/// (`ReportTemplateLibrary`); any `.qrep` with a `template.json`
/// ([ReportTemplateManifest]) is a template too.
library;

import 'dart:typed_data';

import 'report_package.dart';
import 'report_template_art.dart';
import 'report_template_manifest.dart';

/// What a template is for (designer grouping).
enum ReportTemplateCategory {
  /// Invoices, catalogs, quotations.
  sales('Sales', 'المبيعات'),

  /// Statements, vouchers, receipts.
  finance('Finance', 'المالية'),

  /// Stock and warehouse reports.
  inventory('Inventory', 'المخزون'),

  /// Dashboards and KPIs.
  analytics('Analytics', 'التحليلات'),

  /// Certificates and staff documents.
  hr('Human resources', 'الموارد البشرية');

  const ReportTemplateCategory(this.title, this.titleAr);

  /// English name.
  final String title;

  /// Arabic name.
  final String titleAr;

  /// [title] or [titleAr] for [arabic].
  String titleFor({required bool arabic}) => arabic ? titleAr : title;
}

/// Language a template prints in.
enum ReportTemplateLanguage {
  /// Left-to-right English.
  english('en', 'English'),

  /// Right-to-left Arabic.
  arabic('ar', 'العربية');

  const ReportTemplateLanguage(this.code, this.label);

  /// ISO 639-1 code (`ar`, `en`).
  final String code;

  /// Language name in the language itself.
  final String label;
}

/// One catalog entry: XML plus the sample data, images, and fonts it needs.
class ReportTemplateInfo {
  /// ReportTemplateInfo API.
  ///
  /// [xml] may contain `[[key]]` tokens filled from [strings] (XML-escaped)
  /// when [xml] is read; templates of one [family] share a layout and differ
  /// in [strings]. [images] draws the pictures saved with the report.
  const ReportTemplateInfo({
    required this.id,
    required this.title,
    required this.titleAr,
    required this.description,
    required this.descriptionAr,
    required this.category,
    required this.rtl,
    required String xml,
    required this.sampleData,
    String? family,
    this.strings = const <String, String>{},
    this._images,
    this._familyTitle,
    this._familyTitleAr,
    this.order = 0,
    this.subreports = const <String, String>{},
  }) : _layout = xml,
       family = family ?? id,
       _source = null;

  /// The template saved in [package], described by its
  /// [ReportPackage.template] manifest.
  ///
  /// Throws [ReportPackageException] when [package] has no manifest.
  ReportTemplateInfo.fromPackage(ReportPackage package)
    : this._manifest(
        package,
        package.template ??
            (throw const ReportPackageException(
              'Not a template: missing ${ReportTemplateManifest.entry}',
            )),
      );

  ReportTemplateInfo._manifest(ReportPackage package, ReportTemplateManifest m)
    : id = m.id,
      family = m.family,
      title = m.title,
      titleAr = m.titleAr,
      description = m.description,
      descriptionAr = m.descriptionAr,
      category = m.category,
      rtl = m.language == ReportTemplateLanguage.arabic,
      order = m.order,
      strings = const <String, String>{},
      _layout = package.xml,
      _familyTitle = m.familyTitle,
      _familyTitleAr = m.familyTitleAr,
      _images = (() => package.images),
      sampleData = (() => package.sampleData ?? <String, Object?>{}),
      subreports = package.subreports,
      _source = package;

  /// Reads a template `.qrep` ([ReportPackage.decode], then
  /// [ReportTemplateInfo.fromPackage]).
  ///
  /// Throws [ReportPackageException] when the file is damaged or is not a
  /// template.
  factory ReportTemplateInfo.decode(Uint8List bytes) =>
      ReportTemplateInfo.fromPackage(ReportPackage.decode(bytes));

  /// Stable identifier (`sales_invoice_ar`).
  final String id;

  /// Shared id of the language versions (`sales_invoice`).
  final String family;

  /// English title.
  final String title;

  /// Arabic title.
  final String titleAr;

  /// English summary of layout and bindings.
  final String description;

  /// Arabic summary.
  final String descriptionAr;

  /// category API.
  final ReportTemplateCategory category;

  /// Right-to-left layout (the Arabic version).
  final bool rtl;

  /// Values for the `[[key]]` tokens of the layout.
  final Map<String, String> strings;

  /// Position within its [category]; lower comes first.
  final int order;

  final String _layout;

  final ReportPackage? _source;

  final String? _familyTitle;

  final String? _familyTitleAr;

  final Map<String, Uint8List> Function()? _images;

  /// Data shaped like the bindings the template expects.
  final Map<String, Object?> Function() sampleData;

  /// Child layouts stored at `subreports/<name>.xml`.
  final Map<String, String> subreports;

  /// [ReportTemplateLanguage.arabic] for [rtl] templates.
  ReportTemplateLanguage get language =>
      rtl ? ReportTemplateLanguage.arabic : ReportTemplateLanguage.english;

  /// `.qrep` layout XML with every `[[key]]` token filled from [strings].
  ///
  /// Throws [StateError] when a token has no value.
  String get xml {
    if (strings.isEmpty) {
      return _layout;
    }
    return _layout.replaceAllMapped(_token, (Match m) {
      final String key = m.group(1)!;
      final String? value = strings[key];
      if (value == null) {
        throw StateError('Template $id: no string for [[$key]]');
      }
      return value
          .replaceAll('&', '&amp;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;')
          .replaceAll('"', '&quot;');
    });
  }

  static final RegExp _token = RegExp(r'\[\[(\w+)\]\]');

  /// Pictures saved with the report (logo, stamp, product photos, …),
  /// keyed as the layout's `<Image source>` expects. Empty when it has none.
  Map<String, Uint8List> images() =>
      _images?.call() ?? const <String, Uint8List>{};

  /// Complete `.qrep` package: layout, images, fonts, sample data, and
  /// [manifest]. A template read from a file returns that file's package.
  ReportPackage package() =>
      _source ??
      ReportPackage(
        xml: xml,
        images: images(),
        sampleData: sampleData(),
        template: manifest,
        subreports: subreports,
      );

  /// Catalog details as saved in a template `.qrep`.
  ReportTemplateManifest get manifest => ReportTemplateManifest(
    id: id,
    family: family,
    title: title,
    titleAr: titleAr,
    familyTitle: familyTitle,
    familyTitleAr: familyTitleAr,
    description: description,
    descriptionAr: descriptionAr,
    category: category,
    language: language,
    order: order,
  );

  /// Orders templates by [category], then [order], then family, Arabic
  /// before English.
  static int compare(ReportTemplateInfo a, ReportTemplateInfo b) {
    int c = a.category.index.compareTo(b.category.index);
    if (c == 0) {
      c = a.order.compareTo(b.order);
    }
    if (c == 0) {
      c = a.familyTitle.toLowerCase().compareTo(b.familyTitle.toLowerCase());
    }
    if (c == 0 && a.rtl != b.rtl) {
      c = a.rtl ? -1 : 1;
    }
    return c == 0 ? a.id.compareTo(b.id) : c;
  }

  /// [title] or [titleAr] for [arabic].
  String titleFor({required bool arabic}) => arabic ? titleAr : title;

  /// English title shared by the language versions (`VAT sales invoice`).
  String get familyTitle => _familyTitle ?? title;

  /// Arabic title shared by the language versions.
  String get familyTitleAr => _familyTitleAr ?? titleAr;

  /// [familyTitle] or [familyTitleAr] for [arabic].
  String familyTitleFor({required bool arabic}) =>
      arabic ? familyTitleAr : familyTitle;

  /// [description] or [descriptionAr] for [arabic].
  String descriptionFor({required bool arabic}) =>
      arabic ? descriptionAr : description;
}

/// Catalog of professional starting points, grouped by
/// [ReportTemplateCategory]; every family ships Arabic and English versions.
///
/// The same templates now ship as editable `.qrep` files with
/// `quds_office_editor` (`ReportTemplateLibrary.bundled()`); read any
/// template file with [ReportTemplateInfo.decode].
@Deprecated(
  'Use the ready-made .qrep files: ReportTemplateLibrary.bundled() in '
  'quds_office_editor, or ReportTemplateInfo.decode. Removed in 2.0.',
)
abstract final class ReportTemplates {
  /// Every template, in display order (families in order, Arabic first).
  static const List<ReportTemplateInfo> all = <ReportTemplateInfo>[
    ReportTemplateInfo(
      id: 'feature_showcase_ar',
      family: 'feature_showcase',
      title: 'Sales order (Arabic)',
      titleAr: 'أمر بيع (عربي)',
      familyTitle: 'Sales order',
      familyTitleAr: 'أمر بيع',
      description:
          'Sales order that asks for the customer, purchase order, and '
          'delivery date, then prints a rich confirmation, an italic note, '
          'an EAN-13 code, a nested delivery schedule, the item table, and '
          'a branch crosstab.',
      descriptionAr:
          'أمر بيع يسأل عن العميل وأمر الشراء وموعد التوريد، ثم يطبع تأكيداً '
          'غنياً وملاحظة مائلة ورمز EAN-13 وملحق توريد متداخلاً وجدول الأصناف '
          'وجدولاً محورياً للفروع.',
      category: ReportTemplateCategory.sales,
      rtl: true,
      order: -1,
      xml: _featureShowcase,
      strings: _featureShowcaseAr,
      sampleData: _featureShowcaseArData,
      images: _logoImages,
      subreports: _featureSubreportsAr,
    ),
    ReportTemplateInfo(
      id: 'feature_showcase_en',
      family: 'feature_showcase',
      title: 'Sales order (English)',
      titleAr: 'أمر بيع (إنجليزي)',
      familyTitle: 'Sales order',
      familyTitleAr: 'أمر بيع',
      description:
          'Sales order that asks for the customer, purchase order, and '
          'delivery date, then prints a rich confirmation, an italic note, '
          'an EAN-13 code, a nested delivery schedule, the item table, and '
          'a branch crosstab.',
      descriptionAr:
          'أمر بيع يسأل عن العميل وأمر الشراء وموعد التوريد، ثم يطبع تأكيداً '
          'غنياً وملاحظة مائلة ورمز EAN-13 وملحق توريد متداخلاً وجدول الأصناف '
          'وجدولاً محورياً للفروع.',
      category: ReportTemplateCategory.sales,
      rtl: false,
      order: -1,
      xml: _featureShowcase,
      strings: _featureShowcaseEn,
      sampleData: _featureShowcaseEnData,
      images: _logoImages,
      subreports: _featureSubreportsEn,
    ),
    ReportTemplateInfo(
      id: 'sales_invoice_ar',
      family: 'sales_invoice',
      title: 'VAT sales invoice (Arabic)',
      titleAr: 'فاتورة مبيعات ضريبية (عربي)',
      familyTitle: 'VAT sales invoice',
      familyTitleAr: 'فاتورة مبيعات ضريبية',
      description:
          'Tax invoice with logo, seller and customer blocks, QR code, item '
          'table, discount and VAT totals, amount in words, stamp and '
          'signature.',
      descriptionAr:
          'فاتورة ضريبية بالشعار وبيانات البائع والعميل ورمز QR وجدول '
          'الأصناف والخصم والضريبة والمبلغ بالحروف والختم والتوقيع.',
      category: ReportTemplateCategory.sales,
      rtl: true,
      xml: _salesInvoice,
      strings: _salesInvoiceAr,
      sampleData: _salesInvoiceArData,
      images: _brandImages,
    ),
    ReportTemplateInfo(
      id: 'sales_invoice_en',
      family: 'sales_invoice',
      title: 'VAT sales invoice (English)',
      titleAr: 'فاتورة مبيعات ضريبية (إنجليزي)',
      familyTitle: 'VAT sales invoice',
      familyTitleAr: 'فاتورة مبيعات ضريبية',
      description:
          'Tax invoice with logo, seller and customer blocks, QR code, item '
          'table, discount and VAT totals, amount in words, stamp and '
          'signature.',
      descriptionAr:
          'فاتورة ضريبية بالشعار وبيانات البائع والعميل ورمز QR وجدول '
          'الأصناف والخصم والضريبة والمبلغ بالحروف والختم والتوقيع.',
      category: ReportTemplateCategory.sales,
      rtl: false,
      xml: _salesInvoice,
      strings: _salesInvoiceEn,
      sampleData: _salesInvoiceEnData,
      images: _brandImages,
    ),
    ReportTemplateInfo(
      id: 'commercial_invoice_ar',
      family: 'commercial_invoice',
      title: 'Commercial invoice (Arabic)',
      titleAr: 'فاتورة تجارية (عربي)',
      familyTitle: 'Commercial invoice',
      familyTitleAr: 'فاتورة تجارية',
      description:
          'Modern invoice with logo, bill-to / ship-to, Code 128 invoice '
          'barcode, tax and shipping totals, and payment details.',
      descriptionAr:
          'فاتورة حديثة بالشعار وعنوان الفوترة والشحن وباركود رقم الفاتورة '
          'والضريبة والشحن وبيانات الدفع.',
      category: ReportTemplateCategory.sales,
      rtl: true,
      xml: _commercialInvoice,
      strings: _commercialInvoiceAr,
      sampleData: _commercialInvoiceArData,
      images: _logoImages,
    ),
    ReportTemplateInfo(
      id: 'invoice_en',
      family: 'commercial_invoice',
      title: 'Commercial invoice (English)',
      titleAr: 'فاتورة تجارية (إنجليزي)',
      familyTitle: 'Commercial invoice',
      familyTitleAr: 'فاتورة تجارية',
      description:
          'Modern invoice with logo, bill-to / ship-to, Code 128 invoice '
          'barcode, tax and shipping totals, and payment details.',
      descriptionAr:
          'فاتورة حديثة بالشعار وعنوان الفوترة والشحن وباركود رقم الفاتورة '
          'والضريبة والشحن وبيانات الدفع.',
      category: ReportTemplateCategory.sales,
      rtl: false,
      xml: _commercialInvoice,
      strings: _commercialInvoiceEn,
      sampleData: _commercialInvoiceEnData,
      images: _logoImages,
    ),
    ReportTemplateInfo(
      id: 'product_catalog_ar',
      family: 'product_catalog',
      title: 'Product catalog (Arabic)',
      titleAr: 'كتالوج المنتجات (عربي)',
      familyTitle: 'Product catalog',
      familyTitleAr: 'كتالوج المنتجات',
      description:
          'Price list with a product photo per row (saved in the report), '
          'grouped by category, with stock status and terms.',
      descriptionAr:
          'قائمة أسعار بصورة لكل منتج محفوظة في التقرير، مجمعة حسب الفئة، '
          'مع حالة التوفر والشروط.',
      category: ReportTemplateCategory.sales,
      rtl: true,
      xml: _productCatalog,
      strings: _productCatalogAr,
      sampleData: _productCatalogArData,
      images: _catalogImages,
    ),
    ReportTemplateInfo(
      id: 'product_catalog_en',
      family: 'product_catalog',
      title: 'Product catalog (English)',
      titleAr: 'كتالوج المنتجات (إنجليزي)',
      familyTitle: 'Product catalog',
      familyTitleAr: 'كتالوج المنتجات',
      description:
          'Price list with a product photo per row (saved in the report), '
          'grouped by category, with stock status and terms.',
      descriptionAr:
          'قائمة أسعار بصورة لكل منتج محفوظة في التقرير، مجمعة حسب الفئة، '
          'مع حالة التوفر والشروط.',
      category: ReportTemplateCategory.sales,
      rtl: false,
      xml: _productCatalog,
      strings: _productCatalogEn,
      sampleData: _productCatalogEnData,
      images: _catalogImages,
    ),
    ReportTemplateInfo(
      id: 'account_statement_ar',
      family: 'account_statement',
      title: 'Customer account statement (Arabic)',
      titleAr: 'كشف حساب عميل (عربي)',
      familyTitle: 'Customer account statement',
      familyTitleAr: 'كشف حساب عميل',
      description:
          'Debit / credit / running balance table with totals, balance '
          'summary cards, closing balance in words, and a balance trend chart.',
      descriptionAr:
          'جدول مدين ودائن ورصيد متحرك مع الإجماليات، بطاقات ملخص الرصيد، '
          'الرصيد الختامي بالحروف، ومخطط تطور الرصيد.',
      category: ReportTemplateCategory.finance,
      rtl: true,
      xml: _accountStatement,
      strings: _accountStatementAr,
      sampleData: _accountStatementArData,
      images: _logoImages,
    ),
    ReportTemplateInfo(
      id: 'account_statement_en',
      family: 'account_statement',
      title: 'Customer account statement (English)',
      titleAr: 'كشف حساب عميل (إنجليزي)',
      familyTitle: 'Customer account statement',
      familyTitleAr: 'كشف حساب عميل',
      description:
          'Debit / credit / running balance table with totals, balance '
          'summary cards, closing balance in words, and a balance trend chart.',
      descriptionAr:
          'جدول مدين ودائن ورصيد متحرك مع الإجماليات، بطاقات ملخص الرصيد، '
          'الرصيد الختامي بالحروف، ومخطط تطور الرصيد.',
      category: ReportTemplateCategory.finance,
      rtl: false,
      xml: _accountStatement,
      strings: _accountStatementEn,
      sampleData: _accountStatementEnData,
      images: _logoImages,
    ),
    ReportTemplateInfo(
      id: 'receipt_voucher_ar',
      family: 'receipt_voucher',
      title: 'Receipt voucher (Arabic)',
      titleAr: 'سند قبض (عربي)',
      familyTitle: 'Receipt voucher',
      familyTitleAr: 'سند قبض',
      description:
          'A5 landscape receipt voucher: logo, amount box, received-from, '
          'amount in words, payment method, stamp, and three signatures.',
      descriptionAr:
          'سند قبض بحجم A5 أفقي: الشعار، خانة المبلغ، استلمنا من، المبلغ '
          'بالحروف، طريقة الدفع، الختم، وثلاث خانات توقيع.',
      category: ReportTemplateCategory.finance,
      rtl: true,
      xml: _receiptVoucher,
      strings: _receiptVoucherAr,
      sampleData: _receiptVoucherArData,
      images: _brandImages,
    ),
    ReportTemplateInfo(
      id: 'receipt_voucher_en',
      family: 'receipt_voucher',
      title: 'Receipt voucher (English)',
      titleAr: 'سند قبض (إنجليزي)',
      familyTitle: 'Receipt voucher',
      familyTitleAr: 'سند قبض',
      description:
          'A5 landscape receipt voucher: logo, amount box, received-from, '
          'amount in words, payment method, stamp, and three signatures.',
      descriptionAr:
          'سند قبض بحجم A5 أفقي: الشعار، خانة المبلغ، استلمنا من، المبلغ '
          'بالحروف، طريقة الدفع، الختم، وثلاث خانات توقيع.',
      category: ReportTemplateCategory.finance,
      rtl: false,
      xml: _receiptVoucher,
      strings: _receiptVoucherEn,
      sampleData: _receiptVoucherEnData,
      images: _brandImages,
    ),
    ReportTemplateInfo(
      id: 'inventory_ar',
      family: 'inventory',
      title: 'Inventory status (Arabic)',
      titleAr: 'تقرير حالة المخزون (عربي)',
      familyTitle: 'Inventory status',
      familyTitleAr: 'تقرير حالة المخزون',
      description:
          'Stock KPIs, top items by value, value share by category, then '
          'items grouped by category with reorder status and subtotals.',
      descriptionAr:
          'مؤشرات المخزون، أعلى الأصناف قيمة، توزيع القيمة حسب الفئة، ثم '
          'الأصناف مجمعة حسب الفئة مع حالة إعادة الطلب والمجاميع.',
      category: ReportTemplateCategory.inventory,
      rtl: true,
      xml: _inventory,
      strings: _inventoryAr,
      sampleData: _inventoryArData,
    ),
    ReportTemplateInfo(
      id: 'inventory_en',
      family: 'inventory',
      title: 'Inventory status (English)',
      titleAr: 'تقرير حالة المخزون (إنجليزي)',
      familyTitle: 'Inventory status',
      familyTitleAr: 'تقرير حالة المخزون',
      description:
          'Stock KPIs, top items by value, value share by category, then '
          'items grouped by category with reorder status and subtotals.',
      descriptionAr:
          'مؤشرات المخزون، أعلى الأصناف قيمة، توزيع القيمة حسب الفئة، ثم '
          'الأصناف مجمعة حسب الفئة مع حالة إعادة الطلب والمجاميع.',
      category: ReportTemplateCategory.inventory,
      rtl: false,
      xml: _inventory,
      strings: _inventoryEn,
      sampleData: _inventoryEnData,
    ),
    ReportTemplateInfo(
      id: 'sales_performance_ar',
      family: 'sales_performance',
      title: 'Sales performance dashboard (Arabic)',
      titleAr: 'لوحة أداء المبيعات (عربي)',
      familyTitle: 'Sales performance dashboard',
      familyTitleAr: 'لوحة أداء المبيعات',
      description:
          'KPI cards, revenue-vs-target bars, category donut, orders trend, '
          'region ranking, then order details grouped by region.',
      descriptionAr:
          'بطاقات مؤشرات، أعمدة الإيراد مقابل المستهدف، حلقة الفئات، اتجاه '
          'الطلبات، ترتيب المناطق، ثم تفاصيل الطلبات مجمعة حسب المنطقة.',
      category: ReportTemplateCategory.analytics,
      rtl: true,
      xml: _salesPerformance,
      strings: _salesPerformanceAr,
      sampleData: _salesPerformanceArData,
      images: _logoImages,
    ),
    ReportTemplateInfo(
      id: 'sales_performance',
      family: 'sales_performance',
      title: 'Sales performance dashboard (English)',
      titleAr: 'لوحة أداء المبيعات (إنجليزي)',
      familyTitle: 'Sales performance dashboard',
      familyTitleAr: 'لوحة أداء المبيعات',
      description:
          'KPI cards, revenue-vs-target bars, category donut, orders trend, '
          'region ranking, then order details grouped by region.',
      descriptionAr:
          'بطاقات مؤشرات، أعمدة الإيراد مقابل المستهدف، حلقة الفئات، اتجاه '
          'الطلبات، ترتيب المناطق، ثم تفاصيل الطلبات مجمعة حسب المنطقة.',
      category: ReportTemplateCategory.analytics,
      rtl: false,
      xml: _salesPerformance,
      strings: _salesPerformanceEn,
      sampleData: _salesPerformanceEnData,
      images: _logoImages,
    ),
    ReportTemplateInfo(
      id: 'chart_gallery_ar',
      family: 'chart_gallery',
      title: 'Chart gallery (Arabic)',
      titleAr: 'معرض المخططات (عربي)',
      familyTitle: 'Chart gallery',
      familyTitleAr: 'معرض المخططات',
      description:
          'Every chart type, then a world shape map colored from a separate '
          'countries table (ISO code and revenue).',
      descriptionAr:
          'كل أنواع المخططات، ثم خريطة دول ملوّنة من جدول مستقل '
          '(رمز الدولة والإيراد).',
      category: ReportTemplateCategory.analytics,
      rtl: true,
      order: 70,
      xml: _chartGallery,
      strings: _chartGalleryAr,
      sampleData: _chartGalleryArData,
    ),
    ReportTemplateInfo(
      id: 'chart_gallery_en',
      family: 'chart_gallery',
      title: 'Chart gallery (English)',
      titleAr: 'معرض المخططات (إنجليزي)',
      familyTitle: 'Chart gallery',
      familyTitleAr: 'معرض المخططات',
      description:
          'Every chart type, then a world shape map colored from a separate '
          'countries table (ISO code and revenue).',
      descriptionAr:
          'كل أنواع المخططات، ثم خريطة دول ملوّنة من جدول مستقل '
          '(رمز الدولة والإيراد).',
      category: ReportTemplateCategory.analytics,
      rtl: false,
      order: 70,
      xml: _chartGallery,
      strings: _chartGalleryEn,
      sampleData: _chartGalleryEnData,
    ),
    ReportTemplateInfo(
      id: 'certificate_ar',
      family: 'certificate',
      title: 'Certificate of appreciation (Arabic)',
      titleAr: 'شهادة شكر وتقدير (عربي)',
      familyTitle: 'Certificate of appreciation',
      familyTitleAr: 'شهادة شكر وتقدير',
      description:
          'A4 landscape certificate with logo, gold seal, stamp, and '
          'signature saved in the report.',
      descriptionAr:
          'شهادة A4 أفقية بالشعار والختم الذهبي والختم الرسمي والتوقيع '
          'المحفوظة في التقرير.',
      category: ReportTemplateCategory.hr,
      rtl: true,
      xml: _certificate,
      strings: _certificateAr,
      sampleData: _certificateArData,
      images: _certificateImages,
    ),
    ReportTemplateInfo(
      id: 'certificate_en',
      family: 'certificate',
      title: 'Certificate of appreciation (English)',
      titleAr: 'شهادة شكر وتقدير (إنجليزي)',
      familyTitle: 'Certificate of appreciation',
      familyTitleAr: 'شهادة شكر وتقدير',
      description:
          'A4 landscape certificate with logo, gold seal, stamp, and '
          'signature saved in the report.',
      descriptionAr:
          'شهادة A4 أفقية بالشعار والختم الذهبي والختم الرسمي والتوقيع '
          'المحفوظة في التقرير.',
      category: ReportTemplateCategory.hr,
      rtl: false,
      xml: _certificate,
      strings: _certificateEn,
      sampleData: _certificateEnData,
      images: _certificateImages,
    ),
    ReportTemplateInfo(
      id: 'class_certificate_ar',
      family: 'class_certificate',
      title: 'Class certificates (Arabic)',
      titleAr: 'شهادات صف دراسي (عربي)',
      familyTitle: 'Class certificates',
      familyTitleAr: 'شهادات صف دراسي',
      description:
          'One A4 landscape certificate per row of the students table. '
          'Preview and PDF export print a page for every student.',
      descriptionAr:
          'شهادة A4 أفقية لكل صف في جدول الطلاب. المعاينة وتصدير PDF '
          'يطبعان صفحة لكل طالب.',
      category: ReportTemplateCategory.hr,
      rtl: true,
      order: 80,
      xml: _classCertificate,
      strings: _classCertificateAr,
      sampleData: _classCertificateArData,
      images: _certificateImages,
    ),
    ReportTemplateInfo(
      id: 'class_certificate_en',
      family: 'class_certificate',
      title: 'Class certificates (English)',
      titleAr: 'شهادات صف دراسي (إنجليزي)',
      familyTitle: 'Class certificates',
      familyTitleAr: 'شهادات صف دراسي',
      description:
          'One A4 landscape certificate per row of the students table. '
          'Preview and PDF export print a page for every student.',
      descriptionAr:
          'شهادة A4 أفقية لكل صف في جدول الطلاب. المعاينة وتصدير PDF '
          'يطبعان صفحة لكل طالب.',
      category: ReportTemplateCategory.hr,
      rtl: false,
      order: 80,
      xml: _classCertificate,
      strings: _classCertificateEn,
      sampleData: _classCertificateEnData,
      images: _certificateImages,
    ),
  ];

  /// Template with [id], or null.
  static ReportTemplateInfo? byId(String id) {
    for (final ReportTemplateInfo t in all) {
      if (t.id == id) {
        return t;
      }
    }
    return null;
  }

  /// Family ids in display order.
  static List<String> get families => <String>[
    for (final ReportTemplateInfo t in all)
      if (identical(_first(t.family), t)) t.family,
  ];

  /// Language versions of [family] (Arabic first).
  static List<ReportTemplateInfo> variants(String family) =>
      <ReportTemplateInfo>[
        for (final ReportTemplateInfo t in all)
          if (t.family == family) t,
      ];

  /// Version of [family] in [language], or null.
  static ReportTemplateInfo? find(
    String family,
    ReportTemplateLanguage language,
  ) {
    for (final ReportTemplateInfo t in all) {
      if (t.family == family && t.language == language) {
        return t;
      }
    }
    return null;
  }

  /// The other-language version of [info], or null.
  static ReportTemplateInfo? counterpart(ReportTemplateInfo info) => find(
    info.family,
    info.rtl ? ReportTemplateLanguage.english : ReportTemplateLanguage.arabic,
  );

  /// Templates of [category], in display order.
  static List<ReportTemplateInfo> inCategory(ReportTemplateCategory category) =>
      <ReportTemplateInfo>[
        for (final ReportTemplateInfo t in all)
          if (t.category == category) t,
      ];

  static ReportTemplateInfo _first(String family) =>
      all.firstWhere((ReportTemplateInfo t) => t.family == family);
}

// ------------------------------------------------------------------- images

final Map<String, Uint8List> _artCache = <String, Uint8List>{};

/// [draw] once per process; callers get their own copy.
Uint8List _art(String key, Uint8List Function() draw) =>
    Uint8List.fromList(_artCache.putIfAbsent(key, draw));

Map<String, Uint8List> _logoImages() => <String, Uint8List>{
  'logo': _art('logo', ReportTemplateArt.logo),
};

Map<String, Uint8List> _brandImages() => <String, Uint8List>{
  ..._logoImages(),
  'stamp': _art('stamp', ReportTemplateArt.stamp),
  'signature': _art('signature', ReportTemplateArt.signature),
};

Map<String, Uint8List> _catalogImages() => <String, Uint8List>{
  ..._logoImages(),
  for (final ReportProductArt p in ReportProductArt.values)
    'product_${p.name}': _art(
      'product_${p.name}',
      () => ReportTemplateArt.product(p),
    ),
};

Map<String, Uint8List> _certificateImages() => <String, Uint8List>{
  ..._brandImages(),
  'seal': _art('seal', ReportTemplateArt.seal),
};

// ------------------------------------------------------------------ strings

const Map<String, String> _ar = <String, String>{
  'rtl': 'true',
  'font': 'Noto Naskh Arabic',
  'lang': 'ar',
  'date': 'dd/MM/yyyy',
  'longDate': 'dateAr:d MMMM yyyy',
  'page': 'صفحة',
  'of': 'من',
  'cur': 'LYD',
  'money': 'currency:LYD',
  'n': 'n3',
};

const Map<String, String> _en = <String, String>{
  'rtl': 'false',
  'font': 'Liberation Sans',
  'lang': 'en',
  'date': 'dd MMM yyyy',
  'longDate': 'date:MMMM d, yyyy',
  'page': 'Page',
  'of': 'of',
  'cur': 'USD',
  'money': 'currencyCode:USD',
  'n': 'n2',
};

// ------------------------------------------------------------ sales invoice

const String _salesInvoice = r'''<?xml version="1.0" encoding="UTF-8"?>
<QudsReport name="[[name]]" isRtl="[[rtl]]" pageSize="A4" orientation="Portrait" defaultFont="[[font]]" defaultFontSize="9">
    <Settings>
        <Margins top="12mm" bottom="12mm" left="12mm" right="12mm"/>
        <Colors primary="#1F4E79" accent="#2E75B6" muted="#5F6B7A" light="#F3F6FA" border="#D9DEE7" text="#1F2933"/>
    </Settings>
    <Bands>
        <ReportHeader height="70mm">
            <Rectangle x="12mm" y="0mm" width="186mm" height="2.5mm" fill="primary" strokeWidth="0"/>
            <Image name="logo" source="logo" x="12mm" y="5mm" width="19mm" height="19mm"/>
            <Text name="sellerName" x="34mm" y="6mm" width="94mm" height="9mm" fontSize="15" bold="true" color="primary">{{Data.seller.name}}</Text>
            <Text x="34mm" y="15mm" width="94mm" height="5mm" fontSize="8" color="muted">{{Data.seller.address}}</Text>
            <Text x="34mm" y="20mm" width="94mm" height="5mm" fontSize="8" color="muted">[[phone]]: &#x2066;{{Data.seller.phone}}&#x2069;  •  [[vatNo]]: {{Data.seller.vatNo}}</Text>
            <Text name="title" x="130mm" y="5mm" width="68mm" height="12mm" fontSize="20" bold="true" color="primary" alignment="end">[[title]]</Text>
            <Text x="130mm" y="17mm" width="68mm" height="5mm" fontSize="8" color="muted" alignment="end">[[subtitle]]</Text>
            <Line x1="12mm" y1="28mm" x2="198mm" y2="28mm" color="border" strokeWidth="0.75"/>
            <Shape kind="RoundedRectangle" x="12mm" y="32mm" width="100mm" height="34mm" fill="light" strokeWidth="0" cornerRadius="3pt"/>
            <Text x="16mm" y="34mm" width="92mm" height="5mm" fontSize="8" bold="true" color="accent">[[billTo]]</Text>
            <Text name="customerName" x="16mm" y="40mm" width="92mm" height="7mm" fontSize="11" bold="true">{{Data.customer.name}}</Text>
            <Text x="16mm" y="47mm" width="92mm" height="5mm" fontSize="8.5" color="muted">{{Data.customer.address}}</Text>
            <Text x="16mm" y="53mm" width="92mm" height="5mm" fontSize="8.5" color="muted">[[vatNo]]: {{Data.customer.vatNo}}</Text>
            <Text x="16mm" y="59mm" width="92mm" height="5mm" fontSize="8.5" color="muted">[[phone]]: &#x2066;{{Data.customer.phone}}&#x2069;</Text>
            <Shape kind="RoundedRectangle" x="116mm" y="32mm" width="56mm" height="34mm" fill="#FFFFFF" color="border" strokeWidth="0.75" cornerRadius="3pt"/>
            <Text x="119mm" y="34mm" width="24mm" height="7mm" fontSize="8" color="muted" verticalAlignment="middle">[[invNo]]</Text>
            <Text name="invoiceNumber" x="143mm" y="34mm" width="27mm" height="7mm" fontSize="9" bold="true" alignment="end" verticalAlignment="middle">{{Data.invoice.number}}</Text>
            <Text x="119mm" y="42mm" width="24mm" height="7mm" fontSize="8" color="muted" verticalAlignment="middle">[[dateLabel]]</Text>
            <Text x="143mm" y="42mm" width="27mm" height="7mm" fontSize="9" bold="true" alignment="end" verticalAlignment="middle">{{Data.invoice.date | date:[[date]]}}</Text>
            <Text x="119mm" y="50mm" width="24mm" height="7mm" fontSize="8" color="muted" verticalAlignment="middle">[[due]]</Text>
            <Text x="143mm" y="50mm" width="27mm" height="7mm" fontSize="9" bold="true" alignment="end" verticalAlignment="middle">{{Data.invoice.dueDate | date:[[date]]}}</Text>
            <Text x="119mm" y="58mm" width="24mm" height="7mm" fontSize="8" color="muted" verticalAlignment="middle">[[method]]</Text>
            <Text x="143mm" y="58mm" width="27mm" height="7mm" fontSize="9" bold="true" alignment="end" verticalAlignment="middle">{{Data.invoice.paymentMethod}}</Text>
            <QrCode name="qrCode" x="175mm" y="32mm" width="23mm" height="23mm" value="INV:{{Data.invoice.number}};VAT:{{Data.seller.vatNo}};TOTAL:{{SUM(item.qty * item.price - item.discount) * (1 + Data.taxRate) | [[n]]}}"/>
            <Text x="175mm" y="56mm" width="23mm" height="5mm" fontSize="7" color="muted" alignment="center">[[scan]]</Text>
        </ReportHeader>
        <PageHeader height="9mm" printOnFirstPage="false">
            <Text x="12mm" y="1mm" width="186mm" height="6mm" fontSize="8" color="muted">{{Data.seller.name}} — [[invNo]] {{Data.invoice.number}} [[continued]]</Text>
            <Line x1="12mm" y1="7.5mm" x2="198mm" y2="7.5mm" color="border" strokeWidth="0.5"/>
        </PageHeader>
        <Detail dataSet="items" height="16mm">
            <Table name="itemsTable" x="12mm" y="0mm" width="186mm" showGrid="true" borderColor="border" headerBackground="primary" headerColor="#FFFFFF" stripeColor="light" fontSize="9" headerFontSize="9" rowHeight="7.5mm" headerHeight="8mm" padding="2pt">
                <Columns>
                    <Column width="8mm" header="#" align="center"/>
                    <Column width="22mm" header="[[colCode]]" align="center"/>
                    <Column width="64mm" header="[[colName]]" align="start"/>
                    <Column width="16mm" header="[[colUnit]]" align="center"/>
                    <Column width="16mm" header="[[colQty]]" align="center"/>
                    <Column width="22mm" header="[[colPrice]]" align="center"/>
                    <Column width="16mm" header="[[colDiscount]]" align="center"/>
                    <Column width="22mm" header="[[colTotal]]" align="center"/>
                </Columns>
                <RowTemplate>
                    <Cell field="System.RowNumber"/>
                    <Cell field="item.code"/>
                    <Cell field="item.name"/>
                    <Cell field="item.unit"/>
                    <Cell field="item.qty"/>
                    <Cell field="item.price" format="[[n]]"/>
                    <Cell field="item.discount" format="[[n]]"/>
                    <Cell field="item.qty * item.price - item.discount" format="[[n]]" bold="true"/>
                </RowTemplate>
            </Table>
        </Detail>
        <ReportSummary height="80mm" keepTogether="true">
            <Text x="12mm" y="5mm" width="110mm" height="5mm" fontSize="8" bold="true" color="accent">[[inWords]]</Text>
            <Text name="amountInWords" x="12mm" y="10mm" width="110mm" height="16mm" fontSize="9" bold="true">{{AMOUNTWORDS(SUM(item.qty * item.price - item.discount) * (1 + Data.taxRate), '[[cur]]', '[[lang]]')}}</Text>
            <Text x="12mm" y="28mm" width="110mm" height="5mm" fontSize="8" bold="true" color="accent">[[notes]]</Text>
            <Text name="notes" x="12mm" y="33mm" width="110mm" height="14mm" fontSize="8.5" color="muted">{{Data.notes}}</Text>
            <Text x="128mm" y="4mm" width="40mm" height="7mm" fontSize="9" color="muted" verticalAlignment="middle">[[subtotal]]</Text>
            <Text x="168mm" y="4mm" width="30mm" height="7mm" fontSize="9" alignment="end" verticalAlignment="middle">{{SUM(item.qty * item.price) | [[n]]}}</Text>
            <Text x="128mm" y="11mm" width="40mm" height="7mm" fontSize="9" color="muted" verticalAlignment="middle">[[discount]]</Text>
            <Text x="168mm" y="11mm" width="30mm" height="7mm" fontSize="9" alignment="end" verticalAlignment="middle">{{SUM(item.discount) | [[n]]}}</Text>
            <Text x="128mm" y="18mm" width="40mm" height="7mm" fontSize="9" color="muted" verticalAlignment="middle">[[net]]</Text>
            <Text x="168mm" y="18mm" width="30mm" height="7mm" fontSize="9" alignment="end" verticalAlignment="middle">{{SUM(item.qty * item.price - item.discount) | [[n]]}}</Text>
            <Text x="128mm" y="25mm" width="40mm" height="7mm" fontSize="9" color="muted" verticalAlignment="middle">[[vat]] ({{Data.taxRate | percent}})</Text>
            <Text x="168mm" y="25mm" width="30mm" height="7mm" fontSize="9" alignment="end" verticalAlignment="middle">{{SUM(item.qty * item.price - item.discount) * Data.taxRate | [[n]]}}</Text>
            <Shape kind="RoundedRectangle" x="128mm" y="33mm" width="70mm" height="10mm" fill="primary" strokeWidth="0" cornerRadius="3pt"/>
            <Text x="131mm" y="33mm" width="30mm" height="10mm" fontSize="10" bold="true" color="#FFFFFF" verticalAlignment="middle">[[totalDue]]</Text>
            <Text name="grandTotal" x="159mm" y="33mm" width="37mm" height="10mm" fontSize="11" bold="true" color="#FFFFFF" alignment="end" verticalAlignment="middle">{{SUM(item.qty * item.price - item.discount) * (1 + Data.taxRate) | [[money]]}}</Text>
            <Line x1="22mm" y1="66mm" x2="82mm" y2="66mm" color="muted" strokeWidth="0.6" lineStyle="dotted"/>
            <Text x="22mm" y="67mm" width="60mm" height="6mm" fontSize="8.5" color="muted" alignment="center">[[receiver]]</Text>
            <Image name="stamp" source="stamp" x="163mm" y="41mm" width="26mm" height="26mm"/>
            <Image name="signature" source="signature" x="130mm" y="51mm" width="42mm" height="15mm"/>
            <Line x1="128mm" y1="66mm" x2="188mm" y2="66mm" color="muted" strokeWidth="0.6" lineStyle="dotted"/>
            <Text x="128mm" y="67mm" width="60mm" height="6mm" fontSize="8.5" color="muted" alignment="center">[[approved]]</Text>
        </ReportSummary>
        <PageFooter height="10mm">
            <Line x1="12mm" y1="1mm" x2="198mm" y2="1mm" color="border" strokeWidth="0.5"/>
            <Text x="12mm" y="3mm" width="120mm" height="6mm" fontSize="8" color="muted">[[thanks]] — {{Data.seller.email}}</Text>
            <Text x="148mm" y="3mm" width="50mm" height="6mm" fontSize="8" color="muted" alignment="end">[[page]] {{System.PageNumber}} [[of]] {{System.TotalPages}}</Text>
        </PageFooter>
    </Bands>
</QudsReport>
''';

const Map<String, String> _salesInvoiceAr = <String, String>{
  ..._ar,
  'name': 'فاتورة مبيعات',
  'title': 'فاتورة مبيعات',
  'subtitle': 'TAX INVOICE',
  'phone': 'هاتف',
  'vatNo': 'الرقم الضريبي',
  'billTo': 'فاتورة إلى',
  'invNo': 'رقم الفاتورة',
  'dateLabel': 'التاريخ',
  'due': 'الاستحقاق',
  'method': 'طريقة الدفع',
  'scan': 'امسح للتحقق',
  'continued': '(تابع)',
  'colCode': 'الرمز',
  'colName': 'الوصف',
  'colUnit': 'الوحدة',
  'colQty': 'الكمية',
  'colPrice': 'سعر الوحدة',
  'colDiscount': 'الخصم',
  'colTotal': 'الإجمالي',
  'inWords': 'المبلغ بالحروف',
  'notes': 'ملاحظات وشروط',
  'subtotal': 'المجموع',
  'discount': 'الخصم',
  'net': 'الصافي قبل الضريبة',
  'vat': 'الضريبة',
  'totalDue': 'الإجمالي المستحق',
  'receiver': 'توقيع المستلم',
  'approved': 'الختم والتوقيع المعتمد',
  'thanks': 'شكرًا لتعاملكم معنا',
};

const Map<String, String> _salesInvoiceEn = <String, String>{
  ..._en,
  'name': 'Sales invoice',
  'title': 'TAX INVOICE',
  'subtitle': 'فاتورة مبيعات',
  'phone': 'Phone',
  'vatNo': 'VAT No.',
  'billTo': 'BILL TO',
  'invNo': 'Invoice No.',
  'dateLabel': 'Date',
  'due': 'Due date',
  'method': 'Payment',
  'scan': 'Scan to verify',
  'continued': '(continued)',
  'colCode': 'Code',
  'colName': 'Description',
  'colUnit': 'Unit',
  'colQty': 'Qty',
  'colPrice': 'Unit price',
  'colDiscount': 'Discount',
  'colTotal': 'Total',
  'inWords': 'AMOUNT IN WORDS',
  'notes': 'NOTES AND TERMS',
  'subtotal': 'Subtotal',
  'discount': 'Discount',
  'net': 'Net before VAT',
  'vat': 'VAT',
  'totalDue': 'Total due',
  'receiver': 'Received by',
  'approved': 'Authorized stamp and signature',
  'thanks': 'Thank you for your business',
};

const List<(String, String, String, String, String, int, int, int)>
_invoiceLines = <(String, String, String, String, String, int, int, int)>[
  (
    'LP-1420',
    'حاسوب محمول 14 بوصة — معالج i7',
    '14" laptop — Core i7',
    'قطعة',
    'pc',
    3,
    3250,
    150,
  ),
  (
    'MN-2701',
    'شاشة 27 بوصة دقة 4K',
    '27" 4K monitor',
    'قطعة',
    'pc',
    4,
    1180,
    0,
  ),
  (
    'KB-0310',
    'لوحة مفاتيح لاسلكية عربي/إنجليزي',
    'Wireless keyboard (Arabic / English)',
    'قطعة',
    'pc',
    10,
    95,
    25,
  ),
  (
    'MS-0450',
    'فأرة لاسلكية صامتة',
    'Silent wireless mouse',
    'قطعة',
    'pc',
    10,
    55,
    0,
  ),
  (
    'PR-9100',
    'طابعة ليزر ملونة',
    'Color laser printer',
    'قطعة',
    'pc',
    1,
    2100,
    100,
  ),
  (
    'CB-0006',
    'كابل شبكة Cat6 — 305 متر',
    'Cat6 network cable — 305 m',
    'لفة',
    'roll',
    2,
    420,
    0,
  ),
  (
    'SV-1000',
    'خدمة تركيب وتهيئة الأجهزة',
    'Installation and setup service',
    'خدمة',
    'service',
    1,
    850,
    50,
  ),
];

Map<String, Object?> _salesInvoiceArData() => _salesInvoiceData(true);

Map<String, Object?> _salesInvoiceEnData() => _salesInvoiceData(false);

Map<String, Object?> _salesInvoiceData(bool ar) {
  String t(String en, String arabic) => ar ? arabic : en;
  num money(int lyd) => ar ? lyd : lyd ~/ 5;
  return <String, Object?>{
    'seller': <String, Object?>{
      'name': t('Quds Technology Co.', 'شركة القدس للتقنية'),
      'address': t(
        '14 Republic Street, Tripoli',
        'طرابلس — شارع الجمهورية، مبنى 14',
      ),
      'phone': '+218 91 234 5678',
      'vatNo': '300123456700003',
      'email': 'sales@quds.ly',
    },
    'customer': <String, Object?>{
      'name': t('Al-Noor General Trading', 'مؤسسة النور للتجارة العامة'),
      'address': t(
        'River Road, 2nd floor, Benghazi',
        'بنغازي — طريق النهر، الدور الثاني',
      ),
      'vatNo': '310987654300003',
      'phone': '+218 92 765 4321',
    },
    'invoice': <String, Object?>{
      'number': 'INV-2026-0142',
      'date': DateTime(2026, 10, 10),
      'dueDate': DateTime(2026, 11, 9),
      'paymentMethod': t('Bank transfer', 'تحويل مصرفي'),
    },
    'taxRate': 0.15,
    'notes': t(
      'Goods sold cannot be returned or exchanged after 14 days from the '
          'invoice date. Please quote the invoice number when paying.',
      'البضاعة المباعة لا ترد ولا تستبدل بعد 14 يومًا من تاريخ الفاتورة. '
          'يرجى ذكر رقم الفاتورة عند التحويل.',
    ),
    'items': <Map<String, Object?>>[
      for (final (String, String, String, String, String, int, int, int) l
          in _invoiceLines)
        <String, Object?>{
          'code': l.$1,
          'name': ar ? l.$2 : l.$3,
          'unit': ar ? l.$4 : l.$5,
          'qty': l.$6,
          'price': money(l.$7),
          'discount': money(l.$8),
        },
    ],
  };
}

// ------------------------------------------------------- commercial invoice

const String _commercialInvoice = r'''<?xml version="1.0" encoding="UTF-8"?>
<QudsReport name="[[name]]" isRtl="[[rtl]]" pageSize="A4" orientation="Portrait" defaultFont="[[font]]" defaultFontSize="9">
    <Settings>
        <Margins top="12mm" bottom="12mm" left="12mm" right="12mm"/>
        <Colors primary="#0F766E" accent="#14B8A6" muted="#64748B" light="#F1F5F9" border="#E2E8F0" text="#0F172A"/>
    </Settings>
    <Bands>
        <ReportHeader height="66mm">
            <Image name="logo" source="logo" x="12mm" y="1mm" width="22mm" height="22mm"/>
            <Text name="companyName" x="37mm" y="2mm" width="90mm" height="10mm" fontSize="17" bold="true" color="primary">{{Data.company.name}}</Text>
            <Text x="37mm" y="12mm" width="90mm" height="5mm" fontSize="8.5" color="muted">{{Data.company.address}}</Text>
            <Text x="37mm" y="16.5mm" width="90mm" height="5mm" fontSize="8.5" color="muted">{{Data.company.city}}</Text>
            <Text x="37mm" y="21mm" width="90mm" height="5mm" fontSize="8.5" color="muted">&#x2066;{{Data.company.phone}}&#x2069;  |  {{Data.company.email}}</Text>
            <Text name="title" x="120mm" y="0mm" width="78mm" height="13mm" fontSize="26" bold="true" color="primary" alignment="end">[[title]]</Text>
            <Barcode name="invoiceBarcode" x="148mm" y="14mm" width="50mm" height="12mm" symbology="code128" value="{{Data.invoice.number}}" fontSize="7"/>
            <Rectangle x="12mm" y="30mm" width="186mm" height="0.8mm" fill="accent" strokeWidth="0"/>
            <Text x="12mm" y="34mm" width="60mm" height="5mm" fontSize="7.5" bold="true" color="primary">[[billTo]]</Text>
            <Text name="billToName" x="12mm" y="39mm" width="60mm" height="6mm" fontSize="10" bold="true">{{Data.billTo.name}}</Text>
            <Text x="12mm" y="45mm" width="60mm" height="5mm" fontSize="8.5" color="muted">{{Data.billTo.address}}</Text>
            <Text x="12mm" y="49.5mm" width="60mm" height="5mm" fontSize="8.5" color="muted">{{Data.billTo.city}}</Text>
            <Text x="12mm" y="54mm" width="60mm" height="5mm" fontSize="8.5" color="muted">{{Data.billTo.email}}</Text>
            <Text x="78mm" y="34mm" width="60mm" height="5mm" fontSize="7.5" bold="true" color="primary">[[shipTo]]</Text>
            <Text x="78mm" y="39mm" width="60mm" height="6mm" fontSize="10" bold="true">{{Data.shipTo.name}}</Text>
            <Text x="78mm" y="45mm" width="60mm" height="5mm" fontSize="8.5" color="muted">{{Data.shipTo.address}}</Text>
            <Text x="78mm" y="49.5mm" width="60mm" height="5mm" fontSize="8.5" color="muted">{{Data.shipTo.city}}</Text>
            <Shape kind="RoundedRectangle" x="144mm" y="34mm" width="54mm" height="27mm" fill="light" strokeWidth="0" cornerRadius="3pt"/>
            <Text x="147mm" y="36mm" width="22mm" height="5.5mm" fontSize="8" color="muted">[[invNo]]</Text>
            <Text name="invoiceNumber" x="169mm" y="36mm" width="27mm" height="5.5mm" fontSize="8.5" bold="true" alignment="end">{{Data.invoice.number}}</Text>
            <Text x="147mm" y="42mm" width="22mm" height="5.5mm" fontSize="8" color="muted">[[dateLabel]]</Text>
            <Text x="169mm" y="42mm" width="27mm" height="5.5mm" fontSize="8.5" bold="true" alignment="end">{{Data.invoice.date | date:[[date]]}}</Text>
            <Text x="147mm" y="48mm" width="22mm" height="5.5mm" fontSize="8" color="muted">[[due]]</Text>
            <Text x="169mm" y="48mm" width="27mm" height="5.5mm" fontSize="8.5" bold="true" alignment="end">{{Data.invoice.dueDate | date:[[date]]}}</Text>
            <Text x="147mm" y="54mm" width="22mm" height="5.5mm" fontSize="8" color="muted">[[po]]</Text>
            <Text x="169mm" y="54mm" width="27mm" height="5.5mm" fontSize="8.5" bold="true" alignment="end">{{Data.invoice.po}}</Text>
        </ReportHeader>
        <PageHeader height="9mm" printOnFirstPage="false">
            <Text x="12mm" y="1mm" width="186mm" height="6mm" fontSize="8" color="muted">{{Data.company.name}} — [[invNo]] {{Data.invoice.number}} [[continued]]</Text>
            <Line x1="12mm" y1="7.5mm" x2="198mm" y2="7.5mm" color="border" strokeWidth="0.5"/>
        </PageHeader>
        <Detail dataSet="items" height="16mm">
            <Table name="itemsTable" x="12mm" y="0mm" width="186mm" showGrid="false" headerBackground="primary" headerColor="#FFFFFF" stripeColor="light" fontSize="9" headerFontSize="8.5" rowHeight="7.5mm" headerHeight="8mm" padding="3pt">
                <Columns>
                    <Column width="8mm" header="#" align="center"/>
                    <Column width="24mm" header="[[colSku]]" align="start"/>
                    <Column width="82mm" header="[[colDescription]]" align="start"/>
                    <Column width="16mm" header="[[colQty]]" align="center"/>
                    <Column width="26mm" header="[[colPrice]]" align="end"/>
                    <Column width="30mm" header="[[colAmount]]" align="end"/>
                </Columns>
                <RowTemplate>
                    <Cell field="System.RowNumber"/>
                    <Cell field="item.sku"/>
                    <Cell field="item.description"/>
                    <Cell field="item.qty"/>
                    <Cell field="item.unitPrice" format="n2"/>
                    <Cell field="item.qty * item.unitPrice" format="n2" bold="true"/>
                </RowTemplate>
            </Table>
        </Detail>
        <ReportSummary height="72mm" keepTogether="true">
            <Line x1="12mm" y1="1mm" x2="198mm" y2="1mm" color="border" strokeWidth="0.75"/>
            <Text x="134mm" y="4mm" width="32mm" height="6.5mm" fontSize="9" color="muted">[[subtotal]]</Text>
            <Text x="166mm" y="4mm" width="32mm" height="6.5mm" fontSize="9" alignment="end">{{SUM(item.qty * item.unitPrice) | n2}}</Text>
            <Text x="134mm" y="10.5mm" width="32mm" height="6.5mm" fontSize="9" color="muted">[[tax]] ({{Data.taxRate | percent:1}})</Text>
            <Text x="166mm" y="10.5mm" width="32mm" height="6.5mm" fontSize="9" alignment="end">{{SUM(item.qty * item.unitPrice) * Data.taxRate | n2}}</Text>
            <Text x="134mm" y="17mm" width="32mm" height="6.5mm" fontSize="9" color="muted">[[shipping]]</Text>
            <Text x="166mm" y="17mm" width="32mm" height="6.5mm" fontSize="9" alignment="end">{{Data.shipping | n2}}</Text>
            <Shape kind="RoundedRectangle" x="132mm" y="25mm" width="66mm" height="11mm" fill="primary" strokeWidth="0" cornerRadius="3pt"/>
            <Text x="135mm" y="25mm" width="26mm" height="11mm" fontSize="10" bold="true" color="#FFFFFF" verticalAlignment="middle">[[totalDue]]</Text>
            <Text name="grandTotal" x="159mm" y="25mm" width="37mm" height="11mm" fontSize="11" bold="true" color="#FFFFFF" alignment="end" verticalAlignment="middle">{{SUM(item.qty * item.unitPrice) * (1 + Data.taxRate) + Data.shipping | [[money]]}}</Text>
            <Text x="12mm" y="5mm" width="110mm" height="5mm" fontSize="7.5" bold="true" color="primary">[[payment]]</Text>
            <Text x="12mm" y="10.5mm" width="110mm" height="5mm" fontSize="8.5">[[bank]]: {{Data.payment.bank}}</Text>
            <Text x="12mm" y="15.5mm" width="110mm" height="5mm" fontSize="8.5">IBAN: &#x2066;{{Data.payment.iban}}&#x2069;</Text>
            <Text x="12mm" y="20.5mm" width="110mm" height="5mm" fontSize="8.5">[[terms]]: {{Data.payment.terms}}</Text>
            <Text x="12mm" y="29mm" width="110mm" height="5mm" fontSize="7.5" bold="true" color="primary">[[notes]]</Text>
            <Text name="notes" x="12mm" y="34.5mm" width="110mm" height="14mm" fontSize="8.5" color="muted">{{Data.notes}}</Text>
            <Text x="12mm" y="56mm" width="186mm" height="8mm" fontSize="12" bold="true" color="primary" alignment="center">[[thanks]]</Text>
        </ReportSummary>
        <PageFooter height="9mm">
            <Line x1="12mm" y1="1mm" x2="198mm" y2="1mm" color="border" strokeWidth="0.5"/>
            <Text x="12mm" y="2.5mm" width="120mm" height="5.5mm" fontSize="7.5" color="muted">{{Data.company.website}}</Text>
            <Text x="148mm" y="2.5mm" width="50mm" height="5.5mm" fontSize="7.5" color="muted" alignment="end">[[page]] {{System.PageNumber}} [[of]] {{System.TotalPages}}</Text>
        </PageFooter>
    </Bands>
</QudsReport>
''';

const Map<String, String> _commercialInvoiceAr = <String, String>{
  ..._ar,
  'name': 'فاتورة تجارية',
  'title': 'فاتورة',
  'billTo': 'فاتورة إلى',
  'shipTo': 'الشحن إلى',
  'invNo': 'رقم الفاتورة',
  'dateLabel': 'التاريخ',
  'due': 'الاستحقاق',
  'po': 'أمر الشراء',
  'continued': '(تابع)',
  'colSku': 'الرمز',
  'colDescription': 'الوصف',
  'colQty': 'الكمية',
  'colPrice': 'سعر الوحدة',
  'colAmount': 'المبلغ',
  'subtotal': 'المجموع',
  'tax': 'الضريبة',
  'shipping': 'الشحن',
  'totalDue': 'المستحق',
  'payment': 'بيانات الدفع',
  'bank': 'المصرف',
  'terms': 'الشروط',
  'notes': 'ملاحظات',
  'thanks': 'شكرًا لثقتكم بنا',
};

const Map<String, String> _commercialInvoiceEn = <String, String>{
  ..._en,
  'name': 'Commercial Invoice',
  'title': 'INVOICE',
  'billTo': 'BILL TO',
  'shipTo': 'SHIP TO',
  'invNo': 'Invoice #',
  'dateLabel': 'Date',
  'due': 'Due date',
  'po': 'PO #',
  'continued': '(continued)',
  'colSku': 'SKU',
  'colDescription': 'DESCRIPTION',
  'colQty': 'QTY',
  'colPrice': 'UNIT PRICE',
  'colAmount': 'AMOUNT',
  'subtotal': 'Subtotal',
  'tax': 'Tax',
  'shipping': 'Shipping',
  'totalDue': 'TOTAL DUE',
  'payment': 'PAYMENT DETAILS',
  'bank': 'Bank',
  'terms': 'Terms',
  'notes': 'NOTES',
  'thanks': 'Thank you for your business!',
};

const List<(String, String, String, int, int)> _commercialLines =
    <(String, String, String, int, int)>[
      (
        'QOS-ENT',
        'Quds Office Suite — Enterprise license (per seat)',
        'حزمة القدس المكتبية — ترخيص مؤسسات (لكل مستخدم)',
        25,
        180,
      ),
      (
        'QOS-RPT',
        'Report designer add-on (per seat)',
        'إضافة مصمم التقارير (لكل مستخدم)',
        10,
        65,
      ),
      (
        'SUP-PRM',
        'Premium support — 12 months',
        'دعم فني مميز — 12 شهرًا',
        1,
        2400,
      ),
      (
        'TRN-DEV',
        'Developer training workshop (2 days)',
        'ورشة تدريب المطورين (يومان)',
        1,
        1850,
      ),
      (
        'MIG-SRV',
        'Template migration service (per template)',
        'خدمة ترحيل القوالب (لكل قالب)',
        12,
        95,
      ),
      (
        'CLD-STR',
        'Cloud document storage — 1 TB / year',
        'تخزين سحابي للمستندات — 1 تيرابايت سنويًا',
        2,
        320,
      ),
    ];

Map<String, Object?> _commercialInvoiceArData() => _commercialInvoiceData(true);

Map<String, Object?> _commercialInvoiceEnData() =>
    _commercialInvoiceData(false);

Map<String, Object?> _commercialInvoiceData(bool ar) {
  String t(String en, String arabic) => ar ? arabic : en;
  final int rate = ar ? 5 : 1;
  return <String, Object?>{
    'company': <String, Object?>{
      'name': t('Quds Software Ltd.', 'شركة القدس للبرمجيات'),
      'address': t(
        '14 Republic Street, Suite 300',
        'شارع الجمهورية 14، الجناح 300',
      ),
      'city': t('Tripoli, Libya', 'طرابلس، ليبيا'),
      'phone': '+218 21 444 0101',
      'email': 'billing@quds.dev',
      'website': 'www.quds.dev',
    },
    'billTo': <String, Object?>{
      'name': t('Northwind Traders', 'شركة الريح الشمالية للتجارة'),
      'address': t('120 Harbor Road', 'طريق الميناء 120'),
      'city': t('Valletta, Malta', 'فاليتا، مالطا'),
      'email': 'accounts@northwind.example',
    },
    'shipTo': <String, Object?>{
      'name': t('Northwind Warehouse 2', 'مستودع الريح الشمالية 2'),
      'address': t('Unit 7, Freeport Zone', 'الوحدة 7، المنطقة الحرة'),
      'city': t('Marsaxlokk, Malta', 'مارساشلوك، مالطا'),
    },
    'invoice': <String, Object?>{
      'number': 'QS-2026-0381',
      'date': DateTime(2026, 10, 10),
      'dueDate': DateTime(2026, 11, 9),
      'po': 'PO-77812',
    },
    'taxRate': 0.075,
    'shipping': 45 * rate,
    'payment': <String, Object?>{
      'bank': t('Mediterranean Commercial Bank', 'مصرف البحر المتوسط التجاري'),
      'iban': 'LY83 0020 4800 0000 1234 5678',
      'terms': t('Net 30 days', 'السداد خلال 30 يومًا'),
    },
    'notes': t(
      'Licenses are activated on receipt of payment. Support renewals are '
          'billed annually from the activation date.',
      'تُفعَّل التراخيص عند استلام الدفعة، ويُجدَّد الدعم الفني سنويًا من '
          'تاريخ التفعيل.',
    ),
    'items': <Map<String, Object?>>[
      for (final (String, String, String, int, int) l in _commercialLines)
        <String, Object?>{
          'sku': l.$1,
          'description': ar ? l.$3 : l.$2,
          'qty': l.$4,
          'unitPrice': l.$5 * rate,
        },
    ],
  };
}

// ---------------------------------------------------------- product catalog

const String _productCatalog = r'''<?xml version="1.0" encoding="UTF-8"?>
<QudsReport name="[[name]]" isRtl="[[rtl]]" pageSize="A4" orientation="Portrait" defaultFont="[[font]]" defaultFontSize="9">
    <Settings>
        <Margins top="12mm" bottom="12mm" left="12mm" right="12mm"/>
        <Colors primary="#0F3D5E" accent="#F59E0B" muted="#64748B" light="#F1F5F9" border="#E2E8F0" text="#0F172A" good="#15803D" alert="#B91C1C"/>
    </Settings>
    <Bands>
        <ReportHeader height="48mm">
            <Shape kind="RoundedRectangle" x="12mm" y="0mm" width="186mm" height="34mm" fill="primary" strokeWidth="0" cornerRadius="4pt"/>
            <Image name="logo" source="logo" x="17mm" y="4mm" width="26mm" height="26mm"/>
            <Text name="title" x="48mm" y="4mm" width="108mm" height="11mm" fontSize="20" bold="true" color="#FFFFFF">[[title]]</Text>
            <Text x="48mm" y="15mm" width="108mm" height="6mm" fontSize="9.5" color="#E0F2FE">{{Data.company.name}} — {{Data.season}}</Text>
            <Text x="48mm" y="22mm" width="108mm" height="6mm" fontSize="8" color="#BAE6FD">[[validUntil]] {{Data.validUntil | date:[[date]]}}</Text>
            <Shape kind="RoundedRectangle" x="161mm" y="8mm" width="32mm" height="18mm" fill="accent" strokeWidth="0" cornerRadius="3pt"/>
            <Text x="161mm" y="8.5mm" width="32mm" height="10mm" fontSize="14" bold="true" color="#FFFFFF" alignment="center" verticalAlignment="middle">{{COUNT(item.sku)}}</Text>
            <Text x="161mm" y="18mm" width="32mm" height="6mm" fontSize="7.5" color="#FFFFFF" alignment="center">[[products]]</Text>
            <Text name="intro" x="12mm" y="38mm" width="186mm" height="8mm" fontSize="8.5" color="muted">{{Data.intro}}</Text>
        </ReportHeader>
        <PageHeader height="9mm" printOnFirstPage="false">
            <Text x="12mm" y="1mm" width="186mm" height="6mm" fontSize="8" color="muted">[[title]] — {{Data.company.name}} [[continued]]</Text>
            <Line x1="12mm" y1="7.5mm" x2="198mm" y2="7.5mm" color="border" strokeWidth="0.5"/>
        </PageHeader>
        <GroupHeader height="11mm" groupBy="item.category" keepTogether="true">
            <Text x="12mm" y="2mm" width="140mm" height="7mm" fontSize="11" bold="true" color="primary">{{Group.Key}}</Text>
            <Text x="150mm" y="2mm" width="48mm" height="7mm" fontSize="8" color="muted" alignment="end" verticalAlignment="middle">{{Group.Count}} [[items]]</Text>
            <Line x1="12mm" y1="9.5mm" x2="198mm" y2="9.5mm" color="accent" strokeWidth="1"/>
        </GroupHeader>
        <Detail dataSet="items" height="34mm">
            <Shape kind="RoundedRectangle" x="12mm" y="1.5mm" width="186mm" height="31mm" fill="#FFFFFF" color="border" strokeWidth="0.6" cornerRadius="3pt"/>
            <Image name="productPhoto" source="{{item.photo}}" x="14mm" y="3mm" width="37mm" height="28mm" fit="cover"/>
            <Text name="productName" x="55mm" y="3.5mm" width="100mm" height="7mm" fontSize="11" bold="true">{{item.name}}</Text>
            <Text x="55mm" y="10mm" width="100mm" height="5mm" fontSize="7.5" color="muted">[[sku]]: {{item.sku}}  •  [[warranty]]: {{item.warranty}}</Text>
            <Text x="55mm" y="15.5mm" width="100mm" height="15mm" fontSize="8.5" color="#334155">{{item.description}}</Text>
            <Shape kind="RoundedRectangle" x="159mm" y="5mm" width="35mm" height="11mm" fill="light" strokeWidth="0" cornerRadius="3pt"/>
            <Text name="price" x="159mm" y="5mm" width="35mm" height="11mm" fontSize="10.5" bold="true" color="primary" alignment="center" verticalAlignment="middle">{{item.price | [[money]]}}</Text>
            <Text x="159mm" y="18mm" width="35mm" height="5mm" fontSize="8" bold="true" color="good" alignment="center" visibleWhen="item.stock &gt; 0">[[inStock]]</Text>
            <Text x="159mm" y="18mm" width="35mm" height="5mm" fontSize="8" bold="true" color="alert" alignment="center" visibleWhen="item.stock = 0">[[outOfStock]]</Text>
            <Text x="159mm" y="23.5mm" width="35mm" height="5mm" fontSize="7.5" color="muted" alignment="center">{{item.stock}} [[units]]</Text>
        </Detail>
        <ReportSummary height="24mm" keepTogether="true">
            <Shape kind="RoundedRectangle" x="12mm" y="4mm" width="186mm" height="17mm" fill="light" strokeWidth="0" cornerRadius="3pt"/>
            <Text x="16mm" y="5mm" width="178mm" height="6mm" fontSize="8.5" bold="true" color="primary">[[terms]]</Text>
            <Text name="terms" x="16mm" y="11mm" width="178mm" height="9mm" fontSize="8" color="muted">{{Data.terms}}</Text>
        </ReportSummary>
        <PageFooter height="9mm">
            <Line x1="12mm" y1="1mm" x2="198mm" y2="1mm" color="border" strokeWidth="0.5"/>
            <Text x="12mm" y="2.5mm" width="120mm" height="5.5mm" fontSize="7.5" color="muted">{{Data.company.website}}  •  &#x2066;{{Data.company.phone}}&#x2069;</Text>
            <Text x="148mm" y="2.5mm" width="50mm" height="5.5mm" fontSize="7.5" color="muted" alignment="end">[[page]] {{System.PageNumber}} [[of]] {{System.TotalPages}}</Text>
        </PageFooter>
    </Bands>
</QudsReport>
''';

const Map<String, String> _productCatalogAr = <String, String>{
  ..._ar,
  'name': 'كتالوج المنتجات',
  'title': 'كتالوج المنتجات',
  'validUntil': 'الأسعار سارية حتى',
  'products': 'منتج',
  'continued': '(تابع)',
  'items': 'منتجات',
  'sku': 'الرمز',
  'warranty': 'الضمان',
  'inStock': 'متوفر',
  'outOfStock': 'غير متوفر',
  'units': 'قطعة في المخزن',
  'terms': 'الشروط والأحكام',
};

const Map<String, String> _productCatalogEn = <String, String>{
  ..._en,
  'name': 'Product catalog',
  'title': 'Product Catalog',
  'validUntil': 'Prices valid until',
  'products': 'products',
  'continued': '(continued)',
  'items': 'items',
  'sku': 'SKU',
  'warranty': 'Warranty',
  'inStock': 'In stock',
  'outOfStock': 'Out of stock',
  'units': 'units in stock',
  'terms': 'TERMS AND CONDITIONS',
};

const List<
  (ReportProductArt, String, String, String, String, String, String, int, int)
>
_catalogLines = <(ReportProductArt, String, String, String, String, String, String, int, int)>[
  (
    ReportProductArt.laptop,
    'LP-1420',
    'Computers',
    'حواسيب',
    'UltraBook 14 Pro',
    'حاسوب ألترابوك 14 برو',
    '14" 2.8K display, Core i7, 16 GB RAM, 1 TB SSD, backlit Arabic / English keyboard.|شاشة 14 بوصة بدقة 2.8K، معالج Core i7، ذاكرة 16 جيجابايت، تخزين 1 تيرابايت، لوحة مفاتيح مضيئة عربي/إنجليزي.',
    3250,
    18,
  ),
  (
    ReportProductArt.tablet,
    'TB-1100',
    'Computers',
    'حواسيب',
    'Tab 11 Air',
    'جهاز لوحي تاب 11 إير',
    '11" tablet, 256 GB, stylus support, all-day battery for field teams.|جهاز لوحي 11 بوصة، سعة 256 جيجابايت، يدعم القلم، وبطارية تدوم طوال اليوم لفرق العمل الميداني.',
    1690,
    0,
  ),
  (
    ReportProductArt.monitor,
    'MN-2701',
    'Displays',
    'شاشات',
    'View 27 4K',
    'شاشة فيو 27 بدقة 4K',
    '27" IPS 4K monitor, 99% sRGB, USB-C 65 W charging, height-adjustable stand.|شاشة IPS مقاس 27 بوصة بدقة 4K، تغطية 99% sRGB، شحن USB-C بقدرة 65 واط، وقاعدة قابلة لتعديل الارتفاع.',
    1180,
    9,
  ),
  (
    ReportProductArt.keyboard,
    'KB-0310',
    'Accessories',
    'ملحقات',
    'Silent Keys wireless keyboard',
    'لوحة مفاتيح لاسلكية صامتة',
    'Low-profile silent keys, Arabic / English layout, three-device switching.|مفاتيح منخفضة وصامتة، تخطيط عربي/إنجليزي، والتبديل بين ثلاثة أجهزة.',
    95,
    64,
  ),
  (
    ReportProductArt.mouse,
    'MS-0450',
    'Accessories',
    'ملحقات',
    'Glide silent mouse',
    'فأرة غلايد الصامتة',
    'Ergonomic wireless mouse with silent clicks and a 24-month battery.|فأرة لاسلكية مريحة بنقرات صامتة وبطارية تدوم 24 شهرًا.',
    55,
    22,
  ),
  (
    ReportProductArt.headset,
    'HS-0200',
    'Accessories',
    'ملحقات',
    'Studio headset',
    'سماعة رأس ستوديو',
    'Noise-cancelling headset with boom microphone, certified for online meetings.|سماعة رأس بعزل الضوضاء وميكروفون متحرك، معتمدة للاجتماعات عبر الإنترنت.',
    115,
    35,
  ),
  (
    ReportProductArt.printer,
    'PR-9100',
    'Printers',
    'طابعات',
    'ColorJet laser printer',
    'طابعة ليزر ملونة كولورجت',
    'Color laser, 28 ppm, duplex, Wi-Fi and mobile printing.|طابعة ليزر ملونة بسرعة 28 صفحة في الدقيقة، طباعة على الوجهين، واي فاي وطباعة من الهاتف.',
    2100,
    4,
  ),
  (
    ReportProductArt.router,
    'RT-0600',
    'Networking',
    'شبكات',
    'Mesh Wi-Fi 6 router',
    'موجه شبكي واي فاي 6',
    'Tri-band Wi-Fi 6 router, covers 250 m², guest network and parental controls.|موجه ثلاثي النطاق بتقنية واي فاي 6، يغطي 250 م²، مع شبكة للضيوف ورقابة أبوية.',
    560,
    2,
  ),
];

Map<String, Object?> _productCatalogArData() => _productCatalogData(true);

Map<String, Object?> _productCatalogEnData() => _productCatalogData(false);

Map<String, Object?> _productCatalogData(bool ar) {
  String t(String en, String arabic) => ar ? arabic : en;
  return <String, Object?>{
    'company': <String, Object?>{
      'name': t('Quds Technology Co.', 'شركة القدس للتقنية'),
      'website': 'www.quds.ly',
      'phone': '+218 21 444 0101',
    },
    'season': t('Autumn 2026', 'خريف 2026'),
    'validUntil': DateTime(2026, 12, 31),
    'intro': t(
      'Prices include VAT. Volume discounts are available for orders of ten '
          'units or more; contact your account manager for a quotation.',
      'الأسعار شاملة ضريبة القيمة المضافة، وتتوفر خصومات للكميات عند طلب '
          'عشر قطع فأكثر؛ تواصل مع مدير حسابك للحصول على عرض سعر.',
    ),
    'terms': t(
      'Prices may change without notice. Warranty covers manufacturing '
          'defects only. Delivery within 3 working days inside Tripoli.',
      'الأسعار قابلة للتغيير دون إشعار مسبق. يغطي الضمان عيوب التصنيع فقط. '
          'التوصيل خلال 3 أيام عمل داخل طرابلس.',
    ),
    'items': <Map<String, Object?>>[
      for (final (
            ReportProductArt photo,
            String sku,
            String categoryEn,
            String categoryAr,
            String nameEn,
            String nameAr,
            String description,
            int price,
            int stock,
          )
          in _catalogLines)
        <String, Object?>{
          'sku': sku,
          'photo': 'product_${photo.name}',
          'category': ar ? categoryAr : categoryEn,
          'name': ar ? nameAr : nameEn,
          'description': description.split('|')[ar ? 1 : 0],
          'warranty': t(
            price > 1000 ? '2 years' : '1 year',
            price > 1000 ? 'سنتان' : 'سنة واحدة',
          ),
          'price': ar ? price : price ~/ 5,
          'stock': stock,
        },
    ],
  };
}

// -------------------------------------------------------- account statement

const String _accountStatement = r'''<?xml version="1.0" encoding="UTF-8"?>
<QudsReport name="[[name]]" isRtl="[[rtl]]" pageSize="A4" orientation="Portrait" defaultFont="[[font]]" defaultFontSize="9">
    <Settings>
        <Margins top="12mm" bottom="12mm" left="12mm" right="12mm"/>
        <Colors primary="#14532D" accent="#16A34A" muted="#5F6B7A" light="#F2F7F4" border="#D7E3DB" text="#1F2933" debit="#B91C1C" credit="#15803D"/>
    </Settings>
    <Bands>
        <ReportHeader height="84mm">
            <Text name="title" x="12mm" y="2mm" width="100mm" height="11mm" fontSize="20" bold="true" color="primary">[[title]]</Text>
            <Text x="12mm" y="13mm" width="100mm" height="5mm" fontSize="8" color="muted">[[subtitle]]</Text>
            <Image name="logo" source="logo" x="182mm" y="1mm" width="16mm" height="16mm"/>
            <Text name="companyName" x="112mm" y="2mm" width="68mm" height="7mm" fontSize="11" bold="true" alignment="end">{{Data.company.name}}</Text>
            <Text x="112mm" y="9mm" width="68mm" height="5mm" fontSize="8" color="muted" alignment="end">{{Data.company.address}}</Text>
            <Text x="112mm" y="14mm" width="68mm" height="5mm" fontSize="8" color="muted" alignment="end">[[phone]]: &#x2066;{{Data.company.phone}}&#x2069;</Text>
            <Line x1="12mm" y1="22mm" x2="198mm" y2="22mm" color="accent" strokeWidth="1"/>
            <Shape kind="RoundedRectangle" x="12mm" y="26mm" width="112mm" height="30mm" fill="light" strokeWidth="0" cornerRadius="3pt"/>
            <Text x="16mm" y="28mm" width="104mm" height="5mm" fontSize="8" bold="true" color="accent">[[customer]]</Text>
            <Text name="customerName" x="16mm" y="34mm" width="104mm" height="7mm" fontSize="11" bold="true">{{Data.customer.name}}</Text>
            <Text x="16mm" y="41mm" width="50mm" height="5mm" fontSize="8.5" color="muted">[[account]]: {{Data.customer.code}}</Text>
            <Text x="68mm" y="41mm" width="52mm" height="5mm" fontSize="8.5" color="muted">[[phone]]: &#x2066;{{Data.customer.phone}}&#x2069;</Text>
            <Text x="16mm" y="47mm" width="104mm" height="5mm" fontSize="8.5" color="muted">[[address]]: {{Data.customer.address}}</Text>
            <Shape kind="RoundedRectangle" x="128mm" y="26mm" width="70mm" height="30mm" fill="#FFFFFF" color="border" strokeWidth="0.75" cornerRadius="3pt"/>
            <Text x="132mm" y="28mm" width="62mm" height="5mm" fontSize="8" bold="true" color="accent">[[period]]</Text>
            <Text x="132mm" y="34mm" width="20mm" height="6mm" fontSize="8.5" color="muted">[[from]]</Text>
            <Text x="152mm" y="34mm" width="42mm" height="6mm" fontSize="9" bold="true" alignment="end">{{Data.period.from | date:[[date]]}}</Text>
            <Text x="132mm" y="41mm" width="20mm" height="6mm" fontSize="8.5" color="muted">[[to]]</Text>
            <Text x="152mm" y="41mm" width="42mm" height="6mm" fontSize="9" bold="true" alignment="end">{{Data.period.to | date:[[date]]}}</Text>
            <Text x="132mm" y="48mm" width="20mm" height="6mm" fontSize="8.5" color="muted">[[issued]]</Text>
            <Text x="152mm" y="48mm" width="42mm" height="6mm" fontSize="9" alignment="end">{{System.CurrentDate | date:[[date]]}}</Text>
            <Shape kind="RoundedRectangle" x="12mm" y="60mm" width="43.5mm" height="18mm" fill="#FFFFFF" color="border" strokeWidth="0.75" cornerRadius="3pt"/>
            <Text x="14mm" y="61.5mm" width="39.5mm" height="5mm" fontSize="7.5" color="muted" alignment="center">[[opening]]</Text>
            <Text x="14mm" y="67mm" width="39.5mm" height="8mm" fontSize="12" bold="true" alignment="center">{{Data.openingBalance | [[n]]}}</Text>
            <Shape kind="RoundedRectangle" x="59.5mm" y="60mm" width="43.5mm" height="18mm" fill="#FFFFFF" color="border" strokeWidth="0.75" cornerRadius="3pt"/>
            <Text x="61.5mm" y="61.5mm" width="39.5mm" height="5mm" fontSize="7.5" color="muted" alignment="center">[[totalDebit]]</Text>
            <Text x="61.5mm" y="67mm" width="39.5mm" height="8mm" fontSize="12" bold="true" color="debit" alignment="center">{{SUM(item.debit) | [[n]]}}</Text>
            <Shape kind="RoundedRectangle" x="107mm" y="60mm" width="43.5mm" height="18mm" fill="#FFFFFF" color="border" strokeWidth="0.75" cornerRadius="3pt"/>
            <Text x="109mm" y="61.5mm" width="39.5mm" height="5mm" fontSize="7.5" color="muted" alignment="center">[[totalCredit]]</Text>
            <Text x="109mm" y="67mm" width="39.5mm" height="8mm" fontSize="12" bold="true" color="credit" alignment="center">{{SUM(item.credit) | [[n]]}}</Text>
            <Shape kind="RoundedRectangle" x="154.5mm" y="60mm" width="43.5mm" height="18mm" fill="primary" strokeWidth="0" cornerRadius="3pt"/>
            <Text x="156.5mm" y="61.5mm" width="39.5mm" height="5mm" fontSize="7.5" color="#D1FAE5" alignment="center">[[closing]]</Text>
            <Text name="closingBalance" x="156.5mm" y="67mm" width="39.5mm" height="8mm" fontSize="12" bold="true" color="#FFFFFF" alignment="center">{{Data.openingBalance + SUM(item.debit) - SUM(item.credit) | [[n]]}}</Text>
        </ReportHeader>
        <PageHeader height="9mm" printOnFirstPage="false">
            <Text x="12mm" y="1mm" width="186mm" height="6mm" fontSize="8" color="muted">[[title]]: {{Data.customer.name}} ({{Data.customer.code}}) [[continued]]</Text>
            <Line x1="12mm" y1="7.5mm" x2="198mm" y2="7.5mm" color="border" strokeWidth="0.5"/>
        </PageHeader>
        <Detail dataSet="transactions" height="22mm">
            <Table name="transactionsTable" x="12mm" y="0mm" width="186mm" showGrid="true" borderColor="border" headerBackground="primary" headerColor="#FFFFFF" stripeColor="light" fontSize="8.5" headerFontSize="8.5" rowHeight="7mm" headerHeight="8mm" padding="2pt">
                <Columns>
                    <Column width="24mm" header="[[colDate]]" align="center"/>
                    <Column width="24mm" header="[[colRef]]" align="center"/>
                    <Column width="66mm" header="[[colDescription]]" align="start"/>
                    <Column width="24mm" header="[[colDebit]]" align="center"/>
                    <Column width="24mm" header="[[colCredit]]" align="center"/>
                    <Column width="24mm" header="[[colBalance]]" align="center"/>
                </Columns>
                <RowTemplate>
                    <Cell field="item.date" format="date:[[date]]"/>
                    <Cell field="item.ref"/>
                    <Cell field="item.description"/>
                    <Cell field="IF(item.debit > 0, item.debit, null)" format="[[n]]" color="debit"/>
                    <Cell field="IF(item.credit > 0, item.credit, null)" format="[[n]]" color="credit"/>
                    <Cell field="item.balance" format="[[n]]" bold="true"/>
                </RowTemplate>
                <FooterRow>
                    <Cell text=""/>
                    <Cell text=""/>
                    <Cell text="[[total]]" bold="true"/>
                    <Cell field="SUM(item.debit)" format="[[n]]" bold="true"/>
                    <Cell field="SUM(item.credit)" format="[[n]]" bold="true"/>
                    <Cell field="LAST(item.balance)" format="[[n]]" bold="true"/>
                </FooterRow>
            </Table>
        </Detail>
        <ReportSummary height="82mm" keepTogether="true">
            <Shape kind="RoundedRectangle" x="12mm" y="4mm" width="186mm" height="16mm" fill="light" strokeWidth="0" cornerRadius="3pt"/>
            <Text x="16mm" y="5mm" width="120mm" height="7mm" fontSize="10" bold="true" color="primary" verticalAlignment="middle">[[due]]: {{Data.openingBalance + SUM(item.debit) - SUM(item.credit) | [[money]]}}</Text>
            <Text name="amountInWords" x="16mm" y="12mm" width="178mm" height="7mm" fontSize="8.5" color="muted" verticalAlignment="middle">{{AMOUNTWORDS(Data.openingBalance + SUM(item.debit) - SUM(item.credit), '[[cur]]', '[[lang]]')}}</Text>
            <Chart name="balanceChart" x="12mm" y="24mm" width="186mm" height="44mm" chartType="area" title="[[chartTitle]]" dataSet="Data.transactions" category="FORMAT(Row.date, 'dd/MM')" aggregate="last" showLegend="false" valueFormat="n0" borderColor="border" borderWidth="0.5pt">
                <Series name="[[colBalance]]" value="Row.balance" color="accent"/>
            </Chart>
            <Text x="12mm" y="71mm" width="186mm" height="9mm" fontSize="7.5" color="muted">[[review]]</Text>
        </ReportSummary>
        <PageFooter height="9mm">
            <Line x1="12mm" y1="1mm" x2="198mm" y2="1mm" color="border" strokeWidth="0.5"/>
            <Text x="12mm" y="2.5mm" width="120mm" height="5.5mm" fontSize="7.5" color="muted">{{Data.company.name}} — [[department]]</Text>
            <Text x="148mm" y="2.5mm" width="50mm" height="5.5mm" fontSize="7.5" color="muted" alignment="end">[[page]] {{System.PageNumber}} [[of]] {{System.TotalPages}}</Text>
        </PageFooter>
    </Bands>
</QudsReport>
''';

const Map<String, String> _accountStatementAr = <String, String>{
  ..._ar,
  'name': 'كشف حساب',
  'title': 'كشف حساب عميل',
  'subtitle': 'CUSTOMER ACCOUNT STATEMENT',
  'phone': 'هاتف',
  'customer': 'بيانات العميل',
  'account': 'رقم الحساب',
  'address': 'العنوان',
  'period': 'فترة الكشف',
  'from': 'من',
  'to': 'إلى',
  'issued': 'الإصدار',
  'opening': 'الرصيد الافتتاحي',
  'totalDebit': 'إجمالي المدين',
  'totalCredit': 'إجمالي الدائن',
  'closing': 'الرصيد الختامي',
  'continued': '— تابع',
  'colDate': 'التاريخ',
  'colRef': 'المرجع',
  'colDescription': 'البيان',
  'colDebit': 'مدين',
  'colCredit': 'دائن',
  'colBalance': 'الرصيد',
  'total': 'الإجمالي',
  'due': 'الرصيد المستحق',
  'chartTitle': 'تطور الرصيد خلال الفترة',
  'review':
      'يرجى مراجعة الكشف وإبلاغنا بأي ملاحظات خلال 15 يومًا من تاريخ '
      'الإصدار، وإلا اعتبر الرصيد صحيحًا.',
  'department': 'قسم الحسابات',
};

const Map<String, String> _accountStatementEn = <String, String>{
  ..._en,
  'name': 'Account statement',
  'title': 'Account Statement',
  'subtitle': 'كشف حساب عميل',
  'phone': 'Phone',
  'customer': 'CUSTOMER',
  'account': 'Account',
  'address': 'Address',
  'period': 'STATEMENT PERIOD',
  'from': 'From',
  'to': 'To',
  'issued': 'Issued',
  'opening': 'Opening balance',
  'totalDebit': 'Total debit',
  'totalCredit': 'Total credit',
  'closing': 'Closing balance',
  'continued': '(continued)',
  'colDate': 'Date',
  'colRef': 'Reference',
  'colDescription': 'Description',
  'colDebit': 'Debit',
  'colCredit': 'Credit',
  'colBalance': 'Balance',
  'total': 'Total',
  'due': 'Balance due',
  'chartTitle': 'Balance over the period',
  'review':
      'Please review this statement and report any discrepancy within 15 '
      'days of issue; otherwise the balance is considered correct.',
  'department': 'Accounts department',
};

Map<String, Object?> _accountStatementArData() => _accountStatementData(true);

Map<String, Object?> _accountStatementEnData() => _accountStatementData(false);

Map<String, Object?> _accountStatementData(bool ar) {
  String t(String en, String arabic) => ar ? arabic : en;
  final num rate = ar ? 1 : 0.2;
  final num opening = 12500 * rate;
  final List<(int, String, String, String, num, num)> moves =
      <(int, String, String, String, num, num)>[
        (
          2,
          'INV-0921',
          'Sales invoice — computers',
          'فاتورة مبيعات — أجهزة حاسوب',
          8650,
          0,
        ),
        (
          5,
          'RCV-0310',
          'Receipt — bank transfer',
          'سند قبض — تحويل مصرفي',
          0,
          10000,
        ),
        (
          9,
          'INV-0934',
          'Sales invoice — office supplies',
          'فاتورة مبيعات — مستلزمات مكتبية',
          2340.5,
          0,
        ),
        (12, 'RET-0041', 'Sales return', 'مردودات مبيعات', 0, 420),
        (
          15,
          'INV-0948',
          'Sales invoice — printers',
          'فاتورة مبيعات — طابعات',
          4100,
          0,
        ),
        (
          18,
          'RCV-0326',
          'Receipt — cheque 55120',
          'سند قبض — شيك رقم 55120',
          0,
          6500,
        ),
        (
          21,
          'INV-0957',
          'Sales invoice — maintenance',
          'فاتورة مبيعات — خدمات صيانة',
          1250,
          0,
        ),
        (
          24,
          'DBN-0012',
          'Debit note — price difference',
          'إشعار مدين — فرق أسعار',
          310.75,
          0,
        ),
        (27, 'RCV-0339', 'Receipt — cash', 'سند قبض — نقدًا', 0, 3000),
        (
          29,
          'INV-0966',
          'Sales invoice — monitors',
          'فاتورة مبيعات — شاشات',
          5920,
          0,
        ),
      ];
  num balance = opening;
  return <String, Object?>{
    'company': <String, Object?>{
      'name': t('Quds Technology Co.', 'شركة القدس للتقنية'),
      'address': t('Republic Street, Tripoli', 'طرابلس — شارع الجمهورية'),
      'phone': '+218 21 444 0101',
    },
    'customer': <String, Object?>{
      'name': t('Al-Noor General Trading', 'مؤسسة النور للتجارة العامة'),
      'code': 'C-10482',
      'phone': '+218 92 765 4321',
      'address': t('River Road, Benghazi', 'بنغازي — طريق النهر'),
    },
    'period': <String, Object?>{
      'from': DateTime(2026, 9, 1),
      'to': DateTime(2026, 9, 30),
    },
    'openingBalance': opening,
    'transactions': <Map<String, Object?>>[
      for (final (int, String, String, String, num, num) m in moves)
        <String, Object?>{
          'date': DateTime(2026, 9, m.$1),
          'ref': m.$2,
          'description': ar ? m.$4 : m.$3,
          'debit': m.$5 * rate,
          'credit': m.$6 * rate,
          'balance': balance = balance + (m.$5 - m.$6) * rate,
        },
    ],
  };
}

// ---------------------------------------------------------- receipt voucher

const String _receiptVoucher = r'''<?xml version="1.0" encoding="UTF-8"?>
<QudsReport name="[[name]]" isRtl="[[rtl]]" pageSize="A5" orientation="Landscape" defaultFont="[[font]]" defaultFontSize="10">
    <Settings>
        <Margins top="10mm" bottom="10mm" left="10mm" right="10mm"/>
        <Colors primary="#1E3A8A" accent="#2563EB" muted="#64748B" light="#EFF4FF" line="#94A3B8" text="#111827"/>
    </Settings>
    <Bands>
        <ReportHeader height="128mm">
            <Shape kind="RoundedRectangle" x="10mm" y="0mm" width="190mm" height="127mm" color="primary" strokeWidth="1.2" cornerRadius="5pt"/>
            <Image name="logo" source="logo" x="15mm" y="4mm" width="15mm" height="15mm"/>
            <Text name="companyName" x="32mm" y="5mm" width="54mm" height="8mm" fontSize="12" bold="true" color="primary">{{Data.company.name}}</Text>
            <Text x="32mm" y="13mm" width="56mm" height="5mm" fontSize="7.5" color="muted">{{Data.company.address}} — &#x2066;{{Data.company.phone}}&#x2069;</Text>
            <Text name="title" x="85mm" y="4mm" width="60mm" height="11mm" fontSize="22" bold="true" color="primary" alignment="center">[[title]]</Text>
            <Text x="85mm" y="15mm" width="60mm" height="5mm" fontSize="8" color="muted" alignment="center">[[subtitle]]</Text>
            <Shape kind="RoundedRectangle" x="148mm" y="5mm" width="46mm" height="16mm" fill="light" strokeWidth="0" cornerRadius="3pt"/>
            <Text name="voucherNumber" x="151mm" y="6mm" width="40mm" height="7mm" fontSize="9.5" bold="true" verticalAlignment="middle">[[number]]: {{Data.voucher.number}}</Text>
            <Text x="151mm" y="13mm" width="40mm" height="7mm" fontSize="9" color="muted" verticalAlignment="middle">[[dateLabel]]: {{Data.voucher.date | date:[[date]]}}</Text>
            <Line x1="16mm" y1="24mm" x2="194mm" y2="24mm" color="accent" strokeWidth="0.8"/>
            <Text x="16mm" y="28mm" width="30mm" height="12mm" fontSize="10" bold="true" color="primary" verticalAlignment="middle">[[amount]]</Text>
            <Shape kind="RoundedRectangle" x="46mm" y="28mm" width="62mm" height="12mm" fill="light" color="accent" strokeWidth="0.8" cornerRadius="3pt"/>
            <Text name="amount" x="46mm" y="28mm" width="62mm" height="12mm" fontSize="14" bold="true" alignment="center" verticalAlignment="middle">{{Data.voucher.amount | [[money]]}}</Text>
            <Text x="16mm" y="46mm" width="44mm" height="8mm" fontSize="10" color="muted" verticalAlignment="bottom">[[receivedFrom]]</Text>
            <Text name="receivedFrom" x="60mm" y="46mm" width="134mm" height="8mm" fontSize="11" bold="true" verticalAlignment="bottom">{{Data.voucher.receivedFrom}}</Text>
            <Line x1="60mm" y1="54.5mm" x2="194mm" y2="54.5mm" color="line" strokeWidth="0.6" lineStyle="dotted"/>
            <Text x="16mm" y="58mm" width="44mm" height="8mm" fontSize="10" color="muted" verticalAlignment="bottom">[[sumOf]]</Text>
            <Text name="amountInWords" x="60mm" y="58mm" width="134mm" height="8mm" fontSize="9.5" bold="true" verticalAlignment="bottom">{{AMOUNTWORDS(Data.voucher.amount, '[[cur]]', '[[lang]]')}}</Text>
            <Line x1="60mm" y1="66.5mm" x2="194mm" y2="66.5mm" color="line" strokeWidth="0.6" lineStyle="dotted"/>
            <Text x="16mm" y="70mm" width="44mm" height="8mm" fontSize="10" color="muted" verticalAlignment="bottom">[[purpose]]</Text>
            <Text name="purpose" x="60mm" y="70mm" width="134mm" height="8mm" fontSize="10" bold="true" verticalAlignment="bottom">{{Data.voucher.purpose}}</Text>
            <Line x1="60mm" y1="78.5mm" x2="194mm" y2="78.5mm" color="line" strokeWidth="0.6" lineStyle="dotted"/>
            <Text x="16mm" y="82mm" width="26mm" height="8mm" fontSize="10" color="muted" verticalAlignment="bottom">[[method]]</Text>
            <Text x="42mm" y="82mm" width="36mm" height="8mm" fontSize="10" bold="true" verticalAlignment="bottom">{{Data.voucher.method}}</Text>
            <Text x="80mm" y="82mm" width="22mm" height="8mm" fontSize="10" color="muted" verticalAlignment="bottom">[[cheque]]</Text>
            <Text x="102mm" y="82mm" width="32mm" height="8mm" fontSize="10" bold="true" verticalAlignment="bottom">{{COALESCE(Data.voucher.chequeNo, '—')}}</Text>
            <Text x="136mm" y="82mm" width="16mm" height="8mm" fontSize="10" color="muted" verticalAlignment="bottom">[[bank]]</Text>
            <Text x="152mm" y="82mm" width="42mm" height="8mm" fontSize="10" bold="true" verticalAlignment="bottom">{{COALESCE(Data.voucher.bank, '—')}}</Text>
            <Line x1="42mm" y1="90.5mm" x2="194mm" y2="90.5mm" color="line" strokeWidth="0.6" lineStyle="dotted"/>
            <Line x1="22mm" y1="112mm" x2="62mm" y2="112mm" color="line" strokeWidth="0.6"/>
            <Text x="22mm" y="113mm" width="40mm" height="6mm" fontSize="9" color="muted" alignment="center">[[receiver]]</Text>
            <Image name="signature" source="signature" x="86mm" y="98mm" width="38mm" height="13mm"/>
            <Line x1="85mm" y1="112mm" x2="125mm" y2="112mm" color="line" strokeWidth="0.6"/>
            <Text x="85mm" y="113mm" width="40mm" height="6mm" fontSize="9" color="muted" alignment="center">[[accountant]]</Text>
            <Image name="stamp" source="stamp" x="156mm" y="90mm" width="24mm" height="24mm"/>
            <Line x1="148mm" y1="112mm" x2="188mm" y2="112mm" color="line" strokeWidth="0.6"/>
            <Text x="148mm" y="113mm" width="40mm" height="6mm" fontSize="9" color="muted" alignment="center">[[manager]]</Text>
            <QrCode name="qrCode" x="176mm" y="26mm" width="18mm" height="18mm" value="RCV:{{Data.voucher.number}};AMT:{{Data.voucher.amount | [[n]]}}"/>
        </ReportHeader>
    </Bands>
</QudsReport>
''';

const Map<String, String> _receiptVoucherAr = <String, String>{
  ..._ar,
  'name': 'سند قبض',
  'title': 'سند قبض',
  'subtitle': 'RECEIPT VOUCHER',
  'number': 'رقم',
  'dateLabel': 'التاريخ',
  'amount': 'المبلغ',
  'receivedFrom': 'استلمنا من السيد/ السادة:',
  'sumOf': 'مبلغًا وقدره:',
  'purpose': 'وذلك عن:',
  'method': 'طريقة الدفع:',
  'cheque': 'رقم الشيك:',
  'bank': 'المصرف:',
  'receiver': 'المستلم',
  'accountant': 'المحاسب',
  'manager': 'المدير المالي',
};

const Map<String, String> _receiptVoucherEn = <String, String>{
  ..._en,
  'name': 'Receipt voucher',
  'title': 'RECEIPT',
  'subtitle': 'سند قبض',
  'number': 'No.',
  'dateLabel': 'Date',
  'amount': 'Amount',
  'receivedFrom': 'Received from:',
  'sumOf': 'The sum of:',
  'purpose': 'Being payment of:',
  'method': 'Paid by:',
  'cheque': 'Cheque No.:',
  'bank': 'Bank:',
  'receiver': 'Received by',
  'accountant': 'Accountant',
  'manager': 'Finance manager',
};

Map<String, Object?> _receiptVoucherArData() => _receiptVoucherData(true);

Map<String, Object?> _receiptVoucherEnData() => _receiptVoucherData(false);

Map<String, Object?> _receiptVoucherData(bool ar) {
  String t(String en, String arabic) => ar ? arabic : en;
  return <String, Object?>{
    'company': <String, Object?>{
      'name': t('Quds Technology Co.', 'شركة القدس للتقنية'),
      'address': t('Republic Street, Tripoli', 'طرابلس — شارع الجمهورية'),
      'phone': '+218 21 444 0101',
    },
    'voucher': <String, Object?>{
      'number': 'RCV-2026-0339',
      'date': DateTime(2026, 10, 10),
      'amount': ar ? 3750.5 : 750.25,
      'receivedFrom': t(
        'Al-Noor General Trading',
        'مؤسسة النور للتجارة العامة',
      ),
      'purpose': t(
        'Partial payment of sales invoice INV-2026-0142',
        'سداد جزئي لفاتورة المبيعات رقم INV-2026-0142',
      ),
      'method': t('Cheque', 'شيك'),
      'chequeNo': '55120',
      'bank': t('Jumhouria Bank', 'مصرف الجمهورية'),
    },
  };
}

// ---------------------------------------------------------------- inventory

const String _inventory = r'''<?xml version="1.0" encoding="UTF-8"?>
<QudsReport name="[[name]]" isRtl="[[rtl]]" pageSize="A4" orientation="Portrait" defaultFont="[[font]]" defaultFontSize="9">
    <Settings>
        <Margins top="12mm" bottom="12mm" left="12mm" right="12mm"/>
        <Colors primary="#7C2D12" accent="#EA580C" muted="#6B7280" light="#FFF7ED" border="#F1DCCB" text="#1F2933" alert="#DC2626" ok="#15803D"/>
    </Settings>
    <Bands>
        <ReportHeader height="128mm">
            <Shape kind="RoundedRectangle" x="12mm" y="0mm" width="186mm" height="20mm" fill="primary" strokeWidth="0" cornerRadius="4pt"/>
            <Text name="title" x="17mm" y="2.5mm" width="120mm" height="10mm" fontSize="17" bold="true" color="#FFFFFF">[[title]]</Text>
            <Text x="17mm" y="12mm" width="120mm" height="6mm" fontSize="9" color="#FED7AA">{{Data.warehouse}}</Text>
            <Text x="130mm" y="12mm" width="63mm" height="6mm" fontSize="8.5" color="#FED7AA" alignment="end">[[asOf]] {{Data.date | date:[[date]]}}</Text>
            <Shape kind="RoundedRectangle" x="12mm" y="25mm" width="43.5mm" height="20mm" fill="light" color="border" strokeWidth="0.5" cornerRadius="3pt"/>
            <Text x="14mm" y="27mm" width="39.5mm" height="5mm" fontSize="7.5" color="muted" alignment="center">[[kpiItems]]</Text>
            <Text x="14mm" y="33mm" width="39.5mm" height="9mm" fontSize="15" bold="true" alignment="center">{{COUNT(item.code)}}</Text>
            <Shape kind="RoundedRectangle" x="59.5mm" y="25mm" width="43.5mm" height="20mm" fill="light" color="border" strokeWidth="0.5" cornerRadius="3pt"/>
            <Text x="61.5mm" y="27mm" width="39.5mm" height="5mm" fontSize="7.5" color="muted" alignment="center">[[kpiQty]]</Text>
            <Text x="61.5mm" y="33mm" width="39.5mm" height="9mm" fontSize="15" bold="true" alignment="center">{{SUM(item.qty) | n0}}</Text>
            <Shape kind="RoundedRectangle" x="107mm" y="25mm" width="43.5mm" height="20mm" fill="light" color="border" strokeWidth="0.5" cornerRadius="3pt"/>
            <Text x="109mm" y="27mm" width="39.5mm" height="5mm" fontSize="7.5" color="muted" alignment="center">[[kpiValue]]</Text>
            <Text name="stockValue" x="109mm" y="33mm" width="39.5mm" height="9mm" fontSize="15" bold="true" alignment="center">{{SUM(item.qty * item.cost) | n0}}</Text>
            <Shape kind="RoundedRectangle" x="154.5mm" y="25mm" width="43.5mm" height="20mm" fill="#FEF2F2" color="#FECACA" strokeWidth="0.5" cornerRadius="3pt"/>
            <Text x="156.5mm" y="27mm" width="39.5mm" height="5mm" fontSize="7.5" color="alert" alignment="center">[[kpiReorder]]</Text>
            <Text x="156.5mm" y="33mm" width="39.5mm" height="9mm" fontSize="15" bold="true" color="alert" alignment="center">{{SUM(IF(item.qty &lt;= item.reorderLevel, 1, 0))}}</Text>
            <Chart name="topItemsChart" x="12mm" y="50mm" width="112mm" height="66mm" chartType="horizontalBar" title="[[chartTop]]" dataSet="Data.items" category="Row.name" value="Row.qty * Row.cost" sortBy="value" sortOrder="desc" limit="7" showValues="true" showLegend="false" showGrid="false" valueFormat="n0" borderColor="border" borderWidth="0.5pt" palette="#EA580C"/>
            <Chart name="categoryChart" x="128mm" y="50mm" width="70mm" height="66mm" chartType="pie" title="[[chartCategory]]" dataSet="Data.items" category="Row.category" value="Row.qty * Row.cost" sortBy="value" sortOrder="desc" showValues="true" borderColor="border" borderWidth="0.5pt" palette="#7C2D12,#EA580C,#F59E0B,#FDBA74,#A16207,#78716C"/>
            <Text x="12mm" y="119mm" width="186mm" height="7mm" fontSize="11" bold="true" color="primary">[[details]]</Text>
        </ReportHeader>
        <PageHeader height="9mm" printOnFirstPage="false">
            <Text x="12mm" y="1mm" width="186mm" height="6mm" fontSize="8" color="muted">[[title]] — {{Data.warehouse}} [[continued]]</Text>
            <Line x1="12mm" y1="7.5mm" x2="198mm" y2="7.5mm" color="border" strokeWidth="0.5"/>
        </PageHeader>
        <GroupHeader height="10mm" groupBy="item.category" keepTogether="true">
            <Shape kind="RoundedRectangle" x="12mm" y="1.5mm" width="186mm" height="7.5mm" fill="light" strokeWidth="0" cornerRadius="2pt"/>
            <Text x="15mm" y="1.5mm" width="120mm" height="7.5mm" fontSize="9.5" bold="true" color="primary" verticalAlignment="middle">[[category]]: {{Group.Key}}</Text>
            <Text x="138mm" y="1.5mm" width="57mm" height="7.5mm" fontSize="8" color="muted" alignment="end" verticalAlignment="middle">{{Group.Count}} [[items]]</Text>
        </GroupHeader>
        <Detail dataSet="items" sortBy="item.name" height="15mm">
            <Table name="itemsTable" x="12mm" y="0mm" width="186mm" showGrid="true" borderColor="border" headerBackground="#FFFFFF" headerColor="muted" stripeColor="#FFFBF7" fontSize="8.5" headerFontSize="8" rowHeight="6.8mm" headerHeight="7mm" padding="2pt">
                <Columns>
                    <Column width="20mm" header="[[colCode]]" align="center"/>
                    <Column width="50mm" header="[[colItem]]" align="start"/>
                    <Column width="16mm" header="[[colUnit]]" align="center"/>
                    <Column width="18mm" header="[[colQty]]" align="center"/>
                    <Column width="18mm" header="[[colReorder]]" align="center"/>
                    <Column width="20mm" header="[[colCost]]" align="center"/>
                    <Column width="24mm" header="[[colValue]]" align="center"/>
                    <Column width="20mm" header="[[colStatus]]" align="center"/>
                </Columns>
                <RowTemplate>
                    <Cell field="item.code"/>
                    <Cell field="item.name"/>
                    <Cell field="item.unit"/>
                    <Cell field="item.qty" format="n0"/>
                    <Cell field="item.reorderLevel" format="n0"/>
                    <Cell field="item.cost" format="[[n]]"/>
                    <Cell field="item.qty * item.cost" format="[[n]]" bold="true"/>
                    <Cell field="IF(item.qty &lt;= item.reorderLevel, '[[reorder]]', '[[available]]')" bold="true"/>
                </RowTemplate>
            </Table>
        </Detail>
        <GroupFooter height="10mm">
            <Text x="120mm" y="1.5mm" width="40mm" height="6.5mm" fontSize="8.5" bold="true" color="muted" verticalAlignment="middle">[[categoryValue]]</Text>
            <Text x="160mm" y="1.5mm" width="38mm" height="6.5mm" fontSize="8.5" bold="true" alignment="end" verticalAlignment="middle">{{SUM(item.qty * item.cost) | [[money]]}}</Text>
        </GroupFooter>
        <ReportSummary height="26mm" keepTogether="true">
            <Shape kind="RoundedRectangle" x="12mm" y="3mm" width="186mm" height="10mm" fill="primary" strokeWidth="0" cornerRadius="3pt"/>
            <Text x="16mm" y="3mm" width="90mm" height="10mm" fontSize="10" bold="true" color="#FFFFFF" verticalAlignment="middle">[[totalValue]]</Text>
            <Text name="grandTotal" x="120mm" y="3mm" width="74mm" height="10mm" fontSize="11" bold="true" color="#FFFFFF" alignment="end" verticalAlignment="middle">{{SUM(item.qty * item.cost) | [[money]]}}</Text>
            <Text x="12mm" y="15mm" width="186mm" height="8mm" fontSize="8.5" color="muted">{{AMOUNTWORDS(SUM(item.qty * item.cost), '[[cur]]', '[[lang]]')}}</Text>
        </ReportSummary>
        <PageFooter height="9mm">
            <Line x1="12mm" y1="1mm" x2="198mm" y2="1mm" color="border" strokeWidth="0.5"/>
            <Text x="12mm" y="2.5mm" width="120mm" height="5.5mm" fontSize="7.5" color="muted">[[preparedBy]]: {{Data.preparedBy}}</Text>
            <Text x="148mm" y="2.5mm" width="50mm" height="5.5mm" fontSize="7.5" color="muted" alignment="end">[[page]] {{System.PageNumber}} [[of]] {{System.TotalPages}}</Text>
        </PageFooter>
    </Bands>
</QudsReport>
''';

const Map<String, String> _inventoryAr = <String, String>{
  ..._ar,
  'name': 'تقرير المخزون',
  'title': 'تقرير حالة المخزون',
  'asOf': 'بتاريخ',
  'kpiItems': 'عدد الأصناف',
  'kpiQty': 'إجمالي الكميات',
  'kpiValue': 'قيمة المخزون (د.ل)',
  'kpiReorder': 'أصناف تحتاج إعادة طلب',
  'chartTop': 'أعلى الأصناف قيمةً',
  'chartCategory': 'القيمة حسب الفئة',
  'details': 'تفاصيل الأصناف حسب الفئة',
  'continued': '— تابع',
  'category': 'الفئة',
  'items': 'صنف',
  'colCode': 'الرمز',
  'colItem': 'الصنف',
  'colUnit': 'الوحدة',
  'colQty': 'الكمية',
  'colReorder': 'حد الطلب',
  'colCost': 'التكلفة',
  'colValue': 'القيمة',
  'colStatus': 'الحالة',
  'reorder': 'إعادة طلب',
  'available': 'متوفر',
  'categoryValue': 'قيمة الفئة',
  'totalValue': 'إجمالي قيمة المخزون',
  'preparedBy': 'أعدّه',
};

const Map<String, String> _inventoryEn = <String, String>{
  ..._en,
  'name': 'Inventory report',
  'title': 'Inventory Status Report',
  'asOf': 'As of',
  'kpiItems': 'Items',
  'kpiQty': 'Total quantity',
  'kpiValue': 'Stock value (USD)',
  'kpiReorder': 'Items to reorder',
  'chartTop': 'Top items by value',
  'chartCategory': 'Value by category',
  'details': 'Items by category',
  'continued': '(continued)',
  'category': 'Category',
  'items': 'items',
  'colCode': 'Code',
  'colItem': 'Item',
  'colUnit': 'Unit',
  'colQty': 'Qty',
  'colReorder': 'Reorder at',
  'colCost': 'Cost',
  'colValue': 'Value',
  'colStatus': 'Status',
  'reorder': 'Reorder',
  'available': 'In stock',
  'categoryValue': 'Category value',
  'totalValue': 'Total stock value',
  'preparedBy': 'Prepared by',
};

Map<String, Object?> _inventoryArData() => _inventoryData(true);

Map<String, Object?> _inventoryEnData() => _inventoryData(false);

Map<String, Object?> _inventoryData(bool ar) {
  String t(String en, String arabic) => ar ? arabic : en;
  final List<(String, String, String, String, String, int, int, num)> rows =
      <(String, String, String, String, String, int, int, num)>[
        (
          'LP-1420',
          '14" laptop',
          'حاسوب محمول 14 بوصة',
          'Computers',
          'حواسيب',
          18,
          10,
          2650,
        ),
        (
          'LP-1560',
          '15.6" laptop',
          'حاسوب محمول 15.6 بوصة',
          'Computers',
          'حواسيب',
          7,
          8,
          2980,
        ),
        (
          'DT-0700',
          'All-in-one desktop',
          'حاسوب مكتبي متكامل',
          'Computers',
          'حواسيب',
          11,
          5,
          3400,
        ),
        (
          'MN-2401',
          '24" monitor',
          'شاشة 24 بوصة',
          'Displays',
          'شاشات',
          26,
          12,
          640,
        ),
        (
          'MN-2701',
          '27" 4K monitor',
          'شاشة 27 بوصة 4K',
          'Displays',
          'شاشات',
          9,
          10,
          1050,
        ),
        (
          'KB-0310',
          'Wireless keyboard',
          'لوحة مفاتيح لاسلكية',
          'Accessories',
          'ملحقات',
          64,
          30,
          78,
        ),
        (
          'MS-0450',
          'Wireless mouse',
          'فأرة لاسلكية',
          'Accessories',
          'ملحقات',
          22,
          30,
          42,
        ),
        (
          'HS-0200',
          'Headset with microphone',
          'سماعة رأس بميكروفون',
          'Accessories',
          'ملحقات',
          35,
          15,
          115,
        ),
        (
          'PR-9100',
          'Color laser printer',
          'طابعة ليزر ملونة',
          'Printers',
          'طابعات',
          4,
          3,
          1850,
        ),
        (
          'PR-9050',
          'Mono laser printer',
          'طابعة ليزر أبيض وأسود',
          'Printers',
          'طابعات',
          6,
          4,
          920,
        ),
        (
          'TN-9100',
          'Color toner',
          'حبر طابعة ملون',
          'Printers',
          'طابعات',
          12,
          20,
          260,
        ),
        (
          'CB-0006',
          'Cat6 network cable',
          'كابل شبكة Cat6',
          'Networking',
          'شبكات',
          9,
          4,
          380,
        ),
        (
          'SW-2400',
          '24-port switch',
          'محول شبكة 24 منفذ',
          'Networking',
          'شبكات',
          5,
          3,
          1150,
        ),
        (
          'RT-0600',
          'Wireless router',
          'موجه لاسلكي',
          'Networking',
          'شبكات',
          2,
          4,
          560,
        ),
      ];
  return <String, Object?>{
    'warehouse': t('Main warehouse — Tripoli', 'المستودع الرئيسي — طرابلس'),
    'date': DateTime(2026, 10, 10),
    'preparedBy': t('Stores department', 'قسم المخازن'),
    'items': <Map<String, Object?>>[
      for (final (String, String, String, String, String, int, int, num) r
          in rows)
        <String, Object?>{
          'code': r.$1,
          'name': ar ? r.$3 : r.$2,
          'category': ar ? r.$5 : r.$4,
          'unit': t(
            r.$1.startsWith('CB')
                ? 'roll'
                : (r.$1.startsWith('TN') ? 'box' : 'pc'),
            r.$1.startsWith('CB')
                ? 'لفة'
                : (r.$1.startsWith('TN') ? 'علبة' : 'قطعة'),
          ),
          'qty': r.$6,
          'reorderLevel': r.$7,
          'cost': ar ? r.$8 : r.$8 / 5,
        },
    ],
  };
}

// -------------------------------------------------------- sales performance

const String _salesPerformance = r'''<?xml version="1.0" encoding="UTF-8"?>
<QudsReport name="[[name]]" isRtl="[[rtl]]" pageSize="A4" orientation="Portrait" defaultFont="[[font]]" defaultFontSize="9">
    <Settings>
        <Margins top="12mm" bottom="12mm" left="12mm" right="12mm"/>
        <Colors primary="#1E3A8A" accent="#3B82F6" muted="#64748B" light="#F4F7FB" border="#E1E7EF" text="#0F172A" good="#16A34A" warm="#F59E0B" pink="#DB2777"/>
    </Settings>
    <Bands>
        <ReportHeader height="196mm">
            <Shape kind="RoundedRectangle" x="12mm" y="0mm" width="186mm" height="20mm" fill="primary" strokeWidth="0" cornerRadius="4pt"/>
            <Image name="logo" source="logo" x="15mm" y="2.5mm" width="15mm" height="15mm"/>
            <Text name="title" x="33mm" y="3mm" width="110mm" height="9mm" fontSize="17" bold="true" color="#FFFFFF">[[title]]</Text>
            <Text x="33mm" y="12mm" width="110mm" height="6mm" fontSize="9" color="#DBEAFE">{{Data.company}}  •  {{Data.period}}</Text>
            <Text x="130mm" y="12mm" width="64mm" height="6mm" fontSize="8" color="#DBEAFE" alignment="end">[[generated]] {{System.CurrentDate | date:[[date]]}}</Text>
            <Shape kind="RoundedRectangle" x="12mm" y="25mm" width="43.5mm" height="22mm" fill="light" color="border" strokeWidth="0.5" cornerRadius="3pt"/>
            <Rectangle x="12mm" y="28mm" width="1.4mm" height="16mm" fill="accent" strokeWidth="0"/>
            <Text x="16mm" y="27mm" width="38mm" height="5mm" fontSize="7.5" color="muted">[[kpiRevenue]]</Text>
            <Text name="totalRevenue" x="16mm" y="32mm" width="38mm" height="8mm" fontSize="14" bold="true">{{SUM(Data.orders.revenue) | n0}}</Text>
            <Text x="16mm" y="40mm" width="38mm" height="5mm" fontSize="7" color="good">{{SUM(Data.orders.revenue) / SUM(Data.monthly.target) | percent:1}} [[ofTarget]]</Text>
            <Shape kind="RoundedRectangle" x="59.5mm" y="25mm" width="43.5mm" height="22mm" fill="light" color="border" strokeWidth="0.5" cornerRadius="3pt"/>
            <Rectangle x="59.5mm" y="28mm" width="1.4mm" height="16mm" fill="good" strokeWidth="0"/>
            <Text x="63.5mm" y="27mm" width="38mm" height="5mm" fontSize="7.5" color="muted">[[kpiOrders]]</Text>
            <Text x="63.5mm" y="32mm" width="38mm" height="8mm" fontSize="14" bold="true">{{COUNT(Data.orders) | n0}}</Text>
            <Text x="63.5mm" y="40mm" width="38mm" height="5mm" fontSize="7" color="muted">{{DISTINCTCOUNT(Data.orders.customer)}} [[activeCustomers]]</Text>
            <Shape kind="RoundedRectangle" x="107mm" y="25mm" width="43.5mm" height="22mm" fill="light" color="border" strokeWidth="0.5" cornerRadius="3pt"/>
            <Rectangle x="107mm" y="28mm" width="1.4mm" height="16mm" fill="warm" strokeWidth="0"/>
            <Text x="111mm" y="27mm" width="38mm" height="5mm" fontSize="7.5" color="muted">[[kpiUnits]]</Text>
            <Text x="111mm" y="32mm" width="38mm" height="8mm" fontSize="14" bold="true">{{SUM(Data.orders.units) | n0}}</Text>
            <Text x="111mm" y="40mm" width="38mm" height="5mm" fontSize="7" color="muted">[[across]] {{DISTINCTCOUNT(Data.orders.category)}} [[categories]]</Text>
            <Shape kind="RoundedRectangle" x="154.5mm" y="25mm" width="43.5mm" height="22mm" fill="light" color="border" strokeWidth="0.5" cornerRadius="3pt"/>
            <Rectangle x="154.5mm" y="28mm" width="1.4mm" height="16mm" fill="pink" strokeWidth="0"/>
            <Text x="158.5mm" y="27mm" width="38mm" height="5mm" fontSize="7.5" color="muted">[[kpiAverage]]</Text>
            <Text x="158.5mm" y="32mm" width="38mm" height="8mm" fontSize="14" bold="true">{{AVG(Data.orders.revenue) | n0}}</Text>
            <Text x="158.5mm" y="40mm" width="38mm" height="5mm" fontSize="7" color="muted">{{DISTINCTCOUNT(Data.orders.region)}} [[regions]]</Text>
            <Chart name="revenueChart" x="12mm" y="52mm" width="112mm" height="70mm" chartType="bar" title="[[chartRevenue]]" dataSet="Data.monthly" category="Row.month" valueFormat="n0" borderColor="border" borderWidth="0.5pt">
                <Series name="[[seriesRevenue]]" value="Row.revenue" color="primary"/>
                <Series name="[[seriesTarget]]" value="Row.target" color="#94A3B8"/>
            </Chart>
            <Chart name="categoryChart" x="127mm" y="52mm" width="71mm" height="70mm" chartType="donut" title="[[chartCategory]]" dataSet="Data.orders" category="Row.category" value="Row.revenue" sortBy="value" sortOrder="desc" showValues="true" valueFormat="n0" borderColor="border" borderWidth="0.5pt" palette="#1E3A8A,#3B82F6,#16A34A,#F59E0B,#DB2777,#94A3B8"/>
            <Chart name="unitsChart" x="12mm" y="126mm" width="112mm" height="56mm" chartType="line" title="[[chartUnits]]" dataSet="Data.monthly" category="Row.month" showValues="true" showLegend="false" borderColor="border" borderWidth="0.5pt">
                <Series name="[[seriesUnits]]" value="Row.units" color="good"/>
            </Chart>
            <Chart name="regionChart" x="127mm" y="126mm" width="71mm" height="56mm" chartType="horizontalBar" title="[[chartRegion]]" dataSet="Data.orders" category="Row.region" value="Row.revenue" sortBy="value" sortOrder="desc" showValues="true" showLegend="false" showGrid="false" valueFormat="n0" borderColor="border" borderWidth="0.5pt" palette="#3B82F6"/>
            <Text x="12mm" y="186mm" width="186mm" height="8mm" fontSize="12" bold="true" color="primary">[[details]]</Text>
            <Line x1="12mm" y1="194mm" x2="198mm" y2="194mm" color="accent" strokeWidth="1"/>
        </ReportHeader>
        <PageHeader height="9mm" printOnFirstPage="false">
            <Text x="12mm" y="1mm" width="140mm" height="6mm" fontSize="8" color="muted">[[title]] — {{Data.period}}</Text>
            <Line x1="12mm" y1="7.5mm" x2="198mm" y2="7.5mm" color="border" strokeWidth="0.5"/>
        </PageHeader>
        <GroupHeader height="10mm" groupBy="item.region" keepTogether="true">
            <Shape kind="RoundedRectangle" x="12mm" y="1.5mm" width="186mm" height="7.5mm" fill="#EEF2FF" strokeWidth="0" cornerRadius="2pt"/>
            <Text x="15mm" y="1.5mm" width="120mm" height="7.5mm" fontSize="9.5" bold="true" color="primary" verticalAlignment="middle">[[regionGroup]]</Text>
            <Text x="138mm" y="1.5mm" width="57mm" height="7.5mm" fontSize="8" color="muted" alignment="end" verticalAlignment="middle">{{Group.Count}} [[orders]]</Text>
        </GroupHeader>
        <Detail dataSet="orders" sortBy="item.revenue desc" height="15mm">
            <Table name="ordersTable" x="12mm" y="0mm" width="186mm" showGrid="false" headerBackground="#FFFFFF" headerColor="muted" stripeColor="light" fontSize="8.5" headerFontSize="7.5" rowHeight="6.5mm" headerHeight="7mm" padding="3pt">
                <Columns>
                    <Column width="24mm" header="[[colDate]]" align="start"/>
                    <Column width="26mm" header="[[colOrder]]" align="start"/>
                    <Column width="56mm" header="[[colCustomer]]" align="start"/>
                    <Column width="32mm" header="[[colCategory]]" align="start"/>
                    <Column width="18mm" header="[[colUnits]]" align="end"/>
                    <Column width="30mm" header="[[colRevenue]]" align="end"/>
                </Columns>
                <RowTemplate>
                    <Cell field="item.date" format="date:[[date]]"/>
                    <Cell field="item.orderNo"/>
                    <Cell field="item.customer"/>
                    <Cell field="item.category"/>
                    <Cell field="item.units" format="n0"/>
                    <Cell field="item.revenue" format="n2" bold="true"/>
                </RowTemplate>
            </Table>
        </Detail>
        <GroupFooter height="10mm">
            <Line x1="120mm" y1="1mm" x2="198mm" y2="1mm" color="border" strokeWidth="0.75"/>
            <Text x="120mm" y="2mm" width="30mm" height="6.5mm" fontSize="8.5" bold="true" color="muted" verticalAlignment="middle">[[subtotal]]</Text>
            <Text x="150mm" y="2mm" width="18mm" height="6.5mm" fontSize="8.5" bold="true" alignment="end" verticalAlignment="middle">{{SUM(item.units) | n0}}</Text>
            <Text x="168mm" y="2mm" width="30mm" height="6.5mm" fontSize="8.5" bold="true" alignment="end" verticalAlignment="middle">{{SUM(item.revenue) | n2}}</Text>
        </GroupFooter>
        <ReportSummary height="16mm" keepTogether="true">
            <Shape kind="RoundedRectangle" x="12mm" y="3mm" width="186mm" height="10mm" fill="primary" strokeWidth="0" cornerRadius="3pt"/>
            <Text x="16mm" y="3mm" width="100mm" height="10mm" fontSize="10" bold="true" color="#FFFFFF" verticalAlignment="middle">[[grandTotal]] — {{COUNT(item.orderNo)}} [[orders]]</Text>
            <Text x="146mm" y="3mm" width="22mm" height="10mm" fontSize="10" bold="true" color="#FFFFFF" alignment="end" verticalAlignment="middle">{{SUM(item.units) | n0}}</Text>
            <Text name="grandTotal" x="168mm" y="3mm" width="28mm" height="10mm" fontSize="10" bold="true" color="#FFFFFF" alignment="end" verticalAlignment="middle">{{SUM(item.revenue) | n2}}</Text>
        </ReportSummary>
        <PageFooter height="9mm">
            <Line x1="12mm" y1="1mm" x2="198mm" y2="1mm" color="border" strokeWidth="0.5"/>
            <Text x="12mm" y="2.5mm" width="120mm" height="5.5mm" fontSize="7.5" color="muted">{{Data.company}} — [[internal]]</Text>
            <Text x="148mm" y="2.5mm" width="50mm" height="5.5mm" fontSize="7.5" color="muted" alignment="end">[[page]] {{System.PageNumber}} [[of]] {{System.TotalPages}}</Text>
        </PageFooter>
    </Bands>
</QudsReport>
''';

const Map<String, String> _salesPerformanceAr = <String, String>{
  ..._ar,
  'name': 'أداء المبيعات',
  'title': 'تقرير أداء المبيعات',
  'generated': 'أُعدّ في',
  'kpiRevenue': 'إجمالي الإيراد (د.ل)',
  'ofTarget': 'من المستهدف',
  'kpiOrders': 'الطلبات',
  'activeCustomers': 'عميلًا نشطًا',
  'kpiUnits': 'الوحدات المباعة',
  'across': 'ضمن',
  'categories': 'فئات',
  'kpiAverage': 'متوسط الطلب (د.ل)',
  'regions': 'مناطق',
  'chartRevenue': 'الإيراد مقابل المستهدف شهريًا',
  'seriesRevenue': 'الإيراد',
  'seriesTarget': 'المستهدف',
  'chartCategory': 'الإيراد حسب الفئة',
  'chartUnits': 'الوحدات المباعة شهريًا',
  'seriesUnits': 'الوحدات',
  'chartRegion': 'الإيراد حسب المنطقة',
  'details': 'تفاصيل الطلبات حسب المنطقة',
  'regionGroup': 'منطقة {{Group.Key}}',
  'orders': 'طلبات',
  'colDate': 'التاريخ',
  'colOrder': 'رقم الطلب',
  'colCustomer': 'العميل',
  'colCategory': 'الفئة',
  'colUnits': 'الوحدات',
  'colRevenue': 'الإيراد',
  'subtotal': 'المجموع',
  'grandTotal': 'الإجمالي العام',
  'internal': 'للاستخدام الداخلي',
};

const Map<String, String> _salesPerformanceEn = <String, String>{
  ..._en,
  'name': 'Sales Performance',
  'title': 'Sales Performance Report',
  'generated': 'Generated',
  'kpiRevenue': 'Total revenue (USD)',
  'ofTarget': 'of target',
  'kpiOrders': 'Orders',
  'activeCustomers': 'active customers',
  'kpiUnits': 'Units sold',
  'across': 'across',
  'categories': 'categories',
  'kpiAverage': 'Average order (USD)',
  'regions': 'regions',
  'chartRevenue': 'Revenue vs target by month',
  'seriesRevenue': 'Revenue',
  'seriesTarget': 'Target',
  'chartCategory': 'Revenue by category',
  'chartUnits': 'Units sold per month',
  'seriesUnits': 'Units',
  'chartRegion': 'Revenue by region',
  'details': 'Order details by region',
  'regionGroup': '{{Group.Key}} region',
  'orders': 'orders',
  'colDate': 'DATE',
  'colOrder': 'ORDER #',
  'colCustomer': 'CUSTOMER',
  'colCategory': 'CATEGORY',
  'colUnits': 'UNITS',
  'colRevenue': 'REVENUE',
  'subtotal': 'Subtotal',
  'grandTotal': 'Grand total',
  'internal': 'internal use only',
};

Map<String, Object?> _salesPerformanceArData() => _salesPerformanceData(true);

Map<String, Object?> _salesPerformanceEnData() => _salesPerformanceData(false);

Map<String, Object?> _salesPerformanceData(bool ar) {
  final List<String> months = ar
      ? const <String>['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو']
      : const <String>['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun'];
  final num rate = ar ? 5 : 1;
  const List<int> revenue = <int>[48200, 52650, 61300, 57800, 66420, 72900];
  const List<int> target = <int>[50000, 52000, 58000, 60000, 64000, 70000];
  const List<double> share = <double>[0.34, 0.27, 0.22, 0.17];
  final List<String> regions = ar
      ? const <String>['الشمال', 'الجنوب', 'الشرق', 'الغرب']
      : const <String>['North', 'South', 'East', 'West'];
  final List<String> categories = ar
      ? const <String>['حواسيب', 'شاشات', 'ملحقات', 'طابعات', 'خدمات']
      : const <String>[
          'Laptops',
          'Monitors',
          'Accessories',
          'Printers',
          'Services',
        ];
  final List<String> customers = ar
      ? const <String>[
          'مؤسسة النور',
          'شركة الأفق',
          'مجموعة الواحة',
          'شركة المدار',
          'متاجر السلام',
          'شركة البيان',
          'مؤسسة الفجر',
          'شركة الرواد',
        ]
      : const <String>[
          'Northwind Traders',
          'Contoso Retail',
          'Fabrikam Inc.',
          'Adventure Works',
          'Tailspin Toys',
          'Wide World Importers',
          'Litware Group',
          'Proseware LLC',
        ];
  return <String, Object?>{
    'company': ar ? 'شركة القدس التجارية' : 'Quds Trading Co.',
    'period': ar ? 'يناير – يونيو 2026' : 'January – June 2026',
    'monthly': <Map<String, Object?>>[
      for (int m = 0; m < months.length; m++)
        <String, Object?>{
          'month': months[m],
          'revenue': revenue[m] * rate,
          'target': target[m] * rate,
          'units': <int>[
            for (int k = 0; k < share.length; k++) 4 + (m * 7 + k * 11) % 23,
          ].fold<int>(0, (int a, int b) => a + b),
        },
    ],
    'orders': <Map<String, Object?>>[
      for (int m = 0; m < months.length; m++)
        for (int k = 0; k < share.length; k++)
          <String, Object?>{
            'date': DateTime(2026, m + 1, 3 + k * 6),
            'orderNo': 'SO-${10240 + m * 17 + k * 3}',
            'customer': customers[(m * 3 + k * 5) % customers.length],
            'region': regions[(m + k * 3) % regions.length],
            'category': categories[(m * 2 + k) % categories.length],
            'units': 4 + (m * 7 + k * 11) % 23,
            'revenue': revenue[m] * share[k] * rate,
          },
    ],
  };
}

// -------------------------------------------------------------- certificate

const String _certificate = r'''<?xml version="1.0" encoding="UTF-8"?>
<QudsReport name="[[name]]" isRtl="[[rtl]]" pageSize="A4" orientation="Landscape" defaultFont="[[font]]" defaultFontSize="11">
    <Settings>
        <Margins top="10mm" bottom="10mm" left="10mm" right="10mm"/>
        <Colors primary="#12355B" accent="#C9A227" muted="#6B7280" paper="#FFFDF6" text="#1F2933"/>
    </Settings>
    <Bands>
        <ReportHeader height="188mm">
            <Rectangle x="10mm" y="0mm" width="277mm" height="188mm" fill="paper" color="primary" strokeWidth="3"/>
            <Rectangle x="15mm" y="5mm" width="267mm" height="178mm" color="accent" strokeWidth="1"/>
            <Rectangle x="17mm" y="7mm" width="263mm" height="174mm" color="accent" strokeWidth="0.4"/>
            <Image name="logo" source="logo" x="136.5mm" y="13mm" width="24mm" height="24mm"/>
            <Text name="companyName" x="40mm" y="39mm" width="217mm" height="7mm" fontSize="11" color="muted" alignment="center">{{Data.company}}</Text>
            <Text name="title" x="30mm" y="48mm" width="237mm" height="17mm" fontSize="30" bold="true" color="primary" alignment="center">[[title]]</Text>
            <Text x="30mm" y="67mm" width="237mm" height="7mm" fontSize="11" color="muted" alignment="center">[[presented]]</Text>
            <Text name="employeeName" x="30mm" y="76mm" width="237mm" height="14mm" fontSize="25" bold="true" color="text" alignment="center">{{Data.employee.name}}</Text>
            <Line x1="93mm" y1="91mm" x2="204mm" y2="91mm" color="accent" strokeWidth="1.2"/>
            <Text x="40mm" y="94mm" width="217mm" height="8mm" fontSize="11.5" color="primary" alignment="center">{{Data.employee.title}} — {{Data.employee.department}}</Text>
            <Text name="body" x="48mm" y="104mm" width="201mm" height="22mm" fontSize="11.5" color="text" alignment="center">[[body]]</Text>
            <Text x="40mm" y="128mm" width="217mm" height="7mm" fontSize="10" color="muted" alignment="center">[[issued]] {{Data.date | [[longDate]]}}</Text>
            <Image name="signature" source="signature" x="42mm" y="141mm" width="56mm" height="20mm"/>
            <Line x1="37mm" y1="162mm" x2="103mm" y2="162mm" color="muted" strokeWidth="0.6"/>
            <Text name="signerName" x="37mm" y="163mm" width="66mm" height="6mm" fontSize="10.5" bold="true" alignment="center">{{Data.signer.name}}</Text>
            <Text x="37mm" y="169mm" width="66mm" height="6mm" fontSize="9" color="muted" alignment="center">{{Data.signer.title}}</Text>
            <Image name="seal" source="seal" x="131mm" y="138mm" width="35mm" height="35mm"/>
            <Image name="stamp" source="stamp" x="212mm" y="128mm" width="32mm" height="32mm"/>
            <Line x1="194mm" y1="162mm" x2="260mm" y2="162mm" color="muted" strokeWidth="0.6"/>
            <Text x="194mm" y="163mm" width="66mm" height="6mm" fontSize="10.5" bold="true" alignment="center">[[stampLabel]]</Text>
            <Text name="certificateNumber" x="194mm" y="169mm" width="66mm" height="6mm" fontSize="9" color="muted" alignment="center">[[number]]: {{Data.number}}</Text>
        </ReportHeader>
    </Bands>
</QudsReport>
''';

const Map<String, String> _certificateAr = <String, String>{
  ..._ar,
  'name': 'شهادة شكر وتقدير',
  'title': 'شهادة شكر وتقدير',
  'presented': 'تتشرف إدارة الشركة بمنح هذه الشهادة إلى',
  'body':
      'تقديرًا لجهوده المتميزة وإخلاصه في العمل، وإسهامه في '
      '{{Data.reason}}، متمنين له دوام التوفيق والنجاح.',
  'issued': 'حُررت بتاريخ',
  'stampLabel': 'ختم الشركة',
  'number': 'رقم الشهادة',
};

const Map<String, String> _certificateEn = <String, String>{
  ..._en,
  'name': 'Certificate of appreciation',
  'title': 'Certificate of Appreciation',
  'presented': 'This certificate is proudly presented to',
  'body':
      'In recognition of outstanding dedication and commitment, and for '
      '{{Data.reason}}. We wish you continued success.',
  'issued': 'Issued on',
  'stampLabel': 'Company stamp',
  'number': 'Certificate No.',
};

Map<String, Object?> _certificateArData() => _certificateData(true);

Map<String, Object?> _certificateEnData() => _certificateData(false);

Map<String, Object?> _certificateData(bool ar) {
  String t(String en, String arabic) => ar ? arabic : en;
  return <String, Object?>{
    'company': t('Quds Technology Co.', 'شركة القدس للتقنية'),
    'employee': <String, Object?>{
      'name': t('Sara Ahmed Al-Mansouri', 'سارة أحمد المنصوري'),
      'title': t('Senior Software Engineer', 'مهندسة برمجيات أولى'),
      'department': t('Product Development', 'إدارة تطوير المنتجات'),
    },
    'reason': t(
      'leading the successful launch of the Quds Report Studio',
      'قيادة الإطلاق الناجح لاستوديو القدس للتقارير',
    ),
    'date': DateTime(2026, 10, 10),
    'signer': <String, Object?>{
      'name': t('Khaled Omar', 'خالد عمر'),
      'title': t('Chief Executive Officer', 'المدير التنفيذي'),
    },
    'number': 'HR-2026-0087',
  };
}

// -------------------------------------------------------- class certificate

const String _classCertificate = r'''<?xml version="1.0" encoding="UTF-8"?>
<QudsReport name="[[name]]" isRtl="[[rtl]]" pageSize="A4" orientation="Landscape" defaultFont="[[font]]" defaultFontSize="11">
    <Settings>
        <Margins top="10mm" bottom="10mm" left="10mm" right="10mm"/>
        <Colors primary="#12355B" accent="#C9A227" muted="#6B7280" paper="#FFFDF6" text="#1F2933"/>
    </Settings>
    <DataSchema>
        <Field name="school" type="text" description="[[schoolField]]"/>
        <Field name="className" type="text" description="[[classField]]"/>
        <Field name="year" type="text" description="[[yearField]]"/>
        <Field name="date" type="date" description="[[dateField]]"/>
        <Field name="signer.name" type="text" description="[[signerNameField]]"/>
        <Field name="signer.title" type="text" description="[[signerTitleField]]"/>
        <Table name="students" description="[[studentsTable]]">
            <Column name="name" type="text" description="[[colName]]"/>
            <Column name="number" type="text" description="[[colNumber]]"/>
            <Column name="grade" type="text" description="[[colGrade]]"/>
            <Column name="note" type="text" description="[[colNote]]"/>
        </Table>
    </DataSchema>
    <Bands>
        <Detail dataSet="students" height="188mm" newPageBefore="true">
            <Rectangle x="10mm" y="0mm" width="277mm" height="188mm" fill="paper" color="primary" strokeWidth="3"/>
            <Rectangle x="15mm" y="5mm" width="267mm" height="178mm" color="accent" strokeWidth="1"/>
            <Rectangle x="17mm" y="7mm" width="263mm" height="174mm" color="accent" strokeWidth="0.4"/>
            <Image name="logo" source="logo" x="136.5mm" y="13mm" width="24mm" height="24mm"/>
            <Text name="schoolName" x="40mm" y="39mm" width="217mm" height="7mm" fontSize="11" color="muted" alignment="center">{{Data.school}}</Text>
            <Text name="title" x="30mm" y="48mm" width="237mm" height="14mm" fontSize="28" bold="true" color="primary" alignment="center">[[title]]</Text>
            <Text x="30mm" y="64mm" width="237mm" height="7mm" fontSize="11" color="muted" alignment="center">[[presented]]</Text>
            <Text name="studentName" x="30mm" y="73mm" width="237mm" height="14mm" fontSize="25" bold="true" color="text" alignment="center">{{item.name}}</Text>
            <Line x1="93mm" y1="88mm" x2="204mm" y2="88mm" color="accent" strokeWidth="1.2"/>
            <Text name="studentGrade" x="40mm" y="91mm" width="217mm" height="8mm" fontSize="12" color="primary" alignment="center">{{Data.className}} — {{item.grade}}</Text>
            <Text name="body" x="40mm" y="102mm" width="217mm" height="18mm" fontSize="11.5" color="text" alignment="center">[[body]]</Text>
            <Text x="40mm" y="122mm" width="217mm" height="7mm" fontSize="10" color="muted" alignment="center">[[issued]] {{Data.date | [[longDate]]}}</Text>
            <Image name="signature" source="signature" x="42mm" y="134mm" width="56mm" height="20mm"/>
            <Line x1="37mm" y1="155mm" x2="103mm" y2="155mm" color="muted" strokeWidth="0.6"/>
            <Text name="signerName" x="37mm" y="156mm" width="66mm" height="6mm" fontSize="10.5" bold="true" alignment="center">{{Data.signer.name}}</Text>
            <Text x="37mm" y="162mm" width="66mm" height="6mm" fontSize="9" color="muted" alignment="center">{{Data.signer.title}}</Text>
            <Image name="seal" source="seal" x="131mm" y="132mm" width="35mm" height="35mm"/>
            <Image name="stamp" source="stamp" x="212mm" y="122mm" width="32mm" height="32mm"/>
            <Line x1="194mm" y1="155mm" x2="260mm" y2="155mm" color="muted" strokeWidth="0.6"/>
            <Text x="194mm" y="156mm" width="66mm" height="6mm" fontSize="10.5" bold="true" alignment="center">[[stampLabel]]</Text>
            <Text name="certificateNumber" x="194mm" y="162mm" width="66mm" height="6mm" fontSize="9" color="muted" alignment="center">[[number]]: {{item.number}}</Text>
            <Text name="pageOf" x="40mm" y="174mm" width="217mm" height="6mm" fontSize="9" color="muted" alignment="center">[[page]] {{System.PageNumber}} [[of]] {{System.TotalPages}}</Text>
        </Detail>
    </Bands>
</QudsReport>
''';

const Map<String, String> _classCertificateAr = <String, String>{
  ..._ar,
  'name': 'شهادات الصف',
  'title': 'شهادة تقدير',
  'presented': 'تشهد إدارة المدرسة بمنح هذه الشهادة إلى',
  'body':
      'لإتمام العام الدراسي \u200E{{Data.year}}\u200E بنجاح، و{{item.note}}. '
      'مع أطيب التمنيات بدوام التوفيق.',
  'issued': 'حُررت بتاريخ',
  'stampLabel': 'ختم المدرسة',
  'number': 'رقم الشهادة',
  'schoolField': 'اسم المدرسة',
  'classField': 'الصف والشعبة',
  'yearField': 'العام الدراسي',
  'dateField': 'تاريخ التحرير',
  'signerNameField': 'اسم الموقّع',
  'signerTitleField': 'صفة الموقّع',
  'studentsTable': 'طالب واحد في كل صف، وصفحة لكل طالب',
  'colName': 'اسم الطالب',
  'colNumber': 'رقم الشهادة',
  'colGrade': 'التقدير',
  'colNote': 'سبب التقدير',
};

const Map<String, String> _classCertificateEn = <String, String>{
  ..._en,
  'name': 'Class certificates',
  'title': 'Certificate of Achievement',
  'presented': 'This certificate is proudly presented to',
  'body':
      'For successfully completing the {{Data.year}} school year, and '
      '{{item.note}}. With every wish for continued success.',
  'issued': 'Issued on',
  'stampLabel': 'School stamp',
  'number': 'Certificate No.',
  'schoolField': 'School name',
  'classField': 'Class',
  'yearField': 'School year',
  'dateField': 'Issue date',
  'signerNameField': 'Signatory',
  'signerTitleField': 'Signatory title',
  'studentsTable': 'One student per row, one page per student',
  'colName': 'Student name',
  'colNumber': 'Certificate number',
  'colGrade': 'Grade',
  'colNote': 'Citation',
};

Map<String, Object?> _classCertificateArData() => _classCertificateData(true);

Map<String, Object?> _classCertificateEnData() => _classCertificateData(false);

Map<String, Object?> _classCertificateData(bool ar) {
  String t(String en, String arabic) => ar ? arabic : en;
  Map<String, Object?> student(
    String nameEn,
    String nameAr,
    String number,
    String gradeEn,
    String gradeAr,
    String noteEn,
    String noteAr,
  ) => <String, Object?>{
    'name': t(nameEn, nameAr),
    'number': number,
    'grade': t(gradeEn, gradeAr),
    'note': t(noteEn, noteAr),
  };
  return <String, Object?>{
    'school': t('Quds Model School', 'مدرسة القدس النموذجية'),
    'className': t('Grade 6-A', 'الصف السادس (أ)'),
    'year': '2025-2026',
    'date': DateTime(2026, 6, 18),
    'signer': <String, Object?>{
      'name': t('Laila Hassan Al-Amin', 'ليلى حسن الأمين'),
      'title': t('Principal', 'مديرة المدرسة'),
    },
    'students': <Map<String, Object?>>[
      student(
        'Sara Ahmed Al-Mansouri',
        'سارة أحمد المنصوري',
        'G6-2026-01',
        'Excellent',
        'ممتاز',
        'for first place in Arabic',
        'لحصولها على الترتيب الأول في اللغة العربية',
      ),
      student(
        'Yousef Khaled Al-Barghathi',
        'يوسف خالد البرغثي',
        'G6-2026-02',
        'Excellent',
        'ممتاز',
        'for the science fair project',
        'لمشروع معرض العلوم',
      ),
      student(
        'Layla Omar Al-Sharif',
        'ليلى عمر الشريف',
        'G6-2026-03',
        'Very good',
        'جيد جدًا',
        'for excellence in mathematics',
        'لتفوقها في الرياضيات',
      ),
      student(
        'Mohammed Ali Al-Tarhuni',
        'محمد علي الترهوني',
        'G6-2026-04',
        'Excellent',
        'ممتاز',
        'for leading the class reading circle',
        'لقيادته حلقة القراءة الصفية',
      ),
      student(
        'Nour Al-Huda Salem',
        'نور الهدى سالم',
        'G6-2026-05',
        'Very good',
        'جيد جدًا',
        'for the art exhibition',
        'لمعرض الرسم',
      ),
      student(
        'Adam Hassan Al-Mabrouk',
        'آدم حسن المبروك',
        'G6-2026-06',
        'Excellent',
        'ممتاز',
        'for the school sports team',
        'لفريق المدرسة الرياضي',
      ),
      student(
        'Huda Faraj Ben Latif',
        'هدى فرج بن لطيف',
        'G6-2026-07',
        'Very good',
        'جيد جدًا',
        'for helping classmates',
        'لعون زملاء الصف',
      ),
      student(
        'Kareem Saleh Al-Zlitni',
        'كريم صالح الزليطني',
        'G6-2026-08',
        'Excellent',
        'ممتاز',
        'for the history research paper',
        'لبحثه في التاريخ',
      ),
    ],
  };
}

// ------------------------------------------------------------ chart gallery

const String _chartGallery = r'''<?xml version="1.0" encoding="UTF-8"?>
<QudsReport name="[[name]]" isRtl="[[rtl]]" pageSize="A4" orientation="Portrait" defaultFont="[[font]]" defaultFontSize="8">
    <Settings>
        <Margins top="12mm" bottom="12mm" left="12mm" right="12mm"/>
        <Colors primary="#1E3A8A" accent="#3B82F6" muted="#64748B" light="#F4F7FB" border="#E1E7EF" text="#0F172A" good="#166534" warm="#B45309"/>
    </Settings>
    <DataSchema>
        <Field name="company" type="text"/>
        <Field name="period" type="text"/>
        <Field name="attainment" type="number" description="[[attainmentField]]"/>
        <Table name="months" description="[[monthsTable]]">
            <Column name="month" type="text"/>
            <Column name="revenue" type="number"/>
            <Column name="cost" type="number"/>
            <Column name="orders" type="number"/>
        </Table>
        <Table name="shares" description="[[sharesTable]]">
            <Column name="name" type="text"/>
            <Column name="amount" type="number"/>
        </Table>
        <Table name="pipeline" description="[[pipelineTable]]">
            <Column name="stage" type="text"/>
            <Column name="count" type="number"/>
        </Table>
        <Table name="deals" description="[[dealsTable]]">
            <Column name="client" type="text"/>
            <Column name="units" type="number"/>
            <Column name="margin" type="number"/>
            <Column name="size" type="number"/>
        </Table>
        <Table name="skills" description="[[skillsTable]]">
            <Column name="skill" type="text"/>
            <Column name="sales" type="number"/>
            <Column name="service" type="number"/>
        </Table>
        <Table name="quarters" description="[[quartersTable]]">
            <Column name="region" type="text"/>
            <Column name="q1" type="number"/>
            <Column name="q2" type="number"/>
            <Column name="q3" type="number"/>
            <Column name="q4" type="number"/>
        </Table>
        <Table name="countries" description="[[countriesTable]]">
            <Column name="code" type="text" description="[[codeField]]"/>
            <Column name="name" type="text"/>
            <Column name="revenue" type="number" description="[[revenueField]]"/>
        </Table>
    </DataSchema>
    <Bands>
        <ReportHeader height="822mm">
            <Shape kind="RoundedRectangle" x="12mm" y="0mm" width="186mm" height="16mm" fill="primary" strokeWidth="0" cornerRadius="3pt"/>
            <Text name="title" x="16mm" y="1mm" width="140mm" height="8mm" fontSize="14" bold="true" color="#FFFFFF">[[title]]</Text>
            <Text x="16mm" y="9mm" width="178mm" height="6mm" fontSize="8" color="#DBEAFE">{{Data.company}}  •  {{Data.period}}</Text>
            <Chart name="bars" x="12mm" y="22mm" width="90mm" height="50mm" chartType="bar" title="[[cBar]]" dataSet="Data.months" category="Row.month" valueFormat="n0" borderColor="border" borderWidth="0.4pt">
                <Series name="[[revenue]]" value="Row.revenue" color="primary"/>
                <Series name="[[cost]]" value="Row.cost" color="#94A3B8"/>
            </Chart>
            <Chart name="hbars" x="106mm" y="22mm" width="92mm" height="50mm" chartType="horizontalBar" title="[[cHBar]]" dataSet="Data.months" category="Row.month" showLegend="false" valueFormat="n0" borderColor="border" borderWidth="0.4pt">
                <Series name="[[orders]]" value="Row.orders" color="accent"/>
            </Chart>
            <Chart name="stacked" x="12mm" y="76mm" width="90mm" height="50mm" chartType="stackedBar" title="[[cStacked]]" dataSet="Data.months" category="Row.month" valueFormat="n0" borderColor="border" borderWidth="0.4pt">
                <Series name="[[revenue]]" value="Row.revenue" color="primary"/>
                <Series name="[[cost]]" value="Row.cost" color="#94A3B8"/>
            </Chart>
            <Chart name="percent" x="106mm" y="76mm" width="92mm" height="50mm" chartType="percentStackedBar" title="[[cPercent]]" dataSet="Data.months" category="Row.month" borderColor="border" borderWidth="0.4pt">
                <Series name="[[revenue]]" value="Row.revenue" color="primary"/>
                <Series name="[[cost]]" value="Row.cost" color="#94A3B8"/>
            </Chart>
            <Chart name="lines" x="12mm" y="130mm" width="90mm" height="50mm" chartType="line" title="[[cLine]]" dataSet="Data.months" category="Row.month" showMarkers="true" valueFormat="n0" borderColor="border" borderWidth="0.4pt">
                <Series name="[[revenue]]" value="Row.revenue" color="primary"/>
            </Chart>
            <Chart name="areas" x="106mm" y="130mm" width="92mm" height="50mm" chartType="area" title="[[cArea]]" dataSet="Data.months" category="Row.month" showLegend="false" valueFormat="n0" borderColor="border" borderWidth="0.4pt">
                <Series name="[[revenue]]" value="Row.revenue" color="accent"/>
            </Chart>
            <Chart name="stackedArea" x="12mm" y="184mm" width="90mm" height="50mm" chartType="stackedArea" title="[[cStackedArea]]" dataSet="Data.months" category="Row.month" valueFormat="n0" borderColor="border" borderWidth="0.4pt">
                <Series name="[[revenue]]" value="Row.revenue" color="primary"/>
                <Series name="[[cost]]" value="Row.cost" color="#94A3B8"/>
            </Chart>
            <Chart name="combo" x="106mm" y="184mm" width="92mm" height="50mm" chartType="combo" title="[[cCombo]]" dataSet="Data.months" category="Row.month" valueFormat="n0" borderColor="border" borderWidth="0.4pt">
                <Series name="[[revenue]]" value="Row.revenue" color="primary" style="column"/>
                <Series name="[[orders]]" value="Row.orders" color="good" style="line" secondary="true"/>
            </Chart>
            <Chart name="pie" x="12mm" y="238mm" width="90mm" height="50mm" chartType="pie" title="[[cPie]]" dataSet="Data.shares" category="Row.name" showValues="true" valueFormat="n0" borderColor="border" borderWidth="0.4pt" palette="#1E3A8A,#3B82F6,#166534,#B45309,#DB2777">
                <Series name="[[amount]]" value="Row.amount"/>
            </Chart>
            <Chart name="donut" x="106mm" y="238mm" width="92mm" height="50mm" chartType="donut" title="[[cDonut]]" dataSet="Data.shares" category="Row.name" showValues="true" valueFormat="n0" borderColor="border" borderWidth="0.4pt" palette="#1E3A8A,#3B82F6,#166534,#B45309,#DB2777">
                <Series name="[[amount]]" value="Row.amount"/>
            </Chart>
            <Chart name="steps" x="12mm" y="292mm" width="90mm" height="50mm" chartType="waterfall" title="[[cWaterfall]]" lastIsTotal="true" valueFormat="n0" borderColor="border" borderWidth="0.4pt">
                <Point label="[[open]]" value="40"/>
                <Point label="[[sales]]" value="28"/>
                <Point label="[[costs]]" value="-18"/>
                <Point label="[[tax]]" value="-6"/>
                <Point label="[[close]]" value="44" total="true"/>
            </Chart>
            <Chart name="funnel" x="106mm" y="292mm" width="92mm" height="50mm" chartType="funnel" title="[[cFunnel]]" dataSet="Data.pipeline" category="Row.stage" showValues="true" showLegend="false" valueFormat="n0" borderColor="border" borderWidth="0.4pt">
                <Series name="[[count]]" value="Row.count" color="primary"/>
            </Chart>
            <Chart name="dial" x="12mm" y="346mm" width="90mm" height="50mm" chartType="gauge" title="[[cGauge]]" axisMin="0" axisMax="100" target="85" bands="3" borderColor="border" borderWidth="0.4pt">
                <Point label="[[score]]" value="Data.attainment"/>
            </Chart>
            <Chart name="bullet" x="106mm" y="346mm" width="92mm" height="50mm" chartType="bullet" title="[[cBullet]]" axisMin="0" axisMax="100" target="80" bands="3" borderColor="border" borderWidth="0.4pt">
                <Point label="[[score]]" value="Data.attainment"/>
            </Chart>
            <Chart name="dots" x="12mm" y="400mm" width="90mm" height="50mm" chartType="scatter" title="[[cScatter]]" dataSet="Data.deals" category="Row.client" borderColor="border" borderWidth="0.4pt">
                <Series name="[[margin]]" value="Row.margin" x="Row.units" color="primary"/>
            </Chart>
            <Chart name="bubbles" x="106mm" y="400mm" width="92mm" height="50mm" chartType="bubble" title="[[cBubble]]" dataSet="Data.deals" category="Row.client" borderColor="border" borderWidth="0.4pt">
                <Series name="[[margin]]" value="Row.margin" x="Row.units" size="Row.size" color="accent"/>
            </Chart>
            <Chart name="radar" x="12mm" y="454mm" width="90mm" height="50mm" chartType="radar" title="[[cRadar]]" dataSet="Data.skills" category="Row.skill" borderColor="border" borderWidth="0.4pt">
                <Series name="[[salesTeam]]" value="Row.sales" color="primary"/>
                <Series name="[[serviceTeam]]" value="Row.service" color="good"/>
            </Chart>
            <Chart name="heat" x="106mm" y="454mm" width="92mm" height="50mm" chartType="heatmap" title="[[cHeat]]" dataSet="Data.quarters" category="Row.region" valueFormat="n0" borderColor="border" borderWidth="0.4pt">
                <Series name="Q1" value="Row.q1"/>
                <Series name="Q2" value="Row.q2"/>
                <Series name="Q3" value="Row.q3"/>
                <Series name="Q4" value="Row.q4"/>
            </Chart>
            <Chart name="spark" x="12mm" y="508mm" width="90mm" height="50mm" chartType="sparkline" title="[[cSpark]]" dataSet="Data.months" category="Row.month" showLegend="false" showAxes="false" showGrid="false" borderColor="border" borderWidth="0.4pt">
                <Series name="[[revenue]]" value="Row.revenue" color="primary"/>
            </Chart>
            <Chart name="solid" x="106mm" y="508mm" width="92mm" height="50mm" chartType="extrudedBar" title="[[cExtrudedBar]]" dataSet="Data.months" category="Row.month" showLegend="false" valueFormat="n0" borderColor="border" borderWidth="0.4pt">
                <Series name="[[revenue]]" value="Row.revenue" color="primary"/>
            </Chart>
            <Chart name="solidPie" x="12mm" y="562mm" width="90mm" height="50mm" chartType="extrudedPie" title="[[cExtrudedPie]]" dataSet="Data.shares" category="Row.name" showValues="true" valueFormat="n0" borderColor="border" borderWidth="0.4pt" palette="#1E3A8A,#3B82F6,#166534,#B45309,#DB2777">
                <Series name="[[amount]]" value="Row.amount"/>
            </Chart>
            <Chart name="solidDonut" x="106mm" y="562mm" width="92mm" height="50mm" chartType="extrudedDonut" title="[[cExtrudedDonut]]" dataSet="Data.shares" category="Row.name" valueFormat="n0" borderColor="border" borderWidth="0.4pt" palette="#1E3A8A,#3B82F6,#166534,#B45309,#DB2777">
                <Series name="[[amount]]" value="Row.amount"/>
            </Chart>
            <Text x="12mm" y="618mm" width="186mm" height="8mm" fontSize="12" bold="true" color="primary">[[mapTitle]]</Text>
            <Text x="12mm" y="626mm" width="186mm" height="6mm" fontSize="8" color="muted">[[mapNote]]</Text>
            <Chart name="worldMap" x="12mm" y="634mm" width="186mm" height="100mm" chartType="shapeMap" shape="world" title="[[cMap]]" dataSet="Data.countries" category="Row.code" shapeKey="code" showLabels="true" showValues="false" valueFormat="n0" borderColor="border" borderWidth="0.4pt">
                <Series name="[[revenue]]" value="Row.revenue" color="primary"/>
            </Chart>
            <Table name="countriesTable" x="12mm" y="740mm" width="186mm" height="80mm" dataSet="Data.countries" showGrid="true" headerBackground="light" headerColor="muted" stripeColor="light" fontSize="8" headerFontSize="7.5" rowHeight="6mm" headerHeight="7mm" padding="3pt">
                <Columns>
                    <Column width="28mm" header="[[colCode]]" align="start"/>
                    <Column width="98mm" header="[[colCountry]]" align="start"/>
                    <Column width="60mm" header="[[colRevenue]]" align="end"/>
                </Columns>
                <RowTemplate>
                    <Cell field="item.code"/>
                    <Cell field="item.name"/>
                    <Cell field="item.revenue" format="n1"/>
                </RowTemplate>
            </Table>
        </ReportHeader>
        <PageFooter height="8mm">
            <Line x1="12mm" y1="1mm" x2="198mm" y2="1mm" color="border" strokeWidth="0.4"/>
            <Text x="12mm" y="2mm" width="120mm" height="5mm" fontSize="7.5" color="muted">{{Data.company}}</Text>
            <Text x="140mm" y="2mm" width="58mm" height="5mm" fontSize="7.5" color="muted" alignment="end">[[page]] {{System.PageNumber}} [[of]] {{System.TotalPages}}</Text>
        </PageFooter>
    </Bands>
</QudsReport>
''';

const Map<String, String> _chartGalleryAr = <String, String>{
  ..._ar,
  'name': 'معرض المخططات',
  'title': 'معرض المخططات',
  'monthsTable': 'شهور المبيعات',
  'sharesTable': 'حصة الفئات',
  'pipelineTable': 'مراحل البيع',
  'dealsTable': 'الصفقات',
  'skillsTable': 'المهارات',
  'quartersTable': 'الإيراد الفصلي حسب المنطقة',
  'countriesTable': 'إيراد الدول — مصدر تلوين الخريطة',
  'codeField': 'رمز ISO الذي يطابق شكل الدولة',
  'revenueField': 'الإيراد بالمليون دولار',
  'attainmentField': 'نسبة التحقيق من 100',
  'cBar': 'أعمدة',
  'cHBar': 'أعمدة أفقية',
  'cStacked': 'أعمدة مكدسة',
  'cPercent': 'مكدس مئوي',
  'cLine': 'خط',
  'cArea': 'مساحة',
  'cStackedArea': 'مساحة مكدسة',
  'cCombo': 'عمود وخط',
  'cPie': 'دائري',
  'cDonut': 'حلقي',
  'cWaterfall': 'شلال',
  'cFunnel': 'قمع',
  'cGauge': 'مقياس',
  'cBullet': 'شريط هدف',
  'cScatter': 'نقطي',
  'cBubble': 'فقاعي',
  'cRadar': 'رادار',
  'cHeat': 'حراري',
  'cSpark': 'شرارة',
  'cExtrudedBar': 'أعمدة مجسمة',
  'cExtrudedPie': 'دائري مجسم',
  'cExtrudedDonut': 'حلقي مجسم',
  'cMap': 'الإيراد حسب الدولة',
  'mapTitle': 'خريطة الدول',
  'mapNote': 'مربوطة بجدول countries: المفتاح Row.code والقيمة Row.revenue',
  'revenue': 'الإيراد',
  'cost': 'التكلفة',
  'orders': 'الطلبات',
  'amount': 'القيمة',
  'count': 'العدد',
  'margin': 'الهامش',
  'salesTeam': 'المبيعات',
  'serviceTeam': 'الخدمة',
  'score': 'التحقيق',
  'open': 'افتتاح',
  'sales': 'مبيعات',
  'costs': 'تكاليف',
  'tax': 'ضريبة',
  'close': 'إقفال',
  'colCode': 'الرمز',
  'colCountry': 'الدولة',
  'colRevenue': 'الإيراد (مليون)',
};

const Map<String, String> _chartGalleryEn = <String, String>{
  ..._en,
  'name': 'Chart Gallery',
  'title': 'Chart gallery',
  'monthsTable': 'Monthly sales',
  'sharesTable': 'Category share',
  'pipelineTable': 'Sales stages',
  'dealsTable': 'Deals',
  'skillsTable': 'Skills',
  'quartersTable': 'Quarterly revenue by region',
  'countriesTable': 'Country revenue — colors the map',
  'codeField': 'ISO code matched to the country shape',
  'revenueField': 'Revenue in millions of USD',
  'attainmentField': 'Attainment out of 100',
  'cBar': 'Columns',
  'cHBar': 'Bars',
  'cStacked': 'Stacked columns',
  'cPercent': '100% stacked',
  'cLine': 'Line',
  'cArea': 'Area',
  'cStackedArea': 'Stacked area',
  'cCombo': 'Column and line',
  'cPie': 'Pie',
  'cDonut': 'Donut',
  'cWaterfall': 'Waterfall',
  'cFunnel': 'Funnel',
  'cGauge': 'Gauge',
  'cBullet': 'Bullet',
  'cScatter': 'Scatter',
  'cBubble': 'Bubble',
  'cRadar': 'Radar',
  'cHeat': 'Heatmap',
  'cSpark': 'Sparkline',
  'cExtrudedBar': 'Extruded columns',
  'cExtrudedPie': 'Extruded pie',
  'cExtrudedDonut': 'Extruded donut',
  'cMap': 'Revenue by country',
  'mapTitle': 'Country map',
  'mapNote': 'Bound to the countries table: key Row.code, value Row.revenue',
  'revenue': 'Revenue',
  'cost': 'Cost',
  'orders': 'Orders',
  'amount': 'Amount',
  'count': 'Count',
  'margin': 'Margin',
  'salesTeam': 'Sales',
  'serviceTeam': 'Service',
  'score': 'Attainment',
  'open': 'Open',
  'sales': 'Sales',
  'costs': 'Costs',
  'tax': 'Tax',
  'close': 'Close',
  'colCode': 'Code',
  'colCountry': 'Country',
  'colRevenue': 'Revenue (million)',
};

Map<String, Object?> _chartGalleryArData() => _chartGalleryData(true);

Map<String, Object?> _chartGalleryEnData() => _chartGalleryData(false);

Map<String, Object?> _chartGalleryData(bool ar) {
  String pick(String en, String arabic) => ar ? arabic : en;
  return <String, Object?>{
    'company': pick('Quds Trading', 'شركة القدس للتجارة'),
    'period': pick('2026', '2026'),
    'attainment': 74,
    'months': <Map<String, Object?>>[
      for (final (String en, String arabic, int revenue, int cost, int orders)
          in <(String, String, int, int, int)>[
            ('Jan', 'يناير', 42, 28, 120),
            ('Feb', 'فبراير', 48, 30, 132),
            ('Mar', 'مارس', 55, 33, 141),
            ('Apr', 'أبريل', 51, 31, 128),
            ('May', 'مايو', 63, 36, 156),
            ('Jun', 'يونيو', 70, 39, 168),
          ])
        <String, Object?>{
          'month': pick(en, arabic),
          'revenue': revenue,
          'cost': cost,
          'orders': orders,
        },
    ],
    'shares': <Map<String, Object?>>[
      for (final (String en, String arabic, int amount)
          in <(String, String, int)>[
            ('Laptops', 'حواسيب', 34),
            ('Monitors', 'شاشات', 22),
            ('Accessories', 'ملحقات', 18),
            ('Printers', 'طابعات', 14),
            ('Services', 'خدمات', 12),
          ])
        <String, Object?>{'name': pick(en, arabic), 'amount': amount},
    ],
    'pipeline': <Map<String, Object?>>[
      for (final (String en, String arabic, int count)
          in <(String, String, int)>[
            ('Leads', 'عملاء محتملون', 240),
            ('Qualified', 'مؤهلون', 140),
            ('Proposal', 'عروض', 72),
            ('Won', 'صفقات رابحة', 31),
          ])
        <String, Object?>{'stage': pick(en, arabic), 'count': count},
    ],
    'deals': <Map<String, Object?>>[
      for (final (String en, String arabic, int units, int margin, int size)
          in <(String, String, int, int, int)>[
            ('Tripoli', 'طرابلس', 12, 18, 4),
            ('Benghazi', 'بنغازي', 20, 27, 7),
            ('Cairo', 'القاهرة', 35, 22, 11),
            ('Tunis', 'تونس', 16, 31, 5),
            ('Riyadh', 'الرياض', 42, 40, 14),
            ('Dubai', 'دبي', 28, 36, 9),
          ])
        <String, Object?>{
          'client': pick(en, arabic),
          'units': units,
          'margin': margin,
          'size': size,
        },
    ],
    'skills': <Map<String, Object?>>[
      for (final (String en, String arabic, int sales, int service)
          in <(String, String, int, int)>[
            ('Closing', 'الإقفال', 80, 55),
            ('Discovery', 'الاستكشاف', 70, 74),
            ('Demo', 'العرض', 64, 60),
            ('Support', 'الدعم', 48, 88),
            ('Renewal', 'التجديد', 76, 69),
          ])
        <String, Object?>{
          'skill': pick(en, arabic),
          'sales': sales,
          'service': service,
        },
    ],
    'quarters': <Map<String, Object?>>[
      for (final (String en, String arabic, int q1, int q2, int q3, int q4)
          in <(String, String, int, int, int, int)>[
            ('North', 'الشمال', 18, 22, 19, 27),
            ('South', 'الجنوب', 12, 14, 16, 15),
            ('East', 'الشرق', 21, 19, 24, 28),
            ('West', 'الغرب', 16, 18, 17, 20),
          ])
        <String, Object?>{
          'region': pick(en, arabic),
          'q1': q1,
          'q2': q2,
          'q3': q3,
          'q4': q4,
        },
    ],
    'countries': <Map<String, Object?>>[
      for (final (String code, String en, String arabic, num revenue)
          in <(String, String, String, num)>[
            ('US', 'United States', 'الولايات المتحدة', 128),
            ('CN', 'China', 'الصين', 96),
            ('DE', 'Germany', 'ألمانيا', 54),
            ('JP', 'Japan', 'اليابان', 47),
            ('FR', 'France', 'فرنسا', 41),
            ('GB', 'United Kingdom', 'المملكة المتحدة', 38),
            ('IN', 'India', 'الهند', 33),
            ('SA', 'Saudi Arabia', 'السعودية', 29),
            ('CA', 'Canada', 'كندا', 27),
            ('BR', 'Brazil', 'البرازيل', 22),
            ('TR', 'Turkey', 'تركيا', 19),
            ('AE', 'United Arab Emirates', 'الإمارات', 18),
            ('EG', 'Egypt', 'مصر', 14),
            ('QA', 'Qatar', 'قطر', 11),
            ('LY', 'Libya', 'ليبيا', 6.4),
          ])
        <String, Object?>{
          'code': code,
          'name': pick(en, arabic),
          'revenue': revenue,
        },
    ],
  };
}

const String _featureShowcase = r'''<?xml version="1.0" encoding="UTF-8"?>
<QudsReport name="[[name]]" isRtl="[[rtl]]" pageSize="A4" orientation="Portrait" defaultFont="[[font]]" defaultFontSize="9">
    <Settings>
        <Margins top="12mm" bottom="12mm" left="12mm" right="12mm"/>
        <Colors primary="#1E3A8A" accent="#B45309" muted="#64748B" light="#F8FAFC" border="#E2E8F0" text="#0F172A"/>
    </Settings>
    <Variables>
        <Var name="customer" value="[[customer]]" prompt="true" required="true" description="[[customerHint]]"/>
        <Var name="po" value="[[po]]" prompt="true" description="[[poHint]]"/>
        <Var name="deliverBy" type="date" value="[[deliverBy]]" prompt="true" description="[[deliverHint]]"/>
    </Variables>
    <Bands>
        <PageHeader height="8mm" printOnFirstPage="false">
            <Text name="pageTitle" x="12mm" y="1mm" width="130mm" height="6mm" fontSize="8" color="muted">[[pageTitle]] · {{Variables.customer}}</Text>
            <Text x="148mm" y="1mm" width="50mm" height="6mm" fontSize="8" color="muted" alignment="end">{{Data.order.number}}</Text>
        </PageHeader>
        <ReportHeader height="114mm">
            <Image name="logo" source="logo" x="12mm" y="1mm" width="18mm" height="18mm"/>
            <Text name="companyName" x="34mm" y="1mm" width="78mm" height="8mm" fontSize="14" bold="true" color="primary">{{Data.company.name}}</Text>
            <Text x="34mm" y="9mm" width="78mm" height="4.5mm" fontSize="8" color="muted">{{Data.company.address}}</Text>
            <Text x="34mm" y="13.5mm" width="78mm" height="4.5mm" fontSize="8" color="muted" direction="ltr">{{Data.company.phone}}  |  {{Data.company.email}}</Text>
            <Text name="reportTitle" x="116mm" y="0mm" width="82mm" height="10mm" fontSize="20" bold="true" color="primary" alignment="end">[[title]]</Text>
            <Barcode name="ean" x="150mm" y="11mm" width="48mm" height="14mm" symbology="ean13" value="4006381333931" fontSize="7"/>
            <Rectangle x="12mm" y="28mm" width="186mm" height="0.7mm" fill="accent" strokeWidth="0"/>
            <Shape kind="RoundedRectangle" name="customerCard" x="12mm" y="32mm" width="68mm" height="26mm" fill="light" strokeWidth="0" cornerRadius="3pt"/>
            <Text x="15mm" y="34mm" width="62mm" height="4mm" fontSize="7.5" color="muted">[[customerCaption]]</Text>
            <Text name="customerName" x="15mm" y="39mm" width="62mm" height="8mm" fontSize="11" bold="true">{{Variables.customer}}</Text>
            <Text x="15mm" y="48mm" width="62mm" height="7mm" fontSize="8" color="muted">{{Data.billTo.city}}</Text>
            <Shape kind="RoundedRectangle" name="orderCard" x="84mm" y="32mm" width="55mm" height="26mm" fill="light" strokeWidth="0" cornerRadius="3pt"/>
            <Text x="87mm" y="34mm" width="49mm" height="4mm" fontSize="7.5" color="muted">[[orderCaption]]</Text>
            <Text name="orderNumber" x="87mm" y="39mm" width="49mm" height="6mm" fontSize="10" bold="true">{{Data.order.number}}</Text>
            <Text x="87mm" y="46mm" width="49mm" height="4mm" fontSize="7.5" color="muted">[[dateCaption]]</Text>
            <Text x="87mm" y="50.5mm" width="49mm" height="5mm" fontSize="8.5" bold="true">{{Data.order.date | date:[[date]]}}</Text>
            <Shape kind="RoundedRectangle" name="deliveryCard" x="143mm" y="32mm" width="55mm" height="26mm" fill="light" strokeWidth="0" cornerRadius="3pt"/>
            <Text x="146mm" y="34mm" width="49mm" height="4mm" fontSize="7.5" color="muted">[[poHint]]</Text>
            <Text name="poValue" x="146mm" y="39mm" width="49mm" height="6mm" fontSize="10" bold="true">{{Variables.po}}</Text>
            <Text x="146mm" y="46mm" width="49mm" height="4mm" fontSize="7.5" color="muted">[[deliverHint]]</Text>
            <Text name="deliverValue" x="146mm" y="50.5mm" width="49mm" height="5mm" fontSize="8.5" bold="true">{{Variables.deliverBy}}</Text>
            <Text name="blurb" x="12mm" y="62mm" width="186mm" height="7mm" fontSize="10">
                <Run>[[lead]]</Run>
                <Run bold="true" link="https://quds.example"> [[linkLabel]]</Run>
            </Text>
            <Text name="aside" x="12mm" y="70mm" width="186mm" height="5.5mm" fontSize="9" italic="true" color="muted">[[italicLine]]</Text>
            <Shape kind="RoundedRectangle" name="scheduleFrame" x="12mm" y="78mm" width="186mm" height="34mm" fill="#FFFFFF" color="border" strokeWidth="0.6" cornerRadius="3pt"/>
            <Subreport name="deliveryNote" template="delivery" dataSet="deliveries" x="14mm" y="78mm" width="182mm" height="34mm"/>
        </ReportHeader>
        <Section dataSet="items">
            <Detail height="8mm">
                <Table name="itemsTable" x="12mm" y="0mm" width="186mm" showGrid="false" headerBackground="primary" headerColor="#FFFFFF" stripeColor="light" fontSize="9" headerFontSize="8" rowHeight="7.2mm" headerHeight="8mm" padding="3pt">
                    <Columns>
                        <Column width="28mm" header="[[colSku]]" align="start"/>
                        <Column width="86mm" header="[[colDescription]]" align="start"/>
                        <Column width="18mm" header="[[colQty]]" align="center"/>
                        <Column width="27mm" header="[[colPrice]]" align="end"/>
                        <Column width="27mm" header="[[colAmount]]" align="end"/>
                    </Columns>
                    <RowTemplate>
                        <Cell field="item.sku"/>
                        <Cell field="item.description"/>
                        <Cell field="item.qty"/>
                        <Cell field="item.price" format="n2"/>
                        <Cell field="item.qty * item.price" format="n2" bold="true"/>
                    </RowTemplate>
                </Table>
            </Detail>
            <GroupFooter height="16mm">
                <Text x="118mm" y="1mm" width="40mm" height="6mm" fontSize="9" color="muted" alignment="end">[[subtotal]]</Text>
                <Text name="subtotal" x="158mm" y="1mm" width="40mm" height="6mm" fontSize="9" alignment="end">{{SUM(item.qty * item.price) | n2}}</Text>
                <Shape kind="RoundedRectangle" name="totalBar" x="116mm" y="8mm" width="82mm" height="8mm" fill="primary" strokeWidth="0" cornerRadius="3pt"/>
                <Text x="120mm" y="8mm" width="34mm" height="8mm" fontSize="10" bold="true" color="#FFFFFF" verticalAlignment="middle">[[totalDue]]</Text>
                <Text name="grandTotal" x="150mm" y="8mm" width="44mm" height="8mm" fontSize="11" bold="true" color="#FFFFFF" alignment="end" verticalAlignment="middle">{{SUM(item.qty * item.price) | [[money]]}}</Text>
            </GroupFooter>
        </Section>
        <Section>
            <Detail height="46mm">
                <Text name="pivotTitle" x="12mm" y="2mm" width="186mm" height="6mm" fontSize="10" bold="true" color="primary">[[pivotTitle]]</Text>
                <Crosstab name="salesPivot" dataSet="sales" rowField="item.branch" columnField="item.month" valueField="item.amount" x="12mm" y="9mm" width="186mm" height="34mm" headerBold="true"/>
            </Detail>
        </Section>
        <PageFooter height="8mm">
            <Line x1="12mm" y1="1mm" x2="198mm" y2="1mm" color="border" strokeWidth="0.4"/>
            <Text x="12mm" y="2.5mm" width="120mm" height="5mm" fontSize="7.5" color="muted">[[thanks]]</Text>
            <Text x="140mm" y="2.5mm" width="58mm" height="5mm" fontSize="7.5" color="muted" alignment="end">[[page]] {{System.PageNumber}} [[of]] {{System.TotalPages}}</Text>
        </PageFooter>
    </Bands>
</QudsReport>
''';

const String _deliveryNoteAr = r'''<?xml version="1.0" encoding="UTF-8"?>
<QudsReport name="delivery" isRtl="true" pageSize="Custom" pageWidth="182mm" pageHeight="34mm" orientation="Landscape" defaultFont="Noto Naskh Arabic" defaultFontSize="8.5">
    <Settings>
        <Margins top="0mm" bottom="0mm" left="0mm" right="0mm"/>
        <Colors primary="#1E3A8A" muted="#64748B" light="#F8FAFC" text="#0F172A"/>
    </Settings>
    <Bands>
        <ReportHeader height="6.5mm">
            <Rectangle x="0mm" y="0mm" width="182mm" height="6.5mm" fill="primary" strokeWidth="0"/>
            <Text name="scheduleTitle" x="3mm" y="0.4mm" width="176mm" height="5.6mm" fontSize="9" bold="true" color="#FFFFFF" verticalAlignment="middle">ملحق التوريد</Text>
        </ReportHeader>
        <Detail dataSet="items" height="6mm">
            <Table name="schedule" x="0mm" y="0mm" width="182mm" showGrid="false" headerBackground="light" headerColor="primary" fontSize="8.5" headerFontSize="7.5" rowHeight="6mm" headerHeight="6mm" padding="2pt">
                <Columns>
                    <Column width="36mm" header="الموعد" align="start"/>
                    <Column width="110mm" header="موقع التسليم" align="start"/>
                    <Column width="36mm" header="الكمية" align="center"/>
                </Columns>
                <RowTemplate>
                    <Cell field="item.when"/>
                    <Cell field="item.site"/>
                    <Cell field="item.qty"/>
                </RowTemplate>
            </Table>
        </Detail>
    </Bands>
</QudsReport>
''';

const String _deliveryNoteEn = r'''<?xml version="1.0" encoding="UTF-8"?>
<QudsReport name="delivery" isRtl="false" pageSize="Custom" pageWidth="182mm" pageHeight="34mm" orientation="Landscape" defaultFont="Liberation Sans" defaultFontSize="8.5">
    <Settings>
        <Margins top="0mm" bottom="0mm" left="0mm" right="0mm"/>
        <Colors primary="#1E3A8A" muted="#64748B" light="#F8FAFC" text="#0F172A"/>
    </Settings>
    <Bands>
        <ReportHeader height="6.5mm">
            <Rectangle x="0mm" y="0mm" width="182mm" height="6.5mm" fill="primary" strokeWidth="0"/>
            <Text name="scheduleTitle" x="3mm" y="0.4mm" width="176mm" height="5.6mm" fontSize="9" bold="true" color="#FFFFFF" verticalAlignment="middle">Delivery schedule</Text>
        </ReportHeader>
        <Detail dataSet="items" height="6mm">
            <Table name="schedule" x="0mm" y="0mm" width="182mm" showGrid="false" headerBackground="light" headerColor="primary" fontSize="8.5" headerFontSize="7.5" rowHeight="6mm" headerHeight="6mm" padding="2pt">
                <Columns>
                    <Column width="36mm" header="WHEN" align="start"/>
                    <Column width="110mm" header="SITE" align="start"/>
                    <Column width="36mm" header="QTY" align="center"/>
                </Columns>
                <RowTemplate>
                    <Cell field="item.when"/>
                    <Cell field="item.site"/>
                    <Cell field="item.qty"/>
                </RowTemplate>
            </Table>
        </Detail>
    </Bands>
</QudsReport>
''';

const Map<String, String> _featureSubreportsAr = <String, String>{
  'delivery': _deliveryNoteAr,
};

const Map<String, String> _featureSubreportsEn = <String, String>{
  'delivery': _deliveryNoteEn,
};

const Map<String, String> _featureShowcaseAr = <String, String>{
  ..._ar,
  'name': 'أمر بيع',
  'pageTitle': 'أمر بيع',
  'title': 'أمر بيع',
  'lead': 'نؤكد قبول الطلب وفق الشروط المنشورة.',
  'linkLabel': 'شروط التوريد',
  'italicLine': 'الأسعار شاملة التجهيز، والتوريد حسب الملحق أدناه.',
  'customer': 'مؤسسة النور للتجارة',
  'customerHint': 'اسم العميل',
  'po': 'PO-441',
  'poHint': 'أمر الشراء',
  'deliverBy': '2026-10-24',
  'deliverHint': 'موعد التوريد',
  'orderCaption': 'رقم الأمر',
  'dateCaption': 'التاريخ',
  'customerCaption': 'العميل',
  'colSku': 'الرمز',
  'colDescription': 'الوصف',
  'colQty': 'الكمية',
  'colPrice': 'السعر',
  'colAmount': 'المبلغ',
  'subtotal': 'المجموع',
  'totalDue': 'الإجمالي',
  'pivotTitle': 'مبيعات الفروع',
  'thanks': 'شركة القدس للتقنية',
};

const Map<String, String> _featureShowcaseEn = <String, String>{
  ..._en,
  'name': 'Sales order',
  'pageTitle': 'Sales order',
  'title': 'SALES ORDER',
  'lead': 'We confirm this order under the published terms.',
  'linkLabel': 'Delivery terms',
  'italicLine': 'Prices include preparation. Delivery follows the schedule below.',
  'customer': 'Al-Noor Trading',
  'customerHint': 'Customer',
  'po': 'PO-441',
  'poHint': 'Purchase order',
  'deliverBy': '2026-10-24',
  'deliverHint': 'Deliver by',
  'orderCaption': 'Order',
  'dateCaption': 'Date',
  'customerCaption': 'Customer',
  'colSku': 'SKU',
  'colDescription': 'DESCRIPTION',
  'colQty': 'QTY',
  'colPrice': 'PRICE',
  'colAmount': 'AMOUNT',
  'subtotal': 'Subtotal',
  'totalDue': 'TOTAL',
  'pivotTitle': 'Sales by branch',
  'thanks': 'Quds Technology Co.',
};

Map<String, Object?> _featureShowcaseArData() => _featureShowcaseData(true);

Map<String, Object?> _featureShowcaseEnData() => _featureShowcaseData(false);

Map<String, Object?> _featureShowcaseData(bool ar) {
  String t(String en, String arabic) => ar ? arabic : en;
  return <String, Object?>{
    'company': <String, Object?>{
      'name': t('Quds Technology Co.', 'شركة القدس للتقنية'),
      'address': t('Republic Street, Tripoli', 'طرابلس — شارع الجمهورية'),
      'phone': '+218 21 444 0101',
      'email': 'sales@quds.example',
    },
    'billTo': <String, Object?>{
      'city': t('Tripoli', 'طرابلس'),
    },
    'order': <String, Object?>{
      'number': 'SO-2026-0142',
      'date': DateTime(2026, 10, 10),
    },
    'items': <Map<String, Object?>>[
      <String, Object?>{
        'sku': 'QOS-ENT',
        'description': t(
          'Enterprise license, per seat',
          'ترخيص مؤسسات لكل مستخدم',
        ),
        'qty': 12,
        'price': 180,
      },
      <String, Object?>{
        'sku': 'QOS-SUP',
        'description': t('Annual support', 'دعم سنوي'),
        'qty': 12,
        'price': 36,
      },
      <String, Object?>{
        'sku': 'QOS-TRN',
        'description': t('On-site training day', 'يوم تدريب في الموقع'),
        'qty': 3,
        'price': 220,
      },
    ],
    'deliveries': <Map<String, Object?>>[
      <String, Object?>{
        'when': '22/10/2026',
        'site': t('Tripoli headquarters', 'المقر — طرابلس'),
        'qty': 12,
      },
      <String, Object?>{
        'when': '24/10/2026',
        'site': t('Benghazi office', 'مكتب بنغازي'),
        'qty': 8,
      },
      <String, Object?>{
        'when': '02/11/2026',
        'site': t('Misrata warehouse', 'مخزن مصراتة'),
        'qty': 7,
      },
    ],
    'sales': <Map<String, Object?>>[
      <String, Object?>{
        'branch': t('East', 'الشرق'),
        'month': t('Jan', 'يناير'),
        'amount': 18,
      },
      <String, Object?>{
        'branch': t('East', 'الشرق'),
        'month': t('Feb', 'فبراير'),
        'amount': 11,
      },
      <String, Object?>{
        'branch': t('West', 'الغرب'),
        'month': t('Jan', 'يناير'),
        'amount': 9,
      },
      <String, Object?>{
        'branch': t('West', 'الغرب'),
        'month': t('Feb', 'فبراير'),
        'amount': 6,
      },
    ],
  };
}
