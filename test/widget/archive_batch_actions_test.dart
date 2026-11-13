import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/widgets/archive_batch_actions.dart';
import 'package:crisp_cloud/widgets/archive_batch_extraction_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/external_drop_fixture.dart';

class _GrantedLocal extends DropTestLocal implements LocalFileSourceIdentity {
  _GrantedLocal(this.root) : super(root);
  final String root;
  final Object identity = Object();
  @override
  String get grantedBasePath => root;
  @override
  Object? sourceIdentityForPath(String path) =>
      p.equals(root, path) || p.isWithin(root, path) ? identity : null;
}

void main() {
  late Directory temporary;
  late String sourcePath, targetPath, laterPath;
  late _GrantedLocal local;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temporary = await Directory.systemTemp.createTemp('archive-actions-');
    sourcePath = (await Directory(
      p.join(temporary.path, 'source'),
    ).create()).path;
    targetPath = (await Directory(
      p.join(temporary.path, 'target'),
    ).create()).path;
    laterPath = (await Directory(
      p.join(temporary.path, 'later'),
    ).create()).path;
    await File(p.join(sourcePath, 'first.zip')).writeAsBytes([0x50, 0x4b]);
    local = _GrantedLocal(temporary.path);
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(
          (_) => DropTestAuth(DropTestCloud('account')),
        ),
        localFileServiceProvider.overrideWithValue(local),
      ],
    );
    final selected = container.read(panelProvider(PanelSide.remote));
    final target = container.read(panelProvider(PanelSide.local));
    await Future<void>.delayed(Duration.zero);
    await selected.navigateToPath(
      sourcePath,
      origin: selected.captureLocalClipboardOrigin(sourcePath),
    );
    await target.navigateToPath(
      targetPath,
      origin: target.captureLocalClipboardOrigin(targetPath),
    );
    selected.toggleSelection(
      selected.files!.singleWhere((file) => file.name == 'first.zip'),
    );
    container.read(activePanelProvider.notifier).state = PanelSide.remote;
  });

  tearDown(() async {
    container.dispose();
    await temporary.delete(recursive: true);
  });

  testWidgets(
    'batch extraction captures the actual source and reviewed local target',
    (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  return TextButton(
                    onPressed: canExtractArchiveSelection(ref)
                        ? () => showArchiveBatchExtractionForSelection(
                            context,
                            ref,
                          )
                        : null,
                    child: const Text('Extract selection'),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Extract selection'));
      await tester.pumpAndSettle();
      final dialog = tester.widget<ArchiveBatchExtractionDialog>(
        find.byType(ArchiveBatchExtractionDialog),
      );
      // The active pane is named "remote" but its verified listing is local.
      expect(dialog.source.storageReference!.isLocal, isTrue);
      expect(dialog.local, same(local));
      expect(dialog.files.single.path, p.join(sourcePath, 'first.zip'));
      expect(dialog.targetDirectory, targetPath);
      final target = container.read(panelProvider(PanelSide.local));
      await tester.runAsync(
        () => target.navigateToPath(
          laterPath,
          origin: target.captureLocalClipboardOrigin(laterPath),
        ),
      );
      await tester.pumpAndSettle();
      expect(dialog.targetDirectory, targetPath);
      expect(dialog.source.isCurrent, isTrue);
      expect(
        await tester.runAsync(() => Directory(targetPath).list().isEmpty),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
