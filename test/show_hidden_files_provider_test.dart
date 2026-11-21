import 'package:crisp_cloud/providers/show_hidden_files_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('hidden files are off by default and the choice is kept', () async {
    SharedPreferences.setMockInitialValues({});
    final first = ProviderContainer();
    expect(first.read(showHiddenFilesProvider), isFalse);
    await first.read(showHiddenFilesProvider.notifier).toggle();
    expect(first.read(showHiddenFilesProvider), isTrue);
    first.dispose();

    final later = ProviderContainer();
    later.read(showHiddenFilesProvider);
    await Future<void>.delayed(Duration.zero);
    expect(later.read(showHiddenFilesProvider), isTrue);
    later.dispose();
  });

  test('a change made while loading is not overwritten', () async {
    SharedPreferences.setMockInitialValues({
      ShowHiddenFilesNotifier.preferenceKey: true,
    });
    final container = ProviderContainer();
    await container.read(showHiddenFilesProvider.notifier).set(false);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(showHiddenFilesProvider), isFalse);
    container.dispose();
  });
}
