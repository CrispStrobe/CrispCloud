// SPDX-License-Identifier: MPL-2.0
// Pure Dart acceptance for the actual retained DOCs under dart2js/Node.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:xml/xml.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

void _check(bool value, String message) {
  if (!value) throw StateError(message);
}

List<(String, String)> _fields(XmlNode owner) {
  final fields = <(String, String)>[];
  StringBuffer? instruction;
  StringBuffer? cached;
  var separated = false;
  for (final element in owner.descendants.whereType<XmlElement>()) {
    if (element.name.namespaceUri != _w) continue;
    if (element.name.local == 'fldChar') {
      final type = element.getAttribute('fldCharType', namespace: _w);
      if (type == 'begin') {
        _check(instruction == null, 'Flat native fixture field');
        instruction = StringBuffer();
        cached = StringBuffer();
        separated = false;
      } else if (type == 'separate') {
        _check(instruction != null && !separated, 'Field separator');
        separated = true;
      } else if (type == 'end') {
        _check(instruction != null && separated, 'Complete cached field');
        fields.add((instruction.toString(), cached.toString()));
        instruction = null;
      }
    } else if (element.name.local == 'instrText' && instruction != null) {
      _check(!separated, 'Instruction precedes result');
      instruction.write(element.innerText);
    } else if (element.name.local == 't' && instruction != null && separated) {
      cached!.write(element.innerText);
    }
  }
  _check(instruction == null, 'No unterminated field');
  return fields;
}

void _externalOwners(Archive zip) {
  XmlDocument part(String path) =>
      XmlDocument.parse(utf8.decode(zip.findFile(path)!.content));
  void one(XmlNode owner, String url, String cached, String message) {
    final fields = _fields(owner);
    _check(
      fields.length == 1 && fields.single == (' HYPERLINK "$url" ', cached),
      message,
    );
  }

  final body = part('word/document.xml');
  one(body, 'https://example.com/body', 'Body link', 'Body URL field owner');
  final noteId = body
      .findAllElements('footnoteReference', namespace: _w)
      .single
      .getAttribute('id', namespace: _w);
  final note = part('word/footnotes.xml')
      .findAllElements('footnote', namespace: _w)
      .singleWhere((e) => e.getAttribute('id', namespace: _w) == noteId);
  one(
    note,
    'https://example.com/note',
    'Note link',
    'Footnote URL field owner',
  );
  final rels = part('word/_rels/document.xml.rels');
  for (final type in ['default', 'first']) {
    final reference = body
        .findAllElements('headerReference', namespace: _w)
        .singleWhere((e) => e.getAttribute('type', namespace: _w) == type);
    final id = reference.getAttribute(
      'id',
      namespace:
          'http://schemas.openxmlformats.org/officeDocument/2006/relationships',
    );
    final target = rels
        .findAllElements('Relationship')
        .singleWhere((e) => e.getAttribute('Id') == id)
        .getAttribute('Target');
    one(
      part('word/$target'),
      'https://example.com/header',
      'Header link',
      '$type header URL field owner',
    );
  }
}

Uint8List _swappedOwnerTargets(Uint8List original) {
  List<int> utf16(String value) => [
    for (final unit in value.codeUnits) ...[unit & 255, unit >> 8],
  ];
  final body = utf16('https://example.com/body');
  final note = utf16('https://example.com/note');
  final output = Uint8List.fromList(original);
  var bodyCount = 0;
  var noteCount = 0;
  bool matches(int at, List<int> target) {
    for (var i = 0; i < target.length; i++) {
      if (original[at + i] != target[i]) return false;
    }
    return true;
  }

  for (var at = 0; at + body.length <= original.length; at++) {
    if (matches(at, body)) {
      output.setRange(at, at + note.length, note);
      bodyCount++;
    } else if (matches(at, note)) {
      output.setRange(at, at + body.length, body);
      noteCount++;
    }
  }
  _check(
    bodyCount == 2 && noteCount == 2,
    'Exactly literal and HFD targets swapped',
  );
  return output;
}

Map<String, Object?> verifyFieldMetadataWebAcceptance(List cases) {
  _check(
    cases.length == 2,
    'Both independent native field sources are required',
  );
  final results = <String, Object?>{};
  for (final entry in cases) {
    final name = entry['name'] as String;
    _check(!results.containsKey(name), 'Unique field source');
    _check(name == 'external' || name == 'reference', 'Known field source');
    final source = base64Decode(entry['base64'] as String);
    final before = Uint8List.fromList(source);
    final result = convertLegacyWord(source);
    final zip = ZipDecoder().decodeBytes(result.bytes);
    final parts = <String, XmlDocument>{
      for (final part in zip)
        if (part.name.startsWith('word/') &&
            part.name.endsWith('.xml') &&
            part.name.split('/').length == 2)
          part.name: XmlDocument.parse(utf8.decode(part.content)),
    };
    final instructions = parts.values
        .expand((p) => p.findAllElements('instrText', namespace: _w))
        .map((e) => e.innerText)
        .toList();
    for (final part in parts.values) {
      for (final begin in part.findAllElements('fldChar', namespace: _w)) {
        if (begin.getAttribute('fldCharType', namespace: _w) == 'begin') {
          _check(
            begin.getAttribute('fldLock', namespace: _w) == '1',
            'Cached field lock',
          );
        }
      }
    }
    if (name == 'external') {
      _check(instructions.length == 4, 'All body/note/header URL fields');
      _check(
        instructions
                .where((s) => s == ' HYPERLINK "https://example.com/body" ')
                .length ==
            1,
        'Body URL',
      );
      _check(
        instructions
                .where((s) => s == ' HYPERLINK "https://example.com/note" ')
                .length ==
            1,
        'Footnote URL',
      );
      _check(
        instructions
                .where((s) => s == ' HYPERLINK "https://example.com/header" ')
                .length ==
            2,
        'Both header URL occurrences',
      );
      _check(
        result.preservedCounts['binaryHyperlinkFields'] == 4,
        'Qualified URL count',
      );
      _externalOwners(zip);
      // This valid controlled DOC preserves the same global target multiset
      // and field count while attaching body/note URLs to the wrong owners.
      final swapped = convertLegacyWord(_swappedOwnerTargets(source));
      _check(
        swapped.preservedCounts['binaryHyperlinkFields'] == 4,
        'Swap control remains fully qualified',
      );
      var rejected = false;
      try {
        _externalOwners(ZipDecoder().decodeBytes(swapped.bytes));
      } on StateError catch (error) {
        _check(
          error.message == 'Body URL field owner',
          'Swap fails the exact owner guard',
        );
        rejected = true;
      }
      _check(rejected, 'Body/note target swap rejected');
    } else {
      _check(
        instructions.length == 3,
        'REF, internal hyperlink and QUOTE fields',
      );
      _check(instructions[0] == ' REF Target_A \\h  ', 'Reference target');
      final visible = parts['word/document.xml']!
          .findAllElements('t', namespace: _w)
          .map((e) => e.innerText)
          .join();
      _check(
        visible ==
            'ANCHOR-αREF:[CACHED-REF]LINK:[CACHED-LINK]QUOTE:[CACHED-QUOTE]',
        'Original cached reference results',
      );
      _check(
        result.preservedCounts['binaryReferenceFields'] == 1,
        'Qualified REF count',
      );
      final fields = _fields(parts['word/document.xml']!);
      _check(
        fields.length == 3 &&
            fields[0] == (' REF Target_A \\h  ', 'CACHED-REF') &&
            fields[1] == (' HYPERLINK  \\l "Target_A" ', 'CACHED-LINK') &&
            fields[2] == ('QUOTE "LITERAL-β"', 'CACHED-QUOTE'),
        'Reference field/result ownership',
      );
      _check(
        result.preservedCounts['binaryHyperlinkFields'] == 1,
        'Internal hyperlink count',
      );
      final evidence =
          jsonDecode(
                utf8.decode(
                  zip.findFile('word/evidence/manifest.json')!.content,
                ),
              )
              as Map;
      final record =
          (evidence['records'] as List).singleWhere(
                (r) => r['kind'] == 'binaryReferenceField',
              )
              as Map;
      _check(
        record['recoveredNativeTerminator'] == true,
        'Producer padding is disclosed',
      );
    }
    _check(source.length == before.length, 'Source length');
    for (var i = 0; i < source.length; i++) {
      _check(source[i] == before[i], 'Source bytes unchanged');
    }
    results[name] = {
      'fields': instructions.length,
      'sourceBytesUnchanged': true,
      'representation': 'lockedFields',
      'ownerBindingsChecked': true,
    };
  }
  return {
    'cases': results,
    'fields': 7,
    'fieldResultsEvaluated': false,
    'bodyNoteTargetSwapRejected': true,
  };
}
