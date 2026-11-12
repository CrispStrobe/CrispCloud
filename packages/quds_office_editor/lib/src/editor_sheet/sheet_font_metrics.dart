import 'package:flutter/painting.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import '../embed/office_host_fonts.dart';

/// Measures native Normal-style digits with known, loaded Quds host faces.
///
/// Call OfficeHostFonts.ensureRegistered before opening a workbook, or refresh
/// the controller after registration. Unknown families return null instead of
/// labeling an implicit platform fallback as the requested face. A host with
/// its own font registry can supply a SmlColumnMetricsResolver to the controller.
abstract final class SheetFontMetrics {
  static SmlColumnMetrics? measure(SmlNormalFont normalFont) {
    final family = OfficeHostFonts.registeredFamily(
      normalFont.family,
      italic: normalFont.italic,
    );
    if (family == null) return null;
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    );
    var maximum = 0.0;
    try {
      for (var digit = 0; digit <= 9; digit++) {
        painter.text = TextSpan(
          text: '$digit',
          style: TextStyle(
            fontFamily: family,
            fontSize: normalFont.sizePoints * 96 / 72,
            fontWeight: normalFont.bold ? FontWeight.bold : FontWeight.normal,
            fontStyle: normalFont.italic ? FontStyle.italic : FontStyle.normal,
          ),
        );
        painter.layout();
        if (painter.width > maximum) maximum = painter.width;
      }
    } finally {
      painter.dispose();
    }
    if (!maximum.isFinite || maximum.round() <= 0) return null;
    return SmlColumnMetrics(
      maximumDigitWidthPx: maximum.round(),
      resolvedFontFamily: family,
    );
  }
}
