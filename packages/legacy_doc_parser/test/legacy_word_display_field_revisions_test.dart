// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/story_word_fixture.dart';
import 'support/structured_word_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _date = 45 | (8 << 6) | (12 << 11) | (11 << 16) | (126 << 20);
const _text = 'A\x13 LISTNUM \x142.\x15B\r';

Uint8List _record({String original = '1.', int flag = 1, int author = 1}) {
  final bytes = Uint8List(39), data = ByteData(39);
  data.setUint8(0, flag);
  data.setUint16(1, author, Endian.little);
  data.setUint32(3, _date, Endian.little);
  data.setUint16(7, original.length, Endian.little);
  for (var i = 0; i < original.length; i++) {
    data.setUint16(9 + i * 2, original.codeUnitAt(i), Endian.little);
  }
  bytes.setAll(0, data.buffer.asUint8List());
  return bytes;
}

List<int> _fieldPlc(String text, Set<int> privateEnds) {
  final positions = <int>[], records = <int>[];
  var depth = 0;
  for (var cp = 0; cp < text.length; cp++) {
    final unit = text.codeUnitAt(cp);
    if (!const [19, 20, 21].contains(unit)) continue;
    positions.add(cp);
    var flags = 0;
    if (unit == 19) depth++;
    if (unit == 21) {
      flags =
          0x80 | (depth > 1 ? 0x40 : 0) | (privateEnds.contains(cp) ? 0x20 : 0);
      depth--;
    }
    records.addAll([unit, flags]);
  }
  return storyPlc([...positions, 0xffffffff], records);
}

Uint8List _source({
  String text = _text,
  Uint8List? record,
  bool private = false,
  bool hidden = false,
  bool resetStyle = false,
  List<WordFixtureFkpRun>? runs,
}) {
  final first = text.indexOf('\x13'), last = text.lastIndexOf('\x15');
  final spans =
      runs ??
      [
        WordFixtureFkpRun(
          8192 + first,
          8193 + last,
          properties: [
            ...wordSprm(0xca62, [39, ...(record ?? _record())]),
            if (hidden) ...wordSprm(0x083c, [1]),
            if (resetStyle) ...wordSprm(0x2a33, [0]),
          ],
        ),
      ];
  return StructuredWordFixture(
    pieces: [WordFixturePiece(text)],
    characterRuns: [
      if (spans.first.startFc > 8192)
        WordFixtureFkpRun(8192, spans.first.startFc),
      ...spans,
      if (spans.last.endFc < 8192 + text.length)
        WordFixtureFkpRun(spans.last.endFc, 8192 + text.length),
    ],
    extraTablePairs: {
      16: _fieldPlc(text, {if (private) last}),
      51: storyBookmarkNames(['Unknown', 'Alice']),
    },
  ).build();
}

Map<String, Uint8List> _parts(Uint8List bytes) => {
  for (final file in ZipDecoder().decodeBytes(bytes))
    if (file.isFile) file.name: file.content,
};
XmlDocument _xml(Uint8List bytes) =>
    XmlDocument.parse(utf8.decode(_parts(bytes)['word/document.xml']!));
String? _attr(XmlElement element, String name) =>
    element.getAttribute(name, namespace: _w);

// Independent simple-field review projection: acceptance retains the cached
// result; rejection substitutes the literal original from the begin marker.
// It does not interpret the parser model or evaluate any field instructions.
String _reviewText(XmlDocument document, {required bool reject}) {
  final result = StringBuffer();
  var field = false, cached = false;
  String? original;
  for (final element in document.findAllElements('r', namespace: _w)) {
    final marker = element.getElement('fldChar', namespace: _w);
    if (marker != null) {
      switch (_attr(marker, 'fldCharType')) {
        case 'begin':
          expect(field, isFalse);
          field = true;
          original = marker
              .getElement('numberingChange', namespace: _w)
              ?.getAttribute('original', namespace: _w);
        case 'separate':
          cached = true;
          if (reject && original != null) result.write(original);
        case 'end':
          field = cached = false;
          original = null;
      }
    } else if (!field || cached && !(reject && original != null)) {
      for (final text in element.findElements('t', namespace: _w)) {
        result.write(text.innerText);
      }
    }
  }
  expect(field, isFalse);
  return result.toString();
}

void main() {
  test(
    'LISTNUM revision preserves independently reviewed old and current result',
    () {
      final sourceRecord = _record(flag: 255);
      final document = parseLegacyWordDocument(
        _source(record: sourceRecord, resetStyle: true),
      );
      final change = document.fields.single.displayRevision!;
      expect(change.original, '1.');
      expect(change.revision.author, 'Alice');
      final time = change.revision.time!;
      expect(
        [time.year, time.month, time.day, time.hour, time.minute],
        [2026, 11, 12, 8, 45],
      );
      expect(change.hidden, isFalse);
      expect(() => change.sourceRecord![0] = 0, throwsUnsupportedError);
      sourceRecord[0] = 0;
      expect(change.sourceRecord![0], 255);
      expect(document.plainText, 'A2.B');
      final result = convertLegacyWordDocument(document),
          xml = _xml(result.bytes);
      expect(_reviewText(xml, reject: false), 'A2.B');
      expect(_reviewText(xml, reject: true), 'A1.B');
      final marker = xml
          .findAllElements('numberingChange', namespace: _w)
          .single;
      expect(marker.parentElement!.name.local, 'fldChar');
      expect(_attr(marker.parentElement!, 'fldCharType'), 'begin');
      expect(_attr(marker.parentElement!, 'fldLock'), '1');
      expect(_attr(marker, 'author'), 'Alice');
      expect(_attr(marker, 'date'), '2026-11-12T08:45:00');
      expect(result.preservedCounts['displayFieldRevisions'], 1);
      expect(
        result.limitations,
        isNot(contains(LegacyWordConversionLimitation.revisions)),
      );
      final parts = _parts(result.bytes);
      expect(parts.values, contains(orderedEquals(change.sourceRecord!)));
      expect(
        utf8.decode(parts['word/evidence/manifest.json']!),
        contains('DispFldRmOperand'),
      );
    },
  );

  test(
    'a zero mark clears display history without dropping the locked LISTNUM field',
    () {
      final record = _record(flag: 0);
      record[7] = 255; // The unmarked prior result is not applicable.
      final document = parseLegacyWordDocument(_source(record: record));
      expect(document.fields.single.displayRevision, isNull);
      final result = convertLegacyWordDocument(document);
      expect(
        _xml(result.bytes).findAllElements('numberingChange', namespace: _w),
        isEmpty,
      );
      expect(result.preservedCounts['fields'], 1);
      expect(
        result.limitations,
        isNot(contains(LegacyWordConversionLimitation.fieldsLists)),
      );
    },
  );

  test('private and hidden previous results remain inert evidence', () {
    for (final private in [false, true]) {
      final document = parseLegacyWordDocument(
        _source(
          record: _record(original: 'OLD_SECRET'),
          private: private,
          hidden: !private,
        ),
      );
      final result = convertLegacyWordDocument(document),
          parts = _parts(result.bytes);
      expect(document.fields.single.displayRevision!.hidden, isTrue);
      expect(
        utf8.decode(parts['word/document.xml']!),
        isNot(contains('OLD_SECRET')),
      );
      expect(
        _xml(result.bytes).findAllElements('numberingChange', namespace: _w),
        isEmpty,
      );
      expect(
        result.limitations,
        contains(LegacyWordConversionLimitation.revisions),
      );
      expect(
        parts.values,
        contains(
          orderedEquals(document.fields.single.displayRevision!.sourceRecord!),
        ),
      );
    }
  });

  test(
    'nested field identity and private ancestors do not duplicate or expose history',
    () {
      const text =
          '\x13 IF \x13 LISTNUM \x142.\x15 = 2 "yes" "no" \x14yes\x15\r';
      final first = text.indexOf('\x13', 1), last = text.indexOf('\x15');
      for (final private in [false, true]) {
        final document = parseLegacyWordDocument(
          _source(
            text: text,
            private: private,
            runs: [
              WordFixtureFkpRun(
                8192 + first,
                8193 + last,
                properties: wordSprm(0xca62, [
                  39,
                  ..._record(original: 'OLD_SECRET'),
                ]),
              ),
            ],
          ),
        );
        final child = document.fields.singleWhere(
          (field) => field.type == 'LISTNUM',
        );
        expect(child.parentId, isNotNull);
        expect(child.displayRevision!.hidden, private);
        final xml = _xml(convertLegacyWordDocument(document).bytes);
        expect(
          xml.findAllElements('numberingChange', namespace: _w).length,
          private ? 0 : 1,
        );
        if (private) expect(xml.toXmlString(), isNot(contains('OLD_SECRET')));
      }
    },
  );

  test(
    'identical repeated records can differ in ignored padding and flag value',
    () {
      final a = _record(), b = _record(flag: 7);
      b[38] = 0xff;
      final separator = _text.indexOf('\x14');
      final document = parseLegacyWordDocument(
        _source(
          runs: [
            WordFixtureFkpRun(
              8193,
              8192 + separator,
              properties: wordSprm(0xca62, [39, ...a]),
            ),
            WordFixtureFkpRun(
              8192 + separator,
              8193 + _text.indexOf('\x15'),
              properties: wordSprm(0xca62, [39, ...b]),
            ),
          ],
        ),
      );
      expect(document.fields.single.displayRevision!.original, '1.');
      final xml = _xml(convertLegacyWordDocument(document).bytes);
      expect(xml.findAllElements('numberingChange', namespace: _w).length, 1);
    },
  );

  test(
    'unrepresentable old XML controls remain source evidence without invention',
    () {
      final document = parseLegacyWordDocument(
        _source(record: _record(original: '1\t')),
      );
      final result = convertLegacyWordDocument(document),
          xml = _xml(result.bytes);
      final revision = xml
          .findAllElements('numberingChange', namespace: _w)
          .single;
      expect(_attr(revision, 'original'), isNull);
      expect(
        result.limitations,
        contains(LegacyWordConversionLimitation.revisions),
      );
      expect(_reviewText(xml, reject: false), 'A2.B');
    },
  );

  test(
    'malformed, misplaced, and conflicting display histories fail closed',
    () {
      final long = _record()..[7] = 16;
      final unicode = _record();
      ByteData.sublistView(unicode).setUint16(9, 0xd800, Endian.little);
      for (final record in [long, unicode]) {
        expect(
          () => parseLegacyWordDocument(_source(record: record)),
          throwsFormatException,
        );
      }
      expect(
        () => parseLegacyWordDocument(
          _source(text: _text.replaceAll('LISTNUM', 'PAGE')),
        ),
        throwsFormatException,
      );
      expect(
        () => parseLegacyWordDocument(
          _source(
            runs: [
              WordFixtureFkpRun(
                8192,
                8193,
                properties: wordSprm(0xca62, [39, ..._record()]),
              ),
            ],
          ),
        ),
        throwsFormatException,
      );
      for (final length in [38, 40]) {
        expect(
          () => parseLegacyWordDocument(
            _source(
              runs: [
                WordFixtureFkpRun(
                  8193,
                  8194,
                  properties: wordSprm(0xca62, [
                    length,
                    ...List.filled(length, 0),
                  ]),
                ),
              ],
            ),
          ),
          throwsFormatException,
        );
      }
      final separator = _text.indexOf('\x14');
      expect(
        () => parseLegacyWordDocument(
          _source(
            runs: [
              WordFixtureFkpRun(
                8193,
                8192 + separator,
                properties: wordSprm(0xca62, [39, ..._record()]),
              ),
              WordFixtureFkpRun(
                8192 + separator,
                8193 + _text.indexOf('\x15'),
                properties: wordSprm(0xca62, [
                  39,
                  ..._record(original: 'DIFFERENT'),
                ]),
              ),
            ],
          ),
        ),
        throwsFormatException,
      );
    },
  );
}
