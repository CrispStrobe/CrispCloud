/// Ready report templates on top of `pdf_widgets`.
///
/// Import this library on its own. Do not mix it with Flutter's `Text` or
/// `TextDirection` in the same prefix. In a Flutter file:
///
/// ```dart
/// import 'package:quds_office_engine/pdf_templates.dart' as tpl;
///
/// final bytes = tpl.InvoiceTemplate(
///   direction: tpl.TextDirection.rtl,
///   labels: const tpl.TradeLabels(document: 'فاتورة', from: 'من', to: 'إلى'),
///   seller: const tpl.TemplateParty(name: 'الورشة'),
///   buyer: const tpl.TemplateParty(name: 'الحيّ'),
///   totals: const tpl.MoneyTotals(subtotal: '100', total: '100'),
/// ).save();
/// ```
///
/// Every heading is a field on a labels class. [TemplateCatalog] is the index.
/// [TemplateTheme.copyWith] changes color without copying the layout.
/// [TextDirection] flips parties, tables, totals, and the footer.
///
/// To grow a template, reuse [templateBand], [templateTable], and
/// [TemplateDocument.save].
library;

export 'src/builders/office_markup.dart' show ChartPoint;
export 'src/fonts/sfnt_parser.dart' show SfntFont;
export 'src/pdf/templates/catalog.dart';
export 'src/pdf/templates/commerce.dart';
export 'src/pdf/templates/data_reports.dart';
export 'src/pdf/templates/finance.dart';
export 'src/pdf/templates/kit.dart'
    show
        CheckItem,
        CheckMark,
        MoneyTotals,
        joinTemplateFiles,
        SignSlot,
        TemplateDocument,
        TemplateParty,
        TemplateSection,
        TemplateTheme,
        TemplateThemes,
        templateBand,
        templateFacts,
        templateGap,
        templateNotes,
        templateParagraphs,
        templateParties,
        templateSection,
        templateSigns,
        templateTable,
        templateTotals;
export 'src/pdf/templates/narrative.dart';
export 'src/pdf/templates/operations.dart';
export 'src/pdf/templates/people.dart';
export 'src/pdf/templates/sheets.dart'
    show SheetKind, SheetLabels, SheetRow, SheetSkin, SheetTemplate, SuiteSheet;
export 'src/pdf/templates/suite.dart';
export 'src/pdf/widgets/pw_types.dart'
    show PageOrientation, PdfPageFormat, TextDirection;
