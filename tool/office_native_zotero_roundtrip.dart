// Run from the CrispCloud root after flutter pub get:
// dart tool/office_native_zotero_roundtrip.dart INPUT.docx [COMPARED.docx]
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';

/// Compare the visible result and structured metadata without depending on
/// OOXML run boundaries, ZIP timestamps, or JSON object key order.
List<Map<String, Object?>> _inventory(WmlDocument document) {
  final fields = WordZotero.fields(document);
  if (fields.isEmpty) {
    throw StateError('The fixture has no active Zotero fields.');
  }
  return [
    for (final field in fields)
      if (field.isValid)
        {
          'kind': field.kind.name,
          'cachedText': field.cachedText,
          'metadata': _canonicalJson(field.metadata),
        }
      else
        throw StateError('Invalid Zotero ${field.kind.name} field.'),
  ];
}

Object? _canonicalJson(Object? value) {
  if (value is Map<String, dynamic>) {
    return SplayTreeMap<String, Object?>.from(
      value.map((key, value) => MapEntry(key, _canonicalJson(value))),
    );
  }
  if (value is List) return value.map(_canonicalJson).toList();
  return value;
}

void _compare(
  List<Map<String, Object?>> expected,
  List<Map<String, Object?>> actual,
  String route,
) {
  if (expected.length != actual.length) {
    throw StateError(
      '$route changed the field count from ${expected.length} to ${actual.length}.',
    );
  }
  for (var i = 0; i < expected.length; i++) {
    for (final key in expected[i].keys) {
      if (jsonEncode(expected[i][key]) != jsonEncode(actual[i][key])) {
        throw StateError('$route changed $key in Zotero field ${i + 1}.');
      }
    }
  }
}

void main(List<String> arguments) {
  if (arguments.isEmpty || arguments.length > 2) {
    stderr.writeln(
      'Usage: dart tool/office_native_zotero_roundtrip.dart '
      'INPUT.docx [COMPARED.docx]',
    );
    exitCode = 64;
    return;
  }

  final reader = WordDeserializer();
  final source = reader.readBytes(File(arguments[0]).readAsBytesSync());
  final expected = _inventory(source);
  final reopened = reader.readBytes(WordSerializer().writeBytes(source));
  _compare(expected, _inventory(reopened), 'CrispOffice save and reopen');
  if (arguments.length == 2) {
    final compared = reader.readBytes(File(arguments[1]).readAsBytesSync());
    _compare(expected, _inventory(compared), 'Compared DOCX');
  }
  stdout.writeln('Preserved ${expected.length} active Zotero fields.');
}
