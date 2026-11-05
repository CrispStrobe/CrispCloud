// test/file_editability_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/utils/file_editability.dart';

void main() {
  test('text, raster images, PDF and OOXML files are editable', () {
    expect(isEditableInBuiltInEditor('notes.txt'), isTrue);
    expect(isEditableInBuiltInEditor('work.CCIMAGE'), isTrue);
    expect(isEditableInBuiltInEditor('work.ccimage.zip'), isFalse);
    expect(isEditableInBuiltInEditor('README'), isTrue);
    expect(isEditableInBuiltInEditor('main.dart'), isTrue);
    expect(isEditableInBuiltInEditor('photo.jpg'), isTrue);
    expect(isEditableInBuiltInEditor('photo.JPEG'), isTrue);
    expect(isEditableInBuiltInEditor('drawing.PNG'), isTrue);
    expect(isEditableInBuiltInEditor('photo.webp'), isTrue);
    expect(isEditableInBuiltInEditor('image.gif'), isTrue);
    expect(isEditableInBuiltInEditor('image.bmp'), isTrue);
    expect(isEditableInBuiltInEditor('image.tif'), isTrue);
    expect(isEditableInBuiltInEditor('image.TIFF'), isTrue);
    expect(isEditableInBuiltInEditor('report.pdf'), isTrue);
    expect(isEditableInBuiltInEditor('letter.docx'), isTrue);
    expect(isEditableInBuiltInEditor('book.xlsx'), isTrue);
    expect(isEditableInBuiltInEditor('slides.pptx'), isTrue);
  });

  test('view-only and binary formats are not offered as editable', () {
    for (final name in <String>[
      'photo.heic',
      'diagram.svg',
      'movie.avi',
      'archive.zip',
      'legacy.doc',
      'legacy.xls',
      'legacy.ppt',
      'font.ttf',
    ]) {
      expect(isEditableInBuiltInEditor(name), isFalse, reason: name);
    }
  });

  test('image names must end in a supported image extension', () {
    expect(isEditableInBuiltInEditor('photo.jpg.zip'), isFalse);
    expect(isEditableInBuiltInEditor('drawing.png.exe'), isFalse);
    expect(isEditableInBuiltInEditor('photo.jpg.'), isFalse);
    expect(isEditableInBuiltInEditor('drawing.png.'), isFalse);
  });

  test('extensionless and known hidden text files remain editable', () {
    expect(isTextEditableName('README'), isTrue);
    expect(isTextEditableName('Makefile'), isTrue);
    expect(isTextEditableName('.env'), isTrue);
    expect(isTextEditableName('.gitignore'), isTrue);
    expect(isTextEditableName('photo.jpg.'), isFalse);
  });
}
