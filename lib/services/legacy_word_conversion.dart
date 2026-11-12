import 'dart:typed_data';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import 'word_conversion_inspection.dart';

export 'package:legacy_doc_parser/legacy_doc_parser.dart';

/// A new Word package prepared from a legacy DOC/DOT.
/// It has no association with a writable destination; the caller must create
/// a separate file using its captured storage source.
class LegacyWordCopy {
  const LegacyWordCopy({
    required this.fileName,
    required this.bytes,
    this.extension = 'docx',
    this.converterName,
    this.inspection,
  });

  final String fileName;
  final Uint8List bytes;
  final String extension;
  final String? converterName;
  final WordConversionInspection? inspection;
  bool get isTextOnly => converterName == null;
}

/// Backwards-compatible name for callers of the original text-copy workflow.
typedef LegacyWordDocxCopy = LegacyWordCopy;

String suggestedLegacyWordDocxName(String sourceName) {
  return suggestedLegacyWordCopyName(sourceName, textOnly: true);
}

String suggestedLegacyWordCopyName(
  String sourceName, {
  bool textOnly = false,
  String extension = 'docx',
}) {
  final basename = sourceName.split(RegExp(r'[/\\]')).last;
  final stem = basename.replaceFirst(
    RegExp(r'\.(doc|dot)$', caseSensitive: false),
    '',
  );
  final safeStem = stem
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
      .trim();
  var end = safeStem.length > 200 ? 200 : safeStem.length;
  if (end < safeStem.length &&
      safeStem.codeUnitAt(end - 1) >= 0xd800 &&
      safeStem.codeUnitAt(end - 1) <= 0xdbff) {
    end--;
  }
  final shortStem = safeStem.substring(0, end);
  return '${shortStem.isEmpty ? 'Document' : shortStem} (${textOnly ? 'text' : 'converted'}).$extension';
}

/// Only a filename is accepted. Storage placement belongs to the captured
/// source, never to user-supplied directories or the currently active pane.
String validateLegacyWordDocxName(String name) {
  return validateLegacyWordCopyName(name);
}

String validateLegacyWordCopyName(String name, {String extension = 'docx'}) {
  final trimmed = name.trim();
  if (!const {'docx', 'docm'}.contains(extension) ||
      trimmed.length <= 5 ||
      trimmed.length > 255 ||
      !trimmed.toLowerCase().endsWith('.$extension') ||
      trimmed == '.$extension' ||
      RegExp(r'[<>:"/\\|?*\x00-\x1f]').hasMatch(trimmed)) {
    throw const LegacyWordConversionException(
      LegacyWordConversionIssue.invalidName,
    );
  }
  return trimmed;
}
