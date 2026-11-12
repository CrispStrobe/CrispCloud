import 'dart:typed_data';
<<<<<<< HEAD
import 'package:legacy_doc_parser/legacy_doc_parser.dart'
    show LegacyWordConversionException, LegacyWordConversionIssue;
export 'package:legacy_doc_parser/legacy_doc_parser.dart';
=======

import '../../opc/opc_archive.dart';
import '../../opc/content_types.dart';
import '../../xml/namespaces.dart';
import '../../xml/xml_writer.dart';

import 'legacy_word_document.dart';

/// A new DOCX prepared from the extracted main-story text of a legacy DOC/DOT.
part 'legacy_word_structured_conversion.dart';
>>>>>>> origin/feature/format-viewers-path-favorites-20261112

/// A prepared copy whose destination is selected by the host.
class LegacyWordDocxCopy {
  const LegacyWordDocxCopy({required this.fileName, required this.bytes});
  final String fileName;
  final Uint8List bytes;
}

<<<<<<< HEAD
=======
/// Backwards-compatible name for callers of the original text-copy workflow.


/// The built-in structured importer is deliberately a partial conversion.
/// These categories are presented before the user saves a separate copy.
enum LegacyWordConversionLimitation {
  partialFormatting,
  images,
  embeddedObjects,
  headersFooters,
  notesComments,
  revisions,
  macrosSignatures,
  fieldsLists,
}

class LegacyWordStructuredConversion {
  LegacyWordStructuredConversion({
    required Uint8List bytes,
    required List<LegacyWordConversionLimitation> limitations,
  }) : bytes = bytes.asUnmodifiableView(),
       limitations = List.unmodifiable(limitations);

  final Uint8List bytes;
  final List<LegacyWordConversionLimitation> limitations;
}

enum LegacyWordConversionIssue { invalidName, invalidText, tooComplex }

class LegacyWordConversionException implements Exception {
  const LegacyWordConversionException(this.issue);

  final LegacyWordConversionIssue issue;

  @override
  String toString() => switch (issue) {
    LegacyWordConversionIssue.invalidName =>
      'Enter a single filename ending in .docx.',
    LegacyWordConversionIssue.invalidText =>
      'The Word text contains invalid Unicode or XML characters.',
    LegacyWordConversionIssue.tooComplex =>
      'This document has too much text or too many breaks to convert safely.',
  };
}

const int kLegacyWordDocxXmlLimit = 16 * 1024 * 1024;
const int kLegacyWordDocxBreakLimit = 100000;

/// Converts only the extracted main story into a new, macro-free DOCX.
///
/// This is intentionally a text-copy conversion, not a format-preserving
/// binary Word importer. Formatting, page layout, images, objects, headers,
/// footnotes, comments, revision semantics, macros and signatures are omitted.
/// Paragraphs, tabs and Unicode text from the existing bounded parser survive.
/// No original OPC/CFB parts or relationships are reused or executed.
Uint8List convertLegacyWordToDocx(Uint8List bytes) {
  final text = extractLegacyWordText(bytes);
  _validateTextBudget(text);

  final writer = XmlWriter()..writeStartDocument();
  writer.writeStartElement(
    'document',
    prefix: 'w',
    namespaceUri:
        'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
  );
  writer.writeStartElement('body', prefix: 'w');
  for (final paragraph in text.split('\n')) {
    writer.writeStartElement('p', prefix: 'w');
    writer.writeStartElement('r', prefix: 'w');
    var first = true;
    for (final segment in paragraph.split('\t')) {
      if (!first) writer.writeEmptyElement('tab', prefix: 'w');
      first = false;
      writer.writeStartElement('t', prefix: 'w');
      writer.writeAttribute('xml:space', 'preserve');
      writer.writeText(segment);
      writer.writeEndElement();
    }
    writer.writeEndElement();
    writer.writeEndElement();
  }
  final package = OpcPackage.create(OpcPackageKind.word);
  package.getPart('/word/document.xml')!.writeText(writer.toXml());
  return package.save().asUnmodifiableView();
}

// Check before splitting text or building XML. A string with millions of tabs
// or empty paragraphs must not produce millions of intermediate objects.
void _validateTextBudget(String text) {
  var estimatedXmlBytes = 512;
  var breaks = 0;
  for (final rune in text.runes) {
    if (rune == 0x09 || rune == 0x0a) {
      breaks++;
      // Bound the extra paragraph/run/text tags, tab element and attributes.
      estimatedXmlBytes += 80;
    } else {
      if (rune < 0x20 ||
          (rune >= 0xd800 && rune <= 0xdfff) ||
          rune == 0xfffe ||
          rune == 0xffff) {
        throw const LegacyWordConversionException(
          LegacyWordConversionIssue.invalidText,
        );
      }
      estimatedXmlBytes += switch (rune) {
        0x26 => 5, // &amp;
        0x3c || 0x3e => 4, // &lt; / &gt;
        < 0x80 => 1,
        < 0x800 => 2,
        < 0x10000 => 3,
        _ => 4,
      };
    }
    if (breaks > kLegacyWordDocxBreakLimit ||
        estimatedXmlBytes > kLegacyWordDocxXmlLimit) {
      throw const LegacyWordConversionException(
        LegacyWordConversionIssue.tooComplex,
      );
    }
  }
}

>>>>>>> origin/feature/format-viewers-path-favorites-20261112
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
