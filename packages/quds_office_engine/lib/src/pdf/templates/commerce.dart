/// Commerce templates: invoice, quote, receipt, delivery note.
library;

import 'dart:typed_data';

import '../../fonts/sfnt_parser.dart';
import '../widgets/pw_types.dart';
import 'kit.dart';
import 'sheets.dart';

/// Column headings for a trade table. Replace every string for another language.
class TradeLabels {
  /// TradeLabels API.
  const TradeLabels({
    this.document = 'Invoice',
    this.from = 'From',
    this.to = 'To',
    this.number = 'Number',
    this.date = 'Date',
    this.extra = 'Due',
    this.description = 'Description',
    this.quantity = 'Qty',
    this.unit = 'Unit',
    this.amount = 'Amount',
    this.subtotal = 'Subtotal',
    this.tax = 'Tax',
    this.total = 'Total',
    this.notes = 'Notes',
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

  /// extra API. Due date, valid until, payment, or ship date.
  final String extra;

  /// description API.
  final String description;

  /// quantity API.
  final String quantity;

  /// unit API.
  final String unit;

  /// amount API.
  final String amount;

  /// subtotal API.
  final String subtotal;

  /// tax API.
  final String tax;

  /// total API.
  final String total;

  /// notes API.
  final String notes;
}

/// One trade line. Quantity, unit, and amount are already formatted.
class TradeLine {
  /// TradeLine API.
  const TradeLine({
    required this.description,
    this.quantity = '',
    this.unit = '',
    this.amount = '',
    this.detail = '',
  });

  /// description API.
  final String description;

  /// quantity API.
  final String quantity;

  /// unit API.
  final String unit;

  /// amount API.
  final String amount;

  /// detail API. Ordered vs shipped, or a second quantity.
  final String detail;
}

/// Commercial invoice.
class InvoiceTemplate {
  /// InvoiceTemplate API.
  InvoiceTemplate({
    this.direction = TextDirection.ltr,
    this.theme = TemplateThemes.commerce,
    this.font,
    this.fontBold,
    required this.seller,
    required this.buyer,
    this.lines = const <TradeLine>[],
    required this.totals,
    this.labels = const TradeLabels(),
    this.number = '',
    this.date = '',
    this.due = '',
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  });

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// seller API.
  final TemplateParty seller;

  /// buyer API.
  final TemplateParty buyer;

  /// lines API.
  final List<TradeLine> lines;

  /// totals API.
  final MoneyTotals totals;

  /// labels API.
  final TradeLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// due API.
  final String due;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  /// save API.
  Uint8List save() {
    return _trade(
      skin: SheetSkin.invoice,
      direction: direction,
      theme: theme,
      font: font,
      fontBold: fontBold,
      start: seller,
      end: buyer,
      labels: labels,
      number: number,
      date: date,
      extra: due,
      columns: <String>[
        labels.description,
        labels.quantity,
        labels.unit,
        labels.amount,
      ],
      rows: <SheetRow>[
        for (final TradeLine line in lines)
          SheetRow(<String>[
            line.description,
            line.quantity,
            line.unit,
            line.amount,
          ]),
      ],
      totals: totals,
      notes: notes,
      footer: footer,
      signs: signs,
    );
  }
}

/// Quote or estimate. [validUntil] uses the extra label.
class QuoteTemplate {
  /// QuoteTemplate API.
  QuoteTemplate({
    this.direction = TextDirection.ltr,
    this.theme = TemplateThemes.commerce,
    this.font,
    this.fontBold,
    required this.seller,
    required this.buyer,
    this.lines = const <TradeLine>[],
    required this.totals,
    this.labels = const TradeLabels(document: 'Quote', extra: 'Valid until'),
    this.number = '',
    this.date = '',
    this.validUntil = '',
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  });

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// seller API.
  final TemplateParty seller;

  /// buyer API.
  final TemplateParty buyer;

  /// lines API.
  final List<TradeLine> lines;

  /// totals API.
  final MoneyTotals totals;

  /// labels API.
  final TradeLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// validUntil API.
  final String validUntil;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  /// save API.
  Uint8List save() {
    return _trade(
      skin: SheetSkin.quote,
      direction: direction,
      theme: theme,
      font: font,
      fontBold: fontBold,
      start: seller,
      end: buyer,
      labels: labels,
      number: number,
      date: date,
      extra: validUntil,
      columns: <String>[
        labels.description,
        labels.quantity,
        labels.unit,
        labels.amount,
      ],
      rows: <SheetRow>[
        for (final TradeLine line in lines)
          SheetRow(<String>[
            line.description,
            line.quantity,
            line.unit,
            line.amount,
          ]),
      ],
      totals: totals,
      notes: notes,
      footer: footer,
      signs: signs,
    );
  }
}

/// Receipt. [method] uses the extra label.
class ReceiptTemplate {
  /// ReceiptTemplate API.
  ReceiptTemplate({
    this.direction = TextDirection.ltr,
    this.theme = TemplateThemes.commerce,
    this.font,
    this.fontBold,
    required this.seller,
    required this.buyer,
    this.lines = const <TradeLine>[],
    required this.totals,
    this.labels = const TradeLabels(document: 'Receipt', extra: 'Paid by'),
    this.number = '',
    this.date = '',
    this.method = '',
    this.notes,
    this.footer = '',
  });

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// seller API.
  final TemplateParty seller;

  /// buyer API.
  final TemplateParty buyer;

  /// lines API.
  final List<TradeLine> lines;

  /// totals API.
  final MoneyTotals totals;

  /// labels API.
  final TradeLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// method API.
  final String method;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// save API.
  Uint8List save() {
    return _trade(
      skin: SheetSkin.receipt,
      direction: direction,
      theme: theme,
      font: font,
      fontBold: fontBold,
      start: seller,
      end: buyer,
      labels: labels,
      number: number,
      date: date,
      extra: method,
      columns: <String>[labels.description, labels.amount],
      rows: <SheetRow>[
        for (final TradeLine line in lines)
          SheetRow(<String>[line.description, line.amount]),
      ],
      totals: totals,
      notes: notes,
      footer: footer,
      signs: const <SignSlot>[],
    );
  }
}

/// Delivery note. [detail] is the second quantity (shipped).
class DeliveryNoteTemplate {
  /// DeliveryNoteTemplate API.
  DeliveryNoteTemplate({
    this.direction = TextDirection.ltr,
    this.theme = TemplateThemes.commerce,
    this.font,
    this.fontBold,
    required this.sender,
    required this.receiver,
    this.lines = const <TradeLine>[],
    this.labels = const TradeLabels(
      document: 'Delivery note',
      from: 'Sender',
      to: 'Receiver',
      extra: 'Ship date',
      quantity: 'Ordered',
      unit: 'Shipped',
    ),
    this.number = '',
    this.date = '',
    this.shipDate = '',
    this.notes,
    this.footer = '',
    this.signs = const <SignSlot>[],
  });

  /// direction API.
  final TextDirection direction;

  /// theme API.
  final TemplateTheme theme;

  /// font API.
  final SfntFont? font;

  /// fontBold API.
  final SfntFont? fontBold;

  /// sender API.
  final TemplateParty sender;

  /// receiver API.
  final TemplateParty receiver;

  /// lines API.
  final List<TradeLine> lines;

  /// labels API.
  final TradeLabels labels;

  /// number API.
  final String number;

  /// date API.
  final String date;

  /// shipDate API.
  final String shipDate;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  /// save API.
  Uint8List save() {
    return _trade(
      skin: SheetSkin.route,
      direction: direction,
      theme: theme,
      font: font,
      fontBold: fontBold,
      start: sender,
      end: receiver,
      labels: labels,
      number: number,
      date: date,
      extra: shipDate,
      columns: <String>[
        labels.description,
        labels.quantity,
        labels.unit,
      ],
      rows: <SheetRow>[
        for (final TradeLine line in lines)
          SheetRow(<String>[line.description, line.quantity, line.detail]),
      ],
      totals: null,
      notes: notes,
      footer: footer,
      signs: signs,
    );
  }
}

Uint8List _trade({
  required SheetSkin skin,
  required TextDirection direction,
  required TemplateTheme theme,
  required SfntFont? font,
  required SfntFont? fontBold,
  required TemplateParty start,
  required TemplateParty end,
  required TradeLabels labels,
  required String number,
  required String date,
  required String extra,
  required List<String> columns,
  required List<SheetRow> rows,
  required MoneyTotals? totals,
  required String? notes,
  required String footer,
  required List<SignSlot> signs,
}) {
  return SheetTemplate(
    kind: SheetKind.trade,
    skin: skin,
    direction: direction,
    theme: theme,
    font: font,
    fontBold: fontBold,
    owner: start,
    other: end,
    labels: SheetLabels(
      document: labels.document,
      from: labels.from,
      to: labels.to,
      number: labels.number,
      date: labels.date,
      extra: labels.extra,
      notes: labels.notes,
      subtotal: labels.subtotal,
      tax: labels.tax,
      total: labels.total,
      columns: columns,
    ),
    number: number,
    date: date,
    extra: extra,
    rows: rows,
    totals: totals,
    notes: notes,
    footer: footer.isEmpty ? start.name : footer,
    signs: signs,
  ).save();
}
