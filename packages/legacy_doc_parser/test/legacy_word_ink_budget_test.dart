// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';

import 'support/ink_budget_fixture.dart';
import 'support/officeart_shape_fixture.dart';

void main() {
  test('aggregate budgets accept only bounded nonnegative allowances', () {
    for (final value in [-1, 100001]) {
      expect(
        () => LegacyWordInkDecodeBudget(maxPoints: value),
        throwsRangeError,
      );
    }
    for (final value in [-1, 4097]) {
      expect(
        () => LegacyWordInkDecodeBudget(maxStrokes: value),
        throwsRangeError,
      );
    }
    final zero = LegacyWordInkDecodeBudget(maxPoints: 0, maxStrokes: 0);
    expect(
      decodeLegacyWordInk(inkBudgetIsf([]), budget: zero).status,
      LegacyWordInkDecodeStatus.decoded,
    );
    expect(
      decodeLegacyWordInk(inkBudgetIsf([1]), budget: zero).status,
      LegacyWordInkDecodeStatus.limitExceeded,
    );
    expect((zero.pointsUsed, zero.strokesUsed), (0, 0));
  });

  test('point capacity is checked before reading or allocating packets', () {
    // The packets are deliberately absent. The declared count must trip the
    // shared limit before the decoder can try reading those missing bytes.
    final bytes = _frame([10, ..._sized(_unsigned(5))]);
    expect(
      decodeLegacyWordInk(bytes).status,
      LegacyWordInkDecodeStatus.invalid,
    );
    final budget = LegacyWordInkDecodeBudget(maxPoints: 4);
    final result = decodeLegacyWordInk(bytes, budget: budget);
    expect(result.status, LegacyWordInkDecodeStatus.limitExceeded);
    expect(result.reason, contains('aggregate point'));
    expect(result.strokes, isEmpty);
    expect((budget.pointsUsed, budget.strokesUsed), (0, 0));
  });

  test('shared point and stroke reservations survive separate calls', () {
    final budget = LegacyWordInkDecodeBudget(maxPoints: 5, maxStrokes: 2);
    for (final count in [2, 3]) {
      expect(
        decodeLegacyWordInk(inkBudgetIsf([count]), budget: budget).status,
        LegacyWordInkDecodeStatus.decoded,
      );
    }
    expect((budget.pointsUsed, budget.strokesUsed), (5, 2));
    expect((budget.remainingPoints, budget.remainingStrokes), (0, 0));
    final result = decodeLegacyWordInk(inkBudgetIsf([1]), budget: budget);
    expect(result.status, LegacyWordInkDecodeStatus.limitExceeded);
    expect(result.reason, contains('aggregate stroke'));
    expect(result.strokes, isEmpty);
  });

  test('failed partial decodes still consume their attempted work', () {
    for (final tail in <List<int>>[
      [49], // Unknown extension after a completely decoded stroke.
      [10, ..._sized(_unsigned(2))], // Truncated second stroke.
    ]) {
      final budget = LegacyWordInkDecodeBudget(maxPoints: 5);
      final result = decodeLegacyWordInk(
        inkBudgetIsf([3], tail: tail),
        budget: budget,
      );
      expect(
        result.status,
        isIn([
          LegacyWordInkDecodeStatus.unsupported,
          LegacyWordInkDecodeStatus.invalid,
        ]),
      );
      expect(result.strokes, isEmpty);
      expect(budget.pointsUsed, tail.first == 49 ? 3 : 5);
      final later = decodeLegacyWordInk(inkBudgetIsf([3]), budget: budget);
      expect(later.status, LegacyWordInkDecodeStatus.limitExceeded);
      expect(later.strokes, isEmpty);
    }
  });

  test('an over-budget later stroke never exposes a partial collection', () {
    final budget = LegacyWordInkDecodeBudget(maxPoints: 3);
    final result = decodeLegacyWordInk(inkBudgetIsf([2, 2]), budget: budget);
    expect(result.status, LegacyWordInkDecodeStatus.limitExceeded);
    expect(result.strokes, isEmpty);
    expect((budget.pointsUsed, budget.strokesUsed), (2, 1));
    expect(
      decodeLegacyWordInk(inkBudgetIsf([1]), budget: budget).status,
      LegacyWordInkDecodeStatus.decoded,
    );
  });

  test('binary DOC conversion caps total points and preserves every ISF', () {
    final payloads = [
      for (final count in [60000, 60000, 40000, 1]) inkBudgetIsf([count]),
    ];
    final source = inkBudgetWordFixture(payloads);
    final before = Uint8List.fromList(source);
    final document = parseLegacyWordDocument(source);
    final result = convertLegacyWordDocument(document);
    final parts = _parts(result.bytes), records = _inkRecords(parts);
    expect(records.map((record) => record['strokeDecodeStatus']), [
      'decoded',
      'limitExceeded',
      'decoded',
      'limitExceeded',
    ]);
    expect(records.map((record) => record['pointCount']), [
      60000,
      null,
      40000,
      null,
    ]);
    for (var index = 0; index < records.length; index++) {
      final record = records[index];
      expect(parts[record['part']], orderedEquals(payloads[index]));
      expect(record['nativeInkEmitted'], isFalse);
      if (record['strokeDecodeStatus'] == 'limitExceeded') {
        expect(record['strokeDecodeReason'], contains('aggregate point'));
        expect(record['strokeSemanticsDecoded'], isFalse);
        expect(record['strokeCount'], isNull);
      }
    }
    expect(result.preservedCounts['inkPayloads'], 4);
    expect(result.preservedCounts['decodedInkPayloads'], 2);
    expect(result.preservedCounts['decodedInkStrokes'], 2);
    expect(source, orderedEquals(before));
    _noActiveInk(parts);
  });

  test('predecoded public models cannot bypass the conversion allowance', () {
    final inks = [
      LegacyWordOfficeArtInk(data: inkBudgetIsf([60000])),
      LegacyWordOfficeArtInk(data: inkBudgetIsf([60000])),
    ];
    final cached = [for (final ink in inks) ink.decoding!];
    expect(
      cached.map((result) => result.status),
      everyElement(LegacyWordInkDecodeStatus.decoded),
    );
    final output = convertLegacyWordDocument(_publicDocument(inks));
    final records = _inkRecords(_parts(output.bytes));
    expect(records.map((record) => record['strokeDecodeStatus']), [
      'decoded',
      'limitExceeded',
    ]);
    expect(output.preservedCounts['decodedInkPayloads'], 1);
    expect(identical(inks[1].decoding, cached[1]), isTrue);
    expect(inks[1].decoding!.pointCount, 60000);
  });

  test('repeated immutable ink references share one conversion inspection', () {
    final shared = LegacyWordOfficeArtInk(data: inkBudgetIsf([60000]));
    final last = LegacyWordOfficeArtInk(data: inkBudgetIsf([40000]));
    final output = convertLegacyWordDocument(
      _publicDocument([shared, shared, last]),
    );
    final records = _inkRecords(_parts(output.bytes));
    expect(
      records.map((record) => record['strokeDecodeStatus']),
      everyElement('decoded'),
    );
    // These existing preservation counters describe occurrences, while the
    // decode budget charges the shared source model only once.
    expect(output.preservedCounts['inkPayloads'], 3);
    expect(output.preservedCounts['decodedInkPayloads'], 3);
    expect(records.map((record) => record['pointCount']), [
      60000,
      60000,
      40000,
    ]);
  });

  test('inline and floating ink share the same document budget', () {
    final first = LegacyWordOfficeArtInk(data: inkBudgetIsf([60000]));
    final second = LegacyWordOfficeArtInk(data: inkBudgetIsf([60000]));
    final output = convertLegacyWordDocument(
      _publicDocument([second], pictureInk: first),
    );
    final records = _inkRecords(_parts(output.bytes));
    expect(records.first['pictureId'], 'ink-picture');
    expect(records.last['shapeId'], 1025);
    expect(records.map((record) => record['strokeDecodeStatus']), [
      'decoded',
      'limitExceeded',
    ]);
  });

  test('stroke capacity is aggregate even when point capacity remains', () {
    final first = LegacyWordOfficeArtInk(
      data: inkBudgetIsf(List.filled(2048, 1)),
    );
    final second = LegacyWordOfficeArtInk(
      data: inkBudgetIsf(List.filled(2048, 1)),
    );
    final third = LegacyWordOfficeArtInk(data: inkBudgetIsf([1]));
    final output = convertLegacyWordDocument(
      _publicDocument([first, second, third]),
    );
    final records = _inkRecords(_parts(output.bytes));
    expect(records.map((record) => record['strokeDecodeStatus']), [
      'decoded',
      'decoded',
      'limitExceeded',
    ]);
    expect(records.last['strokeDecodeReason'], contains('aggregate stroke'));
    expect(output.preservedCounts['decodedInkStrokes'], 4096);
  });

  test('conversion limits do not poison standalone model inspection', () {
    final first = LegacyWordOfficeArtInk(data: inkBudgetIsf([100000]));
    final later = LegacyWordOfficeArtInk(data: inkBudgetIsf([1]));
    final document = _publicDocument([first, later]);
    final output = convertLegacyWordDocument(document);
    expect(
      _inkRecords(_parts(output.bytes)).last['strokeDecodeStatus'],
      'limitExceeded',
    );
    expect(later.decoding!.status, LegacyWordInkDecodeStatus.decoded);
    expect(later.decoding!.pointCount, 1);
    // A second conversion starts with the same capacity and produces the same
    // package even after the caller inspects a formerly limited payload.
    expect(
      convertLegacyWordDocument(document).bytes,
      orderedEquals(output.bytes),
    );
  });
}

List<int> _unsigned(int value) {
  final result = <int>[];
  do {
    final low = value & 127;
    value ~/= 128;
    result.add(low | (value == 0 ? 0 : 128));
  } while (value != 0);
  return result;
}

List<int> _sized(List<int> bytes) => [..._unsigned(bytes.length), ...bytes];
Uint8List _frame(List<int> body) => Uint8List.fromList([0, ..._sized(body)]);

LegacyWordDocument _publicDocument(
  List<LegacyWordOfficeArtInk> inks, {
  LegacyWordOfficeArtInk? pictureInk,
}) {
  final base = parseLegacyWordDocument(officeArtShapeWordFixture());
  final old = base.media.drawings.single;
  return LegacyWordDocument(
    blocks: base.blocks,
    sections: base.sections,
    plainText: base.plainText,
    safeHtml: '',
    media: LegacyWordMediaCatalog.from(
      pictures: [
        if (pictureInk != null)
          LegacyWordPicture(
            id: 'ink-picture',
            cp: old.anchorCp,
            source: old.source,
            officeArtArtifactId: 'public-model',
            shape: LegacyWordOfficeArtShape(type: 75, ink: pictureInk),
          ),
      ],
      drawings: [
        for (var index = 0; index < inks.length; index++)
          LegacyWordDrawing(
            shapeId: 1025 + index,
            anchorCp: old.anchorCp,
            headerStory: false,
            leftTwips: old.leftTwips,
            topTwips: old.topTwips,
            rightTwips: old.rightTwips,
            bottomTwips: old.bottomTwips,
            horizontalOrigin: old.horizontalOrigin,
            verticalOrigin: old.verticalOrigin,
            wrapMode: old.wrapMode,
            wrapSide: old.wrapSide,
            behindText: old.behindText,
            anchorLocked: false,
            source: old.source,
            shape: LegacyWordOfficeArtShape(type: 1, ink: inks[index]),
          ),
      ],
    ),
  );
}

Map<String, Uint8List> _parts(Uint8List bytes) => {
  for (final entry in ZipDecoder().decodeBytes(bytes))
    if (entry.isFile) entry.name: entry.content,
};

List<Map<String, dynamic>> _inkRecords(Map<String, Uint8List> parts) =>
    (jsonDecode(utf8.decode(parts['word/evidence/manifest.json']!))['records']
            as List)
        .cast<Map<String, dynamic>>()
        .where((record) => record['kind'] == 'officeArtInk')
        .toList();

void _noActiveInk(Map<String, Uint8List> parts) {
  for (final entry in parts.entries) {
    if (entry.key.endsWith('.xml')) {
      expect(utf8.decode(entry.value), isNot(contains('<o:ink')));
    }
  }
}
