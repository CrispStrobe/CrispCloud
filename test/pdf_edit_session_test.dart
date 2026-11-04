import 'dart:async';
import 'dart:typed_data';

import 'package:crisp_cloud/services/pdf_edit_session.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(int value) => Uint8List.fromList([37, 80, 68, 70, value]);

void main() {
  test('owns the initial bytes and distinguishes equal-length revisions', () {
    final original = _bytes(1);
    final session = PdfEditSession(initialBytes: original);
    addTearDown(session.dispose);

    original[4] = 9;
    expect(session.bytes, _bytes(1));
    expect(session.isDirty, isFalse);
    expect(() => session.bytes[4] = 4, throwsUnsupportedError);

    session.updateBytes(_bytes(2));
    expect(session.isDirty, isTrue);
    session.updateBytes(_bytes(1));
    expect(session.isDirty, isFalse, reason: 'Undo back to the baseline is clean');
  });

  test('saves a snapshot and leaves later edits dirty', () async {
    final session = PdfEditSession(initialBytes: _bytes(1));
    addTearDown(session.dispose);
    final editingBuffer = _bytes(2);
    session.updateBytes(editingBuffer);
    final upload = Completer<PdfSaveOutcome>();
    late Uint8List sent;
    final saving = session.save((bytes) {
      sent = bytes;
      return upload.future;
    });

    expect(session.isSaving, isTrue);
    editingBuffer[4] = 3;
    session.updateBytes(editingBuffer);
    expect(sent, _bytes(2), reason: 'The editor can reuse its byte buffer');

    upload.complete(PdfSaveOutcome.savedOriginal);
    expect(await saving, PdfSaveOutcome.savedOriginal);
    expect(session.isSaving, isFalse);
    expect(session.isDirty, isTrue);
    expect(session.bytes, _bytes(3));

    session.updateBytes(_bytes(2));
    expect(session.isDirty, isFalse, reason: 'Only the uploaded revision is clean');
  });

  test('rejects overlapping saves and preserves a failed revision for retry',
      () async {
    final session = PdfEditSession(initialBytes: _bytes(1));
    addTearDown(session.dispose);
    session.updateBytes(_bytes(2));
    final upload = Completer<PdfSaveOutcome>();
    final saving = session.save((_) => upload.future);
    var secondWriterCalled = false;
    await expectLater(
      session.save((_) async {
        secondWriterCalled = true;
        return PdfSaveOutcome.savedCopy;
      }),
      throwsA(isA<PdfSaveInProgressException>()),
    );
    expect(secondWriterCalled, isFalse);

    final failure = StateError('Offline');
    final failed = expectLater(saving, throwsA(same(failure)));
    upload.completeError(failure);
    await failed;
    expect(session.isDirty, isTrue);
    expect(session.isSaving, isFalse);
    expect(session.lastError, same(failure));

    await session.save((bytes) async {
      expect(bytes, _bytes(2));
      return PdfSaveOutcome.savedOriginal;
    });
    expect(session.isDirty, isFalse);
    expect(session.lastError, isNull);
  });

  for (final outcome in [
    PdfSaveOutcome.savedCopy,
    PdfSaveOutcome.downloadedCopy,
  ]) {
    test('$outcome does not pretend that the original was saved', () async {
      final session = PdfEditSession(initialBytes: _bytes(1));
      addTearDown(session.dispose);
      session.updateBytes(_bytes(2));
      await session.save((_) async => outcome);
      expect(session.isDirty, isTrue);
      expect(session.lastSaveOutcome, outcome);
      session.updateBytes(_bytes(1));
      expect(session.isDirty, isFalse);
    });
  }

  test('an upload can complete after the host is disposed', () async {
    final session = PdfEditSession(initialBytes: _bytes(1));
    final upload = Completer<PdfSaveOutcome>();
    final saving = session.save((_) => upload.future);
    session.dispose();
    upload.complete(PdfSaveOutcome.savedOriginal);
    await expectLater(saving, completion(PdfSaveOutcome.savedOriginal));
    expect(() => session.updateBytes(_bytes(2)), throwsStateError);
  });
}
