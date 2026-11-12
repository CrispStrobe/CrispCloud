<<<<<<< HEAD
export 'package:legacy_doc_parser/legacy_doc_parser.dart';
=======
import 'dart:convert';

import 'legacy_word_structured_model.dart';

/// Renders only resolved, visible content. All markup and CSS property names
/// are fixed here; document text cannot introduce links, assets or HTML.
///
/// Merged cells keep the paragraphs from their continuations. The preview is
/// an approximation of Word layout, not a paginated rendering engine.
String renderLegacyWordHtml(List<LegacyWordBlock> blocks) =>
    _HtmlWriter().render(blocks);

class _HtmlWriter {
  static const _maxBytes = 24 * 1024 * 1024;
  static const _maxItems = 200000;
  static const _escape = HtmlEscape(HtmlEscapeMode.element);
  static final _color = RegExp(r'^[a-fA-F0-9]{6}$');
  final _buffer = StringBuffer();
  var _bytes = 0;
  var _items = 0;

  String render(List<LegacyWordBlock> blocks) {
    _write('<div style="white-space:pre-wrap;overflow-wrap:anywhere;">');
    for (final block in blocks) {
      _item();
      switch (block) {
        case LegacyWordParagraph():
          _paragraph(block);
        case LegacyWordTable():
          _table(block);
      }
    }
    _write('</div>');
    return _buffer.toString();
  }

  void _paragraph(LegacyWordParagraph paragraph) {
    _item();
    final style = paragraph.style;
    final heading = style.headingLevel;
    final tag = heading != null && heading >= 1 && heading <= 6
        ? 'h$heading'
        : 'p';
    final attributes = heading != null && heading >= 7 && heading <= 9
        ? ' role="heading" aria-level="$heading"'
        : '';
    final css = <String>[
      'font-weight:normal',
      'font-size:inherit',
      'text-align:${switch (style.alignment) {
        LegacyWordAlignment.left => 'left',
        LegacyWordAlignment.center => 'center',
        LegacyWordAlignment.right => 'right',
        LegacyWordAlignment.justify || LegacyWordAlignment.distribute => 'justify',
      }}',
      'margin-top:${_twips(style.spaceBeforeTwips)}pt',
      'margin-bottom:${_twips(style.spaceAfterTwips)}pt',
      'margin-left:${_twips(style.leftIndentTwips)}pt',
      'margin-right:${_twips(style.rightIndentTwips)}pt',
      'text-indent:${_twips(style.firstLineIndentTwips)}pt',
      if (style.alignment == LegacyWordAlignment.distribute)
        'text-align-last:justify',
      if (style.keepNext) 'break-after:avoid',
      if (style.keepTogether) 'break-inside:avoid',
      if (style.pageBreakBefore) 'break-before:page',
    ];
    final lineSpacing = style.lineSpacingValue;
    if (lineSpacing != null && lineSpacing != 0) {
      css.add(
        style.lineSpacingMultiple
            ? 'line-height:${lineSpacing.abs() / 240}'
            : 'line-height:${_twips(lineSpacing.abs())}pt',
      );
    }
    _write('<$tag$attributes style="${css.join(';')}">');
    var hasVisibleText = false;
    for (final run in paragraph.runs) {
      _item();
      if (run.style.hidden || run.text.isEmpty) continue;
      hasVisibleText = true;
      _run(run);
    }
    if (!hasVisibleText) _write('<br>');
    _write('</$tag>');
  }

  void _run(LegacyWordRun run) {
    final style = run.style;
    final css = <String>[
      if (style.bold) 'font-weight:bold',
      if (style.italic) 'font-style:italic',
      if (style.smallCaps) 'font-variant:small-caps',
      if (style.allCaps) 'text-transform:uppercase',
      if (style.underline || style.strike || style.doubleStrike)
        'text-decoration:${[if (style.underline) 'underline', if (style.strike || style.doubleStrike) 'line-through'].join(' ')}',
      if (style.doubleStrike) 'text-decoration-style:double',
      if (style.fontSizeHalfPoints case final size? when size > 0)
        'font-size:${size / 2}pt',
      if (style.colorHex case final color? when _color.hasMatch(color))
        'color:#$color',
      if (style.highlightHex case final color? when _color.hasMatch(color))
        'background-color:#$color',
      if (style.spacingTwips case final spacing?)
        'letter-spacing:${_twips(spacing)}pt',
      if (style.verticalAlign == LegacyWordVerticalAlignment.superscript)
        'vertical-align:super',
      if (style.verticalAlign == LegacyWordVerticalAlignment.subscript)
        'vertical-align:sub',
      if (style.positionHalfPoints case final position? when position != 0)
        'position:relative;top:${-position / 2}pt',
    ];
    final font = style.fontName;
    if (font != null && font.isNotEmpty && font.length <= 256) {
      // Hex escapes inside one quoted CSS string cannot terminate it or
      // introduce a url(), even if the original font name contains quotes.
      final escapedFont = font.runes
          .map((rune) => '\\${rune.toRadixString(16)} ')
          .join();
      css.add("font-family:'$escapedFont'");
    }
    if (run.deleted) {
      _write(
        '<del style="background-color:#ffe8e8;'
        'text-decoration:line-through;">',
      );
    }
    if (run.inserted) {
      _write(
        '<ins style="background-color:#e5f5e5;'
        'text-decoration:underline;">',
      );
    }
    if (css.isNotEmpty) _write('<span style="${css.join(';')}">');
    _text(run.text);
    if (css.isNotEmpty) _write('</span>');
    if (run.inserted) _write('</ins>');
    if (run.deleted) _write('</del>');
  }

  void _table(LegacyWordTable table) {
    final rows = <List<_HtmlCell>>[];
    var active = <(int, int), _HtmlCell>{};
    for (final row in table.rows) {
      _item();
      final cells = <_HtmlCell>[];
      final nextActive = <(int, int), _HtmlCell>{};
      for (var column = 0; column < row.cells.length;) {
        _item();
        final start = column;
        final first = row.cells[column++];
        final source = <LegacyWordTableCell>[first];
        if (first.mergeStart && !first.mergeContinue) {
          while (column < row.cells.length &&
              row.cells[column].mergeContinue &&
              !row.cells[column].mergeStart) {
            _item();
            source.add(row.cells[column++]);
          }
        }
        final span = column - start;
        final paragraphs = <LegacyWordParagraph>[];
        for (final cell in source) {
          for (final paragraph in cell.paragraphs) {
            _item();
            paragraphs.add(paragraph);
          }
        }
        final continues = source.every(
          (cell) => cell.verticalMergeContinue && !cell.verticalMergeStart,
        );
        final key = (start, span);
        final previous = active[key];
        if (continues && previous != null) {
          previous.rowSpan++;
          previous.paragraphs.addAll(paragraphs);
          nextActive[key] = previous;
          continue;
        }
        final cell = _HtmlCell(
          paragraphs: paragraphs,
          isHeader: row.isHeader,
          columnSpan: span,
          widthTwips: source.every((cell) => cell.widthTwips != null)
              ? source.fold<int>(0, (sum, cell) => sum + cell.widthTwips!)
              : null,
        );
        cells.add(cell);
        if (source.every(
          (cell) => cell.verticalMergeStart && !cell.verticalMergeContinue,
        )) {
          nextActive[key] = cell;
        }
      }
      rows.add(cells);
      active = nextActive;
    }
    _write('<table style="border-collapse:collapse;"><tbody>');
    for (final row in rows) {
      _write('<tr>');
      for (final cell in row) {
        final tag = cell.isHeader ? 'th' : 'td';
        final width = cell.widthTwips;
        _write(
          '<$tag${cell.isHeader ? ' scope="col"' : ''}'
          '${cell.columnSpan > 1 ? ' colspan="${cell.columnSpan}"' : ''}'
          '${cell.rowSpan > 1 ? ' rowspan="${cell.rowSpan}"' : ''}'
          ' style="border:1px solid #888;vertical-align:top;padding:4px;'
          '${width != null && width > 0 ? 'width:${_twips(width)}pt;' : ''}">',
        );
        for (final paragraph in cell.paragraphs) {
          _paragraph(paragraph);
        }
        _write('</$tag>');
      }
      _write('</tr>');
    }
    _write('</tbody></table>');
  }

  void _text(String text) {
    // Chunk before escaping, so a single hostile run cannot allocate an
    // unbounded escaped copy. Keep UTF-16 surrogate pairs in the same chunk.
    for (var start = 0; start < text.length;) {
      var end = start + 4096;
      if (end > text.length) end = text.length;
      if (end < text.length) {
        final last = text.codeUnitAt(end - 1);
        if (last >= 0xd800 && last <= 0xdbff) end--;
      }
      final escaped = _escape.convert(text.substring(start, end));
      _write(
        escaped
            .replaceAll('\n', '<br>')
            .replaceAll('\f', '<br style="break-after:page;">'),
      );
      start = end;
    }
  }

  static String _twips(int value) => (value / 20).toString();

  void _item() {
    if (++_items > _maxItems) {
      throw const FormatException('Word HTML preview is too complex.');
    }
  }

  void _write(String value) {
    if (value.length > _maxBytes - _bytes) {
      throw const FormatException('Word HTML preview exceeds its size limit.');
    }
    _bytes += utf8.encode(value).length;
    if (_bytes > _maxBytes) {
      throw const FormatException('Word HTML preview exceeds its size limit.');
    }
    _buffer.write(value);
  }
}

class _HtmlCell {
  _HtmlCell({
    required this.paragraphs,
    required this.isHeader,
    required this.columnSpan,
    required this.widthTwips,
  });
  final List<LegacyWordParagraph> paragraphs;
  final bool isHeader;
  final int columnSpan;
  final int? widthTwips;
  var rowSpan = 1;
}
>>>>>>> origin/feature/format-viewers-path-favorites-20261112
