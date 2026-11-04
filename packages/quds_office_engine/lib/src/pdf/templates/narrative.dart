/// Narrative templates: memo and briefing.
library;

import 'dart:typed_data';

import '../../builders/office_markup.dart';
import '../../fonts/sfnt_parser.dart';
import '../widgets/pw_types.dart';
import 'kit.dart';
import 'sheets.dart';

/// Memo labels.
class MemoLabels {
  /// MemoLabels API.
  const MemoLabels({
    this.document = 'Memo',
    this.to = 'To',
    this.from = 'From',
    this.date = 'Date',
    this.subject = 'Subject',
  });

  /// document API.
  final String document;

  /// to API.
  final String to;

  /// from API.
  final String from;

  /// date API.
  final String date;

  /// subject API.
  final String subject;
}

/// Internal memo. Sections are heading plus body, in the caller's language.
class MemoTemplate {
  /// MemoTemplate API.
  MemoTemplate({
    this.direction = TextDirection.ltr,
    this.theme = TemplateThemes.narrative,
    this.font,
    this.fontBold,
    required this.from,
    required this.to,
    required this.subject,
    this.sections = const <TemplateSection>[],
    this.labels = const MemoLabels(),
    this.date = '',
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

  /// from API.
  final TemplateParty from;

  /// to API.
  final TemplateParty to;

  /// subject API.
  final String subject;

  /// sections API.
  final List<TemplateSection> sections;

  /// labels API.
  final MemoLabels labels;

  /// date API.
  final String date;

  /// footer API.
  final String footer;

  /// save API.
  Uint8List save() {
    return SheetTemplate(
      kind: SheetKind.brief,
      skin: SheetSkin.notice,
      direction: direction,
      theme: theme,
      font: font,
      fontBold: fontBold,
      owner: from,
      other: to,
      labels: SheetLabels(
        document: labels.document,
        from: labels.from,
        to: labels.to,
        date: labels.date,
      ),
      date: date,
      subject: subject,
      sections: sections,
      footer: footer.isEmpty ? from.name : footer,
    ).save();
  }
}

/// One metric on a briefing.
class BriefMetric {
  /// BriefMetric API.
  const BriefMetric({required this.label, required this.value, this.hint = ''});

  /// label API.
  final String label;

  /// value API.
  final String value;

  /// hint API.
  final String hint;
}

/// Briefing labels.
class BriefingLabels {
  /// BriefingLabels API.
  const BriefingLabels({
    this.document = 'Briefing',
    this.next = 'Next',
  });

  /// document API.
  final String document;

  /// next API.
  final String next;
}

/// Status briefing: summary, optional metrics, optional chart, next steps.
class BriefingTemplate {
  /// BriefingTemplate API.
  BriefingTemplate({
    this.direction = TextDirection.ltr,
    this.theme = TemplateThemes.narrative,
    this.font,
    this.fontBold,
    required this.author,
    required this.title,
    this.summary = '',
    this.metrics = const <BriefMetric>[],
    this.chart,
    this.next = const <String>[],
    this.labels = const BriefingLabels(),
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

  /// author API.
  final TemplateParty author;

  /// title API.
  final String title;

  /// summary API.
  final String summary;

  /// metrics API.
  final List<BriefMetric> metrics;

  /// chart API. Null omits the chart.
  final List<ChartPoint>? chart;

  /// next API.
  final List<String> next;

  /// labels API.
  final BriefingLabels labels;

  /// footer API.
  final String footer;

  /// save API.
  Uint8List save() {
    final List<ChartPoint>? points = chart;
    return SheetTemplate(
      kind: SheetKind.score,
      skin: SheetSkin.tiles,
      direction: direction,
      theme: theme,
      font: font,
      fontBold: fontBold,
      owner: author,
      labels: SheetLabels(document: labels.document, notes: labels.next),
      subject: title,
      paragraphs: summary.isEmpty ? const <String>[] : <String>[summary],
      metrics: <(String, String)>[
        for (final BriefMetric metric in metrics)
          (metric.label, metric.hint.isEmpty ? metric.value : '${metric.value}  ${metric.hint}'),
      ],
      chart: points,
      sections: <TemplateSection>[
        if (next.isNotEmpty) TemplateSection(heading: labels.next, body: next.join('\n')),
      ],
      footer: footer.isEmpty ? author.name : footer,
    ).save();
  }
}
