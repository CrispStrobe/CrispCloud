// SPDX-License-Identifier: MPL-2.0
part of 'conversion.dart';

extension _WordTextboxes on _StructuredWordWriter {
  void _textbox(
    LegacyWordTextboxReference reference,
    LegacyWordStory story,
    LegacyWordDrawing drawing, {
    required bool first,
    int? nextShape,
  }) {
    if (first && !_renderedTextboxes.add(story.id)) return;
    final shape = drawing.shape, text = shape?.text;
    final width = (drawing.rightTwips - drawing.leftTwips) / 20;
    final height = (drawing.bottomTwips - drawing.topTwips) / 20;
    final prefix = reference.inHeaderFooter ? 'Header' : '';
    final next = nextShape == null
        ? null
        : '_legacy${prefix}TextboxShape$nextShape';
    _mediaStart(drawing.presentation);
    _xml.add(
      '<w:pict><v:rect id="_legacy${prefix}TextboxShape${drawing.shapeId}" '
      'style="position:absolute;margin-left:${drawing.leftTwips / 20}pt;'
      'margin-top:${drawing.topTwips / 20}pt;width:${width}pt;height:${height}pt;'
      '${_officeArtVmlPosition(drawing)}${_officeArtVmlStyle(shape)}'
      'z-index:${drawing.behindText ? -1 : drawing.shapeId}',
    );
    if (next != null) _xml.add(';mso-next-textbox:#$next');
    // OfficeArt WrapText controls the text *inside* the shape. FSPA wrapping
    // controls surrounding document text and is written independently below.
    if (text?.wrapMode == 0 || text?.wrapMode == 1) {
      _xml.add(';mso-wrap-style:square');
    } else if (text?.wrapMode == 2) {
      _xml.add(';mso-wrap-style:none');
    }
    _xml.add('"');
    _xml.add(
      shape == null
          ? ' filled="f" stroked="f"'
          : _officeArtVmlAttributes(shape),
    );
    _xml.add('>');
    _officeArtVmlChildren(shape);
    _xml.add('<v:textbox');
    final insets = [
      text?.insetLeftEmu,
      text?.insetTopEmu,
      text?.insetRightEmu,
      text?.insetBottomEmu,
    ];
    if (insets.any((value) => value != null)) {
      if (insets.any((value) => (value?.abs() ?? 0) > 0x7fffffff)) {
        _tooComplex();
      }
      // Both MS-ODRAW and VML define 0.1/0.05/0.1/0.05-inch defaults.
      // A missing margin must not be silently converted to an explicit zero.
      const defaults = [91440, 45720, 91440, 45720];
      final values = [
        for (var index = 0; index < insets.length; index++)
          '${(insets[index] ?? defaults[index]) / 12700}pt',
      ];
      _xml.add(' inset="${values.join(',')}"');
    }
    final styles = <String>[];
    if (next != null) styles.add('mso-next-textbox:#$next');
    const anchors = [
      'top',
      'middle',
      'bottom',
      'top-center',
      'middle-center',
      'bottom-center',
      'top-baseline',
      'bottom-baseline',
      'top-center-baseline',
      'bottom-center-baseline',
    ];
    final anchor = text?.anchor;
    if (anchor != null && anchor >= 0 && anchor < anchors.length) {
      styles.add('v-text-anchor:${anchors[anchor]}');
    }
    final fit = text?.fitShapeToText;
    if (fit != null) styles.add('mso-fit-shape-to-text:${fit ? 't' : 'f'}');
    switch (text?.flow) {
      case 0 || 4:
        styles.add('layout-flow:horizontal');
      case 1:
        styles.addAll([
          'layout-flow:vertical',
          'mso-layout-flow-alt:top-to-bottom',
        ]);
      case 2:
        styles.addAll([
          'layout-flow:vertical',
          'mso-layout-flow-alt:bottom-to-top',
        ]);
      case 3 || 5:
        styles.add('layout-flow:vertical');
    }
    if (styles.isNotEmpty) _xml.add(' style="${styles.join(';')}"');
    _xml.add('><w:txbxContent>');
    if (first) {
      _withStory(story, _part, _xml, () => _blocks(story.blocks));
    } else {
      _xml.add('<w:p/>');
    }
    _xml.add('</w:txbxContent></v:textbox>');
    _officeArtVmlWrap(drawing);
    _xml.add('</v:rect></w:pict>');
    _mediaEnd(drawing.presentation);
    _count('textboxes');
    _evidenceRecords.add({
      'kind': 'textboxLayout',
      'shapeId': drawing.shapeId,
      'story': story.id,
      'insetsEmu': insets,
      'anchor': anchor,
      'wrapMode': text?.wrapMode,
      'flow': text?.flow,
      'fontDirection': text?.fontDirection,
      'fitShapeToText': fit,
      'autoTextMargin': text?.autoTextMargin,
      'reason':
          'Editable source chain and explicit text layout retained; '
          'host reflow, automatic margins and arbitrary shape effects are not certified.',
    });
    limitations.add(LegacyWordConversionLimitation.partialFormatting);
  }
}
