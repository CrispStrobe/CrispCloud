import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/custom_command_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/custom_toolbar_command_service.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/storage_identity.dart';
import 'package:crisp_cloud/widgets/configurable_browser_menu.dart';
import 'package:crisp_cloud/widgets/custom_command_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/external_drop_fixture.dart';

class _GrantedLocal extends DropTestLocal implements LocalFileSourceIdentity {
  _GrantedLocal(this.root) : super(root);
  final String root;
  Object token = Object();
  @override
  String get grantedBasePath => root;
  @override
  Object? sourceIdentityForPath(String path) =>
      p.equals(root, path) || p.isWithin(root, path) ? token : null;
}

void main() {
  late Directory temporary;
  late String sourcePath, targetPath;
  late _GrantedLocal local;
  late DropTestCloud cloud;
  late ProviderContainer container;
  late CustomToolbarCommandService service;
  late PanelNotifier sourcePanel, targetPanel;
  late BrowserMenuCommandBinding binding;
  var starts = 0;
  var inputOwned = true;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temporary = await Directory.systemTemp.createTemp('menu-command-');
    sourcePath = (await Directory(
      p.join(temporary.path, 'source'),
    ).create()).path;
    targetPath = (await Directory(
      p.join(temporary.path, 'target'),
    ).create()).path;
    await File(p.join(sourcePath, 'first.txt')).writeAsString('first');
    await File(p.join(sourcePath, 'second.txt')).writeAsString('second');
    local = _GrantedLocal(temporary.path);
    cloud = DropTestCloud('original');
    starts = 0;
    inputOwned = true;
    service = CustomToolbarCommandService(
      processStarter: (_, _, _) async {
        starts++;
        throw StateError('Menu tests never start a process.');
      },
    );
    await service.load();
    await service.addCommand(
      const CustomToolbarCommand(
        id: 'review',
        label: 'Reviewed command',
        executable: 'printf',
        arguments: ['{CURRENT}', '{FILE}', '{TARGET}'],
      ),
    );
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => DropTestAuth(cloud)),
        localFileServiceProvider.overrideWithValue(local),
        customToolbarCommandServiceProvider.overrideWith((_) => service),
      ],
    );
    sourcePanel = container.read(panelProvider(PanelSide.remote));
    targetPanel = container.read(panelProvider(PanelSide.local));
    await Future<void>.delayed(Duration.zero);
    await targetPanel.navigateToPath(
      targetPath,
      origin: targetPanel.captureLocalClipboardOrigin(targetPath),
    );
    await sourcePanel.navigateToPath(
      sourcePath,
      origin: sourcePanel.captureLocalClipboardOrigin(sourcePath),
    );
    sourcePanel.toggleSelection(
      sourcePanel.files!.firstWhere((file) => file.name == 'first.txt'),
    );
    container.read(activePanelProvider.notifier).state = PanelSide.remote;
  });
  tearDown(() async {
    container.dispose();
    await temporary.delete(recursive: true);
  });

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                binding = userBrowserMenuCommand(
                  context,
                  ref,
                  PanelSide.remote,
                  service.commands.single,
                  ownsInput: () => inputOwned,
                );
                return TextButton(
                  onPressed: binding.onSelected,
                  child: Text(binding.label),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  desktopTest(
    'user commands open the normal review with captured local paths on either pane',
    (tester) async {
      await mount(tester);
      expect(binding.enabled, isTrue);
      expect(starts, 0);
      await tester.tap(find.text('Reviewed command'));
      await tester.pumpAndSettle();
      final dialog = tester.widget<CommandRunDialog>(
        find.byType(CommandRunDialog),
      );
      expect(dialog.captured.currentPath, sourcePath);
      expect(dialog.captured.selectedPaths, [p.join(sourcePath, 'first.txt')]);
      expect(dialog.prepared.arguments, [
        sourcePath,
        p.join(sourcePath, 'first.txt'),
        targetPath,
      ]);
      await tester.runAsync(() => sourcePanel.navigateToPath(targetPath));
      expect(dialog.captured.currentPath, sourcePath);
      expect(dialog.prepared.arguments, [
        sourcePath,
        p.join(sourcePath, 'first.txt'),
        targetPath,
      ]);
      expect(starts, 0);
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();
    },
  );

  for (final mutation in [
    'navigation',
    'selection',
    'grant',
    'other pane',
    'active pane',
    'input ownership',
    'command replacement',
  ]) {
    desktopTest('$mutation invalidates a captured user-command menu callback', (
      tester,
    ) async {
      await mount(tester);
      final invoke = binding.onSelected!;
      switch (mutation) {
        case 'navigation':
          await tester.runAsync(() => sourcePanel.navigateToPath(targetPath));
        case 'selection':
          sourcePanel.clearSelection();
          sourcePanel.toggleSelection(
            sourcePanel.files!.firstWhere((file) => file.name == 'second.txt'),
          );
        case 'grant':
          local.token = Object();
        case 'other pane':
          await tester.runAsync(() => targetPanel.navigateToPath(sourcePath));
        case 'active pane':
          container.read(activePanelProvider.notifier).state = PanelSide.local;
        case 'input ownership':
          inputOwned = false;
        case 'command replacement':
          await tester.runAsync(
            () => service.updateCommand(
              const CustomToolbarCommand(
                id: 'review',
                label: 'Replacement',
                executable: 'printf',
                arguments: ['different'],
              ),
            ),
          );
      }
      invoke();
      await tester.pumpAndSettle();
      expect(find.byType(CommandRunDialog), findsNothing);
      expect(starts, 0);
    });
  }

  desktopTest(
    'an actual remote account cannot inherit local command authority from pane position',
    (tester) async {
      await tester.runAsync(
        () => sourcePanel.navigateToPath(
          '/',
          origin: sourcePanel.resolveStorageReference(
            storageReferenceForClient(cloud),
            '/',
          ),
        ),
      );
      await mount(tester);
      expect(binding.enabled, isFalse);
      expect(starts, 0);
    },
  );
}

void desktopTest(
  String description,
  Future<void> Function(WidgetTester) body,
) => testWidgets(
  description,
  body,
  variant: TargetPlatformVariant.only(TargetPlatform.linux),
);
