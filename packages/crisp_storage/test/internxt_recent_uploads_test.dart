import 'package:crisp_storage/src/cloud/internxt_streaming_transfer.dart';
import 'package:test/test.dart';

void main() {
  setUp(InternxtRecentUploads.clear);

  test('a fresh upload is listed until the server shows it', () {
    InternxtRecentUploads.add('dir', {'uuid': 'f1', 'name': 'blob'});
    final lagging = InternxtRecentUploads.merge('dir', [
      {'uuid': 'old', 'name': 'old'},
    ]);
    expect(lagging.map((f) => (f as Map)['uuid']), ['old', 'f1']);

    final caughtUp = InternxtRecentUploads.merge('dir', [
      {'uuid': 'f1', 'name': 'blob'},
    ]);
    expect(caughtUp, hasLength(1));
    // Once seen, it is no longer added even if a later listing lags again.
    expect(InternxtRecentUploads.merge('dir', const []), isEmpty);
  });

  test('other folders are unaffected', () {
    InternxtRecentUploads.add('dir', {'uuid': 'f1'});
    expect(InternxtRecentUploads.merge('other', const []), isEmpty);
  });

  test('entries expire after the TTL', () {
    InternxtRecentUploads.add('dir', {'uuid': 'f1'});
    final later = DateTime.now().add(
      InternxtRecentUploads.ttl + const Duration(seconds: 1),
    );
    expect(InternxtRecentUploads.merge('dir', const [], now: later), isEmpty);
  });

  test('re-uploading the same uuid keeps one entry', () {
    InternxtRecentUploads.add('dir', {'uuid': 'f1', 'size': 1});
    InternxtRecentUploads.add('dir', {'uuid': 'f1', 'size': 2});
    final merged = InternxtRecentUploads.merge('dir', const []);
    expect(merged, hasLength(1));
    expect((merged.single as Map)['size'], 2);
  });

  group('listing names', () {
    test('appends the stored extension', () {
      expect(
        internxtListingFile({'name': 'blob', 'fileType': 'bin'})['name'],
        'blob.bin',
      );
      expect(
        internxtListingFile({'name': 'x.bin', 'fileType': 'bin'})['name'],
        'x.bin.bin',
      );
      expect(
        internxtListingFile({'name': 'report', 'fileType': 'file'})['name'],
        'report.file',
      );
      expect(
        internxtListingFile({'name': 'README', 'fileType': ''})['name'],
        'README',
      );
      expect(
        internxtListingFile({'plainName': 'a', 'fileType': 'txt'})['name'],
        'a.txt',
      );
    });

    test('keeps the other fields', () {
      final row = internxtListingFile({
        'name': 'a',
        'fileType': 'txt',
        'uuid': 'u',
        'type': 'file',
      });
      expect(row, {
        'name': 'a.txt',
        'fileType': 'txt',
        'uuid': 'u',
        'type': 'file',
      });
    });
  });

  group('HTTP status errors', () {
    test('transient statuses', () {
      for (final status in [408, 429, 500, 502, 503]) {
        expect(
          InternxtHttpStatusError('op', status).isTransient,
          isTrue,
          reason: '$status',
        );
      }
      for (final status in [400, 401, 402, 403, 404, 409]) {
        expect(
          InternxtHttpStatusError('op', status).isTransient,
          isFalse,
          reason: '$status',
        );
      }
    });

    test('keeps the previous message and is a StateError', () {
      final error = InternxtHttpStatusError(
        'Internxt upload verification',
        404,
      );
      expect(error, isA<StateError>());
      expect(error.message, 'Internxt upload verification failed (404).');
    });
  });
}
