import 'dart:async';
import 'dart:io';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/services/storage_identity.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/workflow_fake_client.dart';

class _Auth extends ChangeNotifier implements AuthNotifier {
  @override
  final client = WorkflowFakeClient()..current = false;
  @override
  bool get isConnected => false;
  @override
  String? get userEmail => null;
  @override
  String get providerName => client.providerName;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Uses opaque browser-style grant tokens with real entities for the native
/// metadata pass. The namespace listing is explicit and never reads OS '/'.
class _GrantedFiles extends Fake
    implements LocalFileService, LocalFileSourceIdentity {
  _GrantedFiles(this.first, this.second) : currentPath = first {
    tokens[first] = Object();
    tokens[second] = Object();
  }

  final String first;
  final String second;
  final tokens = <String, Object>{};
  final reads = <String>[];
  int accessRequests = 0;
  String? blockedPath;
  Completer<void>? readGate;
  Completer<void>? readStarted;

  @override
  String currentPath;
  @override
  String? get grantedBasePath => null;
  @override
  Future<String> getInitialPath() async => first;
  @override
  Future<String> getSafeFallbackDirectory() async => first;
  @override
  Future<void> refresh() async {}
  @override
  Object? sourceIdentityForPath(String path) {
    final normalized = p.normalize(path);
    for (final entry in tokens.entries) {
      if (normalized == entry.key || p.isWithin(entry.key, normalized)) {
        return entry.value;
      }
    }
    return null;
  }

  @override
  Future<bool> hasAccessToPath(String path) async =>
      path == '/' || sourceIdentityForPath(path) != null;

  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async {
    reads.add(path);
    final gate = path == blockedPath ? readGate : null;
    if (gate != null) {
      if (!(readStarted?.isCompleted ?? true)) readStarted!.complete();
      await gate.future;
    }
    currentPath = path;
    if (path == '/') return [Directory(first), Directory(second)];
    return Directory(path).list(followLinks: false).toList();
  }

  @override
  Future<bool> ensureAccess(String path) async {
    accessRequests++;
    throw StateError('An existing grant must not request another grant.');
  }

  void block(String path) {
    blockedPath = path;
    readGate = Completer<void>();
    readStarted = Completer<void>();
  }

  void releaseRead() {
    final gate = readGate;
    blockedPath = null;
    readGate = null;
    if (gate != null && !gate.isCompleted) gate.complete();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late _GrantedFiles local;
  late ProviderContainer container;
  late PanelNotifier panel;

  FileItem row(String path) =>
      panel.files!.singleWhere((file) => file.path == path);

  Future<void> navigateFresh(String path) async {
    final origin = panel.resolveStorageReference(
      storageReferenceForSource(LocalPanelSource(path)),
      path,
    );
    expect(origin, isNotNull);
    await panel.navigateToPath(path, origin: origin!);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temporary = await Directory.systemTemp.createTemp('local-grant-origin-');
    final first = p.join(temporary.path, 'First');
    final second = p.join(temporary.path, 'Second');
    await Directory(p.join(first, 'child')).create(recursive: true);
    await Directory(second).create();
    await File(p.join(first, 'first.txt')).writeAsString('first');
    await File(p.join(second, 'second.txt')).writeAsString('second');
    local = _GrantedFiles(first, second);
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => _Auth()),
        localFileServiceProvider.overrideWithValue(local),
      ],
    );
    panel = container.read(panelProvider(PanelSide.local));
    await Future<void>.delayed(Duration.zero);
    await navigateFresh(first);
  });

  tearDown(() async {
    local.releaseRead();
    container.dispose();
    await Future<void>.delayed(Duration.zero);
    await temporary.delete(recursive: true);
  });

  test(
    'a same-path regrant during a read cannot publish a verified listing',
    () async {
      final previous = row(p.join(local.first, 'first.txt'));
      final previousOrigin = panel.originForOperation(previous)!;
      local.block(local.first);
      final refresh = panel.refresh();
      await local.readStarted!.future;
      local.tokens[local.first] = Object();
      expect(previousOrigin.isCurrent, isFalse);
      local.releaseRead();
      await refresh;

      expect(panel.currentPath, local.first);
      expect(panel.isLoading, isFalse);
      expect(panel.hasVerifiedDirectoryListing, isFalse);
      expect(panel.captureCurrentOrigin, throwsStateError);
      expect(panel.originForOperation(previous), isNull);
      for (final file in panel.files ?? <FileItem>[]) {
        expect(panel.originForOperation(file), isNull);
      }
      expect(local.accessRequests, 0);

      // A new explicit refresh captures the replacement token and can publish.
      await panel.refresh();
      final refreshed = row(p.join(local.first, 'first.txt'));
      expect(panel.isLoading, isFalse);
      expect(panel.hasVerifiedDirectoryListing, isTrue);
      expect(panel.captureCurrentOrigin().isCurrent, isTrue);
      expect(panel.originForOperation(refreshed)?.isCurrent, isTrue);
      expect(previousOrigin.isCurrent, isFalse);
      expect(local.accessRequests, 0);
    },
  );

  test(
    'namespace rows bind distinct grants without invalidating unrelated rows',
    () async {
      await navigateFresh('/');
      final first = row(local.first);
      final second = row(local.second);
      final firstOrigin = panel.originForOperation(first)!;
      final secondOrigin = panel.originForOperation(second)!;
      final namespace = panel.captureCurrentOrigin();
      expect(firstOrigin.isCurrent, isTrue);
      expect(secondOrigin.isCurrent, isTrue);

      local.tokens[local.first] = Object();
      expect(firstOrigin.isCurrent, isFalse);
      expect(secondOrigin.isCurrent, isTrue);
      expect(namespace.isCurrent, isTrue);
      expect(panel.originForOperation(first), isNull);
      expect(panel.originForOperation(second)?.isCurrent, isTrue);
      expect(
        () => panel.captureOperationGroups([first, second]),
        throwsStateError,
      );
      expect(panel.captureOperationGroups([second]).values.single, [second]);
      expect(local.accessRequests, 0);
    },
  );

  test(
    'captured source availability survives ordinary pane navigation',
    () async {
      final file = row(p.join(local.first, 'first.txt'));
      final captured = panel.captureOperationOrigin([file]);
      await panel.navigateToPath(p.join(local.first, 'child'));
      expect(panel.currentPath, p.join(local.first, 'child'));
      expect(panel.originForOperation(file), isNull);
      expect(captured.isCurrent, isTrue);

      local.tokens[local.first] = Object();
      expect(captured.isCurrent, isFalse);
      expect(panel.captureCurrentOrigin, throwsStateError);
      expect(local.accessRequests, 0);
    },
  );

  test(
    'a new grant listing does not inherit the prior grant lifetime',
    () async {
      final original = panel.captureCurrentOrigin();
      await navigateFresh(local.second);
      final current = panel.captureCurrentOrigin();
      final file = row(p.join(local.second, 'second.txt'));

      local.tokens[local.first] = Object();
      expect(original.isCurrent, isFalse);
      expect(current.isCurrent, isTrue);
      expect(panel.originForOperation(file)?.isCurrent, isTrue);
      expect(panel.hasVerifiedDirectoryListing, isTrue);

      local.tokens[local.second] = Object();
      expect(current.isCurrent, isFalse);
      expect(panel.originForOperation(file), isNull);
      expect(local.accessRequests, 0);
    },
  );
}
