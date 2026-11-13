import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/archive_creation_batch.dart';
import 'package:crisp_cloud/services/archive_creation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  FileItem file(String name, {bool folder = false}) => FileItem(
    name: name,
    path: '/input/$name',
    isFolder: folder,
    size: folder ? null : 1,
  );
  test('separate outputs keep original extensions and support folders', () {
    final source = [
      file('report.txt'),
      file('report.csv'),
      file('docs', folder: true),
    ];
    final plan = planArchiveCreationBatch(
      files: source,
      destinationDirectory: '/output',
      options: const ArchiveCreationOptions(
        name: 'unused.tar.gz',
        format: ArchiveCreationFormat.tarGzip,
      ),
    );
    source.clear();
    expect(plan.map((item) => item.options.name), [
      'report.txt.tar.gz',
      'report.csv.tar.gz',
      'docs.tar.gz',
    ]);
    expect(plan.every((item) => item.files.length == 1), isTrue);
    expect(() => plan.clear(), throwsUnsupportedError);
    expect(() => plan.first.files.clear(), throwsUnsupportedError);
  });
  test('single-payload compressors accept separate files and reject folder selections', () {
    const options = ArchiveCreationOptions(
      name: 'unused.gz',
      format: ArchiveCreationFormat.gzip,
    );
    final plan = planArchiveCreationBatch(
      files: [file('report.txt'), file('image.png')],
      destinationDirectory: '/output',
      options: options,
    );
    expect(plan.map((item) => item.options.name), [
      'report.txt.gz',
      'image.png.gz',
    ]);
    expect(
      () => planArchiveCreationBatch(
        files: [file('report.txt'), file('folder', folder: true)],
        destinationDirectory: '/output',
        options: options,
      ),
      throwsA(isA<ArchiveCreationException>()),
    );
  });
  test(
    'password and header protection remain effective for every planned 7z',
    () {
      final plan = planArchiveCreationBatch(
        files: [file('first'), file('second')],
        destinationDirectory: '/output',
        options: const ArchiveCreationOptions(
          name: 'unused.7z',
          format: ArchiveCreationFormat.sevenZip,
          compression: ArchiveCreationCompression.lzma2,
          password: 'in-memory',
          encryptNames: true,
        ),
      );
      expect(
        plan.every(
          (item) =>
              item.options.password == 'in-memory' && item.options.encryptNames,
        ),
        isTrue,
      );
      expect(
        plan.every(
          (item) =>
              item.options.compression == ArchiveCreationCompression.lzma2,
        ),
        isTrue,
      );
    },
  );
}
