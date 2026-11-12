// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'legacy_word_document.dart';

part 'legacy_word_structured_conversion.dart';
part 'opc_package_writer.dart';
part 'word_story_writer.dart';
part 'word_media_writer.dart';

/// DOCM is an explicit choice. The DOCX entry point never writes active VBA.
enum LegacyWordOutputFormat { docx, docm }

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
    this.format = LegacyWordOutputFormat.docx,
    Map<String, int> preservedCounts = const {},
    List<String> signatureEvidenceParts = const [],
  }) : bytes = Uint8List.fromList(bytes).asUnmodifiableView(),
       limitations = List.unmodifiable(limitations),
       preservedCounts = Map.unmodifiable(preservedCounts),
       signatureEvidenceParts = List.unmodifiable(signatureEvidenceParts);

  final Uint8List bytes;
  final List<LegacyWordConversionLimitation> limitations;
  final LegacyWordOutputFormat format;
  String get extension => format.name;

  /// Counts describe emitted package content, not complete source fidelity.
  final Map<String, int> preservedCounts;

  /// Original signature bytes stored as inert evidence, never as active OPC
  /// signature parts. A converted document must be verified or signed anew.
  final List<String> signatureEvidenceParts;
  bool get signatureValidityClaimed => false;
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
      'This document exceeds the conversion size or complexity limits.',
  };
}

const int kLegacyWordDocxXmlLimit = 16 * 1024 * 1024;
const int kLegacyWordDocxBreakLimit = 100000;
const int kLegacyWordPackageLimit = 64 * 1024 * 1024;

/// Backwards-compatible, macro-free structured DOCX conversion.
LegacyWordStructuredConversion convertLegacyWordToStructuredDocx(
  Uint8List bytes,
) => convertLegacyWord(bytes);

/// Converts a separate copy. No source bytes, file paths, or applications are
/// modified, and no fields, links, embedded objects, or macros are executed.
LegacyWordStructuredConversion convertLegacyWord(
  Uint8List bytes, {
  LegacyWordOutputFormat format = LegacyWordOutputFormat.docx,
}) => convertLegacyWordDocument(parseLegacyWordDocument(bytes), format: format);

/// Serializes an already parsed document using the same bounded writer.
LegacyWordStructuredConversion convertLegacyWordDocument(
  LegacyWordDocument document, {
  LegacyWordOutputFormat format = LegacyWordOutputFormat.docx,
}) => _convertStructuredDocument(document, format: format);

/// Explicit text-only conversion, retained for callers that choose to omit
/// structure and formatting. Referenced main-body text is read from the DOC.
Uint8List convertLegacyWordToDocx(Uint8List bytes) {
  final text = extractLegacyWordText(bytes);
  _validatePlainTextBudget(text);
  final xml = _BoundedWordXml();
  xml.add(_wordDocumentStart);
  var breaks = 0;
  for (final paragraph in text.split('\n')) {
    if (++breaks > kLegacyWordDocxBreakLimit) _tooComplex();
    xml.add('<w:p><w:r>');
    var first = true;
    for (final segment in paragraph.split('\t')) {
      if (!first) {
        if (++breaks > kLegacyWordDocxBreakLimit) _tooComplex();
        xml.add('<w:tab/>');
      }
      first = false;
      xml.add('<w:t xml:space="preserve">');
      xml.text(segment);
      xml.add('</w:t>');
    }
    xml.add('</w:r></w:p>');
  }
  xml.add('</w:body></w:document>');
  return (_OpcPackageWriter()
        ..addXml('word/document.xml', _docxMainType, xml)
        ..relate('', _officeDocumentRelationship, 'word/document.xml'))
      .encode();
}

void _validatePlainTextBudget(String text) {
  var size = 512;
  var breaks = 0;
  for (final rune in text.runes) {
    if (rune == 9 || rune == 10) {
      size += 80;
      breaks++;
    } else {
      if (rune < 32 ||
          (rune >= 0xd800 && rune <= 0xdfff) ||
          rune == 0xfffe ||
          rune == 0xffff) {
        throw const LegacyWordConversionException(
          LegacyWordConversionIssue.invalidText,
        );
      }
      size += switch (rune) {
        0x26 => 5,
        0x3c || 0x3e => 4,
        < 0x80 => 1,
        < 0x800 => 2,
        < 0x10000 => 3,
        _ => 4,
      };
    }
    if (breaks > kLegacyWordDocxBreakLimit || size > kLegacyWordDocxXmlLimit) {
      _tooComplex();
    }
  }
}

const _wordNamespace =
    'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _relationshipNamespace =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _officeDocumentRelationship = '$_relationshipNamespace/officeDocument';
const _docxMainType =
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml';
const _docmMainType = 'application/vnd.ms-word.document.macroEnabled.main+xml';
const _stylesType =
    'application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml';
const _wordDocumentStart =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<w:document $_wordNamespaces><w:body>';
const _wordNamespaces =
    'xmlns:w="$_wordNamespace" '
    'xmlns:r="$_relationshipNamespace" '
    'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
    'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
    'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture" '
    'xmlns:v="urn:schemas-microsoft-com:vml" '
    'xmlns:o="urn:schemas-microsoft-com:office:office"';
