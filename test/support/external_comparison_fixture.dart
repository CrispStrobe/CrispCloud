import 'dart:async';
import 'dart:convert';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/command_entry_service.dart';
import 'package:crisp_cloud/services/external_comparison_service.dart';
import 'package:crisp_cloud/services/private_tool_staging.dart';
import 'package:crypto/crypto.dart';

import 'gathering_stack_fixture.dart';

class ComparisonBackend extends GatheringMemoryBackend {
  ComparisonBackend(super.reference);
  Future<void> Function(String)? beforeStat;
  Stream<List<int>> Function(FileItem)? read;
  @override
  Future<FileItem?> stat(String path) async {
    await beforeStat?.call(path);
    return super.stat(path);
  }

  @override
  Stream<List<int>> readFile(FileItem file) =>
      read?.call(file) ?? super.readFile(file);
}

class ComparisonHost implements ExternalComparisonHost {
  @override
  String? platform = 'linux';
  CommandEntryFileIdentity? identity = CommandEntryFileIdentity(
    resolvedPath: '/apps/compare tool',
    isDirectory: false,
    size: 99,
    modified: DateTime.utc(2026, 1, 1),
    changed: DateTime.utc(2026, 1, 1),
    mode: 0x1ed,
  );
  Future<void> Function()? beforeInspect;
  Future<void> Function()? beforeLaunch;
  Object? launchError;
  final launches =
      <({String executable, List<String> arguments, String directory})>[];
  @override
  Future<CommandEntryFileIdentity?> inspectExecutable(String path) async {
    await beforeInspect?.call();
    return identity;
  }

  @override
  Future<void> launch(
    String executable,
    List<String> arguments,
    String directory,
  ) async {
    launches.add((
      executable: executable,
      arguments: arguments,
      directory: directory,
    ));
    await beforeLaunch?.call();
    if (launchError case final error?) throw error;
  }
}

class ComparisonMemoryStages implements PrivateToolStagingStore {
  final entries = <String, ComparisonMemoryStage>{};
  var next = 0;
  bool failManifest = false, failDelete = false;
  Future<void> Function(Map<String, dynamic>)? beforeManifest;
  Future<void> Function(String)? beforeInspect;
  Future<void> Function()? beforeDelete;
  @override
  Future<List<String>> list(String kind) async => entries.keys.toList();
  @override
  Future<PrivateToolStage> create({required String kind, String? id}) async {
    final stage = ComparisonMemoryStage(this, id ?? 'session-${++next}', kind);
    entries[stage.id] = stage;
    return stage;
  }

  @override
  Future<PrivateToolStage> open({
    required String kind,
    required String id,
  }) async {
    final stage = entries[id]!;
    stage.closed = false;
    return stage;
  }
}

class ComparisonMemoryStage implements PrivateToolStage {
  ComparisonMemoryStage(this.owner, this.id, this.kind);
  final ComparisonMemoryStages owner;
  @override
  final String id, kind;
  bool closed = false;
  final files = <String, List<int>>{};
  Map<String, dynamic>? manifest;
  @override
  String get directoryPath => '/private/café comparison/$id';
  PrivateStagedFile _file(String name) => PrivateStagedFile(
    name: name,
    path: '$directoryPath/$name',
    length: files[name]!.length,
    sha256: sha256.convert(files[name]!).toString(),
  );
  @override
  Future<PrivateStagedFile> write(
    String name,
    Stream<List<int>> source, {
    required int maxBytes,
    int? expectedLength,
    PrivateStageCheckpoint? checkpoint,
  }) async {
    final bytes = <int>[];
    if (files.containsKey(name)) throw StateError('Already exists');
    await checkpoint?.call();
    await for (final chunk in source) {
      await checkpoint?.call();
      bytes.addAll(chunk);
      if (bytes.length > maxBytes) {
        throw const PrivateStageException(PrivateStageFailure.tooLarge);
      }
    }
    await checkpoint?.call();
    if (expectedLength != null && bytes.length != expectedLength) {
      throw StateError('Length changed');
    }
    files[name] = bytes;
    return _file(name);
  }

  @override
  Future<PrivateStagedFile> inspect(
    String name, {
    required int maxBytes,
    PrivateStageCheckpoint? checkpoint,
  }) async {
    await owner.beforeInspect?.call(name);
    await checkpoint?.call();
    if (files[name]!.length > maxBytes) {
      throw const PrivateStageException(PrivateStageFailure.tooLarge);
    }
    return _file(name);
  }

  @override
  Stream<List<int>> openRead(
    PrivateStagedFile expected, {
    PrivateStageCheckpoint? checkpoint,
  }) async* {
    await checkpoint?.call();
    yield files[expected.name]!;
  }

  @override
  Future<PrivateStagedFile> snapshot(
    String name,
    String snapshotName, {
    required int maxBytes,
    PrivateStageCheckpoint? checkpoint,
  }) => write(
    snapshotName,
    Stream.value(files[name]!),
    maxBytes: maxBytes,
    checkpoint: checkpoint,
  );
  @override
  Stream<void> watch(String name) => const Stream.empty();
  @override
  Future<void> deleteFile(String name) async {
    files.remove(name);
  }

  @override
  Future<Map<String, dynamic>?> readManifest() async => manifest;
  @override
  Future<void> writeManifest(Map<String, dynamic> value) async {
    await owner.beforeManifest?.call(value);
    if (owner.failManifest) throw StateError('Disk full');
    manifest = Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
  }

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  Future<void> delete() async {
    await owner.beforeDelete?.call();
    if (owner.failDelete) throw StateError('Cannot remove');
    files.clear();
    owner.entries.remove(id);
    closed = true;
  }
}

ExternalComparisonConfiguration comparisonConfiguration({
  ExternalComparisonKind kind = ExternalComparisonKind.text,
  List<String> arguments = const ['--', '{left}', '{right}'],
}) => ExternalComparisonConfiguration(
  platform: 'linux',
  kind: kind,
  executable: '/apps/compare tool',
  arguments: arguments,
);

ExternalComparisonPair comparisonPair(
  ComparisonBackend left,
  ComparisonBackend right, {
  String leftPath = '/same/name.txt',
  String rightPath = '/same/name.txt',
  bool Function()? isCurrent,
}) => ExternalComparisonPair(
  left: ExternalComparisonInput(
    backend: left,
    file: left.items[leftPath]!,
    isCurrent: isCurrent ?? () => true,
  ),
  right: ExternalComparisonInput(
    backend: right,
    file: right.items[rightPath]!,
    isCurrent: isCurrent ?? () => true,
  ),
);
