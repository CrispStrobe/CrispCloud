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
    final occurrence = (
      story.id,
      reference.headerAliases.isEmpty && reference.replicaAnchors.isEmpty
          ? null
          : _part,
    );
    if (first && !_renderedTextboxes.add(occurrence)) return;
    final shape = drawing.shape, text = shape?.text;
    final outside = _textboxOutsideBorderTwips(drawing);
    final left = drawing.leftTwips - outside;
    final top = drawing.topTwips - outside;
    final width = (drawing.rightTwips - drawing.leftTwips + 2 * outside) / 20;
    final height = (drawing.bottomTwips - drawing.topTwips + 2 * outside) / 20;
    if (outside != 0 &&
        [
          left,
          top,
          width * 20,
          height * 20,
        ].any((value) => value.abs() > 0x7fffffff)) {
      _tooComplex();
    }
    final prefix = reference.inHeaderFooter ? 'Header' : '';
    // Distinct package identifiers derive from the two original source
    // occurrences. The binary shape ID itself remains unchanged in the model
    // and evidence; a shared header shape never becomes an invented chain.
    final occurrenceSuffix =
        reference.headerAliases.any(
          (alias) => alias.shapeId == reference.shapeId,
        )
        ? 'Cp${drawing.anchorCp}'
        : '';
    final next = nextShape == null
        ? null
        : '_legacy${prefix}TextboxShape$nextShape';
    _mediaStart(drawing.presentation);
    _xml.add(
      '<w:pict><v:rect id="_legacy${prefix}TextboxShape${drawing.shapeId}$occurrenceSuffix" '
      'style="position:absolute;margin-left:${left / 20}pt;'
      'margin-top:${top / 20}pt;width:${width}pt;height:${height}pt;'
      '${_officeArtVmlPosition(drawing)}'
      'z-index:${drawing.behindText ? -1 : drawing.shapeId}',
    );
    if (next != null) _xml.add(';mso-next-textbox:#$next');
    if (shape != null) {
      if (shape.rotationFixed16.abs() > 360 * 65536) _tooComplex();
      if (shape.rotationFixed16 != 0) {
        _xml.add(';rotation:${shape.rotationFixed16 / 65536}');
      }
      if (shape.flipHorizontal || shape.flipVertical) {
        _xml.add(
          ';flip:${shape.flipHorizontal ? 'x' : ''}${shape.flipVertical ? ' y' : ''}',
        );
      }
    }
    // OfficeArt WrapText controls the text *inside* the shape. FSPA wrapping
    // controls surrounding document text and is written independently below.
    if (text?.wrapMode == 0 || text?.wrapMode == 1) {
      _xml.add(';mso-wrap-style:square');
    } else if (text?.wrapMode == 2) {
      _xml.add(';mso-wrap-style:none');
    }
    _xml.add('"');
    _textboxPaint(shape);
    if (shape?.layoutInCell case final layout?) {
      _xml.add(' o:allowincell="${layout ? 't' : 'f'}"');
    }
    _xml.add('><v:textbox');
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
    final wrap = switch (drawing.wrapMode) {
      1 => 'topAndBottom',
      3 => 'none',
      _ => 'square',
    };
    final side = ['both', 'left', 'right', 'largest'][drawing.wrapSide];
    _xml.add(
      '<w10:wrap xmlns:w10="urn:schemas-microsoft-com:office:word" '
      'type="$wrap" side="$side"${_officeArtVmlWrapOrigins(drawing)}/>'
      '</v:rect></w:pict>',
    );
    _mediaEnd(drawing.presentation);
    _count('textboxes');
    _evidenceRecords.add({
      'kind': 'textboxLayout',
      'shapeId': drawing.shapeId,
      'story': story.id,
      'insetsEmu': insets,
      'outsideBorderTwips': outside,
      'wrapDistancesEmu': _drawingMetadata(
        drawing,
      )['officeArtWrapDistancesEmu'],
      'anchor': anchor,
      'wrapMode': text?.wrapMode,
      'flow': text?.flow,
      'fontDirection': text?.fontDirection,
      'fitShapeToText': fit,
      'autoTextMargin': text?.autoTextMargin,
      'position': _drawingMetadata(drawing)['officeArtPosition'],
      'reason':
          'Editable source chain and explicit text layout retained; '
          'host reflow, automatic margins and arbitrary shape effects are not certified.',
    });
    limitations.add(LegacyWordConversionLimitation.partialFormatting);
  }

  int _textboxOutsideBorderTwips(LegacyWordDrawing drawing) {
    final shape = drawing.shape, line = shape?.line;
    final width = line?.widthEmu;
    // OfficeArt textbox rectangles orient from inside the outer half of a
    // simple border. VML text frames orient from the outer frame boundary.
    // Convert the frame only when the source border and transform are known;
    // retain the original FSPA in the model/evidence. See the native contract
    // and independent controls in doc/textbox-frame-borders.md.
    if (shape == null ||
        shape.type != 202 ||
        shape.unsupportedProperties.isNotEmpty ||
        (shape.sourceFlags & 0x37) != 0 ||
        shape.rotationFixed16 != 0 ||
        shape.flipHorizontal ||
        shape.flipVertical ||
        line?.enabled == false ||
        (line?.type ?? 0) != 0 ||
        (line?.compoundStyle ?? 0) != 0 ||
        (line?.dash ?? 0) != 0 ||
        shape.shadow?.enabled == true ||
        shape.text?.autoTextMargin == true ||
        (shape.position?.horizontalMode ?? 0) != 0 ||
        (shape.position?.verticalMode ?? 0) != 0 ||
        width == null ||
        width < 0 ||
        width > 0x0132f540 ||
        width % 635 != 0 ||
        [
          shape.text?.insetLeftEmu,
          shape.text?.insetTopEmu,
          shape.text?.insetRightEmu,
          shape.text?.insetBottomEmu,
        ].any((value) => value != null && value < 0)) {
      return 0;
    }
    // Binary placement is in whole twips. The outer half of an odd-width
    // border is truncated in that source coordinate space, e.g. 15 -> 7.
    return (width ~/ 635) ~/ 2;
  }

  void _textboxPaint(LegacyWordOfficeArtShape? shape) {
    bool color(String? value) =>
        value != null && RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(value);
    final fill = shape?.fill, line = shape?.line;
    if (shape == null || fill?.enabled == false) _xml.add(' filled="f"');
    if (color(fill?.color)) _xml.add(' fillcolor="#${fill!.color}"');
    if (shape == null || line?.enabled == false) _xml.add(' stroked="f"');
    if (color(line?.color)) _xml.add(' strokecolor="#${line!.color}"');
    // Preserve explicit widths. Materializing the source 0.75-point default
    // independently of the source/target frame-border convention caused an
    // accumulating native placement regression; see doc/textbox-stroke-defaults.md.
    final width = line?.widthEmu;
    if (width != null) {
      if (width < 0 || width > 0x0132f540) _tooComplex();
      _xml.add(' strokeweight="${width / 12700}pt"');
    }
  }
}
