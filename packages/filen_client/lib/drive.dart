/// Drive operations: path resolution, folder CRUD, move/rename/trash/delete,
/// search, find, tree, and trash listing.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:filen_client/api.dart';
import 'package:filen_client/cache.dart';
import 'package:filen_client/crypto.dart';
import 'package:filen_client/utils.dart';

class FilenDrive {
  final FilenApi api;
  final FilenCrypto crypto;
  final FilenCache cache;

  String baseFolderUUID = '';
  List<String> masterKeys = [];
  String email = '';

  FilenDrive({
    required this.api,
    required this.crypto,
    required this.cache,
  });

  // --- File / Folder metadata ---

  Future<bool> checkFileExists(String parentUuid, String name) async {
    final hashed = await crypto.hashFileName(name, masterKeys, email);
    try {
      final res = await api.post(
          '/v3/file/exists', {'parent': parentUuid, 'nameHashed': hashed});
      return res['data']['exists'] == true;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, dynamic>> getFileMetadata(String uuid) async {
    final info = await api.post('/v3/file', {'uuid': uuid});
    return info['data'] ?? info;
  }

  Future<Map<String, dynamic>> getFolderMetadata(String uuid) async {
    final info = await api.post('/v3/dir', {'uuid': uuid});
    return info['data'] ?? info;
  }

  // --- Folder creation ---

  Future<void> createDirectory(String name, String parent,
      {String? creationTime, String? modificationTime}) async {
    final uuid = crypto.uuid();
    final mk = masterKeys.last;
    if (mk.isEmpty) throw Exception('No master keys available');
    final encName =
        await crypto.encryptMetadata002(json.encode({'name': name}), mk);
    final hashed = await crypto.hashFileName(name, masterKeys, email);

    final payload = <String, dynamic>{
      'uuid': uuid,
      'name': encName,
      'nameHashed': hashed,
      'parent': parent,
    };

    if (creationTime != null) payload['creationTime'] = creationTime;
    if (modificationTime != null)
      payload['modificationTime'] = modificationTime;

    await api.post('/v3/dir/create', payload);
    cache.invalidate(parent);
  }

  Future<Map<String, dynamic>> createFolderRecursive(String path,
      {String? creationTime, String? modificationTime}) async {
    if (baseFolderUUID.isEmpty) throw Exception("Not logged in");

    var cleanPath = path.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    if (cleanPath.isEmpty) {
      return {'uuid': baseFolderUUID, 'plainName': 'Root', 'path': '/'};
    }

    if (cache.pathCache.containsKey(cleanPath)) {
      return cache.pathCache[cleanPath]!;
    }

    var parts = cleanPath.split('/');
    var currentParentUuid = baseFolderUUID;
    var currentPath = '/';
    Map<String, dynamic> currentFolderInfo = {
      'uuid': baseFolderUUID,
      'plainName': 'Root',
      'path': '/'
    };

    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (part.isEmpty) continue;

      final isLastPart = (i == parts.length - 1);
      final partPathStr = '$currentPath$part/'.replaceAll('//', '/');
      final cleanPartPath = partPathStr.replaceAll(RegExp(r'/$'), '');

      if (cache.pathCache.containsKey(cleanPartPath)) {
        currentFolderInfo = cache.pathCache[cleanPartPath]!;
        currentParentUuid = currentFolderInfo['uuid'];
        currentPath = partPathStr;
        continue;
      }

      final folders = await cache.listFoldersAsync(currentParentUuid,
          api: api, crypto: crypto, masterKeys: masterKeys);
      Map<String, dynamic>? found;

      for (var folder in folders) {
        if (folder['name'] == part) {
          found = folder;
          break;
        }
      }

      if (found != null) {
        currentParentUuid = found['uuid'];
        currentFolderInfo = found;
        currentFolderInfo['path'] = cleanPartPath;
        currentPath = partPathStr;
        cache.pathCache[cleanPartPath] = currentFolderInfo;
      } else {
        api.log("Creating folder: $part in $currentPath");
        try {
          await createDirectory(
            part,
            currentParentUuid,
            creationTime: isLastPart ? creationTime : null,
            modificationTime: isLastPart ? modificationTime : null,
          );
        } catch (e) {
          if (e.toString().contains('409') ||
              e.toString().contains('already exists')) {
            api.log('Conflict (409), re-fetching...');
            await Future.delayed(Duration(milliseconds: 500));
            cache.invalidate(currentParentUuid);
          } else {
            throw e;
          }
        }

        await Future.delayed(Duration(milliseconds: 200));
        cache.invalidate(currentParentUuid);
        final foldersAfter = await cache.listFoldersAsync(currentParentUuid,
            api: api, crypto: crypto, masterKeys: masterKeys);

        Map<String, dynamic>? newFolder;
        for (var f in foldersAfter) {
          if (f['name'] == part) {
            newFolder = f;
            break;
          }
        }

        if (newFolder == null)
          throw Exception("Created folder but couldn't find it: $part");

        currentParentUuid = newFolder['uuid'];
        currentFolderInfo = newFolder;
        currentFolderInfo['path'] = cleanPartPath;
        currentPath = partPathStr;
        cache.pathCache[cleanPartPath] = currentFolderInfo;
      }
    }

    return currentFolderInfo;
  }

  // --- Mutations ---

  Future<void> moveItem(String uuid, String destUuid, String type) async {
    await cache.clearParentCache(uuid, type, api, crypto, masterKeys);
    final endpoint = type == 'folder' ? '/v3/dir/move' : '/v3/file/move';
    await api.post(endpoint, {'uuid': uuid, 'to': destUuid});
    cache.invalidate(destUuid);
    cache.clearPathCache();
  }

  Future<void> trashItem(String uuid, String type) async {
    await cache.clearParentCache(uuid, type, api, crypto, masterKeys);
    final endpoint = type == 'folder' ? '/v3/dir/trash' : '/v3/file/trash';
    await api.post(endpoint, {'uuid': uuid});
    cache.clearPathCache();
  }

  Future<void> restoreItem(String uuid, String type) async {
    final endpoint = type == 'folder' ? '/v3/dir/restore' : '/v3/file/restore';
    await api.post(endpoint, {'uuid': uuid});
    if (baseFolderUUID.isNotEmpty) {
      cache.invalidate(baseFolderUUID);
    }
  }

  Future<void> deletePermanently(String uuid, String type) async {
    await cache.clearParentCache(uuid, type, api, crypto, masterKeys);
    final endpoint = type == 'folder'
        ? '/v3/dir/delete/permanent'
        : '/v3/file/delete/permanent';
    await api.post(endpoint, {'uuid': uuid});
  }

  Future<void> renameItem(String uuid, String newName, String type) async {
    await cache.clearParentCache(uuid, type, api, crypto, masterKeys);
    final mk = masterKeys.last;
    if (mk.isEmpty) throw Exception('No master keys available');
    final nameHashed = await crypto.hashFileName(newName, masterKeys, email);

    if (type == 'folder') {
      final encName =
          await crypto.encryptMetadata002(json.encode({'name': newName}), mk);
      await api.post('/v3/dir/rename',
          {'uuid': uuid, 'name': encName, 'nameHashed': nameHashed});
    } else {
      final metaRaw = await getFileMetadata(uuid);
      final metadata = metaRaw['data'] ?? metaRaw;
      final metaStr = await crypto.tryDecrypt(metadata['metadata'], masterKeys);
      final metaJson = json.decode(metaStr);
      metaJson['name'] = newName;

      final fileKey = metaJson['key'];
      final nameEncrypted = await crypto.encryptMetadata002(newName, fileKey);
      final metadataEncrypted =
          await crypto.encryptMetadata002(json.encode(metaJson), mk);

      await api.post('/v3/file/rename', {
        'uuid': uuid,
        'name': nameEncrypted,
        'metadata': metadataEncrypted,
        'nameHashed': nameHashed
      });
    }
    cache.clearPathCache();
  }

  // --- Flat tree ---

  Future<Map<String, dynamic>> getFlatFolderTree(String folderUuid) async {
    final deviceId = crypto.uuid();
    api.log('Fetching flat tree for $folderUuid (DeviceID: $deviceId)...');

    final response = await api.makeRequest(
      'POST',
      Uri.parse('${FilenApi.apiUrl}/v3/dir/tree'),
      body: json.encode({
        'uuid': folderUuid,
        'deviceId': deviceId,
        'skipCache': 0,
      }),
    );

    final data = json.decode(response.body);
    if (data['status'] != true) {
      throw Exception(data['message'] ?? 'Failed to fetch tree');
    }
    return data['data'] ?? {};
  }

  Future<Map<String, List<Map<String, dynamic>>>> fetchAndParseTree(
      String rootUuid) async {
    final treeData = await getFlatFolderTree(rootUuid);

    final rawFolders = treeData['folders'] as List? ?? [];
    final rawFiles =
        (treeData['files'] as List?) ?? (treeData['uploads'] as List?) ?? [];

    api.log(
        'Tree fetched: ${rawFolders.length} folders, ${rawFiles.length} files');

    final adjacency = <String, List<Map<String, dynamic>>>{};

    for (var f in rawFolders) {
      try {
        String uuid, encName, parent;
        if (f is List) {
          if (f.length < 3) continue;
          uuid = f[0];
          encName = f[1];
          parent = f[2];
        } else {
          if (f['deleted'] == true || f['trash'] == true) continue;
          uuid = f['uuid'];
          encName = f['name'];
          parent = f['parent'];
        }

        var decName = await crypto.tryDecrypt(encName, masterKeys);
        if (decName.startsWith('{')) {
          decName = json.decode(decName)['name'];
        }

        final item = {
          'uuid': uuid,
          'name': decName,
          'parent': parent,
          'type': 'folder'
        };
        if (!adjacency.containsKey(parent)) adjacency[parent] = [];
        adjacency[parent]!.add(item);
      } catch (_) {}
    }

    for (var f in rawFiles) {
      try {
        String uuid, encMeta, parent;
        if (f is List) {
          if (f.length < 6) continue;
          uuid = f[0];
          parent = f[4];
          encMeta = f[5];
        } else {
          if (f['deleted'] == true || f['trash'] == true) continue;
          uuid = f['uuid'];
          parent = f['parent'];
          encMeta = f['metadata'];
        }

        final decMeta = await crypto.tryDecrypt(encMeta, masterKeys);
        final meta = json.decode(decMeta);

        final item = {
          'uuid': uuid,
          'name': meta['name'] ?? 'Unknown',
          'parent': parent,
          'type': 'file',
          'size': meta['size'] ?? 0
        };
        if (!adjacency.containsKey(parent)) adjacency[parent] = [];
        adjacency[parent]!.add(item);
      } catch (_) {}
    }

    return adjacency;
  }

  // --- Path resolution ---

  Future<Map<String, dynamic>> resolvePath(String path) async {
    if (baseFolderUUID.isEmpty) throw Exception("Not logged in");

    var cleanPath = path.trim();
    if (cleanPath.startsWith('/')) cleanPath = cleanPath.substring(1);
    if (cleanPath.endsWith('/'))
      cleanPath = cleanPath.substring(0, cleanPath.length - 1);

    if (cleanPath.isEmpty || cleanPath == '.') {
      return {
        'type': 'folder',
        'uuid': baseFolderUUID,
        'metadata': {'uuid': baseFolderUUID, 'name': 'Root'},
        'path': '/'
      };
    }

    if (cache.pathCache.containsKey(cleanPath)) {
      return cache.pathCache[cleanPath]!;
    }

    String currentUuid = baseFolderUUID;
    String resolvedPath = '/';
    Map<String, dynamic> currentMetadata = {
      'uuid': baseFolderUUID,
      'name': 'Root'
    };

    final pathParts = cleanPath.split('/').where((p) => p.isNotEmpty).toList();

    for (var i = 0; i < pathParts.length; i++) {
      final part = pathParts[i];
      final isLastPart = (i == pathParts.length - 1);
      final currentPartPath = '$resolvedPath$part'.replaceAll('//', '/');

      if (cache.pathCache
          .containsKey(currentPartPath.replaceAll(RegExp(r'^/'), ''))) {
        final cached =
            cache.pathCache[currentPartPath.replaceAll(RegExp(r'^/'), '')]!;
        currentUuid = cached['uuid'];
        currentMetadata = cached['metadata'] ?? cached;
        resolvedPath = '$currentPartPath/';
        if (isLastPart) return cached;
        continue;
      }

      final folders = await cache.listFoldersAsync(currentUuid,
          detailed: true, api: api, crypto: crypto, masterKeys: masterKeys);
      Map<String, dynamic>? foundFolder;

      for (var folder in folders) {
        if (folder['name'] == part) {
          foundFolder = folder;
          break;
        }
      }

      Map<String, dynamic>? foundFile;
      if (isLastPart) {
        final files = await cache.listFolderFiles(currentUuid,
            detailed: true, api: api, crypto: crypto, masterKeys: masterKeys);
        for (var file in files) {
          if (file['name'] == part) {
            foundFile = file;
            break;
          }
        }
      }

      if (foundFolder != null && (!isLastPart || foundFile == null)) {
        currentUuid = foundFolder['uuid'];
        currentMetadata = foundFolder;
        resolvedPath = '$resolvedPath$part/'.replaceAll('//', '/');

        final result = {
          'type': 'folder',
          'uuid': foundFolder['uuid'],
          'metadata': foundFolder,
          'path': resolvedPath.substring(0, resolvedPath.length - 1),
          'parent': foundFolder['parent'],
        };
        cache.pathCache[result['path'] as String] = result;
        if (isLastPart) return result;
      } else if (foundFile != null && isLastPart) {
        resolvedPath = '$resolvedPath$part'.replaceAll('//', '/');
        return {
          'type': 'file',
          'uuid': foundFile['uuid'],
          'metadata': foundFile,
          'path': resolvedPath,
          'parent': currentUuid,
        };
      } else {
        throw Exception("Path not found: $resolvedPath$part");
      }
    }

    return {
      'type': 'folder',
      'uuid': currentUuid,
      'metadata': currentMetadata,
      'path': resolvedPath.isEmpty ? '/' : resolvedPath
    };
  }

  Future<Map<String, dynamic>> resolveOrCreateFolder(String path) async {
    try {
      final info = await resolvePath(path);
      if (info['type'] != 'folder') {
        throw Exception("Path exists but is not a folder");
      }
      return info;
    } on Exception catch (e) {
      if (e.toString().contains("Path not found")) {
        api.log("Creating target folder: $path");
        return await createFolderRecursive(path);
      }
      rethrow;
    }
  }

  // --- Trash ---

  Future<List<Map<String, dynamic>>> getTrashContent() async {
    final response = await api
        .post('/v3/dir/content', {'uuid': 'trash', 'foldersOnly': false});

    final data = response['data'];
    final List<dynamic> rawFolders = data['folders'] ?? [];
    final List<dynamic> rawUploads = data['uploads'] ?? [];

    List<Map<String, dynamic>> results = [];

    for (var f in rawFolders) {
      String name = 'Unknown';
      try {
        var dec = await crypto.tryDecrypt(f['name'], masterKeys);
        name = dec.startsWith('{') ? json.decode(dec)['name'] : dec;
      } catch (_) {
        name = '[Encrypted]';
      }
      results.add({
        'type': 'folder',
        'name': name,
        'uuid': f['uuid'],
        'size': 0,
        'parent': f['parent'],
        'timestamp': f['timestamp'],
        'lastModified': f['lastModified'] ?? 0,
      });
    }

    for (var f in rawUploads) {
      String name = 'Unknown';
      int size = 0;
      int lastModified = 0;
      try {
        final m =
            json.decode(await crypto.tryDecrypt(f['metadata'], masterKeys));
        name = m['name'];
        size = m['size'] ?? 0;
        lastModified = m['lastModified'] ?? 0;
      } catch (_) {
        name = '[Encrypted]';
      }
      results.add({
        'type': 'file',
        'name': name,
        'uuid': f['uuid'],
        'size': size,
        'parent': f['parent'],
        'timestamp': f['timestamp'],
        'lastModified': lastModified,
      });
    }

    return results;
  }

  // --- Search & Find ---

  Future<Map<String, List<Map<String, dynamic>>>> search(String query,
      {bool detailed = false}) async {
    api.log('Server-side search not available, using client-side...');
    final results = await findFiles('/', '*$query*', maxDepth: -1);
    return {
      'folders': [],
      'files': results,
    };
  }

  Future<List<Map<String, dynamic>>> findFiles(String startPath, String pattern,
      {int maxDepth = -1}) async {
    final rootInfo = await resolvePath(startPath);
    if (rootInfo['type'] != 'folder') return [];

    final treeData = await getFlatFolderTree(rootInfo['uuid']);
    final rawFolders = treeData['folders'] as List? ?? [];
    final rawFiles =
        (treeData['files'] as List?) ?? (treeData['uploads'] as List?) ?? [];

    final folderMap = <String, Map<String, dynamic>>{};

    for (var f in rawFolders) {
      try {
        String uuid, encName, parent;
        if (f is List) {
          if (f.length < 3) continue;
          uuid = f[0];
          encName = f[1];
          parent = f[2];
        } else {
          if (f['deleted'] == true || f['trash'] == true) continue;
          uuid = f['uuid'];
          encName = f['name'];
          parent = f['parent'];
        }
        var decName = await crypto.tryDecrypt(encName, masterKeys);
        if (decName.startsWith('{')) {
          decName = json.decode(decName)['name'];
        }
        folderMap[uuid] = {'name': decName, 'parent': parent};
      } catch (_) {}
    }

    final results = <Map<String, dynamic>>[];

    String? getFullPath(String? parentUuid) {
      var parts = <String>[];
      var curr = parentUuid;
      var seen = <String>{};
      while (curr != null && curr != rootInfo['uuid']) {
        if (seen.contains(curr)) return null;
        seen.add(curr);
        if (!folderMap.containsKey(curr)) return null;
        final f = folderMap[curr]!;
        parts.add(f['name']);
        curr = f['parent'];
      }
      if (curr == null && rootInfo['uuid'] != 'root') return null;
      return p.join(startPath, parts.reversed.join('/'));
    }

    // Glob matching: translate `*`/`?` and escape every other character so
    // regex metacharacters in the pattern are matched literally.
    final globBuf = StringBuffer('^');
    for (final ch in pattern.split('')) {
      if (ch == '*') {
        globBuf.write('.*');
      } else if (ch == '?') {
        globBuf.write('.');
      } else {
        globBuf.write(RegExp.escape(ch));
      }
    }
    globBuf.write(r'$');
    final globRegex = RegExp(globBuf.toString(), caseSensitive: false);

    for (var f in rawFiles) {
      try {
        String uuid, encMeta, parent;
        if (f is List) {
          if (f.length < 6) continue;
          uuid = f[0];
          parent = f[4];
          encMeta = f[5];
        } else {
          if (f['deleted'] == true || f['trash'] == true) continue;
          uuid = f['uuid'];
          parent = f['parent'];
          encMeta = f['metadata'];
        }

        final meta = json.decode(await crypto.tryDecrypt(encMeta, masterKeys));
        final name = meta['name'];

        if (!globRegex.hasMatch(name)) continue;

        var dirPath = getFullPath(parent);
        if (parent == rootInfo['uuid'])
          dirPath = startPath;
        else if (dirPath == null) continue;

        if (maxDepth != -1) {
          final relDepth =
              dirPath.split('/').length - startPath.split('/').length;
          if (relDepth >= maxDepth) continue;
        }

        results.add({
          'uuid': uuid,
          'name': name,
          'fullPath': p.join(dirPath, name).replaceAll('\\', '/'),
          'size': meta['size'] ?? 0,
          'lastModified': meta['lastModified'] ?? 0
        });
      } catch (_) {}
    }

    return results;
  }

  Future<void> printTree(
    String path,
    void Function(String) printLine, {
    int maxDepth = 3,
  }) async {
    try {
      final root = await resolvePath(path);
      if (root['type'] != 'folder') {
        printLine("└── 📄 ${p.basename(path)}");
        return;
      }

      final rootUuid = root['uuid'];
      final adjacency = await fetchAndParseTree(rootUuid);

      void printNode(String parentUuid, int currentDepth, String prefix) {
        if (currentDepth >= maxDepth) return;

        final children = adjacency[parentUuid] ?? [];
        children.sort((a, b) {
          if (a['type'] != b['type']) {
            return a['type'] == 'folder' ? -1 : 1;
          }
          return (a['name'] as String)
              .toLowerCase()
              .compareTo((b['name'] as String).toLowerCase());
        });

        for (var i = 0; i < children.length; i++) {
          final item = children[i];
          final isLast = (i == children.length - 1);
          final connector = isLast ? "└── " : "├── ";

          if (item['type'] == 'folder') {
            printLine("$prefix$connector📁 ${item['name']}/");
            final childPrefix = prefix + (isLast ? "    " : "│   ");
            printNode(item['uuid'], currentDepth + 1, childPrefix);
          } else {
            final size = formatSize(item['size']);
            printLine("$prefix$connector📄 ${item['name']} ($size)");
          }
        }
      }

      printNode(rootUuid, 0, "");
    } catch (e) {
      printLine("└── ❌ Error: $e");
    }
  }

  /// Verify uploaded file using metadata hash (no download needed).
  Future<bool> verifyUploadMetadata(String fileUuid, File originalFile) async {
    api.log('Verifying upload using metadata check...');

    print('   📊 Hashing local file...');
    final localHash = await crypto.hashFile(originalFile);
    api.log('   Local SHA-512: $localHash');

    print('   📋 Fetching metadata from server...');
    final metadata = await getFileMetadata(fileUuid);
    final metaStr = await crypto.tryDecrypt(metadata['metadata'], masterKeys);
    final meta = json.decode(metaStr);

    final serverHash = meta['hash'] as String?;

    if (serverHash == null || serverHash.isEmpty) {
      print('   ⚠️  No hash in metadata (empty file?)');
      return await originalFile.length() == 0;
    }

    api.log('   Server SHA-512: $serverHash');

    final match = localHash == serverHash;

    if (match) {
      print('   ✅ Verification successful - hashes match!');
    } else {
      print('   ❌ Verification failed - hashes differ!');
      print('      Local:  $localHash');
      print('      Server: $serverHash');
    }

    return match;
  }
}
