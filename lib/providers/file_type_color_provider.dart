// lib/providers/file_type_color_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/file_type_color_service.dart';

export '../services/file_type_color_service.dart'
    show FileTypeColorRule, FileTypeColorService;

final fileTypeColorProvider =
    ChangeNotifierProvider<FileTypeColorService>((ref) {
  final service = FileTypeColorService();
  service.load();
  return service;
});
