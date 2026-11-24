import 'package:crisp_cloud/providers/panel_cache_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('desktop cache budget defaults to rows, not folder count', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await pumpEventQueue();
    expect(container.read(panelCacheSettingsProvider).maxItems, 20000);
  });

  test('legacy folder setting migrates to a row budget', () async {
    SharedPreferences.setMockInitialValues({'panel.cache.maxFolders.v1': 200});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await pumpEventQueue();
    expect(container.read(panelCacheSettingsProvider).maxItems, 20000);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('panel.cache.maxItems.v1'), 20000);
  });

  test('new row budget clamps oversized input', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await pumpEventQueue();
    await container
        .read(panelCacheSettingsProvider.notifier)
        .setMaxItems(500000);
    expect(container.read(panelCacheSettingsProvider).maxItems, 100000);
  });
}
