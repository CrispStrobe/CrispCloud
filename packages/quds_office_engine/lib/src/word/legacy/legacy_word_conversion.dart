import 'dart:typed_data';
import 'package:legacy_doc_parser/legacy_doc_parser.dart'
    show LegacyWordConversionException, LegacyWordConversionIssue;
export 'package:legacy_doc_parser/legacy_doc_parser.dart';

/// A prepared copy whose destination is selected by the host.
class LegacyWordDocxCopy {
  const LegacyWordDocxCopy({required this.fileName, required this.bytes});
  final String fileName;
  final Uint8List bytes;
}

String suggestedLegacyWordDocxName(String sourceName) {
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
  return '${shortStem.isEmpty ? 'Document' : shortStem} (text).docx';
}

/// Only a filename is accepted. Storage placement belongs to the captured
/// source, never to user-supplied directories or the currently active pane.
String validateLegacyWordDocxName(String name) {
  final trimmed = name.trim();
  if (trimmed.length <= 5 ||
      trimmed.length > 255 ||
      !trimmed.toLowerCase().endsWith('.docx') ||
      trimmed == '.docx' ||
      RegExp(r'[<>:"/\\|?*\x00-\x1f]').hasMatch(trimmed)) {
    throw const LegacyWordConversionException(
      LegacyWordConversionIssue.invalidName,
    );
  }
  return trimmed;
}
