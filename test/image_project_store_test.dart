import 'dart:typed_data';

import 'package:crisp_cloud/services/image_edit_project.dart';
import 'package:crisp_cloud/services/image_edit_session.dart';
import 'package:crisp_cloud/services/image_project_store.dart';
import 'package:crisp_cloud/services/pdf_file_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/image_editor_fixture.dart';

class MemoryProjectStore implements PdfFileStore {
  MemoryProjectStore(this.bytes);
  Uint8List bytes;
  @override
  String get documentId => 'test';
  @override
  String get displayName => 'test.ccimage';
  @override
  String get path => '/test.ccimage';
  @override
  bool get isRemote => false;
  @override
  Future<Uint8List> load() async => bytes;
  @override
  Future<PdfSaveOutcome> save(Uint8List value) async {
    bytes = value;
    return PdfSaveOutcome.savedOriginal;
  }

  @override
  Future<PdfSaveOutcome> saveCopy(Uint8List value, String fileName) =>
      throw UnimplementedError();
}

void main() {
  test('save requires a successfully loaded project', () async {
    final project = ImageEditProject(
      sourceName: 'a.png',
      sourceBytes: buildImageEditorFixture(),
      history: {},
    );
    final backing = MemoryProjectStore(project.encode());
    final store = ImageProjectStore(backing);
    await expectLater(store.save(project), throwsStateError);
    expect((await store.load()).sourceName, 'a.png');
    final changed = ImageEditProject(
      sourceName: 'a.png',
      sourceBytes: project.sourceBytes,
      history: {'history': []},
    );
    expect(await store.save(changed), ImageSaveOutcome.savedOriginal);
    expect(ImageEditProject.decode(backing.bytes).history, {'history': []});
  });
  test('recognizes only project extension', () {
    expect(isImageEditProjectName('Artwork.CCIMAGE'), isTrue);
    expect(isImageEditProjectName('art.ccimage.png'), isFalse);
  });
}
