import 'dart:convert';

import 'package:crisperbooks/crisperbooks.dart';
import 'package:flutter_test/flutter_test.dart';

EbookReadingData data({
  String? hash,
  String note = 'Grüße — 日本語 📖',
  EbookReaderRenderer renderer = EbookReaderRenderer.foliate,
}) => EbookReadingData.capture(
  contentSha256: hash ?? List.filled(64, 'a').join(),
  contentByteLength: 2048,
  renderer: renderer,
  appearance: const EbookAppearance(theme: 'sepia'),
  bookmarks: const [],
  highlights: renderer == EbookReaderRenderer.foliate
      ? [
          EbookHighlight(
            id: 'annotation-1',
            cfi: 'epubcfi(/6/2!/4/2:0)',
            note: note,
          ),
        ]
      : [],
);

void main() {
  test('retains existing sidecar format and Unicode without host storage', () {
    final original = data();
    final encoded = original.encode();
    expect(jsonDecode(encoded)['format'], 'crispcloud-ebook-reading-data');
    final reopened = EbookReadingData.decode(encoded);
    expect(reopened.encode(), encoded);
    expect(reopened.highlights.single.note, 'Grüße — 日本語 📖');
    expect(reopened.fingerprint, original.fingerprint);
    expect(reopened.noteCount, 1);
    expect(() => reopened.highlights.clear(), throwsUnsupportedError);
  });

  test('merge policies preserve explicit conflict choice and idempotence', () {
    final local = data(note: 'Local note');
    final remote = data(note: 'Imported note');
    for (final mode in EbookReadingDataMergeMode.values) {
      final plan = EbookReadingDataImportPlan.prepare(
        bindingKey: 'host-owned-binding',
        local: local,
        imported: remote,
        mode: mode,
      );
      expect(plan.conflictCount, 1);
      expect(
        plan.result.highlights.single.note,
        mode == EbookReadingDataMergeMode.mergeKeepExisting
            ? 'Local note'
            : 'Imported note',
      );
      final repeated = EbookReadingDataImportPlan.prepare(
        bindingKey: 'host-owned-binding',
        local: plan.result,
        imported: remote,
        mode: mode,
      );
      expect(repeated.hasChanges, isFalse);
    }
  });

  test('content and renderer identities cannot be silently mixed', () {
    expect(
      () => data().requireCompatible(data(hash: List.filled(64, 'b').join())),
      throwsA(
        isA<EbookReadingDataException>().having(
          (e) => e.code,
          'code',
          EbookReadingDataError.contentMismatch,
        ),
      ),
    );
    expect(
      () => data().requireCompatible(
        data(renderer: EbookReaderRenderer.portable),
      ),
      throwsA(
        isA<EbookReadingDataException>().having(
          (e) => e.code,
          'code',
          EbookReadingDataError.rendererMismatch,
        ),
      ),
    );
  });

  test(
    'rejects unknown credential fields and over-budget JSON before import',
    () {
      final invalid = data().toJson()..['accountToken'] = 'never accepted';
      expect(
        () => EbookReadingData.fromJson(invalid),
        throwsA(isA<EbookReadingDataException>()),
      );
      expect(
        () => EbookReadingData.decode(
          List.filled(EbookReadingData.maximumJsonBytes + 1, ' ').join(),
        ),
        throwsA(
          isA<EbookReadingDataException>().having(
            (e) => e.code,
            'code',
            EbookReadingDataError.tooLarge,
          ),
        ),
      );
    },
  );
}
