import 'package:flutter/foundation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import 'word_image_import.dart';

const wordNativeClipboardLimit = 12 * 1024 * 1024;
const _expandedLimit = 24 * 1024 * 1024;

typedef WordDocxClipboardFragment = ({
  List<WmlBlock> blocks,
  List<WmlSection>? sections,
});

/// Imports the editable body from the native Word clipboard representation.
/// The CFB is treated as a byte container, never as an executable OLE object.
Future<WordDocxClipboardFragment?> readWordClipboardDocx(
  Uint8List bytes,
) async {
  if (bytes.length > wordNativeClipboardLimit) return null;
  try {
    final source = await compute(
      _readSections,
      bytes,
      debugLabel: 'Read Word clipboard fragment',
    );
    if (source.isEmpty) return null;
    final projection = _ClipboardBody();
    // A copy that carries section stories or actual section boundaries can
    // restore its page layout when pasted into an empty destination.
    final carriesLayout = source.length > 1 || source.any(_hasPageStories);
    if (!carriesLayout) {
      final blocks = await projection.blocks(source.single.blocks);
      return (blocks: blocks, sections: null);
    }
    final sections = [
      for (final section in source) await projection.section(section),
    ];
    return (
      blocks: [for (final section in sections) ...section.blocks],
      sections: sections,
    );
  } on Exception {
    return null;
  }
}

List<WmlSection> _readSections(Uint8List bytes) {
  final Uint8List? docx;
  if (CfbfFile.isCfbf(bytes)) {
    final container = BoundedCfbReader(
      bytes,
      maxFileBytes: wordNativeClipboardLimit,
      maxStreamBytes: wordNativeClipboardLimit,
      maxTotalReadBytes: wordNativeClipboardLimit,
    );
    docx = container.readPath('Package');
  } else {
    docx = bytes;
  }
  if (docx == null) return [];
  final source = ZipReader.open(
    MemoryByteSource(docx),
    maxEntries: 160,
    rejectDuplicateNames: true,
  );
  if (!source.contains('word/document.xml')) return [];
  final filtered = ZipWriter();
  var remaining = _expandedLimit;
  for (final entry in source.entries) {
    final name = entry.fileName;
    if (!_parts.contains(name) &&
        !_assets.hasMatch(name) &&
        !_stories.hasMatch(name)) {
      continue;
    }
    final limit = name.startsWith('word/media/')
        ? WordImageImport.maxInputBytes
        : 2 * 1024 * 1024;
    if (entry.uncompressedSize > remaining || entry.uncompressedSize > limit) {
      throw const FormatException(
        'Word clipboard part exceeds its size budget',
      );
    }
    final part = source.read(
      name,
      maxBytes: remaining < limit ? remaining : limit,
    );
    remaining -= part.length;
    filtered.addFile(name, part, store: true);
  }
  final package = OpcPackage.openBytes(filtered.close());
  if (package.kind != OpcPackageKind.word) return [];
  final document = WordDeserializer().read(package);
  return document.sections.length > 24 ? [] : document.sections;
}

const _parts = {
  '[Content_Types].xml',
  '_rels/.rels',
  'word/document.xml',
  'word/_rels/document.xml.rels',
  'word/styles.xml',
  'word/numbering.xml',
  'word/settings.xml',
  'word/fontTable.xml',
};

final _assets = RegExp(
  r'^word/(?:theme/theme\d+\.xml|media/[A-Za-z0-9_.-]+\.(?:png|jpe?g|gif|webp))$',
  caseSensitive: false,
);

final _stories = RegExp(
  r'^word/(?:(?:header|footer)\d+\.xml|_rels/(?:header|footer)\d+\.xml\.rels)$',
);

bool _hasPageStories(WmlSection source) =>
    source.header.isNotEmpty ||
    source.footer.isNotEmpty ||
    source.firstHeader.isNotEmpty ||
    source.firstFooter.isNotEmpty ||
    source.evenHeader.isNotEmpty ||
    source.evenFooter.isNotEmpty ||
    source.headerVisuals.isNotEmpty ||
    source.footerVisuals.isNotEmpty ||
    source.firstHeaderVisuals.isNotEmpty ||
    source.firstFooterVisuals.isNotEmpty ||
    source.evenHeaderVisuals.isNotEmpty ||
    source.evenFooterVisuals.isNotEmpty;

class _ClipboardBody {
  var _blocks = 0;
  var _runs = 0;
  var _characters = 0;
  var _images = 0;
  var _imageBytes = 0;

  Future<WmlSection> section(WmlSection source) async {
    final size = source.pageSize.copyWith(
      width: source.pageSize.width.clamp(144, 1584),
      height: source.pageSize.height.clamp(144, 1584),
    );
    final m = source.margins;
    final margins = WmlPageMargins(
      top: m.top.clamp(0, size.height * .45),
      bottom: m.bottom.clamp(0, size.height * .45),
      left: m.left.clamp(0, size.width * .45),
      right: m.right.clamp(0, size.width * .45),
      header: m.header.clamp(0, size.height * .45),
      footer: m.footer.clamp(0, size.height * .45),
    );
    Future<List<WmlParagraph>> story(List<WmlParagraph> paragraphs) async => [
      for (final p in paragraphs.take(100))
        await _paragraph(p, pageStory: true),
    ];
    Future<List<WmlVisual>> visuals(List<WmlVisual> pictures) async => [
      for (final picture in pictures) ?await _picture(picture),
    ];
    return WmlSection(
      blocks: await blocks(source.blocks),
      pageSize: size,
      margins: margins,
      columnCount: source.columnCount.clamp(1, 12),
      columnSpace: source.columnSpace.clamp(0, 144),
      columnSep: source.columnSep,
      breakKind: source.breakKind,
      differentFirstPage: source.differentFirstPage,
      differentOddEven: source.differentOddEven,
      linkToPrevious: source.linkToPrevious,
      lineNumbers: source.lineNumbers,
      header: await story(source.header),
      footer: await story(source.footer),
      firstHeader: await story(source.firstHeader),
      firstFooter: await story(source.firstFooter),
      evenHeader: await story(source.evenHeader),
      evenFooter: await story(source.evenFooter),
      headerVisuals: await visuals(source.headerVisuals),
      footerVisuals: await visuals(source.footerVisuals),
      firstHeaderVisuals: await visuals(source.firstHeaderVisuals),
      firstFooterVisuals: await visuals(source.firstFooterVisuals),
      evenHeaderVisuals: await visuals(source.evenHeaderVisuals),
      evenFooterVisuals: await visuals(source.evenFooterVisuals),
    );
  }

  Future<List<WmlBlock>> blocks(List<WmlBlock> source, [int depth = 0]) async {
    if (depth > 20) throw const FormatException('Word clipboard nesting limit');
    final result = <WmlBlock>[];
    for (final block in source) {
      if (++_blocks > 2500) {
        throw const FormatException('Word clipboard block limit');
      }
      switch (block) {
        case WmlParagraph():
          result.add(await _paragraph(block));
        case WmlVisual():
          final picture = await _picture(block);
          if (picture != null) result.add(picture);
        case WmlTable():
          result.add(await _table(block, depth));
        case WmlFrame():
          result.addAll(await blocks(block.blocks, depth + 1));
        case WmlContentControlBlock():
          result.addAll(await blocks(block.blocks, depth + 1));
        case WmlToc():
          for (final para in WmlClone.paragraphsOf(block)) {
            if (++_blocks > 2500) {
              throw const FormatException('Word clipboard block limit');
            }
            result.add(await _paragraph(para));
          }
        default:
          break;
      }
    }
    return result;
  }

  Future<WmlParagraph> _paragraph(
    WmlParagraph source, {
    bool pageStory = false,
  }) async {
    final props = source.properties.copy()
      ..sourcePropertiesXml = null
      ..importedValues = null
      ..styleId = null
      ..defaultStyleId = null
      ..bookmarkName = null
      ..sourceBookmarkName = null
      ..pageNumberField = pageStory && source.properties.pageNumberField
      ..fieldInstruction = pageStory
          ? _safePageField(source.properties.fieldInstruction)
          : null
      ..fieldBegin = false
      ..fieldSeparate = false
      ..fieldEnd = false
      ..noteId = null
      ..endnoteRef = false
      ..explicitJustification = true
      ..explicitIndent = true
      ..explicitLineSpacing = true
      ..explicitSpacingBefore = true
      ..explicitSpacingAfter = true;
    final marker = props.importedParagraphMark;
    if (marker != null) props.importedParagraphMark = _runProps(marker);
    final inlines = <WmlInline>[];
    // Numbering IDs belong to the source package. Keep the displayed labels
    // and tab alignment without picking up a different destination list.
    final hadNumbering = props.numId != null;
    final label = hadNumbering ? props.listLabel : null;
    if (label != null && label.isNotEmpty) {
      inlines.add(
        WmlRun(
          text: label.trimRight() + (props.listLabelUsesSpace ? ' ' : '\t'),
          properties: marker == null ? null : _runProps(marker),
        ),
      );
    }
    props
      ..numId = null
      ..ilvl = 0
      ..listLabel = null
      ..listRestart = null
      ..numberingSuppressed = hadNumbering || props.numberingSuppressed;
    for (final inline in source.inlines) {
      if (++_runs > 20000) {
        throw const FormatException('Word clipboard run limit');
      }
      if (inline is WmlBreak) {
        inlines.add(WmlBreak(inline.type));
      } else if (inline is WmlRun) {
        final text = inline.text;
        _characters += text.length;
        if (_characters > 200000) {
          throw const FormatException('Word clipboard text limit');
        }
        final picture = inline.inlineVisual;
        final embedded = picture == null ? null : await _picture(picture);
        final pageField = pageStory
            ? _safePageField(inline.fieldInstruction)
            : null;
        final formattingOnly =
            picture == null &&
            inline.fieldInstruction == null &&
            inline.noteRefId == null;
        if (text.isNotEmpty ||
            formattingOnly ||
            embedded != null ||
            pageField != null) {
          inlines.add(
            WmlRun(
              text: text,
              properties: _runProps(inline.properties),
              hyperlink: _safeLink(inline.hyperlink),
              inlineVisual: embedded,
              fieldInstruction: pageField,
            ),
          );
        }
      }
    }
    return WmlParagraph(properties: props, inlines: inlines);
  }

  Future<WmlTable> _table(WmlTable source, int depth) async {
    return WmlTable(
      grid: List.of(source.grid),
      properties: source.properties.copy()
        ..sourcePropertiesXml = null
        ..importedValues = null
        ..styleId = null,
      rows: [
        for (final row in source.rows)
          WmlTableRow(
            height: row.height,
            heightIsExact: row.heightIsExact,
            cantSplit: row.cantSplit,
            gridBefore: row.gridBefore,
            gridAfter: row.gridAfter,
            cells: [
              for (final cell in row.cells)
                WmlTableCell(
                  gridSpan: cell.gridSpan,
                  vMerge: cell.vMerge,
                  width: cell.width,
                  fillColor: cell.fillColor,
                  borderTop: cell.borderTop,
                  borderBottom: cell.borderBottom,
                  borderLeft: cell.borderLeft,
                  borderRight: cell.borderRight,
                  blocks: await blocks(cell.blocks, depth + 1),
                ),
            ],
          ),
      ],
    );
  }

  Future<WmlVisual?> _picture(WmlVisual source) async {
    final visual = source.visual;
    final bytes = visual.imageBytes;
    if (!visual.isPicture ||
        bytes == null ||
        _images >= 16 ||
        bytes.length > WordImageImport.maxBatchBytes - _imageBytes) {
      return null;
    }
    _images++;
    _imageBytes += bytes.length;
    final image = await WordImageImport.normalize(bytes);
    if (image == null) return null;
    return WmlVisual(
      visual: OfficeVisual(
        kind: OfficeVisualKind.picture,
        title: visual.title,
        imageBytes: image.imageBytes,
        picture: visual.picture.copy(),
        width: visual.width.clamp(1, 1440),
        height: visual.height.clamp(1, 1440),
        offsetX: visual.offsetX.clamp(-1440, 1440),
        offsetY: visual.offsetY.clamp(-1440, 1440),
      ),
    );
  }

  static String? _safePageField(String? instruction) {
    final command = instruction
        ?.trim()
        .split(RegExp(r'\s+'))
        .first
        .toUpperCase();
    return const {'PAGE', 'NUMPAGES', 'SECTIONPAGES'}.contains(command)
        ? command
        : null;
  }

  static WmlRunProps _runProps(WmlRunProps source) => source.copy()
    ..sourcePropertiesXml = null
    ..importedValues = null
    ..styleId = null;

  static WmlHyperlink? _safeLink(WmlHyperlink? link) {
    final target = link?.url;
    final uri = target == null ? null : Uri.tryParse(target);
    if (uri == null || target!.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      return null;
    }
    return switch (uri.scheme) {
      'http' || 'https' when uri.hasAuthority => WmlHyperlink(url: target),
      'mailto' when uri.path.isNotEmpty => WmlHyperlink(url: target),
      _ => null,
    };
  }
}
