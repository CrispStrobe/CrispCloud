// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:xml/xml.dart';

import '../test/support/section_geometry_fixture.dart';

Map<String, int> verifySectionGeometryWebAcceptance() {
  const w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
  var publicRejected = 0, binaryRejected = 0, parsed = 0, emitted = 0;
  for (final property in sectionGeometryProperties) {
    for (final historical in [false, true]) {
      for (final value in property.invalidValues) {
        _rejects(
          () => convertLegacyWordDocument(
            sectionGeometryDocument(property, value, historical: historical),
          ),
        );
        publicRejected++;
        if (property.encodable(value)) {
          _rejects(
            () => parseLegacyWordDocument(
              sectionGeometryFixture(property, value, historical: historical),
            ),
          );
          binaryRejected++;
        }
      }
      for (final value in property.validValues) {
        final source = parseLegacyWordDocument(
          sectionGeometryFixture(property, value, historical: historical),
        );
        final current = source.sections.single;
        final section = historical
            ? current.formattingRevision!.previousSection!
            : current;
        if (property.read(section) != value) {
          throw StateError('Section geometry changed during parsing.');
        }
        parsed++;
        final document = sectionGeometryDocument(
          property,
          value,
          historical: historical,
        );
        if (!property.nativeRepresentable(value)) {
          _rejects(() => convertLegacyWordDocument(document));
          publicRejected++;
          continue;
        }
        final archive = ZipDecoder().decodeBytes(
          convertLegacyWordDocument(document).bytes,
        );
        final xml = XmlDocument.parse(
          utf8.decode(archive.findFile('word/document.xml')!.content),
        );
        final root = historical
            ? xml.findAllElements('sectPrChange', namespace: w).single
            : xml.rootElement;
        final element = root
            .findAllElements(property.xmlTag, namespace: w)
            .single;
        if (element.getAttribute(property.xmlAttribute, namespace: w) !=
            '$value') {
          throw StateError('Section geometry changed during export.');
        }
        emitted++;
      }
    }
  }
  return {
    'publicRejected': publicRejected,
    'binaryRejected': binaryRejected,
    'parsed': parsed,
    'emitted': emitted,
  };
}

void _rejects(Object? Function() action) {
  try {
    action();
  } on FormatException {
    return;
  }
  throw StateError('Invalid section geometry was accepted.');
}
