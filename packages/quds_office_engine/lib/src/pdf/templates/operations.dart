/// Operations templates: agenda, minutes, checklist, inspection.
library;

import 'dart:typed_data';

import '../../fonts/sfnt_parser.dart';
import '../widgets/pw_types.dart';
import 'kit.dart';
import 'sheets.dart';

/// One agenda slot.
class AgendaItem {
  /// AgendaItem API.
  const AgendaItem({
    required this.time,
    required this.title,
    this.owner = '',
  });

  /// time API.
  final String time;

  /// title API.
  final String title;

  /// owner API.
  final String owner;
}

/// Agenda labels.
class AgendaLabels {
  /// AgendaLabels API.
  const AgendaLabels({
    this.document = 'Agenda',
    this.when = 'When',
    this.where = 'Where',
    this.time = 'Time',
    this.item = 'Item',
    this.owner = 'Owner',
  });

  /// document API.
  final String document;

  /// when API.
  final String when;

  /// where API.
  final String where;

  /// time API.
  final String time;

  /// item API.
  final String item;

  /// owner API.
  final String owner;
}

/// Timed agenda.
class AgendaTemplate {
  /// AgendaTemplate API.
  AgendaTemplate({
    this.direction = TextDirection.ltr,
    this.theme = TemplateThemes.operations,
    this.font,
    this.fontBold,
    required this.host,
    this.items = const <AgendaItem>[],
    this.labels = const AgendaLabels(),
    this.when = '',
    this.where = '',
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

  /// host API.
  final TemplateParty host;

  /// items API.
  final List<AgendaItem> items;

  /// labels API.
  final AgendaLabels labels;

  /// when API.
  final String when;

  /// where API.
  final String where;

  /// footer API.
  final String footer;

  /// save API.
  Uint8List save() {
    return SheetTemplate(
      kind: SheetKind.listing,
      skin: SheetSkin.timeline,
      direction: direction,
      theme: theme,
      font: font,
      fontBold: fontBold,
      owner: host,
      labels: SheetLabels(
        document: labels.document,
        date: labels.when,
        extra: labels.where,
        columns: <String>[labels.time, labels.item, labels.owner],
      ),
      date: when,
      extra: where,
      rows: <SheetRow>[
        for (final AgendaItem item in items)
          SheetRow(<String>[item.time, item.title, item.owner]),
      ],
      footer: footer.isEmpty ? host.name : footer,
    ).save();
  }
}

/// A decision recorded in minutes.
class Decision {
  /// Decision API.
  const Decision({required this.text});

  /// text API.
  final String text;
}

/// An action with an owner and a due string.
class ActionItem {
  /// ActionItem API.
  const ActionItem({
    required this.task,
    this.owner = '',
    this.due = '',
  });

  /// task API.
  final String task;

  /// owner API.
  final String owner;

  /// due API.
  final String due;
}

/// Minutes labels.
class MinutesLabels {
  /// MinutesLabels API.
  const MinutesLabels({
    this.document = 'Minutes',
    this.when = 'When',
    this.attendees = 'Attendees',
    this.decisions = 'Decisions',
    this.actions = 'Actions',
    this.task = 'Task',
    this.owner = 'Owner',
    this.due = 'Due',
  });

  /// document API.
  final String document;

  /// when API.
  final String when;

  /// attendees API.
  final String attendees;

  /// decisions API.
  final String decisions;

  /// actions API.
  final String actions;

  /// task API.
  final String task;

  /// owner API.
  final String owner;

  /// due API.
  final String due;
}

/// Meeting minutes.
class MinutesTemplate {
  /// MinutesTemplate API.
  MinutesTemplate({
    this.direction = TextDirection.ltr,
    this.theme = TemplateThemes.operations,
    this.font,
    this.fontBold,
    required this.host,
    this.attendees = const <String>[],
    this.decisions = const <Decision>[],
    this.actions = const <ActionItem>[],
    this.labels = const MinutesLabels(),
    this.when = '',
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

  /// host API.
  final TemplateParty host;

  /// attendees API.
  final List<String> attendees;

  /// decisions API.
  final List<Decision> decisions;

  /// actions API.
  final List<ActionItem> actions;

  /// labels API.
  final MinutesLabels labels;

  /// when API.
  final String when;

  /// footer API.
  final String footer;

  /// save API.
  Uint8List save() {
    return SheetTemplate(
      kind: SheetKind.brief,
      skin: SheetSkin.masthead,
      direction: direction,
      theme: theme,
      font: font,
      fontBold: fontBold,
      owner: host,
      labels: SheetLabels(
        document: labels.document,
        date: labels.when,
        notes: labels.actions,
      ),
      date: when,
      paragraphs: <String>[
        if (attendees.isNotEmpty) '${labels.attendees}: ${attendees.join(' · ')}',
      ],
      sections: <TemplateSection>[
        for (final Decision item in decisions)
          TemplateSection(heading: labels.decisions, body: item.text),
        for (final ActionItem item in actions)
          TemplateSection(
            heading: labels.actions,
            body: '${item.task}  ·  ${item.owner}  ·  ${item.due}',
          ),
      ],
      footer: footer.isEmpty ? host.name : footer,
    ).save();
  }
}

/// A named group of checks.
class CheckGroup {
  /// CheckGroup API.
  const CheckGroup({required this.title, this.items = const <CheckItem>[]});

  /// title API.
  final String title;

  /// items API.
  final List<CheckItem> items;
}

/// Checklist labels. [marks] maps each [CheckMark] to the printed word.
class ChecklistLabels {
  /// ChecklistLabels API.
  const ChecklistLabels({
    this.document = 'Checklist',
    this.item = 'Item',
    this.mark = 'Mark',
    this.note = 'Note',
    this.marks = const <CheckMark, String>{
      CheckMark.open: 'Open',
      CheckMark.done: 'Done',
      CheckMark.pass: 'Pass',
      CheckMark.fail: 'Fail',
      CheckMark.na: 'N/A',
    },
  });

  /// document API.
  final String document;

  /// item API.
  final String item;

  /// mark API.
  final String mark;

  /// note API.
  final String note;

  /// marks API.
  final Map<CheckMark, String> marks;

  /// word API.
  String word(CheckMark value) => marks[value] ?? '';
}

/// Grouped checklist.
class ChecklistTemplate {
  /// ChecklistTemplate API.
  ChecklistTemplate({
    this.direction = TextDirection.ltr,
    this.theme = TemplateThemes.operations,
    this.font,
    this.fontBold,
    required this.owner,
    this.groups = const <CheckGroup>[],
    this.labels = const ChecklistLabels(),
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

  /// owner API.
  final TemplateParty owner;

  /// groups API.
  final List<CheckGroup> groups;

  /// labels API.
  final ChecklistLabels labels;

  /// footer API.
  final String footer;

  /// save API.
  Uint8List save() {
    return SheetTemplate(
      kind: SheetKind.check,
      skin: SheetSkin.checks,
      direction: direction,
      theme: theme,
      font: font,
      fontBold: fontBold,
      owner: owner,
      labels: SheetLabels(
        document: labels.document,
        columns: <String>[labels.item, labels.mark, labels.note],
      ),
      rows: <SheetRow>[
        for (final CheckGroup group in groups) ...<SheetRow>[
          if (group.title.isNotEmpty) SheetRow(<String>[group.title, '', '']),
          for (final CheckItem item in group.items)
            SheetRow(<String>[item.label, labels.word(item.mark), item.note]),
        ],
      ],
      footer: footer.isEmpty ? owner.name : footer,
    ).save();
  }
}

/// Inspection labels. Counts are computed from [CheckItem.mark].
class InspectionLabels {
  /// InspectionLabels API.
  const InspectionLabels({
    this.document = 'Inspection',
    this.site = 'Site',
    this.when = 'When',
    this.inspector = 'Inspector',
    this.pass = 'Pass',
    this.fail = 'Fail',
    this.open = 'Open',
    this.item = 'Item',
    this.result = 'Result',
    this.note = 'Note',
    this.marks = const <CheckMark, String>{
      CheckMark.open: 'Open',
      CheckMark.done: 'Done',
      CheckMark.pass: 'Pass',
      CheckMark.fail: 'Fail',
      CheckMark.na: 'N/A',
    },
  });

  /// document API.
  final String document;

  /// site API.
  final String site;

  /// when API.
  final String when;

  /// inspector API.
  final String inspector;

  /// pass API.
  final String pass;

  /// fail API.
  final String fail;

  /// open API.
  final String open;

  /// item API.
  final String item;

  /// result API.
  final String result;

  /// note API.
  final String note;

  /// marks API.
  final Map<CheckMark, String> marks;

  /// word API.
  String word(CheckMark value) => marks[value] ?? '';
}

/// Field inspection. Pass, fail, and open counts are derived from items.
class InspectionTemplate {
  /// InspectionTemplate API.
  InspectionTemplate({
    this.direction = TextDirection.ltr,
    this.theme = TemplateThemes.operations,
    this.font,
    this.fontBold,
    required this.inspector,
    required this.site,
    this.items = const <CheckItem>[],
    this.labels = const InspectionLabels(),
    this.when = '',
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

  /// inspector API.
  final TemplateParty inspector;

  /// site API.
  final String site;

  /// items API.
  final List<CheckItem> items;

  /// labels API.
  final InspectionLabels labels;

  /// when API.
  final String when;

  /// notes API.
  final String? notes;

  /// footer API.
  final String footer;

  /// signs API.
  final List<SignSlot> signs;

  /// save API.
  Uint8List save() {
    final int passed = items.where((CheckItem i) => i.mark == CheckMark.pass).length;
    final int failed = items.where((CheckItem i) => i.mark == CheckMark.fail).length;
    final int open = items.where((CheckItem i) => i.mark == CheckMark.open).length;
    return SheetTemplate(
      kind: SheetKind.check,
      skin: SheetSkin.checks,
      direction: direction,
      theme: theme,
      font: font,
      fontBold: fontBold,
      owner: inspector,
      labels: SheetLabels(
        document: labels.document,
        number: labels.site,
        date: labels.when,
        extra: labels.inspector,
        notes: labels.note,
        columns: <String>[labels.item, labels.result, labels.note],
      ),
      number: site,
      date: when,
      extra: '${labels.pass} $passed  ·  ${labels.fail} $failed  ·  ${labels.open} $open',
      rows: <SheetRow>[
        for (final CheckItem item in items)
          SheetRow(<String>[item.label, labels.word(item.mark), item.note]),
      ],
      notes: notes,
      footer: footer.isEmpty ? inspector.name : footer,
      signs: signs,
    ).save();
  }
}
