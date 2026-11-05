import 'dart:convert';

import 'package:crisp_cloud/models/command_extension.dart';
import 'package:crisp_cloud/models/custom_toolbar_command.dart';
import 'package:crisp_cloud/services/command_extension_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

CustomToolbarCommand _command({
  String executable = 'inspect',
  List<String> arguments = const ['{SELECTED}'],
}) => CustomToolbarCommand(
  id: 'inspect',
  label: 'Inspect files',
  executable: executable,
  arguments: arguments,
);
CommandExtensionManifest _manifest({
  String id = 'com.example.inspect',
  CustomToolbarCommand? command,
  Set<CommandExtensionCapability>? capabilities,
}) => CommandExtensionManifest(
  id: id,
  name: 'Inspector',
  version: '1.0.0',
  description: 'Inspect selected local files.',
  commands: [command ?? _command()],
  capabilities: capabilities ?? CommandExtensionCapability.values.toSet(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'install is inert and disabled until the user enables declared actions',
    () async {
      final store = CommandExtensionStore();
      addTearDown(store.dispose);
      await store.install(
        _manifest(capabilities: {CommandExtensionCapability.toolbar}),
      );
      expect(store.installed.single.enabled, isFalse);
      expect(store.actions(CommandExtensionCapability.toolbar), isEmpty);
      await store.setEnabled('com.example.inspect', true);
      expect(
        store
            .actions(CommandExtensionCapability.toolbar)
            .single
            .command
            .executable,
        'inspect',
      );
      expect(store.actions(CommandExtensionCapability.contextMenu), isEmpty);
    },
  );

  test('manifest round-trip retains each argument without shell parsing', () {
    final manifest = _manifest(
      command: _command(
        arguments: ['--label', 'two words', r'$(literal)', '{SELECTED}'],
      ),
    );
    final restored = CommandExtensionManifest.decode(manifest.exportText());
    expect(restored.commands.single.arguments, [
      '--label',
      'two words',
      r'$(literal)',
      '{SELECTED}',
    ]);
    expect(restored.capabilities, CommandExtensionCapability.values.toSet());
  });

  test('binary loaders, background hooks and unsupported capabilities are rejected', () {
    final binary = _manifest().toJson()..['library'] = '/plugin.so';
    expect(
      () => CommandExtensionManifest.fromJson(binary),
      throwsFormatException,
    );
    final script = _manifest().toJson()..['initialize'] = 'run this';
    expect(
      () => CommandExtensionManifest.fromJson(script),
      throwsFormatException,
    );
    final capability = _manifest().toJson()..['capabilities'] = ['fileAction'];
    expect(
      () => CommandExtensionManifest.fromJson(capability),
      throwsArgumentError,
    );
    expect(
      () => _manifest(
        command: const CustomToolbarCommand(
          id: 'legacy',
          label: 'Legacy',
          command: 'echo x',
        ),
      ),
      throwsFormatException,
    );
  });

  test(
    'unsafe IDs, duplicate commands and relative executables are rejected',
    () {
      expect(() => _manifest(id: '../escape'), throwsFormatException);
      expect(
        () =>
            _manifest(command: _command(executable: './from-selected-folder')),
        throwsFormatException,
      );
      final duplicate = _manifest().toJson();
      (duplicate['commands'] as List).add(_command().toJson());
      expect(
        () => CommandExtensionManifest.fromJson(duplicate),
        throwsFormatException,
      );
      expect(
        () => _manifest(
          command: _command(executable: 'sh', arguments: ['-c', 'echo {FILE}']),
        ),
        throwsFormatException,
      );
    },
  );

  test('captured actions are invalid after disable, re-enable, settings changes and removal', () async {
    final store = CommandExtensionStore();
    addTearDown(store.dispose);
    const id = 'com.example.inspect';
    await store.install(_manifest());
    await store.setEnabled(id, true);
    final initial = store.actions(CommandExtensionCapability.toolbar).single;
    expect(store.isActionCurrent(initial), isTrue);
    await store.setEnabled(id, false);
    expect(store.isActionCurrent(initial), isFalse);
    await store.setEnabled(id, true);
    expect(store.isActionCurrent(initial), isFalse);
    final beforeSettings = store
        .actions(CommandExtensionCapability.toolbar)
        .single;
    await store.configure(
      id,
      _command(
        executable: '/usr/bin/inspect',
        arguments: ['--details', '{SELECTED}'],
      ),
    );
    expect(store.isActionCurrent(beforeSettings), isFalse);
    final configured = store.actions(CommandExtensionCapability.toolbar).single;
    expect(configured.command.arguments.first, '--details');
    expect(configured.command.executable, '/usr/bin/inspect');
    await store.remove(id);
    expect(store.isActionCurrent(configured), isFalse);
    expect(store.actions(CommandExtensionCapability.toolbar), isEmpty);
  });

  test(
    'settings and enabled state survive restart but old store snapshots do not',
    () async {
      final first = CommandExtensionStore();
      addTearDown(first.dispose);
      await first.install(_manifest());
      await first.configure(
        'com.example.inspect',
        _command(arguments: ['--new', '{SELECTED}']),
      );
      await first.setEnabled('com.example.inspect', true);
      final captured = first.actions(CommandExtensionCapability.toolbar).single;
      final restored = CommandExtensionStore();
      addTearDown(restored.dispose);
      expect(restored.actions(CommandExtensionCapability.toolbar), isEmpty);
      await restored.ready;
      expect(restored.installed.single.enabled, isTrue);
      expect(
        restored
            .actions(CommandExtensionCapability.toolbar)
            .single
            .command
            .arguments
            .first,
        '--new',
      );
      expect(restored.isActionCurrent(captured), isFalse);
    },
  );

  test('updates require explicit replacement and restart disabled with reviewed defaults', () async {
    final store = CommandExtensionStore();
    addTearDown(store.dispose);
    await store.install(_manifest());
    await store.setEnabled('com.example.inspect', true);
    await store.configure(
      'com.example.inspect',
      _command(arguments: ['--custom']),
    );
    await expectLater(store.install(_manifest()), throwsStateError);
    expect(store.installed.single.enabled, isTrue);
    await store.install(
      _manifest(command: _command(arguments: ['--updated'])),
      replace: true,
    );
    expect(store.installed.single.enabled, isFalse);
    expect(store.installed.single.overrides, isEmpty);
    expect(store.installed.single.commands.single.arguments, ['--updated']);
  });

  test(
    'a captured generation cannot authorize a substituted command',
    () async {
      final store = CommandExtensionStore();
      addTearDown(store.dispose);
      await store.install(_manifest());
      await store.setEnabled('com.example.inspect', true);
      final action = store.actions(CommandExtensionCapability.toolbar).single;
      final substituted = CommandExtensionAction(
        extensionId: action.extensionId,
        extensionName: action.extensionName,
        command: _command(executable: 'different-program'),
        generation: action.generation,
        owner: action.owner,
      );
      expect(store.isActionCurrent(action), isTrue);
      expect(store.isActionCurrent(substituted), isFalse);
    },
  );

  test('simultaneous installations do not lose records', () async {
    final store = CommandExtensionStore();
    addTearDown(store.dispose);
    await Future.wait([
      store.install(_manifest(id: 'com.example.one')),
      store.install(_manifest(id: 'com.example.two')),
    ]);
    expect(store.installed, hasLength(2));
    final saved = jsonDecode(
      (await SharedPreferences.getInstance()).getString(
        CommandExtensionStore.preferencesKey,
      )!,
    ) as Map;
    expect(saved['extensions'], hasLength(2));
  });

  test(
    'failed persistence preserves the current actions and settings',
    () async {
      final prefs = await SharedPreferences.getInstance();
      var fail = false;
      final store = CommandExtensionStore(
        preferences: () async {
          if (fail) throw StateError('storage unavailable');
          return prefs;
        },
      );
      addTearDown(store.dispose);
      await store.install(_manifest());
      await store.setEnabled('com.example.inspect', true);
      final action = store.actions(CommandExtensionCapability.toolbar).single;
      fail = true;
      await expectLater(
        store.configure(
          'com.example.inspect',
          _command(arguments: ['--not-saved']),
        ),
        throwsStateError,
      );
      expect(store.isActionCurrent(action), isTrue);
      expect(store.installed.single.overrides, isEmpty);
    },
  );

  test('corrupt stored manifests are retained and expose no actions', () async {
    SharedPreferences.setMockInitialValues({
      CommandExtensionStore.preferencesKey: '{broken',
    });
    final store = CommandExtensionStore();
    addTearDown(store.dispose);
    await store.ready;
    expect(store.loadError, isNotNull);
    expect(store.actions(CommandExtensionCapability.toolbar), isEmpty);
    await expectLater(store.install(_manifest()), throwsStateError);
    expect(
      (await SharedPreferences.getInstance()).getString(
        CommandExtensionStore.preferencesKey,
      ),
      '{broken',
    );
  });

  test(
    'export uses configured commands and reset restores manifest defaults',
    () async {
      final store = CommandExtensionStore();
      addTearDown(store.dispose);
      await store.install(_manifest());
      await store.configure(
        'com.example.inspect',
        _command(arguments: ['--configured']),
      );
      expect(
        CommandExtensionManifest.decode(
          store.exportManifest('com.example.inspect'),
        ).commands.single.arguments,
        ['--configured'],
      );
      await store.resetSettings('com.example.inspect');
      expect(store.installed.single.commands.single.arguments, ['{SELECTED}']);
      await expectLater(
        store.configure(
          'com.example.inspect',
          const CustomToolbarCommand(
            id: 'unknown',
            label: 'Unknown',
            executable: 'inspect',
          ),
        ),
        throwsFormatException,
      );
    },
  );
}
