import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/services/ebook_reading_data.dart';
import 'package:crisp_cloud/services/ebook_reading_data_files.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'rejects an oversized declared file without subscribing to its stream',
    () async {
      var listened = false;
      final stream = StreamController<List<int>>(
        onListen: () => listened = true,
      );
      await expectLater(
        readEbookReadingDataFile(
          PlatformFile(
            name: 'large.json',
            size: EbookReadingData.maximumJsonBytes + 1,
            readStream: stream.stream,
          ),
        ),
        throwsA(
          isA<EbookReadingDataException>().having(
            (e) => e.code,
            'code',
            EbookReadingDataError.tooLarge,
          ),
        ),
      );
      expect(listened, isFalse);
      unawaited(stream.close());
    },
  );

  test(
    'bounds the real stream even when the provider understates the size',
    () async {
      var canceled = false;
      final stream = StreamController<List<int>>(
        onCancel: () => canceled = true,
      );
      final read = readEbookReadingDataFile(
        PlatformFile(name: 'lie.json', size: 2, readStream: stream.stream),
      );
      final expectation = expectLater(
        read,
        throwsA(isA<EbookReadingDataException>()),
      );
      stream.add(Uint8List(EbookReadingData.maximumJsonBytes));
      stream.add([1]);
      await expectation;
      expect(canceled, isTrue);
      await stream.close();
    },
  );

  test(
    'decodes UTF-8 split across chunks and rejects malformed text',
    () async {
      final bytes = utf8.encode('{"note":"Grüße 日本語 📖"}');
      final text = await readEbookReadingDataFile(
        PlatformFile(
          name: 'notes.json',
          size: bytes.length,
          readStream: Stream.fromIterable(bytes.map((byte) => [byte])),
        ),
      );
      expect(jsonDecode(text), {'note': 'Grüße 日本語 📖'});
      await expectLater(
        readEbookReadingDataFile(
          PlatformFile(
            name: 'bad.json',
            size: 1,
            bytes: Uint8List.fromList([0xff]),
          ),
        ),
        throwsA(
          isA<EbookReadingDataException>().having(
            (e) => e.code,
            'code',
            EbookReadingDataError.invalid,
          ),
        ),
      );
    },
  );

  test('missing contents do not fall back to an unbounded path read', () async {
    await expectLater(
      readEbookReadingDataFile(
        PlatformFile(
          name: 'missing.json',
          path: '/not-an-authorized-read.json',
          size: 1,
        ),
      ),
      throwsA(isA<EbookReadingDataException>()),
    );
  });
}
