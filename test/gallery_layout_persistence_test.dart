import 'dart:async';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/core_providers.dart';
import 'package:crisp_cloud/providers/toolbar_provider.dart';
import 'package:crisp_cloud/services/panel_view_mode_service.dart';
import 'package:crisp_cloud/widgets/file_view_selector.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _DelayedModes extends PanelViewModeService {
  final restored = Completer<PanelViewMode>();
  PanelViewMode? saved;
  @override
  Future<PanelViewMode> getMode(PanelSide side) => restored.future;
  @override
  Future<void> setMode(PanelSide side, PanelViewMode mode) async { saved = mode; }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final layout in ViewMode.values) {
    testWidgets('explicit ${layout.name} choice supersedes a pending tree layout', (tester) async {
      final service = _DelayedModes();
      final container = ProviderContainer(overrides: [
        panelViewModeServiceProvider.overrideWithValue(service),
      ]);
      addTearDown(container.dispose);
      late WidgetRef ref;
      await tester.pumpWidget(UncontrolledProviderScope(container: container,
        child: Consumer(builder: (_, value, __) {
          ref = value;
          return const SizedBox();
        })));
      container.read(panelViewModeProvider(PanelSide.local));
      setFileView(ref, PanelSide.local, layout);
      service.restored.complete(PanelViewMode.tree);
      await tester.pump();
      expect(container.read(localViewModeProvider), layout);
      expect(container.read(panelViewModeProvider(PanelSide.local)), PanelViewMode.full);
      expect(service.saved, PanelViewMode.full);
      await tester.pumpWidget(const SizedBox());
    });
  }

  test('choosing a visual layout wins over pending saved tree restoration', () async {
    final service = _DelayedModes();
    final mode = PanelViewModeNotifier(service, PanelSide.local);
    addTearDown(mode.dispose);
    await mode.setMode(PanelViewMode.full);
    service.restored.complete(PanelViewMode.tree);
    await Future<void>.delayed(Duration.zero);
    expect(mode.state, PanelViewMode.full);
    expect(service.saved, PanelViewMode.full);
  });

  test('early layout choice is persisted without old preference overwriting it', () async {
    SharedPreferences.setMockInitialValues({'file_layout_local_v1': 'column'});
    final controller = FileViewModeController(PanelSide.local);
    addTearDown(controller.dispose);
    controller.state = ViewMode.gallery;
    await Future<void>.delayed(Duration.zero);
    expect(controller.state, ViewMode.gallery);
    expect((await SharedPreferences.getInstance()).getString('file_layout_local_v1'), 'gallery');
  });

  test('density service loading cannot replace an in-flight user choice', () async {
    SharedPreferences.setMockInitialValues({'panel_view_mode_local_v1': 'tree'});
    final service = PanelViewModeService();
    final loading = service.getMode(PanelSide.local);
    await service.setMode(PanelSide.local, PanelViewMode.full);
    expect(await loading, PanelViewMode.full);
    expect(await service.getMode(PanelSide.local), PanelViewMode.full);
  });
}
