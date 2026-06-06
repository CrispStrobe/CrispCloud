// services/local_file_service_native.dart
//
// All native (non-web) LocalFileService implementations:
// MacosFileService, DesktopFileService, MobileFileService

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:macos_secure_bookmarks/macos_secure_bookmarks.dart';
import '../models/file_item.dart';
import 'bookmark_service.dart';
import 'local_file_service.dart';
import 'macos_bookmark_service.dart';

LocalFileService createPlatformFileService() {
  if (Platform.isMacOS) return MacosFileService();
  if (Platform.isAndroid || Platform.isIOS) return MobileFileService();
  if (Platform.isWindows || Platform.isLinux) return DesktopFileService();
  throw UnsupportedError('Unsupported platform');
}

// --- macOS Implementation ---
class MacosFileService implements LocalFileService {
  String? _grantedBasePath;
  final _bookmarks = SecureBookmarks();
  FileSystemEntity? _resolvedBookmarkFile;

  @override
  String currentPath = Platform.environment['HOME'] ?? '/';

  @override
  String? get grantedBasePath => _grantedBasePath;

  @override
  Map<String, dynamic> getWebMetadata(String path) => {};

  @override
  Object? getWebFileRef(String path) => null;

  @override
  Future<void> refresh() async {}

  Future<bool> _loadAndResolveBookmark() async {
    try {
      _resolvedBookmarkFile = await MacOSBookmarkService.getResolvedBookmark();
      if (_resolvedBookmarkFile != null) {
        _grantedBasePath = _resolvedBookmarkFile!.path;
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Failed to load or resolve bookmark: $e');
      _resolvedBookmarkFile = null;
      _grantedBasePath = null;
      return false;
    }
  }

  @override
  Future<String> getInitialPath() async {
    final grantedPath = await MacOSBookmarkService.getLastGrantedDirectory();
    if (grantedPath != null) {
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
      await _loadAndResolveBookmark();
    }

    if (_resolvedBookmarkFile != null && path.startsWith(_resolvedBookmarkFile!.path)) {
      try {
        await _bookmarks.startAccessingSecurityScopedResource(_resolvedBookmarkFile!);
        final entities = await Directory(path).list().toList();
        await _bookmarks.stopAccessingSecurityScopedResource(_resolvedBookmarkFile!);
        return entities;
      } catch (e) {
        try { await _bookmarks.stopAccessingSecurityScopedResource(_resolvedBookmarkFile!); } catch (_) {}
      }
    }

    try {
      return await Directory(path).list().toList();
    } catch (e) {
      debugPrint('Failed to list directory: $e');
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
    _grantedBasePath ??= await MacOSBookmarkService.getLastGrantedDirectory();
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
  String currentPath = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '/';

  @override
  String? get grantedBasePath => null;

  @override
  Map<String, dynamic> getWebMetadata(String path) => {};

  @override
  Object? getWebFileRef(String path) => null;

  @override
  Future<void> refresh() async {}

  @override
  Future<String> getInitialPath() async {
    final lastPath = await BookmarkService.getLastPath();
    try {
      if (lastPath != null && await Directory(lastPath).exists()) {
        currentPath = lastPath;
        return lastPath;
      }
    } catch (e) {
      debugPrint('Could not access last path, using fallback. Error: $e');
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
    if (!await file.parent.exists()) await file.parent.create(recursive: true);
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

  @override
  Object? getWebFileRef(String path) => null;

  @override
  Future<void> refresh() async {}

  Future<bool> _loadAndResolveBookmark() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bookmarkBase64 = prefs.getString(_mobileBookmarkKey);
      if (bookmarkBase64 == null) return false;
      _resolvedBookmarkFile = await _bookmarks.resolveBookmark(bookmarkBase64);
      return true;
    } catch (e) {
      debugPrint('Failed to load or resolve mobile bookmark: $e');
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
          _grantedBasePath = _resolvedBookmarkFile!.path;
          currentPath = _resolvedBookmarkFile!.path;
          return currentPath;
        } else {
          await SharedPreferences.getInstance().then((p) => p.remove(_mobileBookmarkKey));
        }
      } catch (e) {
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
        _grantedBasePath = path;
        currentPath = path;
        await _loadAndResolveBookmark();
      } catch (e) {
        debugPrint('Error saving mobile bookmark: $e');
      }
    }
    return path;
  }

  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async {
    currentPath = path;

    if (_resolvedBookmarkFile == null) await _loadAndResolveBookmark();

    try {
      if (_resolvedBookmarkFile != null && path.startsWith(_resolvedBookmarkFile!.path)) {
        await _bookmarks.startAccessingSecurityScopedResource(_resolvedBookmarkFile!);
      }

      final entities = await Directory(path).list().toList();

      if (_resolvedBookmarkFile != null && path.startsWith(_resolvedBookmarkFile!.path)) {
        await _bookmarks.stopAccessingSecurityScopedResource(_resolvedBookmarkFile!);
      }

      return entities;
    } catch (e) {
      debugPrint('Failed to list mobile directory: $e');
      if (_resolvedBookmarkFile != null && path.startsWith(_resolvedBookmarkFile!.path)) {
        await _bookmarks.stopAccessingSecurityScopedResource(_resolvedBookmarkFile!);
      }
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
