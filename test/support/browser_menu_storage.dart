import 'package:crisp_cloud/services/browser_menu_store.dart';

class MemoryBrowserMenuStorage implements BrowserMenuStorage {
  final values = <String, String>{};
  final writes = <String>[];
  String? failKey;
  Future<void> Function(String)? beforeWrite;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<bool> write(String key, String value) async {
    await beforeWrite?.call(key);
    writes.add(key);
    if (key == failKey) return false;
    values[key] = value;
    return true;
  }
}
