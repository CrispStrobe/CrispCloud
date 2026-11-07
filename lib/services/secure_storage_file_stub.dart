import 'secure_storage_service.dart';

Future<SecureStorage> createEncryptedFileStorage({
  String? masterPassword,
}) async {
  throw UnsupportedError('Encrypted file storage is not available here.');
}
