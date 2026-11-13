import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Reserve enough room for an ordinary formatted size at the actual list font.
double minimumFileSizeColumnWidth(
  BuildContext context, {
  required double fontSize,
  String? fontFamily,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: '1023.9 GiB',
      style: TextStyle(
        fontSize: math.max(9, fontSize - 1),
        fontFamily: fontFamily,
      ),
    ),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final width = math.max(80.0, painter.width.ceilToDouble() + 8);
  painter.dispose();
  return width;
}
