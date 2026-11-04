import '../properties/wml_properties.dart';
import 'wml_document.dart';
import 'wml_run_edit.dart';
import 'word_link.dart';
import 'word_mail_merge.dart';

/// Live Word field kinds we evaluate on layout / update.
enum WmlFieldKind {
  page,
  numPages,
  date,
  time,
  ref,
  seq,
  toc,
  citation,
  indexList,
  hyperlink,
  filename,
  filesize,
  author,
  title,
  mergeField,
  unknown,
}

/// Resolves and refreshes Word fields stored on [WmlParagraphProps].
abstract final class WordFields {
  /// kindOf API.
  static WmlFieldKind kindOf(String? instruction) {
    if (instruction == null || instruction.trim().isEmpty) {
      return WmlFieldKind.unknown;
    }
    final String upper = instruction.toUpperCase();
    if (RegExp(r'(^|[^A-Z])NUMPAGES([^A-Z]|$)').hasMatch(upper)) {
      return WmlFieldKind.numPages;
    }
    if (RegExp(r'(^|[^A-Z])PAGE([^A-Z]|$)').hasMatch(upper)) {
      return WmlFieldKind.page;
    }
    if (RegExp(r'(^|[^A-Z])DATE([^A-Z]|$)').hasMatch(upper)) {
      return WmlFieldKind.date;
    }
    if (RegExp(r'(^|[^A-Z])TIME([^A-Z]|$)').hasMatch(upper)) {
      return WmlFieldKind.time;
    }
    if (RegExp(r'(^|[^A-Z])HYPERLINK\b').hasMatch(upper)) {
      return WmlFieldKind.hyperlink;
    }
    if (RegExp(r'(^|[^A-Z])MERGEFIELD\b').hasMatch(upper)) {
      return WmlFieldKind.mergeField;
    }
    if (RegExp(r'(^|[^A-Z])FILENAME([^A-Z]|$)').hasMatch(upper)) {
      return WmlFieldKind.filename;
    }
    if (RegExp(r'(^|[^A-Z])FILESIZE([^A-Z]|$)').hasMatch(upper)) {
      return WmlFieldKind.filesize;
    }
    if (RegExp(r'(^|[^A-Z])AUTHOR([^A-Z]|$)').hasMatch(upper)) {
      return WmlFieldKind.author;
    }
    if (RegExp(r'(^|[^A-Z])TITLE([^A-Z]|$)').hasMatch(upper)) {
      return WmlFieldKind.title;
    }
    if (RegExp(r'(^|[^A-Z])REF\s').hasMatch(upper) ||
        upper.trimLeft().startsWith('REF')) {
      return WmlFieldKind.ref;
    }
    if (RegExp(r'(^|[^A-Z])SEQ\s').hasMatch(upper) ||
        upper.trimLeft().startsWith('SEQ')) {
      return WmlFieldKind.seq;
    }
    if (RegExp(r'(^|[^A-Z])TOC([^A-Z]|$)').hasMatch(upper)) {
      return WmlFieldKind.toc;
    }
    if (RegExp(r'(^|[^A-Z])CITATION([^A-Z]|$)').hasMatch(upper)) {
      return WmlFieldKind.citation;
    }
    if (RegExp(r'(^|[^A-Z])INDEX([^A-Z]|$)').hasMatch(upper)) {
      return WmlFieldKind.indexList;
    }
    return WmlFieldKind.unknown;
  }

  /// instructionOf API.
  static String instructionOf(WmlFieldKind kind, {String argument = ''}) {
    return switch (kind) {
      WmlFieldKind.page => ' PAGE ',
      WmlFieldKind.numPages => ' NUMPAGES ',
      WmlFieldKind.date => ' DATE \\@ "yyyy-MM-dd" ',
      WmlFieldKind.time => ' TIME \\@ "HH:mm" ',
      WmlFieldKind.ref => ' REF ${argument.trim()} ',
      WmlFieldKind.seq =>
        ' SEQ ${argument.trim().isEmpty ? 'Figure' : argument} ',
      WmlFieldKind.toc => ' TOC \\o "1-3" \\h \\z \\u ',
      WmlFieldKind.citation => ' CITATION ${argument.trim()} ',
      WmlFieldKind.indexList => ' INDEX \\e "\\t" \\c "1" ',
      WmlFieldKind.hyperlink => _hyperlinkInstruction(argument),
      WmlFieldKind.filename => ' FILENAME ',
      WmlFieldKind.filesize => ' FILESIZE ',
      WmlFieldKind.author => ' AUTHOR ',
      WmlFieldKind.title => ' TITLE ',
      WmlFieldKind.mergeField =>
        ' MERGEFIELD ${argument.trim().isEmpty ? 'Field' : argument.trim()} ',
      WmlFieldKind.unknown => argument,
    };
  }

  static String _hyperlinkInstruction(String argument) {
    final String trimmed = argument.trim();
    if (trimmed.isEmpty) {
      return ' HYPERLINK "" ';
    }
    if (trimmed.contains('"')) {
      return ' HYPERLINK $trimmed ';
    }
    return ' HYPERLINK "$trimmed" ';
  }

  /// argumentOf API.
  static String argumentOf(String? instruction) {
    if (instruction == null) {
      return '';
    }
    final Match? merge = RegExp(
      r'MERGEFIELD\s+([A-Za-z0-9_]+)',
      caseSensitive: false,
    ).firstMatch(instruction);
    if (merge != null) {
      return merge.group(1) ?? '';
    }
    final Match? href = RegExp(
      r'HYPERLINK\s+"([^"]*)"',
      caseSensitive: false,
    ).firstMatch(instruction);
    if (href != null) {
      return href.group(1) ?? '';
    }
    final Match? match = RegExp(
      r'(?:REF|SEQ|CITATION)\s+([^\s\\]+)',
      caseSensitive: false,
    ).firstMatch(instruction);
    return match?.group(1) ?? '';
  }

  /// Optional display text from `HYPERLINK "url" "display"`.
  static String hyperlinkDisplayOf(String? instruction) {
    if (instruction == null) {
      return '';
    }
    final Match? match = RegExp(
      r'HYPERLINK\s+"[^"]*"\s+"([^"]*)"',
      caseSensitive: false,
    ).firstMatch(instruction);
    return match?.group(1) ?? '';
  }

  /// evaluate API.
  static String evaluate(
    WmlFieldKind kind, {
    required WmlDocument document,
    int pageNumber = 1,
    int pageCount = 1,
    String? instruction,
    DateTime? now,
    int seqIndex = 1,
  }) {
    final DateTime clock = now ?? DateTime.now();
    return switch (kind) {
      WmlFieldKind.page => '$pageNumber',
      WmlFieldKind.numPages => '$pageCount',
      WmlFieldKind.date =>
        '${clock.year.toString().padLeft(4, '0')}-'
            '${clock.month.toString().padLeft(2, '0')}-'
            '${clock.day.toString().padLeft(2, '0')}',
      WmlFieldKind.time =>
        '${clock.hour.toString().padLeft(2, '0')}:'
            '${clock.minute.toString().padLeft(2, '0')}',
      WmlFieldKind.ref => _refText(document, argumentOf(instruction)),
      WmlFieldKind.seq => '$seqIndex',
      WmlFieldKind.toc => '',
      WmlFieldKind.citation => _citationText(document, argumentOf(instruction)),
      WmlFieldKind.indexList => _indexText(document),
      WmlFieldKind.hyperlink => _hyperlinkText(instruction),
      WmlFieldKind.filename => _filename(document),
      WmlFieldKind.filesize => _filesize(document),
      WmlFieldKind.author => document.properties.creator,
      WmlFieldKind.title => document.properties.title,
      WmlFieldKind.mergeField => WordMailMerge.valueFor(
        document,
        argumentOf(instruction),
      ),
      WmlFieldKind.unknown => '',
    };
  }

  static String _hyperlinkText(String? instruction) {
    final String display = hyperlinkDisplayOf(instruction);
    if (display.isNotEmpty) {
      return display;
    }
    final String url = argumentOf(instruction);
    return url.isEmpty ? '' : url;
  }

  static String _filename(WmlDocument document) {
    final String name = document.sourceFileName.trim();
    if (name.isNotEmpty) {
      return name;
    }
    final String title = document.properties.title.trim();
    return title.isEmpty ? 'Document' : title;
  }

  static String _filesize(WmlDocument document) {
    final int? bytes = document.sourceByteLength;
    if (bytes == null || bytes < 0) {
      return '';
    }
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String _citationText(WmlDocument document, String tag) {
    for (final WmlCitation item in document.citations) {
      if (item.tag == tag) {
        return item.inText;
      }
    }
    return tag.isEmpty ? '' : '($tag)';
  }

  static String _indexText(WmlDocument document) {
    final Map<String, Set<int>> pages = <String, Set<int>>{};
    for (final WmlIndexMark mark in document.indexMarks) {
      pages.putIfAbsent(mark.term, () => <int>{}).add(mark.paragraphIndex + 1);
    }
    final List<String> keys = pages.keys.toList()..sort();
    return <String>[
      'Index',
      for (final String key in keys)
        '$key\t${(pages[key]!.toList()..sort()).join(', ')}',
    ].join('\n');
  }

  static String _refText(WmlDocument document, String bookmark) {
    if (bookmark.isEmpty) {
      return '';
    }
    final int? index = WordLink.paragraphIndexForAnchor(document, bookmark);
    if (index == null || index < 0) {
      return bookmark;
    }
    final List<WmlParagraph> paras = document.paragraphs.toList();
    if (index >= paras.length) {
      return bookmark;
    }
    return paras[index].text.trim();
  }

  /// Marks [paragraph] as a live field and writes the current result.
  static void stamp(
    WmlParagraph paragraph,
    WmlFieldKind kind, {
    String argument = '',
    String result = '',
    String? instruction,
  }) {
    final String instr =
        instruction ?? instructionOf(kind, argument: argument);
    paragraph.properties
      ..fieldInstruction = instr
      ..fieldBegin = true
      ..fieldEnd = true
      ..pageNumberField = kind == WmlFieldKind.page;
    if (kind == WmlFieldKind.hyperlink) {
      final String url = argumentOf(instr);
      if (url.isNotEmpty) {
        _stampHyperlink(paragraph, url, result.isEmpty ? url : result);
        return;
      }
    }
    if (result.isEmpty) {
      return;
    }
    if (paragraph.inlines.isEmpty) {
      paragraph.inlines.add(WmlRun(text: result));
      return;
    }
    WmlRunEdit.replaceRange(paragraph, 0, paragraph.text.length, result);
  }

  static void _stampHyperlink(WmlParagraph paragraph, String url, String text) {
    final WmlHyperlink link = WmlHyperlink(url: url);
    if (paragraph.inlines.isEmpty) {
      paragraph.inlines.add(WordLink.linkedRun(text, link));
      return;
    }
    WmlRunEdit.replaceRange(paragraph, 0, paragraph.text.length, text);
    for (final WmlInline inline in paragraph.inlines) {
      if (inline is WmlRun) {
        inline.hyperlink = link;
        WordLink.applyLook(inline);
      }
    }
  }

  /// Refreshes every field in [document] (body, headers, footers).
  static void update(
    WmlDocument document, {
    int pageCount = 1,
    DateTime? now,
  }) {
    final Map<String, int> seq = <String, int>{};
    void walk(Iterable<WmlParagraph> story, {int pageNumber = 1}) {
      for (final WmlParagraph paragraph in story) {
        final WmlFieldKind kind = kindOf(paragraph.properties.fieldInstruction);
        if (kind == WmlFieldKind.unknown &&
            !paragraph.properties.pageNumberField) {
          continue;
        }
        final WmlFieldKind resolved = kind == WmlFieldKind.unknown
            ? WmlFieldKind.page
            : kind;
        var seqIndex = 1;
        if (resolved == WmlFieldKind.seq) {
          final String name = argumentOf(paragraph.properties.fieldInstruction);
          seqIndex = (seq[name] ?? 0) + 1;
          seq[name] = seqIndex;
        }
        final String? instr = paragraph.properties.fieldInstruction;
        String result = evaluate(
          resolved,
          document: document,
          pageNumber: pageNumber,
          pageCount: pageCount,
          instruction: instr,
          now: now,
          seqIndex: seqIndex,
        );
        if (resolved == WmlFieldKind.page) {
          result = pageResultWithSuffix(paragraph.text, result);
        }
        if (result.isNotEmpty || resolved == WmlFieldKind.hyperlink) {
          stamp(
            paragraph,
            resolved,
            argument: argumentOf(instr),
            result: result,
            instruction: instr,
          );
        }
      }
    }

    walk(document.paragraphs);
    for (final WmlSection section in document.sections) {
      walk(section.header);
      walk(section.footer);
      walk(section.firstHeader);
      walk(section.firstFooter);
      walk(section.evenHeader);
      walk(section.evenFooter);
    }
  }

  /// chromeText API.
  static String chromeText(
    WmlParagraph paragraph, {
    required WmlDocument document,
    required int pageNumber,
    required int pageCount,
    DateTime? now,
  }) {
    final WmlFieldKind kind = kindOf(paragraph.properties.fieldInstruction);
    if (kind == WmlFieldKind.unknown && !paragraph.properties.pageNumberField) {
      return paragraph.text;
    }
    final WmlFieldKind resolved = kind == WmlFieldKind.unknown
        ? WmlFieldKind.page
        : kind;
    final String evaluated = evaluate(
      resolved,
      document: document,
      pageNumber: pageNumber,
      pageCount: pageCount,
      instruction: paragraph.properties.fieldInstruction,
      now: now,
    );
    if (resolved == WmlFieldKind.page) {
      return pageResultWithSuffix(paragraph.text, evaluated);
    }
    return evaluated;
  }

  /// Keeps ` | title` after a PAGE field result.
  static String pageResultWithSuffix(String currentText, String page) {
    final Match? suffix = RegExp(
      r'^\d*(\s*\|.*)$',
    ).firstMatch(currentText.trim());
    if (suffix == null) {
      return page;
    }
    return '$page${suffix.group(1)}';
  }
}
