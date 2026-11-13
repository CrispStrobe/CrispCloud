import 'dart:convert';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

/// A reading-order projection of the parser's independently validated stories.
/// The original source identities are retained; appending a story does not
/// claim that its content occupied that position on the original page.
class LegacyWordPreviewStory {
  const LegacyWordPreviewStory({
    required this.id,
    required this.kind,
    required this.number,
    required this.startCp,
    required this.endCp,
    this.sectionIndex,
    this.headerFooterType,
  });

  final String id;
  final LegacyWordStoryKind kind;
  final int number;
  final int startCp;
  final int endCp;
  final int? sectionIndex;
  final LegacyWordHeaderFooterType? headerFooterType;
}

class LegacyWordPreviewHeading {
  const LegacyWordPreviewHeading(this.start, this.end, this.story);

  final int start;
  final int end;
  final LegacyWordPreviewStory story;
}

class LegacyWordPreview {
  const LegacyWordPreview({
    required this.plainText,
    required this.safeHtml,
    required this.stories,
    required this.textHeadings,
    required this.htmlHeadings,
  });

  final String plainText;

  /// Null when the combined markup would exceed the existing rich-view cap.
  /// The complete bounded text projection remains available in that case.
  final String? safeHtml;
  final List<LegacyWordPreviewStory> stories;
  final List<LegacyWordPreviewHeading> textHeadings;
  final List<LegacyWordPreviewHeading> htmlHeadings;
}

const legacyWordStoryLabels = <LegacyWordStoryKind, String>{
  LegacyWordStoryKind.header: 'Header',
  LegacyWordStoryKind.footer: 'Footer',
  LegacyWordStoryKind.footnote: 'Footnote',
  LegacyWordStoryKind.endnote: 'Endnote',
  LegacyWordStoryKind.comment: 'Comment',
  LegacyWordStoryKind.textbox: 'Text box',
  LegacyWordStoryKind.headerTextbox: 'Header/footer text box',
  LegacyWordStoryKind.footnoteSeparator: 'Footnote separator',
  LegacyWordStoryKind.footnoteContinuationSeparator:
      'Footnote continuation separator',
  LegacyWordStoryKind.footnoteContinuationNotice:
      'Footnote continuation notice',
  LegacyWordStoryKind.endnoteSeparator: 'Endnote separator',
  LegacyWordStoryKind.endnoteContinuationSeparator:
      'Endnote continuation separator',
  LegacyWordStoryKind.endnoteContinuationNotice: 'Endnote continuation notice',
};

/// Compose already escaped parser markup; input document text is never used as
/// a tag, attribute, heading template or replacement target.
LegacyWordPreview projectLegacyWordPreview(LegacyWordDocument document) {
  const maxTextUnits = 8 * 1024 * 1024;
  const maxHtmlUnits = 4 * 1024 * 1024;
  const maxStories = 20000;
  if (document.stories.length > maxStories) {
    throw const FormatException('Word preview has too many stories.');
  }
  // The conversion model also retains stories whose anchors are hidden or
  // inside private field results. They must not become visible merely because
  // the app now displays auxiliary content. A shared story is visible when at
  // least one of its independently recorded occurrences is visible.
  final visibleReferences = <String, bool>{};
  void reference(String id, bool visible) {
    visibleReferences[id] = (visibleReferences[id] ?? false) || visible;
  }

  for (final item in document.noteReferences) {
    reference(item.storyId, !item.presentation.hidden);
  }
  final hiddenComments = <int>{};
  final replies = <int, List<int>>{};
  for (final item in document.commentReferences) {
    if (item.presentation.hidden) hiddenComments.add(item.id);
    if (item.parentId case final parent?) {
      replies.putIfAbsent(parent, () => []).add(item.id);
    }
  }
  // Replies inherit their parent's hidden/private status. A queue keeps this
  // linear in the number of validated references, even for reversed input.
  final pending = hiddenComments.toList();
  for (var index = 0; index < pending.length; index++) {
    for (final child in replies[pending[index]] ?? const <int>[]) {
      if (hiddenComments.add(child)) pending.add(child);
    }
  }
  for (final item in document.commentReferences) {
    reference(item.storyId, !hiddenComments.contains(item.id));
  }
  final drawings = <(bool, int, int), LegacyWordDrawing>{};
  final firstDrawings = <(bool, int), LegacyWordDrawing>{};
  final encodedDrawings = <(bool, int), LegacyWordDrawing>{};
  for (final drawing in document.media.drawings) {
    drawings[(drawing.headerStory, drawing.shapeId, drawing.anchorCp)] =
        drawing;
    firstDrawings.putIfAbsent((
      drawing.headerStory,
      drawing.shapeId,
    ), () => drawing);
    final encoded = drawing.textboxId;
    if (encoded != null && encoded >> 16 > 0) {
      encodedDrawings.putIfAbsent((
        drawing.headerStory,
        encoded >> 16,
      ), () => drawing);
    }
  }
  for (final item in document.textboxReferences) {
    final primary =
        drawings[(item.inHeaderFooter, item.shapeId, item.anchorCp)] ??
        firstDrawings[(item.inHeaderFooter, item.shapeId)] ??
        encodedDrawings[(item.inHeaderFooter, item.id)];
    final occurrences = <LegacyWordDrawing>[
      if (primary != null) primary,
      for (final anchor in [
        ...item.anchors,
        ...item.headerAliases,
        ...item.replicaAnchors,
      ])
        if (drawings[(item.inHeaderFooter, anchor.shapeId, anchor.anchorCp)]
            case final shape?)
          shape,
    ];
    if (occurrences.isNotEmpty) {
      reference(
        item.storyId,
        occurrences.any(
          (drawing) => !drawing.presentation.hidden && !drawing.shapeDeleted,
        ),
      );
    }
  }
  // Global CP order is independent of the physical order of CFB pieces. The
  // parser list index is the stable tie-breaker for shared header occurrences.
  final ordered =
      document.stories.indexed
          .where((item) => visibleReferences[item.$2.id] != false)
          .toList()
        ..sort((a, b) {
          final byCp = a.$2.startCp.compareTo(b.$2.startCp);
          return byCp == 0 ? a.$1.compareTo(b.$1) : byCp;
        });
  final text = StringBuffer(document.plainText);
  final descriptors = <LegacyWordPreviewStory>[];
  final textHeadings = <LegacyWordPreviewHeading>[];
  final labels = <String>[];
  final counts = <LegacyWordStoryKind, int>{};
  var htmlLength = document.safeHtml.length;
  if (text.length > maxTextUnits) {
    throw const FormatException('Word preview exceeds its text limit.');
  }
  for (final (_, story) in ordered) {
    final number = (counts[story.kind] ?? 0) + 1;
    counts[story.kind] = number;
    final descriptor = LegacyWordPreviewStory(
      id: story.id,
      kind: story.kind,
      number: number,
      startCp: story.startCp,
      endCp: story.endCp,
      sectionIndex: story.sectionIndex,
      headerFooterType: story.headerFooterType,
    );
    descriptors.add(descriptor);
    var label = '${legacyWordStoryLabels[story.kind]} $number';
    if (story.sectionIndex case final section?) {
      label += ' · Section ${section + 1}';
    }
    if (story.headerFooterType case final variant?) {
      label +=
          ' · ${switch (variant) {
            LegacyWordHeaderFooterType.even => 'Even pages',
            LegacyWordHeaderFooterType.normal => 'Default pages',
            LegacyWordHeaderFooterType.first => 'First page',
          }}';
    }
    labels.add(label);
    if (text.length + label.length + story.plainText.length + 3 >
        maxTextUnits) {
      throw const FormatException('Word preview exceeds its text limit.');
    }
    if (text.isNotEmpty) text.write('\n\n');
    final start = text.length;
    text.write(label);
    textHeadings.add(LegacyWordPreviewHeading(start, text.length, descriptor));
    text.write('\n${story.plainText}');
    htmlLength +=
        32 + const HtmlEscape().convert(label).length + story.safeHtml.length;
  }
  final htmlHeadings = <LegacyWordPreviewHeading>[];
  String? safeHtml;
  // Measure first: a large image-bearing story must not cause an additional
  // 64 MiB concatenation merely for a viewer that will fall back to text.
  if (htmlLength <= maxHtmlUnits) {
    final html = StringBuffer(document.safeHtml);
    for (var index = 0; index < ordered.length; index++) {
      html.write('<section><hr><h2>');
      final start = html.length;
      html.write(const HtmlEscape().convert(labels[index]));
      htmlHeadings.add(
        LegacyWordPreviewHeading(start, html.length, descriptors[index]),
      );
      html.write('</h2>${ordered[index].$2.safeHtml}</section>');
    }
    safeHtml = html.toString();
  }
  return LegacyWordPreview(
    plainText: text.toString(),
    safeHtml: safeHtml,
    stories: List.unmodifiable(descriptors),
    textHeadings: List.unmodifiable(textHeadings),
    htmlHeadings: List.unmodifiable(htmlHeadings),
  );
}
