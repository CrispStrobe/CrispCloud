import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/gallery.dart';
import 'package:flutter_test/flutter_test.dart';

FileItem photo(String name, {DateTime? date, int? size, bool folder = false}) =>
    FileItem(name: name, path: '/$name', isFolder: folder, updatedAt: date, size: size);

void main() {
  test('natural filename order handles huge numbers and leading zeroes', () {
    final names = ['img10.jpg', 'img0002.jpg', 'img2.jpg', 'img1.jpg',
      'img99999999999999999999999999999.jpg', 'img100000000000000000000000000000.jpg'];
    names.sort(compareGalleryNames);
    expect(names, ['img1.jpg', 'img2.jpg', 'img0002.jpg', 'img10.jpg',
      'img99999999999999999999999999999.jpg', 'img100000000000000000000000000000.jpg']);
  });

  test('gallery retains folders and recognized unsupported image formats', () {
    final files = [photo('readme.txt'), photo('camera.NEF'), photo('folder.jpg', folder: true),
      photo('photo.png'), photo('..', folder: true)];
    final result = const GalleryQuery().apply(files, (_) => const GalleryRecord(), imagesOnly: true);
    expect(result.map((f) => f.name), ['..', 'folder.jpg', 'camera.NEF', 'photo.png']);
    expect(isGalleryImage(files[2]), isFalse);
  });

  test('metadata filters combine without losing folder navigation', () {
    final a = photo('alpine.jpg');
    final b = photo('beach.jpg');
    final directory = photo('trips', folder: true);
    final records = {
      a: const GalleryRecord(rating: 4, color: GalleryColor.blue, favorite: true, tags: ['Alps', 'Holiday']),
      b: const GalleryRecord(rating: 5, color: GalleryColor.blue, favorite: true, tags: ['Beach']),
    };
    final result = const GalleryQuery(text: 'ALPS holiday', extension: 'jpg',
      minimumRating: 4, color: GalleryColor.blue, favoritesOnly: true)
      .apply([a, b, directory], (file) => records[file] ?? const GalleryRecord());
    expect(result, [directory, a]);
  });

  test('date filtering includes the entire final day and excludes unknown dates', () {
    final first = photo('a.jpg', date: DateTime(2026, 3, 1));
    final last = photo('b.jpg', date: DateTime(2026, 3, 3, 23, 59, 59));
    final next = photo('c.jpg', date: DateTime(2026, 3, 4));
    final result = GalleryQuery(after: DateTime(2026, 3, 1), before: DateTime(2026, 3, 3))
      .apply([next, photo('unknown.jpg'), last, first], (_) => const GalleryRecord());
    expect(result, [first, last]);
  });

  test('descending sort keeps parent and folders first without mutating listing', () {
    final items = [photo('small.jpg', size: 10), photo('large.jpg', size: 100),
      photo('folder', folder: true), photo('..', folder: true)];
    final result = const GalleryQuery(sort: GallerySort.size, descending: true)
      .apply(items, (_) => const GalleryRecord());
    expect(result.map((file) => file.name), ['..', 'folder', 'large.jpg', 'small.jpg']);
    expect(items.first.name, 'small.jpg');
  });

  test('corrupt preferences and annotations are safely normalized', () {
    expect(GalleryPreferences.decode('no json').thumbnailSize, 200);
    expect(GalleryPreferences.decode('{"size":99999}').thumbnailSize, 360);
    expect(GalleryPreferences.decode('{"size":20}').thumbnailSize, 120);
    final record = GalleryRecord.fromJson({'rating': 100, 'color': 'invalid',
      'tags': ['  Travel ', 'travel', '', 'Family', 3]});
    expect(record.rating, 5);
    expect(record.color, GalleryColor.none);
    expect(record.tags, ['Travel', 'Family']);
    expect(() => record.tags.add('cannot mutate'), throwsUnsupportedError);
  });
}
