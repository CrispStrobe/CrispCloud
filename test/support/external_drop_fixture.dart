import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/external_drop_source.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:flutter_test/flutter_test.dart';

import 'workflow_fake_client.dart';

class DropTestFile extends DropItemFile {
  DropTestFile(this.browserName, this.data, {this.declaredLength})
    : super('browser-handle', name: browserName);
  final String browserName;
  @override
  String get name => browserName;
  final List<int> data;
  final int? declaredLength;
  Completer<int>? pendingLength;
  final lengthStarted = Completer<void>();
  bool lengthRequested = false;
  int byteReads = 0, streamReads = 0;
  @override
  Future<int> length() async {
    lengthRequested = true;
    if (!lengthStarted.isCompleted) lengthStarted.complete();
    return await pendingLength?.future ?? declaredLength ?? data.length;
  }

  @override
  Future<DateTime> lastModified() async => DateTime.utc(2026, 1, 1);
  @override
  Future<Uint8List> readAsBytes() async {
    byteReads++;
    throw StateError('Whole-file buffering is not a supported drop read.');
  }

  @override
  Stream<Uint8List> openRead([int? start, int? end]) async* {
    streamReads++;
    yield Uint8List.fromList(data.sublist(start ?? 0, end ?? data.length));
  }
}

class DropTestDirectory extends DropItemDirectory {
  DropTestDirectory(this.browserName, List<DropItem> children)
    : super('browser-directory-handle', children, name: browserName);
  final String browserName;
  @override
  String get name => browserName;
}

class RecordingDropAccess implements ExternalDropAccess {
  final started = <List<int>>[];
  final stopped = <List<int>>[];
  int? denyStart;
  @override
  Future<bool> start(Uint8List bookmark) async {
    started.add(List.of(bookmark));
    return started.length != denyStart;
  }

  @override
  Future<bool> stop(Uint8List bookmark) async {
    stopped.add(List.of(bookmark));
    return true;
  }
}

class DropTestCloud extends WorkflowFakeClient {
  DropTestCloud(this.account);
  String account;
  final listed = <String>[];
  Future<void> Function(String)? beforeList;
  @override
  String get providerName => 'Drop fixture';
  @override
  String get userId => account;
  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    listed.add(path);
    await beforeList?.call(path);
    return super.listPath(path);
  }
}

class DropTestAuth extends ChangeNotifier implements AuthNotifier {
  DropTestAuth(this.client);
  @override
  final DropTestCloud client;
  @override
  bool get isConnected => client.current;
  @override
  String? userEmail = 'fixture@example.test';
  @override
  String get providerName => client.providerName;
  void connection(bool connected) {
    client.current = connected;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class DropTestLocal extends Fake
    implements
        LocalFileService,
        LocalDirectorySnapshotReader,
        ScopedLocalFileOperations {
  DropTestLocal(this.currentPath);
  @override
  String currentPath;
  @override
  String get grantedBasePath => currentPath;
  final snapshots = <String>[];
  Future<void> Function(String)? beforeSnapshot;
  @override
  Future<String> getInitialPath() async => currentPath;
  @override
  Future<String> getSafeFallbackDirectory() async => currentPath;
  @override
  Future<bool> hasAccessToPath(String path) async => true;
  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async =>
      Directory(path).list(followLinks: false).toList();
  @override
  Future<List<FileSystemEntity>?> listDirectorySnapshot(String path) async {
    snapshots.add(path);
    await beforeSnapshot?.call(path);
    return Directory(path).list(followLinks: false).toList();
  }

  @override
  Future<T> withFileOperationAccess<T>(
    String path,
    Future<T> Function() action,
  ) => action();
  @override
  Future<void> refresh() async {}
}
