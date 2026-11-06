import 'dart:convert';
import 'package:crisp_cloud/models/gallery.dart';
import 'package:crisp_cloud/services/gallery_catalog_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('annotations persist and remain isolated by source/account asset ID', () async {
    final service = GalleryCatalogService();
    addTearDown(service.dispose);
    await service.update(['account-a:photo'], rating: 4, color: GalleryColor.green,
      tags: ['Alps'], favorite: true);
    final restored = GalleryCatalogService();
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.get('account-a:photo').rating, 4);
    expect(restored.get('account-a:photo').color, GalleryColor.green);
    expect(restored.get('account-a:photo').favorite, isTrue);
    expect(restored.get('account-b:photo').isEmpty, isTrue);
  });

  test('concurrent batches merge updates and can add or replace tags', () async {
    final service = GalleryCatalogService();
    addTearDown(service.dispose);
    await Future.wait([
      service.update(['a', 'b'], rating: 3),
      service.update(['a'], tags: ['Beach']),
      service.update(['a'], favorite: true),
      service.update(['a'], tags: ['beach', 'Summer']),
    ]);
    expect(service.get('a').rating, 3);
    expect(service.get('a').favorite, isTrue);
    expect(service.get('a').tags, ['Beach', 'Summer']);
    expect(service.get('b').rating, 3);
    expect(service.get('b').tags, isEmpty);
    await service.update(['a'], tags: [], replaceTags: true);
    expect(service.get('a').tags, isEmpty);
    expect(service.get('a').rating, 3);
  });

  test('an update issued during initialization retains stored annotations', () async {
    SharedPreferences.setMockInitialValues({GalleryCatalogService.preferencesKey:
      jsonEncode({'old': const GalleryRecord(rating: 5).toJson()})});
    final service = GalleryCatalogService();
    addTearDown(service.dispose);
    final loading = service.load();
    await service.update(['new'], rating: 2);
    await loading;
    expect(service.get('old').rating, 5);
    expect(service.get('new').rating, 2);
  });

  test('a corrupt catalog is not silently overwritten by a new edit', () async {
    SharedPreferences.setMockInitialValues({GalleryCatalogService.preferencesKey: '{broken'});
    final service = GalleryCatalogService();
    addTearDown(service.dispose);
    await expectLater(service.update(['a'], rating: 1), throwsFormatException);
    expect((await SharedPreferences.getInstance()).getString(GalleryCatalogService.preferencesKey), '{broken');
  });

  test('export is scoped to the supplied assets and includes JSON-safe names', () async {
    final service = GalleryCatalogService();
    addTearDown(service.dispose);
    await service.update(['a', 'b'], rating: 5);
    final result = jsonDecode(service.exportJson({'a': 'a"photo.jpg'}));
    expect(result['items'], hasLength(1));
    expect(result['items'][0]['name'], 'a"photo.jpg');
    expect(result['items'][0]['rating'], 5);
  });
}
