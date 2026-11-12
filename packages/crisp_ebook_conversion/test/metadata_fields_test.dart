@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_ebook_conversion/crisp_ebook_conversion.dart';
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

void main() {
  final source = File('test/fixtures/book.epub').readAsBytesSync();
  final redCover = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGP4z8AARAwQCgAf7gP9i18U1AAAAABJRU5ErkJggg==',
  );
  for (final format in KindleExportFormat.values) {
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
