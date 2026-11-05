// Real local files and the Flutter engine decoder, without mocked storage or
// credential requirements. These tests run in normal CI, like viewer_live_test.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/image_edit_session.dart';
import 'package:crisp_cloud/services/image_edit_project.dart';
import 'package:crisp_cloud/services/image_project_store.dart';
import 'package:crisp_cloud/services/pdf_file_store.dart';
import 'package:crisp_cloud/services/image_file_store.dart';
import 'package:crisp_cloud/services/local_file_service_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

import 'support/image_editor_fixture.dart';

Future<(int, int)> _engineDimensions(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    expect(codec.frameCount, 1);
    final frame = await codec.getNextFrame();
    try {
      return (frame.image.width, frame.image.height);
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('crisp_image_editor_');
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  for (final format in ImageFileFormat.values) {
    test('real $format save reopens in the independent Flutter decoder', () async {
      final extension = format == ImageFileFormat.png ? 'png' : 'jpg';
      final original = File('${directory.path}/picture.$extension');
      await original.writeAsBytes(buildImageEditorFixture(format: format));
      final store = ImageFileStore.local(
        service: DesktopFileService(),
        file: FileItem(
          name: 'picture.$extension',
          path: original.path,
          isFolder: false,
        ),
      );
      final source = await store.load();
      expect(await _engineDimensions(source), (24, 16));
      final session = ImageEditSession(initialBytes: source, format: format);
      addTearDown(session.dispose);
      // Exercise an actual pixel operation; the widget suite covers the editor
      // command/capture path while this test verifies durable bytes on disk.
      final rotated = image.copyRotate(image.decodeImage(source)!, angle: 90);
      final exported = format == ImageFileFormat.png
          ? image.encodePng(rotated)
          : image.encodeJpg(rotated, quality: 95);
      session.updateRevision(1);
      expect(
        await session.save(export: () async => exported, write: store.save),
        ImageSaveOutcome.savedOriginal,
      );
      expect(session.isDirty, isFalse);
      final reopened = await original.readAsBytes();
      expect(reopened, exported);
      expect(await _engineDimensions(reopened), (16, 24));
      expect(
        inspectEditableImage(reopened, fileName: original.path).format,
        format,
      );
      expect(
        await directory.list().length,
        1,
        reason: 'No abandoned staging file',
      );
    });
  }

  test(
    'real project saves preserve history and reject outside changes',
    () async {
      final file = File('${directory.path}/picture.ccimage');
      final project = ImageEditProject(
        sourceName: 'picture.png',
        sourceBytes: buildImageEditorFixture(),
        history: {'history': []},
      );
      await file.writeAsBytes(project.encode());
      final store = ImageProjectStore(
        PdfFileStore.local(
          service: DesktopFileService(),
          file: FileItem(
            name: 'picture.ccimage',
            path: file.path,
            isFolder: false,
          ),
          inputLimitBytes: ImageEditProject.maxBytes,
          outputLimitBytes: ImageEditProject.maxBytes,
        ),
      );
      final opened = await store.load();
      final updated = ImageEditProject(
        sourceName: opened.sourceName,
        sourceBytes: opened.sourceBytes,
        history: {
          'history': [
            {'layers': []},
          ],
        },
      );
      expect(await store.save(updated), ImageSaveOutcome.savedOriginal);
      expect(
        ImageEditProject.decode(await file.readAsBytes()).history,
        updated.history,
      );
      final external = project.encode();
      await file.writeAsBytes(external);
      await expectLater(
        store.save(updated),
        throwsA(isA<PdfSaveConflictException>()),
      );
      expect(await file.readAsBytes(), orderedEquals(external));
    },
  );

  test(
    'real WebP save and conflict check preserve the source contract',
    () async {
      final original = File('${directory.path}/picture.webp');
      final pixels = image.decodePng(buildImageEditorFixture())!;
      await original.writeAsBytes(image.encodeWebP(pixels));
      final store = ImageFileStore.local(
        service: DesktopFileService(),
        file: FileItem(
          name: 'picture.webp',
          path: original.path,
          isFolder: false,
        ),
      );
      final source = await store.load();
      final session = ImageEditSession(
        initialBytes: source,
        format: ImageFileFormat.png,
      );
      addTearDown(session.dispose);
      final rotated = image.encodePng(
        image.copyRotate(image.decodePng(source)!, angle: 90),
      );
      session.updateRevision(1);
      expect(
        await session.save(export: () async => rotated, write: store.save),
        ImageSaveOutcome.savedOriginal,
      );
      expect(await _engineDimensions(await original.readAsBytes()), (16, 24));
      final external = image.encodeWebP(
        image.decodePng(buildImageEditorFixture(seed: 9))!,
      );
      await original.writeAsBytes(external);
      session.updateRevision(2);
      await expectLater(
        session.save(export: () async => rotated, write: store.save),
        throwsA(isA<ImageSaveConflictException>()),
      );
      expect(await original.readAsBytes(), orderedEquals(external));
      expect(session.isDirty, isTrue);
    },
  );

  test(
    'an external file change blocks overwrite and keeps edits recoverable',
    () async {
      final original = File('${directory.path}/picture.png');
      final initial = buildImageEditorFixture();
      await original.writeAsBytes(initial);
      final store = ImageFileStore.local(
        service: DesktopFileService(),
        file: FileItem(
          name: 'picture.png',
          path: original.path,
          isFolder: false,
        ),
      );
      final session = ImageEditSession(
        initialBytes: await store.load(),
        format: ImageFileFormat.png,
      )..updateRevision(1);
      addTearDown(session.dispose);
      final external = buildImageEditorFixture(seed: 2);
      await original.writeAsBytes(external);
      await expectLater(
        session.save(
          export: () async => buildImageEditorFixture(seed: 1),
          write: store.save,
        ),
        throwsA(isA<ImageSaveConflictException>()),
      );
      expect(await original.readAsBytes(), external);
      expect(session.isDirty, isTrue);
      expect(session.savedBytes, initial);
      expect(session.isSaving, isFalse);
    },
  );

  test(
    'wrong-format export leaves the real source byte-for-byte unchanged',
    () async {
      final original = File('${directory.path}/picture.jpg');
      final initial = buildImageEditorFixture(format: ImageFileFormat.jpeg);
      await original.writeAsBytes(initial);
      final store = ImageFileStore.local(
        service: DesktopFileService(),
        file: FileItem(
          name: 'picture.jpg',
          path: original.path,
          isFolder: false,
        ),
      );
      final session = ImageEditSession(
        initialBytes: await store.load(),
        format: ImageFileFormat.jpeg,
      )..updateRevision(1);
      addTearDown(session.dispose);
      await expectLater(
        session.save(
          export: () async => buildImageEditorFixture(),
          write: store.save,
        ),
        throwsA(
          isA<ImageEditException>().having(
            (error) => error.reason,
            'reason',
            ImageEditFailure.formatMismatch,
          ),
        ),
      );
      expect(await original.readAsBytes(), initial);
      expect(session.isDirty, isTrue);
      expect(await _engineDimensions(await original.readAsBytes()), (24, 16));
    },
  );
}
