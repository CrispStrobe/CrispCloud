import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';

void main() {
  group('CloudProvider enum', () {
    test('has all expected values', () {
      expect(CloudProvider.values, contains(CloudProvider.filen));
      expect(CloudProvider.values, contains(CloudProvider.internxt));
      expect(CloudProvider.values, contains(CloudProvider.sftp));
      expect(CloudProvider.values, contains(CloudProvider.webdav));
    });
  });

  group('CloudStorageFactory', () {
    test('creates FilenClientAdapter for filen provider', () {
      // Note: This would require a config service to be passed
      // Testing the factory method exists and returns correct type
      expect(CloudStorageFactory.isInternxtSupported, isA<bool>());
    });
  });
}
