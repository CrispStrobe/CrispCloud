// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/fib_extension_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

String _sha256(Uint8List bytes) => Sha256.of(
  bytes,
).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

void main() {
  for (final (version, minimum, dopLength) in [
    (0xd9, 2, 544),
    (0x101, 2, 594),
    (0x10c, 2, 616),
    (0x112, 5, 674),
  ]) {
    for (final words in {minimum, minimum + 1, 7}) {
      test('bounded FIB version $version accepts $words declared words', () {
        final document = parseLegacyWordDocument(
          fibExtensionFixture(
            newVersion: version,
            words: words,
            dopLength: dopLength,
          ),
        );
        expect(document.plainText, 'Bounded FIB');
        expect(document.compatibility.sourceFibNewVersion, version);
        expect(
          document.compatibility[LegacyWordCompatibilityFlag
              .shapeLayoutLikeWW8],
          isTrue,
        );
        expect(
          document.compatibility.issues.map((issue) => issue.name),
          words == minimum
              ? isNot(contains('nonstandardFibExtension'))
              : contains('nonstandardFibExtension'),
        );
      });
    }
    test('FIB version $version still requires its complete known prefix', () {
      expect(
        () => parseLegacyWordDocument(
          fibExtensionFixture(
            newVersion: version,
            words: minimum - 1,
            dopLength: dopLength,
          ),
        ),
        throwsFormatException,
      );
    });
  }
  test('observed Word97 variant exposes only established DOP prefixes', () {
    final document = parseLegacyWordDocument(
      fibExtensionFixture(
        newVersion: 0xc3,
        words: 4,
        pairCount: 108,
        dopLength: 544,
      ),
    );
    final compatibility = document.compatibility;
    expect(document.plainText, 'Bounded FIB');
    expect(compatibility.sourceFibNewVersion, 0xc3);
    expect(compatibility.sourceBlocks, hasLength(2));
    expect(
      compatibility[LegacyWordCompatibilityFlag.shapeLayoutLikeWW8],
      isNull,
    );
    expect(
      compatibility[LegacyWordCompatibilityFlag.doNotExpandShiftReturn],
      isFalse,
    );
    expect(
      compatibility.issues.map((issue) => issue.name),
      containsAll(['nonstandardFibExtension', 'unrecognizedExtension']),
    );
  });
  for (final (version, words, pairs, dopLength) in [
    (0xc2, 4, 108, 544),
    (0xc4, 4, 108, 544),
    (0xc3, 3, 108, 544),
    (0xc3, 4, 93, 544),
    (0xc3, 4, 108, 543),
    (0xc3, 4, 108, 545),
    (0xffff, 7, 183, 674),
  ]) {
    test(
      'unqualified FIB variant $version/$words/$pairs/$dopLength rejects',
      () {
        expect(
          () => parseLegacyWordDocument(
            fibExtensionFixture(
              newVersion: version,
              words: words,
              pairCount: pairs,
              dopLength: dopLength,
            ),
          ),
          throwsFormatException,
        );
      },
    );
  }
  test('a counted FIB extension may not exceed the declared Word stream', () {
    expect(
      () =>
          parseLegacyWordDocument(fibExtensionFixture(truncateExtension: true)),
      throwsFormatException,
    );
  });

  for (final (name, expectedSha, prefix) in [
    (
      '47304.doc',
      '39170c5a103bb0961b269be04da00ae2ae961da6a26f1624f462ac915adaf13e',
      'Just a “test”',
    ),
    (
      'website-stanford-biosketch.doc',
      '6e6e4ffeb1811f0fab5539709b17934d4ac2babe3cf1d670e30af50aef826d2d',
      'Principal Investigator/Program Director',
    ),
  ]) {
    test(
      'original Apache POI $name imports and converts without rewriting',
      () {
        final input = File(
          'test/fixtures/external/poi-20261114/poi/doc/$name',
        ).readAsBytesSync();
        expect(_sha256(input), expectedSha);
        final document = parseLegacyWordDocument(input);
        expect(
          document.plainText.replaceAll(RegExp(r'\s+'), ' ').trim(),
          startsWith(prefix),
        );
        expect(
          document.compatibility.issues.map((issue) => issue.name),
          contains('nonstandardFibExtension'),
        );
        final output = convertLegacyWordDocument(document);
        final xml = XmlDocument.parse(
          utf8.decode(
            ZipDecoder()
                .decodeBytes(output.bytes)
                .findFile('word/document.xml')!
                .content,
          ),
        );
        expect(xml.findAllElements('t', namespace: _w), isNotEmpty);
        expect(_sha256(input), expectedSha);
      },
    );
  }
}
