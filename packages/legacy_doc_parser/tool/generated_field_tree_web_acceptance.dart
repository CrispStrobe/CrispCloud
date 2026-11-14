// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:xml/xml.dart';

import '../test/support/generated_field_tree_fixture.dart';

Map<String, Object?> verifyGeneratedFieldTreeCase(
  int seed, {
  bool ascii = false,
}) {
  final fixture = GeneratedFieldTreeCase(seed, ascii: ascii);
  List<int>? firstOutput;
  for (final split in [false, true]) {
    final source = fixture.bytes(splitPieces: split);
    final original = source.toList();
    final document = parseLegacyWordDocument(source);
    void check(bool condition, String name) {
      if (!condition) throw StateError('seed=$seed split=$split: $name');
    }

    check(
      document.plainText == fixture.expected,
      'display ${jsonEncode(document.plainText)} != ${jsonEncode(fixture.expected)}',
    );
    check(document.fields.length == fixture.fields.length, 'field count');
    final fields = {for (final f in document.fields) f.id: f};
    for (final expected in fixture.fields) {
      final actual = fields[expected.id]!;
      check(
        actual.startCp == expected.start &&
            actual.separatorCp == expected.separator &&
            actual.endCp == expected.end &&
            actual.parentId == expected.parent &&
            actual.instruction == expected.instruction &&
            actual.storedResult == expected.result &&
            actual.type == expected.type &&
            actual.privateResult == expected.privateResult,
        'field ${expected.id} source identity or cached text',
      );
    }
    final converted = convertLegacyWordDocument(document);
    final zip = ZipDecoder().decodeBytes(converted.bytes);
    final xml = XmlDocument.parse(
      utf8.decode(zip.findFile('word/document.xml')!.content),
    );
    final visible = generatedFieldTreeXmlText(xml);
    check(
      visible == fixture.expected,
      'DOCX display ${jsonEncode(visible)} != ${jsonEncode(fixture.expected)}',
    );
    if (firstOutput != null) {
      check(
        _equal(firstOutput, converted.bytes),
        'piece layouts changed DOCX bytes',
      );
    }
    firstOutput = converted.bytes;
    check(_equal(source, original), 'source mutated');
  }
  return {'seed': seed, 'fields': fixture.fields.length, 'layouts': 2};
}

/// Reads the WordprocessingML field stream independently of the DOC parser.
/// Literal cached text inside an enclosing instruction is not body display.
String generatedFieldTreeXmlText(XmlDocument xml) {
  final modes = <bool>[];
  final result = StringBuffer();
  const namespace =
      'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
  for (final element in xml.descendants.whereType<XmlElement>()) {
    if (element.name.namespaceUri != namespace) continue;
    final name = element.name.local;
    if (name == 'fldChar') {
      switch (element.getAttribute('fldCharType', namespace: namespace)) {
        case 'begin':
          modes.add(false);
        case 'separate':
          if (modes.isEmpty || modes.last) {
            throw StateError('Unmatched or duplicate DOCX field separator');
          }
          modes[modes.length - 1] = true;
        case 'end':
          if (modes.isEmpty) throw StateError('Unmatched DOCX field end');
          modes.removeLast();
        default:
          throw StateError('Unknown DOCX field marker');
      }
    } else if (!modes.contains(false)) {
      if (name == 't' || name == 'delText') {
        result.write(element.innerText);
      } else if (name == 'tab') {
        result.write('\t');
      } else if (name == 'br') {
        result.write(switch (element.getAttribute(
          'type',
          namespace: namespace,
        )) {
          'page' => '\f',
          'column' => '\x0e',
          _ => '\n',
        });
      }
    }
  }
  if (modes.isNotEmpty) throw StateError('Unclosed DOCX field');
  return result.toString();
}

Map<String, Object?> verifyGeneratedFieldTreeWebAcceptance() {
  var fields = 0;
  for (var seed = 1; seed <= 96; seed++) {
    fields += verifyGeneratedFieldTreeCase(seed)['fields'] as int;
    fields += verifyGeneratedFieldTreeCase(seed, ascii: true)['fields'] as int;
  }
  return {
    'seedFirst': 1,
    'seedLast': 96,
    'cases': 192,
    'unicodeCases': 96,
    'asciiCases': 96,
    'binaryLayouts': 384,
    'fieldsPerLayout': fields,
    'sourceUnchanged': true,
    'pieceLayoutIndependentDocx': true,
    'storedResultsEvaluated': false,
  };
}

bool _equal(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
