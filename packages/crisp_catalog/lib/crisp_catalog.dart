/// Shared metadata catalogue API with explicit platform availability.
library;

export 'src/catalog_types.dart';
export 'src/catalog_stub.dart' if (dart.library.io) 'src/catalog_native.dart';
