// lib/services/internxt_client_extensions.dart
import 'internxt_client.dart';
import 'dart:io';
import 'dart:typed_data';

extension InternxtClientExtensions on InternxtClient {
  Future<Map<String, dynamic>> listPath(String path) async {
    final resolved = await resolvePath(path);
    // resolvePath might throw if disabled, or return map if enabled
    if (resolved['type'] != 'folder') {
      throw Exception('Path is not a folder: $path');
    }
    
    final folderId = resolved['uuid'];
    final folders = await listFolders(folderId, detailed: true);
    final files = await listFolderFiles(folderId, detailed: true);
    
    return {
      'folders': folders,
      'files': files,
    };
  }

  Future<void> uploadFile(
    List<int> fileData,
    String fileName,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    final tempDir = Directory.systemTemp;
    final tempFile = File('${tempDir.path}/$fileName');
    await tempFile.writeAsBytes(fileData);
    
    try {
      // FIX: Access fields directly
      if (this.userId == null || this.bucketId == null) {
        throw Exception('Not authenticated');
      }
      
      final batchId = 'upload_${DateTime.now().millisecondsSinceEpoch}';
      
      await upload(
        [tempFile.path],
        targetPath,
        recursive: false,
        onConflict: 'skip',
        preserveTimestamps: false,
        include: [],
        exclude: [],
        bridgeUser: this.bucketId!,
        userIdForAuth: this.userId!,
        batchId: batchId,
        saveStateCallback: (state) async {},
      );
    } finally {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  Future<void> downloadFileByPath(
    String remotePath,
    String localPath, {
    Function(int, int)? onProgress,
  }) async {
    final resolved = await resolvePath(remotePath);
    
    if (resolved['type'] != 'file') {
      throw Exception('Path is not a file: $remotePath');
    }
    
    // FIX: Access fields directly
    if (this.userId == null || this.bucketId == null) {
      throw Exception('Not authenticated');
    }
    
    final localDir = File(localPath).parent.path;
    final batchId = 'download_${DateTime.now().millisecondsSinceEpoch}';
    
    await downloadPath(
      remotePath,
      localDestination: localDir,
      recursive: false,
      onConflict: 'skip',
      preserveTimestamps: false,
      include: [],
      exclude: [],
      bridgeUser: this.bucketId!,
      userIdForAuth: this.userId!,
      batchId: batchId,
      saveStateCallback: (state) async {},
    );
    
    final expectedPath = '$localDir/${resolved['name']}';
    if (expectedPath != localPath && File(expectedPath).existsSync()) {
      try {
        if (File(localPath).existsSync()) {
          await File(localPath).delete();
        }
        await File(expectedPath).rename(localPath);
      } catch (_) {}
    }
  }

  Future<void> createFolderPath(String path) async {
    await createFolderRecursive(path);
  }

  Future<void> deletePath(String path) async {
    final resolved = await resolvePath(path);
    await trashItems(resolved['uuid'], resolved['type']);
  }

  Future<void> movePath(String sourcePath, String targetPath) async {
    final sourceResolved = await resolvePath(sourcePath);
    final targetResolved = await resolvePath(targetPath);
    
    if (targetResolved['type'] != 'folder') {
      throw Exception('Target path is not a folder: $targetPath');
    }
    
    if (sourceResolved['type'] == 'file') {
      await moveFile(sourceResolved['uuid'], targetResolved['uuid']);
    } else {
      await moveFolder(sourceResolved['uuid'], targetResolved['uuid']);
    }
  }

  Future<void> renamePath(String path, String newName) async {
    final resolved = await resolvePath(path);
    
    if (resolved['type'] == 'file') {
      final parts = newName.split('.');
      String? extension;
      String plainName = newName;
      
      if (parts.length > 1) {
        extension = parts.last;
        plainName = parts.sublist(0, parts.length - 1).join('.');
      }
      
      await renameFile(resolved['uuid'], plainName, extension);
    } else {
      await renameFolder(resolved['uuid'], newName);
    }
  }
}