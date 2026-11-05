import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/file_collection_store.dart';

final fileCollectionStoreProvider = ChangeNotifierProvider<FileCollectionStore>(
  (ref) => FileCollectionStore(),
);
