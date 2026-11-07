import 'dart:async';

import 'package:crisp_cloud/l10n/terminal_workspace_strings.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/terminal_workspace_service.dart';
import 'package:crisp_cloud/widgets/terminal_workspace_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Client extends Fake implements CloudStorageClient {}

TerminalWorkspace _workspace({bool pending = false}) => TerminalWorkspace(
  id: '123e4567-e89b-12d3-a456-426614174000',
  title: 'Project',
  storage: const StorageReference(
    kind: 'remote',
    provider: 'Cloud',
    accountKey: 'original-account',
  ),
  remoteRoot: '/project',
  remoteRootFingerprint: TerminalWorkspaceFingerprint(
    isDirectory: true,
    objectId: 'root',
  ),
  directoryPath: '/Documents/workspaces/project/files',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  revision: 1,
  status: pending
      ? TerminalWorkspaceStatus.interrupted
      : TerminalWorkspaceStatus.ready,
  entries: [
    if (pending)
      TerminalWorkspaceEntry(
        relativePath: 'file.txt',
        remotePath: '/project/file.txt',
        fingerprint: TerminalWorkspaceFingerprint(
          isDirectory: false,
          objectId: 'file',
        ),
      ),
  ],
);

TerminalWorkspaceChange _change(
  String path,
  TerminalWorkspaceChangeKind kind,
) => TerminalWorkspaceChange(
  workspaceId: _workspace().id,
  manifestRevision: 1,
  relativePath: path,
  remotePath: '/project/$path',
  kind: kind,
  digest:
      kind == TerminalWorkspaceChangeKind.modified ||
          kind == TerminalWorkspaceChangeKind.added
      ? 'a' * 64
      : null,
  size: 3,
);

class _Service extends Fake implements TerminalWorkspaceService {
  List<TerminalWorkspace> saved = [_workspace()];
  List<TerminalWorkspaceChange> changes = [
    _change('file.txt', TerminalWorkspaceChangeKind.modified),
  ];
  Object? listError;
  int lists = 0;
  int loads = 0;
  int resumes = 0;
  int uploads = 0;
  CloudStorageClient? uploadedClient;
  List<TerminalWorkspaceChange>? uploadedChanges;
  @override
  List<String> get warnings => const [];
  @override
  Future<List<TerminalWorkspace>> list({StorageReference? storage}) async {
    lists++;
    if (listError != null) throw listError!;
    return saved;
  }

  @override
  Future<TerminalWorkspace?> load(String id) async {
    loads++;
    return saved.where((workspace) => workspace.id == id).firstOrNull;
  }

  @override
  Future<List<TerminalWorkspaceChange>> inspect(String workspaceId) async =>
      changes;
  @override
  Future<TerminalWorkspace> resumeStage({
    required String workspaceId,
    required CloudStorageClient client,
    required bool Function() isCurrent,
    bool Function()? isCancelled,
  }) async {
    expect(isCurrent(), isTrue);
    expect(isCancelled?.call(), isFalse);
    resumes++;
    saved = [_workspace()];
    return saved.single;
  }

  @override
  Future<TerminalWorkspaceUploadResult> uploadReviewed({
    required String workspaceId,
    required CloudStorageClient client,
    required List<TerminalWorkspaceChange> changes,
    required bool Function() isCurrent,
    bool Function()? isCancelled,
  }) async {
    expect(isCurrent(), isTrue);
    uploads++;
    uploadedClient = client;
    uploadedChanges = changes;
    return TerminalWorkspaceUploadResult(
      workspace: saved.single,
      uploadedPaths: [changes.first.relativePath],
      skippedPaths: const [],
      failures: const {'conflict.txt': 'Remote file changed.'},
    );
  }
}

Future<void> _launch(
  WidgetTester tester,
  Future<void> Function(BuildContext) action,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => unawaited(action(context)),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
}

void main() {
  test('workspace strings localize known keys and preserve unknown text', () {
    for (final language in ['de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar']) {
      final strings = TerminalWorkspaceStrings(language);
      expect(
        strings.text('Stage selected files'),
        isNot('Stage selected files'),
      );
      expect(strings.text('Review uploads'), isNotEmpty);
      expect(strings.text('provider detail'), 'provider detail');
    }
    expect(
      const TerminalWorkspaceStrings('en').text('Review uploads'),
      'Review uploads',
    );
    expect(
      const TerminalWorkspaceStrings('xx').text('Review uploads'),
      'Review uploads',
    );
  });

  testWidgets('task shows progress and returns its completed result', (
    tester,
  ) async {
    final pending = Completer<String>();
    String? result;
    await _launch(tester, (context) async {
      result = await showTerminalWorkspaceTask<String>(
        context,
        title: 'Stage',
        task: (cancelled, progress) {
          expect(cancelled(), isFalse);
          progress(1, 3);
          return pending.future;
        },
      );
    });
    await tester.pump();
    expect(find.text('1 / 3'), findsOneWidget);
    pending.complete('ready');
    await tester.pumpAndSettle();
    expect(result, 'ready');
    expect(find.byType(TerminalWorkspaceTaskDialog<String>), findsNothing);
  });

  testWidgets(
    'cancel waits for the safe checkpoint and suppresses a late result',
    (tester) async {
      final pending = Completer<String>();
      late bool Function() isCancelled;
      var finished = false;
      String? result;
      await _launch(tester, (context) async {
        result = await showTerminalWorkspaceTask<String>(
          context,
          title: 'Stage',
          task: (cancelled, _) {
            isCancelled = cancelled;
            return pending.future;
          },
        );
        finished = true;
      });
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(isCancelled(), isTrue);
      expect(finished, isFalse);
      expect(find.text('Stopping…'), findsOneWidget);
      pending.complete('late');
      await tester.pumpAndSettle();
      expect(finished, isTrue);
      expect(result, isNull);
    },
  );

  testWidgets(
    'task failures remain reviewable and disposal cancels outstanding work',
    (tester) async {
      await _launch(tester, (context) async {
        await showTerminalWorkspaceTask<void>(
          context,
          title: 'Stage',
          task: (_, _) async => throw StateError('disk full'),
        );
      });
      await tester.pumpAndSettle();
      expect(find.text('Workspace operation failed'), findsOneWidget);
      expect(find.textContaining('disk full'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      final pending = Completer<void>();
      late bool Function() isCancelled;
      await _launch(tester, (context) async {
        await showTerminalWorkspaceTask<void>(
          context,
          title: 'Stage',
          task: (cancelled, _) {
            isCancelled = cancelled;
            return pending.future;
          },
        );
      });
      await tester.pumpWidget(const SizedBox());
      expect(isCancelled(), isTrue);
      pending.complete();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'review permits only selected uploadable files and never selects deletions',
    (tester) async {
      final changes = [
        _change('edit.txt', TerminalWorkspaceChangeKind.modified),
        _change('new.txt', TerminalWorkspaceChangeKind.added),
        _change('deleted.txt', TerminalWorkspaceChangeKind.deleted),
        _change('link', TerminalWorkspaceChangeKind.unsafe),
      ];
      List<TerminalWorkspaceChange>? selected;
      await _launch(tester, (context) async {
        selected = await showDialog<List<TerminalWorkspaceChange>>(
          context: context,
          builder: (_) => TerminalWorkspaceReviewDialog(
            workspace: _workspace(),
            changes: changes,
          ),
        );
      });
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('workspace-change-deleted.txt')),
            )
            .onChanged,
        isNull,
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('workspace-change-link')),
            )
            .onChanged,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('workspace-change-new.txt')));
      await tester.pump();
      await tester.tap(find.text('Upload selected'));
      await tester.pumpAndSettle();
      expect(selected, [same(changes.first)]);
    },
  );

  testWidgets('an empty review has no enabled upload action', (tester) async {
    await _launch(tester, (context) async {
      await showDialog<void>(
        context: context,
        builder: (_) => TerminalWorkspaceReviewDialog(
          workspace: _workspace(),
          changes: const [],
        ),
      );
    });
    await tester.pumpAndSettle();
    expect(find.text('No local changes.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('workspace-upload-selected')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('saved workspaces reload their manifest before opening a shell', (
    tester,
  ) async {
    final service = _Service();
    TerminalWorkspace? opened;
    await _launch(tester, (context) async {
      opened = await showDialog<TerminalWorkspace>(
        context: context,
        builder: (_) =>
            TerminalWorkspacesDialog(service: service, resolve: (_) => null),
      );
    });
    await tester.pumpAndSettle();
    expect(find.text('Project'), findsOneWidget);
    await tester.tap(find.byTooltip('Open shell'));
    await tester.pumpAndSettle();
    expect(service.loads, 1);
    expect(opened, same(service.saved.single));
  });

  testWidgets('workspace listing errors can be refreshed', (tester) async {
    final service = _Service()..listError = StateError('unreadable manifest');
    await _launch(tester, (context) async {
      await showDialog<void>(
        context: context,
        builder: (_) =>
            TerminalWorkspacesDialog(service: service, resolve: (_) => null),
      );
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('unreadable manifest'), findsOneWidget);
    service.listError = null;
    service.saved = [];
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(service.lists, 2);
    expect(find.text('No staged workspaces.'), findsOneWidget);
  });

  testWidgets('interrupted staging resumes against a captured account', (
    tester,
  ) async {
    final service = _Service()..saved = [_workspace(pending: true)];
    final client = _Client();
    await _launch(tester, (context) async {
      await showDialog<void>(
        context: context,
        builder: (_) => TerminalWorkspacesDialog(
          service: service,
          resolve: (_) =>
              TerminalWorkspaceBinding(client: client, isCurrent: () => true),
        ),
      );
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Resume download'));
    await tester.pumpAndSettle();
    expect(service.resumes, 1);
    expect(find.byTooltip('Resume download'), findsNothing);
  });

  testWidgets('review resolves the original account only after selection', (
    tester,
  ) async {
    final service = _Service();
    final client = _Client();
    var resolutions = 0;
    await _launch(
      tester,
      (context) => reviewTerminalWorkspace(
        context,
        service: service,
        workspace: _workspace(),
        resolve: (workspace) {
          resolutions++;
          expect(workspace.storage.accountKey, 'original-account');
          return TerminalWorkspaceBinding(
            client: client,
            isCurrent: () => true,
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(resolutions, 0);
    await tester.tap(find.text('Upload selected'));
    await tester.pumpAndSettle();
    expect(resolutions, 1);
    expect(service.uploadedClient, same(client));
    expect(service.uploadedChanges, [same(service.changes.single)]);
    expect(find.text('Uploaded: file.txt'), findsOneWidget);
    expect(find.textContaining('Remote file changed.'), findsOneWidget);
  });

  testWidgets('a missing account keeps reviewed changes local', (tester) async {
    final service = _Service();
    await _launch(
      tester,
      (context) => reviewTerminalWorkspace(
        context,
        service: service,
        workspace: _workspace(),
        resolve: (_) => null,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload selected'));
    await tester.pumpAndSettle();
    expect(service.uploads, 0);
    expect(
      find.text('Reconnect the original cloud account to upload.'),
      findsOneWidget,
    );
  });
}
