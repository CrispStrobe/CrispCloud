// Native (dart:io + FFI) binding of [RustCloudApi] to the generated
// flutter_rust_bridge API in `rust_cloud/`.
import 'dart:convert';
import 'dart:io' show Directory, Platform;

import 'package:flutter_rust_bridge/flutter_rust_bridge.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;

import 'cloud_engine.dart';
import 'rust_cloud/api.dart' as native;
import 'rust_cloud/frb_generated.dart';
import 'rust_library.dart';

const _definedLibrary = String.fromEnvironment('CRISP_CLOUD_LIBRARY');

class NativeRustCloudApi implements RustCloudApi {
  NativeRustCloudApi._();
  static final NativeRustCloudApi instance = NativeRustCloudApi._();

  static Future<void>? _initializing;

  /// Load the native library once. Any failure (missing library, symbol or
  /// content-hash mismatch) becomes [RustCloudUnavailable] before a session,
  /// credential or network request exists. A failed load is not retried in
  /// this process: switching engines must happen before sign-in.
  @override
  Future<void> initialize() => _initializing ??= (() async {
    try {
      // Same order as the SMB bridge: explicit path (define/environment),
      // a library bundled by the build hook (`rust_cloud: true`), then FRB's
      // default developer location (rust_cloud/target/release).
      final explicit = _definedLibrary.isNotEmpty
          ? _definedLibrary
          : Platform.environment['CRISP_CLOUD_LIBRARY'];
      ExternalLibrary? library;
      if (explicit != null && explicit.isNotEmpty) {
        library = ExternalLibrary.open(explicit);
      } else {
        for (final candidate in bundledRustLibraryCandidates(
          os: Platform.operatingSystem,
          executable: Platform.resolvedExecutable,
          workingDirectory: Directory.current.path,
          stem: cloudBridgeStem,
        )) {
          try {
            library = ExternalLibrary.open(candidate);
            break;
          } catch (_) {
            continue;
          }
        }
      }
      await CloudRustLib.init(externalLibrary: library);
      final info = jsonDecode(native.cloudBridgeInfo()) as Map;
      if (info['session_version'] != RustCloudSessionEnvelope.version) {
        throw const RustCloudUnavailable('session format mismatch');
      }
    } on RustCloudUnavailable {
      rethrow;
    } catch (_) {
      throw const RustCloudUnavailable();
    }
  })();

  static T _sync<T>(T Function() action) {
    try {
      return action();
    } on AnyhowException catch (e) {
      throw RustCloudException.fromNative(e.message);
    } on FrbException {
      throw const RustCloudException(RustCloudErrorCode.internal);
    }
  }

  static Future<T> _async<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AnyhowException catch (e) {
      throw RustCloudException.fromNative(e.message);
    } on FrbException {
      throw const RustCloudException(RustCloudErrorCode.internal);
    }
  }

  @override
  Future<String> login(
    RustCloudProvider provider,
    String email,
    String password,
    String? twoFactorCode,
  ) => _async(
    () => native.cloudLogin(
      provider: provider.name,
      email: email,
      password: password,
      twoFactorCode: twoFactorCode,
    ),
  );

  @override
  Future<int> open(RustCloudProvider provider, String envelope) => _async(
    () => native.cloudOpenSession(provider: provider.name, sessionJson: envelope),
  );

  @override
  Map<String, dynamic> info(int session) => _sync(
    () => Map<String, dynamic>.from(
      jsonDecode(native.cloudSessionInfo(id: session)) as Map,
    ),
  );

  @override
  int revision(int session) =>
      _sync(() => native.cloudSessionRevision(id: session));

  @override
  Future<String> export(int session) =>
      _async(() => native.cloudExportSession(id: session));

  @override
  Future<String> list(int session, String path, bool fresh) =>
      _async(() => native.cloudList(id: session, path: path, fresh: fresh));

  @override
  Future<String> stat(int session, String path) =>
      _async(() => native.cloudStat(id: session, path: path));

  @override
  Future<String> mkdir(int session, String path) =>
      _async(() => native.cloudMkdir(id: session, path: path));

  @override
  Future<void> rename(int session, String path, String newName) => _async(
    () => native.cloudRename(id: session, path: path, newName: newName),
  );

  @override
  Future<void> move(int session, String path, String targetFolder) => _async(
    () =>
        native.cloudMove(id: session, path: path, targetFolder: targetFolder),
  );

  @override
  Future<void> trash(int session, String path) =>
      _async(() => native.cloudTrash(id: session, path: path));

  @override
  Future<int> upload(
    int session,
    int transfer,
    String localPath,
    String targetFolder,
    String name,
  ) => _async(
    () => native.cloudUpload(
      id: session,
      transfer: transfer,
      localPath: localPath,
      targetFolder: targetFolder,
      name: name,
    ),
  );

  @override
  Future<int> download(
    int session,
    int transfer,
    String remotePath,
    String localPath,
  ) => _async(
    () => native.cloudDownload(
      id: session,
      transfer: transfer,
      remotePath: remotePath,
      localPath: localPath,
    ),
  );

  @override
  int newTransfer() => _sync(native.cloudNewTransfer);

  @override
  List<int> progress(int transfer) =>
      _sync(() => List<int>.of(native.cloudTransferProgress(transfer: transfer)));

  @override
  void cancel(int transfer) =>
      _sync(() => native.cloudCancelTransfer(transfer: transfer));

  @override
  void release(int transfer) =>
      _sync(() => native.cloudReleaseTransfer(transfer: transfer));

  @override
  void close(int session) => _sync(() => native.cloudCloseSession(id: session));
}

RustCloudApi defaultRustCloudApi() => NativeRustCloudApi.instance;
