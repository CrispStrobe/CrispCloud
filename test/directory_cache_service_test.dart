import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/directory_cache_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  FileItem item(String name) => FileItem(name: name, isFolder: false);
  List<FileItem> listing(String prefix, int count) => [
    for (var i = 0; i < count; i++) item('$prefix$i'),
  ];

  test('listing cache evicts least-recently-used rows at its item bound', () {
    final cache = DirectoryCacheService(maxItems: 3);
    cache.put('a', listing('a', 2));
    cache.put('b', listing('b', 1));
    expect(cache.cachedItems, 3);
    expect(cache.get('a'), isNotNull);
    cache.put('c', listing('c', 1));
    expect(cache.cachedItems, 3);
    expect(cache.get('a'), isNotNull);
    expect(cache.get('b'), isNull);
    expect(cache.get('c'), isNotNull);
  });

  test('a single oversized listing is never cached', () {
    final cache = DirectoryCacheService(maxItems: 2);
    cache.put('small', listing('s', 1));
    cache.put('huge', listing('h', 3));
    expect(cache.get('huge'), isNull);
    expect(cache.get('small'), isNotNull);
    expect(cache.cachedItems, 1);
  });

  test('replacements and invalidation adjust the item count', () {
    final cache = DirectoryCacheService(maxItems: 10);
    cache.put('a', listing('a', 4));
    cache.put('a', listing('a', 2));
    expect(cache.cachedItems, 2);
    cache.invalidate('a');
    expect(cache.cachedItems, 0);
  });

  test('zero disables the listing cache', () {
    final cache = DirectoryCacheService(maxItems: 0);
    cache.put('a', [item('a')]);
    expect(cache.get('a'), isNull);
    expect(cache.cachedItems, 0);
  });
}
