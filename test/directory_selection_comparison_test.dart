import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/directory_selection_comparison.dart';

void main() {
  FileItem file(String name, {int? size, int? day, bool folder = false}) =>
      FileItem(
        name: name,
        isFolder: folder,
        size: size,
        updatedAt: day == null ? null : DateTime.utc(2026, 11, day),
      );
  test('selects new and newer files and differing sizes at equal dates', () {
    final active = [
      file('new'),
      file('newer', day: 12),
      file('older', day: 10),
      file('size', size: 2, day: 11),
      file('equal', size: 3, day: 11),
    ];
    final other = [
      file('newer', day: 11),
      file('older', day: 11),
      file('size', size: 1, day: 11),
      file('equal', size: 3, day: 11),
    ];
    expect(compareDirectorySelection(active, other), [
      active[0],
      active[1],
      active[3],
    ]);
  });
  test('ignores folders, parent entries and unknown metadata equality', () {
    expect(
      compareDirectorySelection(
        [
          file('..'),
          file('dir', folder: true),
          file('unknown'),
          file('conflict'),
        ],
        [file('unknown'), file('conflict', folder: true)],
      ),
      isEmpty,
    );
  });
}
