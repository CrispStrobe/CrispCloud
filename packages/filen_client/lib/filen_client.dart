/// FilenClient: Facade that composes all modules into a single API surface.
///
/// This is also the barrel file — import this to get access to all modules.
library filen_dart;

import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:filen_client/api.dart';
import 'package:filen_client/auth.dart';
import 'package:filen_client/cache.dart';
import 'package:filen_client/config.dart';
import 'package:filen_client/crypto.dart';
import 'package:filen_client/download.dart';
import 'package:filen_client/drive.dart';
import 'package:filen_client/memory_gate.dart';
import 'package:filen_client/upload.dart';
import 'package:filen_client/utils.dart' as utils_lib;

export 'package:filen_client/api.dart';
export 'package:filen_client/auth.dart';
export 'package:filen_client/cache.dart';
export 'package:filen_client/config.dart';
export 'package:filen_client/config_storage.dart';
export 'package:filen_client/crypto.dart';
export 'package:filen_client/download.dart';
export 'package:filen_client/drive.dart';
export 'package:filen_client/upload.dart';
export 'package:filen_client/utils.dart';
export 'package:filen_client/memory_gate.dart';
export 'package:filen_client/paths.dart';

class FilenClient {
  static const apiUrl = 'https://gateway.filen.io';

  final FilenApi api;
  final FilenCrypto crypto;
  final FilenCache cache;
  late final FilenAuth auth;
  late final FilenDrive drive;
  late final FilenUpload uploader;
  late final FilenDownload downloader;
  final ConfigService config;

  bool get debugMode => api.debugMode;
  set debugMode(bool v) => api.debugMode = v;

  String get baseFolderUUID => drive.baseFolderUUID;
  set baseFolderUUID(String v) => drive.baseFolderUUID = v;

  String? get apiKey => api.apiKey;
  set apiKey(String? v) => api.apiKey = v;

  List<String> get masterKeys => drive.masterKeys;
  set masterKeys(List<String> v) => drive.masterKeys = v;

  String? get email => drive.email;

  FilenClient({
    required this.config,
    http.Client? httpClient,
  })  : api = FilenApi(client: httpClient),
        crypto = FilenCrypto(),
        cache = FilenCache() {
    auth = FilenAuth(api: api, crypto: crypto);
    drive = FilenDrive(api: api, crypto: crypto, cache: cache);
    uploader =
        FilenUpload(api: api, crypto: crypto, cache: cache, drive: drive);
    downloader =
        FilenDownload(api: api, crypto: crypto, cache: cache, drive: drive);
  }

  void setAuth(Map<String, dynamic> c) {
    api.apiKey = c['apiKey'] ?? '';
    drive.baseFolderUUID = c['baseFolderUUID'] ?? '';
    drive.masterKeys = (c['masterKeys'] ?? '')
        .toString()
        .split('|')
        .where((k) => k.isNotEmpty)
        .toList();
    drive.email = c['email'] ?? '';
  }

  // --- Delegate methods for backward compatibility ---

  Future<Map<String, dynamic>> login(String email, String password,
          {String twoFactorCode = "XXXXXX"}) =>
      auth.login(email, password, twoFactorCode: twoFactorCode);

  Future<String> fetchBaseFolderUUID() => auth.fetchBaseFolderUUID();

  Future<Map<String, dynamic>> resolvePath(String path) =>
      drive.resolvePath(path);

  Future<Map<String, dynamic>> createFolderRecursive(String path,
          {String? creationTime, String? modificationTime}) =>
      drive.createFolderRecursive(path,
          creationTime: creationTime, modificationTime: modificationTime);

  Future<List<Map<String, dynamic>>> listFoldersAsync(String uuid,
          {bool detailed = false}) =>
      cache.listFoldersAsync(uuid,
          detailed: detailed,
          api: api,
          crypto: crypto,
          masterKeys: drive.masterKeys);

  Future<List<Map<String, dynamic>>> listFolderFiles(String uuid,
          {bool detailed = false}) =>
      cache.listFolderFiles(uuid,
          detailed: detailed,
          api: api,
          crypto: crypto,
          masterKeys: drive.masterKeys);

  Future<void> moveItem(String uuid, String destUuid, String type) =>
      drive.moveItem(uuid, destUuid, type);

  Future<void> trashItem(String uuid, String type) =>
      drive.trashItem(uuid, type);

  Future<void> restoreItem(String uuid, String type) =>
      drive.restoreItem(uuid, type);

  Future<void> deletePermanently(String uuid, String type) =>
      drive.deletePermanently(uuid, type);

  Future<void> renameItem(String uuid, String newName, String type) =>
      drive.renameItem(uuid, newName, type);

  Future<Map<String, dynamic>> getFileMetadata(String uuid) =>
      drive.getFileMetadata(uuid);

  Future<Map<String, dynamic>> getFolderMetadata(String uuid) =>
      drive.getFolderMetadata(uuid);

  Future<bool> checkFileExists(String parentUuid, String name) =>
      drive.checkFileExists(parentUuid, name);

  Future<List<Map<String, dynamic>>> getTrashContent() =>
      drive.getTrashContent();

  Future<Map<String, List<Map<String, dynamic>>>> search(String query,
          {bool detailed = false}) =>
      drive.search(query, detailed: detailed);

  Future<List<Map<String, dynamic>>> findFiles(String startPath, String pattern,
          {int maxDepth = -1}) =>
      drive.findFiles(startPath, pattern, maxDepth: maxDepth);

  Future<void> printTree(String path, void Function(String) printLine,
          {int maxDepth = 3}) =>
      drive.printTree(path, printLine, maxDepth: maxDepth);

  Future<bool> verifyUploadMetadata(String fileUuid, File originalFile) =>
      drive.verifyUploadMetadata(fileUuid, originalFile);

  Future<Map<String, String>> uploadFileChunked(
    File file,
    String parent, {
    String? fileUuid,
    String? creationTime,
    String? modificationTime,
    String? resumeUploadKey,
    int resumeFromChunk = 0,
    Set<int>? completedChunks,
    String? fileKey,
    int maxConcurrentChunks = kDefaultUploadConcurrency,
    Function(int, int, int, int)? onProgress,
    Function(String, String, String)? onUploadStart,
    void Function(Set<int>)? onChunksCompleted,
  }) =>
      uploader.uploadFileChunked(file, parent,
          fileUuid: fileUuid,
          creationTime: creationTime,
          modificationTime: modificationTime,
          resumeUploadKey: resumeUploadKey,
          resumeFromChunk: resumeFromChunk,
          completedChunks: completedChunks,
          fileKey: fileKey,
          maxConcurrentChunks: maxConcurrentChunks,
          onProgress: onProgress,
          onUploadStart: onUploadStart,
          onChunksCompleted: onChunksCompleted);

  Future<void> uploadFile(File file, String parent,
          {String? creationTime, String? modificationTime}) =>
      uploader.uploadFile(file, parent,
          creationTime: creationTime, modificationTime: modificationTime);

  Future<void> uploadBytes(Uint8List data, String fileName, String parentUuid,
          {int maxConcurrentChunks = kDefaultUploadConcurrency,
          Function(int, int)? onProgress}) =>
      uploader.uploadBytes(data, fileName, parentUuid,
          maxConcurrentChunks: maxConcurrentChunks, onProgress: onProgress);

  Future<void> upload(
    List<String> sources,
    String targetPath, {
    required bool recursive,
    required String onConflict,
    required bool preserveTimestamps,
    required List<String> include,
    required List<String> exclude,
    required String batchId,
    Map<String, dynamic>? initialBatchState,
    required Future<void> Function(Map<String, dynamic>) saveStateCallback,
    Function(String, int, int, int, int)? onFileProgress,
    int maxWorkers = kDefaultFileConcurrency,
  }) =>
      uploader.upload(sources, targetPath,
          recursive: recursive,
          onConflict: onConflict,
          preserveTimestamps: preserveTimestamps,
          include: include,
          exclude: exclude,
          batchId: batchId,
          initialBatchState: initialBatchState,
          saveStateCallback: saveStateCallback,
          onFileProgress: onFileProgress,
          maxWorkers: maxWorkers);

  Future<Uint8List> downloadFileBytes(String uuid,
          {int maxConcurrentChunks = kDefaultDownloadConcurrency,
          Function(int, int)? onProgress}) =>
      downloader.downloadFileBytes(uuid,
          maxConcurrentChunks: maxConcurrentChunks, onProgress: onProgress);

  Future<Map<String, dynamic>> downloadFile(String uuid,
          {String? savePath,
          int maxConcurrentChunks = kDefaultDownloadConcurrency,
          Function(int, int)? onProgress}) =>
      downloader.downloadFile(uuid,
          savePath: savePath,
          maxConcurrentChunks: maxConcurrentChunks,
          onProgress: onProgress);

  Future<void> downloadPath(
    String remotePath, {
    String? localDestination,
    required bool recursive,
    required String onConflict,
    required bool preserveTimestamps,
    required List<String> include,
    required List<String> exclude,
    required String batchId,
    Map<String, dynamic>? initialBatchState,
    required Future<void> Function(Map<String, dynamic>) saveStateCallback,
    int maxWorkers = kDefaultFileConcurrency,
  }) =>
      downloader.downloadPath(remotePath,
          localDestination: localDestination,
          recursive: recursive,
          onConflict: onConflict,
          preserveTimestamps: preserveTimestamps,
          include: include,
          exclude: exclude,
          batchId: batchId,
          initialBatchState: initialBatchState,
          saveStateCallback: saveStateCallback,
          maxWorkers: maxWorkers);

  void log(String msg) => api.log(msg);
  void logWebDAV(String msg) => api.logWebDAV(msg);

  bool shouldIncludeFile(
          String fileName, List<String> include, List<String> exclude) =>
      utils_lib.shouldIncludeFile(fileName, include, exclude);
}
