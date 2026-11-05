import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/native_file_operations.dart';

final nativeFileOperationsProvider = Provider<NativeFileOperations>(
  (ref) => const NativeFileOperations(),
);
