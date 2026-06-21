// services/app_state.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/file_item.dart';
import '../models/operation_progress.dart';
import '../models/panel_side.dart';
import '../models/panel_tab.dart';
import '../models/sort.dart';
export '../models/sort.dart';
import '../utils/async_lock.dart';
import '../utils/formatters.dart' as fmt;

import 'cloud_storage_interface.dart';
import 'encrypted_storage_wrapper.dart';
import 'encryption_service.dart';
import 'filen_client_adapter.dart';
import 'filen_config_service.dart';
import 'ftp_client_adapter.dart';
import 'ftp_config_service.dart';
import 'dropbox_config_service.dart';
import 'gdrive_config_service.dart';
import 'internxt_client.dart';
import 'onedrive_config_service.dart';
import 'internxt_client_adapter.dart';
import 'local_file_service.dart';
import 'receive_service.dart';
import 's3_client_adapter.dart';
import 's3_config_service.dart';
import 'secure_storage_service.dart';
import 'sftp_client_adapter.dart';
import 'sftp_config_service.dart';
import 'share_service.dart';
import 'transfer_queue.dart';
import 'webdav_client_adapter.dart';
import 'webdav_config_service.dart';

class AppError {
  final String message;
  final DateTime timestamp;
  final String? context;

  AppError(this.message, {this.context}) : timestamp = DateTime.now();

  @override
  String toString() => message;
}

class AppState extends ChangeNotifier {
  // Async locks — one per critical method to avoid deadlocks when locked
  // methods call each other (switchProvider -> _attemptAutoLogin -> refreshPanel).
  final _switchProviderLock = AsyncLock();
  final _refreshPanelLock = AsyncLock();
  final _autoLoginLock = AsyncLock();

  // Cloud storage abstraction
  CloudProvider _currentProvider = CloudProvider.filen;
  late CloudStorageClient _cloudClient;
  dynamic _config;
  String _configPath = ''; // Store path to recreate configs

  late final LocalFileService _localFileService;
  late final SecureStorage _secureStorage;
  final TransferQueue _transferQueue = TransferQueue();

  bool _isConnected = false;
  String? _userEmail;
  PanelSide _activePanel = PanelSide.local;

  String _remotePath = '/';
  // Per-instance local path — avoids sharing _localPath
  String _localPath = '/';

  List<FileItem>? _localFiles;
  List<FileItem>? _remoteFiles;

  final Set<FileItem> _localSelection = {};
  final Set<FileItem> _remoteSelection = {};
  
  FileItem? _lastSelectedLocal;
  FileItem? _lastSelectedRemote;

  final Set<FileItem> _selectedLocalFiles = {};
  final Set<FileItem> _selectedRemoteFiles = {};

  final List<OperationProgress> _operations = [];

  bool _isSearching = false;
  bool get isSearching => _isSearching;

  bool _showPreview = false;
  bool get showPreview => _showPreview;
  void togglePreview() {
    _showPreview = !_showPreview;
    notifyListeners();
  }

  // --- Tab management ---
  int _tabIdCounter = 0;
  final List<PanelTab> _localTabs = [];
  final List<PanelTab> _remoteTabs = [];
  String _activeLocalTabId = '';
  String _activeRemoteTabId = '';

  List<PanelTab> get localTabs => _localTabs;
  List<PanelTab> get remoteTabs => _remoteTabs;
  String get activeLocalTabId => _activeLocalTabId;
  String get activeRemoteTabId => _activeRemoteTabId;

  PanelTab? get activeLocalTab =>
      _localTabs.isEmpty ? null : _localTabs.firstWhere(
        (t) => t.id == _activeLocalTabId,
        orElse: () => _localTabs.first,
      );

  PanelTab? get activeRemoteTab =>
      _remoteTabs.isEmpty ? null : _remoteTabs.firstWhere(
        (t) => t.id == _activeRemoteTabId,
        orElse: () => _remoteTabs.first,
      );

  String _nextTabId() => 'tab_${_tabIdCounter++}';

  void _initTabs() {
    if (_localTabs.isEmpty) {
      final id = _nextTabId();
      _localTabs.add(PanelTab(id: id, path: _localPath));
      _activeLocalTabId = id;
    }
    if (_remoteTabs.isEmpty) {
      final id = _nextTabId();
      _remoteTabs.add(PanelTab(id: id, path: _remotePath));
      _activeRemoteTabId = id;
    }
  }

  void addTab(PanelSide side, {String? path}) {
    final tabs = side == PanelSide.local ? _localTabs : _remoteTabs;
    final currentPath = side == PanelSide.local ? localPath : _remotePath;
    final id = _nextTabId();
    tabs.add(PanelTab(id: id, path: path ?? currentPath));
    if (side == PanelSide.local) {
      _activeLocalTabId = id;
    } else {
      _activeRemoteTabId = id;
    }
    notifyListeners();
  }

  void closeTab(PanelSide side, String tabId) {
    final tabs = side == PanelSide.local ? _localTabs : _remoteTabs;
    if (tabs.length <= 1) return; // Keep at least one tab
    final tab = tabs.firstWhere((t) => t.id == tabId, orElse: () => tabs.first);
    if (tab.isPinned) return;
    final idx = tabs.indexOf(tab);
    tabs.remove(tab);
    // If closing active tab, activate the nearest one
    final activeId = side == PanelSide.local ? _activeLocalTabId : _activeRemoteTabId;
    if (activeId == tabId) {
      final newIdx = idx.clamp(0, tabs.length - 1);
      if (side == PanelSide.local) {
        _activeLocalTabId = tabs[newIdx].id;
      } else {
        _activeRemoteTabId = tabs[newIdx].id;
      }
    }
    notifyListeners();
  }

  void selectTab(PanelSide side, String tabId) {
    if (side == PanelSide.local) {
      _activeLocalTabId = tabId;
      final tab = activeLocalTab;
      if (tab != null) {
        _localPath = tab.path;
      }
    } else {
      _activeRemoteTabId = tabId;
      final tab = activeRemoteTab;
      if (tab != null) {
        _remotePath = tab.path;
      }
    }
    notifyListeners();
    refreshPanel(side);
  }

  void toggleTabPin(PanelSide side, String tabId) {
    final tabs = side == PanelSide.local ? _localTabs : _remoteTabs;
    final tab = tabs.firstWhere((t) => t.id == tabId, orElse: () => tabs.first);
    tab.isPinned = !tab.isPinned;
    notifyListeners();
  }

  /// Sync the active tab's path when navigating
  void _syncTabPath(PanelSide side) {
    if (side == PanelSide.local) {
      final tab = activeLocalTab;
      if (tab != null) {
        tab.path = localPath;
        tab.updateLabel();
      }
    } else {
      final tab = activeRemoteTab;
      if (tab != null) {
        tab.path = _remotePath;
        tab.updateLabel();
      }
    }
  }

  FileItem? _itemToScrollTo;
  FileItem? get itemToScrollTo => _itemToScrollTo;
  void clearItemToScrollTo() { _itemToScrollTo = null; }

  List<String> _receivedFiles = [];
  String? _receivedText;

  List<String> get receivedFiles => _receivedFiles;
  String? get receivedText => _receivedText;

  bool get hasLocalSelection => _selectedLocalFiles.isNotEmpty;
  bool get hasRemoteSelection => _selectedRemoteFiles.isNotEmpty;
  
  List<FileItem> get selectedLocalFiles => _selectedLocalFiles.toList();
  List<FileItem> get selectedRemoteFiles => _selectedRemoteFiles.toList();

  final List<AppError> _errors = [];
  String? get lastError => _errors.isEmpty ? null : _errors.last.message;
  List<AppError> get errors => List.unmodifiable(_errors);
  bool get hasErrors => _errors.isNotEmpty;

  void clearErrors() {
    _errors.clear();
    notifyListeners();
  }

  void clearLastError() {
    if (_errors.isNotEmpty) {
      _errors.removeLast();
      notifyListeners();
    }
  }

  SortBy _localSortBy = SortBy.name;
  SortOrder _localSortOrder = SortOrder.ascending;
  SortBy _remoteSortBy = SortBy.name;
  SortOrder _remoteSortOrder = SortOrder.ascending;

  SortBy getSort(PanelSide side) => 
      side == PanelSide.local ? _localSortBy : _remoteSortBy;
  
  SortOrder getSortOrder(PanelSide side) => 
      side == PanelSide.local ? _localSortOrder : _remoteSortOrder;

  void setSortBy(PanelSide side, SortBy sortBy) {
    if (side == PanelSide.local) {
      _localSortBy = sortBy;
      _sortFiles(_localFiles, _localSortBy, _localSortOrder);
    } else {
      _remoteSortBy = sortBy;
      _sortFiles(_remoteFiles, _remoteSortBy, _remoteSortOrder);
    }
    notifyListeners();
  }

  void toggleSortOrder(PanelSide side) {
    if (side == PanelSide.local) {
      _localSortOrder = _localSortOrder == SortOrder.ascending 
          ? SortOrder.descending 
          : SortOrder.ascending;
      _sortFiles(_localFiles, _localSortBy, _localSortOrder);
    } else {
      _remoteSortOrder = _remoteSortOrder == SortOrder.ascending 
          ? SortOrder.descending 
          : SortOrder.ascending;
      _sortFiles(_remoteFiles, _remoteSortBy, _remoteSortOrder);
    }
    notifyListeners();
  }

  void _sortFiles(List<FileItem>? files, SortBy sortBy, SortOrder order) {
    if (files == null || files.isEmpty) {
      debugPrint('⚠️ No files to sort');
      return;
    }

    try {
      debugPrint('🔄 Sorting ${files.length} files by $sortBy ($order)');
      
      files.sort((a, b) {
        try {
          if (a.isFolder && !b.isFolder) return -1;
          if (!a.isFolder && b.isFolder) return 1;

          int comparison = 0;
          
          switch (sortBy) {
            case SortBy.name:
              comparison = a.name.toLowerCase().compareTo(b.name.toLowerCase());
              break;
            case SortBy.size:
              final sizeA = a.size ?? 0;
              final sizeB = b.size ?? 0;
              comparison = sizeA.compareTo(sizeB);
              break;
            case SortBy.date:
              final dateA = a.updatedAt ?? DateTime(1970);
              final dateB = b.updatedAt ?? DateTime(1970);
              comparison = dateA.compareTo(dateB);
              break;
            case SortBy.extension:
              if (a.isFolder || b.isFolder) {
                comparison = 0;
              } else {
                final nameA = a.name;
                final nameB = b.name;
                final extA = nameA.contains('.') ? nameA.split('.').last.toLowerCase() : '';
                final extB = nameB.contains('.') ? nameB.split('.').last.toLowerCase() : '';
                comparison = extA.compareTo(extB);
              }
              break;
          }
          return order == SortOrder.ascending ? comparison : -comparison;
        } catch (e) {
          debugPrint('⚠️ Error comparing items: $e');
          return 0;
        }
      });
      
      debugPrint('✅ Sorting complete');
    } catch (e, stackTrace) {
      debugPrint('❌ Error in sorting function: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  Future<void> pickLocalDirectory() async {
    try {
      debugPrint('📂 Opening directory picker...');
      
      final selectedDirectory = await _localFileService.requestDirectoryAccess(
        initialDirectory: _localPath,
      );
      
      if (selectedDirectory != null) {
        debugPrint('📁 User selected: $selectedDirectory');
        _localPath = selectedDirectory;
        await _loadLocalFiles();
        notifyListeners();
      } else {
        debugPrint('⚠️ User cancelled directory selection');
      }
    } catch (e) {
      debugPrint('❌ Error picking directory: $e');
      _errors.add(AppError('Error picking directory: $e'));
      notifyListeners();
    }
  }

  void initializeReceiving() {
    if (kIsWeb) {
      debugPrint('⚠️ Receive sharing intent not supported on web.');
      return;
    }
    
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        ReceiveService.initialize(
          onFilesReceived: (files) {
            _receivedFiles.addAll(files);
            notifyListeners();
          },
          onTextReceived: (text) {
            debugPrint('Received text: $text');
          },
        );
      } else {
        debugPrint('⚠️ Receive sharing intent not supported on this platform.');
      }
    } catch (e) {
      debugPrint('Could not initialize receive service: $e');
    }
  }

  Future<void> shareFiles(List<FileItem> files) async {
    if (kIsWeb) {
       debugPrint('⚠️ File sharing not supported on web.');
       return;
    }
    
    if (Platform.isAndroid || Platform.isIOS) {
      final paths = files.map((f) => f.path!).where((p) => p.isNotEmpty).toList();
      if (paths.isNotEmpty) {
        await ShareService.shareFiles(paths);
      }
    } else {
      debugPrint('⚠️ File sharing not supported on this platform.');
    }
  }

  void clearReceivedFiles() {
    _receivedFiles = [];
    _receivedText = null;
    notifyListeners();
  }

  @override
  void dispose() {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      ReceiveService.dispose();
    }
    super.dispose();
  }

  AppState({required dynamic config, CloudProvider? initialProvider, required SecureStorage secureStorage})
      : _config = config,
        _currentProvider = initialProvider ?? CloudProvider.filen,
        _localFileService = LocalFileService(),
        _secureStorage = secureStorage {

    // EXTRACT PATH: Attempt to extract, but handle failure robustly
    try {
        if (config is FilenConfigService) {
          _configPath = config.configPath;
        } else if (config is FTPConfigService) {
          _configPath = config.configPath;
        } else if (config is SFTPConfigService) {
          _configPath = config.configPath;
        } else if (config is ConfigService) {
          _configPath = config.configPath;
        }
        // Fallback: try dynamic access if types didn't match due to import issues
        else {
            try {
                _configPath = (config as dynamic).configPath;
            } catch (e) {
                debugPrint('AppState: Could not extract configPath: $e');
            }
        }
    } catch (e) {
        debugPrint("⚠️ AppState: Error extracting config path: $e");
    }

    // FALLBACK if extraction failed
    if (_configPath.isEmpty) {
        debugPrint("⚠️ AppState: Config path is empty. Using fallback default.");
        if (!kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows)) {
             final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
             _configPath = p.join(home, '.cloud-storage-config');
        } else {
             _configPath = '.cloud-storage-config';
        }
    }
    
    debugPrint("🔧 AppState initialized with config path: $_configPath");
    
    // Initialize cloud client based on provider
    _cloudClient = CloudStorageFactory.create(_currentProvider, config: config);
    
    _activePanel = PanelSide.local;
    _initTabs();

    _initializeLocalPath();
    _attemptAutoLogin();
  }

  // NEW: Method to switch cloud providers
  Future<void> switchProvider(CloudProvider provider) async {
    if (_currentProvider == provider) return;

    await _switchProviderLock.synchronized(() async {
      // Re-check after acquiring the lock in case another call already switched.
      if (_currentProvider == provider) return;

      debugPrint('🔄 Switching cloud provider to $provider');

      if (_isConnected) {
        await logout();
      }

      // 1. Save Preference
      final prefs = await SharedPreferences.getInstance();
      String providerKey;
      switch (provider) {
        case CloudProvider.dropbox: providerKey = 'dropbox'; break;
        case CloudProvider.filen: providerKey = 'filen'; break;
        case CloudProvider.ftp: providerKey = 'ftp'; break;
        case CloudProvider.gdrive: providerKey = 'gdrive'; break;
        case CloudProvider.onedrive: providerKey = 'onedrive'; break;
        case CloudProvider.s3: providerKey = 's3'; break;
        case CloudProvider.sftp: providerKey = 'sftp'; break;
        case CloudProvider.webdav: providerKey = 'webdav'; break;
        case CloudProvider.internxt: providerKey = 'internxt'; break;
        case CloudProvider.nextcloud: providerKey = 'nextcloud'; break;
        case CloudProvider.pcloud: providerKey = 'pcloud'; break;
        case CloudProvider.azure: providerKey = 'azure'; break;
        case CloudProvider.b2: providerKey = 'b2'; break;
      }
      await prefs.setString('cloud_provider', providerKey);
      debugPrint('💾 Saved provider preference: $providerKey');

      // 2. Instantiate correct config service
      if (provider == CloudProvider.dropbox) {
        _config = DropboxConfigService(configPath: _configPath, secureStorage: _secureStorage);
      } else if (provider == CloudProvider.filen) {
        _config = FilenConfigService(configPath: _configPath, secureStorage: _secureStorage);
      } else if (provider == CloudProvider.ftp) {
        _config = FTPConfigService(configPath: _configPath, secureStorage: _secureStorage);
      } else if (provider == CloudProvider.gdrive) {
        _config = GDriveConfigService(configPath: _configPath, secureStorage: _secureStorage);
      } else if (provider == CloudProvider.onedrive) {
        _config = OneDriveConfigService(configPath: _configPath, secureStorage: _secureStorage);
      } else if (provider == CloudProvider.s3) {
        _config = S3ConfigService(configPath: _configPath, secureStorage: _secureStorage);
      } else if (provider == CloudProvider.sftp) {
        _config = SFTPConfigService(configPath: _configPath, secureStorage: _secureStorage);
      } else if (provider == CloudProvider.webdav) {
        _config = WebDavConfigService(configPath: _configPath, secureStorage: _secureStorage);
      } else if (provider == CloudProvider.internxt) {
        _config = ConfigService(configPath: _configPath);
      }

      // 3. Create Client
      _currentProvider = provider;
      _cloudClient = CloudStorageFactory.create(provider, config: _config);
      _remotePath = _cloudClient.rootPath;
      _remoteFiles = null;

      // 4. Try auto-login with new provider
      await _attemptAutoLogin();

      notifyListeners();
    });
  }

  // Getters for cloud client info
  CloudProvider get currentProvider => _currentProvider;
  String get providerName => _cloudClient.providerName;
  CloudStorageClient get client => _cloudClient;
  bool get isEncryptionEnabled => _cloudClient is EncryptedStorageWrapper;

  /// Wrap the current cloud client with encryption.
  /// Call after login to enable client-side encryption.
  void enableEncryption(String passphrase) {
    if (_cloudClient is EncryptedStorageWrapper) return; // Already wrapped
    final salt = EncryptionService.generateSalt();
    final key = EncryptionService.deriveKey(passphrase, salt);
    _cloudClient = EncryptedStorageWrapper(
      inner: _cloudClient,
      encryptionKey: key,
    );
    notifyListeners();
  }

  /// Remove encryption wrapper, restoring the inner client.
  void disableEncryption() {
    if (_cloudClient is EncryptedStorageWrapper) {
      _cloudClient = (_cloudClient as EncryptedStorageWrapper).inner;
      notifyListeners();
    }
  }

  Future<void> _initializeLocalPath() async {
    try {
      await _localFileService.getInitialPath(); 
      
      if (!kIsWeb && Platform.isMacOS && _localFileService.grantedBasePath == null) {
        debugPrint('📂 No previous directory access, prompting user...');
        await _requestInitialDirectoryAccess();
      } else {
        await _loadLocalFiles(); 
        notifyListeners();
      }
    } catch (e) {
      debugPrint('❌ Error initializing local path: $e');
      _localPath = await _localFileService.getSafeFallbackDirectory();
      _errors.add(AppError(e.toString()));
      notifyListeners();
    }
  }

  Future<void> _requestInitialDirectoryAccess() async {
    _errors.add(AppError('Please select a base directory to grant access (e.g., your home folder)'));
    notifyListeners();

    final grantedPath = await _localFileService.requestDirectoryAccess(
      initialDirectory: await _localFileService.getSafeFallbackDirectory(),
    );

    if (grantedPath != null) {
      _errors.clear();
      await _loadLocalFiles();
      notifyListeners();
    } else {
      _localPath = await _localFileService.getSafeFallbackDirectory();
      _errors.add(AppError('Access cancelled. Using fallback directory.'));
      await _loadLocalFiles(); 
      notifyListeners();
    }
  }

  Future<void> _loadLocalFiles() async {
    try {
      debugPrint('📁 Loading local files from: $localPath');
      
      final entities = await _localFileService.listDirectory(localPath);
      
      if (entities == null) {
         _localFiles = [];
         // On web, empty list might just mean no folder selected yet
         if (!kIsWeb) _errors.add(AppError('Local file access is not supported on this platform.'));
         notifyListeners();
         return;
      }

      final items = <FileItem>[];
      // print('📦 Found ${entities.length} entities');

      for (final entity in entities) {
        try {
          final name = p.basename(entity.path);
          if (name.startsWith('.')) continue;

          // --- WEB SPECIFIC LOGIC ---
          if (kIsWeb) {
            final isFolder = entity is Directory;
            int size = 0;
            DateTime updated = DateTime.now();

            if (!isFolder) {
              // Retrieve real size from WebFileService
              final meta = _localFileService.getWebMetadata(entity.path);
              size = meta['size'] ?? 0;
              updated = meta['modified'] ?? DateTime.now();
            }

            items.add(FileItem(
              name: name,
              path: entity.path,
              isFolder: isFolder,
              size: size,
              updatedAt: updated,
            ));
            continue; 
          }
          // --- Web logic end ---

          final stat = await entity.stat(); 
          if (stat.type == FileSystemEntityType.directory) {
            items.add(FileItem(
              name: name,
              path: entity.path,
              isFolder: true,
              updatedAt: stat.modified,
            ));
          } else if (stat.type == FileSystemEntityType.file) {
            items.add(FileItem(
              name: name,
              path: entity.path,
              isFolder: false,
              size: stat.size,
              updatedAt: stat.modified,
            ));
          }
        } catch (e) {
          continue;
        }
      }

      _localFiles = items;
      _sortFiles(_localFiles, _localSortBy, _localSortOrder);
      // print('✅ Loaded ${_localFiles?.length ?? 0} local items');
      _errors.clear();
      notifyListeners();
    } catch (e) {
      if (!kIsWeb && (e is PathAccessException || e.toString().contains('Operation not permitted') || e.toString().contains('Permission denied'))) {
        _localFiles = [];
        _errors.add(AppError('Permission denied. Use the Browse button (folder icon) to grant access.'));
        notifyListeners();
        return; 
      }
      
      debugPrint('❌ Error loading local files: $e');
      _localFiles = [];
      _errors.add(AppError(e.toString()));
      notifyListeners();
    }
  }

  Future<void> _attemptAutoLogin() async {
    await _autoLoginLock.synchronized(() async {
      debugPrint('🔄 Attempting auto-login for provider: ${_cloudClient.providerName}');

      try {
        if (_cloudClient is InternxtClientAdapter) {
          final adapter = _cloudClient as InternxtClientAdapter;
          final rawCreds = await (_cloudClient as InternxtClientAdapter).config.readCredentials();
          final Map<String, String>? creds = rawCreds?.cast<String, String>();

          if (creds == null || creds['token'] == null) {
             debugPrint('⚠️ Internxt: No credentials found');
             return;
          }
          adapter.setAuth(creds);
          _userEmail = creds['email'];
          _isConnected = true;
          await refreshPanel(PanelSide.remote);
          notifyListeners();
        } else if (_cloudClient is FilenClientAdapter) {
          final adapter = _cloudClient as FilenClientAdapter;
          final creds = await adapter.filenConfig.readCredentials();
          if (creds == null || creds['email'] == null) {
             debugPrint('⚠️ Filen: No credentials found');
             return;
          }
          if (creds['apiKey'] != null && creds['apiKey']!.isNotEmpty) {
            adapter.client.setAuth(creds);
            _userEmail = creds['email'];
            _isConnected = true;
            await refreshPanel(PanelSide.remote);
            notifyListeners();
          }
        } else if (_cloudClient is FTPClientAdapter) {
          final adapter = _cloudClient as FTPClientAdapter;
          final creds = await adapter.config.readCredentials();

          if (creds != null && creds['host'] != null && creds['username'] != null) {
            _userEmail = '${creds['username']}@${creds['host']}';
            _isConnected = true;
            debugPrint('FTP: Auto-login successful for $_userEmail');
            await refreshPanel(PanelSide.remote);
            notifyListeners();
          } else {
            debugPrint('FTP: No saved credentials found');
          }
        } else if (_cloudClient is SFTPClientAdapter) {
          final adapter = _cloudClient as SFTPClientAdapter;
          final creds = await adapter.config.readCredentials();

          if (creds != null && creds['host'] != null && creds['username'] != null) {
            _userEmail = '${creds['username']}@${creds['host']}';
            _isConnected = true;
            debugPrint('✅ SFTP: Auto-login successful for $_userEmail');

            // Force a refresh to list files immediately
            await refreshPanel(PanelSide.remote);
            notifyListeners();
          } else {
            debugPrint('⚠️ SFTP: No saved credentials found');
          }
        } else if (_cloudClient is S3ClientAdapter) {
          final adapter = _cloudClient as S3ClientAdapter;
          final restored = await adapter.restoreCredentials();
          if (restored) {
            _userEmail = '${adapter.userId}@${adapter.bucketId}';
            _isConnected = true;
            debugPrint('✅ S3: Auto-login successful for $_userEmail');
            await refreshPanel(PanelSide.remote);
            notifyListeners();
          } else {
            debugPrint('⚠️ S3: No saved credentials found');
          }
        } else if (_cloudClient is WebDavClientAdapter) {
          final adapter = _cloudClient as WebDavClientAdapter;
          final creds = await adapter.config.readCredentials();

          if (creds != null && creds['host'] != null && creds['username'] != null) {
            _userEmail = '${creds['username']}@${creds['host']}';
            _isConnected = true;
            debugPrint('✅ WebDAV: Auto-login successful for $_userEmail');
            await refreshPanel(PanelSide.remote);
            notifyListeners();
          } else {
            debugPrint('⚠️ WebDAV: No credentials found');
          }
        }
      } catch (e) {
        debugPrint('⚠️ Auto-login exception: $e');
        _errors.add(AppError('Session expired. Please log in again.'));
        _isConnected = false;
        notifyListeners();
      }
    });
  }

  void clearCompletedOperations() {
    _operations.removeWhere((op) => op.isComplete && op.error == null);
    notifyListeners();
  }

  void removeOperation(String id) {
    _operations.removeWhere((op) => op.id == id);
    notifyListeners();
  }

  // Getters
  bool get isConnected => _isConnected;
  String? get userEmail => _userEmail;
  PanelSide get activePanel => _activePanel;
  String get localPath => _localPath;
  String get remotePath => _remotePath;
  List<FileItem>? get localFileItems => _localFiles;
  List<FileItem>? get remoteFiles => _remoteFiles;
  Set<FileItem> get localSelection => _localSelection;
  Set<FileItem> get remoteSelection => _remoteSelection;
  List<OperationProgress> get operations => _operations;
  bool get hasActiveOperations => _operations.any((op) => !op.isComplete);

  Future<void> login(String email, String password, String? tfaCode) async {
    await _cloudClient.login(email, password, twoFactorCode: tfaCode);
    
    if (_cloudClient is InternxtClientAdapter) {
      final adapter = _cloudClient as InternxtClientAdapter;
      final response = adapter.lastLoginResponse;
      
      if (response != null) {
        await adapter.config.saveCredentials({
          'email': email,
          'token': response['token'] ?? '',
          'mnemonic': response['mnemonic'] ?? '',
          'userId': response['userId'] ?? '',
          'bridgeUser': response['bridgeUser'] ?? '',
          'userIdForAuth': response['userIdForAuth'] ?? '',
          'bucketId': response['bucketId'] ?? '',
          'rootFolderId': response['rootFolderId'] ?? '',
          'newToken': response['newToken'] ?? '',
        });
      }
    } else if (_cloudClient is FilenClientAdapter) {
      final adapter = _cloudClient as FilenClientAdapter;
      final savedCreds = await adapter.filenConfig.readCredentials();
      if (savedCreds == null) {
        debugPrint('⚠️ Warning: Filen credentials were not saved properly');
      }
    } else if (_cloudClient is FTPClientAdapter) {
      final adapter = _cloudClient as FTPClientAdapter;
      final savedCreds = await adapter.config.readCredentials();
      if (savedCreds == null) {
        debugPrint('Warning: FTP credentials were not saved properly');
      }
    } else if (_cloudClient is S3ClientAdapter) {
      final adapter = _cloudClient as S3ClientAdapter;
      final savedCreds = await adapter.config.readCredentials();
      if (savedCreds == null) {
        debugPrint('⚠️ Warning: S3 credentials were not saved properly');
      }
    } else if (_cloudClient is SFTPClientAdapter) {
      final adapter = _cloudClient as SFTPClientAdapter;
      final savedCreds = await adapter.config.readCredentials();
      if (savedCreds == null) {
        debugPrint('⚠️ Warning: SFTP credentials were not saved properly');
      }
    } else if (_cloudClient is WebDavClientAdapter) {
      final adapter = _cloudClient as WebDavClientAdapter;
      final savedCreds = await adapter.config.readCredentials();
      if (savedCreds == null) {
        debugPrint('⚠️ Warning: WebDAV credentials were not saved properly');
      }
    }
    
    _userEmail = email;
    _isConnected = true;
    _errors.clear(); 
    notifyListeners();
    await refreshPanel(PanelSide.remote);
  }

  Future<void> logout() async {
    await _cloudClient.logout();
    
    if (_cloudClient is InternxtClientAdapter) {
      await (_cloudClient as InternxtClientAdapter).config.clearCredentials();
    } else if (_cloudClient is FilenClientAdapter) {
      await (_cloudClient as FilenClientAdapter).filenConfig.clearCredentials();
    } else if (_cloudClient is FTPClientAdapter) {
      await (_cloudClient as FTPClientAdapter).config.clearCredentials();
    } else if (_cloudClient is S3ClientAdapter) {
      await (_cloudClient as S3ClientAdapter).config.clearCredentials();
    } else if (_cloudClient is SFTPClientAdapter) {
      await (_cloudClient as SFTPClientAdapter).config.clearCredentials();
    } else if (_cloudClient is WebDavClientAdapter) {
      await (_cloudClient as WebDavClientAdapter).config.clearCredentials();
    }
    
    _isConnected = false;
    _userEmail = null;
    _remoteFiles = null;
    _remotePath = _cloudClient.rootPath;
    _remoteSelection.clear();
    notifyListeners();
  }

  void setActivePanel(PanelSide side) {
    _activePanel = side;
    notifyListeners();
  }

  Future<void> refreshPanel(PanelSide side) async {
    await _refreshPanelLock.synchronized(() async {
      if (side == PanelSide.local) {
        // Force the LocalFileService to re-scan the directory handle/disk.
        // This updates the virtual tree on Web so new downloads appear.
        await _localFileService.refresh();

        await _loadLocalFiles();
      } else {
        try {
          // Only attempt auto-login if we are NOT authenticated AND NOT logically connected.
          // SFTP is often !isAuthenticated (socket closed) but _isConnected (creds loaded).
          if (!_cloudClient.isAuthenticated && !_isConnected) {
            await _attemptAutoLogin();
            // If still not connected after attempt, clear files and return
            if (!_isConnected) {
              _remoteFiles = [];
              notifyListeners();
              return;
            }
          }

          final result = await _cloudClient.listPath(_remotePath);

          final folders = (result['folders'] as List<dynamic>?)?.map((item) {
                final map = item as Map<String, dynamic>;
                DateTime? folderDate;

                // Check keys used by different providers
                final rawDate = map['modificationTime'] ?? map['lastModified'] ?? map['timestamp'];

                if (rawDate != null) {
                  try {
                     if (rawDate is int) {
                       folderDate = DateTime.fromMillisecondsSinceEpoch(rawDate);
                     } else {
                       folderDate = DateTime.parse(rawDate.toString());
                     }
                  } catch (e) {
                    debugPrint('Failed to parse folder date from rawDate=$rawDate: $e');
                  }
                }

                return FileItem(
                  name: map['name'] ?? 'Unknown',
                  isFolder: true,
                  uuid: map['uuid'],
                  updatedAt: folderDate,
                );
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
                // Check keys used by different providers
                final rawDate = map['modificationTime'] ?? map['lastModified'];

                if (rawDate != null) {
                  try {
                     if (rawDate is int) {
                       fileDate = DateTime.fromMillisecondsSinceEpoch(rawDate);
                     } else {
                       fileDate = DateTime.parse(rawDate.toString());
                     }
                  } catch (e) {
                    debugPrint('Failed to parse file date from rawDate=$rawDate: $e');
                  }
                }

                return FileItem(
                  name: fullName,
                  isFolder: false,
                  size: map['size'] as int?,
                  uuid: map['uuid'],
                  updatedAt: fileDate,
                );
              }).toList() ?? [];

          _remoteFiles = [...folders, ...files];
          _sortFiles(_remoteFiles, _remoteSortBy, _remoteSortOrder);
          _errors.clear();
          notifyListeners();
        } catch (e) {
          // Don't clear files on temporary network errors if possible,
          // but for now we follow standard pattern
          debugPrint('❌ Refresh Error: $e');
          _remoteFiles = [];
          _errors.add(AppError(e.toString()));
          notifyListeners();
        }
      }
    });
  }

  Future<void> navigateUp(PanelSide side) async {
    if (side == PanelSide.local) {
      
      final parent = p.dirname(localPath);

      // Ensure we don't navigate above our virtual root
      if (parent != localPath && parent != '.') {
        await navigateToPath(side, parent);
      }
    } else {
      if (_remotePath != '/') {
        _remotePath = p.dirname(_remotePath);
        if (_remotePath.isEmpty) _remotePath = '/';
        await refreshPanel(PanelSide.remote);
        debugPrint('📁 Navigated up to: $_remotePath');
      }
    }
  }

  Future<void> navigateToPath(PanelSide side, String path, {FileItem? selectItem}) async {
    if (side == PanelSide.local) {
      
      // We allow web navigation per a Virtual File System.
      // On Web, we treat the virtual root '/' as accessible.
      // On Desktop/Mobile, we check strict permissions.
      if (!kIsWeb && !await _localFileService.hasAccessToPath(path)) {
        debugPrint('⚠️ Path $path is outside granted directory');
        _errors.add(AppError('Cannot access paths outside the granted directory. Please grant access to a parent folder.'));
        notifyListeners();
        
        // Attempt to request access to the new path
        final newGrant = await _localFileService.requestDirectoryAccess(
          initialDirectory: path,
        );
        
        if (newGrant != null) {
          path = newGrant; 
        } else {
          return; 
        }
      } else if (kIsWeb && !await _localFileService.hasAccessToPath(path)) {
         // On Web, if we try to go somewhere our virtual tree doesn't know about
         // (should only be possible via manual manipulation), block it.
         debugPrint('⚠️ Virtual path not found: $path');
         return;
      }
      
      _localPath = path; 
      await _loadLocalFiles();
      
      if (selectItem != null && _localFiles != null) {
        try {
          final itemToSelect = _localFiles!.firstWhere(
            (file) => file.path == selectItem.path
          );
          _localSelection.clear();
          _localSelection.add(itemToSelect);
          _lastSelectedLocal = itemToSelect;
          _itemToScrollTo = itemToSelect; 
        } catch (e) {
          debugPrint('⚠️ Could not find item to select after navigation: ${selectItem.name}');
        }
      }
      
      notifyListeners();
      debugPrint('📁 Navigated to: $localPath');
    } else {
      // Remote Navigation Logic
      _remotePath = path;
      await refreshPanel(PanelSide.remote);
      
      if (selectItem != null && _remoteFiles != null) {
        try {
          final itemToSelect = _remoteFiles!.firstWhere(
            (file) => file.uuid == selectItem.uuid
          );
          _remoteSelection.clear();
          _remoteSelection.add(itemToSelect);
          _lastSelectedRemote = itemToSelect;
          _itemToScrollTo = itemToSelect; 
        } catch (e) {
          debugPrint('⚠️ Could not find item to select after navigation: ${selectItem.name}');
        }
      }
      
      debugPrint('📁 Navigated to: $_remotePath');
    }
    _syncTabPath(side);
  }

  Future<void> navigateInto(PanelSide side, FileItem item) async {
    if (!item.isFolder) return;

    if (side == PanelSide.local) {
      if (item.path != null) {
        await navigateToPath(side, item.path!);
      }
    } else {
      final newPath = p.posix.join(_remotePath, item.name);
      debugPrint('🔍 Attempting to navigate to: $newPath');
      
      try {
        await navigateToPath(side, newPath);
      } catch (e) {
        debugPrint('⚠️ Navigation failed: $e');
        
        _errors.add(AppError('Cannot open folder: ${item.name}. Path may not exist.'));
        notifyListeners();
      }
    }
  }

  bool isSelected(PanelSide side, FileItem item) {
    return side == PanelSide.local
        ? _localSelection.contains(item)
        : _remoteSelection.contains(item);
  }

  void toggleSelection(PanelSide side, FileItem item, {bool shiftKey = false, bool ctrlKey = false}) {
    final selection = side == PanelSide.local ? _localSelection : _remoteSelection;
    final files = side == PanelSide.local ? _localFiles : _remoteFiles; 
    final lastSelected = side == PanelSide.local ? _lastSelectedLocal : _lastSelectedRemote;

    if (shiftKey && lastSelected != null && files != null) {
      final startIdx = files.indexOf(lastSelected);
      final endIdx = files.indexOf(item);
      if (startIdx != -1 && endIdx != -1) {
        final start = startIdx < endIdx ? startIdx : endIdx;
        final end = startIdx < endIdx ? endIdx : startIdx;
        for (var i = start; i <= end; i++) {
          selection.add(files[i]);
        }
      }
    } else if (ctrlKey) {
      if (selection.contains(item)) {
        selection.remove(item);
      } else {
        selection.add(item);
      }
    } else {
      selection.clear();
      selection.add(item);
    }

    if (side == PanelSide.local) {
      _lastSelectedLocal = item;
    } else {
      _lastSelectedRemote = item;
    }

    notifyListeners();
  }

  void selectAll(PanelSide side) {
    final selection = side == PanelSide.local ? _localSelection : _remoteSelection;
    final files = side == PanelSide.local ? _localFiles : _remoteFiles; 
    if (files != null) {
      selection.addAll(files);
      notifyListeners();
    }
  }

  void clearSelection(PanelSide side) {
    if (side == PanelSide.local) {
      _localSelection.clear();
      _lastSelectedLocal = null;
    } else {
      _remoteSelection.clear();
      _lastSelectedRemote = null;
    }
    notifyListeners();
  }
  
  // --- Credential helper (shared by upload/download) ---

  Future<void> _ensureAuthenticated() async {
    if (_cloudClient is InternxtClientAdapter) {
      final creds = await (_cloudClient as InternxtClientAdapter).config.readCredentials();
      if (creds == null) throw Exception('Not authenticated');
    } else if (_cloudClient is FilenClientAdapter) {
      final creds = await (_cloudClient as FilenClientAdapter).filenConfig.readCredentials();
      if (creds == null) throw Exception('Not authenticated');
    } else if (_cloudClient is FTPClientAdapter) {
      final creds = await (_cloudClient as FTPClientAdapter).config.readCredentials();
      if (creds == null) throw Exception('Not authenticated');
    } else if (_cloudClient is S3ClientAdapter) {
      final creds = await (_cloudClient as S3ClientAdapter).config.readCredentials();
      if (creds == null) throw Exception('Not authenticated');
    } else if (_cloudClient is SFTPClientAdapter) {
      final creds = await (_cloudClient as SFTPClientAdapter).config.readCredentials();
      if (creds == null) throw Exception('Not authenticated');
    } else if (_cloudClient is WebDavClientAdapter) {
      final creds = await (_cloudClient as WebDavClientAdapter).config.readCredentials();
      if (creds == null) throw Exception('Not authenticated');
    }
  }

  // --- File operations (queue-based) ---

  Future<void> uploadFiles(List<FileItem> files, {String? targetPath}) async {
    debugPrint('📤 UPLOAD: ${files.length} files via ${_cloudClient.providerName}');

    await _ensureAuthenticated();
    final target = targetPath ?? _remotePath;

    final fileProgresses = <FileProgress>[];
    int totalBytes = 0;

    for (final file in files) {
      int fileSize = 0;
      if (file.isFolder && file.path != null) {
        fileSize = await _calculateFolderSize(file.path!);
      } else {
        fileSize = file.size ?? 0;
      }
      fileProgresses.add(FileProgress(name: file.name, path: file.path!, size: fileSize));
      totalBytes += fileSize;
    }

    debugPrint('📊 Total size: ${fmt.formatBytes(totalBytes)}');

    final operation = OperationProgress(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: OperationType.upload,
      sourcePath: files.length == 1 ? files.first.path! : '${files.length} files',
      targetPath: target,
      fileName: files.length == 1 ? files.first.name : '${files.length} files',
      totalBytes: totalBytes,
      files: fileProgresses,
    );

    _operations.add(operation);
    notifyListeners();

    int completedBytes = 0;
    int tasksFinished = 0;

    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      final fileProgress = fileProgresses[i];
      final taskId = '${operation.id}_upload_$i';

      _transferQueue.enqueue(TransferTask(
        id: taskId,
        operation: operation,
        execute: () async {
          if (operation.isCancelled) return;
          if (operation.isPaused) await operation.pauseFuture;
          if (operation.isCancelled) return;

          if (file.path == null) {
            fileProgress.error = 'No path';
            return;
          }

          if (file.isFolder) {
            await _uploadFolderViaClient(file.path!, target, operation);
          } else {
            final fileData = await _localFileService.readFile(file.path!, fileItem: file);
            await _cloudClient.uploadFile(
              fileData,
              file.name,
              target,
              onProgress: (current, total) {
                operation.currentBytes = completedBytes + current;
                notifyListeners();
              },
            );
          }

          fileProgress.isComplete = true;
          completedBytes += fileProgress.size;
          operation.currentBytes = completedBytes;

          tasksFinished++;
          if (tasksFinished == files.length) {
            _finalizeBatchOperation(operation, fileProgresses);
            await refreshPanel(PanelSide.remote);
            clearSelection(PanelSide.local);
          }
        },
      ));
    }
  }

  Future<void> downloadFiles(List<FileItem> files, {String? localPath}) async {
    debugPrint('⬇️ DOWNLOAD: ${files.length} files via ${_cloudClient.providerName}');

    await _ensureAuthenticated();
    final target = localPath ?? _localPath;

    final fileProgresses = files
        .map((f) => FileProgress(name: f.name, path: f.uuid ?? f.name, size: f.size ?? 0))
        .toList();
    final totalBytes = files.fold(0, (sum, f) => sum + (f.size ?? 0));

    debugPrint('📊 Total size: ${fmt.formatBytes(totalBytes)}');

    final operation = OperationProgress(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: OperationType.download,
      sourcePath: files.length == 1 ? files.first.name : '${files.length} files',
      targetPath: target,
      fileName: files.length == 1 ? files.first.name : '${files.length} files',
      totalBytes: totalBytes,
      files: fileProgresses,
    );

    _operations.add(operation);
    notifyListeners();

    int completedBytes = 0;
    int tasksFinished = 0;

    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      final fileProgress = fileProgresses[i];
      final taskId = '${operation.id}_download_$i';

      _transferQueue.enqueue(TransferTask(
        id: taskId,
        operation: operation,
        execute: () async {
          if (operation.isCancelled) return;
          if (operation.isPaused) await operation.pauseFuture;
          if (operation.isCancelled) return;

          final remotePath = file.path ?? p.posix.join(_remotePath, file.name);

          if (file.isFolder) {
            if (!kIsWeb) {
              await _downloadFolderViaClient(remotePath, target, operation);
            }
          } else {
            final bytes = await _cloudClient.downloadFileBytes(
              remotePath,
              onProgress: (current, total) {
                if (total > 0) {
                  operation.currentBytes = completedBytes + current;
                  notifyListeners();
                }
              },
            );

            final localFilePath = p.join(target, file.name);
            await _localFileService.saveFile(localFilePath, bytes);

            if (!kIsWeb && file.updatedAt != null) {
              try {
                final f = File(localFilePath);
                if (await f.exists()) {
                  await f.setLastModified(file.updatedAt!);
                }
              } catch (e) {
                debugPrint('⚠️ Timestamp update failed: $e');
              }
            }
          }

          fileProgress.isComplete = true;
          completedBytes += fileProgress.size;
          operation.currentBytes = completedBytes;

          tasksFinished++;
          if (tasksFinished == files.length) {
            _finalizeBatchOperation(operation, fileProgresses);
            await refreshPanel(PanelSide.local);
            clearSelection(PanelSide.remote);
          }
        },
      ));
    }
  }

  void _finalizeBatchOperation(OperationProgress operation, List<FileProgress> fileProgresses) {
    if (operation.isCancelled) {
      operation.fail('Cancelled by user');
    } else {
      final failedCount = fileProgresses.where((f) => f.error != null).length;
      if (failedCount == 0) {
        operation.complete();
      } else if (failedCount == fileProgresses.length) {
        operation.fail('All files failed');
      } else {
        operation.complete();
      }
    }
    notifyListeners();
  }

  Future<int> _calculateFolderSize(String folderPath) async {
    try {
      // We use _localFileService to list directory. This handles macOS security scopes 
      // which prevents the "Operation not permitted" error.
      final entities = await _localFileService.listDirectory(folderPath);
      
      if (entities == null) return 0;
      
      int totalSize = 0;
      for (final entity in entities) {
        if (entity is File) {
          try {
            final stat = await entity.stat();
            totalSize += stat.size;
          } catch (e) {
            debugPrint('⚠️ Could not stat file: ${entity.path}');
          }
        } else if (entity is Directory) {
          // Recursive call for subdirectories using the same safe listing method
          totalSize += await _calculateFolderSize(entity.path);
        }
      }
      return totalSize;
    } catch (e) {
      debugPrint('⚠️ Error calculating folder size: $e');
      return 0;
    }
  }

  // Helper methods for folder operations via cloud client
  Future<void> _uploadFolderViaClient(String localPath, String remotePath, OperationProgress operation) async {
    if (kIsWeb) return;
    
    final folderName = p.basename(localPath);
    final newRemotePath = p.posix.join(remotePath, folderName);

    try {
      await _cloudClient.createFolderPath(newRemotePath);
    } catch (e) {
      // Folder might already exist
    }

    // Use listDirectory to get entities (handles listing permissions)
    final entities = await _localFileService.listDirectory(localPath);
    if (entities == null) return;

    for (final entity in entities) {
      if (operation.isCancelled) break;
      
      if (entity is File) {
        try {
          final fileName = p.basename(entity.path);
          // FIX: Use readFile to get bytes (handles reading permissions)
          final fileData = await _localFileService.readFile(entity.path);
          
          await _cloudClient.uploadFile(fileData, fileName, newRemotePath);
          operation.currentBytes += fileData.length;
          notifyListeners();
        } catch (e) {
          debugPrint('⚠️ Error reading/uploading file in folder ${entity.path}: $e');
        }
      } else if (entity is Directory) {
        await _uploadFolderViaClient(entity.path, newRemotePath, operation);
      }
    }
  }

  Future<void> _downloadFolderViaClient(String remotePath, String localPath, OperationProgress operation) async {
    if (kIsWeb) return;
    
    final folderName = p.basename(remotePath);
    final newLocalPath = p.join(localPath, folderName);

    await Directory(newLocalPath).create(recursive: true);

    final contents = await _cloudClient.listPath(remotePath);
    
    for (final file in contents['files']) {
      if (operation.isCancelled) break;
      
      final fileName = file['name'];
      final fileSize = int.tryParse(file['size']?.toString() ?? '0') ?? 0;
      final localFilePath = p.join(newLocalPath, fileName);
      
      await _cloudClient.downloadFileByPath(
        p.posix.join(remotePath, fileName),
        localFilePath,
      );
      
      operation.currentBytes += fileSize;
      notifyListeners();
    }

    for (final folder in contents['folders']) {
      if (operation.isCancelled) break;
      
      await _downloadFolderViaClient(
        p.posix.join(remotePath, folder['name']),
        newLocalPath,
        operation,
      );
    }
  }

  // CHANGED: Uses cloud client abstraction
  Future<void> deleteFiles(PanelSide side, List<FileItem> files) async {
    if (kIsWeb && side == PanelSide.local) return;
    try {
      for (final file in files) {
        if (side == PanelSide.local) {
          if (file.isFolder) {
            await Directory(file.path!).delete(recursive: true);
          } else {
            await File(file.path!).delete();
          }
        } else {
          // FIX: Use absolute path
          final deletePath = file.path ?? p.posix.join(_remotePath, file.name);
          await _cloudClient.deletePath(deletePath);
        }
      }
      await refreshPanel(side);
      clearSelection(side);
    } catch (e) {
      debugPrint('❌ Error deleting files: $e');
      _errors.add(AppError('Delete failed: $e'));
      notifyListeners();
    }
  }

  Future<void> moveFiles(PanelSide side, List<FileItem> files, String targetPath) async {
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
          // FIX: Use file.path (absolute) instead of combining _remotePath + name
          final sourcePath = file.path ?? p.posix.join(_remotePath, file.name);
          debugPrint('🚀 Moving: $sourcePath -> $targetPath');
          await _cloudClient.movePath(sourcePath, targetPath);
        }
      }

      await refreshPanel(side);
      clearSelection(side);
    } catch (e) {
      debugPrint('❌ Error moving files: $e');
      _errors.add(AppError('Move failed: $e'));
      notifyListeners();
      await refreshPanel(side);
    }
  }

  Future<void> copyFiles(PanelSide side, List<FileItem> files, String targetPath) async {
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
          final tempPath = p.join(Directory.systemTemp.path, file.name);
          await _cloudClient.downloadFileByPath(p.posix.join(_remotePath, file.name), tempPath);
          final data = await File(tempPath).readAsBytes();
          await _cloudClient.uploadFile(data, file.name, targetPath);
          await File(tempPath).delete();
        }
      }

      await refreshPanel(side);
    } catch (e) {
      debugPrint('❌ Error copying files: $e');
      _errors.add(AppError('Copy failed: $e'));
      notifyListeners();
    }
  }

  Future<void> _copyDirectory(String source, String target) async {
    if (kIsWeb) return;
    await Directory(target).create(recursive: true);
    final dir = Directory(source);
    final entities = await dir.list().toList();
    
    for (final entity in entities) {
      if (entity is File) {
        await entity.copy(p.join(target, p.basename(entity.path)));
      } else if (entity is Directory) {
        await _copyDirectory(entity.path, p.join(target, p.basename(entity.path)));
      }
    }
  }

  // CHANGED: Uses cloud client abstraction
  Future<void> renameFile(PanelSide side, FileItem file, String newName) async {
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
        // FIX: Use absolute path
        final sourcePath = file.path ?? p.posix.join(_remotePath, file.name);
        await _cloudClient.renamePath(sourcePath, newName);
      }
      await refreshPanel(side);
    } catch (e) {
      debugPrint('❌ Error renaming file: $e');
      _errors.add(AppError('Rename failed: $e'));
      notifyListeners();
    }
  }

  // CHANGED: Uses cloud client abstraction
  Future<void> createFolder(PanelSide side, String name) async {
    if (kIsWeb && side == PanelSide.local) return;
    try {
      if (side == PanelSide.local) {
        await Directory(p.join(localPath, name)).create();
      } else {
        await _cloudClient.createFolderPath(p.posix.join(_remotePath, name));
      }

      await refreshPanel(side);
    } catch (e) {
      debugPrint('❌ Error creating folder: $e');
      _errors.add(AppError('Create folder failed: $e'));
      notifyListeners();
    }
  }

  // CHANGED: Search methods now use cloud client (if supported)
  Future<Map<String, List<FileItem>>> searchFiles(String query) async {
    if (_isSearching) return {};
    _isSearching = true;
    notifyListeners();
    
    try {
      // Check if cloud client supports search
      if (_cloudClient is InternxtClientAdapter) {
        final adapter = _cloudClient as InternxtClientAdapter;
        final results = await adapter.search(query, detailed: true);
        
        final folders = (results['folders'] as List<dynamic>?)
            ?.map((item) => FileItem(
                  name: item['fullPath'] ?? item['name'], 
                  isFolder: true,
                  uuid: item['uuid'],
                  path: item['fullPath'], 
                ))
            .toList() ?? [];
            
        final files = (results['files'] as List<dynamic>?)
            ?.map((item) {
              final plainName = item['name'] ?? 'Unknown';
              final fileType = item['type'] ?? '';
              final fullName = (fileType.isNotEmpty && !plainName.endsWith(fileType)) 
                  ? '$plainName.$fileType' 
                  : plainName;
              final displayName = item['fullPath'] ?? fullName;
              
              return FileItem(
                name: displayName,
                isFolder: false,
                uuid: item['uuid'],
                path: item['fullPath'], 
              );
            })
            .toList() ?? [];

        _isSearching = false;
        notifyListeners();
        return {'folders': folders, 'files': files};
      } else {
        // Filen or other providers - implement as needed
        throw UnsupportedError('Search not supported for ${_cloudClient.providerName}');
      }
    } catch (e) {
      _errors.add(AppError("Search failed: $e"));
      _isSearching = false;
      notifyListeners();
      return {};
    }
  }

  Future<List<FileItem>> findFiles(String pattern) async {
    if (_isSearching) return [];
    _isSearching = true;
    notifyListeners();
    
    try {
      // Check if cloud client supports find
      if (_cloudClient is InternxtClientAdapter) {
        final adapter = _cloudClient as InternxtClientAdapter;
        final results = await adapter.findFiles(_remotePath, pattern, maxDepth: -1);
        
        final files = results
            .map((item) {
              final plainName = item['name'] ?? 'Unknown';
              final fileType = item['fileType'] ?? '';
              final fullName = (fileType.isNotEmpty && !plainName.endsWith(fileType)) 
                  ? '$plainName.$fileType' 
                  : plainName;
              final displayName = item['fullPath'] ?? fullName;

              return FileItem(
                name: displayName,
                isFolder: false,
                uuid: item['uuid'],
                size: item['size'] as int?,
                path: item['fullPath'], 
                updatedAt: DateTime.tryParse(item['updatedAt'] ?? ''),
              );
            })
            .toList();

        _isSearching = false;
        notifyListeners();
        return files;
      } else {
        throw UnsupportedError('Find not supported for ${_cloudClient.providerName}');
      }
    } catch (e) {
      _errors.add(AppError("Find failed: $e"));
      _isSearching = false;
      notifyListeners();
      return [];
    }
  }

  void pauseOperation(String operationId) {
    try {
      final operation = _operations.firstWhere((op) => op.id == operationId);
      operation.pause();
      notifyListeners();
    } catch (e) {
      debugPrint('⚠️ Error pausing operation: $e');
    }
  }

  void resumeOperation(String operationId) {
    try {
      final operation = _operations.firstWhere((op) => op.id == operationId);
      operation.resume();
      notifyListeners();
    } catch (e) {
      debugPrint('⚠️ Error resuming operation: $e');
    }
  }

  void cancelOperation(String operationId) {
    try {
      final operation = _operations.firstWhere((op) => op.id == operationId);
      operation.cancel();
      // Optionally remove it immediately or let the UI handle it
      notifyListeners();
    } catch (e) {
      debugPrint('⚠️ Error cancelling operation: $e');
    }
  }
}