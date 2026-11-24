import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/directory_cache_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('listing cache evicts least-recently-used folders at its bound', () {
    final cache = DirectoryCacheService(maxEntries: 2);
    FileItem item(String name) => FileItem(name: name, isFolder: false);
    cache.put('a', [item('a')]);
    cache.put('b', [item('b')]);
    expect(cache.get('a'), isNotNull);
    cache.put('c', [item('c')]);
    expect(cache.get('a'), isNotNull);
    expect(cache.get('b'), isNull);
    expect(cache.get('c'), isNotNull);
  });

  test('zero disables the listing cache', () {
    final cache = DirectoryCacheService(maxEntries: 0);
    cache.put('a', [FileItem(name: 'a', isFolder: false)]);
    expect(cache.get('a'), isNull);
  });
}
