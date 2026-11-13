// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';
import 'dart:typed_data';

import 'legacy_word_metafile.dart';
import 'legacy_word_structured_model.dart';
import 'legacy_word_numbering.dart';

part 'legacy_word_html_media.dart';

/// Renders only resolved, visible content. All markup and CSS property names
/// are fixed here; document text cannot introduce links or HTML. Referenced
/// media may introduce bounded data images; external names are never fetched.
///
/// Merged cells keep the paragraphs from their continuations. The preview is
/// an approximation of Word layout, not a paginated rendering engine.
String renderLegacyWordHtml(
  List<LegacyWordBlock> blocks, {
  List<LegacyWordNumberingDefinition> numberingDefinitions = const [],
  int? defaultTabStopTwips,
  LegacyWordMediaCatalog media = const LegacyWordMediaCatalog(),
}) => LegacyWordHtmlRenderer(
  numberingDefinitions: numberingDefinitions,
  defaultTabStopTwips: defaultTabStopTwips,
  media: media,
).render(blocks);

/// Reuses one bounded image validation/cache across related document stories.
/// Each rendered story still has its own text/markup output budget.
class LegacyWordHtmlRenderer {
  LegacyWordHtmlRenderer({
    this.numberingDefinitions = const [],
    this.defaultTabStopTwips,
    LegacyWordMediaCatalog media = const LegacyWordMediaCatalog(),
  }) : _media = _HtmlMediaIndex(media);
  final List<LegacyWordNumberingDefinition> numberingDefinitions;
  final int? defaultTabStopTwips;
  final _HtmlMediaIndex _media;
  var _renderedBytes = 0;
  static const _maxCombinedBytes = 64 * 1024 * 1024;

  String render(List<LegacyWordBlock> blocks) => renderAll([blocks]).single;

  /// Reserves all text and placeholder markup before enabling image expansion.
  /// This prevents image previews from exhausting later stories' text budget.
  List<String> renderAll(List<List<LegacyWordBlock>> stories) {
    if (stories.length > 20001) {
      throw const FormatException('Word preview has too many stories.');
    }
    if (_media._events.isEmpty) {
      final result = <String>[];
      for (final blocks in stories) {
        final writer = _HtmlWriter(
          numberingDefinitions,
          defaultTabStopTwips,
          _media,
        );
        result.add(writer.render(blocks));
        _renderedBytes += writer._bytes;
        if (_renderedBytes > _maxCombinedBytes) {
          throw const FormatException(
            'Word story previews exceed the output limit.',
          );
        }
      }
      return List.unmodifiable(result);
    }
    final baselineBytes = <int>[];
    var totalBaseline = 0;
    for (final blocks in stories) {
      final measure = _HtmlWriter(
        numberingDefinitions,
        defaultTabStopTwips,
        _media,
        measureOnly: true,
      )..render(blocks);
      baselineBytes.add(measure._bytes);
      totalBaseline += measure._bytes;
      if (totalBaseline > _maxCombinedBytes - _renderedBytes) {
        throw const FormatException(
          'Word story previews exceed the output limit.',
        );
      }
    }
    _media.remainingExpansionBytes =
        _maxCombinedBytes - _renderedBytes - totalBaseline;
    final result = <String>[];
    for (var i = 0; i < stories.length; i++) {
      final writer = _HtmlWriter(
        numberingDefinitions,
        defaultTabStopTwips,
        _media,
        imageExpansionBytes: _HtmlWriter._maxBytes - baselineBytes[i],
      );
      result.add(writer.render(stories[i]));
      _renderedBytes += writer._bytes;
    }
    return List.unmodifiable(result);
  }
}

class _HtmlWriter {
  _HtmlWriter(
    this.numberingDefinitions,
    this.defaultTabStopTwips,
    this._media, {
    this.measureOnly = false,
    this.imageExpansionBytes = 0,
  });
  static const _maxBytes = 24 * 1024 * 1024;
  static const _maxItems = 200000;
  static const _escape = HtmlEscape(HtmlEscapeMode.element);
  static final _color = RegExp(r'^[a-fA-F0-9]{6}$');
  final _buffer = StringBuffer();
  final List<LegacyWordNumberingDefinition> numberingDefinitions;
  final int? defaultTabStopTwips;
  final _HtmlMediaIndex _media;
  final bool measureOnly;
  int imageExpansionBytes;
  final _markers = <LegacyWordParagraph, _HtmlListMarker>{};
  var _bytes = 0;
  var _items = 0;
  var _markerUnits = 0;
  var _tableDepth = 0;

  String render(List<LegacyWordBlock> blocks) {
    _prepareNumbering(blocks);
    if (defaultTabStopTwips != null &&
        (defaultTabStopTwips! <= 0 || defaultTabStopTwips! > 65535)) {
      throw const FormatException('Invalid Word preview tab interval.');
    }
    _write(
      '<div style="white-space:pre-wrap;overflow-wrap:anywhere;'
      '${defaultTabStopTwips == null ? '' : 'tab-size:${_twips(defaultTabStopTwips!)}pt;'}">',
    );
    _blocks(blocks);
    _write('</div>');
    return _buffer.toString();
  }

  void _blocks(List<LegacyWordBlock> blocks) {
    for (var index = 0; index < blocks.length; index++) {
      final block = blocks[index];
      _item();
      switch (block) {
        case LegacyWordParagraph():
          _paragraph(
            block,
            previous: index > 0 && blocks[index - 1] is LegacyWordParagraph
                ? blocks[index - 1] as LegacyWordParagraph
                : null,
            next:
                index + 1 < blocks.length &&
                    blocks[index + 1] is LegacyWordParagraph
                ? blocks[index + 1] as LegacyWordParagraph
                : null,
          );
        case LegacyWordTable():
          _table(block);
      }
    }
  }

  void _prepareNumbering(List<LegacyWordBlock> blocks) {
    if (numberingDefinitions.isEmpty) return;
    final resolved = LegacyWordNumberingResolver(
      numberingDefinitions,
    ).resolve(blocks);
    for (final entry in resolved.entries) {
      _item();
      final value = entry.value;
      if (value == null) {
        _markers[entry.key] = const _HtmlListMarker(unsupported: true);
        continue;
      }
      final text = _listText(value);
      _markerUnits += text?.length ?? 0;
      if (_markerUnits > 4 * 1024 * 1024) {
        throw const FormatException(
          'Word numbering labels exceed the preview limit.',
        );
      }
      _markers[entry.key] = _HtmlListMarker(
        text: text,
        level: value.level,
        unsupported: text == null,
        ambiguousContinuation: value.approximate,
      );
    }
  }

  String? _listText(LegacyWordResolvedNumbering marker) {
    final level = marker.level;
    if (level.format == 'bullet') return level.text;
    const formats = {
      // A level without its own number sequence can still carry literal text
      // and placeholders referencing numbered ancestor levels (MS-DOC 2.4.6.3).
      'none',
      'decimal',
      'decimalZero',
      'upperRoman',
      'lowerRoman',
      'upperLetter',
      'lowerLetter',
    };
    if (!formats.contains(level.format)) return null;
    final output = StringBuffer();
    for (var i = 0; i < level.text.length; i++) {
      final unit = level.text.codeUnitAt(i);
      if (unit != 37 ||
          i + 1 == level.text.length ||
          level.text.codeUnitAt(i + 1) < 49 ||
          level.text.codeUnitAt(i + 1) > 57) {
        output.writeCharCode(unit);
        continue;
      }
      final index = level.text.codeUnitAt(++i) - 49;
      final sourceFormat = marker.referenceFormats[index];
      if (sourceFormat == null || index > level.level) return null;
      final value = marker.referenceNumbers[index];
      final number = sourceFormat == 'none' || sourceFormat == 'bullet'
          ? ''
          : value == null
          ? null
          : _listNumber(
              value,
              level.legal && sourceFormat != 'decimalZero'
                  ? 'decimal'
                  : sourceFormat,
            );
      if (number == null) return null;
      if (number.length > 4096 - output.length) {
        throw const FormatException(
          'Word numbering label exceeds the preview limit.',
        );
      }
      output.write(number);
    }
    return output.toString();
  }

  static String? _listNumber(int value, String format) {
    if (format == 'decimal') return '$value';
    if (format == 'decimalZero') return value.toString().padLeft(2, '0');
    if (format == 'upperLetter' || format == 'lowerLetter') {
      if (value < 1) return null;
      // Word list letters repeat the same letter after Z: AA, BB, ... ZZ,
      // AAA. This differs from spreadsheet-column bijective base-26 labels.
      final repeats = (value - 1) ~/ 26 + 1;
      if (repeats > 1024) return null;
      final first = format == 'lowerLetter' ? 97 : 65;
      return String.fromCharCode(first + (value - 1) % 26) * repeats;
    }
    if (format != 'upperRoman' && format != 'lowerRoman') return null;
    if (value < 1 || value > 3999) return null;
    const symbols = [
      (1000, 'M'),
      (900, 'CM'),
      (500, 'D'),
      (400, 'CD'),
      (100, 'C'),
      (90, 'XC'),
      (50, 'L'),
      (40, 'XL'),
      (10, 'X'),
      (9, 'IX'),
      (5, 'V'),
      (4, 'IV'),
      (1, 'I'),
    ];
    final result = StringBuffer();
    var remaining = value;
    for (final (number, symbol) in symbols) {
      while (remaining >= number) {
        result.write(symbol);
        remaining -= number;
      }
    }
    final text = result.toString();
    return format == 'lowerRoman' ? text.toLowerCase() : text;
  }

  _HtmlDecoration _paragraphDecoration(
    LegacyWordParagraph paragraph,
    LegacyWordParagraph? previous,
    LegacyWordParagraph? next,
  ) {
    final style = paragraph.style;
    final css = <String>[];
    var attributes = '';
    final shading = _shading(style.shading);
    css.addAll(shading.css);
    attributes += shading.attributes;
    final joinsPrevious =
        previous != null &&
        previous.endCp == paragraph.startCp &&
        _sameBorderGroup(previous.style, style);
    final joinsNext =
        next != null &&
        paragraph.endCp == next.startCp &&
        _sameBorderGroup(style, next.style);
    var approximateBorder = false;
    for (final side in const [
      LegacyWordBorderSide.top,
      LegacyWordBorderSide.left,
      LegacyWordBorderSide.bottom,
      LegacyWordBorderSide.right,
    ]) {
      var border = style.borders[side];
      if (side == LegacyWordBorderSide.top && joinsPrevious) {
        border = style.borders[LegacyWordBorderSide.between];
        css.add('border-top:none');
      }
      if (side == LegacyWordBorderSide.bottom && joinsNext) {
        css.add('border-bottom:none');
        continue;
      }
      if (border == null) continue;
      if (border.widthEighthPoints < 0 ||
          border.widthEighthPoints > 255 ||
          border.spacingPoints < 0 ||
          border.spacingPoints > 31) {
        throw const FormatException('Invalid Word preview border dimensions.');
      }
      final line = switch (border.style) {
        'none' || 'nil' => 'none',
        'single' || 'thick' => 'solid',
        'double' => 'double',
        'dotted' => 'dotted',
        'dashed' || 'dashSmallGap' || 'dotDash' || 'dotDotDash' => 'dashed',
        _ => null,
      };
      if (line == null) {
        approximateBorder = true;
        continue;
      }
      if (border.shadow ||
          border.frame ||
          const {
            'dashSmallGap',
            'dotDash',
            'dotDotDash',
          }.contains(border.style)) {
        approximateBorder = true;
      }
      final color = border.colorHex;
      css.add(
        'border-${side.name}:${border.widthEighthPoints / 8}pt $line '
        '${color != null && _color.hasMatch(color) ? '#$color' : 'currentColor'}',
      );
      if (line != 'none' && border.spacingPoints > 0) {
        css.add('padding-${side.name}:${border.spacingPoints}pt');
      }
    }
    // Word's paragraph "bar" border has no effect. Do not confuse it with
    // the distinct, active bar-tab alignment. Grouping also depends on source
    // properties outside this model, so between borders are explicitly partial.
    if (style.borders.containsKey(LegacyWordBorderSide.between)) {
      approximateBorder = true;
    }
    if (approximateBorder) attributes += ' data-word-border="approximate"';
    final tabs = style.tabs;
    if (tabs.length > 64) {
      throw const FormatException('Word preview has too many tab stops.');
    }
    if (tabs.isNotEmpty) {
      final interval = tabs.first.positionTwips;
      var regular = interval > 0;
      var last = -32769;
      for (var i = 0; i < tabs.length; i++) {
        final stop = tabs[i];
        if (stop.positionTwips < -31680 ||
            stop.positionTwips > 31680 ||
            stop.positionTwips <= last) {
          throw const FormatException('Invalid Word preview tab stops.');
        }
        last = stop.positionTwips;
        regular =
            regular &&
            stop.positionTwips == interval * (i + 1) &&
            stop.alignment == LegacyWordTabAlignment.left &&
            stop.leader == LegacyWordTabLeader.none;
      }
      if (regular) css.add('tab-size:${_twips(interval)}pt');
      attributes += regular
          ? ' data-word-tabs="uniform-approximation"'
          : ' data-word-tabs="approximate"';
    }
    return _HtmlDecoration(css, attributes);
  }

  static bool _sameBorderGroup(
    LegacyWordParagraphStyle a,
    LegacyWordParagraphStyle b,
  ) {
    if (a.borders.isEmpty ||
        b.borders.isEmpty ||
        a.styleIndex != b.styleIndex ||
        a.leftIndentTwips != b.leftIndentTwips ||
        a.rightIndentTwips != b.rightIndentTwips ||
        a.firstLineIndentTwips != b.firstLineIndentTwips) {
      return false;
    }
    for (final side in LegacyWordBorderSide.values) {
      if (side == LegacyWordBorderSide.bar) continue;
      final first = a.borders[side], second = b.borders[side];
      if (first == null || second == null) {
        if (first != second) return false;
      } else if (first.style != second.style ||
          first.rawType != second.rawType ||
          first.widthEighthPoints != second.widthEighthPoints ||
          first.colorHex != second.colorHex ||
          first.spacingPoints != second.spacingPoints ||
          first.shadow != second.shadow ||
          first.frame != second.frame) {
        return false;
      }
    }
    return true;
  }

  static _HtmlDecoration _shading(LegacyWordShading? shading) {
    if (shading == null || shading.pattern == 'nil') {
      return const _HtmlDecoration([], '');
    }
    final foreground = shading.foregroundHex;
    final background = shading.backgroundHex;
    final fg = foreground != null && _color.hasMatch(foreground)
        ? foreground
        : null;
    final bg = background != null && _color.hasMatch(background)
        ? background
        : null;
    String? color;
    if (shading.pattern == 'solid') {
      color = fg;
    } else if (shading.pattern == 'clear') {
      color = bg;
    } else {
      final match = RegExp(
        r'^pct([0-9]{1,2})$',
      ).firstMatch(shading.pattern ?? '');
      if (match != null && fg != null && bg != null) {
        final percent = int.parse(match.group(1)!);
        final output = StringBuffer();
        for (var i = 0; i < 6; i += 2) {
          final front = int.parse(fg.substring(i, i + 2), radix: 16);
          final back = int.parse(bg.substring(i, i + 2), radix: 16);
          output.write(
            ((front * percent + back * (100 - percent)) / 100)
                .round()
                .toRadixString(16)
                .padLeft(2, '0'),
          );
        }
        color = output.toString();
      } else {
        color = bg;
      }
    }
    return _HtmlDecoration(
      [if (color != null) 'background-color:#$color'],
      shading.pattern == 'solid' || shading.pattern == 'clear'
          ? ''
          : ' data-word-shading="approximate"',
    );
  }

  void _paragraph(
    LegacyWordParagraph paragraph, {
    LegacyWordParagraph? previous,
    LegacyWordParagraph? next,
  }) {
    _item();
    final style = paragraph.style;
    final heading = style.headingLevel;
    final tag = heading != null && heading >= 1 && heading <= 6
        ? 'h$heading'
        : 'p';
    var attributes = heading != null && heading >= 7 && heading <= 9
        ? ' role="heading" aria-level="$heading"'
        : '';
    if (paragraph.formattingRevision?.marked == true) {
      attributes +=
          ' data-word-formatting-revision="paragraph" title="Paragraph formatting changed"';
    }
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
      if (style.layout.rightToLeft) 'direction:rtl',
      if (style.layout.rightToLeft) 'unicode-bidi:plaintext',
      if (style.layout.suppressAutoHyphens) 'hyphens:none',
      'widows:${style.layout.widowControl ? 2 : 1}',
      'orphans:${style.layout.widowControl ? 2 : 1}',
    ];
    final marker = _markers[paragraph];
    if (marker?.unsupported == true ||
        (marker == null && style.listId != null && style.listId != 0)) {
      attributes += ' data-word-numbering="unsupported"';
    } else if (marker?.ambiguousContinuation == true) {
      attributes += ' data-word-numbering="instance-approximation"';
    }
    final decoration = _paragraphDecoration(paragraph, previous, next);
    css.addAll(decoration.css);
    attributes += decoration.attributes;
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
    final images = _media.within(paragraph.startCp, paragraph.endCp);
    final visible =
        paragraph.runs.any((run) => !run.style.hidden && run.text.isNotEmpty) ||
        images.isNotEmpty;
    if (visible &&
        marker != null &&
        marker.text != null &&
        marker.text!.isNotEmpty &&
        !marker.level!.characterStyle.hidden) {
      final level = marker.level!;
      _write(
        '<span data-word-list-label="true" style="text-indent:0;'
        'text-align:${switch (level.markerAlignment) {
          LegacyWordAlignment.center => 'center',
          LegacyWordAlignment.right => 'right',
          _ => 'left',
        }};">',
      );
      _run(
        LegacyWordRun(
          startCp: paragraph.startCp,
          endCp: paragraph.startCp,
          text: marker.text!,
          style: level.characterStyle,
        ),
      );
      _write('</span>');
      switch (level.suffix) {
        case LegacyWordListSuffix.tab:
          _write('\t');
        case LegacyWordListSuffix.space:
          _write(' ');
        case LegacyWordListSuffix.nothing:
          break;
      }
    }
    var imageIndex = 0;
    for (final run in paragraph.runs) {
      _item();
      while (imageIndex < images.length &&
          images[imageIndex].cp < run.startCp) {
        _image(images[imageIndex++]);
        hasVisibleText = true;
      }
      if (run.style.hidden) {
        // Source presentation already includes field privacy. Also respect a
        // hidden public-model run even if its media metadata is inconsistent.
        while (imageIndex < images.length &&
            images[imageIndex].cp < run.endCp) {
          imageIndex++;
        }
        continue;
      }
      var textStart = 0;
      while (imageIndex < images.length && images[imageIndex].cp < run.endCp) {
        final image = images[imageIndex++];
        final offset = image.cp - run.startCp;
        if (offset < textStart ||
            offset > run.text.length ||
            run.text.length != run.endCp - run.startCp ||
            (offset > 0 &&
                offset < run.text.length &&
                run.text.codeUnitAt(offset - 1) >= 0xd800 &&
                run.text.codeUnitAt(offset - 1) <= 0xdbff)) {
          throw const FormatException('Ambiguous Word preview image anchor.');
        }
        if (offset > textStart) {
          _run(run, text: run.text.substring(textStart, offset));
        }
        _image(image);
        hasVisibleText = true;
        textStart = offset;
      }
      if (textStart < run.text.length) {
        _run(run, text: run.text.substring(textStart));
        hasVisibleText = true;
      }
    }
    while (imageIndex < images.length) {
      _image(images[imageIndex++]);
      hasVisibleText = true;
    }
    final mark = paragraph.mark;
    if (mark != null && !mark.style.hidden && (mark.inserted || mark.deleted)) {
      final kind = mark.deleted ? 'deleted' : 'inserted';
      _write(
        '<span data-word-paragraph-mark="$kind" title="Paragraph mark $kind" '
        'style="${mark.deleted ? 'background-color:#ffe8e8;text-decoration:line-through' : 'background-color:#e5f5e5;text-decoration:underline'};">¶</span>',
      );
      hasVisibleText = true;
    }
    if (!hasVisibleText) _write('<br>');
    _write('</$tag>');
  }

  void _run(LegacyWordRun run, {String? text}) {
    final style = run.style;
    final symbol = run.symbol;
    final symbolCode = symbol?.hexadecimalCode;
    if (symbol != null &&
        (run.text.isEmpty ||
            run.text.codeUnits.any((value) => value != 0xfffc))) {
      throw const FormatException('Invalid Word symbol preview text.');
    }
    final kerning = style.kerningThresholdHalfPoints;
    if (kerning < 0 || kerning > 3276) {
      throw const FormatException('Invalid Word preview kerning threshold.');
    }
    final unresolvedKerning = kerning > 0 && style.fontSizeHalfPoints == null;
    final css = <String>[
      if (unresolvedKerning)
        'font-kerning:auto'
      else
        'font-kerning:${kerning == 0 || style.fontSizeHalfPoints! < kerning ? 'none' : 'normal'}',
      if (style.bold) 'font-weight:bold',
      if (style.italic) 'font-style:italic',
      if (style.smallCaps) 'font-variant:small-caps',
      if (style.allCaps) 'text-transform:uppercase',
      if (style.strike || style.doubleStrike) 'text-decoration:line-through',
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
    final font = symbol?.fontName ?? style.fontName;
    if (font != null && font.isNotEmpty && font.length <= 256) {
      // Hex escapes inside one quoted CSS string cannot terminate it or
      // introduce a url(), even if the original font name contains quotes.
      final escapedFont = font.runes
          .map((rune) => '\\${rune.toRadixString(16)} ')
          .join();
      css.add("font-family:'$escapedFont'");
    }
    if (run.formattingRevision?.marked == true) {
      _write(
        '<span data-word-formatting-revision="character" '
        'title="Character formatting changed" style="outline:1px dotted #805a00;">',
      );
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
    if (css.isNotEmpty) {
      _write(
        '<span${symbolCode == null ? '' : ' data-word-symbol="$symbolCode"'}${unresolvedKerning ? ' data-word-kerning="threshold-unresolved" data-word-kerning-threshold-half-points="$kerning"' : ''} style="${css.join(';')}">',
      );
    }
    if (style.underline) {
      final kind = style.underlineStyle;
      final line = switch (kind) {
        'double' => 'double',
        'dotted' || 'dottedHeavy' => 'dotted',
        'dash' ||
        'dotDash' ||
        'dotDotDash' ||
        'dashedHeavy' ||
        'dashDotHeavy' ||
        'dashDotDotHeavy' ||
        'dashLong' ||
        'dashLongHeavy' => 'dashed',
        'wave' || 'wavyHeavy' || 'wavyDouble' => 'wavy',
        _ => 'solid',
      };
      final heavy = const {
        'thick',
        'dottedHeavy',
        'dashedHeavy',
        'dashDotHeavy',
        'dashDotDotHeavy',
        'wavyHeavy',
        'dashLongHeavy',
      }.contains(kind);
      final approximate = !const {
        null,
        'single',
        'double',
        'dotted',
        'dash',
        'wave',
      }.contains(kind);
      // Keep this separate from the surrounding strike decoration: CSS gives
      // one decoration style to every line declared on the same element.
      _write(
        '<span${approximate ? ' data-word-underline="approximate"' : ''} '
        'style="text-decoration:underline;text-decoration-style:$line;'
        '${heavy ? 'text-decoration-thickness:0.12em;' : ''}">',
      );
    }
    var visibleText = text ?? run.text;
    if (symbol != null) {
      final code = symbol.characterCode;
      // Font-specific UTF-16 values need not be legal standalone HTML text.
      // Preserve their operand in metadata and keep an opaque glyph position.
      if (code >= 0x20 && code < 0xfffe && (code < 0xd800 || code > 0xdfff)) {
        visibleText = String.fromCharCode(code) * visibleText.length;
      }
    }
    _text(visibleText);
    if (style.underline) _write('</span>');
    if (css.isNotEmpty) _write('</span>');
    if (run.inserted) _write('</ins>');
    if (run.deleted) _write('</del>');
    if (run.formattingRevision?.marked == true) _write('</span>');
  }

  void _table(LegacyWordTable table) {
    if (++_tableDepth > 63) {
      throw const FormatException('Word tables are nested too deeply.');
    }
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
        final blocks = <LegacyWordBlock>[];
        for (final cell in source) {
          for (final block in cell.blocks) {
            _item();
            blocks.add(block);
          }
        }
        final continues = source.every(
          (cell) => cell.verticalMergeContinue && !cell.verticalMergeStart,
        );
        final key = (start, span);
        final previous = active[key];
        if (continues && previous != null) {
          previous.rowSpan++;
          previous.blocks.addAll(blocks);
          nextActive[key] = previous;
          continue;
        }
        final cell = _HtmlCell(
          blocks: blocks,
          isHeader: row.isHeader,
          columnSpan: span,
          widthTwips: source.every((cell) => cell.widthTwips != null)
              ? source.fold<int>(0, (sum, cell) => sum + cell.widthTwips!)
              : null,
          shading: first.shading,
          source: first,
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
    final origin = table.rows.isEmpty
        ? 0
        : table.rows
              .map((row) => row.originTwips)
              .reduce((a, b) => a < b ? a : b);
    if (origin < -31680 || origin > 31680) {
      throw const FormatException('Invalid Word preview table origin.');
    }
    final completeWidths =
        table.rows.isNotEmpty &&
        table.rows.every(
          (row) => row.cells.every(
            (cell) => cell.widthTwips != null && cell.widthTwips! > 0,
          ),
        );
    final width = completeWidths
        ? table.rows
                  .map(
                    (row) =>
                        row.originTwips +
                        row.cells.fold<int>(
                          0,
                          (sum, cell) => sum + cell.widthTwips!,
                        ),
                  )
                  .reduce((a, b) => a > b ? a : b) -
              origin
        : null;
    final alignment = switch (table.alignment) {
      LegacyWordAlignment.left => 'margin-inline-start:${_twips(origin)}pt;',
      LegacyWordAlignment.center =>
        'margin-inline-start:auto;margin-inline-end:auto;',
      LegacyWordAlignment.right =>
        'margin-inline-start:auto;margin-inline-end:0;',
      _ => throw const FormatException('Invalid Word preview table alignment.'),
    };
    final unequalOrigins = table.rows.any((row) => row.originTwips != origin);
    _write(
      '<table${table.rightToLeft ? ' dir="rtl"' : ''}'
      '${unequalOrigins ? ' data-word-table-grid="approximate"' : ''}'
      ' style="border-collapse:collapse;table-layout:${table.autoFit ? 'auto' : 'fixed'};'
      '$alignment${width == null ? '' : 'width:${_twips(width)}pt;'}"><tbody>',
    );
    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex], sourceRow = table.rows[rowIndex];
      final height = sourceRow.heightTwips;
      if (height != null && (height < -31680 || height > 31680)) {
        throw const FormatException('Invalid Word preview row height.');
      }
      _write(
        '<tr${height != null && height < 0 ? ' data-word-row-height="approximate-exact"' : ''}'
        ' style="${sourceRow.cantSplit == true ? 'break-inside:avoid;' : ''}'
        '${height == null || height == 0 ? '' : 'height:${_twips(height.abs())}pt;'}">',
      );
      for (final cell in row) {
        final tag = cell.isHeader ? 'th' : 'td';
        final width = cell.widthTwips;
        final shading = _shading(cell.shading);
        final decoration = _tableCellDecoration(
          cell.source,
          rightToLeft: table.rightToLeft,
        );
        _write(
          '<$tag${cell.isHeader ? ' scope="col"' : ''}'
          '${cell.columnSpan > 1 ? ' colspan="${cell.columnSpan}"' : ''}'
          '${cell.rowSpan > 1 ? ' rowspan="${cell.rowSpan}"' : ''}'
          '${shading.attributes}${decoration.attributes}'
          ' style="${decoration.css.join(';')};'
          '${shading.css.isEmpty ? '' : '${shading.css.join(';')};'}'
          '${width != null && width > 0 ? 'width:${_twips(width)}pt;' : ''}">',
        );
        _blocks(cell.blocks);
        _write('</$tag>');
      }
      _write('</tr>');
    }
    _write('</tbody></table>');
    _tableDepth--;
  }

  _HtmlDecoration _tableCellDecoration(
    LegacyWordTableCell cell, {
    required bool rightToLeft,
  }) {
    final format = cell.formatting;
    final alignment = format.verticalAlignment ?? LegacyWordCellAlignment.top;
    final css = <String>[
      'vertical-align:${alignment == LegacyWordCellAlignment.center ? 'middle' : alignment.name}',
      if (format.noWrap != null)
        'white-space:${format.noWrap! ? 'pre' : 'pre-wrap'}',
      if (format.noWrap == true) 'overflow-wrap:normal',
    ];
    var approximate = false;
    String physical(String side) => !rightToLeft
        ? side
        : side == 'left'
        ? 'right'
        : side == 'right'
        ? 'left'
        : side;
    for (final entry in format.borders.entries) {
      final side = entry.key, border = entry.value;
      if (side.index >= 4) {
        if (border.style != 'none' && border.style != 'nil') approximate = true;
        continue;
      }
      if (border.widthEighthPoints < 0 || border.widthEighthPoints > 255) {
        throw const FormatException('Invalid Word cell border width.');
      }
      final line = switch (border.style) {
        'none' || 'nil' => 'none',
        'single' || 'thick' => 'solid',
        'double' => 'double',
        'dotted' => 'dotted',
        'dashed' || 'dashSmallGap' || 'dotDash' || 'dotDotDash' => 'dashed',
        _ => null,
      };
      if (line == null) {
        approximate = true;
      } else {
        css.add(
          'border-${physical(side.name)}:${border.widthEighthPoints / 8}pt $line '
          '${border.colorHex != null && _color.hasMatch(border.colorHex!) ? '#${border.colorHex}' : 'currentColor'}',
        );
      }
      if (border.shadow ||
          border.frame ||
          const {
            'dotDash',
            'dotDotDash',
            'dashSmallGap',
          }.contains(border.style)) {
        approximate = true;
      }
    }
    for (final entry in format.margins.entries) {
      if (entry.key.index >= 4) continue;
      final margin = entry.value ?? 0;
      if (margin < 0 || margin > 31680) {
        throw const FormatException('Invalid Word cell margin.');
      }
      css.add('padding-${physical(entry.key.name)}:${_twips(margin)}pt');
    }
    final direction = format.textDirection;
    var attributes = approximate ? ' data-word-border="approximate"' : '';
    if (direction != null && direction != LegacyWordCellTextDirection.lrTb) {
      // Preserve an explicit marker until the preview has a verified vertical
      // layout engine. A generic CSS rotation cannot reproduce Word's modes.
      attributes += ' data-word-cell-text-direction="${direction.name}"';
    }
    if (format.fitText == true) {
      attributes += ' data-word-cell-fit-text="approximate"';
    }
    if (format.hideMark == true) {
      attributes += ' data-word-cell-hide-mark="approximate"';
    }
    return _HtmlDecoration(css, attributes);
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
            .replaceAll('\f', '<br style="break-after:page;">')
            .replaceAll('\u000e', '<br style="break-after:column;">'),
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
    if (!measureOnly) _buffer.write(value);
  }
}

class _HtmlCell {
  _HtmlCell({
    required this.blocks,
    required this.isHeader,
    required this.columnSpan,
    required this.widthTwips,
    required this.shading,
    required this.source,
  });
  final LegacyWordTableCell source;
  final List<LegacyWordBlock> blocks;
  final bool isHeader;
  final int columnSpan;
  final int? widthTwips;
  final LegacyWordShading? shading;
  var rowSpan = 1;
}

class _HtmlListMarker {
  const _HtmlListMarker({
    this.text,
    this.level,
    this.unsupported = false,
    this.ambiguousContinuation = false,
  });
  final String? text;
  final LegacyWordNumberingLevel? level;
  final bool unsupported;
  final bool ambiguousContinuation;
}

class _HtmlDecoration {
  const _HtmlDecoration(this.css, this.attributes);
  final List<String> css;
  final String attributes;
}
