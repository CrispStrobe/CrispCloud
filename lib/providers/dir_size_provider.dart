// lib/providers/dir_size_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/dir_size_service.dart';

final dirSizeProvider = Provider<DirSizeService>((ref) => DirSizeService());
