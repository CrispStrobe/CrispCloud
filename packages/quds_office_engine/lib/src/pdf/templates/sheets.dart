/// Shared sheet layouts used by the classified template suite.
library;

import 'dart:typed_data';

import '../../builders/office_markup.dart';
import '../../fonts/sfnt_parser.dart';
import '../widgets/pw_box.dart';
import '../widgets/pw_core.dart';
import '../widgets/pw_layout.dart';
import '../widgets/pw_media.dart';
import '../widgets/pw_style.dart';
import '../widgets/pw_text.dart';
import '../widgets/pw_types.dart';
import 'kit.dart';

part 'skins.dart';

/// Which blocks a [SheetTemplate] paints.
enum SheetKind {
  /// Parties, lines, and optional money totals.
  trade,

  /// Facts plus a movement table.
  ledger,

  /// Parties, paragraphs, and a sign-off.
  letter,

  /// Landscape award.
  award,

  /// Facts plus a mark table.
  check,

  /// Sections, optional chart, next steps.
  brief,

  /// Filter facts plus a record table.
  listing,

  /// Metric cards and an optional chart.
  score,
}

/// How the page is composed. Text does not pick this; the document type does.
enum SheetSkin {
  /// Parties, ruled lines, and a money box.
  invoice,

  /// Narrow centred slip and a large total.
  receipt,

  /// Centred title, parties, and a priced table. Not an invoice bar.
  quote,

  /// Letterhead, date, and prose. No colour band.
  letter,

  /// Framed, centred award.
  certificate,

  /// Opening and closing chips, then a movement table.
  statement,

  /// Two stacks and a net bar.
  split,

  /// Large number cards and a chart.
  tiles,

  /// Time gutter and item cards.
  timeline,

  /// Drawn boxes, not a table of mark words.
  checks,

  /// Origin and destination, then a manifest.
  route,

  /// Centred masthead and a headline.
  masthead,

  /// Subject rows with a mark pill.
  grades,

  /// Name panel on the start edge.
  identity,

  /// Heavy top rule and a boxed notice.
  notice,

  /// Cheque-like frame and an amount box.
  voucher,

  /// Ruled catalogue cards, no header band.
  catalog,

  /// Two option columns.
  comparison,

  /// Debit and credit columns.
  journal,
}

/// Default skin when a caller does not pick one.
SheetSkin skinForKind(SheetKind kind) {
  return switch (kind) {
    SheetKind.trade => SheetSkin.invoice,
    SheetKind.ledger => SheetSkin.statement,
    SheetKind.letter => SheetSkin.letter,
    SheetKind.award => SheetSkin.certificate,
    SheetKind.check => SheetSkin.checks,
    SheetKind.brief => SheetSkin.masthead,
    SheetKind.listing => SheetSkin.catalog,
    SheetKind.score => SheetSkin.tiles,
  };
}

/// Headings for a [SheetTemplate]. Replace every string for another language.
class SheetLabels {
  /// SheetLabels API.
  const SheetLabels({
    required this.document,
    this.from = 'From',
    this.to = 'To',
    this.number = 'Number',
    this.date = 'Date',
    this.extra = 'Reference',
    this.subject = 'Subject',
    this.notes = 'Notes',
    this.subtotal = 'Subtotal',
    this.tax = 'Tax',
    this.total = 'Total',
    this.presentedTo = 'Presented to',
    this.columns = const <String>['Description', 'Detail', 'Amount'],
  });

  /// document API.
  final String document;

  /// from API.
  final String from;

  /// to API.
  final String to;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API.
  final String subject;

  /// notes API.
  final String notes;

  /// subtotal API.
  final String subtotal;

  /// tax API.
  final String tax;

  /// total API.
  final String total;

  /// presentedTo API.
  final String presentedTo;

  /// columns API. Logical order. RTL flips the table.
  final List<String> columns;
}

/// A named suite template. [save] writes one document in [direction].
abstract interface class SuiteSheet {
  /// save API.
  Uint8List save();
}

/// Shared constructor shape so the catalog can build any suite template.
typedef SuiteCtor = SuiteSheet Function({
  TextDirection direction,
  TemplateTheme? theme,
  SfntFont? font,
  SfntFont? fontBold,
  required TemplateParty from,
  TemplateParty? to,
  SheetLabels? labels,
  String number,
  String date,
  String extra,
  String subject,
  String recipient,
  List<SheetRow> rows,
  List<String> paragraphs,
  List<TemplateSection> sections,
  List<(String, String)> metrics,
  List<ChartPoint>? chart,
  String chartTitle,
  MoneyTotals? totals,
  String? notes,
  String footer,
  List<SignSlot> signs,
});

/// One table row. Cells follow [SheetLabels.columns].
class SheetRow {
  /// SheetRow API.
  const SheetRow(this.cells);

  /// cells API.
  final List<String> cells;
}

/// A customizable sheet. Named suite classes wrap this with domain defaults.
class SheetTemplate {
  /// SheetTemplate API.
  SheetTemplate({
    required this.kind,
    this.direction = TextDirection.ltr,
    required this.theme,
    this.font,
    this.fontBold,
    required this.owner,
    this.other,
    this.labels = const SheetLabels(document: 'Report'),
    this.number = '',
    this.date = '',
    this.extra = '',
    this.subject = '',
    this.recipient = '',
    this.rows = const <SheetRow>[],
    this.paragraphs = const <String>[],
    this.sections = const <TemplateSection>[],
    this.metrics = const <(String, String)>[],
    this.chart,
    this.chartTitle = '',
    this.totals,
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
    this.landscape = false,
    SheetSkin? skin,
  }) : skin = skin ?? skinForKind(kind);

  /// kind API.
  final SheetKind kind;

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// owner API. Start party. Also the document author.
  final TemplateParty owner;

  /// other API. End party. Omitted when null.
  final TemplateParty? other;

  /// labels API.
  final SheetLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// extra API.
  final String extra;

  /// subject API. When set, it becomes the band title.
  final String subject;

  /// recipient API. Used by [SheetKind.award].
  final String recipient;

  /// rows API.
  final List<SheetRow> rows;

  /// paragraphs API.
  final List<String> paragraphs;

  /// sections API.
  final List<TemplateSection> sections;

  /// metrics API.
  final List<(String, String)> metrics;

  /// chart API.
  final List<ChartPoint>? chart;

  /// chartTitle API.
  final String chartTitle;

  /// totals API.
  final MoneyTotals? totals;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  /// landscape API.
  final bool landscape;

  /// skin API. The page composition, not the words.
  final SheetSkin skin;

  /// save API.
  Uint8List save() {
    final String title = subject.isEmpty ? labels.document : subject;
    return TemplateDocument.save(
      title: title,
      author: owner.name,
      direction: direction,
      theme: theme,
      font: font,
      fontBold: fontBold,
      footer: footer.isEmpty ? owner.name : footer,
      pageFormat: landscape ? theme.pageFormat.landscape : null,
      build: _build,
    );
  }

  List<Widget> _build(Context context) => paintSheetSkin(this);
}
