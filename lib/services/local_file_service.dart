// services/local_file_service.dart
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart'; // Import for kIsWeb
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'bookmark_service.dart';

// If running on web (dart.library.html), load the stub. Otherwise, load the real package.
import 'macos_bookmark_service.dart' if (dart.library.html) 'macos_bookmark_service_stub.dart';
import 'package:macos_secure_bookmarks/macos_secure_bookmarks.dart' if (dart.library.html) 'macos_bookmark_service_stub.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_html/html.dart' as html; // For Web Input
import 'package:universal_html/js.dart' as js;     // For JS Interop (File System Access API)
import 'package:cross_file/cross_file.dart'; 
import '../models/file_item.dart';
import 'package:path/path.dart' as p;

/// Abstract interface for handling local file system access.
abstract class LocalFileService {
  late String currentPath;
  String? get grantedBasePath;
  Future<String> getInitialPath();
  Future<String?> requestDirectoryAccess({String? initialDirectory});
  Future<List<FileSystemEntity>?> listDirectory(String path);
  Future<bool> hasAccessToPath(String path);
  Future<String> getSafeFallbackDirectory();
  
  /// We need this to read files while maintaining the security scope e.g. on macOS
  Future<Uint8List> readFile(String path, {FileItem? fileItem});

  /// Save data to a file, handling platform-specific permissions (Web download or Secure Bookmarks)
  Future<void> saveFile(String path, Uint8List data);

  // Helper for Web to get metadata without stat()
  Map<String, dynamic> getWebMetadata(String path) => {};
  
  factory LocalFileService() {
    if (kIsWeb) {
      return WebFileService.instance; // RETURN SINGLETON
    }
    
    if (Platform.isMacOS) {
      return MacosFileService();
    }
    if (Platform.isAndroid || Platform.isIOS) {
      return MobileFileService();
    }
    if (Platform.isWindows || Platform.isLinux) {
      return DesktopFileService();
    }
    throw UnsupportedError('Unsupported platform');
  }
}

// --- Web Implementation (Singleton & Enhanced) ---
class WebFileService implements LocalFileService {
  // Singleton pattern to preserve state across reloads/instantiations
  static final WebFileService instance = WebFileService._internal();
  WebFileService._internal();

  // Stores directory structure: Key='/Photos', Value=[Entity('img.jpg')]
  static final Map<String, List<FileSystemEntity>> _virtualTree = {};
  // Stores actual file references: Key='/Photos/img.jpg', Value=FileObject
  static final Map<String, html.File> _fileRefs = {};
  
  // File System Access API Handle (Chrome/Edge only)
  static dynamic _rootDirHandle;

  @override
  String currentPath = '/';

  @override
  String? get grantedBasePath => null;

  @override
  Future<String> getInitialPath() async => '/';

  @override
  Map<String, dynamic> getWebMetadata(String path) {
    final f = _fileRefs[path];
    if (f != null) {
      return {
        'size': f.size,
        'modified': DateTime.fromMillisecondsSinceEpoch(f.lastModified ?? DateTime.now().millisecondsSinceEpoch),
      };
    }
    return {};
  }

  /// Tries to use Modern API (Chrome), falls back to Legacy Input (Safari)
  @override
  Future<String?> requestDirectoryAccess({String? initialDirectory}) async {
    // 1. Reset State
    _virtualTree.clear();
    _fileRefs.clear();
    _rootDirHandle = null;

    // 2. Try File System Access API (Chrome/Edge/Opera)
    if (js.context.hasProperty('showDirectoryPicker')) {
      try {
        print("🌐 [Web] Attempting 'showDirectoryPicker' (Write Access)...");
        final promise = js.context.callMethod('showDirectoryPicker');
        _rootDirHandle = await js.promiseToFuture(promise);
        
        final rootName = _rootDirHandle['name'];
        print("✅ [Web] Got handle for folder: $rootName");

        // Recursively build the virtual tree from the handle
        await _buildTreeFromHandle(_rootDirHandle, '/$rootName');
        
        currentPath = '/$rootName';
        return currentPath;
      } catch (e) {
        print("⚠️ [Web] showDirectoryPicker cancelled or failed: $e. Falling back to input.");
        // Fallthrough to legacy input if user cancels or API fails
      }
    }

    // 3. Legacy Fallback (Safari/Firefox)
    // No write access, download goes to Downloads folder.
    final completer = Completer<String?>();
    final input = html.FileUploadInputElement();
    
    input.setAttribute('webkitdirectory', ''); 
    input.setAttribute('directory', '');      
    input.multiple = true;  
    
    input.onChange.listen((e) {
      if (input.files == null || input.files!.isEmpty) {
        completer.complete(null);
        return;
      }

      String rootName = 'root';
      // Heuristic to detect root folder name from relative paths
      if (input.files!.isNotEmpty) {
        final firstPath = input.files!.first.relativePath ?? input.files!.first.name;
        final parts = firstPath.split('/');
        if (parts.isNotEmpty) rootName = parts[0];
      }

      print("📂 [Web] Processing ${input.files!.length} files via legacy input...");

      for (final file in input.files!) {
        // Filter out macOS metadata files
        if (file.name.startsWith('._')) continue;

        final relPath = file.relativePath ?? file.name;
        final fullPath = '/$relPath';
        
        _fileRefs[fullPath] = file;
        _populateVirtualTree(relPath);
      }

      final startPath = '/$rootName';
      currentPath = startPath;
      completer.complete(startPath);
    });

    input.click();
    return completer.future;
  }

  // Recursive walker for File System Access API
  Future<void> _buildTreeFromHandle(dynamic dirHandle, String currentAbsPath) async {
    // Ensure entry exists for this folder
    if (!_virtualTree.containsKey(currentAbsPath)) {
      _virtualTree[currentAbsPath] = [];
    }

    // Iterate values(). This is AsyncIterable in JS.
    final valuesIterator = dirHandle.callMethod('values');
    
    while (true) {
      final next = await js.promiseToFuture(valuesIterator.callMethod('next'));
      if (next['done'] == true) break;
      
      final handle = next['value'];
      final name = handle['name'];
      
      // Filter hidden/system files
      if (name.startsWith('.') || name.startsWith('._')) continue;

      final itemAbsPath = "$currentAbsPath/$name";
      
      if (handle['kind'] == 'file') {
        _virtualTree[currentAbsPath]!.add(File(itemAbsPath));
        
        // Get the File object for reading
        final fileObj = await js.promiseToFuture(handle.callMethod('getFile'));
        _fileRefs[itemAbsPath] = fileObj;
        
      } else if (handle['kind'] == 'directory') {
        _virtualTree[currentAbsPath]!.add(Directory(itemAbsPath));
        await _buildTreeFromHandle(handle, itemAbsPath);
      }
    }
  }

  // Helper for Legacy Input
  void _populateVirtualTree(String relPath) {
    final parts = relPath.split('/');
    String parentPath = '/'; // Start at absolute root
    
    for (int i = 0; i < parts.length; i++) {
      final partName = parts[i];
      final isFile = (i == parts.length - 1);
      final currentItemPath = parentPath == '/' ? '/$partName' : '$parentPath/$partName';

      if (!_virtualTree.containsKey(parentPath)) {
        _virtualTree[parentPath] = [];
      }

      final exists = _virtualTree[parentPath]!.any((e) => e.path == currentItemPath);

      if (!exists) {
        if (isFile) {
          _virtualTree[parentPath]!.add(File(currentItemPath));
        } else {
          _virtualTree[parentPath]!.add(Directory(currentItemPath));
        }
      }
      parentPath = currentItemPath;
    }
  }

  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async {
    String lookup = path;
    if (lookup.length > 1 && lookup.endsWith('/')) {
      lookup = lookup.substring(0, lookup.length - 1);
    }
    return _virtualTree[lookup] ?? [];
  }

  @override
  Future<bool> hasAccessToPath(String path) async {
    String lookup = path;
    if (lookup.length > 1 && lookup.endsWith('/')) {
      lookup = lookup.substring(0, lookup.length - 1);
    }
    return _virtualTree.containsKey(lookup) || _fileRefs.containsKey(lookup);
  }

  @override
  Future<String> getSafeFallbackDirectory() async => '/';

  @override
  Future<Uint8List> readFile(String path, {FileItem? fileItem}) async {
    final fileRef = _fileRefs[path];
    if (fileRef == null) throw Exception('File ref not found: $path');
    
    final reader = html.FileReader();
    reader.readAsArrayBuffer(fileRef);
    await reader.onLoad.first;
    return reader.result as Uint8List;
  }

  @override
  Future<void> saveFile(String path, Uint8List data) async {
    // 1. Try Modern "Save to Folder" (Chrome/Edge)
    if (_rootDirHandle != null) {
      try {
        print('🌐 [Web] Attempting direct write to folder handle...');
        // We need to walk the handle to find the correct subfolder if path is deep
        // For simplicity, we assume writing relative to root handle for now, 
        // or implement a path walker.
        
        // Simple implementation: Write to root of selected folder if path matches
        // Extract filename
        final fileName = p.basename(path);
        
        // Get File Handle (create: true)
        final fileHandlePromise = _rootDirHandle.callMethod('getFileHandle', [
          fileName, 
          js.JsObject.jsify({'create': true})
        ]);
        final fileHandle = await js.promiseToFuture(fileHandlePromise);
        
        // Create Writable
        final writablePromise = fileHandle.callMethod('createWritable');
        final writable = await js.promiseToFuture(writablePromise);
        
        // Write
        await js.promiseToFuture(writable.callMethod('write', [data]));
        await js.promiseToFuture(writable.callMethod('close'));
        
        print('✅ [Web] Successfully wrote to $fileName');
        return;
      } catch (e) {
        print('⚠️ [Web] Direct write failed ($e). Falling back to download.');
      }
    }

    // 2. Fallback "Save As" (Safari/Firefox)
    print('🌐 [Web] Triggering browser download for $path');
    final fileName = p.basename(path);
    final blob = html.Blob([data]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute("download", fileName)
      ..click();
    html.Url.revokeObjectUrl(url);
  }
}

// --- macOS Implementation ---
class MacosFileService implements LocalFileService {
  String? _grantedBasePath;
  final _bookmarks = SecureBookmarks();
  FileSystemEntity? _resolvedBookmarkFile;
  
  @override
  String currentPath = !kIsWeb ? (Platform.environment['HOME'] ?? '/') : '/';

  @override
  String? get grantedBasePath => _grantedBasePath;

  @override
  Map<String, dynamic> getWebMetadata(String path) => {};

  Future<bool> _loadAndResolveBookmark() async {
    try {
      _resolvedBookmarkFile = await MacOSBookmarkService.getResolvedBookmark();
      if (_resolvedBookmarkFile != null) {
        _grantedBasePath = _resolvedBookmarkFile!.path;
        return true;
      }
      return false;
    } catch (e) {
      print('⚠️ Failed to load or resolve bookmark: $e');
      _resolvedBookmarkFile = null;
      _grantedBasePath = null;
      return false;
    }
  }

  @override
  Future<String> getInitialPath() async {
    final grantedPath = await MacOSBookmarkService.getLastGrantedDirectory();
    if (grantedPath != null) {
      print('✅ Found bookmarked path: $grantedPath');
      _grantedBasePath = grantedPath;
      currentPath = grantedPath;
      return currentPath;
    }
    currentPath = await getSafeFallbackDirectory();
    _grantedBasePath = null;
    return currentPath;
  }

  @override
  Future<String?> requestDirectoryAccess({String? initialDirectory}) async {
    final path = await MacOSBookmarkService.requestDirectoryAccess(
      initialDirectory: initialDirectory,
    );
    if (path != null) {
      _grantedBasePath = path;
      currentPath = path;
      await _loadAndResolveBookmark(); 
    }
    return path;
  }

  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async {
    currentPath = path;
    if (_resolvedBookmarkFile == null) {
      if (!await _loadAndResolveBookmark()) {
         // If no bookmark, try mostly harmless listing, might throw
      }
    }

    // Try secure listing if we have a bookmark and path is inside it
    if (_resolvedBookmarkFile != null && path.startsWith(_resolvedBookmarkFile!.path)) {
      try {
        await _bookmarks.startAccessingSecurityScopedResource(_resolvedBookmarkFile!);
        final dir = Directory(path);
        final entities = await dir.list().toList();
        await _bookmarks.stopAccessingSecurityScopedResource(_resolvedBookmarkFile!);
        return entities;
      } catch (e) {
        try { await _bookmarks.stopAccessingSecurityScopedResource(_resolvedBookmarkFile!); } catch (_) {}
        // Fallthrough to try normal listing
      }
    }
    
    // Normal listing fallback
    try {
      return await Directory(path).list().toList();
    } catch (e) {
      print('❌ Failed to list directory: $e');
      rethrow;
    }
  }

  @override
  Future<Uint8List> readFile(String path, {FileItem? fileItem}) async {
    if (_resolvedBookmarkFile == null) await _loadAndResolveBookmark();
    
    if (_resolvedBookmarkFile != null && path.startsWith(_resolvedBookmarkFile!.path)) {
      try {
        await _bookmarks.startAccessingSecurityScopedResource(_resolvedBookmarkFile!);
        final data = await File(path).readAsBytes();
        await _bookmarks.stopAccessingSecurityScopedResource(_resolvedBookmarkFile!);
        return data;
      } catch (e) {
        try { await _bookmarks.stopAccessingSecurityScopedResource(_resolvedBookmarkFile!); } catch (_) {}
        rethrow;
      }
    }
    return File(path).readAsBytes();
  }

  @override
  Future<void> saveFile(String path, Uint8List data) async {
    if (_resolvedBookmarkFile == null) await _loadAndResolveBookmark();

    if (_resolvedBookmarkFile != null && path.startsWith(_resolvedBookmarkFile!.path)) {
      try {
        print('🔐 [MacOS] Writing to secure path: $path');
        await _bookmarks.startAccessingSecurityScopedResource(_resolvedBookmarkFile!);
        
        final file = File(path);
        // Ensure parent exists
        if (!await file.parent.exists()) {
           await file.parent.create(recursive: true);
        }
        await file.writeAsBytes(data);
        
        await _bookmarks.stopAccessingSecurityScopedResource(_resolvedBookmarkFile!);
        return;
      } catch (e) {
        try { await _bookmarks.stopAccessingSecurityScopedResource(_resolvedBookmarkFile!); } catch (_) {}
        print('❌ [MacOS] Secure write failed: $e');
        rethrow;
      }
    }
    
    // Fallback normal write
    print('💾 [MacOS] Writing to path (no bookmark scope): $path');
    final file = File(path);
    if (!await file.parent.exists()) {
       await file.parent.create(recursive: true);
    }
    await file.writeAsBytes(data);
  }

  @override
  Future<bool> hasAccessToPath(String path) async {
    if (_grantedBasePath == null) {
      _grantedBasePath = await MacOSBookmarkService.getLastGrantedDirectory();
    }
    if (_grantedBasePath != null && path.startsWith(_grantedBasePath!)) return true;
    return path.startsWith(Platform.environment['HOME'] ?? '/');
  }
  
  @override
  Future<String> getSafeFallbackDirectory() async {
     return Platform.environment['HOME'] ?? '/';
  }
}

// --- Windows/Linux Implementation ---
class DesktopFileService implements LocalFileService {
  @override
  String currentPath = !kIsWeb ? (Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '/') : '/';
  
  @override
  String? get grantedBasePath => null; 

  @override
  Map<String, dynamic> getWebMetadata(String path) => {};

  @override
  Future<String> getInitialPath() async {
    final lastPath = await BookmarkService.getLastPath();
    try {
      if (lastPath != null && await Directory(lastPath).exists()) {
        currentPath = lastPath;
        return lastPath;
      }
    } catch(e) {
      print('⚠️ Could not access last path, using fallback. Error: $e');
    }
    currentPath = await getSafeFallbackDirectory();
    return currentPath;
  }

  @override
  Future<String?> requestDirectoryAccess({String? initialDirectory}) async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Directory',
      lockParentWindow: true,
      initialDirectory: initialDirectory,
    );
    if (path != null) {
      await BookmarkService.saveLastPath(path);
      currentPath = path;
    }
    return path;
  }

  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async {
    currentPath = path;
    return Directory(path).list().toList();
  }
  
  @override
  Future<Uint8List> readFile(String path, {FileItem? fileItem}) async {
    return File(path).readAsBytes();
  }

  @override
  Future<void> saveFile(String path, Uint8List data) async {
    final file = File(path);
    if (!await file.parent.exists()) {
       await file.parent.create(recursive: true);
    }
    await file.writeAsBytes(data);
  }

  @override
  Future<bool> hasAccessToPath(String path) async => true; 
  
  @override
  Future<String> getSafeFallbackDirectory() async {
     return Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '/';
  }
}

// --- Mobile (Android/iOS) Implementation ---
class MobileFileService implements LocalFileService {
  String? _grantedBasePath;
  static const String _mobileBookmarkKey = 'mobile_bookmark_data';
  final _bookmarks = SecureBookmarks();
  FileSystemEntity? _resolvedBookmarkFile;
  
  @override
  String currentPath = '/'; 

  @override
  String? get grantedBasePath => _grantedBasePath;

  @override
  Map<String, dynamic> getWebMetadata(String path) => {};
  
  Future<bool> _loadAndResolveBookmark() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bookmarkBase64 = prefs.getString(_mobileBookmarkKey); 
      if (bookmarkBase64 == null) {
        return false;
      }
      _resolvedBookmarkFile = await _bookmarks.resolveBookmark(bookmarkBase64);
      return true;
    } catch (e) {
      print('⚠️ Failed to load or resolve mobile bookmark: $e');
      _resolvedBookmarkFile = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_mobileBookmarkKey); 
      return false;
    }
  }

  @override
  Future<String> getInitialPath() async {
    if (await _loadAndResolveBookmark()) {
      try {
        if (await _resolvedBookmarkFile!.exists()) {
          print('✅ Resolved saved mobile path: ${_resolvedBookmarkFile!.path}');
          _grantedBasePath = _resolvedBookmarkFile!.path;
          currentPath = _resolvedBookmarkFile!.path;
          return currentPath;
        } else {
          print('⚠️ Saved mobile bookmark path no longer exists.');
          await SharedPreferences.getInstance().then((p) => p.remove(_mobileBookmarkKey));
        }
      } catch (e) {
         print('⚠️ Error checking existence of bookmarked path: $e');
         await SharedPreferences.getInstance().then((p) => p.remove(_mobileBookmarkKey));
      }
    }

    final dir = await getApplicationDocumentsDirectory();
    _grantedBasePath = dir.path;
    currentPath = dir.path;
    return dir.path;
  }

  @override
  Future<String?> requestDirectoryAccess({String? initialDirectory}) async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select a Folder',
      initialDirectory: initialDirectory,
    );
    
    if (path != null) {
      try {
        final String bookmarkData = await _bookmarks.bookmark(Directory(path));
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_mobileBookmarkKey, bookmarkData);
        print('✅ Saved mobile bookmark for: $path');
        _grantedBasePath = path;
        currentPath = path;
        await _loadAndResolveBookmark(); 
      } catch (e) {
        print('❌ Error saving mobile bookmark: $e');
      }
    }
    return path; 
  }

  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async {
    currentPath = path; 
    
    if (_resolvedBookmarkFile == null) {
      await _loadAndResolveBookmark();
    }
    
    try {
      if (_resolvedBookmarkFile != null && path.startsWith(_resolvedBookmarkFile!.path)) {
        await _bookmarks.startAccessingSecurityScopedResource(_resolvedBookmarkFile!);
      }
      
      final dir = Directory(path);
      final entities = await dir.list().toList();
      
      if (_resolvedBookmarkFile != null && path.startsWith(_resolvedBookmarkFile!.path)) {
        await _bookmarks.stopAccessingSecurityScopedResource(_resolvedBookmarkFile!);
      }
      
      return entities;
    } catch (e) {
      print('❌ Failed to list mobile directory: $e');
      if (_resolvedBookmarkFile != null && path.startsWith(_resolvedBookmarkFile!.path)) {
         await _bookmarks.stopAccessingSecurityScopedResource(_resolvedBookmarkFile!);
      }
      rethrow;
    }
  }
  
  @override
  Future<Uint8List> readFile(String path, {FileItem? fileItem}) async {
    if (_resolvedBookmarkFile == null) {
      await _loadAndResolveBookmark();
    }

    if (_resolvedBookmarkFile != null && path.startsWith(_resolvedBookmarkFile!.path)) {
      try {
        await _bookmarks.startAccessingSecurityScopedResource(_resolvedBookmarkFile!);
        final data = await File(path).readAsBytes();
        await _bookmarks.stopAccessingSecurityScopedResource(_resolvedBookmarkFile!);
        return data;
      } catch (e) {
        try {
          await _bookmarks.stopAccessingSecurityScopedResource(_resolvedBookmarkFile!);
        } catch (_) {}
        rethrow;
      }
    }
    
    return File(path).readAsBytes();
  }

  @override
  Future<void> saveFile(String path, Uint8List data) async {
    if (_resolvedBookmarkFile == null) await _loadAndResolveBookmark();

    if (_resolvedBookmarkFile != null && path.startsWith(_resolvedBookmarkFile!.path)) {
      try {
        await _bookmarks.startAccessingSecurityScopedResource(_resolvedBookmarkFile!);
        final file = File(path);
        if (!await file.parent.exists()) await file.parent.create(recursive: true);
        await file.writeAsBytes(data);
        await _bookmarks.stopAccessingSecurityScopedResource(_resolvedBookmarkFile!);
        return;
      } catch (e) {
        try { await _bookmarks.stopAccessingSecurityScopedResource(_resolvedBookmarkFile!); } catch (_) {}
        rethrow;
      }
    }
    final file = File(path);
    if (!await file.parent.exists()) await file.parent.create(recursive: true);
    await file.writeAsBytes(data);
  }

  @override
  Future<bool> hasAccessToPath(String path) async {
    if (path.startsWith(currentPath)) return true;
    if (_grantedBasePath != null && path.startsWith(_grantedBasePath!)) return true;
    try {
      await Directory(path).stat();
      return true;
    } catch (e) {
      return false;
    }
  }
  
  @override
  Future<String> getSafeFallbackDirectory() async {
     return (await getApplicationDocumentsDirectory()).path;
  }
}