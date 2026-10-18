import 'secure_storage_service.dart';

class SmbConfigService {
  final SecureStorage storage;
  SmbConfigService(this.storage);
  Future<Map<String, String>?> readCredentials() =>
      storage.readMap('smb_credentials');
  Future<void> saveCredentials(Map<String, String> value) =>
      storage.writeMap('smb_credentials', value);
  Future<void> clearCredentials() => storage.delete('smb_credentials');
}
