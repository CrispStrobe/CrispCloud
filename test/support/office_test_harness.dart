import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/file_cache_service.dart';
import 'package:crisp_cloud/services/office_device_export.dart';
import 'package:crisp_cloud/widgets/office_editor_dialog.dart';
import 'package:crisp_cloud/widgets/office_editor_ribbon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'workflow_fake_client.dart';
import 'workspace_fixture.dart';

class OfficeTestCloud extends WorkflowFakeClient {
  Completer<void>? _nextUpload;
  Completer<void>? _activeUpload;
  Uint8List? pendingBytes;
  int uploadAttempts = 0;

  void pauseNextUpload() {
    _nextUpload = Completer<void>();
    pendingBytes = null;
  }

  void releaseUpload() => _activeUpload!.complete();

  @override
  Future<void> uploadFile(
    List<int> bytes,
    String name,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    uploadAttempts++;
    final gate = _nextUpload;
    _nextUpload = null;
    if (gate != null) {
      _activeUpload = gate;
      pendingBytes = Uint8List.fromList(bytes);
      await gate.future;
      _activeUpload = null;
    }
    await super.uploadFile(bytes, name, targetPath, onProgress: onProgress);
  }
}

class _Cache extends FileCacheService {
  @override
  Future<void> remove(String remotePath, String provider) async {}
}

/// Opens the real host over a deterministic captured remote target.
class OfficeTestHarness {
  OfficeTestHarness._(this.tester, this.cloud, this.container, this.name);

  final WidgetTester tester;
  final OfficeTestCloud cloud;
  final ProviderContainer container;
  final String name;

  OfficeEditorRibbon get ribbon =>
      tester.widget<OfficeEditorRibbon>(find.byType(OfficeEditorRibbon));
  OfficeController get controller => ribbon.controller;
  Uint8List get savedBytes => cloud.files['/$name']!;

  static Future<OfficeTestHarness> open(
    WidgetTester tester, {
    String name = 'report.docx',
    String fixture = 'word.docx',
    Uint8List? bytesOverride,
    bool expectEditor = true,
    OfficeDeviceExporter copyExporter = exportOfficeCopy,
    Locale locale = const Locale('en'),
  }) async {
    SharedPreferences.setMockInitialValues({});
    final cloud = OfficeTestCloud()
      ..put(
        '/$name',
        bytesOverride ??
            File('packages/quds_office_engine/test/fixtures/fidelity/$fixture')
                .readAsBytesSync(),
      );
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => WorkspaceTestAuth(cloud)),
        fileCacheProvider.overrideWithValue(_Cache()),
      ],
    );
    addTearDown(container.dispose);
    final panel = container.read(panelProvider(PanelSide.remote));
    await panel.refresh();
    final file = panel.files!.single;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => OfficeEditorDialog(
                      file: file,
                      side: PanelSide.remote,
                      bytesOverride: bytesOverride,
                      targetOverride: bytesOverride == null
                          ? null
                          : panel.captureFileTarget(file),
                      copyExporter: copyExporter,
                    ),
                  ),
                ),
                child: const Text('Open fixture'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open fixture'));
    await officePumpUntil(
      tester,
      () => expectEditor
          ? find.byType(OfficeEditorRibbon).evaluate().isNotEmpty
          : find
                .textContaining('Could not open this document')
                .evaluate()
                .isNotEmpty,
    );
    await tester.pump(const Duration(milliseconds: 400));
    return OfficeTestHarness._(tester, cloud, container, name);
  }

  Future<void> back() async {
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> save() async {
    ribbon.onSave();
    await officePumpUntil(tester, () => !ribbon.saving);
  }

  Future<void> copy() async {
    ribbon.onSaveCopy!();
    await officePumpUntil(tester, () => !ribbon.saving);
  }

  Future<void> dispose() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }
}

Future<void> officePumpUntil(
  WidgetTester tester,
  bool Function() complete,
) async {
  final elapsed = Stopwatch()..start();
  do {
    await tester.pump(const Duration(milliseconds: 20));
    await Future<void>.delayed(const Duration(milliseconds: 1));
    if (elapsed.elapsed > const Duration(seconds: 15)) {
      throw TimeoutException('The Office host operation did not complete.');
    }
  } while (!complete());
  await tester.pump();
}
