// lib/providers/panel_provider.dart
//
// Per-panel state: file listing, selection, sort, tabs, navigation.
// Used as a family provider keyed by PanelSide.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../models/panel_tab.dart';
import '../services/local_file_service.dart';
import 'auth_provider.dart';
import 'core_providers.dart';
import 'error_provider.dart';

enum SortBy { name, size, date, extension }
enum SortOrder { ascending, descending }

class PanelNotifier extends ChangeNotifier {
  final Ref _ref;
  final PanelSide side;

  final LocalFileService _localFileService;

  List<FileItem>? _files;
  final Set<FileItem> _selection = {};
  FileItem? _lastSelected;
  FileItem? _itemToScrollTo;

  SortBy _sortBy = SortBy.name;
  SortOrder _sortOrder = SortOrder.ascending;

  // Tabs
  int _tabIdCounter = 0;
  final List<PanelTab> _tabs = [];
  String _activeTabId = '';

  final _refreshLock = _AsyncLock();

  PanelNotifier(this._ref, this.side)
      : _localFileService = _ref.read(localFileServiceProvider) {
    _initFirstTab();
    if (side == PanelSide.local) {
      _initializeLocalPath();
    }
  }

  // --- Getters ---
  List<FileItem>? get files => _files;
  Set<FileItem> get selection => _selection;
  FileItem? get lastSelected => _lastSelected;
  FileItem? get itemToScrollTo => _itemToScrollTo;
  void clearItemToScrollTo() { _itemToScrollTo = null; }

  SortBy get sortBy => _sortBy;
  SortOrder get sortOrder => _sortOrder;

  String get currentPath {
    if (side == PanelSide.local) return _localFileService.currentPath;
    return _remotePath;
  }
  String _remotePath = '/';

  List<PanelTab> get tabs => _tabs;
  String get activeTabId => _activeTabId;
  PanelTab? get activeTab =>
      _tabs.isEmpty ? null : _tabs.firstWhere(
        (t) => t.id == _activeTabId,
        orElse: () => _tabs.first,
      );

  // --- Sort ---
  void setSortBy(SortBy sortBy) {
    _sortBy = sortBy;
    _sortFiles();
    notifyListeners();
  }

  void toggleSortOrder() {
    _sortOrder = _sortOrder == SortOrder.ascending
        ? SortOrder.descending
        : SortOrder.ascending;
    _sortFiles();
    notifyListeners();
  }

  void _sortFiles() {
    if (_files == null || _files!.isEmpty) return;
    _files!.sort((a, b) {
      if (a.isFolder && !b.isFolder) return -1;
      if (!a.isFolder && b.isFolder) return 1;

      int comparison = 0;
      switch (_sortBy) {
        case SortBy.name:
          comparison = (a.name).toLowerCase().compareTo((b.name).toLowerCase());
          break;
        case SortBy.size:
          comparison = (a.size ?? 0).compareTo(b.size ?? 0);
          break;
        case SortBy.date:
          comparison = (a.updatedAt ?? DateTime(1970)).compareTo(b.updatedAt ?? DateTime(1970));
          break;
        case SortBy.extension:
          if (a.isFolder || b.isFolder) {
            comparison = 0;
          } else {
            final extA = a.name.contains('.') ? a.name.split('.').last.toLowerCase() : '';
            final extB = b.name.contains('.') ? b.name.split('.').last.toLowerCase() : '';
            comparison = extA.compareTo(extB);
          }
          break;
      }
      return _sortOrder == SortOrder.ascending ? comparison : -comparison;
    });
  }

  // --- Selection ---
  bool isSelected(FileItem item) => _selection.contains(item);

  void toggleSelection(FileItem item, {bool shiftKey = false, bool ctrlKey = false}) {
    if (shiftKey && _lastSelected != null && _files != null) {
      final startIdx = _files!.indexOf(_lastSelected!);
      final endIdx = _files!.indexOf(item);
      if (startIdx != -1 && endIdx != -1) {
        final start = startIdx < endIdx ? startIdx : endIdx;
        final end = startIdx < endIdx ? endIdx : startIdx;
        for (var i = start; i <= end; i++) {
          _selection.add(_files![i]);
        }
      }
    } else if (ctrlKey) {
      if (_selection.contains(item)) {
        _selection.remove(item);
      } else {
        _selection.add(item);
      }
    } else {
      _selection.clear();
      _selection.add(item);
    }
    _lastSelected = item;
    notifyListeners();
  }

  void selectAll() {
    if (_files != null) {
      _selection.addAll(_files!);
      notifyListeners();
    }
  }

  void clearSelection() {
    _selection.clear();
    _lastSelected = null;
    notifyListeners();
  }

  // --- Navigation ---
  Future<void> refresh() async {
    await _refreshLock.synchronized(() async {
      if (side == PanelSide.local) {
        await _localFileService.refresh();
        await _loadLocalFiles();
      } else {
        await _loadRemoteFiles();
      }
    });
  }

  Future<void> navigateUp() async {
    if (side == PanelSide.local) {
      final parent = p.dirname(currentPath);
      if (parent != currentPath && parent != '.') {
        await navigateToPath(parent);
      }
    } else {
      if (_remotePath != '/') {
        _remotePath = p.dirname(_remotePath);
        if (_remotePath.isEmpty) _remotePath = '/';
        await refresh();
      }
    }
  }

  Future<void> navigateToPath(String path, {FileItem? selectItem}) async {
    if (side == PanelSide.local) {
      if (!kIsWeb && !await _localFileService.hasAccessToPath(path)) {
        final newGrant = await _localFileService.requestDirectoryAccess(initialDirectory: path);
        if (newGrant != null) {
          path = newGrant;
        } else {
          _ref.read(errorProvider).addError(
            'Cannot access paths outside the granted directory.',
          );
          return;
        }
      } else if (kIsWeb && !await _localFileService.hasAccessToPath(path)) {
        return;
      }
      _localFileService.currentPath = path;
      await _loadLocalFiles();
    } else {
      _remotePath = path;
      await _loadRemoteFiles();
    }

    if (selectItem != null && _files != null) {
      try {
        final found = _files!.firstWhere(
          (f) => side == PanelSide.local
              ? f.path == selectItem.path
              : f.uuid == selectItem.uuid,
        );
        _selection.clear();
        _selection.add(found);
        _lastSelected = found;
        _itemToScrollTo = found;
      } catch (_) {}
    }

    _syncTabPath();
    notifyListeners();
  }

  Future<void> navigateInto(FileItem item) async {
    if (!item.isFolder) return;
    if (side == PanelSide.local) {
      if (item.path != null) await navigateToPath(item.path!);
    } else {
      await navigateToPath(p.posix.join(_remotePath, item.name));
    }
  }

  Future<void> pickLocalDirectory() async {
    try {
      final dir = await _localFileService.requestDirectoryAccess(
        initialDirectory: _localFileService.currentPath,
      );
      if (dir != null) {
        _localFileService.currentPath = dir;
        await _loadLocalFiles();
        notifyListeners();
      }
    } catch (e) {
      _ref.read(errorProvider).addError('Error picking directory: $e');
    }
  }

  // --- File operations (local panel helpers) ---
  Future<void> deleteFiles(List<FileItem> files) async {
    final errors = _ref.read(errorProvider);
    if (kIsWeb && side == PanelSide.local) return;
    try {
      final client = _ref.read(authProvider).client;
      for (final file in files) {
        if (side == PanelSide.local) {
          if (file.isFolder) {
            await Directory(file.path!).delete(recursive: true);
          } else {
            await File(file.path!).delete();
          }
        } else {
          final deletePath = file.path ?? p.posix.join(_remotePath, file.name);
          await client.deletePath(deletePath);
        }
      }
      await refresh();
      clearSelection();
    } catch (e) {
      errors.addError('Delete failed: $e');
    }
  }

  Future<void> renameFile(FileItem file, String newName) async {
    if (kIsWeb && side == PanelSide.local) return;
    try {
      if (side == PanelSide.local) {
        final newPath = p.join(p.dirname(file.path!), newName);
        if (file.isFolder) {
          await Directory(file.path!).rename(newPath);
        } else {
          await File(file.path!).rename(newPath);
        }
      } else {
        final client = _ref.read(authProvider).client;
        final sourcePath = file.path ?? p.posix.join(_remotePath, file.name);
        await client.renamePath(sourcePath, newName);
      }
      await refresh();
    } catch (e) {
      _ref.read(errorProvider).addError('Rename failed: $e');
    }
  }

  Future<void> createFolder(String name) async {
    if (kIsWeb && side == PanelSide.local) return;
    try {
      if (side == PanelSide.local) {
        await Directory(p.join(currentPath, name)).create();
      } else {
        final client = _ref.read(authProvider).client;
        await client.createFolderPath(p.posix.join(_remotePath, name));
      }
      await refresh();
    } catch (e) {
      _ref.read(errorProvider).addError('Create folder failed: $e');
    }
  }

  Future<void> moveFiles(List<FileItem> files, String targetPath) async {
    if (kIsWeb && side == PanelSide.local) return;
    try {
      for (final file in files) {
        if (side == PanelSide.local) {
          final newPath = p.join(targetPath, file.name);
          if (file.isFolder) {
            await Directory(file.path!).rename(newPath);
          } else {
            await File(file.path!).rename(newPath);
          }
        } else {
          final client = _ref.read(authProvider).client;
          final sourcePath = file.path ?? p.posix.join(_remotePath, file.name);
          await client.movePath(sourcePath, targetPath);
        }
      }
      await refresh();
      clearSelection();
    } catch (e) {
      _ref.read(errorProvider).addError('Move failed: $e');
      await refresh();
    }
  }

  Future<void> copyFiles(List<FileItem> files, String targetPath) async {
    if (kIsWeb && side == PanelSide.local) return;
    try {
      for (final file in files) {
        if (side == PanelSide.local) {
          final newPath = p.join(targetPath, file.name);
          if (file.isFolder) {
            await _copyDirectory(file.path!, newPath);
          } else {
            await File(file.path!).copy(newPath);
          }
        } else {
          if (kIsWeb) throw UnsupportedError('Remote copy not supported on web');
          final client = _ref.read(authProvider).client;
          final tempPath = p.join(Directory.systemTemp.path, file.name);
          await client.downloadFileByPath(p.posix.join(_remotePath, file.name), tempPath);
          final data = await File(tempPath).readAsBytes();
          await client.uploadFile(data, file.name, targetPath);
          await File(tempPath).delete();
        }
      }
      await refresh();
    } catch (e) {
      _ref.read(errorProvider).addError('Copy failed: $e');
    }
  }

  Future<void> _copyDirectory(String source, String target) async {
    if (kIsWeb) return;
    await Directory(target).create(recursive: true);
    final entities = await Directory(source).list().toList();
    for (final entity in entities) {
      if (entity is File) {
        await entity.copy(p.join(target, p.basename(entity.path)));
      } else if (entity is Directory) {
        await _copyDirectory(entity.path, p.join(target, p.basename(entity.path)));
      }
    }
  }

  // --- Tabs ---
  String _nextTabId() => 'tab_${_tabIdCounter++}';

  void _initFirstTab() {
    final id = _nextTabId();
    final path = side == PanelSide.local ? _localFileService.currentPath : _remotePath;
    _tabs.add(PanelTab(id: id, path: path));
    _activeTabId = id;
  }

  void addTab({String? path}) {
    final id = _nextTabId();
    _tabs.add(PanelTab(id: id, path: path ?? currentPath));
    _activeTabId = id;
    notifyListeners();
  }

  void closeTab(String tabId) {
    if (_tabs.length <= 1) return;
    final tab = _tabs.firstWhere((t) => t.id == tabId, orElse: () => _tabs.first);
    if (tab.isPinned) return;
    final idx = _tabs.indexOf(tab);
    _tabs.remove(tab);
    if (_activeTabId == tabId) {
      final newIdx = idx.clamp(0, _tabs.length - 1);
      _activeTabId = _tabs[newIdx].id;
    }
    notifyListeners();
  }

  void selectTab(String tabId) {
    _activeTabId = tabId;
    final tab = activeTab;
    if (tab != null) {
      if (side == PanelSide.local) {
        _localFileService.currentPath = tab.path;
      } else {
        _remotePath = tab.path;
      }
    }
    notifyListeners();
    refresh();
  }

  void toggleTabPin(String tabId) {
    final tab = _tabs.firstWhere((t) => t.id == tabId, orElse: () => _tabs.first);
    tab.isPinned = !tab.isPinned;
    notifyListeners();
  }

  void _syncTabPath() {
    final tab = activeTab;
    if (tab != null) {
      tab.path = currentPath;
      tab.updateLabel();
    }
  }

  // --- Internal loading ---
  Future<void> _initializeLocalPath() async {
    try {
      await _localFileService.getInitialPath();
      if (!kIsWeb && Platform.isMacOS && _localFileService.grantedBasePath == null) {
        _ref.read(errorProvider).addError(
          'Please select a base directory to grant access (e.g., your home folder)',
        );
        final grantedPath = await _localFileService.requestDirectoryAccess(
          initialDirectory: await _localFileService.getSafeFallbackDirectory(),
        );
        if (grantedPath != null) {
          _ref.read(errorProvider).clearErrors();
        } else {
          _localFileService.currentPath = await _localFileService.getSafeFallbackDirectory();
          _ref.read(errorProvider).clearErrors();
          _ref.read(errorProvider).addError('Access cancelled. Using fallback directory.');
        }
      }
      await _loadLocalFiles();
      notifyListeners();
    } catch (e) {
      _localFileService.currentPath = await _localFileService.getSafeFallbackDirectory();
      _ref.read(errorProvider).addError(e.toString());
      notifyListeners();
    }
  }

  Future<void> _loadLocalFiles() async {
    try {
      final entities = await _localFileService.listDirectory(currentPath);
      if (entities == null) {
        _files = [];
        if (!kIsWeb) {
          _ref.read(errorProvider).addError('Local file access is not supported on this platform.');
        }
        notifyListeners();
        return;
      }

      final items = <FileItem>[];
      for (final entity in entities) {
        try {
          final name = p.basename(entity.path);
          if (name.startsWith('.')) continue;

          if (kIsWeb) {
            final isFolder = entity is Directory;
            int size = 0;
            DateTime updated = DateTime.now();
            if (!isFolder) {
              final meta = _localFileService.getWebMetadata(entity.path);
              size = meta['size'] ?? 0;
              updated = meta['modified'] ?? DateTime.now();
            }
            items.add(FileItem(name: name, path: entity.path, isFolder: isFolder, size: size, updatedAt: updated));
            continue;
          }

          final stat = await entity.stat();
          if (stat.type == FileSystemEntityType.directory) {
            items.add(FileItem(name: name, path: entity.path, isFolder: true, updatedAt: stat.modified));
          } else if (stat.type == FileSystemEntityType.file) {
            items.add(FileItem(name: name, path: entity.path, isFolder: false, size: stat.size, updatedAt: stat.modified));
          }
        } catch (_) {
          continue;
        }
      }

      _files = items;
      _sortFiles();
      _ref.read(errorProvider).clearErrors();
      notifyListeners();
    } catch (e) {
      if (!kIsWeb && (e is PathAccessException || e.toString().contains('Operation not permitted'))) {
        _files = [];
        _ref.read(errorProvider).addError('Permission denied. Use the Browse button to grant access.');
        notifyListeners();
        return;
      }
      _files = [];
      _ref.read(errorProvider).addError(e.toString());
      notifyListeners();
    }
  }

  Future<void> _loadRemoteFiles() async {
    final auth = _ref.read(authProvider);
    try {
      if (!auth.client.isAuthenticated && !auth.isConnected) {
        _files = [];
        notifyListeners();
        return;
      }

      final result = await auth.client.listPath(_remotePath);

      final folders = (result['folders'] as List<dynamic>?)?.map((item) {
        final map = item as Map<String, dynamic>;
        DateTime? folderDate;
        final rawDate = map['modificationTime'] ?? map['lastModified'] ?? map['timestamp'];
        if (rawDate != null) {
          try {
            if (rawDate is int) folderDate = DateTime.fromMillisecondsSinceEpoch(rawDate);
            else folderDate = DateTime.parse(rawDate.toString());
          } catch (_) {}
        }
        return FileItem(name: map['name'] ?? 'Unknown', isFolder: true, uuid: map['uuid'], updatedAt: folderDate);
      }).toList() ?? [];

      final files = (result['files'] as List<dynamic>?)?.map((item) {
        final map = item as Map<String, dynamic>;
        final fileName = map['name'] ?? 'Unknown';
        final rawType = map['fileType'] ?? map['type'] ?? '';
        final fileType = rawType.toString().toLowerCase();
        String fullName = fileName;
        if (fileType.isNotEmpty && fileType != 'file' && !fileName.toLowerCase().endsWith('.$fileType')) {
          fullName = '$fileName.$rawType';
        }
        DateTime? fileDate;
        final rawDate = map['modificationTime'] ?? map['lastModified'];
        if (rawDate != null) {
          try {
            if (rawDate is int) fileDate = DateTime.fromMillisecondsSinceEpoch(rawDate);
            else fileDate = DateTime.parse(rawDate.toString());
          } catch (_) {}
        }
        return FileItem(name: fullName, isFolder: false, size: map['size'] as int?, uuid: map['uuid'], updatedAt: fileDate);
      }).toList() ?? [];

      _files = [...folders, ...files];
      _sortFiles();
      _ref.read(errorProvider).clearErrors();
      notifyListeners();
    } catch (e) {
      debugPrint('Refresh Error: $e');
      _files = [];
      _ref.read(errorProvider).addError(e.toString());
      notifyListeners();
    }
  }
}

class _AsyncLock {
  Completer<void>? _completer;
  Future<T> synchronized<T>(Future<T> Function() action) async {
    while (_completer != null) {
      await _completer!.future;
    }
    _completer = Completer<void>();
    try {
      return await action();
    } finally {
      final c = _completer!;
      _completer = null;
      c.complete();
    }
  }
}

final panelProvider = ChangeNotifierProvider.family<PanelNotifier, PanelSide>((ref, side) {
  return PanelNotifier(ref, side);
});
