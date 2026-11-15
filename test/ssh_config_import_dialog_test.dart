import 'dart:async';

import 'package:crisp_cloud/l10n/ssh_config_import_strings.dart';
import 'package:crisp_cloud/models/ssh_config_import.dart';
import 'package:crisp_cloud/models/ssh_terminal_config.dart';
import 'package:crisp_cloud/models/ssh_terminal_profile.dart';
import 'package:crisp_cloud/services/ssh_terminal_profiles.dart';
import 'package:crisp_cloud/widgets/ssh_config_import_dialog.dart';
import 'package:crisp_cloud/widgets/ssh_terminal_profiles_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String? raw;
  late SshTerminalProfiles store;
  setUp(() {
    raw = null;
    store = SshTerminalProfiles(
      read: () async => raw,
      write: (value) async => raw = value,
    );
  });

  Future<void> open(WidgetTester tester, {Widget? dialog}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (_) => dialog ?? SshConfigImportDialog(store: store),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> preview(WidgetTester tester, String source) async {
    await tester.enterText(
      find.byKey(const ValueKey('ssh-config-source')),
      source,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('ssh-config-preview')),
    );
    await tester.tap(find.byKey(const ValueKey('ssh-config-preview')));
    await tester.pumpAndSettle();
  }

  Future<void> select(WidgetTester tester, String alias) async {
    final checkbox = find.byKey(ValueKey('ssh-config-select-$alias'));
    await tester.ensureVisible(checkbox);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
  }

  FilledButton importButton(WidgetTester tester) => tester.widget<FilledButton>(
    find.byKey(const ValueKey('ssh-config-import')),
  );

  SshTerminalProfile profile(String name, [String host = 'original.example']) =>
      SshTerminalProfile(
        name: name,
        config: SshTerminalConfig(host: host, port: 22, username: 'existing'),
      );

  testWidgets('only selected aliases are saved with no automatic connection', (
    tester,
  ) async {
    await open(tester);
    await preview(tester, 'Host one two\nUser alice\nIdentityFile ~/.ssh/key');
    expect(importButton(tester).onPressed, isNull);
    expect(raw, isNull);
    await select(tester, 'two');
    await tester.tap(find.byKey(const ValueKey('ssh-config-import')));
    await tester.pumpAndSettle();
    final saved = await store.load();
    expect(saved.single.name, 'two');
    expect(saved.single.config.host, 'two');
    expect(saved.single.config.privateKey, isEmpty);
    expect(raw, isNot(contains('~/.ssh/key')));
    expect(find.byType(SshConfigImportDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'existing names get an editable unique suggestion and never overwrite',
    (tester) async {
      await store.save(profile('one'));
      await open(tester);
      await preview(tester, 'Host one\nUser alice\nHostName imported.example');
      final name = find.byKey(const ValueKey('ssh-config-name-one'));
      expect(tester.widget<TextField>(name).controller!.text, 'one (1)');
      await select(tester, 'one');
      await tester.enterText(name, 'one');
      await tester.pumpAndSettle();
      expect(importButton(tester).onPressed, isNull);
      expect(
        find.text('A profile with this name already exists.'),
        findsOneWidget,
      );
      await tester.enterText(name, 'Reviewed');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ssh-config-import')));
      await tester.pumpAndSettle();
      final saved = await store.load();
      expect(
        saved.singleWhere((p) => p.name == 'one').config.host,
        'original.example',
      );
      expect(
        saved.singleWhere((p) => p.name == 'Reviewed').config.host,
        'imported.example',
      );
    },
  );

  testWidgets('a racing profile save rejects the batch without replacements', (
    tester,
  ) async {
    await open(tester);
    await preview(tester, 'Host one\nUser alice');
    await select(tester, 'one');
    await store.save(profile('one'));
    await tester.tap(find.byKey(const ValueKey('ssh-config-import')));
    await tester.pumpAndSettle();
    expect((await store.load()).single.config.host, 'original.example');
    expect(
      find.text(
        'Could not import profiles. Check names and available space, then try again.',
      ),
      findsOneWidget,
    );
    expect(find.byType(SshConfigImportDialog), findsOneWidget);
  });

  testWidgets('unsupported routing is visible and cannot be selected', (
    tester,
  ) async {
    await open(tester);
    await preview(
      tester,
      'Host blocked\nUser alice\nProxyCommand special\nHost safe\nUser bob',
    );
    final blocked = tester.widget<CheckboxListTile>(
      find.byKey(const ValueKey('ssh-config-select-blocked')),
    );
    expect(blocked.onChanged, isNull);
    expect(
      find.textContaining('ProxyCommand cannot be imported'),
      findsOneWidget,
    );
    await select(tester, 'safe');
    expect(importButton(tester).onPressed, isNotNull);
  });

  testWidgets('default username fixes a missing user after a fresh preview', (
    tester,
  ) async {
    await open(tester);
    await preview(tester, 'Host one');
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const ValueKey('ssh-config-select-one')),
          )
          .onChanged,
      isNull,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('ssh-config-default-user')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('ssh-config-default-user')),
      'chosen',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ssh-config-select-one')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('ssh-config-preview')));
    await tester.pumpAndSettle();
    await select(tester, 'one');
    await tester.tap(find.byKey(const ValueKey('ssh-config-import')));
    await tester.pumpAndSettle();
    expect((await store.load()).single.config.username, 'chosen');
  });

  testWidgets('editing a previewed source revokes its old selection', (
    tester,
  ) async {
    await open(tester);
    await preview(tester, 'Host old\nUser alice');
    await select(tester, 'old');
    await tester.ensureVisible(find.byKey(const ValueKey('ssh-config-source')));
    await tester.enterText(
      find.byKey(const ValueKey('ssh-config-source')),
      'Host new\nUser bob',
    );
    await tester.pumpAndSettle();
    expect(importButton(tester).onPressed, isNull);
    expect(find.byKey(const ValueKey('ssh-config-select-old')), findsNothing);
    expect(raw, isNull);
  });

  testWidgets(
    'oversized paste rejects all text and revokes the prior preview',
    (tester) async {
      await open(tester);
      const source = 'Host old\nUser alice';
      await preview(tester, source);
      await select(tester, 'old');
      final field = find.byKey(const ValueKey('ssh-config-source'));
      await tester.ensureVisible(field);
      await tester.enterText(field, 'x' * (SshConfigImport.maxCharacters + 1));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, source);
      expect(
        find.text('Input is too long. Nothing was pasted.'),
        findsOneWidget,
      );
      expect(importButton(tester).onPressed, isNull);
      expect(find.byKey(const ValueKey('ssh-config-select-old')), findsNothing);
      expect(raw, isNull);
    },
  );

  testWidgets('storage errors stay bounded and do not leak internal details', (
    tester,
  ) async {
    final broken = SshTerminalProfiles(
      read: () async => null,
      write: (_) async => throw StateError('PRIVATE_ERROR_DETAIL'),
    );
    await open(tester, dialog: SshConfigImportDialog(store: broken));
    await preview(tester, 'Host one\nUser alice');
    await select(tester, 'one');
    await tester.tap(find.byKey(const ValueKey('ssh-config-import')));
    await tester.pumpAndSettle();
    expect(find.textContaining('PRIVATE_ERROR_DETAIL'), findsNothing);
    expect(
      find.text(
        'Could not import profiles. Check names and available space, then try again.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('pending batch writes disable cancel and all import controls', (
    tester,
  ) async {
    final release = Completer<void>();
    final pending = SshTerminalProfiles(
      read: () async => null,
      write: (_) => release.future,
    );
    await open(tester, dialog: SshConfigImportDialog(store: pending));
    await preview(tester, 'Host one\nUser alice');
    await select(tester, 'one');
    await tester.tap(find.byKey(const ValueKey('ssh-config-import')));
    await tester.pump();
    expect(importButton(tester).onPressed, isNull);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('ssh-config-source')))
          .enabled,
      isFalse,
    );
    release.complete();
    await tester.pumpAndSettle();
    expect(find.byType(SshConfigImportDialog), findsNothing);
  });

  testWidgets('profile manager exposes import and stays open after saving', (
    tester,
  ) async {
    await open(tester, dialog: SshTerminalProfilesDialog(store: store));
    await tester.tap(find.byKey(const ValueKey('ssh-profiles-import-config')));
    await tester.pumpAndSettle();
    await preview(tester, 'Host one\nUser alice');
    await select(tester, 'one');
    await tester.tap(find.byKey(const ValueKey('ssh-config-import')));
    await tester.pumpAndSettle();
    expect(find.byType(SshConfigImportDialog), findsNothing);
    expect(find.byType(SshTerminalProfilesDialog), findsOneWidget);
    expect(find.byKey(const ValueKey('ssh-profile-one')), findsOneWidget);
  });

  testWidgets(
    'short narrow layouts scroll source preview and selection without overflow',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 360);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await open(tester);
      await preview(
        tester,
        'Host one\nUser alice\nIdentityFile ~/.ssh/long-key-name',
      );
      await select(tester, 'one');
      expect(importButton(tester).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'all eight established locales translate the import entry point',
    (tester) async {
      for (final locale in ['de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar']) {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Localizations.override(
                context: context,
                locale: Locale(locale),
                child: Builder(
                  builder: (localized) => Text(
                    localized.sshConfigImportTr('Import OpenSSH config'),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(
          find.text('Import OpenSSH config'),
          findsNothing,
          reason: locale,
        );
      }
    },
  );
}
