@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_ebook/crisp_ebook.dart';
import 'package:crisp_ebook_conversion/crisp_ebook_conversion.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

List<Uint8List> records(Uint8List input) {
  final view = ByteData.sublistView(input);
  final count = view.getUint16(76);
  final offsets = List.generate(count, (i) => view.getUint32(78 + i * 8));
  return List.generate(
    count,
    (i) => Uint8List.fromList(
      input.sublist(offsets[i], i + 1 < count ? offsets[i + 1] : input.length),
    ),
  );
}

Map<int, List<Uint8List>> exth(Uint8List record) {
  final view = ByteData.sublistView(record);
  if (view.getUint32(128) & 0x40 == 0) return {};
  final start = 16 + view.getUint32(20);
  expect(ascii.decode(record.sublist(start, start + 4)), 'EXTH');
  var cursor = start + 12;
  final fields = <int, List<Uint8List>>{};
  for (var i = 0; i < view.getUint32(start + 8); i++) {
    final type = view.getUint32(cursor), size = view.getUint32(cursor + 4);
    (fields[type] ??= []).add(
      Uint8List.fromList(record.sublist(cursor + 8, cursor + size)),
    );
    cursor += size;
  }
  return fields;
}

List<int> sections(List<Uint8List> book) {
  final boundary = exth(book.first)[121]?.first;
  if (boundary == null) return [0];
  final index = ByteData.sublistView(boundary).getUint32(0);
  if (index == 0xffffffff) return [0];
  expect(ascii.decode(book[index - 1]), 'BOUNDARY');
  return [0, index];
}

Uint8List fullName(Uint8List record) {
  final view = ByteData.sublistView(record);
  final offset = view.getUint32(84);
  return Uint8List.fromList(
    record.sublist(offset, offset + view.getUint32(88)),
  );
}

// Independent decoder for the Windows-1252 fixture bytes. Latin-1 alone would
// incorrectly decode the Euro, smart quotes and em dash in the C1 byte range.
const _windows1252C1 = [
  0x20ac,
  0x81,
  0x201a,
  0x192,
  0x201e,
  0x2026,
  0x2020,
  0x2021,
  0x2c6,
  0x2030,
  0x160,
  0x2039,
  0x152,
  0x8d,
  0x17d,
  0x8f,
  0x90,
  0x2018,
  0x2019,
  0x201c,
  0x201d,
  0x2022,
  0x2013,
  0x2014,
  0x2dc,
  0x2122,
  0x161,
  0x203a,
  0x153,
  0x9d,
  0x17e,
  0x178,
];

String decodeMetadata(Uint8List header, Uint8List bytes) {
  final encoding = ByteData.sublistView(header).getUint32(28);
  if (encoding == 65001) return utf8.decode(bytes);
  expect(encoding, 1252);
  return String.fromCharCodes(
    bytes.map(
      (byte) =>
          byte >= 0x80 && byte <= 0x9f ? _windows1252C1[byte - 0x80] : byte,
    ),
  );
}

Uint8List _u32(int value) =>
    (ByteData(4)..setUint32(0, value)).buffer.asUint8List();

/// Fixture surgery only: rebuild a metadata header in its existing padding,
/// keeping every record offset and every nonmetadata byte unchanged.
Uint8List withHeader(
  Uint8List input,
  int index, {
  int? encoding,
  Map<int, List<Uint8List>>? fields,
  bool hasExth = true,
}) {
  final original = records(input)[index];
  final old = ByteData.sublistView(original);
  final headerLength = 16 + old.getUint32(20);
  final values = fields ?? exth(original);
  final block = BytesBuilder();
  if (hasExth) {
    final entries = BytesBuilder();
    var count = 0;
    for (final field in values.entries) {
      for (final value in field.value) {
        entries.add(_u32(field.key));
        entries.add(_u32(value.length + 8));
        entries.add(value);
        count++;
      }
    }
    final length = (entries.length + 12 + 3) & ~3;
    block.add(ascii.encode('EXTH'));
    block.add(_u32(length));
    block.add(_u32(count));
    block.add(entries.takeBytes());
    block.add(Uint8List(length - block.length));
  }
  final name = fullName(original);
  final nameOffset = headerLength + block.length;
  expect(nameOffset + name.length, lessThanOrEqualTo(original.length));
  final header = Uint8List(original.length)
    ..setRange(0, headerLength, original)
    ..setRange(headerLength, nameOffset, block.takeBytes())
    ..setRange(nameOffset, nameOffset + name.length, name);
  final view = ByteData.sublistView(header);
  view.setUint32(84, nameOffset);
  view.setUint32(88, name.length);
  view.setUint32(
    128,
    hasExth ? old.getUint32(128) | 0x40 : old.getUint32(128) & ~0x40,
  );
  if (encoding != null) view.setUint32(28, encoding);
  final output = Uint8List.fromList(input);
  final start = ByteData.sublistView(input).getUint32(78 + index * 8);
  output.setRange(start, start + header.length, header);
  return output;
}

/// Keep the KF7 half of a generated dual MOBI as a standalone legacy fixture.
Uint8List legacyOnly(Uint8List input) {
  final parts = records(input);
  final headerIndexes = sections(parts);
  expect(headerIndexes, hasLength(2));
  final boundary = headerIndexes.last;
  final fields = exth(parts.first)..[121] = [_u32(0xffffffff)];
  final first = records(withHeader(input, 0, fields: fields)).first;
  final kept = [first, ...parts.sublist(1, boundary - 1)];
  final header = Uint8List.fromList(input.sublist(0, 78));
  ByteData.sublistView(header).setUint16(76, kept.length);
  final table = BytesBuilder();
  var offset = 78 + kept.length * 8 + 2;
  for (var index = 0; index < kept.length; index++) {
    table.add(_u32(offset));
    table.add(input.sublist(82 + index * 8, 86 + index * 8));
    offset += kept[index].length;
  }
  return (BytesBuilder()
        ..add(header)
        ..add(table.takeBytes())
        ..add([0, 0])
        ..add(kept.expand((part) => part).toList()))
      .takeBytes();
}

void expectUnchangedResources(Uint8List before, Uint8List after) {
  final original = records(before), edited = records(after);
  final headers = sections(original);
  expect(edited.length, original.length);
  expect(sections(edited), headers);
  for (var index = 0; index < original.length; index++) {
    if (!headers.contains(index)) {
      expect(
        edited[index],
        original[index],
        reason: 'Nonmetadata record $index',
      );
    }
  }
}

Future<void> expectIdempotent(
  KindlingConverter converter,
  EbookConversionResult result,
  KindleMetadataPatch patch,
  KindleExportFormat format,
) async {
  final repeated = await converter.rewriteMetadata(
    result.bytes,
    patch: patch,
    format: format,
  );
  expect(repeated.noOp, isTrue);
  expect(repeated.bytes, result.bytes);
}

void main() {
  final source = File('test/fixtures/book.epub').readAsBytesSync();
  final redCover = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGP4z8AARAwQCgAf7gP9i18U1AAAAABJRU5ErkJggg==',
  );
  for (final format in KindleExportFormat.values) {
    test(
      '${format.extension}: new metadata is visible when a section has no EXTH',
      () async {
        final converter = KindlingConverter();
        final original = await converter.exportKindle(source, format: format);
        final headers = sections(records(original.bytes));
        final scenarios = <(Uint8List, int)>[
          (
            headers.length == 1 ? original.bytes : legacyOnly(original.bytes),
            0,
          ),
          if (headers.length > 1) (original.bytes, headers.last),
        ];
        for (final (book, index) in scenarios) {
          final input = withHeader(book, index, hasExth: false);
          final baseline = Uint8List.fromList(input);
          final before = records(input)[index];
          expect(exth(before), isEmpty);
          expect(ByteData.sublistView(before).getUint32(128) & 0x40, 0);
          final patch = KindleMetadataPatch(
            authors: ['New author'],
            publisher: 'New publisher',
            description: 'Metadata added to a section without EXTH.',
          );
          final result = await converter.rewriteMetadata(
            input,
            patch: patch,
            format: format,
          );
          expect(result.noOp, isFalse);
          expect(input, baseline);
          expectUnchangedResources(input, result.bytes);
          final after = records(result.bytes)[index];
          expect(ByteData.sublistView(after).getUint32(128) & 0x40, 0x40);
          final fields = exth(after);
          expect(fields[100]?.map(utf8.decode).toList(), ['New author']);
          expect(fields[101]?.map(utf8.decode).toList(), ['New publisher']);
          expect(fields[103]?.map(utf8.decode).toList(), [patch.description]);
          expect(fullName(after), fullName(before));
          await expectIdempotent(converter, result, patch, format);
        }
      },
    );

    test(
      '${format.extension}: title Clear removes header title without a nonempty EXTH 503',
      () async {
        final converter = KindlingConverter();
        final original = await converter.exportKindle(source, format: format);
        final headers = sections(records(original.bytes));
        for (final emptyRecord in [false, true]) {
          var input = Uint8List.fromList(original.bytes);
          for (final index in headers) {
            final fields = exth(records(input)[index]);
            expect(fields[542], isNotEmpty);
            if (emptyRecord) {
              fields[503] = [Uint8List(0)];
            } else {
              fields.remove(503);
            }
            input = withHeader(input, index, fields: fields);
            expect(fullName(records(input)[index]), isNotEmpty);
          }
          final baseline = Uint8List.fromList(input);
          final patch = KindleMetadataPatch(title: '');
          final result = await converter.rewriteMetadata(
            input,
            patch: patch,
            format: format,
          );
          expect(result.noOp, isFalse);
          expect(input, baseline);
          expectUnchangedResources(input, result.bytes);
          for (final index in headers) {
            final header = records(result.bytes)[index];
            final fields = exth(header);
            expect(fields.containsKey(503), isFalse);
            expect(fields.containsKey(542), isFalse);
            expect(ByteData.sublistView(header).getUint32(88), 0);
            expect(fullName(header), isEmpty);
          }
          await expectIdempotent(converter, result, patch, format);
        }
      },
    );

    test(
      '${format.extension}: all metadata fields, clear and untouched records',
      () async {
        final converter = KindlingConverter();
        final original = await converter.exportKindle(source, format: format);
        final patch = KindleMetadataPatch(
          title: 'Title 世界',
          authors: ['One', 'Béla'],
          publisher: 'Éditions',
          description: 'Description & notes',
          language: 'de',
          isbn: '9781234567897',
          asin: 'B012345678',
          publicationDate: '2026-11-12',
          subjects: ['A', '世界'],
          identifier: 'urn:uuid:12345678-1234-1234-1234-123456789abc',
        );
        final result = await converter.rewriteMetadata(
          original.bytes,
          patch: patch,
          format: format,
        );
        final before = records(original.bytes), after = records(result.bytes);
        final headers = sections(before);
        expect(after.length, before.length);
        for (var i = 0; i < before.length; i++) {
          if (!headers.contains(i)) {
            expect(after[i], before[i], reason: 'Record $i');
          }
        }
        for (final index in headers) {
          final fields = exth(after[index]);
          final expected = <int, List<String>>{
            503: ['Title 世界'],
            100: ['One', 'Béla'],
            101: ['Éditions'],
            103: ['Description & notes'],
            524: ['de'],
            104: ['9781234567897'],
            504: ['B012345678'],
            106: ['2026-11-12'],
            105: ['A', '世界'],
            113: ['urn:uuid:12345678-1234-1234-1234-123456789abc'],
          };
          for (final field in expected.entries) {
            expect(fields[field.key]?.map(utf8.decode).toList(), field.value);
          }
        }
        final repeated = await converter.rewriteMetadata(
          result.bytes,
          patch: patch,
          format: format,
        );
        expect(repeated.noOp, isTrue);
        expect(repeated.bytes, result.bytes);
        final cleared = await converter.rewriteMetadata(
          result.bytes,
          patch: KindleMetadataPatch(
            publisher: '',
            description: '',
            subjects: [],
            isbn: '',
          ),
          format: format,
        );
        for (final index in headers) {
          final fields = exth(records(cleared.bytes)[index]);
          for (final type in [101, 103, 105, 104]) {
            expect(fields.containsKey(type), isFalse);
          }
          expect(fields[100]?.map(utf8.decode).toList(), ['One', 'Béla']);
        }
      },
    );

    test(
      '${format.extension}: existing cover replacement retains content and obeys pixel budget',
      () async {
        final converter = KindlingConverter();
        final original = await converter.exportKindle(source, format: format);
        final before = records(original.bytes);
        final fields = exth(before.first);
        final firstImage = ByteData.sublistView(before.first).getUint32(108);
        final cover =
            firstImage + ByteData.sublistView(fields[201]!.first).getUint32(0);
        final changed = <int>{...sections(before), cover};
        if (fields[202] != null) {
          changed.add(
            firstImage + ByteData.sublistView(fields[202]!.first).getUint32(0),
          );
        }
        final result = await converter.rewriteMetadata(
          original.bytes,
          patch: KindleMetadataPatch(),
          cover: redCover,
          format: format,
        );
        final after = records(result.bytes);
        expect(after.length, before.length);
        expect(after[cover], isNot(equals(before[cover])));
        for (var i = 0; i < before.length; i++) {
          if (!changed.contains(i)) {
            expect(after[i], before[i], reason: 'Record $i');
          }
        }
        final bounded = KindlingConverter(
          limits: const EbookConversionLimits(maxImagePixels: 1),
        );
        await expectLater(
          bounded.rewriteMetadata(
            original.bytes,
            patch: KindleMetadataPatch(),
            cover: redCover,
            format: format,
          ),
          throwsA(
            isA<EbookConversionException>().having(
              (e) => e.code,
              'code',
              'limitExceeded',
            ),
          ),
        );
      },
    );
  }

  test(
    'Windows-1252 and mixed-section metadata is lossless or fails explicitly',
    () async {
      // Preserve the covered, valid publication while making its body valid in
      // either codepage; relabeling the original Greek/Japanese bytes is not a
      // Windows-1252 fixture.
      final book = EpubDocument.open(source);
      for (final chapter in book.chapters) {
        book.updateText(
          chapter.path,
          book.readText(chapter.path).replaceAll(RegExp(r'[^\x00-\x7f]'), '?'),
        );
      }
      final converter = KindlingConverter();
      final original = await converter.exportKindle(
        book.toBytes(),
        format: KindleExportFormat.legacyMobi,
      );
      final patch = KindleMetadataPatch(
        title: 'Café € —',
        authors: ['Béla', '€ditor'],
        publisher: 'Éditions',
        description: '“Quotes” — €',
        subjects: ['café', '€'],
      );
      const title1252 = [0x43, 0x61, 0x66, 0xe9, 0x20, 0x80, 0x20, 0x97];
      for (final candidate in [legacyOnly(original.bytes), original.bytes]) {
        final input = withHeader(candidate, 0, encoding: 1252);
        final baseline = Uint8List.fromList(input);
        final result = await converter.rewriteMetadata(
          input,
          patch: patch,
          format: KindleExportFormat.legacyMobi,
        );
        expect(result.noOp, isFalse);
        expect(input, baseline);
        expectUnchangedResources(input, result.bytes);
        final after = records(result.bytes);
        for (final index in sections(after)) {
          final header = after[index];
          expect(
            ByteData.sublistView(header).getUint32(28),
            index == 0 ? 1252 : 65001,
          );
          final fields = exth(header);
          final expected = <int, List<String>>{
            503: [patch.title!],
            100: patch.authors!,
            101: [patch.publisher!],
            103: [patch.description!],
            105: patch.subjects!,
          };
          for (final field in expected.entries) {
            expect(
              fields[field.key]
                  ?.map((value) => decodeMetadata(header, value))
                  .toList(),
              field.value,
            );
          }
          final title = index == 0 ? title1252 : utf8.encode(patch.title!);
          expect(fields[503]!.single, title);
          expect(fullName(header), title);
          expect(
            fields[542]!.single,
            md5.convert(title).bytes.take(4).toList(),
          );
        }
        await expectIdempotent(
          converter,
          result,
          patch,
          KindleExportFormat.legacyMobi,
        );
        for (final unsupported in [
          KindleMetadataPatch(title: '世界'),
          KindleMetadataPatch(authors: ['Author 😀']),
          KindleMetadataPatch(
            description: 'Must not replace U+0080 with Euro: \u0080',
          ),
        ]) {
          await expectLater(
            converter.rewriteMetadata(input, patch: unsupported),
            throwsA(
              isA<EbookConversionException>()
                  .having((error) => error.code, 'code', 'conversionFailed')
                  .having(
                    (error) => error.message,
                    'diagnostic',
                    contains(
                      'metadata cannot be represented losslessly in MOBI text encoding 1252',
                    ),
                  ),
            ),
          );
          expect(input, baseline);
        }
        final unknown = withHeader(input, 0, encoding: 932);
        final unknownBaseline = Uint8List.fromList(unknown);
        await expectLater(
          converter.rewriteMetadata(
            unknown,
            patch: KindleMetadataPatch(title: 'New ASCII title'),
          ),
          throwsA(
            isA<EbookConversionException>()
                .having((error) => error.code, 'code', 'conversionFailed')
                .having(
                  (error) => error.message,
                  'diagnostic',
                  contains('unsupported MOBI text encoding 932'),
                ),
          ),
        );
        expect(unknown, unknownBaseline);
        final noop = await converter.rewriteMetadata(
          input,
          patch: KindleMetadataPatch(),
        );
        expect(noop.noOp, isTrue);
        expect(noop.bytes, input);
      }
    },
  );

  test('capabilities describe independent operations', () {
    const native = EbookConversionCapabilities(
      available: true,
      runtime: EbookConversionRuntime.native,
      cancellationMode: EbookCancellationMode.cooperative,
    );
    expect(
      native.canExportAzw3 &&
          native.canExportLegacyMobi &&
          native.canRewriteKindleMetadata &&
          native.canReplaceKindleCover,
      isTrue,
    );
    const metadata = EbookConversionCapabilities(
      available: true,
      runtime: EbookConversionRuntime.webAssembly,
      cancellationMode: EbookCancellationMode.workerTermination,
      canExportAzw3: false,
      canExportLegacyMobi: false,
      canRewriteKindleMetadata: true,
      canReplaceKindleCover: false,
    );
    expect(metadata.canRewriteKindleMetadata, isTrue);
    expect(
      metadata.canExportAzw3 ||
          metadata.canExportLegacyMobi ||
          metadata.canReplaceKindleCover,
      isFalse,
    );
  });
}
