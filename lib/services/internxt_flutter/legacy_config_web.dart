import 'package:internxt_client/config_storage.dart';

import 'shared_prefs_storage.dart';

ConfigStorage legacyInternxtStorage() => SharedPreferencesStorage();

String? legacyInternxtEnvironmentKey() => null;
