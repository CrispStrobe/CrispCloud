import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// Formats visible editor values using the current locale's digits and
/// separators. Pixel math and serialized values must remain locale-independent.
String formatEditorNumber(
  BuildContext context,
  num value, {
  int? fractionDigits,
}) {
  final format = NumberFormat.decimalPattern(
    Localizations.localeOf(context).toString(),
  );
  if (fractionDigits != null) {
    format
      ..minimumFractionDigits = fractionDigits
      ..maximumFractionDigits = fractionDigits;
  }
  return format.format(value);
}
