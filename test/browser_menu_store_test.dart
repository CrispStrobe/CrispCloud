import 'dart:async';

import 'package:crisp_cloud/models/browser_menu_layout.dart';
import 'package:crisp_cloud/services/browser_menu_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/browser_menu_storage.dart';

BrowserMenuLayout named(String id) => BrowserMenuLayout([
  BrowserMenuNode(
    id: id,
    kind: BrowserMenuNodeKind.submenu,
    label: 'Custom',
    children: [
      BrowserMenuNode(
        id: '$id-copy',
        kind: BrowserMenuNodeKind.command,
        commandId: 'action:copy',
      ),
    ],
  ),
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('saved identity survives a preferences-backed store restart', () async {
    final store = BrowserMenuStore();
    await store.ready;
    await store.save(named('persisted'));
    store.dispose();
    final restored = BrowserMenuStore();
    addTearDown(restored.dispose);
    await restored.ready;
    expect(restored.layout.toJson(), named('persisted').toJson());
    expect(restored.recovered, isFalse);
  });

  test('corrupt current storage recovers last valid layout without erasing records', () async {
    final storage = MemoryBrowserMenuStorage()
      ..values[BrowserMenuStore.currentKey] = '{bad json'
      ..values[BrowserMenuStore.backupKey] = named('last-good').encode();
    final store = BrowserMenuStore(storage: storage);
    addTearDown(store.dispose);
    await store.ready;
    expect(store.layout.menus.single.id, 'last-good');
    expect(store.recovered, isTrue);
    expect(storage.writes, isEmpty);
    expect(storage.values[BrowserMenuStore.currentKey], '{bad json');
  });

  test('corrupt active and backup records retain usable defaults and a recovery notice', () async {
    final storage = MemoryBrowserMenuStorage()
      ..values[BrowserMenuStore.currentKey] = '[]'
      ..values[BrowserMenuStore.backupKey] = '{}';
    final store = BrowserMenuStore(storage: storage);
    addTearDown(store.dispose);
    await store.ready;
    expect(store.layout.toJson(), BrowserMenuLayout.defaults().toJson());
    expect(store.recovered, isTrue);
    expect(storage.writes, isEmpty);
  });

  for (final key in [BrowserMenuStore.currentKey, BrowserMenuStore.backupKey]) {
    test(
      'a failed $key write leaves the live last-good layout active',
      () async {
        final storage = MemoryBrowserMenuStorage();
        final store = BrowserMenuStore(storage: storage);
        addTearDown(store.dispose);
        await store.ready;
        await store.save(named('good'));
        storage.failKey = key;
        await expectLater(store.save(named('next')), throwsStateError);
        expect(store.layout.menus.single.id, 'good');
        final reloaded = BrowserMenuStore(storage: storage);
        addTearDown(reloaded.dispose);
        await reloaded.ready;
        expect(reloaded.layout.menus.single.id, 'good');
      },
    );
  }

  test('invalid constructed or imported layouts cannot replace the active configuration', () async {
    final storage = MemoryBrowserMenuStorage();
    final store = BrowserMenuStore(storage: storage);
    addTearDown(store.dispose);
    await store.ready;
    await store.save(named('good'));
    final writes = storage.writes.length;
    final invalid = BrowserMenuLayout([
      BrowserMenuNode(id: 'bad', kind: BrowserMenuNodeKind.separator),
    ]);
    expect(() => store.save(invalid), throwsFormatException);
    expect(
      () => BrowserMenuLayout.decode('{"version":1,"menus":[{"id":"x"}]}'),
      throwsFormatException,
    );
    expect(store.layout.menus.single.id, 'good');
    expect(storage.writes.length, writes);
  });

  test(
    'queued saves keep the immediately preceding valid layout as backup',
    () async {
      final storage = MemoryBrowserMenuStorage();
      final store = BrowserMenuStore(storage: storage);
      addTearDown(store.dispose);
      await store.ready;
      final entered = Completer<void>(), release = Completer<void>();
      storage.beforeWrite = (key) async {
        if (key == BrowserMenuStore.currentKey && !entered.isCompleted) {
          entered.complete();
          await release.future;
        }
      };
      final first = store.save(named('first'));
      await entered.future;
      final second = store.save(named('second'));
      release.complete();
      await Future.wait([first, second]);
      expect(store.layout.menus.single.id, 'second');
      expect(
        BrowserMenuLayout.decode(storage.values[BrowserMenuStore.backupKey]!)
            .menus
            .single
            .id,
        'first',
      );
    },
  );

  test(
    'reset restores usable defaults and keeps the preceding layout recoverable',
    () async {
      final storage = MemoryBrowserMenuStorage();
      final store = BrowserMenuStore(storage: storage);
      addTearDown(store.dispose);
      await store.ready;
      await store.save(named('custom'));
      await store.reset();
      expect(store.layout.toJson(), BrowserMenuLayout.defaults().toJson());
      expect(
        BrowserMenuLayout.decode(storage.values[BrowserMenuStore.backupKey]!)
            .menus
            .single
            .id,
        'custom',
      );
    },
  );
}
