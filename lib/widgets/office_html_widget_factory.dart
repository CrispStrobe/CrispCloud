import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

/// Images in parser-generated Office markup are self-contained data URIs.
///
/// The core HTML factory otherwise sends SVG bytes to Flutter's raster codec.
/// Keep this factory scoped to the bounded, fixed-tag Office renderer; it is
/// deliberately not used for arbitrary HTML documents or email content.
class OfficeHtmlWidgetFactory extends WidgetFactory {
  static const _svgPrefix = 'data:image/svg+xml;base64,';
  static const _maxDataUriLength = 4 * 1024 * 1024;

  @override
  Widget? buildImageWidget(BuildTree tree, ImageSource src) {
    final url = src.url;
    if (!url.startsWith('data:image/') || url.length > _maxDataUriLength) {
      return null;
    }
    if (!url.startsWith(_svgPrefix)) {
      if (url.startsWith('data:image/svg+xml')) return null;
      return super.buildImageWidget(tree, src);
    }
    try {
      final bytes = base64Decode(url.substring(_svgPrefix.length));
      return SvgPicture.memory(
        bytes,
        width: src.width,
        height: src.height,
        fit: BoxFit.fill,
        semanticsLabel: src.image?.alt ?? src.image?.title,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    } on FormatException {
      return null;
    }
  }
}
