import 'dart:async';
import 'dart:typed_data';

import 'package:crisp_cloud/services/image_edit_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

import 'support/image_editor_fixture.dart';

Matcher _failure(ImageEditFailure reason) => isA<ImageEditException>().having(
  (error) => error.reason,
  'reason',
  reason,
);

ImageEditSession _session({ImageFileFormat format = ImageFileFormat.png}) {
  final session = ImageEditSession(
    initialBytes: buildImageEditorFixture(format: format),
    format: format,
  );
  addTearDown(session.dispose);
  return session;
}

void main() {
  group('image format policy', () {
    test('only exact PNG/JPEG suffixes are editable', () {
      for (final name in ['photo.png', 'photo.PNG', 'photo.jpg', 'x.JPEG']) {
        expect(isEditableImageFileName(name), isTrue, reason: name);
      }
      for (final name in [
        'photo.gif', 'photo.webp', 'photo.apng', 'photo.svg', 'photo.heic',
        'photo.tiff', 'photo.png.txt', 'photo.jpg.', 'README', '',
      ]) {
        expect(isEditableImageFileName(name), isFalse, reason: name);
      }
    });

    for (final format in ImageFileFormat.values) {
      test('inspects actual $format pixels and dimensions', () {
        final bytes = buildImageEditorFixture(format: format);
        final info = inspectEditableImage(
          bytes,
          fileName: format == ImageFileFormat.png ? 'x.PNG' : 'x.JPEG',
        );
        expect(info.format, format);
        expect((info.width, info.height), (24, 16));
        expect(() => validateImageEditorOutput(bytes, format), returnsNormally);
      });
    }

    test('filename and encoded content must agree', () {
      expect(
        () => inspectEditableImage(buildImageEditorFixture(), fileName: 'x.jpg'),
        throwsA(_failure(ImageEditFailure.formatMismatch)),
      );
      expect(
        () => inspectEditableImage(
          buildImageEditorFixture(format: ImageFileFormat.jpeg),
          fileName: 'x.png',
        ),
        throwsA(_failure(ImageEditFailure.formatMismatch)),
      );
      expect(
        () => inspectEditableImage(buildImageEditorFixture(), fileName: 'x.gif'),
        throwsA(_failure(ImageEditFailure.unsupportedFormat)),
      );
      expect(
        () => inspectEditableImage(Uint8List.fromList([71, 73, 70]), fileName: 'x.png'),
        throwsA(_failure(ImageEditFailure.invalidImage)),
      );
    });

    test('rejects APNG instead of overwriting it with its first frame', () {
      expect(
        () => inspectEditableImage(imageTestAnimatedPng(), fileName: 'x.png'),
        throwsA(_failure(ImageEditFailure.animatedImage)),
      );
    });

    test('rejects corrupt CRCs and incomplete/trailing PNG chunks', () {
      final png = buildImageEditorFixture();
      final corrupt = Uint8List.fromList(png)..[29] ^= 1;
      for (final bytes in [
        corrupt,
        Uint8List.fromList(png.sublist(0, png.length - 1)),
        Uint8List.fromList([...png, 0]),
        Uint8List.fromList(png.sublist(0, 33)),
      ]) {
        expect(
          () => inspectEditableImage(bytes, fileName: 'x.png'),
          throwsA(_failure(ImageEditFailure.invalidImage)),
        );
      }
    });

    test('rejects JPEG missing EOI or containing appended frames', () {
      final jpg = buildImageEditorFixture(format: ImageFileFormat.jpeg);
      for (final bytes in [
        Uint8List.fromList(jpg.sublist(0, jpg.length - 2)),
        Uint8List.fromList([...jpg, ...jpg]),
        Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]),
        Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 0xff, 0xff]),
      ]) {
        expect(
          () => inspectEditableImage(bytes, fileName: 'x.jpg'),
          throwsA(_failure(ImageEditFailure.invalidImage)),
        );
      }
    });

    test('rejects a JPEG multi-picture marker even with a .jpg suffix', () {
      final jpg = buildImageEditorFixture(format: ImageFileFormat.jpeg);
      final mpo = Uint8List.fromList([
        ...jpg.sublist(0, 2),
        0xff, 0xe2, 0, 6, 77, 80, 70, 0,
        ...jpg.sublist(2),
      ]);
      expect(
        () => inspectEditableImage(mpo, fileName: 'x.jpg'),
        throwsA(_failure(ImageEditFailure.animatedImage)),
      );
    });

    test('bounds pixels and dimensions before trying to decode them', () {
      for (final dimensions in [
        (kImageEditorMaxDimension + 1, 1),
        (1, kImageEditorMaxDimension + 1),
        (10000, 10000),
      ]) {
        expect(
          () => inspectEditableImage(
            imageTestPngWithDimensions(dimensions.$1, dimensions.$2),
            fileName: 'x.png',
          ),
          throwsA(_failure(ImageEditFailure.dimensionsTooLarge)),
        );
      }
      expect(
        () => inspectEditableImage(imageTestPngWithDimensions(0, 16), fileName: 'x.png'),
        throwsA(_failure(ImageEditFailure.invalidImage)),
      );
    });

    test('rejects oversized encoded inputs before format parsing', () {
      expect(
        () => inspectEditableImage(
          Uint8List(kImageEditorInputLimitBytes + 1),
          fileName: 'x.png',
        ),
        throwsA(_failure(ImageEditFailure.inputTooLarge)),
      );
    });

    test('a valid container with invalid pixels cannot be saved', () {
      final broken = imageTestUndecodablePng();
      expect(inspectEditableImage(broken, fileName: 'x.png').width, 24);
      expect(
        () => validateImageEditorOutput(broken, ImageFileFormat.png),
        throwsA(_failure(ImageEditFailure.invalidImage)),
      );
    });

    test('PNG output retains transparent pixels and dimensions', () {
      final bytes = buildImageEditorFixture();
      validateImageEditorOutput(bytes, ImageFileFormat.png);
      final decoded = image.decodePng(bytes)!;
      expect((decoded.width, decoded.height), (24, 16));
      expect(decoded.getPixel(0, 4).a, 0);
      expect(decoded.getPixel(1, 4).a, 255);
    });
  });

  group('host image edit session', () {
    test('owns immutable saved bytes and starts at a custom clean revision', () {
      final bytes = buildImageEditorFixture();
      final expected = Uint8List.fromList(bytes);
      final session = ImageEditSession(
        initialBytes: bytes,
        format: ImageFileFormat.png,
        initialRevision: 42,
      );
      addTearDown(session.dispose);
      bytes[0] = 0;
      expect(session.savedBytes, expected);
      expect(() => session.savedBytes[0] = 0, throwsUnsupportedError);
      expect(session.currentRevision, 42);
      expect(session.savedRevision, 42);
      expect(session.isDirty, isFalse);
      session.updateRevision(43);
      expect(session.isDirty, isTrue);
      session.updateRevision(42);
      expect(session.isDirty, isFalse);
    });

    test('captures and persists a revision before marking it clean', () async {
      final session = _session()..updateRevision(1);
      final bytes = buildImageEditorFixture(seed: 1);
      final upload = Completer<ImageSaveOutcome>();
      final invoked = Completer<void>();
      late Uint8List written;
      final saving = session.save(
        export: () async => bytes,
        write: (snapshot) {
          written = snapshot;
          invoked.complete();
          return upload.future;
        },
      );
      await invoked.future;
      expect(session.isSaving, isTrue);
      expect(session.isDirty, isTrue);
      expect(session.savedRevision, 0);
      expect(written, bytes);
      bytes[0] = 0;
      expect(written[0], 137, reason: 'The exporter can reuse a mutable buffer');
      expect(() => written[0] = 0, throwsUnsupportedError);
      upload.complete(ImageSaveOutcome.savedOriginal);
      expect(await saving, ImageSaveOutcome.savedOriginal);
      expect(session.savedBytes, written);
      expect(session.savedRevision, 1);
      expect(session.isDirty, isFalse);
      expect(session.isSaving, isFalse);
    });

    test('a newer edit during upload remains unsaved', () async {
      final session = _session()..updateRevision(1);
      final upload = Completer<ImageSaveOutcome>();
      final invoked = Completer<void>();
      final saving = session.save(
        export: () async => buildImageEditorFixture(seed: 1),
        write: (_) {
          invoked.complete();
          return upload.future;
        },
      );
      await invoked.future;
      session.updateRevision(2);
      upload.complete(ImageSaveOutcome.savedOriginal);
      await saving;
      expect(session.isDirty, isTrue);
      expect(session.savedRevision, 1);
      session.updateRevision(1);
      expect(session.isDirty, isFalse);
      session.updateRevision(3);
      expect(session.isDirty, isTrue, reason: 'New branch tokens must differ');
    });

    test('a revision changed during capture is never written', () async {
      final session = _session()..updateRevision(1);
      final capture = Completer<Uint8List>();
      var writes = 0;
      final saving = session.save(
        export: () => capture.future,
        write: (_) async {
          writes++;
          return ImageSaveOutcome.savedOriginal;
        },
      );
      session.updateRevision(2);
      final failed = expectLater(saving, throwsA(_failure(ImageEditFailure.staleExport)));
      capture.complete(buildImageEditorFixture(seed: 1));
      await failed;
      expect(writes, 0);
      expect(session.savedRevision, 0);
      expect(session.isDirty, isTrue);
      expect(session.isSaving, isFalse);
    });

    test('concurrent saves are rejected before a second capture begins', () async {
      final session = _session()..updateRevision(1);
      final capture = Completer<Uint8List>();
      final saving = session.save(
        export: () => capture.future,
        write: (_) async => ImageSaveOutcome.savedOriginal,
      );
      var secondCaptured = false;
      await expectLater(
        session.save(
          export: () async {
            secondCaptured = true;
            return buildImageEditorFixture();
          },
          write: (_) async => ImageSaveOutcome.savedOriginal,
        ),
        throwsA(isA<ImageSaveInProgressException>()),
      );
      expect(secondCaptured, isFalse);
      capture.complete(buildImageEditorFixture(seed: 1));
      await saving;
    });

    test('failed writes preserve the source baseline and can be retried', () async {
      final session = _session()..updateRevision(1);
      final initial = session.savedBytes;
      final failure = StateError('offline');
      await expectLater(
        session.save(
          export: () async => buildImageEditorFixture(seed: 1),
          write: (_) async => throw failure,
        ),
        throwsA(same(failure)),
      );
      expect(session.lastError, same(failure));
      expect(session.savedBytes, initial);
      expect(session.savedRevision, 0);
      expect(session.isDirty, isTrue);
      expect(session.isSaving, isFalse);
      await session.save(
        export: () async => buildImageEditorFixture(seed: 1),
        write: (_) async => ImageSaveOutcome.savedOriginal,
      );
      expect(session.isDirty, isFalse);
      expect(session.lastError, isNull);
    });

    test('failed export releases busy state without writing', () async {
      final session = _session()..updateRevision(1);
      final failure = StateError('capture unavailable');
      var writes = 0;
      await expectLater(
        session.save(
          export: () async => throw failure,
          write: (_) async {
            writes++;
            return ImageSaveOutcome.savedOriginal;
          },
        ),
        throwsA(same(failure)),
      );
      expect(writes, 0);
      expect(session.isSaving, isFalse);
      expect(session.isDirty, isTrue);
    });

    test('empty, wrong-format and undecodable captures never reach storage', () async {
      final session = _session()..updateRevision(1);
      var writes = 0;
      for (final bytes in [
        Uint8List(0),
        buildImageEditorFixture(format: ImageFileFormat.jpeg),
        imageTestUndecodablePng(),
      ]) {
        await expectLater(
          session.save(
            export: () async => bytes,
            write: (_) async {
              writes++;
              return ImageSaveOutcome.savedOriginal;
            },
          ),
          throwsA(isA<ImageEditException>()),
        );
        expect(session.isDirty, isTrue);
        expect(session.isSaving, isFalse);
      }
      expect(writes, 0);
    });

    for (final outcome in [ImageSaveOutcome.savedCopy, ImageSaveOutcome.downloadedCopy]) {
      test('$outcome keeps the original dirty', () async {
        final session = _session()..updateRevision(1);
        final original = session.savedBytes;
        expect(
          await session.save(
            export: () async => buildImageEditorFixture(seed: 1),
            write: (_) async => outcome,
          ),
          outcome,
        );
        expect(session.savedBytes, original);
        expect(session.isDirty, isTrue);
        expect(session.lastSaveOutcome, outcome);
      });
    }

    test('disposing during export prevents a new orphaned write', () async {
      final session = ImageEditSession(
        initialBytes: buildImageEditorFixture(),
        format: ImageFileFormat.png,
      )..updateRevision(1);
      final capture = Completer<Uint8List>();
      var writes = 0;
      final saving = session.save(
        export: () => capture.future,
        write: (_) async {
          writes++;
          return ImageSaveOutcome.savedOriginal;
        },
      );
      session.dispose();
      final failed = expectLater(saving, throwsStateError);
      capture.complete(buildImageEditorFixture(seed: 1));
      await failed;
      expect(writes, 0);
    });

    test('an already-started upload can finish after disposal', () async {
      final session = ImageEditSession(
        initialBytes: buildImageEditorFixture(),
        format: ImageFileFormat.png,
      )..updateRevision(1);
      final upload = Completer<ImageSaveOutcome>();
      final invoked = Completer<void>();
      final saving = session.save(
        export: () async => buildImageEditorFixture(seed: 1),
        write: (_) {
          invoked.complete();
          return upload.future;
        },
      );
      await invoked.future;
      session.dispose();
      upload.complete(ImageSaveOutcome.savedOriginal);
      await expectLater(saving, completion(ImageSaveOutcome.savedOriginal));
      expect(() => session.updateRevision(2), throwsStateError);
    });
  });
}
