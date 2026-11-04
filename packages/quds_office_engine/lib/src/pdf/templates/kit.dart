/// Shared theme, parties, and page chrome for report templates.
///
/// Chrome uses the current [TextDirection], so start/end follow the page.
library;

import 'dart:typed_data';

import '../../fonts/sfnt_parser.dart';
import '../file/tools/pdf_toolbox.dart';
import '../widgets/pw_box.dart';
import '../widgets/pw_core.dart';
import '../widgets/pw_layout.dart';
import '../widgets/pw_style.dart';
import '../widgets/pw_table.dart';
import '../widgets/pw_text.dart';
import '../widgets/pw_types.dart';

/// Colors and page size. Pass a different [accent] per domain or brand.
class TemplateTheme {
  /// TemplateTheme API.
  const TemplateTheme({
    this.accent = '0F766E',
    this.ink = '1C1917',
    this.muted = '57534E',
    this.wash = 'F0FDFA',
    this.line = '99F6E4',
    this.onAccent = 'F0FDFA',
    this.pageFormat = PdfPageFormat.a4,
    this.margin = const EdgeInsets.fromLTRB(36, 32, 36, 42),
  });

  /// accent API.
  final String accent;

  /// ink API.
  final String ink;

  /// muted API.
  final String muted;

  /// wash API.
  final String wash;

  /// line API.
  final String line;

  /// onAccent API.
  final String onAccent;

  /// pageFormat API.
  final PdfPageFormat pageFormat;

  /// margin API.
  final EdgeInsets margin;

  /// copyWith API.
  TemplateTheme copyWith({
    String? accent,
    String? ink,
    String? muted,
    String? wash,
    String? line,
    String? onAccent,
    PdfPageFormat? pageFormat,
    EdgeInsets? margin,
  }) {
    return TemplateTheme(
      accent: accent ?? this.accent,
      ink: ink ?? this.ink,
      muted: muted ?? this.muted,
      wash: wash ?? this.wash,
      line: line ?? this.line,
      onAccent: onAccent ?? this.onAccent,
      pageFormat: pageFormat ?? this.pageFormat,
      margin: margin ?? this.margin,
    );
  }
}

/// Default palettes. Override any field with [TemplateTheme.copyWith].
abstract final class TemplateThemes {
  /// commerce API.
  static const TemplateTheme commerce = TemplateTheme(
    accent: '0F766E',
    wash: 'F0FDFA',
    line: '99F6E4',
  );

  /// finance API.
  static const TemplateTheme finance = TemplateTheme(
    accent: '1E3A5F',
    wash: 'F8FAFC',
    line: 'CBD5E1',
    onAccent: 'F8FAFC',
  );

  /// people API.
  static const TemplateTheme people = TemplateTheme(
    accent: '8A6A2F',
    wash: 'FBF7EF',
    line: 'E7D7B1',
    onAccent: 'FFFBF3',
  );

  /// operations API.
  static const TemplateTheme operations = TemplateTheme(
    accent: '334155',
    wash: 'F8FAFC',
    line: 'CBD5E1',
    onAccent: 'F8FAFC',
  );

  /// narrative API.
  static const TemplateTheme narrative = TemplateTheme(
    accent: '3730A3',
    wash: 'EEF2FF',
    line: 'C7D2FE',
    onAccent: 'EEF2FF',
  );

  /// data API.
  static const TemplateTheme data = TemplateTheme(
    accent: '217346',
    wash: 'F0FDF4',
    line: 'BBF7D0',
    onAccent: 'F0FDF4',
  );

  /// education API.
  static const TemplateTheme education = TemplateTheme(
    accent: '1D4E89',
    wash: 'E8F1FB',
    line: 'B6D4FE',
    onAccent: 'F8FBFF',
  );

  /// property API.
  static const TemplateTheme property = TemplateTheme(
    accent: '9A3412',
    wash: 'FFF7ED',
    line: 'FED7AA',
    onAccent: 'FFF7ED',
  );

  /// logistics API.
  static const TemplateTheme logistics = TemplateTheme(
    accent: '155E75',
    wash: 'ECFEFF',
    line: 'A5F3FC',
    onAccent: 'ECFEFF',
  );

  /// programs API.
  static const TemplateTheme programs = TemplateTheme(
    accent: '9F1239',
    wash: 'FFF1F2',
    line: 'FECDD3',
    onAccent: 'FFF1F2',
  );
}

/// A named party: seller, buyer, employee, clinic.
class TemplateParty {
  /// TemplateParty API.
  const TemplateParty({required this.name, this.lines = const <String>[]});

  /// name API.
  final String name;

  /// lines API.
  final List<String> lines;
}

/// A heading that is already formatted. The template does not parse money.
class MoneyTotals {
  /// MoneyTotals API.
  const MoneyTotals({required this.subtotal, this.tax, required this.total});

  /// subtotal API.
  final String subtotal;

  /// tax API.
  final String? tax;

  /// total API.
  final String total;
}

/// One signature slot. Empty [name] leaves a line to sign on paper.
class SignSlot {
  /// SignSlot API.
  const SignSlot({required this.role, this.name = ''});

  /// role API.
  final String role;

  /// name API.
  final String name;
}

/// Check state for lists and inspections.
enum CheckMark { open, done, pass, fail, na }

/// One row in a checklist or inspection.
class CheckItem {
  /// CheckItem API.
  const CheckItem({
    required this.label,
    this.mark = CheckMark.open,
    this.note = '',
  });

  /// label API.
  final String label;

  /// mark API.
  final CheckMark mark;

  /// note API.
  final String note;
}

/// Heading plus body. Used by memos and briefings.
class TemplateSection {
  /// TemplateSection API.
  const TemplateSection({required this.heading, required this.body});

  /// heading API.
  final String heading;

  /// body API.
  final String body;
}

/// Writes a multi-page document in [direction].
abstract final class TemplateDocument {
  /// save API.
  static Uint8List save({
    required String title,
    String author = '',
    required TextDirection direction,
    required TemplateTheme theme,
    String footer = '',
    SfntFont? font,
    SfntFont? fontBold,
    PdfPageFormat? pageFormat,
    PageOrientation orientation = PageOrientation.natural,
    required List<Widget> Function(Context context) build,
  }) {
    final Document doc = Document(
      title: title,
      author: author,
      font: font,
      fontBold: fontBold,
    );
    final PdfPageFormat format = pageFormat ?? theme.pageFormat;
    doc.addPage(
      MultiPage(
        pageFormat: format,
        orientation: orientation,
        margin: theme.margin,
        textDirection: direction,
        footer: (Context context) => Footer(
          leading: Text(
            footer,
            style: TextStyle(fontSize: 8, color: theme.muted),
          ),
        ),
        build: build,
      ),
    );
    return doc.save();
  }
}

/// Concatenates already saved template files. Page size and fonts stay.
Uint8List joinTemplateFiles(List<Uint8List> files) {
  if (files.isEmpty) {
    throw ArgumentError('joinTemplateFiles needs at least one file');
  }
  return PdfToolbox.merge(<PdfPageSource>[
    for (final Uint8List bytes in files) PdfPageSource(bytes),
  ]);
}

/// Accent band. [kicker] and [title] are caller strings, not fixed English.
Widget templateBand(TemplateTheme theme, {required String kicker, required String title}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(color: theme.accent),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          kicker,
          style: TextStyle(fontSize: 8, color: theme.onAccent),
        ),
        SizedBox(height: 4),
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: theme.onAccent,
          ),
        ),
      ],
    ),
  );
}

/// Small section heading.
Widget templateSection(TemplateTheme theme, String label) {
  return Text(
    label,
    style: TextStyle(
      fontSize: 8,
      fontWeight: FontWeight.bold,
      color: theme.accent,
    ),
  );
}

/// Two parties. Order is start then end, and flips with direction.
Widget templateParties(
  TemplateTheme theme, {
  required String startLabel,
  required TemplateParty start,
  required String endLabel,
  required TemplateParty end,
}) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Expanded(child: _partyCard(theme, startLabel, start)),
      SizedBox(width: 10),
      Expanded(child: _partyCard(theme, endLabel, end)),
    ],
  );
}

Widget _partyCard(TemplateTheme theme, String label, TemplateParty party) {
  return Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: theme.wash, borderRadius: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(fontSize: 8, color: theme.accent),
        ),
        SizedBox(height: 3),
        Text(
          party.name,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: theme.ink,
          ),
        ),
        for (final String line in party.lines) ...<Widget>[
          SizedBox(height: 2),
          Text(line, style: TextStyle(fontSize: 9, color: theme.muted)),
        ],
      ],
    ),
  );
}

/// Label/value pairs in two columns.
Widget templateFacts(TemplateTheme theme, List<(String, String)> items) {
  final List<Widget> cells = <Widget>[
    for (final (String label, String value) in items)
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(label, style: TextStyle(fontSize: 8, color: theme.muted)),
            SizedBox(height: 1),
            Text(
              value,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: theme.ink,
              ),
            ),
          ],
        ),
      ),
  ];
  return GridView(
    crossAxisCount: 2,
    mainAxisSpacing: 0,
    crossAxisSpacing: 12,
    childAspectRatio: 4.2,
    children: cells,
  );
}

/// Logical column order. The table already reverses columns in RTL.
Widget templateTable(
  TemplateTheme theme, {
  required List<String> headers,
  required List<List<String>> rows,
}) {
  return Table.fromTextArray(
    headers: headers,
    data: rows,
    headerStyle: TextStyle(
      fontSize: 8,
      fontWeight: FontWeight.bold,
      color: theme.onAccent,
    ),
    cellStyle: TextStyle(fontSize: 9, color: theme.ink),
    headerDecoration: theme.accent,
    oddRowDecoration: theme.wash,
    tableBorder: TableBorder.all(color: theme.line, width: 0.4),
    cellPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
  );
}

/// Totals pinned to the end edge.
Widget templateTotals(
  TemplateTheme theme, {
  required List<(String, String)> rows,
  required String totalLabel,
  required String total,
}) {
  return Align(
    alignment: AlignmentDirectional.centerEnd,
    child: Container(
      width: 220,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: theme.line),
        borderRadius: 4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final (String label, String value) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(fontSize: 9, color: theme.muted),
                    ),
                  ),
                  Text(value, style: TextStyle(fontSize: 9, color: theme.ink)),
                ],
              ),
            ),
          Divider(color: theme.line, height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  totalLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: theme.accent,
                  ),
                ),
              ),
              Text(
                total,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: theme.accent,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Optional notes block. Empty [body] returns nothing.
Widget templateNotes(TemplateTheme theme, {required String title, String? body}) {
  if (body == null || body.trim().isEmpty) {
    return const SizedBox.shrink();
  }
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: theme.wash, borderRadius: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(title, style: TextStyle(fontSize: 8, color: theme.accent)),
        SizedBox(height: 4),
        Text(
          body,
          style: TextStyle(fontSize: 10, height: 1.35, color: theme.ink),
        ),
      ],
    ),
  );
}

/// Body paragraphs.
List<Widget> templateParagraphs(TemplateTheme theme, List<String> paragraphs) {
  return <Widget>[
    for (final String paragraph in paragraphs) ...<Widget>[
      Text(
        paragraph,
        style: TextStyle(fontSize: 11, height: 1.4, color: theme.ink),
      ),
      SizedBox(height: 8),
    ],
  ];
}

/// Signature slots along the line. Empty names leave a rule.
Widget templateSigns(TemplateTheme theme, List<SignSlot> slots) {
  if (slots.isEmpty) {
    return const SizedBox.shrink();
  }
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      for (int i = 0; i < slots.length; i++) ...<Widget>[
        if (i > 0) SizedBox(width: 16),
        Expanded(child: _sign(theme, slots[i])),
      ],
    ],
  );
}

Widget _sign(TemplateTheme theme, SignSlot slot) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Text(slot.role, style: TextStyle(fontSize: 8, color: theme.muted)),
      SizedBox(height: 16),
      Container(
        height: 0.6,
        decoration: BoxDecoration(color: theme.line),
      ),
      if (slot.name.isNotEmpty) ...<Widget>[
        SizedBox(height: 4),
        Text(
          slot.name,
          style: TextStyle(fontSize: 10, color: theme.ink),
        ),
      ],
    ],
  );
}

/// Vertical gap used between blocks.
Widget templateGap([double height = 12]) => SizedBox(height: height);
