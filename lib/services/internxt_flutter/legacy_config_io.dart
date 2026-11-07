import 'dart:io';

import 'package:internxt_client/config_storage.dart';

// Reading the old backend directly avoids ConfigService's directory creation
// and chmod subprocess. The secure adapter never calls its init or write.
ConfigStorage legacyInternxtStorage() => FileConfigStorage();

String? legacyInternxtEnvironmentKey() =>
    Platform.environment['INTERNXT_CREDENTIALS_KEY'];
