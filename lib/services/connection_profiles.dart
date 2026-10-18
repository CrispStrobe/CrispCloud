import 'package:crisp_storage/crisp_storage.dart' as shared;
import 'secure_storage_service.dart';
export 'package:crisp_storage/crisp_storage.dart' show ConnectionProfile;

class ConnectionProfileService extends shared.ConnectionProfileStore {
  ConnectionProfileService(SecureStorage storage)
      : super(
            read: () => storage.read('connection_profiles'),
            write: (value) => storage.write('connection_profiles', value));
  // Retain read compatibility, while writes reject malformed stored data.
  @override
  Future<List<shared.ConnectionProfile>> getAll() async {
    try {
      return await super.getAll();
    } on FormatException {
      return [];
    } on TypeError {
      return [];
    }
  }
}
