class MacosKeychainInfo {
  const MacosKeychainInfo({required this.path, required this.label});
  final String path;
  final String label;
}

class MacosKeychainService {
  static bool get isSupported => false;
  static Future<List<MacosKeychainInfo>> listKeychains() async => const [];
  static Future<void> selectKeychain(String path) async =>
      throw UnsupportedError('Keychain selection is macOS-only.');
  static Future<void> createKeychain(String path, String password) async =>
      throw UnsupportedError('Keychain creation is macOS-only.');
}
