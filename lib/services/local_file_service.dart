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

  // Helper for Web to get metadata without stat()
  Map<String, dynamic> getWebMetadata(String path) => {};
  
  factory LocalFileService() {
    if (kIsWeb) {
      return WebFileService();
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

// --- Web Implementation (Stubbed) ---
class WebFileService implements LocalFileService {
  // Stores directory structure: Key='/Photos', Value=[Entity('img.jpg')]
  final Map<String, List<FileSystemEntity>> _virtualTree = {};
  
  // Stores actual file references: Key='/Photos/img.jpg', Value=FileObject
  final Map<String, html.File> _fileRefs = {};

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

  @override
  Future<String?> requestDirectoryAccess({String? initialDirectory}) async {
    final completer = Completer<String?>();
    final input = html.FileUploadInputElement();
    
    input.setAttribute('webkitdirectory', ''); 
    input.setAttribute('directory', '');      
    input.multiple = true;  
    
    // Handle cancel/close somewhat (imperfect on web)
    bool isSelected = false;
    
    input.onChange.listen((e) {
      isSelected = true;
      if (input.files == null || input.files!.isEmpty) {
        completer.complete(null);
        return;
      }

      // RESET EVERYTHING
      _virtualTree.clear();
      _fileRefs.clear();

      String rootName = 'root';
      // Detect root folder name
      if (input.files!.isNotEmpty) {
        final firstPath = input.files!.first.relativePath ?? input.files!.first.name;
        rootName = firstPath.split('/')[0];
      }

      for (final file in input.files!) {
        // relativePath: "RootFolder/Sub/File.txt"
        final relPath = file.relativePath ?? file.name;
        
        // Full Virtual Path: "/RootFolder/Sub/File.txt"
        final fullPath = '/$relPath';
        
        _fileRefs[fullPath] = file;

        final parts = relPath.split('/');
        String parentPath = '/'; // Start at absolute root
        
        for (int i = 0; i < parts.length; i++) {
          final partName = parts[i];
          final isFile = (i == parts.length - 1);
          
          // Current item path: "/RootFolder" or "/RootFolder/Sub"
          final currentItemPath = parentPath == '/' ? '/$partName' : '$parentPath/$partName';

          // Ensure parent list exists
          if (!_virtualTree.containsKey(parentPath)) {
            _virtualTree[parentPath] = [];
          }

          // Check for duplicates in this folder
          final exists = _virtualTree[parentPath]!.any((e) => e.path == currentItemPath);

          if (!exists) {
            if (isFile) {
              _virtualTree[parentPath]!.add(File(currentItemPath));
            } else {
              _virtualTree[parentPath]!.add(Directory(currentItemPath));
            }
          }
          
          // Advance
          parentPath = currentItemPath;
        }
      }

      // Set current path to the actual selected folder name (e.g. "/Photos")
      // NOT just "/"
      final startPath = '/$rootName';
      currentPath = startPath;
      completer.complete(startPath);
    });

    input.click();
    
    // On Web, we can't easily detect "Cancel", so we rely on the user picking something.
    return completer.future;
  }

  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async {
    // Normalize path: ensure no trailing slash (unless root)
    String lookup = path;
    if (lookup.length > 1 && lookup.endsWith('/')) {
      lookup = lookup.substring(0, lookup.length - 1);
    }
    
    return _virtualTree[lookup] ?? [];
  }

  @override
  Future<bool> hasAccessToPath(String path) async {
    // On virtual FS, we have access if it exists in our tree or file refs
    // Normalize logic
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
         throw Exception('No bookmark found. Please grant access.');
      }
    }

    if (!path.startsWith(_resolvedBookmarkFile!.path)) {
      throw Exception('Path $path is outside of granted bookmark ${_resolvedBookmarkFile!.path}.');
    }

    try {
      await _bookmarks.startAccessingSecurityScopedResource(_resolvedBookmarkFile!);
      // print('🔐 Started security access for ${_resolvedBookmarkFile!.path}');

      final dir = Directory(path);
      final entities = await dir.list().toList();
      
      await _bookmarks.stopAccessingSecurityScopedResource(_resolvedBookmarkFile!);
      // print('🔓 Stopped security access for ${_resolvedBookmarkFile!.path}');
      
      return entities;
    } catch (e) {
      print('❌ Failed to list directory with bookmark: $e');
      try {
        await _bookmarks.stopAccessingSecurityScopedResource(_resolvedBookmarkFile!);
      } catch (e2) { /* ignore */ }
      rethrow; 
    }
  }

  @override
  Future<Uint8List> readFile(String path, {FileItem? fileItem}) async {
    if (_resolvedBookmarkFile == null) {
      await _loadAndResolveBookmark();
    }
    
    // If we have a secure bookmark, wrap the read operation
    if (_resolvedBookmarkFile != null && path.startsWith(_resolvedBookmarkFile!.path)) {
      try {
        await _bookmarks.startAccessingSecurityScopedResource(_resolvedBookmarkFile!);
        final data = await File(path).readAsBytes();
        await _bookmarks.stopAccessingSecurityScopedResource(_resolvedBookmarkFile!);
        return data;
      } catch (e) {
        // Ensure we stop accessing even if read fails
        try {
          await _bookmarks.stopAccessingSecurityScopedResource(_resolvedBookmarkFile!);
        } catch (_) {}
        rethrow;
      }
    }
    
    // Fallback if no bookmark is involved (e.g. non-sandboxed parts)
    return File(path).readAsBytes();
  }

  @override
  Future<bool> hasAccessToPath(String path) async {
    if (_grantedBasePath == null) {
      _grantedBasePath = await MacOSBookmarkService.getLastGrantedDirectory();
    }
    if (_grantedBasePath == null) return false;
    return path.startsWith(_grantedBasePath!);
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