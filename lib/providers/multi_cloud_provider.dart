// lib/providers/multi_cloud_provider.dart
//
// Riverpod provider wrapping MultiCloudService.
// Exposes connection management, cloud-to-cloud transfer, comparison,
// and unified search to the UI layer.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/file_item.dart';
import '../models/operation_progress.dart';
import '../services/cloud_storage_interface.dart';
import '../services/log_service.dart';
import '../services/multi_cloud_service.dart';
import 'error_provider.dart';

export '../services/multi_cloud_service.dart'
    show CloudConnection, FileDiff, FileDiffKind, MultiCloudSearchResult;

class MultiCloudNotifier extends ChangeNotifier {
  static const _log = Log('MultiCloudNotifier');

  final Ref _ref;
  final MultiCloudService _service = MultiCloudService();

  bool _isComparing = false;
  bool _isSearching = false;
  bool _isTransferring = false;

  List<FileDiff> _lastDiffs = [];
  List<MultiCloudSearchResult> _lastSearchResults = [];
  OperationProgress? _activeTransfer;

  MultiCloudNotifier(this._ref);

  // ---------------------------------------------------------------------------
  // State getters
  // ---------------------------------------------------------------------------

  List<CloudConnection> get connections => _service.getAllConnections();
  bool get isComparing => _isComparing;
  bool get isSearching => _isSearching;
  bool get isTransferring => _isTransferring;
  List<FileDiff> get lastDiffs => List.unmodifiable(_lastDiffs);
  List<MultiCloudSearchResult> get lastSearchResults => List.unmodifiable(_lastSearchResults);
  OperationProgress? get activeTransfer => _activeTransfer;

  // ---------------------------------------------------------------------------
  // Connection management
  // ---------------------------------------------------------------------------

  void addConnection({
    required String id,
    required String label,
    required CloudProvider provider,
    required CloudStorageClient client,
  }) {
    _service.addConnection(id: id, label: label, provider: provider, client: client);
    _log.info('Connection added: $id');
    notifyListeners();
  }

  CloudConnection? getConnection(String id) => _service.getConnection(id);

  Future<void> removeConnection(String id) async {
    await _service.removeConnection(id);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Cloud-to-cloud transfer
  // ---------------------------------------------------------------------------

  Future<void> transferBetweenClouds({
    required CloudStorageClient sourceClient,
    required String sourcePath,
    required CloudStorageClient targetClient,
    required String targetPath,
    required List<FileItem> files,
  }) async {
    if (_isTransferring) return;

    _log.info('Starting cloud-to-cloud transfer of ${files.length} files');
    _isTransferring = true;
    _activeTransfer = null;
    notifyListeners();

    try {
      final operation = await _service.transferBetweenClouds(
        sourceClient: sourceClient,
        sourcePath: sourcePath,
        targetClient: targetClient,
        targetPath: targetPath,
        files: files,
        onFileProgress: (fileName, current, total) {
          notifyListeners();
        },
      );
      _activeTransfer = operation;
      notifyListeners();
    } catch (e, st) {
      _log.error('Cloud-to-cloud transfer failed', e, st);
      _ref.read(errorProvider).addError('Transfer failed: $e');
    } finally {
      _isTransferring = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Cross-provider comparison
  // ---------------------------------------------------------------------------

  Future<void> compareFiles({
    required CloudStorageClient clientA,
    required String pathA,
    required CloudStorageClient clientB,
    required String pathB,
  }) async {
    if (_isComparing) return;

    _log.info('Starting comparison');
    _isComparing = true;
    _lastDiffs = [];
    notifyListeners();

    try {
      _lastDiffs = await _service.compareFiles(
        clientA: clientA,
        pathA: pathA,
        clientB: clientB,
        pathB: pathB,
      );
    } catch (e, st) {
      _log.error('Comparison failed', e, st);
      _ref.read(errorProvider).addError('Comparison failed: $e');
    } finally {
      _isComparing = false;
      notifyListeners();
    }
  }

  void clearDiffs() {
    _lastDiffs = [];
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Unified search
  // ---------------------------------------------------------------------------

  Future<void> searchAcrossProviders(String query) async {
    if (_isSearching) return;

    _log.info('Unified search: "$query"');
    _isSearching = true;
    _lastSearchResults = [];
    notifyListeners();

    try {
      _lastSearchResults = await _service.searchAcrossProviders(
        query,
        _service.getAllConnections(),
      );
    } catch (e, st) {
      _log.error('Unified search failed', e, st);
      _ref.read(errorProvider).addError('Search failed: $e');
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  void clearSearchResults() {
    _lastSearchResults = [];
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }
}

final multiCloudProvider = ChangeNotifierProvider<MultiCloudNotifier>((ref) {
  return MultiCloudNotifier(ref);
});
