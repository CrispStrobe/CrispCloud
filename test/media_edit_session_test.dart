import 'package:crisp_cloud/services/media_edit_session.dart';
import 'package:crisp_cloud/services/media_editor_backend.dart';
import 'package:flutter_test/flutter_test.dart';

const audio = MediaInfo(
  kind: MediaKind.audio,
  duration: Duration(seconds: 20),
  sampleRate: 48000,
  channels: 2,
);

void main() {
  test(
    'export captures immutable recipe and locks history until completion',
    () {
      final session = MediaEditSession(audio);
      session.apply(
        session.edit.copyWith(
          start: const Duration(seconds: 2),
          end: const Duration(seconds: 10),
          gainDb: -6,
        ),
      );
      final revision = session.beginExport();
      expect(revision.edit.duration, const Duration(seconds: 8));
      expect(session.canUndo, isFalse);
      expect(
        () => session.apply(session.edit.copyWith(gainDb: 3)),
        throwsA(isA<MediaEditException>()),
      );
      session.undo();
      expect(identical(session.revision, revision), isTrue);
      session.finishExport(revision, persisted: true);
      expect(session.isDirty, isFalse);
      expect(session.canUndo, isTrue);
    },
  );

  test('failed save and preview never mark edits clean', () {
    final session = MediaEditSession(audio);
    session.apply(session.edit.copyWith(fadeIn: const Duration(seconds: 1)));
    final preview = session.beginExport();
    session.finishExport(preview, persisted: false);
    expect(session.isDirty, isTrue);
    final retry = session.beginExport();
    expect(identical(preview, retry), isTrue);
    session.finishExport(retry, persisted: true);
    expect(session.isDirty, isFalse);
  });

  test('undo branches cannot reuse the identity of a saved recipe', () {
    final session = MediaEditSession(audio);
    session.apply(session.edit.copyWith(gainDb: -3));
    final saved = session.beginExport();
    session.finishExport(saved, persisted: true);
    session.undo();
    expect(session.isDirty, isTrue);
    session.redo();
    expect(session.isDirty, isFalse);
    session.undo();
    session.apply(session.edit.copyWith(gainDb: 3));
    expect(session.revision.id, isNot(saved.id));
    expect(session.isDirty, isTrue);
    expect(session.canRedo, isFalse);
  });

  test('a stale export cannot complete another operation', () {
    final session = MediaEditSession(audio);
    final first = session.beginExport();
    session.finishExport(first, persisted: false);
    session.apply(session.edit.copyWith(gainDb: 2));
    final second = session.beginExport();
    expect(
      () => session.finishExport(first, persisted: true),
      throwsStateError,
    );
    expect(session.isExporting, isTrue);
    expect(session.isDirty, isTrue);
    session.finishExport(second, persisted: false);
  });

  test('invalid time ranges and nonfinite gain never reach a renderer', () {
    final session = MediaEditSession(audio);
    for (final edit in [
      session.edit.copyWith(start: const Duration(seconds: -1)),
      session.edit.copyWith(end: Duration.zero),
      session.edit.copyWith(end: const Duration(seconds: 21)),
      session.edit.copyWith(gainDb: double.nan),
      session.edit.copyWith(gainDb: double.infinity),
      session.edit.copyWith(gainDb: 13),
      session.edit.copyWith(fadeIn: const Duration(seconds: 21)),
      session.edit.copyWith(fadeOut: const Duration(microseconds: -1)),
      session.edit.copyWith(quarterTurns: 1),
    ]) {
      expect(() => session.apply(edit), throwsA(isA<MediaEditException>()));
    }
    expect(session.canUndo, isFalse);
  });

  test('video rejects malformed crops and unavailable audio processing', () {
    final session = MediaEditSession(
      const MediaInfo(
        kind: MediaKind.video,
        duration: Duration(seconds: 4),
        width: 1920,
        height: 1080,
      ),
    );
    for (final edit in [
      session.edit.copyWith(
        crop: const MediaCrop(x: 0.5, y: 0, width: 0.6, height: 1),
      ),
      session.edit.copyWith(
        crop: const MediaCrop(x: 0, y: double.nan, width: 1, height: 1),
      ),
      session.edit.copyWith(maxOutputHeight: 1),
      session.edit.copyWith(quarterTurns: 4),
      session.edit.copyWith(gainDb: -6),
      session.edit.copyWith(fadeIn: const Duration(seconds: 1)),
    ]) {
      expect(() => session.apply(edit), throwsA(isA<MediaEditException>()));
    }
    session.apply(
      session.edit.copyWith(
        crop: const MediaCrop(x: 0.25, y: 0, width: 0.5, height: 1),
        quarterTurns: 1,
        muted: true,
        maxOutputHeight: 720,
      ),
    );
    expect(session.isDirty, isTrue);
  });

  test('cancellation is idempotent and late subscribers are notified', () {
    final cancellation = MediaCancellation();
    var calls = 0;
    void listener() => calls++;
    cancellation.addListener(listener);
    cancellation.cancel();
    cancellation.cancel();
    expect(calls, 1);
    cancellation.addListener(listener);
    expect(calls, 2);
    expect(
      cancellation.throwIfCancelled,
      throwsA(isA<MediaOperationCancelled>()),
    );
  });
}
