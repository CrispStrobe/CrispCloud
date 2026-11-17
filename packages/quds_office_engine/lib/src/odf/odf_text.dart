import 'dart:convert';

import '../xml/xml_node.dart';
import '../xml/xml_writer.dart';

/// Namespace for ODF paragraph text and explicit whitespace elements.
const odfTextNamespace = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';

/// Namespace for ODF office structure and annotation stories.
const odfOfficeNamespace = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';

/// Namespace for ODF table structure and covered cells.
const odfTableNamespace = 'urn:oasis:names:tc:opendocument:xmlns:table:1.0';

/// Writes authored text without ODF's literal XML whitespace collapse.
///
/// Repeated and edge spaces are explicit, including run boundaries where the
/// following run may be empty or styled differently. Internal single spaces can
/// stay literal. CRLF and CR are normalized to logical LF breaks.
/// See ODF 1.3 Part 3, sections 6.1.2–6.1.5.
void writeOdfText(XmlWriter writer, String text) {
  var start = 0;
  var index = 0;
  while (index < text.length) {
    final unit = text.codeUnitAt(index);
    if (!_isWhitespace(unit)) {
      index++;
      continue;
    }
    if (index > start) writer.writeText(text.substring(start, index));
    if (unit == 0x20) {
      final first = index;
      while (index < text.length && text.codeUnitAt(index) == 0x20) {
        index++;
      }
      final count = index - first;
      if (count == 1 &&
          first > 0 &&
          index < text.length &&
          !_isWhitespace(text.codeUnitAt(first - 1)) &&
          !_isWhitespace(text.codeUnitAt(index))) {
        writer.writeText(' ');
      } else {
        writer.writeEmptyElement(
          's',
          prefix: 'text',
          attributes: count == 1 ? null : {'text:c': '$count'},
        );
      }
    } else {
      index++;
      if (unit == 0x0d &&
          index < text.length &&
          text.codeUnitAt(index) == 0x0a) {
        index++;
      }
      writer.writeEmptyElement(
        unit == 0x09 ? 'tab' : 'line-break',
        prefix: 'text',
      );
    }
    start = index;
  }
  if (start < text.length) writer.writeText(text.substring(start));
}

/// Repeated whitespace or decoded text exceeded the configured output budget.
class OdfTextLimitException extends FormatException {
  /// Creates a bounded ODF text-expansion failure.
  const OdfTextLimitException() : super('ODF text exceeds the content limit.');
}

/// Shared cumulative UTF-8 output budget, checked before whitespace allocation.
///
/// The generic extractor caps decoded paragraph/cell content at 16 MiB. This
/// includes separators inserted by [readOdfText] inside table cells, but excludes
/// wrappers and block separators added later by OfficeTextExtract.plainString.
/// Bounded search decodes the whole document with its caller-supplied byte limit,
/// including every emitted paragraph separator.
class OdfTextBudget {
  /// Creates a budget for one document or extraction operation.
  OdfTextBudget([this.maximumBytes = 16 * 1024 * 1024]) {
    if (maximumBytes < 0) {
      throw ArgumentError.value(maximumBytes, 'maximumBytes');
    }
  }

  /// Maximum UTF-8 bytes emitted by this decoder, including its separators.
  final int maximumBytes;
  int _used = 0;

  /// Bytes still available before allocating decoded whitespace.
  int get remaining => maximumBytes - _used;

  /// Reserves output bytes before their corresponding string is constructed.
  void consume(int bytes) {
    if (bytes < 0 || bytes > remaining) throw const OdfTextLimitException();
    _used += bytes;
  }
}

/// Whether [element] is an ODF text paragraph or heading.
bool isOdfParagraph(XmlElement element) =>
    element.namespaceUri == odfTextNamespace &&
    (element.localName == 'p' || element.localName == 'h');

/// Covered-cell stories are retained in the package but are not visible text.
bool isOdfCoveredCell(XmlElement element) =>
    element.namespaceUri == odfTableNamespace &&
    element.localName == 'covered-table-cell';

/// Annotations have their own story and are not part of visible body text.
bool isOdfAnnotation(XmlElement element) =>
    element.namespaceUri == odfOfficeNamespace &&
    element.localName == 'annotation';

/// Enumerates paragraph blocks without treating inline spans as word breaks.
Iterable<XmlElement> odfParagraphs(XmlElement element) sync* {
  if (isOdfCoveredCell(element) || isOdfAnnotation(element)) return;
  if (isOdfParagraph(element)) {
    yield element;
    return;
  }
  for (final child in element.childElements) {
    yield* odfParagraphs(child);
  }
}

/// Reads paragraphs in [element], retaining empty blocks and their separators.
String readOdfText(XmlElement element, OdfTextBudget budget) {
  final result = StringBuffer();
  var first = true;
  for (final paragraph in odfParagraphs(element)) {
    if (!first) {
      budget.consume(1);
      result.write('\n');
    }
    result.write(_readParagraph(paragraph, budget));
    first = false;
  }
  return result.toString();
}

String _readParagraph(XmlElement paragraph, OdfTextBudget budget) {
  final text = _ParagraphText(budget);
  void visit(XmlNode node) {
    if (node is XmlText) {
      text.literal(node.text);
      return;
    }
    if (node is XmlCdata) {
      text.literal(node.text);
      return;
    }
    if (node is XmlElement &&
        node.namespaceUri ==
            'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0') {
      if (node.localName == 'text-box') {
        // readOdfText accounts for the decoded bytes, including separators.
        text.decoded(readOdfText(node, budget));
      } else if (node.localName == 'frame') {
        for (final child in node.childElements) {
          visit(child);
        }
      }
      return;
    }
    if (node is! XmlElement || node.namespaceUri != odfTextNamespace) return;
    switch (node.localName) {
      case 's':
        final raw = node.getAttribute('c', namespaceUri: odfTextNamespace);
        final normalized = raw?.trim() ?? '1';
        if (!RegExp(r'^[+-]?[0-9]+$').hasMatch(normalized)) {
          throw const FormatException('Invalid ODF text:s count.');
        }
        final count = int.tryParse(normalized);
        if (count != null && count < 0) {
          throw const FormatException('Invalid ODF text:s count.');
        }
        if (count == null || count > budget.remaining) {
          throw const OdfTextLimitException();
        }
        text.spaces(count);
        return;
      case 'tab':
        text.explicit('\t');
        return;
      case 'line-break':
        text.explicit('\n');
        return;
      case 'ruby':
        for (final child in node.childElements) {
          if (child.localName == 'ruby-base' &&
              child.namespaceUri == odfTextNamespace) {
            visit(child);
          }
        }
        return;
      case 'ruby-text':
      case 'note':
      case 'soft-page-break':
        return;
    }
    for (final child in node.children) {
      visit(child);
    }
  }

  visit(paragraph);
  return text.toString();
}

bool _isWhitespace(int unit) =>
    unit == 0x20 || unit == 0x09 || unit == 0x0a || unit == 0x0d;

class _ParagraphText {
  _ParagraphText(this.budget);

  final OdfTextBudget budget;
  final _buffer = StringBuffer();
  bool _started = false;
  bool _pendingSpace = false;

  void literal(String value) {
    var index = 0;
    while (index < value.length) {
      if (_isWhitespace(value.codeUnitAt(index))) {
        _pendingSpace = true;
        index++;
        continue;
      }
      final start = index;
      while (index < value.length && !_isWhitespace(value.codeUnitAt(index))) {
        index++;
      }
      _flushSpace();
      _append(value.substring(start, index));
      _started = true;
    }
  }

  void explicit(String value) {
    _flushSpace();
    _append(value);
    _started = true;
  }

  void decoded(String value) {
    _flushSpace();
    _buffer.write(value);
    if (value.isNotEmpty) _started = true;
  }

  void spaces(int count) {
    _flushSpace();
    budget.consume(count);
    _buffer.write(' ' * count);
    // Even text:s with count zero separates literal whitespace sequences.
    _started = true;
  }

  void _flushSpace() {
    if (_pendingSpace && _started) _append(' ');
    _pendingSpace = false;
  }

  void _append(String value) {
    budget.consume(utf8.encode(value).length);
    _buffer.write(value);
  }

  @override
  String toString() => _buffer.toString();
}
