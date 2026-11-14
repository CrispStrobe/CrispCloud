import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

SlideEditorController _controller({OfficeInteractionMode? mode}) {
  final controller = SlideEditorController(
    config: OfficeSurfaceConfig(mode: mode ?? OfficeInteractionMode.editing),
    presentation: PmlPresentation(
      slides: [
        PmlSlide(id: 256, notes: 'Original notes'),
        PmlSlide(id: 257, notes: 'Neighbor notes'),
      ],
    ),
  );
  addTearDown(controller.dispose);
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('notes-only edits become dirty and undo on the owning slide', () {
    final controller = _controller();
    final owning = controller.slide;
    final initialRevision = controller.contentRevision;
    controller.setSpeakerNotes('Updated notes');
    expect(controller.isDirty, isTrue);
    expect(controller.canUndo, isTrue);
    expect(controller.contentRevision, initialRevision + 1);
    controller.setActiveSlide(1);
    controller.undo();
    expect(owning.notes, 'Original notes');
    expect(controller.speakerNotes, 'Neighbor notes');
    expect(controller.contentRevision, initialRevision + 2);
    controller.redo();
    expect(owning.notes, 'Updated notes');
    expect(controller.speakerNotes, 'Neighbor notes');
    expect(controller.contentRevision, initialRevision + 3);
  });

  test('unchanged notes retain clean state and pending redo history', () {
    final controller = _controller();
    var notifications = 0;
    controller.addListener(() => notifications++);
    controller.setSpeakerNotes('Original notes');
    expect(controller.isDirty, isFalse);
    expect(controller.canUndo, isFalse);
    expect(controller.contentRevision, 0);
    expect(notifications, 0);
    controller.setSpeakerNotes('Updated notes');
    controller.undo();
    controller.markClean();
    final revision = controller.contentRevision;
    final beforeNotifications = notifications;
    controller.setSpeakerNotes('Original notes');
    expect(controller.isDirty, isFalse);
    expect(controller.canRedo, isTrue);
    expect(controller.contentRevision, revision);
    expect(notifications, beforeNotifications);
    controller.redo();
    expect(controller.speakerNotes, 'Updated notes');
  });

  for (final mode in [
    OfficeInteractionMode.viewing,
    OfficeInteractionMode.selecting,
  ]) {
    test('$mode blocks speaker-note mutations and history', () {
      final controller = _controller(mode: mode);
      controller.setSpeakerNotes('Blocked');
      expect(controller.speakerNotes, 'Original notes');
      expect(controller.isDirty, isFalse);
      expect(controller.canUndo, isFalse);
      expect(controller.contentRevision, 0);
    });
  }

  for (final asynchronous in [false, true]) {
    test(
      'notes and clearing survive ${asynchronous ? 'isolate' : 'direct'} save',
      () async {
        final controller = _controller();
        const updated = 'Updated <note> & detail\nSecond line';
        controller.setSpeakerNotes(updated);
        for (final expected in [updated, '', updated]) {
          if (expected.isEmpty) {
            controller.setSpeakerNotes('');
          } else if (controller.speakerNotes.isEmpty) {
            controller.undo();
          }
          final bytes = asynchronous
              ? await controller.saveBytesAsync()
              : controller.saveBytes();
          final saved = SlideDeserializer().read(OpcPackage.openBytes(bytes));
          expect(saved.slides[0].notes, expected);
          expect(saved.slides[1].notes, 'Neighbor notes');
        }
      },
    );
  }

  test(
    'notes edited after an async save advance the upload revision',
    () async {
      final controller = _controller();
      controller.setSpeakerNotes('Uploaded notes');
      final uploadingRevision = controller.contentRevision;
      final bytes = await controller.saveBytesAsync();
      controller.setSpeakerNotes('Newer unsaved notes');
      expect(controller.contentRevision, greaterThan(uploadingRevision));
      expect(controller.isDirty, isTrue);
      expect(
        SlideDeserializer().read(OpcPackage.openBytes(bytes)).slides[0].notes,
        'Uploaded notes',
      );
      expect(controller.speakerNotes, 'Newer unsaved notes');
    },
  );
}
