import 'image_edit_project.dart';
import 'image_edit_session.dart';
import 'pdf_edit_session.dart';
import 'pdf_file_store.dart';

/// Project storage uses the same captured-origin and conflict checks as other
/// host editors, while serializing an editable project instead of a raster.
class ImageProjectStore {
  ImageProjectStore(this._store);
  final PdfFileStore _store;
  bool _loaded = false;

  Future<ImageEditProject> load() async {
    _loaded = false;
    final bytes = await _store.load();
    final project = ImageEditProject.decode(bytes);
    _loaded = true;
    return project;
  }

  Future<ImageSaveOutcome> save(ImageEditProject project) async {
    if (!_loaded) throw StateError('Load the image project before saving.');
    return switch (await _store.save(project.encode())) {
      PdfSaveOutcome.savedOriginal => ImageSaveOutcome.savedOriginal,
      PdfSaveOutcome.savedCopy => ImageSaveOutcome.savedCopy,
      PdfSaveOutcome.downloadedCopy => ImageSaveOutcome.downloadedCopy,
    };
  }
}

bool isImageEditProjectName(String name) =>
    name.toLowerCase().endsWith('.ccimage');
