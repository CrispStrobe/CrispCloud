import 'dart:async';
import 'dart:io';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/ios_terminal_connection.dart';
import 'package:crisp_cloud/services/terminal_connection.dart';
import 'package:crisp_cloud/services/terminal_workspace_service.dart';
import 'package:path/path.dart' as p;

import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/terminal_backends.dart';
import 'package:crisp_cloud/services/terminal_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/workflow_fake_client.dart';

class _ScopedFiles extends Fake
    implements LocalFileService, ScopedLocalFileOperations {
  int leases = 0;
  final active = <String, int>{};
  @override
  Future<T> withFileOperationAccess<T>(
    String path,
    Future<T> Function() action,
  ) async {
    leases++;
    active.update(path, (count) => count + 1, ifAbsent: () => 1);
    try {
      return await action();
    } finally {
      leases--;
      active.update(path, (count) => count - 1);
    }
  }
}

/// Native cleanup can fail independently of output delivery. Keep the read
/// pending until a successful native close, matching the plugin's ownership
/// contract instead of using an already-completed fake exit future.
class _NativeCleanupHarness {
  _NativeCleanupHarness(this.messenger) {
    messenger.setMockMethodCallHandler(channel, _handle);
  }

  static const channel = MethodChannel('crisp_ios_shell/control');
  final TestDefaultBinaryMessenger messenger;
  final calls = <(String, String?)>[];
  final outputs = <String, Completer<Map<String, Object?>>>{};
  final reading = <String, Completer<void>>{};
  final firstClose = Completer<void>();
  Completer<void>? closeGate;
  bool acknowledgeCleanup = false;
  void Function(String)? beforeStart;

  int get starts => outputs.length;
  int get closes => calls.where((call) => call.$1 == 'close').length;

  Future<Object?> _handle(MethodCall call) async {
    final arguments = Map<String, Object?>.from(call.arguments as Map);
    final id = arguments['sessionId'] as String?;
    calls.add((call.method, id));
    switch (call.method) {
      case 'start':
        beforeStart?.call(arguments['workingDirectory'] as String);
        final newId = 'cleanup-review-${outputs.length + 1}';
        outputs[newId] = Completer<Map<String, Object?>>();
        reading[newId] = Completer<void>();
        return {'sessionId': newId};
      case 'read':
        if (!reading[id]!.isCompleted) reading[id]!.complete();
        return outputs[id]!.future;
      case 'close':
        if (!firstClose.isCompleted) firstClose.complete();
        if (!acknowledgeCleanup) {
          throw PlatformException(code: 'cleanup_unconfirmed');
        }
        await closeGate?.future;
        finish(id!);
        return null;
      default:
        return null;
    }
  }

  void finish(String id) {
    final output = outputs[id]!;
    if (!output.isCompleted) {
      output.complete({'data': Uint8List(0), 'exitCode': 0});
    }
  }

  void permitCleanup() {
    acknowledgeCleanup = true;
    if (closeGate != null && !closeGate!.isCompleted) closeGate!.complete();
    for (final id in outputs.keys) {
      finish(id);
    }
  }

  Future<void> dispose() async {
    permitCleanup();
    await Future<void>.delayed(Duration.zero);
    messenger.setMockMethodCallHandler(channel, null);
  }
}

Future<void> _attemptDisconnect(TerminalSession session) async {
  try {
    await session.disconnect().timeout(const Duration(seconds: 3));
  } on PlatformException catch (error) {
    // Both reporting styles keep the same ownership requirement: the UI must
    // retain a retryable failed connection rather than claim disconnection.
    if (error.code != 'cleanup_unconfirmed') rethrow;
  }
}

class _AncestorLinkClient extends WorkflowFakeClient
    with CloudTransferOperations {
  final symbolicDirectories = <String>{};

  @override
  String get transferIdentity => 'review-account';

  @override
  StorageTransferCapabilities get transferCapabilities =>
      const StorageTransferCapabilities(
        caseSensitivity: StorageCaseSensitivity.sensitive,
        nativeMove: true,
        atomicMove: true,
        noReplaceMove: true,
        boundedUpload: true,
        boundedDownload: true,
        symbolicLinks: true,
      );

  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    final listing = await super.listPath(path);
    listing['folders'] = [
      for (final raw in listing['folders'] as List)
        <String, dynamic>{
          ...Map<String, dynamic>.from(raw as Map),
          if (symbolicDirectories.contains(raw['path'])) 'isSymlink': true,
        },
    ];
    return listing;
  }

  @override
  Future<CloudTransferResult> moveToExact(
    String sourcePath,
    String destinationPath, {
    bool replace = false,
    String? expectedSourceVersion,
    String? expectedDestinationVersion,
    TransferCheckpoint? checkpoint,
  }) async {
    await checkpoint?.call();
    if (replace ||
        files.containsKey(destinationPath) ||
        directories.contains(destinationPath)) {
      throw StateError('No-replace destination exists');
    }
    final bytes = files.remove(sourcePath)!;
    modified.remove(sourcePath);
    put(destinationPath, bytes);
    return CloudTransferResult(path: destinationPath, size: bytes.length);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('crisp_ios_shell/control');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test('native terminal disconnect drains a pending read and releases its folder scope', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final output = Completer<Map<String, Object?>>();
    final reading = Completer<void>();
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'start':
          return {'sessionId': 'review-native'};
        case 'read':
          if (!reading.isCompleted) reading.complete();
          return output.future;
        case 'close':
          if (!output.isCompleted) {
            output.complete({'data': Uint8List(0), 'exitCode': 0});
          }
          return null;
        default:
          return null;
      }
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final files = _ScopedFiles();
    final session = TerminalSession();
    addTearDown(session.dispose);
    await session.connect(
      (columns, rows) => openScopedLocalTerminal(
        files,
        '/Documents/project/files',
        columns,
        rows,
      ),
      kind: TerminalSessionKind.ios,
    );
    await reading.future;
    expect(files.leases, 1);
    await session.disconnect().timeout(const Duration(seconds: 3));
    expect(session.status, TerminalSessionStatus.disconnected);
    expect(files.leases, 0);
    expect(calls.where((method) => method == 'close'), hasLength(1));
    await session.disconnect();
    expect(calls.where((method) => method == 'close'), hasLength(1));
  });

  test('unconfirmed native cleanup retains its scope and permits a later close retry', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final native = _NativeCleanupHarness(messenger);
    addTearDown(native.dispose);
    final files = _ScopedFiles();
    final connection = await openScopedLocalTerminal(
      files,
      '/Documents/retry/files',
      80,
      24,
    );
    final output = connection.output.listen((_) {});
    addTearDown(() async {
      native.permitCleanup();
      await connection.close();
      await output.cancel();
    });
    await native.reading['cleanup-review-1']!.future;
    var exitSettled = false;
    unawaited(
      connection.exitCode.then<void>(
        (_) => exitSettled = true,
        onError: (Object _) => exitSettled = true,
      ),
    );

    final first = connection.close();
    final concurrent = connection.close();
    final unconfirmed = throwsA(
      isA<PlatformException>().having(
        (error) => error.code,
        'code',
        'cleanup_unconfirmed',
      ),
    );
    await Future.wait([
      expectLater(first, unconfirmed),
      expectLater(concurrent, unconfirmed),
    ]);
    expect(native.closes, 1);
    expect(exitSettled, isFalse);
    expect(files.leases, 1);
    await connection.write('must not reach a closing command\r');
    await connection.resize(90, 30);
    expect(
      native.calls.where((call) => call.$1 == 'write' || call.$1 == 'resize'),
      isEmpty,
    );

    native.acknowledgeCleanup = true;
    await connection.close().timeout(const Duration(seconds: 3));
    expect(await connection.exitCode, 0);
    expect(files.leases, 0);
    expect(native.closes, 2);
    await connection.close();
    expect(native.closes, 2);
  });

  test('a native read error retains the scope until cleanup acknowledgement succeeds', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final native = _NativeCleanupHarness(messenger);
    addTearDown(native.dispose);
    final files = _ScopedFiles();
    final connection = await openScopedLocalTerminal(
      files,
      '/Documents/read-error/files',
      80,
      24,
    );
    final reported = Completer<Object>();
    final output = connection.output.listen(
      (_) {},
      onError: (Object error) {
        if (!reported.isCompleted) reported.complete(error);
      },
    );
    addTearDown(() async {
      native.permitCleanup();
      await connection.close();
      await output.cancel();
    });
    var exitSettled = false;
    final exited = expectLater(
      connection.exitCode,
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'read_failed',
        ),
      ),
    ).then((_) => exitSettled = true);
    await native.reading['cleanup-review-1']!.future;
    native.outputs['cleanup-review-1']!.completeError(
      PlatformException(code: 'read_failed'),
    );
    expect(await reported.future, isA<PlatformException>());
    expect(exitSettled, isFalse);
    expect(files.leases, 1);
    await expectLater(
      connection.close(),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'cleanup_unconfirmed',
        ),
      ),
    );
    expect(files.leases, 1);

    native.acknowledgeCleanup = true;
    await connection.close().timeout(const Duration(seconds: 3));
    await exited;
    expect(exitSettled, isTrue);
    expect(files.leases, 0);
  });

  test('a failed disconnect retains ownership and blocks opening over the live native command', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final native = _NativeCleanupHarness(messenger);
    addTearDown(native.dispose);
    final files = _ScopedFiles();
    final session = TerminalSession();
    addTearDown(() async {
      native.permitCleanup();
      await session.disconnect();
      session.dispose();
    });
    Future<TerminalConnection> open(int columns, int rows) =>
        openScopedLocalTerminal(files, '/Documents/owned/files', columns, rows);
    await session.connect(open, kind: TerminalSessionKind.ios);
    await native.reading['cleanup-review-1']!.future;

    await _attemptDisconnect(session);
    expect(files.leases, 1);
    expect(session.status, TerminalSessionStatus.failed);
    expect(session.error, isNotNull);
    expect(session.canDisconnect, isTrue);
    try {
      await session.connect(open, kind: TerminalSessionKind.ios);
    } on PlatformException catch (error) {
      if (error.code != 'cleanup_unconfirmed') rethrow;
    }
    expect(native.starts, 1);
    expect(files.leases, 1);
    expect(session.canDisconnect, isTrue);

    native.acknowledgeCleanup = true;
    await session.disconnect().timeout(const Duration(seconds: 3));
    expect(files.leases, 0);
    expect(session.status, TerminalSessionStatus.disconnected);
    expect(session.canDisconnect, isFalse);
  });

  test(
    'a new native open waits for an in-flight close before starting',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final native = _NativeCleanupHarness(messenger)
        ..acknowledgeCleanup = true
        ..closeGate = Completer<void>();
      addTearDown(native.dispose);
      final files = _ScopedFiles();
      final first = await openScopedLocalTerminal(
        files,
        '/Documents/closing/files',
        80,
        24,
      );
      final firstOutput = first.output.listen((_) {});
      Future<IosTerminalConnection>? opening;
      addTearDown(() async {
        native.permitCleanup();
        await first.close();
        await firstOutput.cancel();
        await (await opening)?.close();
      });
      await native.reading['cleanup-review-1']!.future;
      final closing = first.close();
      await native.firstClose.future;
      native.beforeStart = (_) {
        expect(native.outputs['cleanup-review-1']!.isCompleted, isTrue);
      };
      opening = IosTerminalConnection.open('/Documents/next/files', 80, 24);
      await Future<void>.delayed(Duration.zero);
      expect(native.starts, 1);
      expect(files.leases, 1);
      expect(native.closes, 1);

      native.closeGate!.complete();
      await closing.timeout(const Duration(seconds: 3));
      final next = await opening.timeout(const Duration(seconds: 3));
      expect(native.starts, 2);
      expect(files.leases, 0);
      await next.close().timeout(const Duration(seconds: 3));
    },
  );

  test('reopening during disposal waits for native cleanup before the output cancellation completes', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final native = _NativeCleanupHarness(messenger)
      ..acknowledgeCleanup = true
      ..closeGate = Completer<void>();
    addTearDown(native.dispose);
    final files = _ScopedFiles();
    final session = TerminalSession();
    Future<IosTerminalConnection>? opening;
    addTearDown(() async {
      native.permitCleanup();
      await (await opening)?.close();
      session.dispose();
    });
    await session.connect(
      (columns, rows) => openScopedLocalTerminal(
        files,
        '/Documents/disposing/files',
        columns,
        rows,
      ),
      kind: TerminalSessionKind.ios,
    );
    await native.reading['cleanup-review-1']!.future;
    session.dispose();
    await native.firstClose.future;
    opening = IosTerminalConnection.open('/Documents/reopened/files', 80, 24);
    await Future<void>.delayed(Duration.zero);
    expect(native.starts, 1);
    expect(native.closes, 1);
    expect(files.leases, 1);

    native.closeGate!.complete();
    final next = await opening.timeout(const Duration(seconds: 3));
    expect(native.starts, 2);
    expect(files.leases, 0);
    await next.close().timeout(const Duration(seconds: 3));
  });

  test(
    'a new native open retries cleanup left by a disposed terminal owner',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final native = _NativeCleanupHarness(messenger);
      addTearDown(native.dispose);
      final files = _ScopedFiles();
      final session = TerminalSession();
      TerminalConnection? next;
      StreamSubscription<String>? nextOutput;
      addTearDown(() async {
        native.permitCleanup();
        await next?.close();
        await nextOutput?.cancel();
        session.dispose();
      });
      await session.connect(
        (columns, rows) => openScopedLocalTerminal(
          files,
          '/Documents/old/files',
          columns,
          rows,
        ),
        kind: TerminalSessionKind.ios,
      );
      await native.reading['cleanup-review-1']!.future;
      session.dispose();
      // dispose cannot await asynchronous native cleanup. Let its cancellation
      // attempt finish while the command and directory grant remain alive.
      await Future<void>.delayed(Duration.zero);
      expect(native.closes, greaterThan(0));
      expect(files.active['/Documents/old/files'], 1);
      expect(native.outputs['cleanup-review-1']!.isCompleted, isFalse);

      native.acknowledgeCleanup = true;
      native.beforeStart = (_) {
        expect(native.outputs['cleanup-review-1']!.isCompleted, isTrue);
      };
      next = await openScopedLocalTerminal(
        files,
        '/Documents/new/files',
        80,
        24,
        opener: IosTerminalConnection.open,
      ).timeout(const Duration(seconds: 3));
      nextOutput = next.output.listen((_) {});
      await native.reading['cleanup-review-2']!.future;
      expect(files.active['/Documents/old/files'], 0);
      expect(files.active['/Documents/new/files'], 1);
      await next.close().timeout(const Duration(seconds: 3));
      expect(files.leases, 0);
    },
  );

  test(
    'new nested upload rejects every remote symlink ancestor before writing',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'workspace-review-ancestor-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final service = TerminalWorkspaceService(
        rootDirectory: p.join(temp.path, 'workspaces'),
      );
      final cloud = _AncestorLinkClient()..put('/cloud/seed.txt', [1]);
      final workspace = await service.stage(
        client: cloud,
        remoteRoot: '/cloud',
        items: [
          FileItem(
            name: 'seed.txt',
            path: '/cloud/seed.txt',
            isFolder: false,
            size: 1,
          ),
        ],
        isCurrent: () => true,
      );
      // This remote ancestor was not part of the original staged selection.
      // Its ordinary-looking child is reached by following the symlink.
      cloud.directories.addAll(['/cloud/linked', '/cloud/linked/sub']);
      cloud.symbolicDirectories.add('/cloud/linked');
      final added = File(
        p.join(workspace.directoryPath, 'linked', 'sub', 'new.txt'),
      );
      await added.parent.create(recursive: true);
      await added.writeAsBytes([2, 3]);
      final review = (await service.inspect(workspace.id))
          .where((change) => change.relativePath == 'linked/sub/new.txt')
          .toList();
      final result = await service.uploadReviewed(
        workspaceId: workspace.id,
        client: cloud,
        changes: review,
        isCurrent: () => true,
      );
      expect(
        result.failures['linked/sub/new.txt'],
        contains('parent is not a regular directory'),
      );
      expect(cloud.writes, isEmpty);
      expect(cloud.files.containsKey('/cloud/linked/sub/new.txt'), isFalse);
    },
  );
}
