// test/file_editability_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/utils/file_editability.dart';

void main() {
  test('text, PDF and OOXML files are editable', () {
    expect(isEditableInBuiltInEditor('notes.txt'), isTrue);
    expect(isEditableInBuiltInEditor('README'), isTrue);
    expect(isEditableInBuiltInEditor('main.dart'), isTrue);
    expect(isEditableInBuiltInEditor('report.pdf'), isTrue);
    expect(isEditableInBuiltInEditor('letter.docx'), isTrue);
    expect(isEditableInBuiltInEditor('book.xlsx'), isTrue);
    expect(isEditableInBuiltInEditor('slides.pptx'), isTrue);
  });

  test('view-only and binary formats are not offered as editable', () {
    for (final name in <String>[
      'photo.jpg',
      'movie.mp4',
      'archive.zip',
      'legacy.doc',
      'legacy.xls',
      'legacy.ppt',
      'font.ttf',
    ]) {
      expect(isEditableInBuiltInEditor(name), isFalse, reason: name);
    }
  });
}
