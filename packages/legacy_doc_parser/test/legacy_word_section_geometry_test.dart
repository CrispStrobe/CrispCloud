// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import '../tool/section_geometry_web_acceptance.dart';
import 'support/section_geometry_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

void main() {
  test('section geometry shared JavaScript corpus passes on the VM', () {
    expect(verifySectionGeometryWebAcceptance(), {
      'publicRejected': 70,
      'binaryRejected': 52,
      'parsed': 48,
      'emitted': 44,
    });
  });

  for (final property in sectionGeometryProperties) {
    for (final historical in [false, true]) {
      final scope = historical ? 'historical' : 'current';
      for (final value in property.invalidValues) {
        test('public ${property.name} $value $scope is rejected', () {
          final document = sectionGeometryDocument(
            property,
            value,
            historical: historical,
          );
          expect(
            () => convertLegacyWordDocument(document),
            throwsFormatException,
          );
        });
        if (property.encodable(value)) {
          test('binary ${property.name} $value $scope is rejected', () {
            final bytes = sectionGeometryFixture(
              property,
              value,
              historical: historical,
            );
            expect(() => parseLegacyWordDocument(bytes), throwsFormatException);
          });
        }
      }
      for (final value in property.validValues) {
        test('binary ${property.name} $value $scope stays exact', () {
          final parsed = parseLegacyWordDocument(
            sectionGeometryFixture(property, value, historical: historical),
          );
          final current = parsed.sections.single;
          final section = historical
              ? current.formattingRevision!.previousSection!
              : current;
          expect(property.read(section), value);
        });
        test('public ${property.name} $value $scope output', () {
          final document = sectionGeometryDocument(
            property,
            value,
            historical: historical,
          );
          if (!property.nativeRepresentable(value)) {
            expect(
              () => convertLegacyWordDocument(document),
              throwsFormatException,
            );
            return;
          }
          final archive = ZipDecoder().decodeBytes(
            convertLegacyWordDocument(document).bytes,
          );
          final xml = XmlDocument.parse(
            utf8.decode(archive.findFile('word/document.xml')!.content),
          );
          final root = historical
              ? xml.findAllElements('sectPrChange', namespace: _w).single
              : xml.rootElement;
          final element = root
              .findAllElements(property.xmlTag, namespace: _w)
              .single;
          expect(
            element.getAttribute(property.xmlAttribute, namespace: _w),
            '$value',
          );
        });
      }
    }
  }

  test('unspecified geometry stays absent', () {
    final document = sectionGeometryDocument(
      sectionGeometryProperties.first,
      null,
    );
    final archive = ZipDecoder().decodeBytes(
      convertLegacyWordDocument(document).bytes,
    );
    final xml = XmlDocument.parse(
      utf8.decode(archive.findFile('word/document.xml')!.content),
    );
    expect(xml.findAllElements('pgSz', namespace: _w), isEmpty);
    expect(xml.findAllElements('pgMar', namespace: _w), isEmpty);
    final columns = xml.findAllElements('cols', namespace: _w).single;
    expect(columns.getAttribute('space', namespace: _w), isNull);
  });
}
