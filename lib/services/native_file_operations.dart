import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'storage_trash.dart';

class NativeFileClipboard {
  const NativeFileClipboard({required this.paths, required this.cut});
  final List<String> paths;
  final bool cut;
}

/// Desktop shell integration. Unavailable methods fail without substituting
/// permanent deletion or converting file clipboard data to plain text.
class NativeFileOperations {
  const NativeFileOperations({
    this.channel = const MethodChannel('crispcloud/files'),
  });
  final MethodChannel channel;

  static bool get supported =>
      !kIsWeb &&
      const [
        TargetPlatform.linux,
        TargetPlatform.macOS,
        TargetPlatform.windows,
      ].contains(defaultTargetPlatform);

  Future<TrashReceipt> trash(String path) async {
    final result = await channel.invokeMapMethod<String, dynamic>('trash', {
      'path': path,
    });
    if (result == null) {
      throw StateError('The system did not return a trash receipt.');
    }
    return TrashReceipt.fromJson(result);
  }

  Future<void> restore(TrashReceipt receipt) =>
      channel.invokeMethod<void>('restoreTrash', receipt.toJson());

  Future<void> writeClipboard(List<String> paths, {bool cut = false}) async {
    if (paths.isEmpty) throw ArgumentError('Select files to copy.');
    await channel.invokeMethod<void>('writeClipboard', {
      'paths': paths,
      'cut': cut,
    });
  }

  Future<NativeFileClipboard?> readClipboard() async {
    final result = await channel.invokeMapMethod<String, dynamic>(
      'readClipboard',
    );
    if (result == null) return null;
    final paths =
        (result['paths'] as List?)
            ?.whereType<String>()
            .where((p) => p.isNotEmpty)
            .toList() ??
        <String>[];
    return paths.isEmpty
        ? null
        : NativeFileClipboard(paths: paths, cut: result['cut'] == true);
  }
}
