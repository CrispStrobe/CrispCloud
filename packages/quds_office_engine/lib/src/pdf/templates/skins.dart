part of 'sheets.dart';

/// Paints [sheet] with its [SheetSkin]. Words stay on the sheet; the skin
/// chooses the composition.
List<Widget> paintSheetSkin(SheetTemplate sheet) {
  return switch (sheet.skin) {
    SheetSkin.invoice => _invoice(sheet),
    SheetSkin.quote => _quote(sheet),
    SheetSkin.receipt => _receipt(sheet),
    SheetSkin.letter => _letterSkin(sheet),
    SheetSkin.certificate => _certificate(sheet),
    SheetSkin.statement => _statement(sheet),
    SheetSkin.split => _split(sheet),
    SheetSkin.tiles => _tiles(sheet),
    SheetSkin.timeline => _timeline(sheet),
    SheetSkin.checks => _checks(sheet),
    SheetSkin.route => _route(sheet),
    SheetSkin.masthead => _masthead(sheet),
    SheetSkin.grades => _grades(sheet),
    SheetSkin.identity => _identity(sheet),
    SheetSkin.notice => _notice(sheet),
    SheetSkin.voucher => _voucher(sheet),
    SheetSkin.catalog => _catalog(sheet),
    SheetSkin.comparison => _comparison(sheet),
    SheetSkin.journal => _journal(sheet),
  };
}

String _title(SheetTemplate sheet) =>
    sheet.subject.isEmpty ? sheet.labels.document : sheet.subject;

String _cell(SheetRow row, int index) =>
    index < row.cells.length ? row.cells[index] : '';

bool _done(String mark) {
  switch (mark.trim().toLowerCase()) {
    case 'done':
    case 'pass':
    case 'present':
    case 'yes':
    case 'paid':
    case 'تم':
    case 'نجاح':
    case 'حاضر':
    case 'صُرف':
      return true;
    default:
      return false;
  }
}

Widget _ink(String text, {double size = 10, bool bold = false, String? color, TextAlign align = TextAlign.start}) {
  return Text(
    text,
    textAlign: align,
    style: TextStyle(
      fontSize: size,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      color: color,
    ),
  );
}

List<Widget> _invoice(SheetTemplate sheet) {
  final TemplateTheme theme = sheet.theme;
  final TemplateParty? end = sheet.other;
  final MoneyTotals? money = sheet.totals;
  return <Widget>[
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(width: 6, height: 46, color: theme.accent),
        SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _ink(sheet.labels.document, size: 9, bold: true, color: theme.accent),
              SizedBox(height: 2),
              _ink(_title(sheet), size: 20, bold: true, color: theme.ink),
              SizedBox(height: 2),
              _ink(sheet.owner.name, size: 9, color: theme.muted),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _meta(theme, sheet.labels.number, sheet.number),
            _meta(theme, sheet.labels.date, sheet.date),
            _meta(theme, sheet.labels.extra, sheet.extra),
          ],
        ),
      ],
    ),
    SizedBox(height: 12),
    if (end != null)
      templateParties(
        theme,
        startLabel: sheet.labels.from,
        start: sheet.owner,
        endLabel: sheet.labels.to,
        end: end,
      ),
    SizedBox(height: 12),
    templateTable(
      theme,
      headers: sheet.labels.columns,
      rows: <List<String>>[
        for (final SheetRow row in sheet.rows) row.cells,
      ],
    ),
    if (money != null) ...<Widget>[
      SizedBox(height: 10),
      Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Container(
          width: 200,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          decoration: BoxDecoration(color: theme.accent),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _moneyLine(theme.onAccent, sheet.labels.subtotal, money.subtotal),
              if (money.tax != null)
                _moneyLine(theme.onAccent, sheet.labels.tax, money.tax!),
              SizedBox(height: 4),
              _moneyLine(theme.onAccent, sheet.labels.total, money.total, strong: true),
            ],
          ),
        ),
      ),
    ],
    SizedBox(height: 12),
    templateNotes(theme, title: sheet.labels.notes, body: sheet.notes),
    ..._signs(sheet),
  ];
}

List<Widget> _quote(SheetTemplate sheet) {
  final TemplateTheme theme = sheet.theme;
  final TemplateParty? end = sheet.other;
  final MoneyTotals? money = sheet.totals;
  return <Widget>[
    _ink(sheet.owner.name, size: 9, color: theme.accent, align: TextAlign.center),
    Divider(color: theme.accent, thickness: 2, height: 8),
    _ink(_title(sheet), size: 22, bold: true, color: theme.ink, align: TextAlign.center),
    SizedBox(height: 6),
    Row(
      children: <Widget>[
        Expanded(child: _chip(theme, sheet.labels.number, sheet.number)),
        SizedBox(width: 8),
        Expanded(child: _chip(theme, sheet.labels.date, sheet.date)),
        SizedBox(width: 8),
        Expanded(child: _chip(theme, sheet.labels.extra, sheet.extra)),
      ],
    ),
    SizedBox(height: 12),
    if (end != null)
      templateParties(
        theme,
        startLabel: sheet.labels.from,
        start: sheet.owner,
        endLabel: sheet.labels.to,
        end: end,
      ),
    SizedBox(height: 10),
    templateTable(
      theme,
      headers: sheet.labels.columns,
      rows: <List<String>>[
        for (final SheetRow row in sheet.rows) row.cells,
      ],
    ),
    if (money != null) ...<Widget>[
      SizedBox(height: 8),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(border: Border.all(color: theme.accent, width: 1.2)),
        child: Row(
          children: <Widget>[
            Expanded(child: _ink(sheet.labels.total, size: 11, color: theme.ink)),
            _ink(money.total, size: 16, bold: true, color: theme.accent),
          ],
        ),
      ),
    ],
    SizedBox(height: 10),
    templateNotes(theme, title: sheet.labels.notes, body: sheet.notes),
    ..._signs(sheet),
  ];
}

Widget _meta(TemplateTheme theme, String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Text(
      '$label  $value',
      textAlign: TextAlign.end,
      softWrap: false,
      style: TextStyle(fontSize: 8, color: theme.muted),
    ),
  );
}

Widget _moneyLine(String color, String label, String value, {bool strong = false}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Row(
      children: <Widget>[
        Expanded(child: _ink(label, size: strong ? 11 : 8, bold: strong, color: color)),
        SizedBox(width: 8),
        Text(
          value,
          softWrap: false,
          style: TextStyle(
            fontSize: strong ? 13 : 9,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    ),
  );
}

List<Widget> _receipt(SheetTemplate sheet) {
  final TemplateTheme theme = sheet.theme;
  final String amount = sheet.totals?.total ??
      (sheet.rows.isEmpty ? '' : _cell(sheet.rows.last, sheet.rows.last.cells.length - 1));
  return <Widget>[
    Center(
      child: Container(
        width: 280,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          border: Border.all(color: theme.ink, width: 1.2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _ink(sheet.owner.name, size: 12, bold: true, color: theme.ink, align: TextAlign.center),
            SizedBox(height: 2),
            _ink(sheet.labels.document, size: 8, color: theme.muted, align: TextAlign.center),
            Divider(color: theme.ink, thickness: 0.6, height: 10),
            Divider(color: theme.ink, thickness: 0.4, height: 4),
            SizedBox(height: 6),
            _ink(amount, size: 26, bold: true, color: theme.ink, align: TextAlign.center),
            _ink(sheet.labels.total, size: 8, color: theme.muted, align: TextAlign.center),
            SizedBox(height: 8),
            for (final SheetRow row in sheet.rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  children: <Widget>[
                    Expanded(child: _ink(_cell(row, 0), size: 9, color: theme.ink)),
                    _ink(_cell(row, row.cells.length - 1), size: 9, bold: true, color: theme.ink),
                  ],
                ),
              ),
            Divider(color: theme.line, thickness: 0.4, height: 8),
            _ink('${sheet.labels.number} ${sheet.number}', size: 8, color: theme.muted, align: TextAlign.center),
            _ink('${sheet.labels.date} ${sheet.date}', size: 8, color: theme.muted, align: TextAlign.center),
            if (sheet.notes != null && sheet.notes!.trim().isNotEmpty) ...<Widget>[
              SizedBox(height: 6),
              _ink(sheet.notes!, size: 8, color: theme.muted, align: TextAlign.center),
            ],
          ],
        ),
      ),
    ),
  ];
}

List<Widget> _letterSkin(SheetTemplate sheet) {
  final TemplateTheme theme = sheet.theme;
  final TemplateParty? end = sheet.other;
  return <Widget>[
    _ink(sheet.owner.name, size: 16, bold: true, color: theme.ink),
    for (final String line in sheet.owner.lines)
      _ink(line, size: 8, color: theme.muted),
    Divider(color: theme.accent, thickness: 1.1, height: 8),
    Row(
      children: <Widget>[
        Expanded(child: _ink(sheet.labels.document, size: 8, color: theme.accent)),
        _ink(sheet.date, size: 9, color: theme.ink),
      ],
    ),
    SizedBox(height: 14),
    if (end != null) ...<Widget>[
      _ink(sheet.labels.to, size: 8, color: theme.muted),
      SizedBox(height: 2),
      _ink(end.name, size: 12, bold: true, color: theme.ink),
      for (final String line in end.lines) _ink(line, size: 9, color: theme.muted),
      SizedBox(height: 12),
    ],
    _ink(_title(sheet), size: 13, bold: true, color: theme.ink),
    SizedBox(height: 8),
    ...templateParagraphs(theme, sheet.paragraphs),
    if (sheet.notes != null && sheet.notes!.trim().isNotEmpty) ...<Widget>[
      SizedBox(height: 8),
      _ink(sheet.notes!, size: 10, color: theme.ink),
    ],
    ..._signs(sheet),
  ];
}

List<Widget> _certificate(SheetTemplate sheet) {
  final TemplateTheme theme = sheet.theme;
  return <Widget>[
    Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(border: Border.all(color: theme.accent, width: 2)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(28, 22, 28, 18),
        decoration: BoxDecoration(border: Border.all(color: theme.line, width: 0.6)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _ink(sheet.owner.name, size: 10, color: theme.accent, align: TextAlign.center),
            SizedBox(height: 8),
            _ink(sheet.labels.document, size: 22, bold: true, color: theme.accent, align: TextAlign.center),
            SizedBox(height: 10),
            _ink(sheet.labels.presentedTo, size: 9, color: theme.muted, align: TextAlign.center),
            SizedBox(height: 4),
            _ink(
              sheet.recipient.isEmpty ? _title(sheet) : sheet.recipient,
              size: 24,
              bold: true,
              color: theme.ink,
              align: TextAlign.center,
            ),
            SizedBox(height: 8),
            Container(width: 72, height: 1.2, color: theme.accent),
            SizedBox(height: 8),
            _ink(_title(sheet), size: 12, color: theme.ink, align: TextAlign.center),
            for (final String paragraph in sheet.paragraphs)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _ink(paragraph, size: 10, color: theme.muted, align: TextAlign.center),
              ),
            SizedBox(height: 10),
            _ink('${sheet.labels.date}  ${sheet.date}', size: 9, color: theme.ink, align: TextAlign.center),
            ..._signs(sheet),
          ],
        ),
      ),
    ),
  ];
}

List<Widget> _statement(SheetTemplate sheet) {
  final TemplateTheme theme = sheet.theme;
  final String opening = sheet.rows.isEmpty ? sheet.extra : _cell(sheet.rows.first, 0);
  return <Widget>[
    _ink(sheet.owner.name, size: 11, bold: true, color: theme.accent),
    SizedBox(height: 2),
    _ink(_title(sheet), size: 18, bold: true, color: theme.ink),
    SizedBox(height: 10),
    Row(
      children: <Widget>[
        Expanded(child: _chip(theme, sheet.labels.number, sheet.number)),
        SizedBox(width: 8),
        Expanded(child: _chip(theme, sheet.labels.date, sheet.date)),
        SizedBox(width: 8),
        Expanded(child: _chip(theme, sheet.labels.extra, sheet.extra.isEmpty ? opening : sheet.extra)),
      ],
    ),
    SizedBox(height: 12),
    templateTable(
      theme,
      headers: sheet.labels.columns,
      rows: <List<String>>[
        for (final SheetRow row in sheet.rows) row.cells,
      ],
    ),
    SizedBox(height: 10),
    templateNotes(theme, title: sheet.labels.notes, body: sheet.notes),
  ];
}

Widget _chip(TemplateTheme theme, String label, String value) {
  return Container(
    padding: const EdgeInsets.fromLTRB(8, 6, 8, 7),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: theme.accent, width: 2)),
      color: theme.wash,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _ink(label, size: 7, color: theme.muted),
        SizedBox(height: 2),
        _ink(value, size: 11, bold: true, color: theme.ink),
      ],
    ),
  );
}

List<Widget> _split(SheetTemplate sheet) {
  final TemplateTheme theme = sheet.theme;
  final String net = sheet.totals?.total ?? sheet.extra;
  return <Widget>[
    _ink(sheet.owner.name, size: 10, color: theme.muted),
    _ink(_title(sheet), size: 18, bold: true, color: theme.ink),
    SizedBox(height: 8),
    _ink('${sheet.labels.date}  ${sheet.date}    ${sheet.number}', size: 8, color: theme.muted),
    SizedBox(height: 10),
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: _stack(theme, sheet.labels.from, sheet.metrics.map((item) => (item.$1, item.$2)).toList())),
        SizedBox(width: 10),
        Expanded(
          child: _stack(
            theme,
            sheet.labels.to,
            <(String, String)>[
              for (final SheetRow row in sheet.rows) (_cell(row, 0), _cell(row, row.cells.length - 1)),
            ],
          ),
        ),
      ],
    ),
    SizedBox(height: 12),
    Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: theme.accent,
      child: Row(
        children: <Widget>[
          Expanded(child: _ink(sheet.labels.total, size: 11, bold: true, color: theme.onAccent)),
          _ink(net, size: 16, bold: true, color: theme.onAccent),
        ],
      ),
    ),
  ];
}

Widget _stack(TemplateTheme theme, String title, List<(String, String)> lines) {
  return Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(border: Border.all(color: theme.line)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _ink(title, size: 8, bold: true, color: theme.accent),
        SizedBox(height: 6),
        for (final (String label, String value) in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              children: <Widget>[
                Expanded(child: _ink(label, size: 9, color: theme.ink)),
                _ink(value, size: 9, bold: true, color: theme.ink),
              ],
            ),
          ),
      ],
    ),
  );
}

List<Widget> _tiles(SheetTemplate sheet) {
  final TemplateTheme theme = sheet.theme;
  final List<ChartPoint>? points = sheet.chart;
  final List<(String, String)> metrics = sheet.metrics.isNotEmpty
      ? sheet.metrics
      : <(String, String)>[
          for (final SheetRow row in sheet.rows) (_cell(row, 0), _cell(row, 1)),
        ];
  return <Widget>[
    _ink(sheet.labels.document, size: 8, bold: true, color: theme.accent),
    SizedBox(height: 2),
    _ink(_title(sheet), size: 22, bold: true, color: theme.ink),
    SizedBox(height: 4),
    _ink('${sheet.owner.name}  ·  ${sheet.date}', size: 8, color: theme.muted),
    SizedBox(height: 12),
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int i = 0; i < metrics.length && i < 3; i++) ...<Widget>[
          if (i > 0) SizedBox(width: 8),
          Expanded(child: _tile(theme, metrics[i].$1, metrics[i].$2)),
        ],
      ],
    ),
    for (final String paragraph in sheet.paragraphs)
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: _ink(paragraph, size: 10, color: theme.ink),
      ),
    if (points != null && points.isNotEmpty) ...<Widget>[
      SizedBox(height: 12),
      Chart(
        type: ChartType.bar,
        title: sheet.chartTitle,
        points: points,
        width: 420,
        height: 140,
      ),
    ],
    for (final TemplateSection section in sheet.sections) ...<Widget>[
      SizedBox(height: 8),
      _ink(section.heading, size: 8, bold: true, color: theme.accent),
      SizedBox(height: 2),
      _ink(section.body, size: 10, color: theme.ink),
    ],
    SizedBox(height: 10),
    templateNotes(theme, title: sheet.labels.notes, body: sheet.notes),
  ];
}

Widget _tile(TemplateTheme theme, String label, String value) {
  return Container(
    padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
    decoration: BoxDecoration(color: theme.wash, borderRadius: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _ink(value, size: 18, bold: true, color: theme.accent),
        SizedBox(height: 2),
        _ink(label, size: 8, color: theme.muted),
      ],
    ),
  );
}

List<Widget> _timeline(SheetTemplate sheet) {
  final TemplateTheme theme = sheet.theme;
  return <Widget>[
    _ink(_title(sheet), size: 18, bold: true, color: theme.ink),
    SizedBox(height: 2),
    _ink('${sheet.owner.name}  ·  ${sheet.date}  ·  ${sheet.extra}', size: 8, color: theme.muted),
    SizedBox(height: 12),
    for (final SheetRow row in sheet.rows)
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 64,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              color: theme.accent,
              child: _ink(_cell(row, 0), size: 8, bold: true, color: theme.onAccent),
            ),
            SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: theme.line, width: 0.6)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _ink(_cell(row, 1), size: 11, bold: true, color: theme.ink),
                    if (row.cells.length > 2)
                      _ink(_cell(row, 2), size: 8, color: theme.muted),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    templateNotes(theme, title: sheet.labels.notes, body: sheet.notes),
  ];
}

List<Widget> _checks(SheetTemplate sheet) {
  final TemplateTheme theme = sheet.theme;
  final List<SheetRow> items = sheet.rows
      .where((SheetRow row) => _cell(row, 1).trim().isNotEmpty)
      .toList();
  final int done = items.where((SheetRow row) => _done(_cell(row, 1))).length;
  return <Widget>[
    Row(
      children: <Widget>[
        Expanded(child: _ink(_title(sheet), size: 18, bold: true, color: theme.ink)),
        Directionality(
          textDirection: TextDirection.ltr,
          child: _ink('done $done of ${items.length}', size: 11, bold: true, color: theme.accent),
        ),
      ],
    ),
    SizedBox(height: 2),
    _ink(
      '${sheet.owner.name}  ·  ${sheet.number}${sheet.extra.isEmpty ? '' : '  ·  ${sheet.extra}'}',
      size: 8,
      color: theme.muted,
    ),
    SizedBox(height: 10),
    for (final SheetRow row in sheet.rows)
      if (_cell(row, 1).trim().isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 3),
          child: _ink(_cell(row, 0), size: 8, bold: true, color: theme.accent),
        )
      else
      Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 11,
              height: 11,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(
                color: _done(_cell(row, 1)) ? theme.accent : null,
                border: Border.all(color: theme.accent, width: 1),
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _ink(_cell(row, 0), size: 10, bold: true, color: theme.ink),
                  if (_cell(row, 2).isNotEmpty)
                    _ink(_cell(row, 2), size: 8, color: theme.muted),
                ],
              ),
            ),
            _ink(_cell(row, 1), size: 8, color: theme.accent),
          ],
        ),
      ),
    templateNotes(theme, title: sheet.labels.notes, body: sheet.notes),
    ..._signs(sheet),
  ];
}

List<Widget> _route(SheetTemplate sheet) {
  final TemplateTheme theme = sheet.theme;
  final TemplateParty end = sheet.other ?? const TemplateParty(name: '');
  return <Widget>[
    _ink(sheet.labels.document, size: 8, bold: true, color: theme.accent),
    SizedBox(height: 4),
    _ink(sheet.number, size: 20, bold: true, color: theme.ink),
    SizedBox(height: 8),
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: _endpoint(theme, '1', sheet.labels.from, sheet.owner.name, filled: true)),
        SizedBox(width: 8),
        Expanded(child: _endpoint(theme, '2', sheet.labels.to, end.name, filled: false)),
      ],
    ),
    SizedBox(height: 8),
    _ink('${sheet.labels.date}  ${sheet.date}    ${sheet.labels.extra}  ${sheet.extra}', size: 8, color: theme.muted),
    SizedBox(height: 10),
    for (final SheetRow row in sheet.rows)
      Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(border: Border.all(color: theme.line)),
        child: Row(
          children: <Widget>[
            Expanded(child: _ink(_cell(row, 0), size: 10, bold: true, color: theme.ink)),
            _ink(row.cells.length > 1 ? row.cells.sublist(1).join('  ·  ') : '', size: 8, color: theme.muted),
          ],
        ),
      ),
    templateNotes(theme, title: sheet.labels.notes, body: sheet.notes),
  ];
}

Widget _endpoint(
  TemplateTheme theme,
  String index,
  String label,
  String name, {
  required bool filled,
}) {
  return Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: filled ? theme.accent : theme.wash,
      borderRadius: 4,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _ink(label, size: 7, color: filled ? theme.onAccent : theme.muted),
        SizedBox(height: 3),
        _ink(name, size: 12, bold: true, color: filled ? theme.onAccent : theme.ink),
        SizedBox(height: 4),
        _ink(index, size: 8, bold: true, color: filled ? theme.onAccent : theme.accent),
      ],
    ),
  );
}

List<Widget> _masthead(SheetTemplate sheet) {
  final TemplateTheme theme = sheet.theme;
  return <Widget>[
    _ink(sheet.owner.name, size: 9, color: theme.accent, align: TextAlign.center),
    Divider(color: theme.ink, thickness: 1.4, height: 6),
    Divider(color: theme.ink, thickness: 0.4, height: 3),
    SizedBox(height: 8),
    _ink(_title(sheet), size: 22, bold: true, color: theme.ink, align: TextAlign.center),
    SizedBox(height: 4),
    _ink('${sheet.labels.document}  ·  ${sheet.date}', size: 8, color: theme.muted, align: TextAlign.center),
    SizedBox(height: 12),
    for (final String paragraph in sheet.paragraphs)
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _ink(paragraph, size: 11, color: theme.ink),
      ),
    for (final TemplateSection section in sheet.sections)
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(width: 3, height: 36, color: theme.accent),
          SizedBox(width: 8),
          Expanded(
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _ink(section.heading, size: 8, bold: true, color: theme.accent),
            SizedBox(height: 2),
            _ink(section.body, size: 10, color: theme.ink),
          ],
        ),
          ),
        ],
      ),
    templateNotes(theme, title: sheet.labels.notes, body: sheet.notes),
  ];
}

List<Widget> _grades(SheetTemplate sheet) {
  final TemplateTheme theme = sheet.theme;
  final TemplateParty? student = sheet.other;
  return <Widget>[
    _ink(sheet.owner.name, size: 9, color: theme.accent),
    SizedBox(height: 2),
    _ink(student?.name ?? _title(sheet), size: 20, bold: true, color: theme.ink),
    SizedBox(height: 2),
    _ink('${sheet.labels.document}  ·  ${sheet.extra}', size: 8, color: theme.muted),
    SizedBox(height: 12),
    for (final SheetRow row in sheet.rows)
      Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.line, width: 0.5)),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 48,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(color: theme.wash, borderRadius: 8),
              child: _ink(_cell(row, 1), size: 12, bold: true, color: theme.accent, align: TextAlign.center),
            ),
            SizedBox(width: 8),
            Expanded(child: _ink(_cell(row, 0), size: 11, color: theme.ink)),
            if (row.cells.length > 2)
              SizedBox(
                width: 72,
                child: _ink(_cell(row, 2), size: 8, color: theme.muted, align: TextAlign.end),
              ),
          ],
        ),
      ),
    templateNotes(theme, title: sheet.labels.notes, body: sheet.notes),
  ];
}

List<Widget> _identity(SheetTemplate sheet) {
  final TemplateTheme theme = sheet.theme;
  return <Widget>[
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 150,
          padding: const EdgeInsets.all(12),
          color: theme.accent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _ink(sheet.owner.name, size: 14, bold: true, color: theme.onAccent),
              SizedBox(height: 4),
              _ink(sheet.extra, size: 8, color: theme.onAccent),
              SizedBox(height: 8),
              _ink(sheet.labels.document, size: 8, color: theme.onAccent),
            ],
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _ink(_title(sheet), size: 14, bold: true, color: theme.ink),
              SizedBox(height: 6),
              for (final (String label, String value) in sheet.metrics)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    children: <Widget>[
                      SizedBox(width: 72, child: _ink(label, size: 8, color: theme.muted)),
                      _ink(value, size: 10, bold: true, color: theme.ink),
                    ],
                  ),
                ),
              for (final String paragraph in sheet.paragraphs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _ink(paragraph, size: 10, color: theme.ink),
                ),
            ],
          ),
        ),
      ],
    ),
    ..._signs(sheet),
  ];
}

List<Widget> _notice(SheetTemplate sheet) {
  final TemplateTheme theme = sheet.theme;
  return <Widget>[
    Container(width: double.infinity, height: 8, color: theme.accent),
    SizedBox(height: 12),
    _ink(sheet.labels.document, size: 9, bold: true, color: theme.accent),
    SizedBox(height: 4),
    _ink(_title(sheet), size: 20, bold: true, color: theme.ink),
    SizedBox(height: 4),
    _ink('${sheet.owner.name}  ·  ${sheet.date}  ·  ${sheet.number}', size: 8, color: theme.muted),
    SizedBox(height: 10),
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(width: 4, color: theme.accent),
        SizedBox(width: 10),
        Expanded(
          child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: theme.wash,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final String paragraph in sheet.paragraphs)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _ink(paragraph, size: 11, color: theme.ink),
            ),
          for (final TemplateSection section in sheet.sections) ...<Widget>[
            _ink(section.heading, size: 8, bold: true, color: theme.accent),
            SizedBox(height: 2),
            _ink(section.body, size: 10, color: theme.ink),
            SizedBox(height: 6),
          ],
        ],
      ),
          ),
        ),
      ],
    ),
    if (sheet.notes != null) ...<Widget>[
      SizedBox(height: 8),
      _ink(sheet.notes!, size: 9, color: theme.muted),
    ],
    ..._signs(sheet),
  ];
}

List<Widget> _voucher(SheetTemplate sheet) {
  final TemplateTheme theme = sheet.theme;
  final String payee = sheet.other?.name ?? sheet.recipient;
  final String amount = sheet.totals?.total ??
      (sheet.rows.isEmpty ? sheet.extra : _cell(sheet.rows.first, sheet.rows.first.cells.length - 1));
  return <Widget>[
    Container(
      width: double.infinity,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(border: Border.all(color: theme.accent, width: 1.4)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(border: Border.all(color: theme.line, width: 0.5)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(child: _ink(sheet.owner.name, size: 11, bold: true, color: theme.accent)),
                _ink(sheet.labels.document, size: 9, color: theme.muted),
              ],
            ),
            SizedBox(height: 10),
            _ink(sheet.labels.to, size: 8, color: theme.muted),
            Container(
              margin: const EdgeInsets.only(top: 2, bottom: 8),
              padding: const EdgeInsets.only(bottom: 3),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: theme.ink, width: 0.6)),
              ),
              child: _ink(payee, size: 14, bold: true, color: theme.ink),
            ),
            _ink(
              sheet.rows.length > 1
                  ? (sheet.extra.isEmpty ? '' : sheet.extra)
                  : (sheet.rows.isEmpty ? (sheet.notes ?? '') : _cell(sheet.rows.first, 0)),
              size: 9,
              color: theme.muted,
            ),
            SizedBox(height: 6),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(border: Border.all(color: theme.accent, width: 1.2)),
                child: _ink(amount, size: 16, bold: true, color: theme.accent),
              ),
            ),
            if (sheet.rows.length > 1) ...<Widget>[
              SizedBox(height: 8),
              for (final SheetRow row in sheet.rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    children: <Widget>[
                      Expanded(child: _ink(_cell(row, 0), size: 9, color: theme.ink)),
                      if (row.cells.length > 2)
                        _ink(row.cells.sublist(1, row.cells.length - 1).join(' · '), size: 8, color: theme.muted),
                      SizedBox(width: 8),
                      _ink(_cell(row, row.cells.length - 1), size: 9, bold: true, color: theme.ink),
                    ],
                  ),
                ),
            ],
            SizedBox(height: 8),
            _ink('${sheet.labels.number} ${sheet.number}    ${sheet.labels.date} ${sheet.date}', size: 8, color: theme.muted),
            ..._signs(sheet),
          ],
        ),
      ),
    ),
  ];
}

List<Widget> _catalog(SheetTemplate sheet) {
  final TemplateTheme theme = sheet.theme;
  return <Widget>[
    _ink(_title(sheet), size: 20, bold: true, color: theme.ink),
    SizedBox(height: 2),
    _ink('${sheet.owner.name}  ·  ${sheet.number}', size: 8, color: theme.muted),
    Divider(color: theme.ink, thickness: 0.8, height: 10),
    for (final SheetRow row in sheet.rows)
      Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.line, width: 0.4)),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _ink(_cell(row, 0), size: 11, bold: true, color: theme.ink),
                  if (row.cells.length > 2)
                    _ink(row.cells.sublist(1, row.cells.length - 1).join('  ·  '), size: 8, color: theme.muted),
                ],
              ),
            ),
            _ink(_cell(row, row.cells.length - 1), size: 12, bold: true, color: theme.accent),
          ],
        ),
      ),
    SizedBox(height: 8),
    templateNotes(theme, title: sheet.labels.notes, body: sheet.notes),
  ];
}

List<Widget> _comparison(SheetTemplate sheet) {
  final TemplateTheme theme = sheet.theme;
  final List<String> heads = sheet.labels.columns;
  final String left = heads.length > 1 ? heads[1] : sheet.labels.from;
  final String right = heads.length > 2 ? heads[2] : sheet.labels.to;
  return <Widget>[
    _ink(_title(sheet), size: 18, bold: true, color: theme.ink),
    SizedBox(height: 10),
    Row(
      children: <Widget>[
        Expanded(child: Container(height: 22, color: theme.accent, padding: const EdgeInsets.all(4), child: _ink(left, size: 9, bold: true, color: theme.onAccent))),
        SizedBox(width: 8),
        Expanded(child: Container(height: 22, color: theme.ink, padding: const EdgeInsets.all(4), child: _ink(right, size: 9, bold: true, color: theme.onAccent))),
      ],
    ),
    SizedBox(height: 6),
    for (final SheetRow row in sheet.rows)
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: <Widget>[
            SizedBox(width: 72, child: _ink(_cell(row, 0), size: 8, color: theme.muted)),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(6),
                color: theme.wash,
                child: _ink(_cell(row, 1), size: 10, bold: true, color: theme.ink),
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(border: Border.all(color: theme.line)),
                child: _ink(_cell(row, 2), size: 10, color: theme.ink),
              ),
            ),
          ],
        ),
      ),
  ];
}

List<Widget> _journal(SheetTemplate sheet) {
  final TemplateTheme theme = sheet.theme;
  return <Widget>[
    Row(
      children: <Widget>[
        Container(width: 4, height: 28, color: theme.accent),
        SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _ink(sheet.labels.document, size: 8, color: theme.accent),
              _ink('${sheet.number}  ·  ${sheet.date}', size: 14, bold: true, color: theme.ink),
            ],
          ),
        ),
      ],
    ),
    SizedBox(height: 10),
    Row(
      children: <Widget>[
        Expanded(child: _ink(sheet.labels.columns.length > 2 ? sheet.labels.columns[2] : sheet.labels.from, size: 8, bold: true, color: theme.muted)),
        Expanded(child: _ink(sheet.labels.columns.length > 3 ? sheet.labels.columns[3] : sheet.labels.to, size: 8, bold: true, color: theme.muted, align: TextAlign.end)),
      ],
    ),
    Divider(color: theme.ink, thickness: 0.6, height: 6),
    for (final SheetRow row in sheet.rows)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _ink(_cell(row, 0), size: 9, bold: true, color: theme.ink),
                  _ink(_cell(row, 1), size: 8, color: theme.muted),
                ],
              ),
            ),
            SizedBox(
              width: 70,
              child: _ink(_cell(row, 2), size: 10, bold: true, color: theme.ink, align: TextAlign.end),
            ),
            SizedBox(
              width: 70,
              child: _ink(_cell(row, 3), size: 10, color: theme.ink, align: TextAlign.end),
            ),
          ],
        ),
      ),
    Divider(color: theme.ink, thickness: 0.8, height: 8),
    templateNotes(theme, title: sheet.labels.notes, body: sheet.notes),
  ];
}

List<Widget> _signs(SheetTemplate sheet) {
  if (sheet.signs.isEmpty) {
    return const <Widget>[];
  }
  return <Widget>[
    SizedBox(height: 16),
    templateSigns(sheet.theme, sheet.signs),
  ];
}
