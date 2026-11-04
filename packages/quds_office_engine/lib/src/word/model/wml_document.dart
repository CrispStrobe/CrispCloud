import '../../fonts/office_typeface.dart';
import '../../office/office_document_properties.dart';
import '../../opc/ole/embedded_part.dart';
import '../../opc/opc_archive.dart';
import '../../visual/office_visual.dart';
import '../math/omml_document.dart';
import '../properties/wml_properties.dart';
import 'word_notes.dart';
import 'word_revision.dart';
import 'word_styles.dart';

/// Class WmlBlock.
sealed class WmlBlock {
  /// WmlBlock API.
  WmlBlock();
}

/// Class WmlInline.
sealed class WmlInline {
  /// WmlInline API.
  WmlInline();
}

/// Class WmlRun.
class WmlRun extends WmlInline {
  /// WmlRun API.
  WmlRun({
    this.text = '',
    WmlRunProps? properties,
    this.hyperlink,
    List<int>? commentIds,
    this.noteRefId,
    this.noteRefEndnote = false,
  }) : properties = properties ?? WmlRunProps(),
       commentIds = commentIds ?? <int>[];

  /// text API.
  String text;

  /// properties API.
  WmlRunProps properties;

  /// hyperlink API.
  WmlHyperlink? hyperlink;

  /// commentIds API.
  List<int> commentIds;

  /// `w:footnoteReference` / `w:endnoteReference` id when this run is a mark.
  int? noteRefId;

  /// True when [noteRefId] points at an endnote.
  bool noteRefEndnote;
}

/// Class WmlComment.
class WmlComment {
  /// WmlComment API.
  WmlComment({
    required this.id,
    this.author = 'Quds Office',
    this.initials = 'QO',
    this.dateIso = '',
    String text = '',
    List<WmlParagraph>? paragraphs,
    List<WmlVisual>? visuals,
    this.parentId,
    this.resolved = false,
  }) : paragraphs =
           paragraphs ??
           <WmlParagraph>[
             WmlParagraph(inlines: <WmlInline>[WmlRun(text: text)]),
           ],
       visuals = visuals ?? <WmlVisual>[];

  /// id API.
  int id;

  /// author API.
  String author;

  /// initials API.
  String initials;

  /// dateIso API.
  String dateIso;

  /// paragraphs API.
  List<WmlParagraph> paragraphs;

  /// visuals API.
  List<WmlVisual> visuals;

  /// parentId API.
  int? parentId;

  /// resolved API.
  bool resolved;

  /// isReply API.
  bool get isReply => parentId != null;

  /// text API.
  String get text {
    final StringBuffer buffer = StringBuffer();
    for (final WmlParagraph paragraph in paragraphs) {
      final String line = paragraph.text;
      if (line.isEmpty) {
        continue;
      }
      if (buffer.isNotEmpty) {
        buffer.write('\n');
      }
      buffer.write(line);
    }
    return buffer.toString();
  }

  /// text API.
  set text(String value) {
    final WmlRunProps props = paragraphs.isEmpty
        ? WmlRunProps(fontSizeHalfPoints: 20)
        : (paragraphs.first.inlines
                  .whereType<WmlRun>()
                  .firstOrNull
                  ?.properties
                  .copy() ??
              WmlRunProps(fontSizeHalfPoints: 20));
    paragraphs
      ..clear()
      ..add(
        WmlParagraph(
          inlines: <WmlInline>[WmlRun(text: value, properties: props)],
        ),
      );
  }

  /// copy API.
  WmlComment copy() => WmlComment(
    id: id,
    author: author,
    initials: initials,
    dateIso: dateIso,
    paragraphs: <WmlParagraph>[
      for (final WmlParagraph paragraph in paragraphs)
        WmlParagraph(
          properties: paragraph.properties,
          inlines: <WmlInline>[
            for (final WmlInline inline in paragraph.inlines)
              if (inline is WmlRun)
                WmlRun(
                  text: inline.text,
                  properties: inline.properties.copy(),
                  hyperlink: inline.hyperlink,
                  commentIds: List<int>.from(inline.commentIds),
                )
              else
                inline,
          ],
        ),
    ],
    visuals: <WmlVisual>[
      for (final WmlVisual visual in visuals)
        WmlVisual(visual: visual.visual.copy()),
    ],
    parentId: parentId,
    resolved: resolved,
  );
}

/// Office-style hyperlink: heading/bookmark, web URL, or local file.
class WmlHyperlink {
  /// WmlHyperlink API.
  const WmlHyperlink({this.anchor, this.url, this.file});

  /// Internal bookmark or heading target (`w:anchor`).
  final String? anchor;

  /// url API.
  final String? url;

  /// file API.
  final String? file;

  /// isInternal API.
  bool get isInternal => anchor != null && anchor!.isNotEmpty;

  /// isWeb API.
  bool get isWeb {
    final String? value = url;
    if (value == null || value.isEmpty) {
      return false;
    }
    return value.startsWith('http://') ||
        value.startsWith('https://') ||
        value.startsWith('mailto:');
  }

  /// isFile API.
  bool get isFile => file != null && file!.isNotEmpty;

  /// displayTarget API.
  String get displayTarget => url ?? file ?? anchor ?? '';

  /// copy API.
  WmlHyperlink copy() => WmlHyperlink(anchor: anchor, url: url, file: file);

  /// fromTarget API.
  static WmlHyperlink? fromTarget(String raw) {
    final String value = raw.trim();
    if (value.isEmpty) {
      return null;
    }
    if (value.startsWith('#')) {
      return WmlHyperlink(anchor: value.substring(1));
    }
    if (value.startsWith('http://') ||
        value.startsWith('https://') ||
        value.startsWith('mailto:')) {
      return WmlHyperlink(url: value);
    }
    if (value.startsWith('file:') ||
        value.startsWith('/') ||
        value.contains('\\') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value)) {
      return WmlHyperlink(file: value);
    }
    return WmlHyperlink(anchor: value);
  }
}

/// Class WmlBreak.
class WmlBreak extends WmlInline {
  /// WmlBreak API.
  WmlBreak(this.type);

  /// type API.
  final WmlBreakType type;
}

/// Class WmlObject.
class WmlObject extends WmlInline {
  /// WmlObject API.
  WmlObject({
    required this.relationshipId,
    this.embedded,
    this.width = 200,
    this.height = 120,
  });

  /// relationshipId API.
  String relationshipId;

  /// embedded API.
  IsolatedEmbeddedPackage? embedded;

  /// width API.
  double width;

  /// height API.
  double height;
}

/// Class WmlParagraph.
class WmlParagraph extends WmlBlock {
  /// WmlParagraph API.
  WmlParagraph({List<WmlInline>? inlines, WmlParagraphProps? properties})
    : inlines = inlines ?? <WmlInline>[],
      properties = properties ?? WmlParagraphProps();

  /// inlines API.
  List<WmlInline> inlines;

  /// properties API.
  WmlParagraphProps properties;

  /// text API.
  String get text {
    final StringBuffer buffer = StringBuffer();
    for (final WmlInline inline in inlines) {
      if (inline is WmlRun) {
        buffer.write(inline.text);
      }
    }
    return buffer.toString();
  }
}

/// Class WmlTableCell.
class WmlTableCell {
  /// WmlTableCell API.
  WmlTableCell({
    List<WmlBlock>? blocks,
    this.gridSpan = 1,
    this.vMerge = WmlVMerge.none,
    this.width,
    this.fillColor,
    this.borderTop,
    this.borderBottom,
    this.borderLeft,
    this.borderRight,
  }) : blocks = blocks ?? <WmlBlock>[];

  /// blocks API.
  List<WmlBlock> blocks;

  /// gridSpan API.
  int gridSpan;

  /// vMerge API.
  WmlVMerge vMerge;

  /// width API.
  double? width;

  /// fillColor API.
  String? fillColor;

  /// `null` inherits table grid; `false` is `w:val="nil"` / none.
  bool? borderTop;

  /// borderBottom API.
  bool? borderBottom;

  /// borderLeft API.
  bool? borderLeft;

  /// borderRight API.
  bool? borderRight;
}

/// Class WmlTableRow.
class WmlTableRow {
  /// WmlTableRow API.
  WmlTableRow({List<WmlTableCell>? cells, this.cantSplit = false, this.height})
    : cells = cells ?? <WmlTableCell>[];

  /// cells API.
  List<WmlTableCell> cells;

  /// cantSplit API.
  bool cantSplit;

  /// height API.
  double? height;
}

/// Class WmlVisual.
class WmlVisual extends WmlBlock {
  /// WmlVisual API.
  WmlVisual({required this.visual});

  /// visual API.
  OfficeVisual visual;
}

/// Absolutely positioned text box / shape, independent of the story flow.
class WmlFrame extends WmlBlock {
  /// WmlFrame API.
  WmlFrame({
    this.x = 72,
    this.y = 72,
    this.width = 200,
    this.height = 120,
    this.anchor = WmlFrameAnchor.page,
    this.wrap = WmlFrameWrap.none,
    this.fillColor,
    this.strokeColor,
    List<WmlBlock>? blocks,
  }) : blocks = blocks ?? <WmlBlock>[];

  /// x API.
  double x;

  /// y API.
  double y;

  /// width API.
  double width;

  /// height API.
  double height;

  /// anchor API.
  WmlFrameAnchor anchor;

  /// wrap API.
  WmlFrameWrap wrap;

  /// fillColor API.
  String? fillColor;

  /// strokeColor API.
  String? strokeColor;

  /// blocks API.
  List<WmlBlock> blocks;

  /// pageX API.
  double pageX(WmlSection section) =>
      anchor == WmlFrameAnchor.margin ? section.margins.left + x : x;

  /// pageY API.
  double pageY(WmlSection section) =>
      anchor == WmlFrameAnchor.margin ? section.margins.top + y : y;
}

/// Class WmlEquation.
class WmlEquation extends WmlBlock {
  /// WmlEquation API.
  WmlEquation({required this.math});

  /// math API.
  OmmlEquation math;
}

/// Class WmlTocEntry.
class WmlTocEntry {
  /// WmlTocEntry API.
  WmlTocEntry({
    required this.text,
    required this.level,
    required this.headingParagraphIndex,
    this.pageNumber = 1,
  });

  /// text API.
  String text;

  /// level API.
  int level;

  /// headingParagraphIndex API.
  int headingParagraphIndex;

  /// pageNumber API.
  int pageNumber;
}

/// Live table of contents built from heading paragraphs.
class WmlToc extends WmlBlock {
  /// WmlToc API.
  WmlToc({
    this.minLevel = 1,
    this.maxLevel = 3,
    this.showPageNumbers = true,
    this.captionLabel,
    String title = 'Table of Contents',
    List<WmlTocEntry>? entries,
    WmlParagraph? titleParagraph,
    List<WmlParagraph>? itemParagraphs,
  }) : title = title,
       entries = entries ?? <WmlTocEntry>[],
       titleParagraph =
           titleParagraph ??
           WmlParagraph(
             properties: WmlParagraphProps(
               styleId: 'TOCHeading',
               spacingAfter: 10,
               spacingBefore: 0,
             ),
             inlines: <WmlInline>[
               WmlRun(
                 text: title,
                 properties: WmlRunProps(
                   bold: true,
                   fontSizeHalfPoints: 28,
                   color: '1F4E79',
                 ),
               ),
             ],
           ),
       itemParagraphs = itemParagraphs ?? <WmlParagraph>[];

  /// minLevel API.
  int minLevel;

  /// maxLevel API.
  int maxLevel;

  /// showPageNumbers API.
  bool showPageNumbers;

  /// When set, the TOC is a table of figures for this caption label.
  String? captionLabel;

  /// title API.
  String title;

  /// entries API.
  List<WmlTocEntry> entries;

  /// titleParagraph API.
  WmlParagraph titleParagraph;

  /// itemParagraphs API.
  List<WmlParagraph> itemParagraphs;
}

/// Class WmlTable.
class WmlTable extends WmlBlock {
  /// WmlTable API.
  WmlTable({
    List<double>? grid,
    List<WmlTableRow>? rows,
    WmlTableProps? properties,
  }) : grid = grid ?? <double>[],
       rows = rows ?? <WmlTableRow>[],
       properties = properties ?? WmlTableProps();

  /// grid API.
  List<double> grid;

  /// rows API.
  List<WmlTableRow> rows;

  /// properties API.
  WmlTableProps properties;
}

/// A bibliographic source referenced from the document body.
class WmlCitation {
  /// WmlCitation API.
  WmlCitation({
    required this.tag,
    required this.author,
    required this.title,
    this.year = '',
    this.pages = '',
  });

  /// Short tag used in the body (`(Smith 2020)`).
  String tag;

  /// author API.
  String author;

  /// title API.
  String title;

  /// year API.
  String year;

  /// pages API.
  String pages;

  /// inText API.
  String get inText {
    final String yearBit = year.isEmpty ? '' : ' $year';
    return '($author$yearBit)';
  }

  /// bibliographyLine API.
  String get bibliographyLine {
    final String yearBit = year.isEmpty ? '' : ' ($year).';
    return '$author.$yearBit $title';
  }
}

/// An index term marked in the document.
class WmlIndexMark {
  /// WmlIndexMark API.
  WmlIndexMark({required this.term, required this.paragraphIndex});

  /// term API.
  String term;

  /// paragraphIndex API.
  int paragraphIndex;
}

/// How the next section starts.
enum WmlSectionBreakKind { nextPage, continuous, oddPage, evenPage }

/// Class WmlSection.
class WmlSection {
  /// WmlSection API.
  WmlSection({
    List<WmlBlock>? blocks,
    this.pageSize = const WmlPageSize(),
    this.margins = const WmlPageMargins(),
    this.columnCount = 1,
    this.columnSpace = 36,
    this.columnSep = false,
    this.breakKind = WmlSectionBreakKind.nextPage,
    this.differentFirstPage = false,
    this.differentOddEven = false,
    this.linkToPrevious = true,
    this.lineNumbers = false,
    List<WmlParagraph>? header,
    List<WmlParagraph>? footer,
    List<WmlParagraph>? firstHeader,
    List<WmlParagraph>? firstFooter,
    List<WmlParagraph>? evenHeader,
    List<WmlParagraph>? evenFooter,
    List<WmlVisual>? headerVisuals,
    List<WmlVisual>? footerVisuals,
    List<WmlVisual>? firstHeaderVisuals,
    List<WmlVisual>? firstFooterVisuals,
    List<WmlVisual>? evenHeaderVisuals,
    List<WmlVisual>? evenFooterVisuals,
  }) : blocks = blocks ?? <WmlBlock>[],
       header = header ?? <WmlParagraph>[],
       footer = footer ?? <WmlParagraph>[],
       firstHeader = firstHeader ?? <WmlParagraph>[],
       firstFooter = firstFooter ?? <WmlParagraph>[],
       evenHeader = evenHeader ?? <WmlParagraph>[],
       evenFooter = evenFooter ?? <WmlParagraph>[],
       headerVisuals = headerVisuals ?? <WmlVisual>[],
       footerVisuals = footerVisuals ?? <WmlVisual>[],
       firstHeaderVisuals = firstHeaderVisuals ?? <WmlVisual>[],
       firstFooterVisuals = firstFooterVisuals ?? <WmlVisual>[],
       evenHeaderVisuals = evenHeaderVisuals ?? <WmlVisual>[],
       evenFooterVisuals = evenFooterVisuals ?? <WmlVisual>[];

  /// blocks API.
  List<WmlBlock> blocks;

  /// pageSize API.
  WmlPageSize pageSize;

  /// margins API.
  WmlPageMargins margins;

  /// columnCount API.
  int columnCount;

  /// columnSpace API.
  double columnSpace;

  /// columnSep API.
  bool columnSep;

  /// breakKind API.
  WmlSectionBreakKind breakKind;

  /// differentFirstPage API.
  bool differentFirstPage;

  /// differentOddEven API.
  bool differentOddEven;

  /// linkToPrevious API.
  bool linkToPrevious;

  /// lineNumbers API.
  bool lineNumbers;

  /// header API.
  List<WmlParagraph> header;

  /// footer API.
  List<WmlParagraph> footer;

  /// firstHeader API.
  List<WmlParagraph> firstHeader;

  /// firstFooter API.
  List<WmlParagraph> firstFooter;

  /// evenHeader API.
  List<WmlParagraph> evenHeader;

  /// evenFooter API.
  List<WmlParagraph> evenFooter;

  /// Pictures / drawings from the default header part.
  List<WmlVisual> headerVisuals;

  /// Pictures / drawings from the default footer part.
  List<WmlVisual> footerVisuals;

  /// Pictures / drawings from the first-page header part.
  List<WmlVisual> firstHeaderVisuals;

  /// Pictures / drawings from the first-page footer part.
  List<WmlVisual> firstFooterVisuals;

  /// Pictures / drawings from the even-page header part.
  List<WmlVisual> evenHeaderVisuals;

  /// Pictures / drawings from the even-page footer part.
  List<WmlVisual> evenFooterVisuals;

  /// headerForPage API.
  List<WmlParagraph> headerForPage(int pageNumber, {required bool firstInSection}) {
    if (differentFirstPage && firstInSection && firstHeader.isNotEmpty) {
      return firstHeader;
    }
    if (differentOddEven && pageNumber.isEven && evenHeader.isNotEmpty) {
      return evenHeader;
    }
    return header;
  }

  /// Header drawings for [pageNumber] (logo, etc.).
  List<WmlVisual> headerVisualsForPage(
    int pageNumber, {
    required bool firstInSection,
  }) {
    if (differentFirstPage &&
        firstInSection &&
        firstHeaderVisuals.isNotEmpty) {
      return firstHeaderVisuals;
    }
    if (differentOddEven &&
        pageNumber.isEven &&
        evenHeaderVisuals.isNotEmpty) {
      return evenHeaderVisuals;
    }
    return headerVisuals;
  }

  /// footerForPage API.
  List<WmlParagraph> footerForPage(int pageNumber, {required bool firstInSection}) {
    if (differentFirstPage && firstInSection && firstFooter.isNotEmpty) {
      return firstFooter;
    }
    if (differentOddEven && pageNumber.isEven && evenFooter.isNotEmpty) {
      return evenFooter;
    }
    return footer;
  }

  /// Footer drawings for [pageNumber].
  List<WmlVisual> footerVisualsForPage(
    int pageNumber, {
    required bool firstInSection,
  }) {
    if (differentFirstPage &&
        firstInSection &&
        firstFooterVisuals.isNotEmpty) {
      return firstFooterVisuals;
    }
    if (differentOddEven &&
        pageNumber.isEven &&
        evenFooterVisuals.isNotEmpty) {
      return evenFooterVisuals;
    }
    return footerVisuals;
  }

  /// contentWidth API.
  double get contentWidth => pageSize.width - margins.left - margins.right;

  /// contentHeight API.
  double get contentHeight => pageSize.height - margins.top - margins.bottom;

  /// resolvedColumnCount API.
  int get resolvedColumnCount => columnCount < 1 ? 1 : columnCount;

  /// columnWidth API.
  double get columnWidth {
    final int n = resolvedColumnCount;
    return ((contentWidth - columnSpace * (n - 1)) / n).clamp(12, contentWidth);
  }

  /// columnOriginX API.
  double columnOriginX(int index) =>
      margins.left + index * (columnWidth + columnSpace);
}

/// What a restricted document still allows.
enum WmlRestrictMode { readOnly, comments, forms }

/// Class WmlDocument.
class WmlDocument {
  /// WmlDocument API.
  WmlDocument({
    List<WmlSection>? sections,
    List<WmlComment>? comments,
    List<WmlNote>? footnotes,
    List<WmlNote>? endnotes,
    List<WmlRevision>? revisions,
    List<WmlCitation>? citations,
    List<WmlIndexMark>? indexMarks,
    List<WmlStyle>? styles,
    OfficeDocumentProperties? properties,
    this.package,
    this.trackRevisions = false,
    this.watermark = '',
    this.restrictEditing = false,
    this.restrictMode = WmlRestrictMode.readOnly,
    List<Map<String, String>>? mailMergeRecords,
    this.mailMergePreview = 0,
    this.sourceFileName = '',
    this.sourceByteLength,
  }) : sections = sections ?? <WmlSection>[WmlSection()],
       comments = comments ?? <WmlComment>[],
       footnotes = footnotes ?? <WmlNote>[],
       endnotes = endnotes ?? <WmlNote>[],
       revisions = revisions ?? <WmlRevision>[],
       citations = citations ?? <WmlCitation>[],
       indexMarks = indexMarks ?? <WmlIndexMark>[],
       styles = styles ?? <WmlStyle>[],
       mailMergeRecords = mailMergeRecords ?? <Map<String, String>>[],
       properties = properties ?? OfficeDocumentProperties();

  /// sections API.
  List<WmlSection> sections;

  /// comments API.
  List<WmlComment> comments;

  /// footnotes API.
  List<WmlNote> footnotes;

  /// endnotes API.
  List<WmlNote> endnotes;

  /// revisions API.
  List<WmlRevision> revisions;

  /// citations API.
  List<WmlCitation> citations;

  /// indexMarks API.
  List<WmlIndexMark> indexMarks;

  /// Paragraph styles written to `styles.xml` when non-empty.
  List<WmlStyle> styles;

  /// properties API.
  OfficeDocumentProperties properties;

  /// package API.
  OpcPackage? package;

  /// trackRevisions API.
  bool trackRevisions;

  /// Diagonal / stamp watermark text painted by hosts.
  String watermark;

  /// Form / read-only protection (not file encryption).
  bool restrictEditing;

  /// restrictMode API.
  WmlRestrictMode restrictMode;

  /// Mail-merge data rows.
  final List<Map<String, String>> mailMergeRecords;

  /// mailMergePreview API.
  int mailMergePreview;

  /// Original package file name for FILENAME fields (host-supplied).
  String sourceFileName;

  /// Original package size in bytes for FILESIZE fields (host-supplied).
  int? sourceByteLength;

  /// empty API.
  factory WmlDocument.empty({String text = '', bool? rtl}) {
    final bool useRtl = rtl ?? OfficeTypeface.isRtlText(text);
    return WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          blocks: <WmlBlock>[
            WmlParagraph(
              properties: WmlParagraphProps(
                rightToLeft: useRtl ? true : null,
                justification: useRtl
                    ? WmlJustification.right
                    : WmlJustification.left,
              ),
              inlines: <WmlInline>[WmlRun(text: text)],
            ),
          ],
        ),
      ],
    );
  }

  /// paragraphs API.
  Iterable<WmlParagraph> get paragraphs sync* {
    for (final WmlSection section in sections) {
      yield* _paragraphsIn(section.blocks);
    }
  }

  /// sectionIndexOf API.
  int sectionIndexOf(WmlParagraph paragraph) {
    for (int i = 0; i < sections.length; i++) {
      for (final WmlParagraph candidate in _paragraphsIn(sections[i].blocks)) {
        if (identical(candidate, paragraph)) {
          return i;
        }
      }
    }
    return 0;
  }

  /// visuals API.
  Iterable<WmlVisual> get visuals sync* {
    for (final WmlSection section in sections) {
      yield* _visualsIn(section.blocks);
    }
  }

  static Iterable<WmlVisual> _visualsIn(List<WmlBlock> blocks) sync* {
    for (final WmlBlock block in blocks) {
      switch (block) {
        case WmlVisual():
          yield block;
        case WmlFrame():
          yield* _visualsIn(block.blocks);
        case WmlTable(:final List<WmlTableRow> rows):
          for (final WmlTableRow row in rows) {
            for (final WmlTableCell cell in row.cells) {
              yield* _visualsIn(cell.blocks);
            }
          }
        case WmlParagraph():
          break;
        case WmlEquation():
          break;
        case WmlToc():
          break;
      }
    }
  }

  static Iterable<WmlParagraph> _paragraphsIn(List<WmlBlock> blocks) sync* {
    for (final WmlBlock block in blocks) {
      switch (block) {
        case WmlParagraph():
          yield block;
        case WmlTable(:final List<WmlTableRow> rows):
          for (final WmlTableRow row in rows) {
            for (final WmlTableCell cell in row.cells) {
              yield* _paragraphsIn(cell.blocks);
            }
          }
        case WmlFrame():
          yield* _paragraphsIn(block.blocks);
        case WmlVisual():
          break;
        case WmlEquation():
          break;
        case WmlToc():
          yield block.titleParagraph;
          yield* block.itemParagraphs;
      }
    }
  }

  /// equations API.
  Iterable<WmlEquation> get equations sync* {
    for (final WmlSection section in sections) {
      yield* _equationsIn(section.blocks);
    }
  }

  static Iterable<WmlEquation> _equationsIn(List<WmlBlock> blocks) sync* {
    for (final WmlBlock block in blocks) {
      switch (block) {
        case WmlEquation():
          yield block;
        case WmlTable(:final List<WmlTableRow> rows):
          for (final WmlTableRow row in rows) {
            for (final WmlTableCell cell in row.cells) {
              yield* _equationsIn(cell.blocks);
            }
          }
        case WmlFrame():
          yield* _equationsIn(block.blocks);
        case WmlParagraph():
        case WmlVisual():
        case WmlToc():
          break;
      }
    }
  }
}
