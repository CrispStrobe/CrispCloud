import 'package:shared_preferences/shared_preferences.dart';

import 'file_collection_storage.dart';
import 'file_collection_storage_browser.dart';

FileCollectionStorage createArchivePublicationStorage() =>
    createFileCollectionStorage(preferences: SharedPreferences.getInstance);
