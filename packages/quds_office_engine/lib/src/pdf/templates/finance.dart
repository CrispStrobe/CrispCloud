/// Finance templates: statement, expense claim, payslip.
library;

import 'dart:typed_data';

import '../../fonts/sfnt_parser.dart';
import '../widgets/pw_types.dart';
import 'kit.dart';
import 'sheets.dart';

/// One movement on a statement. Amounts are already formatted.
class StatementLine {
  /// StatementLine API.
  const StatementLine({
    required this.date,
    required this.detail,
    this.debit = '',
    this.credit = '',
    this.balance = '',
  });

  /// date API.
  final String date;

  /// detail API.
  final String detail;

  /// debit API.
  final String debit;

  /// credit API.
  final String credit;

  /// balance API.
  final String balance;
}

/// Column labels for a statement.
class StatementLabels {
  /// StatementLabels API.
  const StatementLabels({
    this.document = 'Statement',
    this.account = 'Account',
    this.period = 'Period',
    this.opening = 'Opening',
    this.closing = 'Closing',
    this.date = 'Date',
    this.detail = 'Detail',
    this.debit = 'Debit',
    this.credit = 'Credit',
    this.balance = 'Balance',
    this.notes = 'Notes',
  });

  /// document API.
  final String document;

  /// account API.
  final String account;

  /// period API.
  final String period;

  /// opening API.
  final String opening;

  /// closing API.
  final String closing;

  /// date API.
  final String date;

  /// detail API.
  final String detail;

  /// debit API.
  final String debit;

  /// credit API.
  final String credit;

  /// balance API.
  final String balance;

  /// notes API.
  final String notes;
}

/// Account statement.
class StatementTemplate {
  /// StatementTemplate API.
  StatementTemplate({
    this.direction = TextDirection.ltr,
    this.theme = TemplateThemes.finance,
    this.font,
    this.fontBold,
    required this.issuer,
    required this.account,
    this.lines = const <StatementLine>[],
    this.labels = const StatementLabels(),
    this.period = '',
    this.opening = '',
    this.closing = '',
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

  /// issuer API.
  final TemplateParty issuer;

  /// account API.
  final TemplateParty account;

  /// lines API.
  final List<StatementLine> lines;

  /// labels API.
  final StatementLabels labels;

  /// period API.
  final String period;

  /// opening API.
  final String opening;

  /// closing API.
  final String closing;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// save API.
  Uint8List save() {
    return SheetTemplate(
      kind: SheetKind.ledger,
      skin: SheetSkin.statement,
      direction: direction,
      theme: theme,
      font: font,
      fontBold: fontBold,
      owner: issuer,
      other: account,
      labels: SheetLabels(
        document: labels.document,
        from: labels.account,
        to: issuer.name,
        number: labels.period,
        date: labels.opening,
        extra: labels.closing,
        notes: labels.notes,
        columns: <String>[
          labels.date,
          labels.detail,
          labels.debit,
          labels.credit,
          labels.balance,
        ],
      ),
      number: period,
      date: opening,
      extra: closing,
      rows: <SheetRow>[
        for (final StatementLine line in lines)
          SheetRow(<String>[
            line.date,
            line.detail,
            line.debit,
            line.credit,
            line.balance,
          ]),
      ],
      notes: notes,
      footer: footer.isEmpty ? issuer.name : footer,
    ).save();
  }
}

/// One expense row.
class ExpenseLine {
  /// ExpenseLine API.
  const ExpenseLine({
    required this.date,
    required this.category,
    this.note = '',
    required this.amount,
  });

  /// date API.
  final String date;

  /// category API.
  final String category;

  /// note API.
  final String note;

  /// amount API.
  final String amount;
}

/// Labels for an expense claim.
class ExpenseLabels {
  /// ExpenseLabels API.
  const ExpenseLabels({
    this.document = 'Expense claim',
    this.claimant = 'Claimant',
    this.purpose = 'Purpose',
    this.date = 'Date',
    this.category = 'Category',
    this.note = 'Note',
    this.amount = 'Amount',
    this.total = 'Total',
    this.notes = 'Notes',
  });

  /// document API.
  final String document;

  /// claimant API.
  final String claimant;

  /// purpose API.
  final String purpose;

  /// date API.
  final String date;

  /// category API.
  final String category;

  /// note API.
  final String note;

  /// amount API.
  final String amount;

  /// total API.
  final String total;

  /// notes API.
  final String notes;
}

/// Expense claim.
class ExpenseTemplate {
  /// ExpenseTemplate API.
  ExpenseTemplate({
    this.direction = TextDirection.ltr,
    this.theme = TemplateThemes.finance,
    this.font,
    this.fontBold,
    required this.claimant,
    this.lines = const <ExpenseLine>[],
    required this.total,
    this.labels = const ExpenseLabels(),
    this.purpose = '',
    this.date = '',
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

  /// claimant API.
  final TemplateParty claimant;

  /// lines API.
  final List<ExpenseLine> lines;

  /// total API.
  final String total;

  /// labels API.
  final ExpenseLabels labels;

  /// purpose API.
  final String purpose;

  /// date API.
  final String date;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  /// save API.
  Uint8List save() {
    return SheetTemplate(
      kind: SheetKind.ledger,
      skin: SheetSkin.voucher,
      direction: direction,
      theme: theme,
      font: font,
      fontBold: fontBold,
      owner: claimant,
      labels: SheetLabels(
        document: labels.document,
        to: labels.purpose,
        number: labels.claimant,
        date: labels.date,
        total: labels.total,
        notes: labels.notes,
        columns: <String>[
          labels.category,
          labels.note,
          labels.amount,
        ],
      ),
      number: claimant.name,
      date: date,
      recipient: purpose,
      rows: <SheetRow>[
        for (final ExpenseLine line in lines)
          SheetRow(<String>[line.category, line.note, line.amount]),
      ],
      totals: MoneyTotals(subtotal: total, total: total),
      notes: notes,
      footer: footer.isEmpty ? claimant.name : footer,
      signs: signs,
    ).save();
  }
}

/// One payslip amount, already formatted.
class PayLine {
  /// PayLine API.
  const PayLine({required this.label, required this.amount});

  /// label API.
  final String label;

  /// amount API.
  final String amount;
}

/// Payslip labels.
class PayslipLabels {
  /// PayslipLabels API.
  const PayslipLabels({
    this.document = 'Payslip',
    this.employee = 'Employee',
    this.period = 'Period',
    this.paidOn = 'Paid on',
    this.earnings = 'Earnings',
    this.deductions = 'Deductions',
    this.item = 'Item',
    this.amount = 'Amount',
    this.net = 'Net pay',
  });

  /// document API.
  final String document;

  /// employee API.
  final String employee;

  /// period API.
  final String period;

  /// paidOn API.
  final String paidOn;

  /// earnings API.
  final String earnings;

  /// deductions API.
  final String deductions;

  /// item API.
  final String item;

  /// amount API.
  final String amount;

  /// net API.
  final String net;
}

/// Payslip: earnings, deductions, net.
class PayslipTemplate {
  /// PayslipTemplate API.
  PayslipTemplate({
    this.direction = TextDirection.ltr,
    this.theme = TemplateThemes.finance,
    this.font,
    this.fontBold,
    required this.employer,
    required this.employee,
    this.earnings = const <PayLine>[],
    this.deductions = const <PayLine>[],
    required this.net,
    this.labels = const PayslipLabels(),
    this.period = '',
    this.paidOn = '',
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

  /// employer API.
  final TemplateParty employer;

  /// employee API.
  final TemplateParty employee;

  /// earnings API.
  final List<PayLine> earnings;

  /// deductions API.
  final List<PayLine> deductions;

  /// net API.
  final String net;

  /// labels API.
  final PayslipLabels labels;

  /// period API.
  final String period;

  /// paidOn API.
  final String paidOn;

  /// footer API.
  final String footer;

  /// save API.
  Uint8List save() {
    return SheetTemplate(
      kind: SheetKind.ledger,
      skin: SheetSkin.split,
      direction: direction,
      theme: theme,
      font: font,
      fontBold: fontBold,
      owner: employer,
      other: employee,
      labels: SheetLabels(
        document: labels.document,
        from: labels.earnings,
        to: labels.deductions,
        number: labels.paidOn,
        date: labels.period,
        total: labels.net,
      ),
      number: paidOn,
      date: period,
      subject: '${labels.document}  ·  ${employee.name}',
      metrics: <(String, String)>[
        for (final PayLine line in earnings) (line.label, line.amount),
      ],
      rows: <SheetRow>[
        for (final PayLine line in deductions) SheetRow(<String>[line.label, line.amount]),
      ],
      totals: MoneyTotals(subtotal: net, total: net),
      footer: footer.isEmpty ? employer.name : footer,
    ).save();
  }
}
