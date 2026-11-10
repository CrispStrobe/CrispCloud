import 'dart:convert';

import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/providers/recent_locations_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _accountA = StorageReference(
  kind: 'remote',
  provider: 'Cloud',
  accountKey: 'a',
);
const _accountB = StorageReference(
  kind: 'remote',
  provider: 'Cloud',
  accountKey: 'b',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('recents distinguish account namespaces and move only the matching location', () async {
    final notifier = RecentLocationsNotifier();
    addTearDown(notifier.dispose);
    await notifier.ready;
    notifier.add('/shared', PanelSide.remote, storage: _accountA);
    notifier.add('/shared', PanelSide.remote, storage: _accountB);
    notifier.add('/shared', PanelSide.remote, storage: _accountA);
    expect(notifier.entries, hasLength(2));
    expect(notifier.entries.map((entry) => entry.storage), [
      _accountA,
      _accountB,
    ]);
    final restored = RecentEntry.fromJson(notifier.entries.first.toJson());
    expect(restored.storage, _accountA);
    expect(restored.path, '/shared');
  });

  test('startup navigation is merged ahead of loaded preferences', () async {
    SharedPreferences.setMockInitialValues({
      'recent_locations': jsonEncode([
        RecentEntry(
          path: '/saved',
          side: PanelSide.remote,
          visitedAt: DateTime.utc(2026),
          storage: _accountA,
        ).toJson(),
      ]),
    });
    final notifier = RecentLocationsNotifier();
    addTearDown(notifier.dispose);
    notifier.add('/just-opened', PanelSide.remote, storage: _accountB);
    await notifier.ready;
    expect(notifier.entries.map((entry) => entry.path), [
      '/just-opened',
      '/saved',
    ]);
  });

  test(
    'clearing during startup cannot resurrect loaded destinations',
    () async {
      SharedPreferences.setMockInitialValues({
        'recent_locations': jsonEncode([
          RecentEntry(
            path: '/saved',
            side: PanelSide.remote,
            visitedAt: DateTime.utc(2026),
            storage: _accountA,
          ).toJson(),
        ]),
      });
      final notifier = RecentLocationsNotifier();
      addTearDown(notifier.dispose);
      notifier.clear();
      await notifier.ready;
      expect(notifier.entries, isEmpty);
    },
  );

  test('legacy entries remain unscoped and corrupt neighbors do not hide valid entries', () async {
    SharedPreferences.setMockInitialValues({
      'recent_locations': jsonEncode([
        {'path': '/legacy', 'side': 'remote'},
        {'path': null},
        RecentEntry(
          path: '/saved',
          side: PanelSide.remote,
          visitedAt: DateTime.utc(2026),
          storage: _accountA,
        ).toJson(),
      ]),
    });
    final notifier = RecentLocationsNotifier();
    addTearDown(notifier.dispose);
    await notifier.ready;
    expect(notifier.entries, hasLength(2));
    expect(notifier.entries.first.storage, isNull);
    expect(notifier.entries.last.storage, _accountA);
  });

  test(
    'recent destinations remain bounded across accounts and panes',
    () async {
      final notifier = RecentLocationsNotifier();
      addTearDown(notifier.dispose);
      await notifier.ready;
      for (var i = 0; i < 30; i++) {
        notifier.add('/folder-$i', PanelSide.remote, storage: _accountA);
      }
      expect(notifier.entries, hasLength(RecentLocationsNotifier.maxRecent));
      expect(notifier.entries.first.path, '/folder-29');
    },
  );
}
