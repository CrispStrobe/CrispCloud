import 'dart:io';

import 'file_collection_storage.dart';
import 'file_collection_storage_native.dart';

FileCollectionStorage createArchivePublicationStorage() =>
    Platform.environment.containsKey('FLUTTER_TEST')
    ? MemoryFileCollectionStorage()
    : NativeFileCollectionStorage();
