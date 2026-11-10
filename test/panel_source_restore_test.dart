import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/panel_source_provider.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final side in PanelSide.values) {
    testWidgets('restores the saved ${side.name} source without a newer choice', (
      tester,
    ) async {
      final key = 'panel_source_${side.name}';
      SharedPreferences.setMockInitialValues({
        key: 'local',
        '${key}_path': '/saved/${side.name}',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(panelSourceProvider(side)).currentPath, '/');

      await tester.pump();

      final restored = container.read(panelSourceProvider(side));
      expect(restored, isA<LocalPanelSource>());
      expect(restored.currentPath, '/saved/${side.name}');
    });
  }

  final choices = <String, void Function(PanelSourceNotifier)>{
    'source selection': (notifier) =>
        notifier.setSource(const LocalPanelSource('/chosen')),
    'same-source selection': (notifier) =>
        notifier.setSource(const LocalPanelSource('/')),
    'path navigation': (notifier) => notifier.navigateTo('/chosen'),
    'archive entry': (notifier) => notifier.enterArchive('/chosen.zip'),
    'container entry': (notifier) =>
        notifier.enterContainer('/chosen.vc', 'test-password'),
    'parent navigation': (notifier) => notifier.exitToParent(),
  };
  for (final choice in choices.entries) {
    testWidgets('${choice.key} wins over a pending startup restore', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'panel_source_remote': 'local',
        'panel_source_remote_path': '/saved',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(
        panelSourceProvider(PanelSide.remote).notifier,
      );
      choice.value(notifier);
      final chosen = container.read(panelSourceProvider(PanelSide.remote));

      await tester.pump();

      expect(container.read(panelSourceProvider(PanelSide.remote)), same(chosen));
      if (chosen.isLocal) {
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('panel_source_remote_path'), chosen.currentPath);
      }
    });
  }

  testWidgets('a pending local marker cannot reset newer navigation to root', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'panel_source_remote': 'local'});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(
      panelSourceProvider(PanelSide.remote).notifier,
    );
    notifier.setSource(const LocalPanelSource('/local'));
    notifier.navigateTo('/two');

    await tester.pump();

    expect(container.read(panelSourceProvider(PanelSide.remote)).currentPath, '/two');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('panel_source_remote_path'), '/two');
  });

  testWidgets('disposing before preferences resolve does not publish a source', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'panel_source_local': 'local',
      'panel_source_local_path': '/saved',
    });
    final container = ProviderContainer();
    container.read(panelSourceProvider(PanelSide.local));
    container.dispose();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
