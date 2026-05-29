// lib/providers/search_provider.dart
//
// Manages cloud search and find operations.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../services/internxt_client_adapter.dart';
import 'auth_provider.dart';
import 'error_provider.dart';
import 'panel_provider.dart';

class SearchNotifier extends ChangeNotifier {
  final Ref _ref;

  bool _isSearching = false;
  bool get isSearching => _isSearching;

  SearchNotifier(this._ref);

  Future<Map<String, List<FileItem>>> searchFiles(String query) async {
    if (_isSearching) return {};
    _isSearching = true;
    notifyListeners();

    try {
      final client = _ref.read(authProvider).client;
      if (client is InternxtClientAdapter) {
        final results = await client.search(query, detailed: true);

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
              return FileItem(
                name: item['fullPath'] ?? fullName,
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
        throw UnsupportedError('Search not supported for ${client.providerName}');
      }
    } catch (e) {
      _ref.read(errorProvider).addError('Search failed: $e');
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
      final client = _ref.read(authProvider).client;
      final remotePath = _ref.read(panelProvider(PanelSide.remote)).currentPath;

      if (client is InternxtClientAdapter) {
        final results = await client.findFiles(remotePath, pattern, maxDepth: -1);
        final files = results.map((item) {
          final plainName = item['name'] ?? 'Unknown';
          final fileType = item['fileType'] ?? '';
          final fullName = (fileType.isNotEmpty && !plainName.endsWith(fileType))
              ? '$plainName.$fileType'
              : plainName;
          return FileItem(
            name: item['fullPath'] ?? fullName,
            isFolder: false,
            uuid: item['uuid'],
            size: item['size'] as int?,
            path: item['fullPath'],
            updatedAt: DateTime.tryParse(item['updatedAt'] ?? ''),
          );
        }).toList();

        _isSearching = false;
        notifyListeners();
        return files;
      } else {
        throw UnsupportedError('Find not supported for ${client.providerName}');
      }
    } catch (e) {
      _ref.read(errorProvider).addError('Find failed: $e');
      _isSearching = false;
      notifyListeners();
      return [];
    }
  }
}

final searchProvider = ChangeNotifierProvider<SearchNotifier>((ref) {
  return SearchNotifier(ref);
});
