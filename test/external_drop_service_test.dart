import 'dart:async';
import 'dart:io';

import 'package:crisp_cloud/models/panel_drag_data.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/external_drop_service.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/services/storage_identity.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/external_drop_fixture.dart';

class _VirtualLocal extends DropTestLocal implements LocalFileSourceIdentity {
  _VirtualLocal(super.currentPath);
  Object token = Object();
  @override
  Object? sourceIdentityForPath(String path) =>
      p.equals(path, currentPath) || p.isWithin(currentPath, path)
      ? token
      : null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late DropTestLocal local;
  late DropTestCloud primary;
  late DropTestCloud secondary;
  late ProviderContainer container;
  late PanelNotifier panel;
  const service = ExternalDropService(browser: true);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('drop-destination-');
    local = _VirtualLocal(directory.path);
    primary = DropTestCloud('primary');
    secondary = DropTestCloud('secondary')
      ..directories.addAll(['/target', '/elsewhere']);
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => DropTestAuth(primary)),
        localFileServiceProvider.overrideWithValue(local),
      ],
    );
    container
        .read(multiCloudProvider)
        .addConnection(
          id: 'secondary',
          label: 'Secondary account',
          provider: CloudProvider.s3,
          client: secondary,
        );
    panel = container.read(panelProvider(PanelSide.local));
    await Future<void>.delayed(Duration.zero);
    await panel.navigateToPath(
      '/target',
      origin: panel.resolveStorageReference(
        storageReferenceForClient(secondary),
        '/target',
      ),
    );
    expect(panel.captureCurrentOrigin().source, isA<RemotePanelSource>());
    primary.listed.clear();
    secondary.listed.clear();
  });
  tearDown(() async {
    container.dispose();
    await directory.delete(recursive: true);
  });

  test(
    'the visually local pane retains its actual secondary remote destination',
    () async {
      final destination = service.capture(panel, local);
      final prepared = await service.prepare(panel, destination, [
        DropTestFile('file.txt', [1]),
      ]);
      addTearDown(prepared.source.close);
      expect(destination.side, PanelSide.local);
      expect(destination.path, '/target');
      expect(
        (destination.origin.source as RemotePanelSource).client,
        same(secondary),
      );
      expect(primary.listed, isEmpty);
      expect(secondary.listed, ['/target']);
      expect(primary.writes, isEmpty);
      expect(secondary.writes, isEmpty);
      expect(local.snapshots, isEmpty);
    },
  );

  for (final mutation in ['navigation', 'refresh', 'tab', 'account']) {
    test(
      '$mutation during source metadata preparation rejects the original destination',
      () async {
        final destination = service.capture(panel, local);
        final file = DropTestFile('late.txt', [1])
          ..pendingLength = Completer<int>();
        final pending = service.prepare(panel, destination, [file]);
        final rejected = expectLater(
          pending,
          throwsA(
            isA<PanelDragException>().having(
              (error) => error.failure,
              'failure',
              PanelDragFailure.destinationChanged,
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        switch (mutation) {
          case 'navigation':
            await panel.navigateToPath('/elsewhere');
          case 'refresh':
            await panel.refresh();
          case 'tab':
            panel.addTab(path: '/target');
            await panel.refresh();
          case 'account':
            secondary.account = 'replacement';
        }
        file.pendingLength!.complete(1);
        await rejected;
        expect(primary.writes, isEmpty);
        expect(secondary.writes, isEmpty);
      },
    );
  }

  test('a reviewed destination remains the captured path when the pane later browses elsewhere', () async {
    final destination = service.capture(panel, local);
    final prepared = await service.prepare(panel, destination, [
      DropTestFile('file.txt', [1]),
    ]);
    addTearDown(prepared.source.close);
    await panel.navigateToPath('/elsewhere');
    expect(destination.isCurrent, isFalse);
    expect(destination.path, '/target');
    expect(destination.origin.isCurrent, isTrue);
    expect(prepared.sourceOrigin.isCurrent, isTrue);
    expect(
      (destination.origin.source as RemotePanelSource).client,
      same(secondary),
    );
  });

  test(
    'the visually remote pane can target an actual granted local folder',
    () async {
      final remoteSide = container.read(panelProvider(PanelSide.remote));
      await remoteSide.navigateToPath(
        directory.path,
        origin: remoteSide.captureLocalClipboardOrigin(directory.path),
      );
      final destination = service.capture(remoteSide, local);
      final prepared = await service.prepare(remoteSide, destination, [
        DropTestFile('file.txt', [1]),
      ]);
      addTearDown(prepared.source.close);
      expect(destination.side, PanelSide.remote);
      expect(destination.origin.source, isA<LocalPanelSource>());
      expect(destination.path, directory.path);
      expect(local.snapshots, [directory.path]);
      expect(primary.writes, isEmpty);
      expect(secondary.writes, isEmpty);
    },
  );

  test(
    'a replaced local grant cannot inherit a pending external drop',
    () async {
      await panel.navigateToPath(
        directory.path,
        origin: panel.captureLocalClipboardOrigin(directory.path),
      );
      final destination = service.capture(panel, local);
      final file = DropTestFile('late.txt', [1])
        ..pendingLength = Completer<int>();
      final pending = service.prepare(panel, destination, [file]);
      final rejected = expectLater(pending, throwsA(isA<PanelDragException>()));
      await Future<void>.delayed(Duration.zero);
      (local as _VirtualLocal).token = Object();
      file.pendingLength!.complete(1);
      await rejected;
      expect(await directory.list().isEmpty, isTrue);
    },
  );

  test(
    'search and ungranted synthetic local roots cannot receive external files',
    () async {
      panel.showSearchResults([], origin: panel.captureCurrentOrigin());
      expect(
        () => service.capture(panel, local),
        throwsA(isA<PanelDragException>()),
      );
      await panel.navigateToPath(
        '/',
        origin: panel.captureLocalClipboardOrigin('/'),
      );
      expect(
        () => service.capture(panel, local),
        throwsA(isA<PanelDragException>()),
      );
    },
  );
}
