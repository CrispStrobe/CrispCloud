import 'package:crisp_cloud/services/duplicate_name_template.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final sample in [
    ('photo.jpg', 'photo (1).jpg'),
    ('archive.tar.gz', 'archive.tar (1).gz'),
    ('.gitignore', '.gitignore (1)'),
    ('README', 'README (1)'),
    ('name with spaces.pdf', 'name with spaces (1).pdf'),
  ]) {
    test('default template preserves the filename parts of ${sample.$1}', () {
      expect(
        DuplicateNameTemplate(DuplicateNameTemplate.defaultTemplate)
            .apply(sample.$1, index: 1),
        sample.$2,
      );
    });
  }

  test('custom template pads counters without truncating larger values', () {
    final template = DuplicateNameTemplate('{name}_copy-{counter:000}{ext}');
    expect(template.apply('report.pdf', index: 7), 'report_copy-007.pdf');
    expect(template.apply('report.pdf', index: 1234), 'report_copy-1234.pdf');
  });

  test('literal braces can be escaped without being interpreted as tokens', () {
    final template = DuplicateNameTemplate('{{{name}}}-{counter}{ext}');
    expect(template.apply('report.pdf', index: 2), '{report}-2.pdf');
  });

  test('invalid templates are rejected before allocation', () {
    for (final value in [
      '',
      '{name}{ext}',
      '{name}-{unknown}-{counter}',
      '{name}-{counter:3}',
      '{name}-{counter:0000000000000}',
      '{name}-{counter',
      '{name}-{counter}}',
      '../{name}-{counter}',
      'folder\\{counter}',
      '{name}\u0000{counter}',
      '{name}\n{counter}',
    ]) {
      expect(
        () => DuplicateNameTemplate(value),
        throwsFormatException,
        reason: value,
      );
    }
  });
}
