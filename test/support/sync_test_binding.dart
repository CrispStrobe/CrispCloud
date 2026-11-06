import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/installation_identity.dart';
import 'package:crisp_cloud/services/sync_database.dart';
import 'package:crisp_cloud/services/sync_source_binding.dart';

Future<void>? _initialization;

Future<SyncPair> bindTestPair(
  SyncDatabase database,
  SyncPair pair,
  CloudStorageClient client,
) async {
  await (_initialization ??= () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await InstallationIdentityService.instance.initialize();
  }());
  await database.rebindPair(
    pair.id,
    SyncSourceBinding.capture(
      localPath: pair.localPath,
      remotePath: pair.remotePath,
      client: client,
    ).encode(),
  );
  return database.getPair(pair.id);
}
