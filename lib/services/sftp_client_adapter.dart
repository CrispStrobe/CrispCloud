// lib/services/sftp_client_adapter.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;

import 'cloud_storage_interface.dart';
import 'sftp_config_service.dart'; 

class SFTPClientAdapter implements CloudStorageClient {
  final SFTPConfigService _config;
  
  // FIX: Expose config for AppState to read credentials
  SFTPConfigService get config => _config;
  
  // SSH State
  SSHClient? _sshClient;
  SftpClient? _sftp;
  String? _username;
  String? _host;
  int _port = 23; 

  SFTPClientAdapter({required dynamic config}) 
      : _config = (config is SFTPConfigService) 
            ? config 
            : SFTPConfigService(configPath: ''); 

  @override
  String get providerName => 'SFTP';

  @override
  String get rootPath => '/';

  @override
  bool get isAuthenticated => _sftp != null;

  @override
  String? get userId => _username;

  @override
  String? get bucketId => _host; 

  // --- Connection Management ---

  Future<void> _ensureConnection() async {
    if (_sshClient != null && !_sshClient!.isClosed && _sftp != null) return;

    final creds = await _config.readCredentials();
    if (creds == null) throw Exception('Not logged in');

    _username = creds['username'];
    _host = creds['host'];
    final password = creds['password'];
    _port = int.tryParse(creds['port'] ?? '23') ?? 23;

    if (_host == null || _username == null || password == null) {
       throw Exception('Incomplete credentials');
    }

    try {
      final socket = await SSHSocket.connect(_host!, _port);
      
      _sshClient = SSHClient(
        socket,
        username: _username!,
        onPasswordRequest: () => password,
      );
      
      await _sshClient!.authenticated;
      _sftp = await _sshClient!.sftp();
    } catch (e) {
      _sshClient?.close();
      _sshClient = null;
      _sftp = null;
      throw Exception('Connection failed: $e');
    }
  }

  // --- Interface Implementation ---

  @override
  Future<void> login(String email, String password, {String? twoFactorCode}) async {
    String user = email;
    String host = '';
    String port = '22';
    
    if (email.contains('@')) {
      final parts = email.split('@');
      user = parts[0];
      final hostPart = parts[1];
      
      if (hostPart.contains(':')) {
        final hostParts = hostPart.split(':');
        host = hostParts[0];
        port = hostParts[1];
      } else {
        host = hostPart;
      }
    } else {
      throw Exception('Format must be user@host (e.g. u12345@u123.your-storagebox.de)');
    }

    await _config.saveCredentials({
      'username': user,
      'password': password,
      'host': host,
      'port': port,
    });

    try {
      await _ensureConnection();
    } catch (e) {
      await _config.clearCredentials();
      rethrow;
    }
  }

  @override
  Future<bool> is2faNeeded(String email) async => false; 

  @override
  Future<void> logout() async {
    _sshClient?.close();
    _sshClient = null;
    _sftp = null;
    await _config.clearCredentials();
  }

  @override
  Future<Map<String, dynamic>?> resolvePath(String path) async {
    await _ensureConnection();
    try {
      final stat = await _sftp!.stat(path);
      
      // FIX: Handle int timestamp safely
      String? updatedAt;
      if (stat.modifyTime != null) {
        updatedAt = DateTime.fromMillisecondsSinceEpoch(stat.modifyTime! * 1000).toIso8601String();
      }

      return {
        'type': stat.isDirectory ? 'folder' : 'file',
        'name': p.basename(path),
        'path': path,
        'size': stat.size,
        'updatedAt': updatedAt,
        'uuid': path, 
      };
    } catch (e) {
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    await _ensureConnection();
    
    final folders = <Map<String, dynamic>>[];
    final files = <Map<String, dynamic>>[];

    try {
      final items = await _sftp!.listdir(path);
      
      for (final item in items) {
        if (item.filename == '.' || item.filename == '..') continue;
        
        final fullPath = p.posix.join(path, item.filename);
        final isDir = item.attr.isDirectory;
        
        // FIX: Handle int timestamp safely
        final modTimeInt = item.attr.modifyTime ?? 0;
        final modTimeStr = DateTime.fromMillisecondsSinceEpoch(modTimeInt * 1000).toIso8601String();
        
        final map = {
          'uuid': fullPath, 
          'name': item.filename, // Keep full name (e.g. file.txt)
          'size': item.attr.size,
          'modificationTime': modTimeStr,
          'type': isDir ? 'folder' : 'file',
          'path': fullPath,
          // AppState adds extension if fileType exists. 
          // Since SFTP returns full names, we leave fileType null/empty.
        };

        if (isDir) {
          folders.add(map);
        } else {
          files.add(map);
        }
      }
    } catch (e) {
      print('SFTP List Error: $e');
      throw Exception('Failed to list path $path: $e');
    }

    return {
      'folders': folders,
      'files': files,
    };
  }

  @override
  Future<void> uploadFile(
    List<int> fileData,
    String fileName,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    await _ensureConnection();
    final remoteFilePath = p.posix.join(targetPath, fileName);
    
    final file = await _sftp!.open(
      remoteFilePath,
      mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.truncate,
    );
    
    try {
      final bytes = Uint8List.fromList(fileData);
      
      int offset = 0;
      const chunkSize = 32 * 1024; 
      final total = bytes.length;
      
      while (offset < total) {
        var end = offset + chunkSize;
        if (end > total) end = total;
        
        final chunk = bytes.sublist(offset, end);
        await file.writeBytes(chunk); 
        
        offset = end;
        if (onProgress != null) onProgress(offset, total);
      }
    } finally {
      await file.close();
    }
  }

  @override
  Future<void> downloadFileByPath(
    String remotePath,
    String localPath, {
    Function(int, int)? onProgress,
  }) async {
    await _ensureConnection();
    
    final file = await _sftp!.open(remotePath, mode: SftpFileOpenMode.read);
    final fileSize = (await file.stat()).size ?? 0;
    
    final localFile = File(localPath);
    final sink = localFile.openWrite();
    
    try {
      int downloaded = 0;
      int offset = 0;
      
      while(true) {
         final chunk = await file.readBytes(length: 32 * 1024, offset: offset);
         if (chunk.isEmpty) break;
         
         sink.add(chunk);
         offset += chunk.length;
         downloaded += chunk.length;
         
         if (onProgress != null) onProgress(downloaded, fileSize);
      }
    } finally {
      await sink.close();
      await file.close();
    }
  }

  @override
  Future<Uint8List> downloadFileBytes(
    String remotePath, {
    Function(int, int)? onProgress,
  }) async {
    await _ensureConnection();
    
    final file = await _sftp!.open(remotePath, mode: SftpFileOpenMode.read);
    final fileSize = (await file.stat()).size ?? 0;
    
    // Use a BytesBuilder to collect chunks efficiently
    final builder = BytesBuilder(copy: false);
    
    try {
      int downloaded = 0;
      int offset = 0;
      
      while(true) {
         final chunk = await file.readBytes(length: 32 * 1024, offset: offset);
         if (chunk.isEmpty) break;
         
         builder.add(chunk);
         offset += chunk.length;
         downloaded += chunk.length;
         
         if (onProgress != null) onProgress(downloaded, fileSize);
      }
      
      return builder.takeBytes();
    } finally {
      await file.close();
    }
  }

  @override
  Future<void> createFolderPath(String path) async {
    await _ensureConnection();
    try {
      await _sftp!.mkdir(path);
    } catch (e) {
      // Ignore if exists
    }
  }

  @override
  Future<void> deletePath(String path) async {
    await _ensureConnection();
    final stat = await _sftp!.stat(path);
    
    if (stat.isDirectory) {
      await _deleteDirectoryRecursive(path);
    } else {
      await _sftp!.remove(path);
    }
  }
  
  Future<void> _deleteDirectoryRecursive(String path) async {
    final items = await _sftp!.listdir(path);
    for (var item in items) {
      if (item.filename == '.' || item.filename == '..') continue;
      final fullPath = p.posix.join(path, item.filename);
      
      if (item.attr.isDirectory) {
        await _deleteDirectoryRecursive(fullPath);
      } else {
        await _sftp!.remove(fullPath);
      }
    }
    await _sftp!.rmdir(path);
  }

  @override
  Future<void> movePath(String sourcePath, String targetPath) async {
    await _ensureConnection();
    await _sftp!.rename(sourcePath, targetPath);
  }

  @override
  Future<void> renamePath(String path, String newName) async {
    await _ensureConnection();
    final newPath = p.posix.join(p.dirname(path), newName);
    await _sftp!.rename(path, newPath);
  }
}